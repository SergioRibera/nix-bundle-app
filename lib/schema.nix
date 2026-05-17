{
  lib,
  drv,
  target,
  format,
  config,
  ...
}:

let
  inherit (lib) mkOption types literalExpression;

  desktopActionModule = {
    options = {
      name = mkOption {
        type = types.str;
        description = "Visible label for the action.";
        example = "Open in new window";
      };
      exec = mkOption {
        type = types.str;
        description = "Command-line executed when this action is selected.";
        example = "/opt/my-app/bin/my-app --new-window";
      };
      icon = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional icon name reference for this action.";
      };
    };
  };

  desktopEntryModule = {
    options = {
      name = mkOption {
        type = types.str;
        description = "Display name. Becomes the `Name=` field.";
        example = "My App";
      };
      exec = mkOption {
        type = types.str;
        description = "Command-line. Becomes the `Exec=` field. Supports `%F %U %f %u` placeholders.";
        example = "/opt/my-app/bin/my-app %F";
      };
      type = mkOption {
        type = types.enum [
          "Application"
          "Link"
          "Directory"
        ];
        default = "Application";
        description = "Entry kind. `Type=` field.";
      };
      genericName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Locale-independent generic name (e.g. `Web Browser`).";
      };
      comment = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Tooltip shown by the launcher.";
      };
      tryExec = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to a binary that must exist for the entry to be shown.";
      };
      icon = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Icon name reference (looked up via the icon theme).";
      };
      iconPath = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = ''
          Optional filesystem path to an icon file to ship with the bundle.
          When set, the file lands at `/usr/share/icons/hicolor/512x512/apps/<icon>.png`.
        '';
      };
      categories = mkOption {
        type = types.listOf types.str;
        default = [ "Utility" ];
        description = "XDG menu categories. Becomes `Categories=` (joined with `;`).";
        example = [
          "Development"
          "IDE"
        ];
      };
      keywords = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Search keywords. Becomes `Keywords=`.";
      };
      mimeTypes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "MIME types handled by this entry. Becomes `MimeType=`.";
      };
      terminal = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the launcher should open a terminal first.";
      };
      startupNotify = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Set `StartupNotify=` for startup-notification support.";
      };
      startupWMClass = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "WM_CLASS to associate this entry with its window.";
      };
      workingDirectory = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Working directory passed to `Exec`.";
      };
      noDisplay = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Hide the entry from menus while keeping it registered.";
      };
      hidden = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Mark as deleted at the user level.";
      };
      singleMainWindow = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Hint that the app has a single primary window.";
      };
      dbusActivatable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Whether the app can be activated via D-Bus.";
      };
      prefersNonDefaultGPU = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Hint that the app should run on the discrete GPU.";
      };
      actions = mkOption {
        type = types.attrsOf (types.submodule desktopActionModule);
        default = { };
        description = "Context-menu actions. Each becomes a `[Desktop Action <key>]` section.";
        example = literalExpression ''
          {
            "NewWindow" = { name = "New window"; exec = "/opt/app/bin/app --new"; };
          }
        '';
      };
      extra = mkOption {
        type = types.attrsOf (
          types.oneOf [
            types.str
            types.bool
            types.int
            (types.listOf types.str)
          ]
        );
        default = { };
        description = "Arbitrary extra keys to embed in `[Desktop Entry]`.";
        example = literalExpression ''{ "X-AppImage-Version" = "1.0"; }'';
      };
      fileName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Override the generated `.desktop` filename (without extension).";
      };
    };
  };

  systemdOverridesModule = {
    options = {
      unitOverrides = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        description = "Extra `[Unit]` fields to set/override.";
      };
      serviceOverrides = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        description = "Extra `[Service]` fields to set/override.";
      };
      installOverrides = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        description = "Extra `[Install]` fields to set/override.";
      };
      wantedBy = mkOption {
        type = types.listOf types.str;
        default = [ "multi-user.target" ];
        description = "Targets that pull this unit in via `WantedBy=`.";
      };
    };
  };

  launchdOverridesModule = {
    options = {
      label = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Override the `Label` plist key. Defaults to the service `name`.";
      };
      keepAlive = mkOption {
        type = types.bool;
        default = true;
        description = "Plist `KeepAlive`.";
      };
      runAtLoad = mkOption {
        type = types.bool;
        default = true;
        description = "Plist `RunAtLoad`.";
      };
      abandonProcessGroup = mkOption {
        type = types.bool;
        default = false;
        description = "Plist `AbandonProcessGroup`.";
      };
      throttleInterval = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Plist `ThrottleInterval` (seconds).";
      };
      processType = mkOption {
        type = types.nullOr (
          types.enum [
            "Background"
            "Standard"
            "Adaptive"
            "Interactive"
          ]
        );
        default = null;
        description = "Plist `ProcessType`.";
      };
    };
  };

  windowsServiceModule = {
    options = {
      serviceName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "`sc.exe` service name. Defaults to the service `name`.";
      };
      displayName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Friendly display name (services.msc).";
      };
      account = mkOption {
        type = types.enum [
          "LocalSystem"
          "LocalService"
          "NetworkService"
        ];
        default = "LocalSystem";
        description = "Service account (`obj=`).";
      };
      start = mkOption {
        type = types.enum [
          "auto"
          "demand"
          "disabled"
        ];
        default = "auto";
        description = "Startup type (`start=`).";
      };
      errorControl = mkOption {
        type = types.enum [
          "normal"
          "severe"
          "critical"
          "ignore"
        ];
        default = "normal";
        description = "Error-control level (`error=`).";
      };
      depends = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Names of services this one depends on.";
      };
    };
  };

  serviceModule = {
    options = {
      name = mkOption {
        type = types.str;
        description = "Service identifier (becomes systemd unit basename / launchd Label / sc.exe service name).";
        example = "my-agent";
      };
      exec = mkOption {
        type = types.str;
        description = "Command-line. Parsed as `<binary> [args...]`.";
        example = "/opt/my-app/bin/my-app --daemon";
      };
      description = mkOption {
        type = types.str;
        default = "";
        description = "Human description.";
      };
      user = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Run as this user (linux/mac).";
      };
      group = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Run with this group (linux/mac).";
      };
      workingDirectory = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Service working directory.";
      };
      environment = mkOption {
        type = types.attrsOf (types.either types.str types.int);
        default = { };
        description = "Environment variables for the service.";
        example = {
          LOG_LEVEL = "info";
          PORT = 8080;
        };
      };
      restart = mkOption {
        type = types.enum [
          "always"
          "on-failure"
          "no"
        ];
        default = "on-failure";
        description = "Restart policy.";
      };
      restartSec = mkOption {
        type = types.ints.unsigned;
        default = 5;
        description = "Seconds to wait between restarts.";
      };
      startAtBoot = mkOption {
        type = types.bool;
        default = true;
        description = "Enable + start at boot.";
      };
      after = mkOption {
        type = types.listOf types.str;
        default = [ "network.target" ];
        description = "systemd ordering constraint.";
      };
      requires = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "systemd hard-dependency constraint.";
      };
      wants = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "systemd soft-dependency constraint.";
      };
      type = mkOption {
        type = types.enum [
          "simple"
          "forking"
          "oneshot"
          "notify"
          "dbus"
        ];
        default = "simple";
        description = "systemd service Type.";
      };
      stdout = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Standard output redirect (file path).";
      };
      stderr = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Standard error redirect (file path).";
      };
      systemd = mkOption {
        type = types.submodule systemdOverridesModule;
        default = { };
        description = "systemd-specific overrides.";
      };
      launchd = mkOption {
        type = types.submodule launchdOverridesModule;
        default = { };
        description = "launchd-specific tuning.";
      };
      windows = mkOption {
        type = types.submodule windowsServiceModule;
        default = { };
        description = "Windows-service-specific settings.";
      };
    };
  };

  dependsModule = {
    options = {
      deb = mkOption {
        type = types.listOf types.str;
        default = [ "libc6" ];
        description = "Debian `Depends:` list.";
      };
      rpm = mkOption {
        type = types.listOf types.str;
        default = [ "glibc" ];
        description = "RPM `Requires:` list.";
      };
      archlinux = mkOption {
        type = types.listOf types.str;
        default = [ "glibc" ];
        description = "Arch Linux `depends` list.";
      };
      brew = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Homebrew `depends_on` formula names.";
      };
      nsis = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "(reserved; not yet used by the NSIS format).";
      };
      debRecommends = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Debian `Recommends:` list.";
      };
      rpmRecommends = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "RPM `Recommends:` list.";
      };
      archlinuxOptional = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Arch Linux `optdepends` list.";
      };
      rpmGroup = mkOption {
        type = types.str;
        default = "Applications/System";
        description = "RPM `Group:` field.";
      };
    };
  };
