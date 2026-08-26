{
  pkgs,
  deps,
  drv,
  format,
  meta,
  target,
  ...
}:

let
  isWindows = target.os == "windows";
  isDarwin = target.os == "darwin";
  outFile = "${meta.name}-${meta.version}-${target.arch}-${target.os}.zip";

  windowsPrep = ''
    stage=$PWD/${meta.name}-${meta.version}
    mkdir -p "$stage"
    ${deps.copyBinaries drv "$stage"}
    ${deps.copyWindowsDlls drv "$stage"}
    if [ -d "${drv}/share" ]; then
      ${pkgs.rsync}/bin/rsync -a --copy-links "${drv}/share/" "$stage/share/" || true
    fi
    ${deps.verifyStagedBinaries {
      binDir = "$stage";
      inherit target;
    }}
  '';

  darwinPrep = ''
    stage=$PWD/${meta.name}-${meta.version}
    mkdir -p "$stage/bin" "$stage/lib"
    ${deps.copyBinaries drv "$stage/bin"}
    ${deps.copyDarwinLibs drv "$stage/lib"}
    if [ -d "${drv}/share" ]; then
      ${pkgs.rsync}/bin/rsync -a --copy-links "${drv}/share/" "$stage/share/" || true
    fi
    ${deps.verifyStagedBinaries {
      binDir = "$stage/bin";
      inherit target;
    }}
  '';

  linuxPrep = ''
    stage=$PWD/${meta.name}-${meta.version}
    mkdir -p "$stage/bin" "$stage/lib"
    ${deps.copyBinaries drv "$stage/bin"}
    ${deps.copyLinuxLibs drv "$stage/lib"}
    if [ -d "${drv}/share" ]; then
      ${pkgs.rsync}/bin/rsync -a --copy-links "${drv}/share/" "$stage/share/" || true
    fi
    ${deps.verifyStagedBinaries {
      binDir = "$stage/bin";
      inherit target;
    }}
  '';

  prep =
    if isWindows then
      windowsPrep
    else if isDarwin then
      darwinPrep
    else
      linuxPrep;
in
pkgs.stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.zip
    pkgs.rsync
    pkgs.coreutils
    pkgs.patchelf
    pkgs.file
    pkgs.gnugrep
  ];

  buildCommand = ''
    ${prep}
    mkdir -p $out
    ( cd "$PWD" && ${pkgs.zip}/bin/zip -r -9 "$out/${outFile}" "${meta.name}-${meta.version}" )
  '';

  passthru = {
    info = meta;
    inherit target format outFile;
  };
}
