{
  stdenv,
  lib,
  utils,
  desktop,
  services,
  drv,
  format,
  meta,
  target,
  gnutar,
  gzip,
  xz,
  zstd,
  patchelf,
  file,
  gnugrep,
  gawk,
  gnused,
  rsync,
  coreutils,
  closureInfo,
  ...
}:

let
  isLinux = target.os == "linux";
  isDarwin = target.os == "darwin";
  isWindows = target.os == "windows";

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
  common = import ./_common-linux.nix {
    inherit
      lib
      deps
      desktop
      services
      ;
  };

  ext = format;
  compressor =
    {
      "tar.gz" = "${gzip}/bin/gzip -n -9";
      "tar.xz" = "${xz}/bin/xz -9 -T0";
      "tar.zst" = "${zstd}/bin/zstd -19 -T0";
    }
    .${ext} or "${gzip}/bin/gzip -n -9";

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
    ${deps.verifyStagedBinaries {
      binDir = "$stage/bin";
      inherit target;
    }}
  '';

  windowsPrep = ''
    stage=$PWD/${meta.name}-${meta.version}
    mkdir -p "$stage"
    ${deps.copyBinaries drv "$stage"}
    ${deps.copyWindowsDlls drv "$stage"}
    if [ -d "${drv}/share" ]; then
      ${rsync}/bin/rsync -a --copy-links "${drv}/share/" "$stage/share/" || true
    fi
    ${deps.verifyStagedBinaries {
      binDir = "$stage";
      inherit target;
    }}
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
stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-${target.arch}-${target.os}.${ext}";
  dontUnpack = true;
  nativeBuildInputs = [
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
    ( cd "$PWD" && ${gnutar}/bin/tar --owner=0 --group=0 --sort=name -cf - "${rootDir}" \
      | ${compressor} > "$out/${outFile}" )
  '';

  passthru = {
    info = meta;
    inherit target format outFile;
  };
}
