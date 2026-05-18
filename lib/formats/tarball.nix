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
  ...
}:

let
  isLinux = target.os == "linux";
  isDarwin = target.os == "darwin";
  isWindows = target.os == "windows";

  common = import ./_common-linux.nix {
    inherit
      pkgs
      lib
      deps
      utils
      desktop
      services
      ;
  };

  ext = format;
  compressor =
    {
      "tar.gz" = "${pkgs.gzip}/bin/gzip -n -9";
      "tar.xz" = "${pkgs.xz}/bin/xz -9 -T0";
      "tar.zst" = "${pkgs.zstd}/bin/zstd -19 -T0";
    }
    .${ext} or "${pkgs.gzip}/bin/gzip -n -9";

  outFile = "${meta.name}-${meta.version}-${target.arch}-${target.os}.${ext}";

  linuxPrep = ''
    stage=$PWD/${meta.name}-${meta.version}
    mkdir -p "$stage"
    ${common.stageLinux {
      inherit drv meta target;
      stage = "$stage";
    }}
  '';

  darwinPrep = ''
    stage=$PWD/${meta.name}-${meta.version}
    mkdir -p "$stage/bin" "$stage/lib" "$stage/share"
    ${deps.copyBinaries drv "$stage/bin"}
    ${deps.copyDarwinLibs drv "$stage/lib"}
    ${deps.copyResources drv "$stage/share"}
  '';

  windowsPrep = ''
    stage=$PWD/${meta.name}-${meta.version}
    mkdir -p "$stage"
    ${deps.copyBinaries drv "$stage"}
    ${deps.copyWindowsDlls drv "$stage"}
    if [ -d "${drv}/share" ]; then
      ${pkgs.rsync}/bin/rsync -a --copy-links "${drv}/share/" "$stage/share/" || true
    fi
  '';

  prep =
    if isLinux then
      linuxPrep
    else if isDarwin then
      darwinPrep
    else if isWindows then
      windowsPrep
    else
      darwinPrep;

  rootDir = "${meta.name}-${meta.version}";

in
pkgs.stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-${target.arch}-${target.os}.${ext}";
  dontUnpack = true;
  nativeBuildInputs = with pkgs; [
    gnutar
    gzip
    xz
    zstd
    patchelf
    file
    gnugrep
    rsync
    coreutils
  ];

  buildCommand = ''
    ${prep}
    mkdir -p $out
    ( cd "$PWD" && ${pkgs.gnutar}/bin/tar --owner=0 --group=0 --sort=name -cf - "${rootDir}" \
      | ${compressor} > "$out/${outFile}" )
  '';

  passthru = {
    info = meta;
    inherit target format outFile;
  };
}
