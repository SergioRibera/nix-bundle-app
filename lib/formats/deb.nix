{ pkgs, lib, deps, utils, desktop, services, drv, format, meta, target }:

let
  common = import ./_common-linux.nix { inherit pkgs lib deps utils desktop services; };
  depList = meta.depends.deb or [];
  recommendsList = meta.depends.debRecommends or [];

  controlLines = builtins.filter (l: l != "") [
    "Package: ${meta.name}"
    "Version: ${meta.version}"
    "Architecture: ${meta.debArch}"
    "Maintainer: ${meta.maintainer}"
    "Section: ${meta.section}"
    "Priority: ${meta.priority}"
    (lib.optionalString (meta.homepage != "") "Homepage: ${meta.homepage}")
    (lib.optionalString (depList != []) "Depends: ${lib.concatStringsSep ", " depList}")
    (lib.optionalString (recommendsList != []) "Recommends: ${lib.concatStringsSep ", " recommendsList}")
    "Description: ${if meta.summary != "" then meta.summary else meta.name}"
  ];
  controlBody = lib.concatStringsSep "\n" controlLines + "\n";
in
pkgs.stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-${meta.debArch}.deb";
  dontUnpack = true;
  nativeBuildInputs = with pkgs; [ dpkg fakeroot patchelf file gnugrep rsync coreutils ];

  buildCommand = ''
    stage=$PWD/stage
    mkdir -p "$stage/DEBIAN"

    ${common.stageLinux { inherit drv meta target; stage = "$stage"; }}

    ${pkgs.coreutils}/bin/install -m 644 ${pkgs.writeText "control" controlBody} "$stage/DEBIAN/control"

    ${lib.optionalString (common.hasServices meta) ''
      cp ${pkgs.writeText "postinst" ''
        #!/bin/sh
        set -e
        ${common.postinstSnippet meta}
        exit 0
      ''} "$stage/DEBIAN/postinst"
      cp ${pkgs.writeText "prerm" ''
        #!/bin/sh
        set -e
        ${common.prermSnippet meta}
        exit 0
      ''} "$stage/DEBIAN/prerm"
      cp ${pkgs.writeText "postrm" ''
        #!/bin/sh
        set -e
        ${common.postrmSnippet meta}
        exit 0
      ''} "$stage/DEBIAN/postrm"
      chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm" "$stage/DEBIAN/postrm"
    ''}

    mkdir -p $out
    fakeroot dpkg-deb --build "$stage" "$out/${meta.name}_${meta.version}_${meta.debArch}.deb"
  '';

  passthru = { info = meta; inherit target format; };
}
