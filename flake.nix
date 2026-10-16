{
  description = "nix-bundle-app — turn any Nix derivation into native installers (deb, rpm, archlinux, .app, .dmg, brew, NSIS, zip, tarball)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Thin flake wrapper around the canonical overlay. Workflows + flake
  # consumers get `.#foo` targets and a devshell; everything substantive
  # lives in `overlay.nix` and should be consumed as an overlay by apps
  # that don't want a flake dependency.
  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      overlay = import ./overlay.nix;

      # x86_64-darwin is dropped in nixpkgs 26.11; apple silicon only on darwin.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      eachSystem =
        f:
        lib.genAttrs supportedSystems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ overlay ];
            }
          )
        );

      # Back-compat shim for consumers that imported the old
      # `nix-bundle-app.lib.mkLib pkgs` entry point.
      mkLib = pkgs: (pkgs.extend overlay).nixBundleApp;
    in
    {
      overlays.default = overlay;
      overlays.nixBundleApp = overlay;

      lib = { inherit mkLib; };

      templates.default = {
        path = ./examples/hello;
        description = "Minimal nix-bundle-app consumer";
      };

      legacyPackages = eachSystem lib.id;

      packages = eachSystem (
        pkgs:
        let
          examples = import ./examples { inherit pkgs; };
        in
        examples
        // {
          default = examples.hello-tar-gz;
          docs = pkgs.callPackage ./lib/docs.nix { };
        }
      );

      # `nix run .#hello-deb-signed -- ./dist` builds + signs in one shot.
      # The bundle needs `info.signing.<os>.enable = true`; secrets come
      # from the caller's env vars (P12_PASSWORD / GPG_KEY_ID / …).
      apps = eachSystem (
        pkgs:
        let
          examples = import ./examples { inherit pkgs; };
          mkSignedApp =
            bundle:
            let
              drv = pkgs.nixBundleApp.signedApp { inherit bundle; };
            in
            {
              type = "app";
              program = "${drv}/bin/${drv.name}";
            };
        in
        {
          hello-deb-signed = mkSignedApp examples.hello-deb;
          hello-rpm-signed = mkSignedApp examples.hello-rpm;
          hello-nsis-signed = mkSignedApp examples.hello-nsis;
          hello-msi-signed = mkSignedApp examples.hello-msi;
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          hello-pkg-signed = mkSignedApp examples.hello-pkg;
        }
      );

      checks = eachSystem (pkgs: import ./tests { inherit pkgs; });

      formatter = eachSystem (pkgs: pkgs.nixfmt-tree);

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.nil ];
        };
      });
    };
}
