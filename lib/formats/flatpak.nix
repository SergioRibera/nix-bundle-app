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
  gnutar,
  gzip,
  coreutils,
  patchelf,
  file,
  gnugrep,
  rsync,
  gnused,
  gawk,
  findutils,
  closureInfo,
  writeText,
  writeShellScript,
  ...
}:

# Produces a flatpak source layout (manifest YAML + source tarball + helper
# build script). Doesn't run `flatpak-builder` itself — that needs network
# access to fetch the runtime, which Nix sandbox forbids. User runs
# `./build.sh` on a flatpak-enabled host to materialise the `.flatpak`.

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

  fp = meta.flatpak;
  appId = meta.bundleId;
  command = if fp.command != null then fp.command else meta.name;
  tarName = "${meta.name}-${meta.version}.tar.gz";

  finishArgsYaml = lib.concatMapStringsSep "\n" (a: "  - ${a}") fp.finishArgs;

  extraModulesYaml =
    if fp.extraModules == [ ] then
      ""
    else
      lib.concatMapStringsSep "\n" (m: "  - " + builtins.toJSON m) fp.extraModules;

  manifestYaml = ''
    app-id: ${appId}
    runtime: ${fp.runtime}
    runtime-version: '${fp.runtimeVersion}'
    sdk: ${fp.sdk}
    command: ${command}
    finish-args:
    ${finishArgsYaml}
    modules:
      - name: ${meta.name}
        buildsystem: simple
        sources:
          - type: archive
            path: ${tarName}
            strip-components: 0
        build-commands:
          - mkdir -p /app/bin /app/lib /app/share
          - if [ -d opt/${meta.name}/bin ]; then cp -a opt/${meta.name}/bin/. /app/bin/; fi
          - if [ -d opt/${meta.name}/lib ]; then cp -a opt/${meta.name}/lib/. /app/lib/; fi
          - if [ -d opt/${meta.name}/share ]; then cp -a opt/${meta.name}/share/. /app/share/; fi
          - if [ -d usr/share/applications ]; then install -Dm644 usr/share/applications/* /app/share/applications/ 2>/dev/null || true; fi
          - if [ -d usr/share/icons ]; then cp -a usr/share/icons /app/share/ 2>/dev/null || true; fi
    ${extraModulesYaml}
  '';

  buildScript = ''
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(cd "$(dirname "$0")" && pwd)
    cd "$here"

    if ! command -v flatpak-builder >/dev/null 2>&1; then
      echo "flatpak-builder not in PATH. Install via 'nix shell nixpkgs#flatpak-builder' or your distro." >&2
      exit 1
    fi

    BUILD_DIR=''${BUILD_DIR:-build}
    REPO_DIR=''${REPO_DIR:-repo}
    APP_ID=${appId}
    OUTPUT=''${OUTPUT:-${meta.name}-${meta.version}.flatpak}

    rm -rf "$BUILD_DIR"
    flatpak-builder --force-clean --repo="$REPO_DIR" "$BUILD_DIR" ${appId}.yaml
    flatpak build-bundle "$REPO_DIR" "$OUTPUT" "$APP_ID"
    echo "Built: $here/$OUTPUT"
  '';
in
stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-flatpak-source";
  dontUnpack = true;
  nativeBuildInputs = [
    gnutar
    gzip
    coreutils
    patchelf
    file
    gnugrep
    rsync
    gnused
    gawk
    findutils
  ];

  buildCommand = ''
    set -euo pipefail
    stage=$PWD/stage
    mkdir -p "$stage"

    ${common.stageLinux {
      inherit drv meta target;
      stage = "$stage";
    }}

    mkdir -p $out
    ( cd "$stage" && ${gnutar}/bin/tar --owner=0 --group=0 --sort=name \
        -czf "$out/${tarName}" . )

    cp ${writeText "${appId}.yaml" manifestYaml} "$out/${appId}.yaml"
    cp ${writeShellScript "build.sh" buildScript} "$out/build.sh"
    chmod +x "$out/build.sh"

    ${signing.emitSignScript {
      inherit meta format;
      artifactGlob = "*.flatpak";
    }}
  '';

  passthru = {
    info = meta;
    inherit target format;
    outFile = "${appId}.yaml";
  };
}
