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

  urlSchemeModule = {
    options = {
      scheme = mkOption {
        type = types.strMatching "[a-z][a-z0-9+.-]*";
        example = "hello";
        description = "URL scheme without `:` or `//`, e.g. `hello` for `hello://open?x=1`.";
      };
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "What the scheme is, for the system's UI (`URL:<name>` on Windows). Defaults to `displayName`.";
      };
    };
  };

  appstreamModule = {
    options = {
      enable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Ship the metainfo file. Defaults to on when `desktopEntries` is non-empty.";
      };
      releaseDate = mkOption {
        type = types.nullOr (types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}");
        default = null;
        example = "2026-11-14";
        description = "Date of this `version` (`YYYY-MM-DD`). Without it the metainfo lists no release, since AppStream needs one per release and a build has no reproducible \"today\".";
      };
      metadataLicense = mkOption {
        type = types.str;
        default = "CC0-1.0";
        description = "SPDX license of the metainfo file itself (`metadata_license`). Flathub accepts CC0-1.0, CC-BY-*, FSFAP and MIT.";
      };
      screenshots = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              image = mkOption {
                type = types.str;
                description = "Public URL of the screenshot.";
              };
              caption = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Short caption.";
              };
            };
          }
        );
        default = [ ];
        description = "Screenshots for software centers; the first is the default one.";
      };
    };
  };

  fileAssociationModule = {
    options = {
      id = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Uniform Type Identifier on macOS and ProgID on Windows for an
          exported type. Use the system UTI for well-known types
          (`com.adobe.pdf`, `public.plain-text`). Required when `exported = true`.
        '';
        example = "org.example.hello.document";
      };
      name = mkOption {
        type = types.str;
        description = "Human-readable type name (`CFBundleTypeName`, MIME `<comment>`, Windows `FriendlyTypeName`).";
        example = "Hello document";
      };
      extensions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "File extensions without the leading dot.";
        example = [ "hello" ];
      };
      mimeTypes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "MIME types of the type. Linux matches desktop entries to files by these.";
        example = [ "application/x-hello" ];
      };
      role = mkOption {
        type = types.enum [
          "viewer"
          "editor"
        ];
        default = "viewer";
        description = "Whether the app only opens (`viewer`) or also saves (`editor`) the type. macOS `CFBundleTypeRole`.";
      };
      rank = mkOption {
        type = types.enum [
          "owner"
          "default"
          "alternate"
        ];
        default = "alternate";
        description = ''
          How strongly the app claims the type. macOS `LSHandlerRank`; on
          Windows `owner` also makes the app the default handler of every
          extension, the other ranks only add it to "Open with".
        '';
      };
      exported = mkOption {
        type = types.bool;
        default = false;
        description = ''
          The app defines this type. macOS gets a `UTExportedTypeDeclarations`
          entry and Linux a shared-mime-info package declaring the MIME types
          with their extension globs.
        '';
      };
      conformsTo = mkOption {
        type = types.listOf types.str;
        default = [ "public.data" ];
        description = "macOS only: parent UTIs of a declared type (`UTTypeConformsTo`).";
        example = [
          "public.data"
          "public.content"
        ];
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

  signingDarwinModule = {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Generate a `sign.sh` next to darwin artifacts that drives `rcodesign`.";
      };
      p12File = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = ''
          Path to a `.p12` developer-id signing identity. Can be a nix store
          path (read at script-runtime) or an absolute host path. Override at
          runtime via `P12_FILE=...` env var.
        '';
      };
      teamId = mkOption {
        type = types.str;
        default = "";
        description = "Apple Team ID (10-char). Embedded as `--team-name`. Override via `TEAM_ID`.";
      };
      hardenedRuntime = mkOption {
        type = types.bool;
        default = true;
        description = "Set the hardened-runtime code-signature flag (`--code-signature-flags runtime`).";
      };
      entitlements = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = "Path to an `entitlements.plist` to embed.";
      };
    };
  };

  signingWindowsModule = {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Generate a `sign.sh` next to windows artifacts that drives `osslsigncode`.";
      };
      pkcs12File = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = "Path to a `.pfx`/`.p12` Authenticode signing cert. Override via `PKCS12_FILE`.";
      };
      timestampUrl = mkOption {
        type = types.str;
        default = "http://timestamp.sectigo.com";
        description = "RFC 3161 timestamp authority. Override via `TIMESTAMP_URL`.";
      };
      description = mkOption {
        type = types.str;
        default = "";
        description = "Embedded `-n` description shown in signature properties.";
      };
      url = mkOption {
        type = types.str;
        default = "";
        description = "Embedded `-i` URL shown in signature properties.";
      };
    };
  };

  signingLinuxModule = {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Generate a `sign.sh` next to linux artifacts that drives GPG / dpkg-sig / rpmsign.";
      };
      keyId = mkOption {
        type = types.str;
        default = "";
        description = "GPG key fingerprint or short id used as `--local-user`. Override via `GPG_KEY_ID`.";
      };
      style = mkOption {
        type = types.enum [
          "detached"
          "embedded"
        ];
        default = "detached";
        description = ''
          `detached` → emits `<artifact>.sig` next to the bundle (works for any format).
          `embedded` → uses `dpkg-sig` (deb) or `rpmsign --addsign` (rpm) to embed
          the signature inside the package. Ignored for appimage/archlinux/tar*.
        '';
      };
    };
  };

  signingModule = {
    options = {
      darwin = mkOption {
        type = types.submodule signingDarwinModule;
        default = { };
        description = "Per-platform signing settings — darwin (`rcodesign`).";
      };
      windows = mkOption {
        type = types.submodule signingWindowsModule;
        default = { };
        description = "Per-platform signing settings — windows (`osslsigncode`).";
      };
      linux = mkOption {
        type = types.submodule signingLinuxModule;
        default = { };
        description = "Per-platform signing settings — linux (GPG / dpkg-sig / rpmsign).";
      };
    };
  };

  flatpakModule = {
    options = {
      runtime = mkOption {
        type = types.str;
        default = "org.freedesktop.Platform";
        description = "Flatpak runtime to target (e.g. `org.freedesktop.Platform`, `org.gnome.Platform`).";
      };
      runtimeVersion = mkOption {
        type = types.str;
        default = "23.08";
        description = "Runtime version string.";
      };
      sdk = mkOption {
        type = types.str;
        default = "org.freedesktop.Sdk";
        description = "SDK paired with `runtime` for the build step.";
      };
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Name of the binary `flatpak run <appid>` invokes. Defaults to `info.name`.";
      };
      finishArgs = mkOption {
        type = types.listOf types.str;
        default = [
          "--share=ipc"
          "--socket=wayland"
          "--socket=fallback-x11"
          "--device=dri"
        ];
        description = ''
          Sandbox permission flags passed to `flatpak-builder` via the
          manifest's `finish-args`. Tune for GUI vs CLI vs networked apps.
        '';
      };
      extraModules = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = ''
          Extra `modules` entries appended to the generated manifest. Each
          should be an attrset matching the flatpak-builder schema (raw YAML
          struct: `{ name = ...; buildsystem = ...; sources = ...; }`).
        '';
      };
    };
  };

  snapModule = {
    options = {
      base = mkOption {
        type = types.str;
        default = "core22";
        description = "Snap base. `core22` ↔ Ubuntu 22.04 LTS.";
      };
      grade = mkOption {
        type = types.enum [
          "stable"
          "devel"
        ];
        default = "stable";
        description = "Snap grade (devel snaps may not be promoted past edge/beta).";
      };
      confinement = mkOption {
        type = types.enum [
          "strict"
          "classic"
          "devmode"
        ];
        default = "strict";
        description = "Sandbox confinement level. `classic` requires Snap Store review.";
      };
      plugs = mkOption {
        type = types.listOf types.str;
        default = [
          "home"
          "network"
        ];
        description = "Interfaces (plugs) the app consumes.";
      };
      summary = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Snap summary line. Defaults to `info.summary`.";
      };
    };
  };

  archlinuxModule = {
    options = {
      output = mkOption {
        type = types.enum [
          "pkg"
          "aur"
          "both"
        ];
        default = "both";
        description = ''
          Selects what the `archlinux` format emits:
          - `pkg`  → only the binary `*.pkg.tar.zst` (install with `pacman -U`).
          - `aur`  → only an AUR-pushable `PKGBUILD` + `.SRCINFO` + source tarball.
          - `both` → both, with AUR layout under `aur/`.
        '';
      };
    };
  };

  productbuildModule = {
    options = {
      title = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Installer window title. Defaults to `info.name` when null.";
      };
      organization = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Reverse-DNS organization id (top half of `bundleId`).";
      };
      welcome = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = "Path to a welcome screen file (rtf/rtfd/html/txt).";
        example = literalExpression "./Resources/welcome.html";
      };
      license = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = "Path to a license file shown on the License screen.";
      };
      readme = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = "Path to a readme/release-notes file shown on the Readme screen.";
      };
      conclusion = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = "Path to a conclusion screen file shown after install completes.";
      };
      background = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = "Optional installer background image (png/tiff/jpg).";
      };
      allowCustomize = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If true the installer offers the Customize button. Useful when the
          distribution contains more than one component.
        '';
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

  macosModule = {
    options = {
      icns = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = ''
          `.icns` that replaces the one rendered from `icon`. Copied into
          `Contents/Resources/AppIcon.icns` and referenced by `CFBundleIconFile`.
        '';
        example = literalExpression "./assets/app.icns";
      };
      bundleSignature = mkOption {
        type = types.str;
        default = "????";
        description = "`CFBundleSignature` (4-char OSType code), also written to `PkgInfo`.";
      };
      minimumSystemVersion = mkOption {
        type = types.str;
        default = "10.13";
        description = "`LSMinimumSystemVersion`.";
      };
      buildVersion = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          `CFBundleVersion`, the build number. Defaults to the numeric
          `version`, which is always `CFBundleShortVersionString`.
        '';
        example = "42";
      };
      category = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "`LSApplicationCategoryType`: where Finder and the App Store file the app.";
        example = "public.app-category.developer-tools";
      };
      copyright = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "`NSHumanReadableCopyright`, shown in the About window and in Finder.";
        example = "© 2026 Acme Inc.";
      };
      infoPlist = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = ''
          Extra `Info.plist` keys for anything without its own option. Applied
          last, so they override generated keys. Values are strings, booleans,
          integers, lists and attribute sets (dictionaries).
        '';
        example = literalExpression ''
          {
            LSUIElement = true;
            NSSupportsAutomaticGraphicsSwitching = true;
          }
        '';
      };
      entitlements = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = ''
          Code-signing entitlements, rendered to a plist that `sign.sh` embeds.
          Leave empty to use `signing.darwin.entitlements` (a file) instead;
          setting both is an error.
        '';
        example = literalExpression ''
          { "com.apple.security.network.client" = true; }
        '';
      };
    };
  };

  localNetworkModule = {
    options = {
      reason = mkOption {
        type = types.str;
        description = ''
          Why the app talks to devices on the local network, shown in the
          permission prompt. macOS (`NSLocalNetworkUsageDescription`): without
          it the system refuses LAN traffic without asking, and sockets fail
          with "No route to host".
        '';
        example = "Finds and streams from apps running on your network.";
      };
      udp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = ''
          UDP ports the app receives on. Windows: the MSI and NSIS installers
          add inbound firewall rules for them (machine-wide installs only),
          so Defender neither blocks nor asks on first run.
        '';
        example = [ 7701 ];
      };
      tcp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = "TCP ports the app listens on; like `udp`.";
        example = [ 8080 ];
      };
    };
  };

  windowsShortcutsModule = {
    options = {
      startMenu = mkOption {
        type = types.bool;
        default = true;
        description = "Start-menu shortcut.";
      };
      desktop = mkOption {
        type = types.bool;
        default = false;
        description = "Desktop shortcut.";
      };
    };
  };

  windowsArpModule = {
    options = {
      helpUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Support link (`HelpLink` / `ARPHELPLINK`).";
      };
      updateUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Where updates are published (`URLUpdateInfo` / `ARPURLUPDATEINFO`).";
      };
      contact = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Support contact (`Contact` / `ARPCONTACT`).";
      };
      comments = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Free text (`Comments` / `ARPCOMMENTS`).";
      };
    };
  };

  windowsModule = {
    options = {
      installDirName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Install directory name: under `%ProgramFiles%`, or under
          `%LOCALAPPDATA%\Programs` for a per-user install. Defaults to `name`.
        '';
      };
      upgradeCode = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Pinned `UpgradeCode` GUID for the MSI. Derived deterministically from
          `bundleId` if null — **pin this once you cut a release**, otherwise
          future MSIs won't be recognised as upgrades.
        '';
        example = "12345678-90AB-CDEF-1234-567890ABCDEF";
      };
      publisher = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Shown as the publisher in "Apps & features" and the MSI
          `Manufacturer`. Defaults to `maintainer` without the `<email>`.
        '';
        example = "Acme Inc.";
      };
      scope = mkOption {
        type = types.enum [
          "perMachine"
          "perUser"
        ];
        default = "perMachine";
        description = ''
          `perMachine`: `%ProgramFiles%`, needs admin, for every user.
          `perUser`: `%LOCALAPPDATA%\Programs`, no admin prompt, for the
          installing user only (firewall rules need admin, so none are added).
        '';
      };
      shortcuts = mkOption {
        type = types.submodule windowsShortcutsModule;
        default = { };
        description = "Shortcuts the installers create.";
      };
      arp = mkOption {
        type = types.submodule windowsArpModule;
        default = { };
        description = ''
          Extra "Apps & features" (Add/Remove Programs) fields. `homepage`
          already fills the about link.
        '';
      };
    };
  };

  permissionsModule = {
    options.network.local = mkOption {
      type = types.nullOr (types.submodule localNetworkModule);
      default = null;
      description = ''
        The app reaches devices on the local network: LAN broadcast or
        multicast discovery, or connections to other hosts on the LAN.

        - macOS bundles: `NSLocalNetworkUsageDescription` from `reason`.
        - Windows (MSI, NSIS, per machine): an inbound firewall rule for
          `udp` / `tcp` ports, removed on uninstall.
        - flatpak: `--share=network`; snap: `network`, plus `network-bind`
          when ports are declared.
      '';
    };
  };
