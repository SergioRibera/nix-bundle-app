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
  appBundle = import ./app.nix {
    inherit
      pkgs
      lib
      deps
      utils
      desktop
      services
      signing
      drv
      format
      meta
      target
      ;
  };
  outFile = "${meta.name}-${meta.version}-${utils.darwinArch target.arch}.dmg";
in
pkgs.stdenv.mkDerivation (
  {
    name = outFile;
    dontUnpack = true;
    # Linux: emit an HFS+ hybrid ISO that Finder mounts transparently.
    # darwin: defer to hdiutil for a real UDIF DMG.
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnused
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.xorriso ];
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    # hdiutil lives outside the nix store and depends on system frameworks —
    # let nix expose the host binary + its runtime deps into the sandbox and
    # skip substitution (the output is host-dependent).
    __impureHostDeps = [
      "/usr/bin/hdiutil"
      "/System/Library/PrivateFrameworks/DiskImages.framework"
      "/System/Library/Frameworks/CoreServices.framework"
      "/System/Library/Frameworks/CoreFoundation.framework"
      "/System/Library/Frameworks/IOKit.framework"
    ];
    preferLocalBuild = true;
    allowSubstitutes = false;
  }
  // {

    buildCommand =
      let
        linuxBuild = ''
          stage=$PWD/dmg-root
          mkdir -p "$stage"
          cp -r ${appBundle}/${meta.name}.app "$stage/"
          chmod -R u+w "$stage"

          mkdir -p $out
          xorrisofs \
            -hfsplus \
            -V "${meta.name}" \
            -app-id "${meta.bundleId}" \
            -o "$out/${outFile}" \
            "$stage" 2>/dev/null \
          || ${pkgs.gnutar}/bin/tar -czf "$out/${outFile}" -C "$stage" .
        '';

        darwinBuild = ''
          stage=$PWD/dmg-root
          mkdir -p "$stage"
          cp -r ${appBundle}/${meta.name}.app "$stage/"
          chmod -R u+w "$stage"
          mkdir -p $out
          # hdiutil ships with macOS, never through nixpkgs — hit the absolute
          # path so a partial PATH inside the nix sandbox doesn't push us into
          # the tar fallback (which produces a `.dmg` that Finder rejects with
          # "image not recognized").
          if [ -x /usr/bin/hdiutil ]; then
            /usr/bin/hdiutil create -volname "${meta.name}" -srcfolder "$stage" \
              -ov -format UDZO "$out/${outFile}"
          elif command -v hdiutil >/dev/null 2>&1; then
            hdiutil create -volname "${meta.name}" -srcfolder "$stage" \
              -ov -format UDZO "$out/${outFile}"
          else
            echo "hdiutil not available; falling back to tar (NOT a real DMG)." >&2
            ${pkgs.gnutar}/bin/tar -czf "$out/${outFile}" -C "$stage" .
          fi
        '';
      in
      (if pkgs.stdenv.isDarwin then darwinBuild else linuxBuild)
      + signing.emitSignScript {
        inherit meta format;
        artifactGlob = "*.dmg";
      };

    passthru = {
      info = meta;
      inherit
        target
        format
        outFile
        appBundle
        ;
    };
  }
)
