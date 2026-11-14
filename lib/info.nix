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
          {
            _file = "info";
            config = userInfo;
          }
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

      # `1.2.0-alpha.1+build` split for package managers that reject `-`
      # in versions: deb and rpm sort `~` before the release, pacman takes
      # `_`, MSI and macOS bundles want plain numbers. Only the package
      # metadata uses these; file names keep `version`, since release hosts
      # rename assets with characters such as `~`.
      release = builtins.head (lib.splitString "+" cfg.version);
      versionParts = lib.splitString "-" release;
      numericVersion = builtins.head versionParts;
      prerelease =
        if builtins.length versionParts > 1 then
          lib.concatStringsSep "." (builtins.tail versionParts)
        else
          null;
      withPrerelease =
        sep: if prerelease == null then numericVersion else "${numericVersion}${sep}${prerelease}";

      derived = {
        inherit numericVersion;
        debVersion = withPrerelease "~";
        rpmVersion = withPrerelease "~";
        archVersion = withPrerelease "_";
        bundleId =
          if cfg.bundleId != null then cfg.bundleId else "com.example.${utils.sanitizeName cfg.name}";
        installDirName =
          if cfg.windows.installDirName != null then cfg.windows.installDirName else cfg.name;
        # "Name <email>" reads badly in "Apps & features"; keep the name.
        publisher =
          if cfg.windows.publisher != null then
            cfg.windows.publisher
          else
            lib.trim (builtins.head (lib.splitString "<" cfg.maintainer));
        displayName = if cfg.displayName != null then cfg.displayName else cfg.name;
        appBundleName = "${if cfg.displayName != null then cfg.displayName else cfg.name}.app";
        inherit target format;
        debArch = utils.debArch target.arch;
        rpmArch = utils.rpmArch target.arch;
        archArch = utils.archArch target.arch;
        darwinArch = utils.darwinArch target.arch;
      };
    in
    # Force assertion check before returning meta; warnings (renamed options)
    # print once per evaluation.
    builtins.seq assertionGuard (
      lib.foldr (w: acc: lib.warn "nix-bundle-app: ${w}" acc) (
        cfg
        // derived
        // {
          # freedesktop icon name: flatpak requires it to equal the app id.
          iconName = derived.bundleId;
        }
      ) cfg.warnings
    );
in
{
  inherit normalize;
  schema = schemaPath;
}
