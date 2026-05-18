{ pkgs, bundler }:

let
  helpers = import ./lib.nix { inherit pkgs bundler; };
  args = { inherit helpers; };
in
import ./hello-bundles.nix args
// import ./hello-services.nix args
// import ./rust-linux.nix args
// import ./rust-darwin.nix args
// import ./rust-windows.nix args
