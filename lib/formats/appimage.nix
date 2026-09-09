{
  lib,
  utils,
  desktop,
  signing,
  drv,
  format,
  meta,
  target,
  stdenv,
  fetchurl,
  squashfsTools,
  coreutils,
  file,
  gnugrep,
  gawk,
  rsync,
  patchelf,
  gnused,
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
  outFile = "${meta.name}-${meta.version}-${target.arch}.AppImage";

  # Runtime is a ~200KB ELF that mounts the appended squashfs and execs AppRun.
  # AppImage/type2-runtime publishes to a rolling `continuous` release tag, so
  # the artifact rotates whenever upstream rebuilds. When CI trips a hash
  # mismatch, refresh via:
  #   nix-prefetch-url --type sha256 \
  #     https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-<arch>
  #   nix hash convert --hash-algo sha256 --to sri <base32>
  # Downstreams can bypass the pin entirely with
  # `info.appImageRuntime = pkgs.fetchurl { url=...; hash=...; }`.
  defaultRuntime =
    let
      url = "https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-${target.arch}";
      hash =
        {
          "x86_64" = "sha256-HMSbzx4szVk8N5rbF8n4WjbWGQiCllBN6VsdBiFa678=";
          "aarch64" = "sha256-fV13K3wy8MhMrwpFKjBypXCQJ9fqxYVv64mnp6iIE3I=";
        }
        .${target.arch} or null;
    in
    if hash == null then
      throw "nix-bundle-app: no pinned AppImage runtime hash for arch '${target.arch}'. Supply meta.appImageRuntime."
    else
      pkgs.fetchurl {
        inherit url hash;
      };

  runtime = if meta.appImageRuntime != null then meta.appImageRuntime else defaultRuntime;

  # AppImage spec requires exactly one top-level .desktop. Use the first
  # user-supplied entry; otherwise synthesize a minimal one from the
  # package's name + summary so the AppImage is still spec-compliant.
  primaryEntry =
    if meta.desktopEntries != [ ] then
      builtins.head meta.desktopEntries
    else
      {
        name = meta.name;
        exec = "${meta.name} %F";
        comment = if meta.summary != "" then meta.summary else meta.name;
        icon = meta.name;
        categories = [ "Utility" ];
        terminal = meta.appImageTerminal;
      };

  renderedDesktop = desktop.renderEntry primaryEntry;

  appRun = ''
    #!/bin/sh
    HERE="$(dirname -- "$(readlink -f -- "$0")")"
    export LD_LIBRARY_PATH="$HERE/usr/lib:$LD_LIBRARY_PATH"
    export PATH="$HERE/usr/bin:$PATH"
    export XDG_DATA_DIRS="$HERE/usr/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    exec "$HERE/usr/bin/${meta.name}" "$@"
  '';
in
stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = [
    squashfsTools
    coreutils
    file
    gnugrep
    rsync
    patchelf
    gnused
  ];

  buildCommand = ''
    AppDir=$PWD/${meta.name}.AppDir
    mkdir -p "$AppDir/usr/bin" "$AppDir/usr/lib" "$AppDir/usr/share"

    ${deps.copyBinaries drv "$AppDir/usr/bin"}
    ${deps.copyLinuxLibs drv "$AppDir/usr/lib"}
    ${deps.copyResources drv "$AppDir/usr/share"}

    chmod -R u+w "$AppDir"
    ${deps.verifyStagedBinaries {
      binDir = "$AppDir/usr/bin";
      inherit target;
    }}
    ${deps.patchLinuxBinaries {
      binDir = "$AppDir/usr/bin";
      inherit target;
      keepInterpreter = meta.keepInterpreter;
      # AppImage always bundles libs in the squashed image, so RPATH
      # must point at the bundled tree regardless of `meta.bundleLibs`.
      setBundledRpath = true;
    }}

    cat > "$AppDir/${meta.name}.desktop" <<'DESKTOP_EOF'
    ${renderedDesktop.content}
    DESKTOP_EOF

    ${lib.optionalString (renderedDesktop.iconPath != null) ''
      cp "${renderedDesktop.iconPath}" "$AppDir/${meta.name}.png" || true
      ( cd "$AppDir" && ln -sf "${meta.name}.png" .DirIcon )
    ''}
    if [ ! -e "$AppDir/${meta.name}.png" ]; then
      # 1x1 transparent PNG so appimagetool spec is satisfied
      ${coreutils}/bin/printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xfc\xff\xff?\x00\x05\xfe\x02\xfe\xa3\x3e\x8a\xcc\x00\x00\x00\x00IEND\xaeB`\x82' > "$AppDir/${meta.name}.png"
      ( cd "$AppDir" && ln -sf "${meta.name}.png" .DirIcon )
    fi

    cat > "$AppDir/AppRun" <<'APPRUN_EOF'
    ${appRun}
    APPRUN_EOF
    chmod +x "$AppDir/AppRun"

    mksquashfs "$AppDir" payload.squashfs \
      -root-owned -noappend -comp zstd -all-root \
      -no-progress -no-xattrs

    mkdir -p $out
    cat ${runtime} payload.squashfs > "$out/${outFile}"
    chmod +x "$out/${outFile}"

    ${signing.emitSignScript {
      inherit meta format;
      artifactGlob = "*.AppImage";
    }}
  '';

  passthru = {
    info = meta;
    inherit target format runtime;
    inherit outFile;
  };
}
