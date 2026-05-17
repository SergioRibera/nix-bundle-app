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
