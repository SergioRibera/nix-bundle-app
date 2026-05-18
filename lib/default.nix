{ pkgs }:

let
  lib = pkgs.lib;

  utils = import ./utils.nix { inherit lib; };
  desktop = import ./desktop.nix { inherit lib; };
  services = import ./services.nix { inherit lib utils; };
  infoLib = import ./info.nix { inherit lib utils; };
  deps = import ./deps.nix { inherit pkgs lib utils; };
  signing = import ./signing.nix { inherit lib; };

  formatModules = {
    deb = import ./formats/deb.nix;
    rpm = import ./formats/rpm.nix;
    archlinux = import ./formats/archlinux.nix;
    appimage = import ./formats/appimage.nix;
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
    app = "darwin";
    dmg = "darwin";
    pkg = "darwin";
    productbuild = "darwin";
    # Homebrew is supported on macOS AND linuxbrew. Allow any host.
    brew = "any";
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
      requiredOS = formatOS.${format};
      meta =
        assert lib.assertMsg (
          requiredOS == "any" || requiredOS == t.os
        ) "nix-bundle-app: format '${format}' requires os='${requiredOS}', got os='${t.os}'.";
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
  formats = builtins.attrNames formatModules;
  inherit (infoLib) normalize;
}
