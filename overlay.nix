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
  # None of these return a derivation — they're pure string/attrset-rendering
  # libraries — so they're `import`ed, not `callPackage`d. `deps.nix` needs
  # tool derivations of its own (to embed absolute store paths in the shell
  # it generates), but it's reused by many different format derivations, so
  # rather than resolve those once here and hand every format the same fixed
  # splice, each format module `import`s `deps.nix` itself using the tool
  # args *it* received from its own `callPackage` call below. That keeps
  # exactly one `callPackage` call per derivation, with that call the sole
  # authority over how its tools are spliced.
  signing = import ./lib/signing.nix { inherit lib; };
  releaseLib = import ./lib/release.nix { inherit lib; };

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

      # Formats that embed another format's derivation as a nested
      # sub-bundle (dmg/pkg embed app.nix; productbuild embeds pkg.nix,
      # which itself embeds app.nix; brew embeds tarball.nix). Each is
      # built via its own single `callPackage` call right here — the only
      # place with access to both `pkgs` and `formatModules` — using
      # exactly the args the format module used to pass along when it
      # built the sub-bundle itself. No module receives `callPackage`;
      # each receives the finished derivation(s) as plain arguments.
      mkAppBundle =
        { format, meta }:
        pkgs.callPackage formatModules.app {
          inherit
            utils
            services
            signing
            drv
            format
            meta
            ;
          target = t;
        };

      mkPkgBundle =
        { format, meta }:
        pkgs.callPackage formatModules.pkg {
          inherit
            utils
            services
            signing
            drv
            format
            meta
            ;
          target = t;
          appBundle = mkAppBundle { inherit format meta; };
        };

      extraArgs =
        if format == "dmg" || format == "pkg" then
          { appBundle = mkAppBundle { inherit format meta; }; }
        else if format == "productbuild" then
          {
            componentPkg = mkPkgBundle {
              format = "pkg";
              meta = meta // {
                format = "pkg";
              };
            };
          }
        else if format == "brew" then
          {
            tarball = pkgs.callPackage formatModules."tar.gz" {
              inherit
                utils
                desktop
                services
                drv
                ;
              target = t;
              format = "tar.gz";
              meta = meta // {
                format = "tar.gz";
              };
            };
          }
        else
          { };
    in
    pkgs.callPackage mod (
      {
        inherit
          utils
          desktop
          services
          signing
          drv
          format
          meta
          ;
        target = t;
      }
      // extraArgs
    );

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
    # Each is curried on its own tool deps first — `callPackage` resolves
    # those (one call, right here, per exposed derivation-producing entry
    # point), then we apply `bundle` to get the function callers expect.
    signedApp = pkgs.callPackage signing.signedApp { };
    release = pkgs.callPackage releaseLib.release { } bundle;
    installScripts = pkgs.callPackage releaseLib.installScripts { } bundle;
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
