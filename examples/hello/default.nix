# Minimal nix-bundle-app consumer.
#
# This uses a relative path so it builds straight out of a checkout of this
# repo (`nix-build examples/hello`). In a real project, replace the relative
# overlay import with a pinned checkout, e.g.:
#
#   nixBundleAppSrc = builtins.fetchTarball {
#     url = "https://github.com/SergioRibera/nix-bundle-app/archive/<rev>.tar.gz";
#     sha256 = "...";
#   };
#   pkgs = import <nixpkgs> {
#     overlays = [ (import "${nixBundleAppSrc}/overlay.nix") ];
#   };
#
# (pin nixpkgs itself the same way, or via niv/npins, instead of `<nixpkgs>`).

{
  pkgs ? import <nixpkgs> { overlays = [ (import ../../overlay.nix) ]; },
}:
let
  bundler = pkgs.nixBundleApp;

  info = {
    maintainer = "Demo <demo@example.com>";
    homepage = "https://example.com";
    license = "MIT";
  };
in
{
  deb = bundler.bundle {
    drv = pkgs.hello;
    format = "deb";
    inherit info;
  };
  rpm = bundler.bundle {
    drv = pkgs.hello;
    format = "rpm";
    inherit info;
  };
  archlinux = bundler.bundle {
    drv = pkgs.hello;
    format = "archlinux";
    inherit info;
  };
  tarball = bundler.bundle {
    drv = pkgs.hello;
    format = "tar.gz";
    inherit info;
  };

  # Cross-target Windows installer (requires Linux host).
  windows-installer = bundler.bundle {
    drv = pkgs.pkgsCross.mingwW64.hello;
    format = "nsis";
    target = {
      arch = "x86_64";
      os = "windows";
    };
    inherit info;
  };

  all = bundler.bundleAll {
    drv = pkgs.hello;
    formats = [
      "deb"
      "rpm"
      "archlinux"
      "tar.gz"
      "tar.xz"
      "zip"
    ];
    inherit info;
  };
}
