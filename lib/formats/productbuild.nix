{
  pkgs,
  lib,
  deps,
  utils,
  desktop,
  services,
  signing,
  drv,
  format,
  meta,
  target,
}:

let
  inner = import ./pkg.nix {
    inherit
      pkgs
      lib
      deps
      utils
      desktop
      services
      signing
      drv
      target
      ;
    format = "pkg";
    meta = meta // {
      format = "pkg";
    };
  };

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
      if n >= 2 then lib.concatStringsSep "." (lib.sublist 0 (n - 1) parts) else meta.bundleId;

  resourceRefs = {
    welcome = pb.welcome;
    license = pb.license;
    readme = pb.readme;
    conclusion = pb.conclusion;
    background = pb.background;
  };
  # Strip the store hash, keep the trailing extension. The Resources/ filename
  # ends up as `welcome.html` instead of `welcome-<hash>-welcome.html`.
  extensionOf =
    path:
    let
      m = builtins.match ".*(\\.[^./]+)$" (baseNameOf (toString path));
    in
    if m == null then "" else builtins.head m;
  filenameFor = key: path: "${key}${extensionOf path}";

  screenRef =
    tag: key:
    let
      path = resourceRefs.${key};
    in
    if path == null then "" else "<${tag} file=\"${esc (filenameFor key path)}\"/>";

  bgRef =
    if pb.background == null then
      ""
    else
      "<background file=\"${esc (filenameFor "background" pb.background)}\" alignment=\"center\" scaling=\"proportional\"/>";

  customize = if pb.allowCustomize then "always" else "never";

  distributionXml = ''
    <?xml version="1.0" encoding="utf-8"?>
    <installer-gui-script minSpecVersion="2">
      <title>${esc title}</title>
      <organization>${esc organization}</organization>
      <options customize="${customize}" require-scripts="false" rootVolumeOnly="true"/>
      ${screenRef "welcome" "welcome"}
      ${screenRef "license" "license"}
      ${screenRef "readme" "readme"}
      ${screenRef "conclusion" "conclusion"}
      ${bgRef}
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
pkgs.stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.gnused
    pkgs.xar
  ];

  buildCommand =
    let
      stageInner = ''
        work=$PWD/dist
        mkdir -p "$work/Resources"
        cp ${inner}/${innerFile} "$work/${innerFile}"
        chmod u+w "$work/${innerFile}"

        cd "$work"
        ${copyResource "welcome"}
        ${copyResource "license"}
        ${copyResource "readme"}
        ${copyResource "conclusion"}
        ${copyResource "background"}

        cp ${pkgs.writeText "Distribution" distributionXml} Distribution
        chmod u+w Distribution
        ${pkgs.gnused}/bin/sed -i 's/^    //' Distribution
      '';

      # Distribution xml + Resources/ + component pkg side by side is what
      # the Installer.app expects; `productbuild` assembles that into an
      # outer xar for us, or we hand-assemble the same thing with `xar`.
      productbuildBuild = ''
        productbuild \
          --distribution Distribution \
          --resources Resources \
          --package-path . \
          "$out/${outFile}"
      '';

      xarBuild = ''
        xar --compression none -cf "$out/${outFile}" \
          Distribution Resources ${innerFile}
      '';
    in
    ''
      ${stageInner}
      mkdir -p $out
      if command -v productbuild >/dev/null 2>&1; then
        ${productbuildBuild}
      else
        ${xarBuild}
      fi
    ''
    + signing.emitSignScript {
      inherit meta format;
      artifactGlob = "*-install.pkg";
    };

  passthru = {
    info = meta;
    inherit target format outFile;
    componentPkg = inner;
  };
}
