# Desktop entries + cross-OS services

Both are declared as Nix structs once; the bundler materialises them into per-OS files at the right paths.

## Desktop entries

```nix
info.desktopEntries = [{
  name = "My App";
  exec = "/opt/my-app/bin/my-app %F";
  categories = [ "Utility" "Development" ];
  icon = "my-app";
  iconPath = ./assets/icon.png;
  mimeTypes = [ "text/x-myproject" ];
  keywords = [ "editor" "notes" ];
}];
```

Materialises into:

| OS | Output |
|----|--------|
| linux (deb/rpm/archlinux/appimage/flatpak/snap) | `/usr/share/applications/<file>.desktop` |
| linux (icon) | `/usr/share/icons/hicolor/512x512/apps/<icon>.png` |
| darwin (`.app`) | `Info.plist` `CFBundleDocumentTypes` for `mimeTypes` |
| windows | shortcut + file-type associations (NSIS) |

### All desktop entry fields

| Field | Type | Maps to `.desktop` field |
|-------|------|-------------------------|
| `name` | str | `Name=` |
| `exec` | str | `Exec=` (supports `%F %U %f %u`) |
| `type` | enum `Application` / `Link` / `Directory` (default `Application`) | `Type=` |
| `genericName` | str/null | `GenericName=` |
| `comment` | str/null | `Comment=` (tooltip) |
| `tryExec` | str/null | `TryExec=` — entry hidden if this path doesn't exist |
| `icon` | str/null | `Icon=` (theme name) |
| `iconPath` | path/null | actual file, copied to hicolor 512×512 |
| `categories` | [str] | `Categories=` — see XDG menu spec (`Utility`, `Development`, `Game`, …) |
| `mimeTypes` | [str] | `MimeType=` |
| `keywords` | [str] | `Keywords=` |
| `terminal` | bool (default `false`) | `Terminal=` |
| `startupNotify` | bool/null | `StartupNotify=` |
| `startupWMClass` | str/null | `StartupWMClass=` |
| `noDisplay` | bool (default `false`) | `NoDisplay=` |
| `hidden` | bool (default `false`) | `Hidden=` |
| `dbusActivatable` | bool (default `false`) | `DBusActivatable=` |
| `prefersNonDefaultGPU` | bool (default `false`) | `PrefersNonDefaultGPU=` |
| `singleMainWindow` | bool (default `false`) | `SingleMainWindow=` |
| `fileName` | str (default `<name>.desktop`) | output filename |
| `actions` | `{ <id> = { name; exec; icon ? null; }; }` | XDG `Actions=` + `[Desktop Action <id>]` sections |
| `extra` | attrs | freeform key/values appended to the `.desktop` |

## Services

```nix
info.services = [{
  name = "my-agent";
  exec = "/opt/my-app/bin/my-app --daemon";
  description = "Background worker for My App";
  user = "myapp";
  group = "myapp";
  environment = { LOG_LEVEL = "info"; PORT = 8080; };
  restart = "on-failure";
  type = "simple";
}];
```

Materialises into:

| OS | Output |
|----|--------|
| linux | `/lib/systemd/system/<name>.service`, enabled via `postinst` |
| darwin (`pkg`) | `/Library/LaunchDaemons/<label>.plist`, loaded via `postinstall` |
| windows (NSIS) | `install-services.bat` / `uninstall-services.bat`, run from installer sections |
| windows (MSI) | native `<ServiceInstall>` + `<ServiceControl>` rows |
| darwin (`brew`) | `service do … end` block in `Formula.rb` |

### Generic fields

| Field | Type | Default |
|-------|------|---------|
| `name` | str | — |
| `exec` | str | — |
| `description` | str | `""` |
| `user` / `group` | str/null | `null` |
| `workingDirectory` | str/null | `null` |
| `environment` | attrs of str/int | `{}` |
| `restart` | enum `always` / `on-failure` / `no` | `"on-failure"` |
| `restartSec` | uint | `5` |
| `startAtBoot` | bool | `true` |
| `after` | [str] | `[ "network.target" ]` |
| `requires` | [str] | `[]` |
| `wants` | [str] | `[]` |
| `type` | enum `simple` / `forking` / `oneshot` / `notify` / `dbus` | `"simple"` |
| `stdout` / `stderr` | str/null | `null` |

### Per-OS overrides

`services.*.systemd`:
- `wantedBy` — defaults to `[ "multi-user.target" ]`.
- `unitOverrides` — extra `[Unit]` key=value pairs.
- `serviceOverrides` — extra `[Service]` pairs.
- `installOverrides` — extra `[Install]` pairs.

`services.*.launchd`:
- `label` — defaults to `<bundleId>.<service-name>`.
- `processType` — `Interactive` / `Background` / `Standard` / `Adaptive`.
- `keepAlive` — bool or struct.
- `runAtLoad` — bool.
- `throttleInterval` — uint seconds.
- `abandonProcessGroup` — bool.

`services.*.windows`:
- `serviceName` — defaults to `name`.
- `displayName` — defaults to `description`.
- `account` — `LocalSystem` / `NetworkService` / `LocalService` / explicit `DOMAIN\user`.
- `start` — `auto` / `demand` / `disabled` / `delayed-auto`.
- `errorControl` — `ignore` / `normal` / `severe` / `critical`.
- `depends` — list of windows service names this depends on.

## Common patterns

### GUI app + tray daemon

Combine: one `desktopEntries` for the GUI binary, one `services` for the daemon.

```nix
info = {
  desktopEntries = [{
    name = "My App";
    exec = "/opt/my-app/bin/my-app";
    categories = [ "Utility" ];
    icon = "my-app";
    iconPath = ./assets/icon.png;
  }];

  services = [{
    name = "my-app-agent";
    exec = "/opt/my-app/bin/my-app --agent";
    description = "Sync agent for My App";
    restart = "always";
  }];
};
```

### CLI daemon, no GUI

Just `services`. Omit `desktopEntries` entirely.

### `appimage` + services → eval error

AppImages cannot host services (no persistent install location). The schema rejects this combo at eval time.
