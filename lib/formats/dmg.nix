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
  outFile = "${meta.name}-${meta.version}-${utils.darwinArch target.arch}.dmg";
in
pkgs.stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  # Linux: emit an HFS+ hybrid ISO that Finder mounts transparently.
  # darwin: defer to hdiutil for a real UDIF DMG.
  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.gnused
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.xorriso ];

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
        if command -v hdiutil >/dev/null 2>&1; then
          hdiutil create -volname "${meta.name}" -srcfolder "$stage" \
            -ov -format UDZO "$out/${outFile}"
        else
          ${pkgs.gnutar}/bin/tar -czf "$out/${outFile}" -C "$stage" .
        fi
      '';
    in
    if pkgs.stdenv.isDarwin then darwinBuild else linuxBuild;

  passthru = {
    info = meta;
    inherit target format appBundle;
  };
}
