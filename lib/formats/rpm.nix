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
  rpm,
  patchelf,
  file,
  gnugrep,
  rsync,
  coreutils,
  gnused,
  gawk,
  findutils,
  closureInfo,
  writeText,
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
      writeText
      ;
  };
  common = import ./_common-linux.nix {
    inherit
      lib
      deps
      desktop
      services
      writeText
      ;
  };
  reqs = meta.depends.rpm or [ ];
  recs = meta.depends.rpmRecommends or [ ];
  group = meta.depends.rpmGroup or "Applications/System";

  hasEntries = meta.desktopEntries != [ ];
  hasIcons = lib.any (e: e.iconPath != null) meta.desktopEntries;
in
stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-1.${meta.rpmArch}.rpm";
  dontUnpack = true;
  nativeBuildInputs = [
    rpm
    patchelf
    file
    gnugrep
    rsync
    coreutils
    gnused
    gawk
    findutils
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

    ${lib.optionalString meta.autoDepends (
      deps.discoverLinuxDepsSnippet {
        kind = "rpm";
        scanDirs = [
          "$buildroot/opt/${meta.name}/bin"
          "$buildroot/opt/${meta.name}/lib"
        ];
        userDeps = reqs;
        outFile = "rpm-requires.csv";
      }
    )}

    requires_line=""
    ${
      if meta.autoDepends then
        ''
          if [ -s rpm-requires.csv ]; then
            requires_line="Requires: $(cat rpm-requires.csv | tr ',' ' ' | tr -s ' ' | sed 's/ /, /g')"
          fi
        ''
      else
        lib.optionalString (reqs != [ ]) ''requires_line="Requires: ${lib.concatStringsSep ", " reqs}"''
    }

    {
      echo "Name: ${meta.name}"
      echo "Version: ${meta.version}"
      echo "Release: 1%{?dist}"
      echo "Summary: ${meta.summary}"
      echo "License: ${meta.license}"
      ${lib.optionalString (meta.homepage != "") ''echo "URL: ${meta.homepage}"''}
      echo "Group: ${group}"
      echo "BuildArch: ${meta.rpmArch}"
      echo "AutoReqProv: no"
      [ -n "$requires_line" ] && echo "$requires_line"
      ${lib.optionalString (recs != [ ]) ''echo "Recommends: ${lib.concatStringsSep ", " recs}"''}
      echo
      echo "%description"
      echo "${meta.longDescription}"
      echo
      echo "%files"
      echo "%attr(0755, root, root) /opt/${meta.name}"
      echo "/usr/bin/*"
      ${lib.optionalString (common.hasServices meta) ''echo "%attr(0644, root, root) /lib/systemd/system/*"''}
      ${lib.optionalString hasEntries ''echo "/usr/share/applications/*"''}
      ${lib.optionalString hasIcons ''echo "/usr/share/icons/hicolor/512x512/apps/*"''}
      ${lib.concatMapStringsSep "\n      " (p: ''echo "${p}"'') (common.extraFilesPaths meta)}
      echo
      echo "%post"
      cat <<'POST_EOF'
    ${common.postinstSnippet meta}
    POST_EOF
      echo
      echo "%preun"
      cat <<'PREUN_EOF'
    ${common.prermSnippet meta}
    PREUN_EOF
      echo
      echo "%postun"
      cat <<'POSTUN_EOF'
    ${common.postrmSnippet meta}
    POSTUN_EOF
      echo
      echo "%clean"
      echo 'rm -rf $RPM_BUILD_ROOT'
    } > "$topdir/SPECS/${meta.name}.spec"

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

    ${signing.emitSignScript {
      inherit meta format;
      artifactGlob = "*.rpm";
    }}
  '';

  passthru = {
    info = meta;
    inherit target format;
    outFile = "${meta.name}-${meta.version}-1.${meta.rpmArch}.rpm";
  };
}
