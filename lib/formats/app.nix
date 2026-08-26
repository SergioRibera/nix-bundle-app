{
  pkgs,
  lib,
  deps,
  services,
  signing,
  drv,
  format,
  meta,
  target,
  ...
}:

let
  appName = "${meta.name}.app";
  execName = meta.name;
  renderedServices = services.renderAllLaunchd meta.services;

  plist = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleName</key>            <string>${meta.name}</string>
      <key>CFBundleDisplayName</key>     <string>${meta.name}</string>
      <key>CFBundleExecutable</key>      <string>${execName}</string>
      <key>CFBundleIdentifier</key>      <string>${meta.bundleId}</string>
      <key>CFBundleVersion</key>         <string>${meta.version}</string>
      <key>CFBundleShortVersionString</key><string>${meta.version}</string>
      <key>CFBundlePackageType</key>     <string>APPL</string>
      <key>CFBundleSignature</key>       <string>${meta.bundleSignature}</string>
      <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
      <key>LSMinimumSystemVersion</key>  <string>${meta.minimumSystemVersion}</string>
      <key>NSHighResolutionCapable</key> <true/>
      <key>NSPrincipalClass</key>        <string>NSApplication</string>
      ${lib.optionalString (
        meta.macOsIcon != null
      ) "<key>CFBundleIconFile</key><string>AppIcon.icns</string>"}
    </dict>
    </plist>
  '';
in
pkgs.stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}.app";
  dontUnpack = true;
  nativeBuildInputs = with pkgs; [
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

        ${deps.patchDarwinBinaries "$appdir/Contents/MacOS"}

        ${lib.optionalString (meta.macOsIcon != null) ''
          cp "${meta.macOsIcon}" "$appdir/Contents/Resources/AppIcon.icns" || true
        ''}

        cat > "$appdir/Contents/Info.plist" <<'EOF'
    ${plist}
    EOF
        ${pkgs.gnused}/bin/sed -i 's/^    //' "$appdir/Contents/Info.plist"

        cat > "$appdir/Contents/PkgInfo" <<EOF
    APPL${meta.bundleSignature}
    EOF

        ${lib.optionalString (renderedServices != [ ]) ''
          # Launchd plists travel inside the bundle for reference. To actually
          # register them as system services you need a .pkg installer (which
          # copies them to /Library/LaunchDaemons) — see the `pkg` format.
          mkdir -p "$appdir/Contents/Resources/LaunchDaemons"
          ${lib.concatMapStringsSep "\n" (p: ''
            cp ${pkgs.writeText p.filename p.content} \
               "$appdir/Contents/Resources/LaunchDaemons/${p.filename}"
          '') renderedServices}
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
  };
}
