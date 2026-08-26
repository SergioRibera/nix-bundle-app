{
  pkgs ? import <nixpkgs> { },
  bundler ? (pkgs.extend (import ../overlay.nix)).nixBundleApp,
}:

let
  helpers = import ./lib.nix { inherit pkgs bundler; };
  args = { inherit helpers; };
in
import ./hello-bundles.nix args
// import ./hello-services.nix args
// import ./hello-extra-files.nix args
// import ./rust-linux.nix args
// import ./rust-darwin.nix args
// import ./rust-windows.nix args
