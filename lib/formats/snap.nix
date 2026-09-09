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
  coreutils,
  patchelf,
  file,
  gnugrep,
  rsync,
  gnused,
  gawk,
  findutils,
  closureInfo,
  ...
}:

# Produces a snapcraft source layout (`snapcraft.yaml` + staged payload + a
# build script). Doesn't run snapcraft directly — snapcraft needs an LXD or
# multipass build VM which the Nix sandbox can't provide. User runs
# `./build.sh` on a snapcraft-enabled host to materialise the `.snap`.

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

  sn = meta.snap;
  summary = if sn.summary != null then sn.summary else meta.summary;

  snapArch = if target.arch == "x86_64" then "amd64" else target.arch;

  plugsBlock = lib.concatMapStringsSep "\n" (p: "      - ${p}") sn.plugs;

  descIndented = lib.replaceStrings [ "\n" ] [ "\n  " ] meta.longDescription;

  serviceApps = lib.concatMapStringsSep "\n" (
    s:
    let
      svcBin = baseNameOf (lib.head (lib.splitString " " s.exec));
      restartCond = if s.restart == "always" then "always" else "on-failure";
    in
    "  ${s.name}:\n"
    + "    command: bin/${svcBin}\n"
    + "    daemon: simple\n"
    + "    restart-condition: ${restartCond}\n"
    + "    plugs:\n"
    + plugsBlock
  ) meta.services;

  # If a service shares the binary name with the main app, the daemon entry
  # already covers `snap run <name>`. Emitting a second top-level app with the
  # same key produces "found duplicate key" in snapcraft.yaml.
  hasMainService = lib.any (s: s.name == meta.name) meta.services;

  cliAppBlock = lib.optionalString (!hasMainService) (
    "  ${meta.name}:\n" + "    command: bin/${meta.name}\n" + "    plugs:\n" + plugsBlock + "\n"
  );

  manifestYaml =
    "name: ${meta.name}\n"
    + "version: '${meta.version}'\n"
    + "summary: ${summary}\n"
    + "description: |\n"
    + "  ${descIndented}\n"
    + "base: ${sn.base}\n"
    + "grade: ${sn.grade}\n"
    + "confinement: ${sn.confinement}\n"
    + "architectures:\n"
    + "  - build-on: ${snapArch}\n"
    + "parts:\n"
    + "  ${meta.name}:\n"
    + "    plugin: dump\n"
    + "    source: ./payload/\n"
    + "    organize:\n"
    + "      opt/${meta.name}/bin/*: bin/\n"
    + "      opt/${meta.name}/lib/*: lib/\n"
    + "      opt/${meta.name}/share/*: share/\n"
    + "apps:\n"
    + cliAppBlock
    + lib.optionalString (meta.services != [ ]) (serviceApps + "\n");

  buildScript = ''
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(cd "$(dirname "$0")" && pwd)
    cd "$here"

    if ! command -v snapcraft >/dev/null 2>&1; then
      echo "snapcraft not in PATH. Install via 'snap install snapcraft --classic' or 'nix shell nixpkgs#snapcraft'." >&2
      exit 1
    fi
    snapcraft pack --output "${meta.name}_${meta.version}_${snapArch}.snap"
    echo "Built: $here/${meta.name}_${meta.version}_${snapArch}.snap"
  '';
in
stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-snap-source";
  dontUnpack = true;
  nativeBuildInputs = [
    gnutar
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
    payload=$PWD/payload
    mkdir -p "$payload"

    ${common.stageLinux {
      inherit drv meta target;
      stage = "$payload";
    }}

    # Snap uses snap-internal paths (bin/, lib/, share/) via the `organize:`
    # directive — FHS layout under usr/ would duplicate every binary in the
    # finished .snap. Drop it.
    rm -rf "$payload/usr"

    mkdir -p $out/snap $out/payload
    ${coreutils}/bin/cp -a --no-preserve=ownership "$payload"/. $out/payload/

    cat > "$out/snap/snapcraft.yaml" <<'MANIFEST_EOF'
    ${manifestYaml}
    MANIFEST_EOF
    cat > "$out/build.sh" <<'BUILD_SH_EOF'
    ${buildScript}
    BUILD_SH_EOF
    chmod +x "$out/build.sh"

    ${signing.emitSignScript {
      inherit meta format;
      artifactGlob = "*.snap";
    }}
  '';

  passthru = {
    info = meta;
    inherit target format;
    outFile = "snap/snapcraft.yaml";
  };
}