in
{
  options = {
    name = mkOption {
      type = types.str;
      default = drv.pname or drv.name or "app";
      defaultText = literalExpression "drv.pname or drv.name or \"app\"";
      description = "Package name. Drives install paths, manifest fields and output filenames.";
      example = "my-app";
    };

    version = mkOption {
      type = types.str;
      default = drv.version or "0.0.0";
      defaultText = literalExpression "drv.version or \"0.0.0\"";
      description = "Semantic version. Appears in manifest fields and bundle filenames.";
      example = "1.2.3";
    };

    description = mkOption {
      type = types.str;
      default = drv.meta.description or "";
      defaultText = literalExpression "drv.meta.description or \"\"";
      description = "Short package description.";
    };

    summary = mkOption {
      type = types.str;
      default = drv.meta.description or "";
      defaultText = literalExpression "drv.meta.description or \"\"";
      description = "One-line summary (deb Description, rpm Summary, etc).";
    };

    longDescription = mkOption {
      type = types.str;
      default = drv.meta.longDescription or (drv.meta.description or "");
      defaultText = literalExpression "drv.meta.longDescription or drv.meta.description";
      description = "Multi-paragraph description (rpm %description, AppImage, etc).";
    };

    homepage = mkOption {
      type = types.str;
      default = drv.meta.homepage or "";
      defaultText = literalExpression "drv.meta.homepage or \"\"";
      description = "Project homepage URL.";
    };

    license = mkOption {
      type = types.str;
      default =
        let
          l = drv.meta.license or null;
        in
        if l == null then
          "Unspecified"
        else if builtins.isList l then
          lib.concatMapStringsSep " AND " (x: x.spdxId or x.fullName or (toString x)) l
        else
          l.spdxId or l.fullName or (toString l);
      defaultText = literalExpression "derived from drv.meta.license";
      description = "License identifier — SPDX preferred.";
      example = "MIT";
    };

    maintainer = mkOption {
      type = types.str;
      default = "Unspecified <noreply@example.com>";
      description = "Maintainer in `Name <email>` form.";
      example = "Jane Doe <jane@example.com>";
    };

    section = mkOption {
      type = types.str;
      default = "utils";
      description = "Debian `Section:` field.";
    };

    priority = mkOption {
      type = types.str;
      default = "optional";
      description = "Debian `Priority:` field.";
    };

    desktopEntries = mkOption {
      type = types.listOf (types.submodule desktopEntryModule);
      default = [ ];
      description = "Declarative XDG Desktop Entry definitions to ship on linux bundles. The first entry is also used as the AppImage top-level `.desktop`.";
    };

    services = mkOption {
      type = types.listOf (types.submodule serviceModule);
      default = [ ];
      description = ''
        Cross-OS background services. Materialised as systemd unit (`/lib/systemd/system/`)
        on linux, launchd plist (`/Library/LaunchDaemons/`) on macOS `.pkg`, and
        `sc.exe`-based registration via shipped batch files on Windows.
      '';
    };

    binDir = mkOption {
      type = types.str;
      default = "bin";
      description = "Subdir under `/opt/<name>/` where binaries land. Rarely needs changing.";
    };

    libDir = mkOption {
      type = types.str;
      default = "lib";
      description = "Subdir under `/opt/<name>/` where bundled libs land.";
    };

    bundleId = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "macOS `CFBundleIdentifier`. Defaults to `com.example.<name>` when null.";
      example = "com.acme.my-app";
    };

    bundleSignature = mkOption {
      type = types.str;
      default = "????";
      description = "macOS `CFBundleSignature` (4-char OSType code).";
    };

    macOsIcon = mkOption {
      type = types.nullOr (types.either types.path types.str);
      default = null;
      description = "Path to a `.icns` icon file. Copied into `Contents/Resources/AppIcon.icns` and referenced by `CFBundleIconFile`.";
      example = literalExpression "./assets/app.icns";
    };

    minimumSystemVersion = mkOption {
      type = types.str;
      default = "10.13";
      description = "macOS minimum system version (`LSMinimumSystemVersion`).";
    };

    installDirName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Windows install-dir name under `%ProgramFiles%`. Defaults to `name` when null.";
    };

    downloadUrl = mkOption {
      type = types.str;
      default = "";
      description = "Public URL where the tarball will be hosted. Embedded in the brew formula's `url`.";
    };

    keepInterpreter = mkOption {
      type = types.bool;
      default = false;
      description = "If true, do not rewrite the ELF dynamic loader path on linux bundles (advanced).";
    };

    appImageRuntime = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Override the AppImage type2 runtime binary. Defaults to a pinned `fetchurl` of `AppImage/type2-runtime`.";
      example = literalExpression ''pkgs.fetchurl { url = "..."; sha256 = "..."; }'';
    };

    appImageTerminal = mkOption {
      type = types.bool;
      default = false;
      description = "If true, the AppImage's bundled `.desktop` sets `Terminal=true` (CLI tools).";
    };

    msiUpgradeCode = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Pinned `UpgradeCode` GUID for the MSI. Derived deterministically from
        `bundleId` if null — **pin this once you cut a release**, otherwise
        future MSIs won't be recognised as upgrades.
      '';
      example = "12345678-90AB-CDEF-1234-567890ABCDEF";
    };

    depends = mkOption {
      type = types.submodule dependsModule;
      default = { };
      description = "Per-format runtime dependencies surfaced in manifests.";
    };

    assertions = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            assertion = mkOption { type = types.bool; };
            message = mkOption { type = types.str; };
          };
        }
      );
      default = [ ];
      internal = true;
      visible = false;
      description = "Internal: cross-field consistency checks. Failures throw at evaluation time.";
    };
  };

  config = {
    assertions = [
      {
        assertion = config.name != "";
        message = "info.name must be a non-empty string.";
      }
      {
        assertion = config.version != "";
        message = "info.version must be a non-empty string.";
      }
      {
        assertion =
          config.appImageRuntime != null
          || format != "appimage"
          || target.arch == "x86_64"
          || target.arch == "aarch64";
        message =
          "AppImage runtime auto-fetch is only pinned for x86_64 and aarch64. "
          + "Supply info.appImageRuntime for arch='${target.arch}'.";
      }
      {
        assertion = config.services == [ ] || format != "appimage";
        message =
          "info.services has no effect for the AppImage format — AppImages are "
          + "single-binary user apps, not system services. Use a deb/rpm/archlinux "
          + "bundle for service installation on linux.";
      }
      {
        assertion = lib.all (s: s.exec != "") config.services;
        message = "Every entry in info.services must set a non-empty `exec`.";
      }
      {
        assertion = lib.all (s: s.name != "") config.services;
        message = "Every entry in info.services must set a non-empty `name`.";
      }
      {
        assertion = lib.all (e: e.name != "" && e.exec != "") config.desktopEntries;
        message = "Every entry in info.desktopEntries must set non-empty `name` and `exec`.";
      }
      {
        assertion =
          config.msiUpgradeCode == null
          ||
            builtins.match "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" config.msiUpgradeCode
            != null;
        message =
          "info.msiUpgradeCode must be a GUID of shape "
          + "'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX' (got '${toString config.msiUpgradeCode}').";
      }
    ];
  };
}
