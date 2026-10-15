{
  stdenv,
  lib,
  utils,
  signing,
  format,
  meta,
  target,
  componentPkg,
  coreutils,
  gnused,
  xar,
  ...
}:

let
  innerFile = "${meta.name}-${meta.version}-${utils.darwinArch target.arch}.pkg";
  outFile = "${meta.name}-${meta.version}-${utils.darwinArch target.arch}-install.pkg";

  esc = utils.xmlEscape;
  pb = meta.productbuild;

  title = if pb.title != null then pb.title else meta.name;
  organization =
    if pb.organization != null then
      pb.organization
    else
      let
        parts = lib.splitString "." meta.bundleId;
        n = builtins.length parts;
      in
      if n >= 2 then builtins.elemAt parts (n - 2) else meta.bundleId;

  resourceRefs = {
    welcome = pb.welcome;
    license = pb.license;
    readme = pb.readme;
    conclusion = pb.conclusion;
    background = pb.background;
  };

  filenameFor =
    key: path:
    let
      base = builtins.baseNameOf (toString path);
      ext = lib.toLower (lib.lists.last (lib.splitString "." base));
    in
    "${key}.${ext}";

  distributionXml = ''
    <?xml version="1.0" encoding="utf-8"?>
    <installer-gui-script minSpecVersion="1">
      <title>${esc title}</title>
      <organization>${esc organization}</organization>
      ${lib.optionalString (
        resourceRefs.welcome != null
      ) ''<welcome file="${esc (filenameFor "welcome" resourceRefs.welcome)}" mime-type="text/plain"/>''}
      ${lib.optionalString (
        resourceRefs.license != null
      ) ''<license file="${esc (filenameFor "license" resourceRefs.license)}" mime-type="text/plain"/>''}
      ${lib.optionalString (
        resourceRefs.readme != null
      ) ''<readme file="${esc (filenameFor "readme" resourceRefs.readme)}" mime-type="text/plain"/>''}
      ${lib.optionalString (resourceRefs.conclusion != null)
        ''<conclusion file="${esc (filenameFor "conclusion" resourceRefs.conclusion)}" mime-type="text/plain"/>''
      }
      ${lib.optionalString (resourceRefs.background != null)
        ''<background file="${esc (filenameFor "background" resourceRefs.background)}" alignment="topleft" scaling="none"/>''
      }
      <options customize="never" require-scripts="false" allow-external-scripts="no"/>
      <choices-outline>
        <line choice="default">
          <line choice="${esc meta.bundleId}"/>
        </line>
      </choices-outline>
      <choice id="default"/>
      <choice id="${esc meta.bundleId}" visible="false">
        <pkg-ref id="${esc meta.bundleId}"/>
      </choice>
      <pkg-ref id="${esc meta.bundleId}" version="${esc meta.version}" onConclusion="none">${esc innerFile}</pkg-ref>
    </installer-gui-script>
  '';

  copyResource =
    key:
    let
      path = resourceRefs.${key};
    in
    lib.optionalString (path != null) ''
      cp "${path}" "Resources/${filenameFor key path}"
    '';
in
stdenv.mkDerivation (
  {
    name = outFile;
    dontUnpack = true;
    nativeBuildInputs = [
      coreutils
      gnused
      xar
    ];
  }
  // lib.optionalAttrs stdenv.isDarwin {
    __impureHostDeps = [
      "/usr/bin/productbuild"
      "/usr/bin/pkgbuild"
      "/System/Library/PrivateFrameworks/PackageKit.framework"
      "/System/Library/Frameworks/CoreFoundation.framework"
      "/System/Library/Frameworks/Security.framework"
    ];
    preferLocalBuild = true;
    allowSubstitutes = false;
  }
  // {

    buildCommand =
      let
        stageInner = ''
          work=$PWD/dist
          mkdir -p "$work/Resources"
          cp ${componentPkg}/${innerFile} "$work/${innerFile}"
          chmod u+w "$work/${innerFile}"

          cd "$work"
          ${copyResource "welcome"}
          ${copyResource "license"}
          ${copyResource "readme"}
          ${copyResource "conclusion"}
          ${copyResource "background"}

          cat > Distribution <<'DISTRIBUTION_EOF'
          ${distributionXml}
          DISTRIBUTION_EOF
          chmod u+w Distribution
          ${gnused}/bin/sed -i 's/^    //' Distribution
        '';

        # Hand-assembled distribution xar (linux cross-build path). Real
        # productbuild sets a bunch of xar metadata + gzip compression that
        # Apple's `installer` inspects — hitting the system tool below when
        # we build on macOS avoids "Installer can't locate the data" errors.
        linuxBuild = ''
          ${stageInner}
          mkdir -p $out
          xar --compression none -cf "$out/${outFile}" \
            Distribution Resources ${innerFile}
        '';

        darwinBuild = ''
          ${stageInner}
          mkdir -p $out
          if [ -x /usr/bin/productbuild ]; then
            /usr/bin/productbuild \
              --distribution Distribution \
              --resources Resources \
              --package-path . \
              "$out/${outFile}"
          else
            xar --compression none -cf "$out/${outFile}" \
              Distribution Resources ${innerFile}
          fi
        '';
      in
      (if stdenv.isDarwin then darwinBuild else linuxBuild)
      + signing.emitSignScript {
        inherit meta format;
        artifactGlob = "*-install.pkg";
      };

    passthru = {
      info = meta;
      inherit
        target
        format
        outFile
        componentPkg
        ;
    };
  }
)
