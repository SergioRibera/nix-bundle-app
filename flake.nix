{
  description = "nix-bundle-app — turn any Nix derivation into native installers (deb, rpm, archlinux, .app, .dmg, brew, NSIS, zip, tarball)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    let
      mkLib = pkgs: import ./lib { inherit pkgs; };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        bundler = mkLib pkgs;
        examples = import ./examples { inherit pkgs bundler; };
        tests = import ./tests { inherit pkgs bundler; };
      in
      {
        lib = bundler;

        packages = examples // {
          default = examples.hello-tar-gz;
          # Auto-generated options reference (built by .github/workflows/docs.yml).
          docs = import ./lib/docs.nix { inherit pkgs; };
        };

        checks = tests;

        apps.help = {
          type = "app";
          meta.description = "Print nix-bundle-app usage";
          program = toString (pkgs.writeShellScript "nix-bundle-app-help" ''
            cat <<EOF
            nix-bundle-app — bundle any Nix derivation into native installers.

            Quick usage in your flake:

              inputs.nix-bundle-app.url = "github:rustlanges/nix-bundle-app";

              outputs = { self, nixpkgs, nix-bundle-app, flake-utils }:
                flake-utils.lib.eachDefaultSystem (system:
                  let
                    pkgs = nixpkgs.legacyPackages.\''${system};
                    bundler = nix-bundle-app.lib.mkLib pkgs;
                  in {
                    packages.hello-deb = bundler.bundle {
                      drv = pkgs.hello;
                      format = "deb";
                      info.maintainer = "You <you@example.com>";
                    };
                    packages.hello-all = bundler.bundleAll {
                      drv = pkgs.hello;
                      formats = [ "deb" "rpm" "archlinux" "tar.gz" "zip" "app" "brew" ];
                    };
                  });

            Supported formats:
              linux:   deb, rpm, archlinux, tar.gz, tar.xz, tar.zst, appimage(soon)
              darwin:  app, dmg, brew, tar.gz
              windows: nsis (.exe installer), zip

            Run examples:
              nix build .#hello-deb
              nix build .#hello-rpm
              nix build .#hello-archlinux
              nix build .#hello-app
              nix build .#hello-nsis

            See README.md for the full API.
            EOF
          '');
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ nixfmt-rfc-style nil ];
        };
      })
    // {
      lib = { inherit mkLib; };

      templates.default = {
        path = ./examples/hello;
        description = "Minimal nix-bundle-app consumer";
      };
    };
}
