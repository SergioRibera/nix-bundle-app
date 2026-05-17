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
  reqs = meta.depends.rpm or [ ];
  recs = meta.depends.rpmRecommends or [ ];
  group = meta.depends.rpmGroup or "Applications/System";

  hasEntries = meta.desktopEntries != [ ];
  hasIcons = lib.any (e: e.iconPath != null) meta.desktopEntries;
in
pkgs.stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-1.${meta.rpmArch}.rpm";
  dontUnpack = true;
  nativeBuildInputs = with pkgs; [
    rpm
    patchelf
    file
    gnugrep
    rsync
    coreutils
    gnused
  ];

  buildCommand = ''
    export HOME=$(mktemp -d)
    topdir=$HOME/rpmbuild
    buildroot=$topdir/BUILDROOT/${meta.name}-${meta.version}-1.${meta.rpmArch}
    export RPM_DB_PATH=$HOME/.rpmdb
    mkdir -p "$RPM_DB_PATH"
    mkdir -p "$topdir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    mkdir -p "$buildroot"

    rpm --initdb --dbpath "$RPM_DB_PATH"

    ${common.stageLinux {
      inherit drv meta target;
      stage = "$buildroot";
    }}

    # rpmbuild's %clean wants to rm the buildroot; nix store copies come
    # in read-only. Make everything writable so cleanup succeeds.
    chmod -R u+w "$buildroot"

    cat > "$topdir/SPECS/${meta.name}.spec" <<EOF
    Name: ${meta.name}
    Version: ${meta.version}
    Release: 1%{?dist}
    Summary: ${meta.summary}
    License: ${meta.license}
    ${lib.optionalString (meta.homepage != "") "URL: ${meta.homepage}"}
    Group: ${group}
    BuildArch: ${meta.rpmArch}
    AutoReqProv: no
    ${lib.optionalString (reqs != [ ]) "Requires: ${lib.concatStringsSep ", " reqs}"}
    ${lib.optionalString (recs != [ ]) "Recommends: ${lib.concatStringsSep ", " recs}"}

    %description
    ${meta.longDescription}

    %files
    %attr(0755, root, root) /opt/${meta.name}
    /usr/bin/*
    ${lib.optionalString (common.hasServices meta) "%attr(0644, root, root) /lib/systemd/system/*"}
    ${lib.optionalString hasEntries "/usr/share/applications/*"}
    ${lib.optionalString hasIcons "/usr/share/icons/hicolor/512x512/apps/*"}

    %post
    ${common.postinstSnippet meta}

    %preun
    ${common.prermSnippet meta}

    %postun
    ${common.postrmSnippet meta}

    %clean
    rm -rf \$RPM_BUILD_ROOT
    EOF

    ${pkgs.gnused}/bin/sed -i 's/^    //' "$topdir/SPECS/${meta.name}.spec"

    mkdir -p "$HOME/tmp"

    rpmbuild \
      --define "_topdir $topdir" \
      --define "_tmppath $HOME/tmp" \
      --define "_dbpath $RPM_DB_PATH" \
      --define "_binary_payload w9.zstdio" \
      --define "_build_id_links none" \
      --define "__check_files %{nil}" \
      --define "__strip /bin/true" \
      --define "__os_install_post %{nil}" \
      --buildroot "$buildroot" \
      --dbpath "$RPM_DB_PATH" \
      --target ${meta.rpmArch} \
      -bb "$topdir/SPECS/${meta.name}.spec"

    mkdir -p $out
    cp "$topdir/RPMS/${meta.rpmArch}/${meta.name}-${meta.version}-1.${meta.rpmArch}.rpm" \
       "$out/${meta.name}-${meta.version}-1.${meta.rpmArch}.rpm"
  '';

  passthru = {
    info = meta;
    inherit target format;
  };
}
