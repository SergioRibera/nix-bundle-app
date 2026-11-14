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
// import ./hello-icon.nix args
// import ./hello-prerelease.nix args
// import ./hello-file-associations.nix args
// import ./hello-nsis-script.nix args
// import ./hello-productbuild.nix args
// import ./hello-macos.nix args
// import ./rust-linux.nix args
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (import ./host-libs.nix args)
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin (import ./rust-darwin.nix args)
// import ./rust-windows.nix args
