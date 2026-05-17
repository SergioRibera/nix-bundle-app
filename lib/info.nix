# Normalises and validates the user-supplied `info` attrset by running it
# through `lib.evalModules` with the schema declared in ./schema.nix.
#
# Returns a frozen `meta` value: schema-typed user fields plus a handful of
# derived attrs (arch-mapped names, default bundleId / installDirName, the
# canonical target / format keys for use by format modules).
{ lib, utils }:

let
  schemaPath = ./schema.nix;

  normalize = userInfo: drv: target: format:
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
        if failed == [ ] then null
        else throw (
          "nix-bundle-app: ${toString (builtins.length failed)} "
          + "configuration assertion(s) failed:\n"
          + lib.concatMapStringsSep "\n" (a: "  - " + a.message) failed
        );

      derived = {
        bundleId =
          if cfg.bundleId != null then cfg.bundleId
          else "com.example.${utils.sanitizeName cfg.name}";
        installDirName =
          if cfg.installDirName != null then cfg.installDirName else cfg.name;
        inherit target format;
        debArch = utils.debArch target.arch;
        rpmArch = utils.rpmArch target.arch;
        archArch = utils.archArch target.arch;
        darwinArch = utils.darwinArch target.arch;
      };
    in
      # `builtins.seq assertionGuard X` forces the guard's evaluation
      # (potentially throwing) before returning `X`.
      builtins.seq assertionGuard (cfg // derived);
in
{
  inherit normalize;
  schema = schemaPath;
}
