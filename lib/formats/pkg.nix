{
  pkgs,
  lib,
  deps,
  utils,
  desktop,
  services,
  drv,
  format,
  meta,
  target,
}:

let
  appBundle = import ./app.nix {
    inherit
      pkgs
      lib
      deps
      utils
      desktop
      services
      drv
      format
      meta
      target
      ;
  };
  outFile = "${meta.name}-${meta.version}-${utils.darwinArch target.arch}.pkg";

  renderedServices = services.renderAllLaunchd meta.services;
  hasServices = renderedServices != [ ];

  # When services are present we need files at two roots (/Applications and
  # /Library/LaunchDaemons), so we set install-location="/" and lay them out
  # under those subpaths in the Payload.
  installLocation = if hasServices then "/" else "/Applications";

  pkgInfoXML = ''
    <?xml version="1.0" encoding="utf-8"?>
    <pkg-info format-version="2"
              identifier="${meta.bundleId}"
              version="${meta.version}"
              install-location="${installLocation}"
              auth="root">
      <payload installKBytes="@INSTKB@" numberOfFiles="@NFILES@"/>
      <bundle-version>
        <bundle id="${meta.bundleId}"
                CFBundleIdentifier="${meta.bundleId}"
                path="${
                  if hasServices then "./Applications/${meta.name}.app" else "./${meta.name}.app"
                }"
                CFBundleVersion="${meta.version}"
                CFBundleShortVersionString="${meta.version}"/>
      </bundle-version>
      <upgrade-bundle>
        <bundle id="${meta.bundleId}"/>
      </upgrade-bundle>
      ${lib.optionalString hasServices ''<scripts><postinstall file="./postinstall"/></scripts>''}
    </pkg-info>
  '';

  postinstallText = lib.optionalString hasServices ''
    #!/bin/sh
    # nix-bundle-app: load launchd services
    set -e
    ${lib.concatMapStringsSep "\n" (p: ''
      /bin/launchctl load -w "/Library/LaunchDaemons/${p.filename}" 2>/dev/null || true
    '') renderedServices}
    exit 0
  '';
in
pkgs.stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.gnused
    pkgs.gzip
    pkgs.cpio
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [
    pkgs.bomutils
    pkgs.xar
  ];

  buildCommand =
    let
      stageRoot = ''
        work=$PWD/build
        root=$work/root
        mkdir -p "$root"
        ${
          if hasServices then
            ''
              mkdir -p "$root/Applications" "$root/Library/LaunchDaemons"
              cp -r ${appBundle}/${meta.name}.app "$root/Applications/"
              ${lib.concatMapStringsSep "\n" (p: ''
                cp ${pkgs.writeText p.filename p.content} \
                   "$root/Library/LaunchDaemons/${p.filename}"
                chmod 644 "$root/Library/LaunchDaemons/${p.filename}"
              '') renderedServices}
            ''
          else
            ''
              cp -r ${appBundle}/${meta.name}.app "$root/"
            ''
        }
        chmod -R u+w "$root"
      '';

      linuxBuild = ''
        ${stageRoot}
        flat=$work/flat
        mkdir -p "$flat"

        ( cd "$root" && find . -print | cpio -o --format=odc 2>/dev/null ) \
          | gzip -9 > "$flat/Payload"

        ( ulimit -c 0 && mkbom "$root" "$flat/Bom" 2>/dev/null ) || : > "$flat/Bom"

        nfiles=$( find "$root" | wc -l )
        instkb=$( du -sk "$root" | cut -f1 )

        cp ${pkgs.writeText "PackageInfo" pkgInfoXML} "$flat/PackageInfo.tpl"
        ${pkgs.gnused}/bin/sed -i 's/^    //' "$flat/PackageInfo.tpl"
        ${pkgs.gnused}/bin/sed \
          -e "s/@INSTKB@/$instkb/" \
          -e "s/@NFILES@/$nfiles/" \
          "$flat/PackageInfo.tpl" > "$flat/PackageInfo"
        rm "$flat/PackageInfo.tpl"

        ${lib.optionalString hasServices ''
          mkdir -p "$work/scripts"
          cp ${pkgs.writeText "postinstall" postinstallText} "$work/scripts/postinstall"
          chmod 755 "$work/scripts/postinstall"
          ( cd "$work/scripts" && find . -print | cpio -o --format=odc 2>/dev/null ) \
            | gzip -9 > "$flat/Scripts"
        ''}

        mkdir -p $out
        ( cd "$flat" && xar --compression none -cf "$out/${outFile}" \
            PackageInfo Bom Payload ${lib.optionalString hasServices "Scripts"} )
      '';

      darwinBuild = ''
        ${stageRoot}
        mkdir -p $out
        if command -v pkgbuild >/dev/null 2>&1; then
          ${lib.optionalString hasServices ''
            mkdir -p scripts
            cp ${pkgs.writeText "postinstall" postinstallText} scripts/postinstall
            chmod 755 scripts/postinstall
          ''}
          pkgbuild \
            --root "$root" \
            --identifier "${meta.bundleId}" \
            --version "${meta.version}" \
            --install-location ${installLocation} \
            ${lib.optionalString hasServices "--scripts scripts"} \
            "$out/${outFile}"
        else
          echo "pkgbuild not on PATH; falling back to manual flat pkg" >&2
          ${pkgs.gnutar}/bin/tar -czf "$out/${outFile}" -C "$root" .
        fi
      '';
    in
    if pkgs.stdenv.isDarwin then darwinBuild else linuxBuild;

  passthru = {
    info = meta;
    inherit target format appBundle;
  };
}
