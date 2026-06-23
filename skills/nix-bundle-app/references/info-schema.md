# `info` field reference (condensed)

Canonical schema lives in `lib/schema.nix`; this is a hand-curated quick-lookup. For exhaustive option docs see `docs/options.md`.

## Identity (defaults derived from `drv`)

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `name` | str | `drv.pname` | Package name. |
| `version` | str | `drv.version` | Package version. |
| `summary` | str | `drv.meta.description or "<name>"` | One-line summary (deb `Description:` first line, rpm `Summary:`). |
| `description` | str | `summary` | Short description. |
| `longDescription` | str | `description` | Multi-paragraph description. |
| `license` | str | `"Unspecified"` | SPDX-style. Used by deb/rpm/archlinux/brew/Formula. |
| `maintainer` | str | `"Unknown <unknown@example.com>"` | Deb/rpm `Maintainer:`. **Set this for real packages.** |
| `homepage` | str | `drv.meta.homepage or ""` | Used in all manifests. |
| `bundleId` | str | `"com.example.<name>"` | Reverse-DNS. Drives macOS bundle id, MSI UpgradeCode derivation, AppStream id. |
| `bundleSignature` | str | `"????"` | macOS 4-char creator code. Rarely changed. |

## Layout

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `binDir` | str | `"bin"` | Where bin/ sits inside the staged tree. |
| `libDir` | str | `"lib"` | Where libs sit. `$ORIGIN/../lib` rpath assumes this. |
| `installDirName` | str | `name` | Top-level directory name (e.g. `/opt/<installDirName>` on linux). |

## Dependencies

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `autoDepends` | bool | `true` | Scan `patchelf --print-needed` → `lib/lib-map.nix` → merge into `depends.<distro>`. Auto-detected entries never replace user ones. |
| `depends.deb` | [str] | `[]` | Extra deb `Depends:`. |
| `depends.debRecommends` | [str] | `[]` | deb `Recommends:`. |
| `depends.rpm` | [str] | `[]` | Extra rpm `Requires:`. |
| `depends.rpmRecommends` | [str] | `[]` | rpm `Recommends:`. |
| `depends.rpmGroup` | str | `"Applications"` | rpm `Group:`. |
| `depends.archlinux` | [str] | `[]` | PKGBUILD `depends=()`. |
| `depends.archlinuxOptional` | [str] | `[]` | PKGBUILD `optdepends=()`. |
| `depends.brew` | [str] | `[]` | `Formula.rb` `depends_on`. |
| `depends.nsis` | [str] | `[]` | NSIS install-time prerequisites. |

Tip: turn `autoDepends` off and switch to explicit lists when shipping a hermetic bundle with every lib copied — you don't *want* `libc6` listed as a runtime dep because you ship your own.

## Extra system files (linux installer formats)

`extraFiles = { "<dest>" = <src>; ... }` — drop files into the staged tree at fixed install paths. Honoured by `deb`, `rpm`, `archlinux`. Ignored by `appimage`, `flatpak`, `snap` (no system install location), and by darwin/windows formats.

| Key | Type | Meaning |
|-----|------|---------|
| destination path | `str` (absolute) | Where the file lands inside the installed package (e.g. `/lib/udev/rules.d/61-foo.rules`, `/etc/modprobe.d/foo.conf`). |
| source | `path` or `str` | Nix path/store path copied as-is, or an inline string materialised via `pkgs.writeText`. |

When any destination is under `/lib/udev/rules.d/`, `/usr/lib/udev/rules.d/`, or `/etc/udev/rules.d/`, the generated maintainer scripts also run `udevadm control --reload-rules && udevadm trigger` on install/remove.

The maintainer scripts (deb postinst, rpm %post, archlinux `.INSTALL`) are emitted whenever the bundle has either `services` or `extraFiles` with udev rules — pure-data extras still get staged without scripts.

```nix
info.extraFiles = {
  "/lib/udev/rules.d/61-foo.rules" = ./contrib/foo.rules;
  "/etc/modprobe.d/foo.conf"       = "options foo_mod debug=1\n";
  "/etc/modules-load.d/foo.conf"   = ./contrib/modules-load.conf;
};
```

## Desktop entries

