{
  description = "nix-bundle-app — turn any Nix derivation into native installers (deb, rpm, archlinux, .app, .dmg, brew, NSIS, zip, tarball)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    let
      mkLib = pkgs: import ./lib { inherit pkgs; };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
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
          docs = import ./lib/docs.nix { inherit pkgs; };
        };

        # `nix run .#hello-deb-signed -- ./dist` builds + signs in one shot.
        # The bundle needs `info.signing.<os>.enable = true`; secrets come
        # from the caller's env vars (P12_PASSWORD / GPG_KEY_ID / …).
        apps = {
          hello-deb-signed = bundler.signedApp { bundle = examples.hello-deb; };
          hello-rpm-signed = bundler.signedApp { bundle = examples.hello-rpm; };
          hello-pkg-signed = bundler.signedApp { bundle = examples.hello-pkg; };
          hello-nsis-signed = bundler.signedApp { bundle = examples.hello-nsis; };
          hello-msi-signed = bundler.signedApp { bundle = examples.hello-msi; };
        };

        checks = tests;

        formatter = pkgs.nixfmt-tree;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nil
          ];
        };
      }
    )
    // {
      lib = { inherit mkLib; };

      templates.default = {
        path = ./examples/hello;
        description = "Minimal nix-bundle-app consumer";
      };
    };
}
