{
  stdenv,
  lib,
  utils,
  desktop,
  services,
  signing,
  drv,
  format,
  meta,
  target,
  dpkg,
  fakeroot,
  patchelf,
  file,
  gnugrep,
  rsync,
  coreutils,
  gawk,
  gnused,
  findutils,
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
  common = import ./_common-linux.nix {
    inherit
      lib
      deps
      desktop
      services
      ;
  };
  depList = meta.depends.deb or [ ];
  recommendsList = meta.depends.debRecommends or [ ];
  description = if meta.summary != "" then meta.summary else meta.name;
  esc = s: builtins.replaceStrings [ "/" "&" "\\" ] [ "\\/" "\\&" "\\\\" ] s;
  # dpkg-deb requires Package + filename to match [a-z0-9][-+.a-z0-9]*.
  # Sanitize `meta.name` for those two surfaces only; install paths
  # (`/opt/${meta.name}`) and other manifest text keep the upstream name
  # so cross-distro layouts stay aligned.
  pkgName = utils.debName meta.name;
in
stdenv.mkDerivation {
  name = "${pkgName}-${meta.version}-${meta.debArch}.deb";
  dontUnpack = true;
  nativeBuildInputs = [
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
      echo "Package: ${pkgName}"
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

    ${lib.optionalString (common.needsPostScripts meta) ''
      cat > "$stage/DEBIAN/postinst" <<'DEB_POSTINST_EOF'
      #!/bin/sh
      set -e
      ${common.postinstSnippet meta}
      exit 0
      DEB_POSTINST_EOF
      cat > "$stage/DEBIAN/prerm" <<'DEB_PRERM_EOF'
      #!/bin/sh
      set -e
      ${common.prermSnippet meta}
      exit 0
      DEB_PRERM_EOF
      cat > "$stage/DEBIAN/postrm" <<'DEB_POSTRM_EOF'
      #!/bin/sh
      set -e
      ${common.postrmSnippet meta}
      exit 0
      DEB_POSTRM_EOF
      chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm" "$stage/DEBIAN/postrm"
    ''}

    mkdir -p $out
    fakeroot dpkg-deb --build "$stage" "$out/${pkgName}_${meta.version}_${meta.debArch}.deb"

    ${signing.emitSignScript {
      inherit meta format;
      artifactGlob = "*.deb";
    }}
  '';

  passthru = {
    info = meta;
    inherit target format;
    outFile = "${pkgName}_${meta.version}_${meta.debArch}.deb";
  };
}
