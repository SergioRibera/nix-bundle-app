{
  description = "nix-bundle-app — turn any Nix derivation into native installers (deb, rpm, archlinux, .app, .dmg, brew, NSIS, zip, tarball)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # Thin flake wrapper around the canonical overlay. Workflows + flake
  # consumers get `.#foo` targets and a devshell; everything substantive
  # lives in `overlay.nix` and should be consumed as an overlay by apps
  # that don't want a flake dependency.
  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      overlay = import ./overlay.nix;
      # Back-compat shim for consumers that imported the old
      # `nix-bundle-app.lib.mkLib pkgs` entry point. Returns the same
      # bundler attrset they used to get.
      mkLib = pkgs: (pkgs.extend overlay).nixBundleApp;
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.extend overlay;
        bundler = pkgs.nixBundleApp;
        examples = import ./examples { inherit pkgs; };
        tests = import ./tests { inherit pkgs; };
      in
      {
        legacyPackages = pkgs;

        lib = bundler;

        packages = examples // {
          default = examples.hello-tar-gz;
          docs = import ./lib/docs.nix { inherit pkgs; };
        };

        # `nix run .#hello-deb-signed -- ./dist` builds + signs in one shot.
        # The bundle needs `info.signing.<os>.enable = true`; secrets come
        # from the caller's env vars (P12_PASSWORD / GPG_KEY_ID / …).
        apps =
          let
            mkSignedApp =
              bundle:
              let
                drv = bundler.signedApp { inherit bundle; };
              in
              {
                type = "app";
                program = "${drv}/bin/${drv.name}";
              };
          in
          {
            hello-deb-signed = mkSignedApp examples.hello-deb;
            hello-rpm-signed = mkSignedApp examples.hello-rpm;
            hello-pkg-signed = mkSignedApp examples.hello-pkg;
            hello-nsis-signed = mkSignedApp examples.hello-nsis;
            hello-msi-signed = mkSignedApp examples.hello-msi;
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
      overlays.default = overlay;
      overlays.nixBundleApp = overlay;

      lib = { inherit mkLib; };

      templates.default = {
        path = ./examples/hello;
        description = "Minimal nix-bundle-app consumer";
      };
    };
}
