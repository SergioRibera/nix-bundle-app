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
  writeText,
  writeShellScript,
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
  outFile = "${meta.name}-${meta.version}-${target.arch}.AppImage";

  # Pinned to a numbered type2-runtime release, not `continuous` — that tag
  # is rebuilt in place upstream, which would make the sha256 below go stale.
  # Bump + refresh the hashes to update, or override per-bundle via
  # `info.appImageRuntime`.
  runtimeRelease = "20251108";

  defaultRuntime =
    let
      url = "https://github.com/AppImage/type2-runtime/releases/download/${runtimeRelease}/runtime-${target.arch}";
      sha =
        {
          "x86_64" = "0396xi3km1yd0z4329lbjxmv82ddc40gd0x8hca0ylcj7i28pjig";
          "aarch64" = "0i3lv1j8d9yqssh2i97idmdg9xx11jgdairkdpzw1ikwj77xzjq0";
        }
        .${target.arch} or null;
    in
    if sha == null then
      throw "nix-bundle-app: no pinned AppImage runtime hash for arch '${target.arch}'. Supply meta.appImageRuntime."
    else
      fetchurl {
        inherit url;
        sha256 = sha;
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

    cp ${writeText renderedDesktop.filename renderedDesktop.content} \
       "$AppDir/${meta.name}.desktop"

    ${lib.optionalString (renderedDesktop.iconPath != null) ''
      cp "${renderedDesktop.iconPath}" "$AppDir/${meta.name}.png" || true
      ( cd "$AppDir" && ln -sf "${meta.name}.png" .DirIcon )
    ''}
    if [ ! -e "$AppDir/${meta.name}.png" ]; then
      # 1x1 transparent PNG so appimagetool spec is satisfied
      ${coreutils}/bin/printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xfc\xff\xff?\x00\x05\xfe\x02\xfe\xa3\x3e\x8a\xcc\x00\x00\x00\x00IEND\xaeB`\x82' > "$AppDir/${meta.name}.png"
      ( cd "$AppDir" && ln -sf "${meta.name}.png" .DirIcon )
    fi

    cp ${writeShellScript "AppRun" appRun} "$AppDir/AppRun"
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
