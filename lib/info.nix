{ lib, utils }:

let
  schemaPath = ./schema.nix;

  normalize =
    userInfo: drv: target: format:
    let
      evaluated = lib.evalModules {
        modules = [
          schemaPath
          { _module.args = { inherit drv target format; }; }
          { config = userInfo; }
        ];
      };

      cfg = evaluated.config;

      failed = builtins.filter (a: !a.assertion) cfg.assertions;

      assertionGuard =
        if failed == [ ] then
          null
        else
          throw (
            "nix-bundle-app: ${toString (builtins.length failed)} "
            + "configuration assertion(s) failed:\n"
            + lib.concatMapStringsSep "\n" (a: "  - " + a.message) failed
          );

      derived = {
        bundleId =
          if cfg.bundleId != null then cfg.bundleId else "com.example.${utils.sanitizeName cfg.name}";
        installDirName = if cfg.installDirName != null then cfg.installDirName else cfg.name;
        displayName = if cfg.displayName != null then cfg.displayName else cfg.name;
        appBundleName = "${if cfg.displayName != null then cfg.displayName else cfg.name}.app";
        inherit target format;
        debArch = utils.debArch target.arch;
        rpmArch = utils.rpmArch target.arch;
        archArch = utils.archArch target.arch;
        darwinArch = utils.darwinArch target.arch;
      };
    in
    # Force assertion check before returning meta.
    builtins.seq assertionGuard (
      cfg
      // derived
      // {
        # freedesktop icon name: flatpak requires it to equal the app id.
        iconName = derived.bundleId;
      }
    );
in
{
  inherit normalize;
  schema = schemaPath;
}
