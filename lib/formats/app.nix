{
  stdenv,
  lib,
  utils,
  services,
  signing,
  drv,
  format,
  meta,
  target,
  file,
  gnugrep,
  gawk,
  rsync,
  coreutils,
  gnused,
  patchelf,
  closureInfo,
  ...
}:

let
  deps = import ../deps.nix {
    inherit
      lib
      utils
      closureInfo
      coreutils
      file
      gawk
      gnugrep
      gnused
      patchelf
      rsync
      ;
  };
  appName = meta.appBundleName;
  # An explicit `.icns` wins over the one rendered from `info.icon`.
  mac = meta.macos;
  icns =
    if mac.icns != null then
      mac.icns
    else if meta.iconSet != null then
      "${meta.iconSet}/icon.icns"
    else
      null;
  execName = meta.name;
  renderedServices = services.renderAllLaunchd meta.services;
  fileAssociations = import ../file-associations.nix { inherit lib; };
  urlSchemes = import ../url-schemes.nix { inherit lib; };

  localNetwork = meta.permissions.network.local;

  # Generated keys first, `macos.infoPlist` last: an explicit key always wins.
  plistKeys = {
    CFBundleName = meta.displayName;
    CFBundleDisplayName = meta.displayName;
    CFBundleExecutable = execName;
    CFBundleIdentifier = meta.bundleId;
    CFBundleVersion = if mac.buildVersion != null then mac.buildVersion else meta.numericVersion;
    CFBundleShortVersionString = meta.numericVersion;
    CFBundlePackageType = "APPL";
    CFBundleSignature = mac.bundleSignature;
    CFBundleInfoDictionaryVersion = "6.0";
    LSMinimumSystemVersion = mac.minimumSystemVersion;
    NSHighResolutionCapable = true;
    NSPrincipalClass = "NSApplication";
  }
  // lib.optionalAttrs (icns != null) { CFBundleIconFile = "AppIcon.icns"; }
  // lib.optionalAttrs (mac.category != null) { LSApplicationCategoryType = mac.category; }
  // lib.optionalAttrs (mac.copyright != null) { NSHumanReadableCopyright = mac.copyright; }
  // lib.optionalAttrs (localNetwork != null) {
    NSLocalNetworkUsageDescription = localNetwork.reason;
  }
  // fileAssociations.plistKeys meta
  // urlSchemes.plistKeys meta
  // mac.infoPlist;

  plist = lib.generators.toPlist { escape = true; } plistKeys;
in
stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}.app";
  dontUnpack = true;
  nativeBuildInputs = [
    file
    gnugrep
    rsync
    coreutils
  ];

  buildCommand = ''
        appdir="$out/${appName}"
        mkdir -p "$appdir/Contents/MacOS"
        mkdir -p "$appdir/Contents/Resources"
        mkdir -p "$appdir/Contents/Frameworks"

        ${deps.copyBinaries drv "$appdir/Contents/MacOS"}
        ${deps.copyDarwinLibs drv "$appdir/Contents/Frameworks"}
        ${deps.copyResources drv "$appdir/Contents/Resources/share"}

        ${deps.verifyStagedBinaries {
          binDir = "$appdir/Contents/MacOS";
          inherit target;
        }}

        ${deps.patchDarwinLibs "$appdir/Contents/Frameworks"}
        ${deps.patchDarwinBinaries "$appdir/Contents/MacOS"}

        ${lib.optionalString (icns != null) ''
          cp "${icns}" "$appdir/Contents/Resources/AppIcon.icns" || true
        ''}

        cat > "$appdir/Contents/Info.plist" <<'EOF'
    ${plist}
    EOF
        ${gnused}/bin/sed -i 's/^    //' "$appdir/Contents/Info.plist"

        cat > "$appdir/Contents/PkgInfo" <<EOF
    APPL${mac.bundleSignature}
    EOF

        ${lib.optionalString (renderedServices != [ ]) ''
          # Launchd plists travel inside the bundle for reference. To actually
          # register them as system services you need a .pkg installer (which
          # copies them to /Library/LaunchDaemons) — see the `pkg` format.
          mkdir -p "$appdir/Contents/Resources/LaunchDaemons"
          ${lib.concatStrings (
            lib.imap1 (i: p: ''
              cat > "$appdir/Contents/Resources/LaunchDaemons/${p.filename}" <<'LAUNCHD_${toString i}_EOF'
              ${p.content}
              LAUNCHD_${toString i}_EOF
            '') renderedServices
          )}
        ''}

        ${signing.emitSignScript {
          inherit meta format;
          artifactGlob = "*.app";
        }}
  '';

  passthru = {
    info = meta;
    inherit target format;
    outFile = appName;
    launchdPlists = renderedServices;
    infoPlist = plist;
  };
}
