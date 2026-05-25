{ pkgs }:

let
  lib = pkgs.lib;

  utils = import ./utils.nix { inherit lib; };
  desktop = import ./desktop.nix { inherit lib; };
  services = import ./services.nix { inherit lib utils; };
  infoLib = import ./info.nix { inherit lib utils; };
  deps = import ./deps.nix { inherit pkgs lib utils; };
  signing = import ./signing.nix { inherit pkgs lib; };
  releaseLib = import ./release.nix { inherit pkgs lib; };

  formatModules = {
    deb = import ./formats/deb.nix;
    rpm = import ./formats/rpm.nix;
    archlinux = import ./formats/archlinux.nix;
    appimage = import ./formats/appimage.nix;
    flatpak = import ./formats/flatpak.nix;
    snap = import ./formats/snap.nix;
    "tar.gz" = import ./formats/tarball.nix;
    "tar.xz" = import ./formats/tarball.nix;
    "tar.zst" = import ./formats/tarball.nix;
    app = import ./formats/app.nix;
    dmg = import ./formats/dmg.nix;
    pkg = import ./formats/pkg.nix;
    productbuild = import ./formats/productbuild.nix;
    brew = import ./formats/brew.nix;
    nsis = import ./formats/nsis.nix;
    exe = import ./formats/nsis.nix;
    msi = import ./formats/msi.nix;
    zip = import ./formats/zip.nix;
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
  inherit
    bundle
    bundleAll
    utils
    desktop
    services
    signing
    ;
  inherit (signing) signedApp;
  release = releaseLib.release bundle;
  installScripts = releaseLib.installScripts bundle;
  formats = builtins.attrNames formatModules;
  formatOS = formatOS;
  targets = targetsByOS;
  linuxTargets = targetsByOS.linux;
  darwinTargets = targetsByOS.darwin;
  windowsTargets = targetsByOS.windows;
  inherit (infoLib) normalize;
}
