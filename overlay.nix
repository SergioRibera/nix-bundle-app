# The canonical definition of nix-bundle-app — no flake, no separate library
# entry point. Pure, pkgs-independent pieces extend `final.lib.nixBundleApp`;
# everything that builds derivations or shells out lives on
# `final.nixBundleApp` directly.
final: prev:
let
  pkgs = final;
  lib = final.lib;

  utils = import ./lib/utils.nix { inherit lib; };
  desktop = import ./lib/desktop.nix { inherit lib; };
  services = import ./lib/services.nix { inherit lib utils; };
  infoLib = import ./lib/info.nix { inherit lib utils; };
  deps = import ./lib/deps.nix { inherit pkgs lib utils; };
  signing = import ./lib/signing.nix { inherit pkgs lib; };
  releaseLib = import ./lib/release.nix { inherit pkgs lib; };

  formatModules = {
    deb = import ./lib/formats/deb.nix;
    rpm = import ./lib/formats/rpm.nix;
    archlinux = import ./lib/formats/archlinux.nix;
    appimage = import ./lib/formats/appimage.nix;
    flatpak = import ./lib/formats/flatpak.nix;
    snap = import ./lib/formats/snap.nix;
    "tar.gz" = import ./lib/formats/tarball.nix;
    "tar.xz" = import ./lib/formats/tarball.nix;
    "tar.zst" = import ./lib/formats/tarball.nix;
    app = import ./lib/formats/app.nix;
    dmg = import ./lib/formats/dmg.nix;
    pkg = import ./lib/formats/pkg.nix;
    productbuild = import ./lib/formats/productbuild.nix;
    brew = import ./lib/formats/brew.nix;
    nsis = import ./lib/formats/nsis.nix;
    exe = import ./lib/formats/nsis.nix;
    msi = import ./lib/formats/msi.nix;
    zip = import ./lib/formats/zip.nix;
  };

  formatOS = {
    deb = "linux";
    rpm = "linux";
    archlinux = "linux";
    appimage = "linux";
    flatpak = "linux";
    snap = "linux";
    app = "darwin";
    dmg = "darwin";
    pkg = "darwin";
    productbuild = "darwin";
    # Homebrew: macOS + linuxbrew only.
    brew = [
      "linux"
      "darwin"
    ];
    nsis = "windows";
    exe = "windows";
    msi = "windows";
    "tar.gz" = "any";
    "tar.xz" = "any";
    "tar.zst" = "any";
    zip = "any";
  };

  resolveTarget =
    drv: target: if target != null then utils.normalizeTarget target else utils.detectTargetFromDrv drv;

  # `formatOS` values can be: a single os string ("linux"), the wildcard "any",
  # or a list of os strings (e.g. brew = ["linux" "darwin"]).
  osMatches =
    spec: os: if builtins.isList spec then builtins.elem os spec else spec == "any" || spec == os;

  # Per-OS format lists, auto-derived from `formatOS`. Wildcards ("any") and
  # multi-OS specs are folded into each matching bucket so consumers iterate one
  # list per platform without hardcoding.
  targetsByOS =
    let
      formatsFor = os: builtins.attrNames (lib.filterAttrs (_: v: osMatches v os) formatOS);
      anyFmts = builtins.attrNames (lib.filterAttrs (_: v: v == "any") formatOS);
    in
    {
      linux = lib.sort (a: b: a < b) (formatsFor "linux");
      darwin = lib.sort (a: b: a < b) (formatsFor "darwin");
      windows = lib.sort (a: b: a < b) (formatsFor "windows");
      any = anyFmts;
    };

  bundle =
    {
      drv,
      format,
      info ? { },
      target ? null,
    }:
    let
      mod =
        formatModules.${format}
          or (throw "nix-bundle-app: unknown format '${format}'. Supported: ${lib.concatStringsSep ", " (builtins.attrNames formatModules)}");
      t = resolveTarget drv target;
      allowedOS = formatOS.${format};
      allowedDesc = if builtins.isList allowedOS then lib.concatStringsSep "|" allowedOS else allowedOS;
      meta =
        assert lib.assertMsg (osMatches allowedOS t.os)
          "nix-bundle-app: format '${format}' requires os='${allowedDesc}', got os='${t.os}'.";
        infoLib.normalize info drv t format;
    in
    mod {
      inherit
        pkgs
        lib
        deps
        utils
        desktop
        services
        signing
        drv
        format
        meta
        ;
      target = t;
    };

  bundleAll =
    {
      drv,
      formats,
      info ? { },
      target ? null,
    }:
    let
      built = map (fmt: {
        name = fmt;
        path = bundle {
          inherit drv info target;
          format = fmt;
        };
      }) formats;
    in
    pkgs.linkFarm "${drv.pname or drv.name or "bundle"}-bundles" built;
in
{
  nixBundleApp = {
    inherit bundle bundleAll;
    inherit (signing) signedApp;
    release = releaseLib.release bundle;
    installScripts = releaseLib.installScripts bundle;
    formats = builtins.attrNames formatModules;
    inherit formatOS;
    targets = targetsByOS;
    linuxTargets = targetsByOS.linux;
    darwinTargets = targetsByOS.darwin;
    windowsTargets = targetsByOS.windows;
  };

  lib = (prev.lib or { }) // {
    nixBundleApp = {
      inherit utils desktop services;
      inherit (infoLib) normalize;
    };
  };
}
