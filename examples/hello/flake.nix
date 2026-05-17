{
  description = "Minimal nix-bundle-app consumer — bundle GNU hello as native installers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-bundle-app.url = "path:../..";
  };

  outputs = { nixpkgs, flake-utils, nix-bundle-app, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        bundler = nix-bundle-app.lib.mkLib pkgs;

        info = {
          maintainer = "Demo <demo@example.com>";
          homepage = "https://example.com";
          license = "MIT";
        };
      in {
        packages = {
          deb = bundler.bundle { drv = pkgs.hello; format = "deb"; inherit info; };
          rpm = bundler.bundle { drv = pkgs.hello; format = "rpm"; inherit info; };
          archlinux = bundler.bundle { drv = pkgs.hello; format = "archlinux"; inherit info; };
          tarball = bundler.bundle { drv = pkgs.hello; format = "tar.gz"; inherit info; };

          # Cross-target Windows installer (requires Linux host).
          windows-installer = bundler.bundle {
            drv = pkgs.pkgsCross.mingwW64.hello;
            format = "nsis";
            target = { arch = "x86_64"; os = "windows"; };
            inherit info;
          };

          # All linux formats at once.
          all = bundler.bundleAll {
            drv = pkgs.hello;
            formats = [ "deb" "rpm" "archlinux" "tar.gz" "tar.xz" "zip" ];
            inherit info;
          };
        };
      });
}