Each entry: `{ name; exec; type ? "Application"; genericName ? null; comment ? null; tryExec ? null; icon ? null; iconPath ? null; categories ? []; mimeTypes ? []; keywords ? []; terminal ? false; startupNotify ? null; startupWMClass ? null; noDisplay ? false; hidden ? false; dbusActivatable ? false; prefersNonDefaultGPU ? false; singleMainWindow ? false; fileName ? "<name>.desktop"; actions ? { <id> = { name; exec; icon ? null; }; }; extra ? {}; }`.

`exec` supports XDG placeholders `%F %U %f %u`. `iconPath` (path) ships the file at `/usr/share/icons/hicolor/512x512/apps/<icon>.png`; `icon` (string) is just the icon-theme name.

## Services

Cross-OS service struct. Each entry: `{ name; exec; description ? ""; user ? null; group ? null; workingDirectory ? null; environment ? {}; restart ? "on-failure"; restartSec ? 5; startAtBoot ? true; after ? [ "network.target" ]; requires ? []; wants ? []; type ? "simple"; stdout ? null; stderr ? null; systemd ? {…}; launchd ? {…}; windows ? {…}; }`.

Per-OS overrides only fill gaps the generic struct can't express:
- `systemd.unitOverrides`, `systemd.serviceOverrides`, `systemd.installOverrides`, `systemd.wantedBy`.
- `launchd.label`, `launchd.processType`, `launchd.keepAlive`, `launchd.runAtLoad`, `launchd.throttleInterval`, `launchd.abandonProcessGroup`.
- `windows.serviceName`, `windows.displayName`, `windows.account`, `windows.start`, `windows.errorControl`, `windows.depends`.

## Format-specific

| Field | Format(s) | Purpose |
|-------|-----------|---------|
| `appImageRuntime` | appimage | Path/url of the type2-runtime ELF. Override for stable releases. |
| `appImageTerminal` | appimage | Mark the AppImage as a terminal app. |
| `flatpak.runtime` | flatpak | e.g. `org.freedesktop.Platform`. |
| `flatpak.runtimeVersion` | flatpak | e.g. `"23.08"`. |
| `flatpak.sdk` | flatpak | e.g. `org.freedesktop.Sdk`. |
| `flatpak.command` | flatpak | Entry-point inside the sandbox. |
| `flatpak.finishArgs` | flatpak | `--share=...`, `--socket=...`, `--filesystem=...`. |
| `flatpak.extraModules` | flatpak | Extra module blocks appended to the manifest. |
| `snap.base` | snap | `"core22"` (Ubuntu 22.04), `"core24"`, … |
| `snap.confinement` | snap | `"strict"` / `"classic"` / `"devmode"`. |
| `snap.grade` | snap | `"stable"` / `"devel"`. |
| `snap.plugs` | snap | List of interfaces (`network`, `home`, …). |
| `snap.summary` | snap | One-line summary (snap-store visible). |
| `archlinux.output` | archlinux | `"pkg"` / `"aur"` / `"both"` (default). |
| `productbuild.welcome` / `.license` / `.readme` / `.conclusion` | productbuild | Paths to rich-text screens. |
| `productbuild.background` | productbuild | Path to the background image. |
| `productbuild.title`, `.organization` | productbuild | Strings. |
| `productbuild.allowCustomize` | productbuild | bool. |
| `macOsIcon` | app/dmg/pkg/productbuild | `.icns` (path). |
| `minimumSystemVersion` | darwin formats | e.g. `"11.0"`. |
| `msiUpgradeCode` | msi | Pin a stable UUID for released MSIs. Leaving it derived from `bundleId` is fine for first release but locks you in. |

## Misc

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `downloadUrl` | str | `""` | Used by archlinux AUR `source=()` + `sha256sums=()`. |
| `keepInterpreter` | bool | `false` | If `true`, skip `patchelf --set-interpreter` on linux. Use when the binary expects a host glibc. |
| `signing.{darwin,windows,linux}` | submodule | disabled | See `signing.md`. |

## Common gotchas

- Don't set `name` or `version` manually unless they differ from the drv — easy to drift.
- `desktopEntries.*.icon` (string) without `iconPath` (file) means you rely on the system having the icon already.
- `services.*.type = "notify"` on systemd needs the binary to call `sd_notify`.
- `msiUpgradeCode` must be a UUID — schema enforces format.
