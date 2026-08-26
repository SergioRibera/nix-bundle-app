{ pkgs, bundler }:

let
  # Checks below assert hardcoded x86_64 artifact names, so each drv must
  # genuinely be that target regardless of host — cross-compile unless
  # already native.
  isLinuxHost = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  isX86_64Darwin = pkgs.stdenv.hostPlatform.system == "x86_64-darwin";
  drv = if isLinuxHost then pkgs.hello else pkgs.pkgsCross.gnu64.hello;
  drvWin = pkgs.pkgsCross.mingwW64.hello;
  drvDarwin = if isX86_64Darwin then pkgs.hello else pkgs.pkgsCross.x86_64-darwin.hello;

  rustSrc = ./rust;
  rustName = "nix-bundle-app-rust-demo";
  rustVersion = "0.1.0";

  buildRust =
    rp:
    rp.buildRustPackage {
      pname = rustName;
      version = rustVersion;
      src = rustSrc;
      cargoLock.lockFile = ./rust/Cargo.lock;
      doCheck = false;
    };

  rustLinux =
    if isLinuxHost then buildRust pkgs.rustPlatform else buildRust pkgs.pkgsCross.gnu64.rustPlatform;
  rustWindows = buildRust pkgs.pkgsCross.mingwW64.rustPlatform;
  rustDarwin =
    if isX86_64Darwin then
      buildRust pkgs.rustPlatform
    else
      buildRust pkgs.pkgsCross.x86_64-darwin.rustPlatform;

  # `nsis` is `meta.broken` on darwin in nixpkgs; skip there, CI still runs it.
  canNsis = !pkgs.stdenv.hostPlatform.isDarwin;

  # rpmbuild only packages for its own host CPU regardless of `--target`, and
  # this repo has no x86_64-linux builder; skip, CI (x86_64-linux) covers it.
  canRpm = pkgs.stdenv.hostPlatform.system == "x86_64-linux";

  info = {
    homepage = "https://example.com";
    maintainer = "tests <noreply@example.com>";
    license = "GPL-3.0";
  };

  rustInfo = info // {
    name = rustName;
    version = rustVersion;
    summary = "nix-bundle-app rust E2E demo";
    longDescription = "Tiny rust binary used to validate end-to-end bundling.";
  };

  check =
    {
      name,
      format,
      drv,
      target ? null,
      info ? { },
      expect,
    }:
    let
      built = bundler.bundle {
        inherit
          drv
          format
          info
          target
          ;
      };
    in
    pkgs.runCommand "check-${name}" { } ''
      if [ ! -d "${built}" ]; then
        echo "bundle output missing: ${built}" >&2; exit 1
      fi
      found=0
      for f in ${built}/*; do
        name=$(basename "$f")
        case "$name" in
          ${expect}) found=1; break ;;
        esac
      done
      if [ $found -ne 1 ]; then
        echo "Expected artifact matching '${expect}' not found in:" >&2
        ls -1 "${built}" >&2
        exit 1
      fi
      mkdir -p $out
      echo "ok ${name}" > $out/result
    '';

  e2e =
    {
      name,
      format,
      drv,
      target ? null,
      info ? { },
      expect,
      probeInputs ? [ ],
      assertScript,
    }:
    let
      built = bundler.bundle {
        inherit
          drv
          format
          info
          target
          ;
      };
    in
    pkgs.runCommand "e2e-${name}" { nativeBuildInputs = probeInputs; } ''
      set -euo pipefail
      shopt -s nullglob
      candidates=( ${built}/${expect} )
      if [ "''${#candidates[@]}" -eq 0 ]; then
        echo "no artifact matching '${expect}' in ${built}:" >&2
        ls -1 ${built} >&2
        exit 1
      fi
      artifact="''${candidates[0]}"
      echo "probing $artifact"
      ${assertScript}
      mkdir -p $out
      echo "ok ${name}" > $out/result
    '';
in
{
  inherit
    pkgs
    check
    e2e
    info
    rustInfo
    drv
    drvWin
    drvDarwin
    rustLinux
    rustWindows
    rustDarwin
    rustName
    rustVersion
    canNsis
    canRpm
    ;
}
