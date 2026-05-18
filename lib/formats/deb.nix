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
  depList = meta.depends.deb or [ ];
  recommendsList = meta.depends.debRecommends or [ ];
  description = if meta.summary != "" then meta.summary else meta.name;
  esc = s: builtins.replaceStrings [ "/" "&" "\\" ] [ "\\/" "\\&" "\\\\" ] s;
in
pkgs.stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-${meta.debArch}.deb";
  dontUnpack = true;
  nativeBuildInputs = with pkgs; [
    dpkg
    fakeroot
    patchelf
    file
    gnugrep
    rsync
    coreutils
    gawk
    gnused
    findutils
  ];

  buildCommand = ''
    stage=$PWD/stage
    mkdir -p "$stage/DEBIAN"

    ${common.stageLinux {
      inherit drv meta target;
      stage = "$stage";
    }}

    ${lib.optionalString meta.autoDepends (
      deps.discoverLinuxDepsSnippet {
        kind = "deb";
        scanDirs = [
          "$stage/opt/${meta.name}/bin"
          "$stage/opt/${meta.name}/lib"
        ];
        userDeps = depList;
        outFile = "deb-depends.csv";
      }
    )}

    {
      echo "Package: ${meta.name}"
      echo "Version: ${meta.version}"
      echo "Architecture: ${meta.debArch}"
      echo "Maintainer: ${meta.maintainer}"
      echo "Section: ${meta.section}"
      echo "Priority: ${meta.priority}"
      ${lib.optionalString (meta.homepage != "") ''echo "Homepage: ${meta.homepage}"''}
      ${
        if meta.autoDepends then
          ''
            if [ -s deb-depends.csv ]; then
              echo "Depends: $(cat deb-depends.csv)"
            fi
          ''
        else
          lib.optionalString (depList != [ ]) ''echo "Depends: ${lib.concatStringsSep ", " depList}"''
      }
      ${lib.optionalString (
        recommendsList != [ ]
      ) ''echo "Recommends: ${lib.concatStringsSep ", " recommendsList}"''}
      echo "Description: ${esc description}"
    } > "$stage/DEBIAN/control"
    chmod 644 "$stage/DEBIAN/control"

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

    ${signing.emitSignScript {
      inherit meta format;
      artifactGlob = "*.deb";
    }}
  '';

  passthru = {
    info = meta;
    inherit target format;
  };
}
