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

# Produces a snapcraft source layout (`snapcraft.yaml` + staged payload + a
# build script). Doesn't run snapcraft directly — snapcraft needs an LXD or
# multipass build VM which the Nix sandbox can't provide. User runs
# `./build.sh` on a snapcraft-enabled host to materialise the `.snap`.

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
    + "  ${meta.name}:\n"
    + "    command: bin/${meta.name}\n"
    + "    plugs:\n"
    + plugsBlock
    + "\n"
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
pkgs.stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-snap-source";
  dontUnpack = true;
  nativeBuildInputs = with pkgs; [
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
    ${pkgs.coreutils}/bin/cp -a --no-preserve=ownership "$payload"/. $out/payload/

    cp ${pkgs.writeText "snapcraft.yaml" manifestYaml} "$out/snap/snapcraft.yaml"
    cp ${pkgs.writeShellScript "build.sh" buildScript} "$out/build.sh"
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