in
{
  # The macOS- and Windows-only options moved under `macos` and `windows`;
  # the old names keep working with a deprecation warning.
  imports = [
    (lib.mkRenamedOptionModule [ "macOsIcon" ] [ "macos" "icns" ])
    (lib.mkRenamedOptionModule [ "bundleSignature" ] [ "macos" "bundleSignature" ])
    (lib.mkRenamedOptionModule [ "minimumSystemVersion" ] [ "macos" "minimumSystemVersion" ])
    (lib.mkRenamedOptionModule [ "installDirName" ] [ "windows" "installDirName" ])
    (lib.mkRenamedOptionModule [ "msiUpgradeCode" ] [ "windows" "upgradeCode" ])
  ];

  options = {
    name = mkOption {
      type = types.str;
      default = drv.pname or drv.name or "app";
      defaultText = literalExpression "drv.pname or drv.name or \"app\"";
      description = "Package name. Drives install paths, manifest fields and output filenames.";
      example = "my-app";
    };

    displayName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Human-facing app name: the macOS `.app` bundle and `CFBundleName`,
        the DMG volume, the Windows installer, Start menu shortcut and
        "Apps & features" entry. Defaults to `name`, which keeps driving
        every path, package name and registry key.
      '';
      example = "My App";
    };

    icon = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Square PNG (1024 px recommended) every format derives its icon from:
        freedesktop hicolor PNGs named after `bundleId` (and the default
        `Icon=` of desktop entries, the AppImage `.DirIcon`, the snap icon),
        the `.icns` of a `.app` (unless `macOsIcon` is set) and the `.ico`
        of the NSIS / MSI installers and their shortcuts.
      '';
      example = literalExpression "./assets/icon.png";
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

    fileAssociations = mkOption {
      type = types.listOf (types.submodule fileAssociationModule);
      default = [ ];
      description = ''
        File types the app opens, so installed bundles show it under "Open
        with" and claim the types it defines.

        - linux: every MIME type joins `MimeType=` of the desktop entries that
          set no `mimeTypes` of their own (`%F` is appended to an `exec`
          without a field code), and exported types ship
          `/usr/share/mime/packages/<bundleId>.xml`.
        - macOS `.app` (and dmg, pkg, productbuild): `CFBundleDocumentTypes`,
          plus `UTExportedTypeDeclarations` for exported types and
          `UTImportedTypeDeclarations` for other non-system ids.
        - Windows (MSI, NSIS): one ProgID per association with
          `shell\open\command`, listed under `OpenWithProgids` of every
          extension, and the extension default when `rank = "owner"`.
          The ProgID is `id` for exported types, `<bundleId>.<first extension>`
          otherwise.
      '';
      example = literalExpression ''
        [
          {
            id = "org.example.hello.document";
            name = "Hello document";
            extensions = [ "hello" ];
            mimeTypes = [ "application/x-hello" ];
            role = "editor";
            rank = "owner";
            exported = true;
          }
          {
            id = "com.adobe.pdf";
            name = "PDF document";
            extensions = [ "pdf" ];
            mimeTypes = [ "application/pdf" ];
          }
        ]
      '';
    };

    urlSchemes = mkOption {
      type = types.listOf (
        types.coercedTo types.str (scheme: { inherit scheme; }) (types.submodule urlSchemeModule)
      );
      default = [ ];
      description = ''
        URL schemes the app handles (`hello://…` links). A plain string is
        the scheme.

        - linux: `x-scheme-handler/<scheme>` joins `MimeType=` of the desktop
          entries that set no `mimeTypes` of their own; an `exec` without a
          field code gets `%U`, so files arrive as `file://` URIs too.
        - macOS `.app` (and dmg, pkg, productbuild): `CFBundleURLTypes`.
        - Windows (MSI, NSIS): `Software\Classes\<scheme>` with
          `URL Protocol` and `shell\open\command` passing the URL as `%1`.
      '';
      example = literalExpression ''[ "hello" { scheme = "hello-dev"; name = "Hello (dev)"; } ]'';
    };

    appstream = mkOption {
      type = types.submodule appstreamModule;
      default = { };
      description = ''
        AppStream metainfo at `/usr/share/metainfo/<bundleId>.metainfo.xml`,
        the listing GNOME Software, KDE Discover and Flathub show: id,
        names, description (blank lines split paragraphs), license,
        developer (`windows.publisher`'s default: `maintainer` without the
        email), homepage, launchable desktop entry, release and screenshots.
        Shipped by deb, rpm, archlinux, tar, flatpak and AppImage.
      '';
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

    extraFiles = mkOption {
      type = types.attrsOf (types.either types.path types.str);
      default = { };
      description = ''
        Extra files dropped into the staged tree at fixed absolute paths.
        Keys are the destination paths inside the installed package
        (e.g. `/lib/udev/rules.d/61-myapp.rules`). Values are either a
        Nix path / store path (copied verbatim) or an inline string
        (written directly into the destination at build time).

        Honoured by the linux installer formats (`deb`, `rpm`,
        `archlinux`). Ignored by `appimage` / `flatpak` / `snap` (no
        system install location) and by darwin/windows formats.

        If any entry lands under `/lib/udev/rules.d/`,
        `/usr/lib/udev/rules.d/`, or `/etc/udev/rules.d/`, the
        post-install hook will additionally run `udevadm control
        --reload-rules && udevadm trigger` (best-effort).
      '';
      example = literalExpression ''
        {
          "/lib/udev/rules.d/61-myapp.rules" = ./contrib/myapp.rules;
          "/etc/modprobe.d/myapp.conf" = "options myapp_mod debug=1\n";
          "/etc/modules-load.d/myapp.conf" = ./contrib/modules-load.conf;
        }
      '';
    };

    autoDepends = mkOption {
      type = types.bool;
      default = true;
      description = ''
        For linux package formats (`deb`, `rpm`, `archlinux`), scan the staged
        binaries' `NEEDED` SONAMEs and add matching distro packages to the
        manifest's `Depends` / `Requires` / `depends` field. The mapping table
        ships with the library; user-supplied `info.depends.<distro>` always wins
        — auto-detected entries are merged in addition, never replacing.
      '';
    };

    bundleLibs = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When `true` (the default), Linux package formats copy every
        non-glibc runtime library out of the derivation's Nix closure
        into `/opt/<name>/lib/` and rewrite the binaries' `RPATH` to
        `$ORIGIN/../lib` so the bundled copies resolve first. The
        produced bundles are self-contained at the cost of being large.

        Set to `false` to ship the binaries naked: no `lib/` dir gets
        copied, no `RPATH` rewrite happens, and the dynamic linker
        resolves SONAMEs through the system loader cache. Pair with
        `autoDepends = true` (or hand-rolled `info.depends.<distro>`)
        so the produced `.deb` / `.rpm` / `PKGBUILD` declares the
        runtime libs as install-time deps — the target distro's package
        manager pulls them in alongside the binary.

        Tarball / archive formats ignore this flag (they have no
        manifest to declare deps with), so they still bundle.
      '';
    };

    hostLibs = mkOption {
      type = types.listOf types.str;
      default = [
        # GPU / driver stack: glvnd and the Vulkan loader locate vendor
        # drivers through paths compiled in at build time, which point
        # into /nix/store — Nix's copies find no driver on other distros.
        "libGL"
        "libGLX"
        "libGLdispatch"
        "libOpenGL"
        "libEGL"
        "libGLESv1_CM"
        "libGLESv2"
        "libvulkan"
        "libgbm"
        "libdrm"
        "libnvidia"
        "libcuda"
        "libva"
        "libvdpau"
        # Config/data lookups compiled to /nix/store paths: fonts.conf,
        # XKB keymaps, X locale db, ALSA config. freetype rides along
        # with fontconfig so both come from the same build.
        "libfontconfig"
        "libfreetype"
        "libxkbcommon"
        "libX11"
        "libxcb"
        "libasound"
      ];
      description = ''
        Library name prefixes that Linux bundles never copy out of the Nix
        closure; the target's own copies are used instead. A prefix
        matches `<prefix>.so*`, `<prefix>-*.so*` and `<prefix>_*.so*`
        (so `libxcb` also covers `libxcb-xkb`, `libX11` covers
        `libX11-xcb`).

        The defaults are libraries every desktop distro ships and whose
        Nix builds break off-Nix: GPU driver loaders (glvnd, Vulkan,
        GBM) and libraries that read config or data from compiled-in
        store paths (fontconfig, xkbcommon, X11 locales, ALSA). Package
        formats still declare them as dependencies through
        `autoDepends`.

        Applies wherever libs are bundled (`deb`/`rpm`/`archlinux` with
        `bundleLibs`, `appimage`, archives, and the payload `flatpak` /
        `snap` stage). Setting it replaces the default list; `[ ]` gives
        a fully self-contained bundle.
      '';
      example = [
        "libGL"
        "libEGL"
        "libvulkan"
      ];
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
      description = ''
        Reverse-DNS app id: macOS `CFBundleIdentifier`, flatpak app id, icon
        and MIME package name on linux, and the seed of the MSI `UpgradeCode`.
        Defaults to `com.example.<name>` when null.
      '';
      example = "com.acme.my-app";
    };

    macos = mkOption {
      type = types.submodule macosModule;
      default = { };
      description = "macOS-only settings: the `.app` bundle's `Info.plist`, icon override and entitlements.";
    };

    permissions = mkOption {
      type = types.submodule permissionsModule;
      default = { };
      description = ''
        What the app needs from the system, declared once. Each format turns
        it into its own form: usage descriptions in the macOS `Info.plist`.
      '';
    };

    windows = mkOption {
      type = types.submodule windowsModule;
      default = { };
      description = "Windows-only settings for the MSI and NSIS installers.";
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

    depends = mkOption {
      type = types.submodule dependsModule;
      default = { };
      description = "Per-format runtime dependencies surfaced in manifests.";
    };

    productbuild = mkOption {
      type = types.submodule productbuildModule;
      default = { };
      description = ''
        Settings for the macOS `productbuild` distribution format. Drives the
        welcome / license / readme / conclusion screens and the installer chrome.
      '';
    };

    archlinux = mkOption {
      type = types.submodule archlinuxModule;
      default = { };
      description = "Settings for the `archlinux` format (binary pkg vs AUR layout).";
    };

    flatpak = mkOption {
      type = types.submodule flatpakModule;
      default = { };
      description = "Settings for the `flatpak` format (manifest + source layout).";
    };

    snap = mkOption {
      type = types.submodule snapModule;
      default = { };
      description = "Settings for the `snap` format (`snapcraft.yaml` + source layout).";
    };

    signing = mkOption {
      type = types.submodule signingModule;
      default = { };
      description = ''
        Codesigning hooks. Bundles always build unsigned; when an entry is
        `enable = true` the corresponding format also drops a turnkey
        `sign.sh` next to the artifact, ready to run with secrets supplied
        via env vars (`P12_PASSWORD`, `PKCS12_PASSWORD`, `GPG_KEY_ID`).
        See README "Codesigning" for the workflow.
      '';
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

    warnings = mkOption {
      type = types.listOf types.str;
      default = [ ];
      internal = true;
      visible = false;
      description = "Internal: messages printed at evaluation time, e.g. for renamed options.";
    };
  };

  config = {
    warnings =
      let
        local = config.permissions.network.local;
        ports = local != null && (local.udp != [ ] || local.tcp != [ ]);
      in
      lib.optional
        (
          builtins.elem format [
            "msi"
            "nsis"
            "exe"
          ]
          && ports
          && config.windows.scope == "perUser"
        )
        (
          "permissions.network.local ports get no firewall rules in a per-user install "
          + "(they need admin); Windows asks the user on first run instead."
        );

    assertions = [
      {
        assertion =
          !(
            builtins.elem format [
              "msi"
              "nsis"
              "exe"
            ]
            && config.services != [ ]
            && config.windows.scope == "perUser"
          );
        message = "info.services need admin to install; use windows.scope = \"perMachine\".";
      }
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
        assertion = lib.all (a: !a.exported || (a.id != null && a.id != "")) config.fileAssociations;
        message =
          "info.fileAssociations: exported types need an `id` (their UTI / ProgID), missing on: "
          + lib.concatMapStringsSep ", " (a: "'${a.name}'") (
            builtins.filter (a: a.exported && (a.id == null || a.id == "")) config.fileAssociations
          )
          + ".";
      }
      {
        assertion = lib.all (a: lib.all (e: !lib.hasPrefix "." e) a.extensions) config.fileAssociations;
        message = "info.fileAssociations: write `extensions` without the leading dot (\"pdf\", not \".pdf\").";
      }
      {
        assertion =
          config.windows.upgradeCode == null
          ||
            builtins.match "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" config.windows.upgradeCode
            != null;
        message =
          "info.windows.upgradeCode must be a GUID of shape "
          + "'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX' (got '${toString config.windows.upgradeCode}').";
      }
      {
        assertion = config.macos.entitlements == { } || config.signing.darwin.entitlements == null;
        message =
          "info.macos.entitlements and info.signing.darwin.entitlements are both set; "
          + "keep one: the attribute set, or the path to an entitlements file.";
      }
    ];
  };
}
