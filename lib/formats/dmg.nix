{
  stdenv,
  utils,
  signing,
  format,
  meta,
  target,
  appBundle,
  coreutils,
  gnused,
  gnutar,
  xorriso,
  ...
}:

let
  outFile = "${meta.name}-${meta.version}-${utils.darwinArch target.arch}.dmg";
in
stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = [
    coreutils
    gnused
    xorriso
  ];

  buildCommand =
    let
      stage = ''
        stage=$PWD/dmg-root
        mkdir -p "$stage"
        cp -r ${appBundle}/${meta.name}.app "$stage/"
        chmod -R u+w "$stage"
      '';

      # Real UDIF DMG. `hdiutil` is an unsandboxed macOS system tool, never
      # on the nix build PATH, so this only ever runs outside the sandbox.
      hdiutilBuild = ''
        hdiutil create -volname "${meta.name}" -srcfolder "$stage" \
          -ov -format UDZO "$out/${outFile}"
      '';

      # HFS+ hybrid ISO — Finder mounts it transparently, works everywhere.
      xorrisoBuild = ''
        xorrisofs \
          -hfsplus \
          -V "${meta.name}" \
          -appid "${meta.bundleId}" \
          -o "$out/${outFile}" \
          "$stage" 2>/dev/null \
        || ${gnutar}/bin/tar -czf "$out/${outFile}" -C "$stage" .
      '';
    in
    ''
      ${stage}
      mkdir -p $out
      if command -v hdiutil >/dev/null 2>&1; then
        ${hdiutilBuild}
      else
        ${xorrisoBuild}
      fi
    ''
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
