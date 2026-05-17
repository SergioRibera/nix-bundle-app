# nix-bundle-app

Turn any Nix derivation into native installers for **Linux**, **macOS**, and **Windows** — no Nix required on the target machine.

It does *not* build your program. You give it a pre-built derivation (e.g. `pkgs.hello`, your crane/cargo-built binary, a `stdenv.mkDerivation`, anything), and it produces installable artifacts plus the manifests each OS expects.

| OS      | Formats                                           |
|---------|---------------------------------------------------|
| linux   | `deb`, `rpm`, `archlinux`, `appimage`, `brew` (linuxbrew), `tar.gz`, `tar.xz`, `tar.zst`, `zip` |
| darwin  | `app`, `dmg`, `pkg`, `brew`, `tar.gz`, `zip`      |
| windows | `nsis` (`.exe` installer), `msi`, `zip`           |

Signing is **not** done yet — bundles ship unsigned.

## Add to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-bundle-app.url = "github:rustlanges/nix-bundle-app";
  };

  outputs = { self, nixpkgs, flake-utils, nix-bundle-app }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        bundler = nix-bundle-app.lib.mkLib pkgs;
      in {
        packages = {
          # one format
          hello-deb = bundler.bundle {
            drv = pkgs.hello;
            format = "deb";
            info.maintainer = "You <you@example.com>";
          };

          # many at once
          hello-all = bundler.bundleAll {
            drv = pkgs.hello;
            formats = [ "deb" "rpm" "archlinux" "tar.gz" ];
            info.maintainer = "You <you@example.com>";
          };
        };
      });
}
```

Then `nix build .#hello-deb`. Output ends up in `result/`.

## API

### `bundler.bundle`

```nix
bundler.bundle {
  drv     = ...;          # a derivation. Must contain bin/ (and optionally lib/, share/)
  format  = "deb";        # one of the supported formats
  info    = { ... };      # optional, see below
  target  = { ... };      # optional, override { arch, os }; defaults to drv.system
}
```

### `bundler.bundleAll`

```nix
bundler.bundleAll {
  drv     = ...;
  formats = [ "deb" "rpm" "archlinux" "tar.gz" "zip" ];
  info    = { ... };
  target  = { ... };
}
```

Returns a `linkFarm` derivation whose subdirectories are the per-format outputs.

### `info` fields (all optional)

| Field                      | Default                      | Notes                                     |
|----------------------------|------------------------------|-------------------------------------------|
| `name`                     | `drv.pname or drv.name`      |                                           |
| `version`                  | `drv.version or "0.0.0"`     |                                           |
| `description` / `summary`  | from `drv.meta.description`  |                                           |
| `longDescription`          | from `drv.meta`              |                                           |
| `homepage`                 | from `drv.meta`              |                                           |
| `license`                  | from `drv.meta.license`      | SPDX preferred                            |
| `maintainer`               | `Unspecified <noreply@…>`    | `Name <email>`                            |
| `section`                  | `"utils"`                    | deb only                                  |
| `priority`                 | `"optional"`                 | deb only                                  |
| `desktopEntries`           | `[ ]`                        | declarative `.desktop` structs — see [Desktop entries](#desktop-entries) |
| `services`                 | `[ ]`                        | declarative cross-OS services — see [Services](#services) |
| `bundleId`                 | `com.example.<name>`         | macOS CFBundleIdentifier                  |
| `macOsIcon`                | `null`                       | path to `.icns` for `.app`/`.dmg`/`.pkg`  |
| `minimumSystemVersion`     | `"10.13"`                    | macOS                                     |
| `installDirName`           | `<name>`                     | windows install dir                       |
| `downloadUrl`              | `""`                         | brew formula `url`                        |
| `keepInterpreter`          | `false`                      | skip patchelf interpreter rewrite (linux) |
| `appImageRuntime`          | pinned `fetchurl`            | override AppImage type2 runtime           |
| `appImageTerminal`         | `false`                      | AppImage `.desktop` Terminal=             |
| `msiUpgradeCode`           | derived from `bundleId`      | pin to stabilize across releases          |
| `depends.deb`              | `[ "libc6" ]`                | per-format deps list                      |
| `depends.rpm`              | `[ "glibc" ]`                |                                           |
| `depends.archlinux`        | `[ "glibc" ]`                |                                           |
| `depends.brew`             | `[ ]`                        |                                           |
| `depends.debRecommends`    | `[ ]`                        |                                           |
| `depends.rpmRecommends`    | `[ ]`                        |                                           |
| `depends.archlinuxOptional`| `[ ]`                        |                                           |

### `target`

```nix
{ arch = "x86_64"; os = "linux"; }   # arch ∈ x86_64 | aarch64 | armv7l | armv6l | i686 | riscv64
                                     # os   ∈ linux | darwin | windows
```

If omitted, it's inferred from `drv.system`. For cross-bundling (e.g. you build the
windows artifact on a linux host) you supply both `drv` (which must be the cross-built
derivation, e.g. `pkgs.pkgsCross.mingwW64.hello`) and `target = { arch = "x86_64"; os = "windows"; }`.

## What happens under the hood

For each bundle the library:

1. Walks the runtime closure of `drv` via `pkgs.closureInfo`.
2. Copies every shared library in the closure into the bundle's `lib/` (Linux) /
   `Contents/Frameworks/` (macOS) / next to `.exe` (Windows), **except** base
   libs that every target system ships (libc, libm, libpthread, libdl, ld-linux,
   libSystem, libobjc, etc.) — those are listed as manifest deps instead.
3. Patches binaries:
   - **Linux**: `patchelf --set-interpreter /lib64/ld-linux-...` and `--set-rpath '$ORIGIN/../lib'`.
   - **macOS**: `install_name_tool -change` rewrites `/nix/store/...` references to
     `@executable_path/../Frameworks/<lib>`.
   - **Windows**: no patching needed; DLLs sit next to the `.exe`.
4. Generates the format's manifest (control, spec, PKGINFO, Info.plist, .nsi, .wxs, PackageInfo, AppRun, etc.).
5. Packs it with the appropriate tool (`dpkg-deb`, `rpmbuild`, `bsdtar+zstd`, `xorrisofs`, `makensis`, `wixl`, `xar+cpio+bomutils`, `mksquashfs`, `tar`, `zip`).

### Desktop entries

Linux installs get xdg `.desktop` files generated from `info.desktopEntries`. Each entry is a Nix struct — no raw files. The renderer escapes special chars, builds `Categories=`/`Keywords=` lists, and emits `[Desktop Action <name>]` sections for the `actions` attr.

```nix
info.desktopEntries = [
  {
    name        = "Hello Demo";              # → Name=
    exec        = "/opt/hello/bin/hello %F"; # → Exec=
    comment     = "Friendly greeter";        # → Comment=
    icon        = "hello";                   # → Icon=  (name reference)
    iconPath    = ./hello.png;               # actual file to ship at /usr/share/icons/.../hello.png
    categories  = [ "Utility" "Education" ]; # → Categories=Utility;Education;
    keywords    = [ "demo" "greeting" ];     # → Keywords=demo;greeting;
    terminal    = false;
    mimeTypes   = [ "text/plain" ];
    startupNotify = true;
    actions = {                              # → [Desktop Action Verbose]
      "Verbose" = { name = "Run verbose"; exec = "/opt/hello/bin/hello --verbose"; };
    };
    extra = { "X-AppImage-Version" = "1.0"; }; # raw extra keys
  }
];
```

If you'd rather start from an existing `.desktop` file and tweak it, the lib exposes a parser:

```nix
let
  base = bundler.desktop.fromFile ./hello.desktop;
in {
  info.desktopEntries = [ (base // { name = "Hello (custom)"; }) ];
}
```

AppImage uses the **first** entry as its top-level `.desktop`. All other linux formats install every entry to `/usr/share/applications/`. Icons (when `iconPath` is set) land in `/usr/share/icons/hicolor/512x512/apps/<icon>.png`.

For the macOS `.app`/`.dmg`/`.pkg` icon, set `info.macOsIcon` to a `.icns` file — that's a separate field because the formats and paths involved have nothing to do with `.desktop`.

### Services

Define a service once as a Nix struct; the renderer emits the right artifact per OS:

| OS      | Output                                            | Activation                                         |
|---------|---------------------------------------------------|----------------------------------------------------|
| linux   | `/lib/systemd/system/<name>.service`              | `postinst` runs `systemctl daemon-reload && enable --now` |
| darwin  | `/Library/LaunchDaemons/<label>.plist` (in `.pkg`) | `postinstall` runs `launchctl load -w`            |
| darwin  | `Contents/Resources/LaunchDaemons/...` (in `.app`) | informational only — manual `launchctl load`      |
| windows | `install-services.bat` / `uninstall-services.bat` (in payload) | NSIS runs them in Install/Uninstall sections; MSI ships them — auto-run via custom action is on the roadmap |

```nix
info.services = [
  {
    name        = "hello-agent";          # systemd unit name / launchd Label / sc serviceName base
    description = "Hello background greeter";
    exec        = "/opt/hello/bin/hello --daemon"; # cross-OS default; OS-specific paths via overrides below
    user        = "hello";
    group       = "hello";
    workingDirectory = "/var/lib/hello";
    environment = { LOG_LEVEL = "info"; HELLO_INTERVAL = "60"; };
    restart     = "always";               # always | on-failure | no
    restartSec  = 10;
    startAtBoot = true;
    type        = "simple";               # simple | forking | oneshot | notify | dbus
    stdout      = "/var/log/hello.log";
    stderr      = "/var/log/hello.log";
    after       = [ "network-online.target" ];
    requires    = [ ];
    wants       = [ ];

    # Per-OS overrides (all optional).
    systemd = {
      unitOverrides    = { Slice = "user.slice"; };
      serviceOverrides = { LimitNOFILE = 65536; };
      installOverrides = { };
      wantedBy         = [ "multi-user.target" ];
    };
    launchd = {
      label = null;                       # defaults to `name`
      keepAlive = true;
      runAtLoad = true;
      abandonProcessGroup = false;
      processType = "Background";         # Background | Standard | Adaptive | Interactive
      throttleInterval = null;
    };
    windows = {
      serviceName  = "HelloAgent";        # display+registry name (defaults to `name`)
      displayName  = "Hello Greeter Agent";
      account      = "LocalSystem";       # LocalSystem | LocalService | NetworkService
      start        = "auto";              # auto | demand | disabled
      errorControl = "normal";
      depends      = [ ];
    };
  }
];
```

The renderer parses `exec` as `"<bin> <args>..."`. On Windows, NSIS rewrites the binary to `%~dp0<exe>` so the service binPath resolves relative to the install directory. Apple `ProgramArguments` is split on spaces too — quote-bearing args aren't handled yet, so for shell-tricky commands wrap them in a launcher script.

### Format-specific notes

- **`appimage`**: AppDir contains `usr/{bin,lib,share}`, `AppRun` launcher, `.desktop` entry (first of `info.desktopEntries`) and icon (1×1 transparent PNG inserted if none provided). Packed as a SquashFS payload appended to a pinned [type2-runtime](https://github.com/AppImage/type2-runtime) binary. Override the runtime via `info.appImageRuntime = pkgs.fetchurl { ... };`. The bundled libs go into `usr/lib`; `AppRun` exports `LD_LIBRARY_PATH` so the binary picks them up regardless of host.
- **`pkg`** (macOS): Flat `.pkg` (xar archive: `PackageInfo`, `Bom`, `Payload`, optional `Scripts`). Without services the `.app` ends up at `/Applications/<name>.app`. With `info.services` the layout flips to `install-location="/"` so both `/Applications/<name>.app` and `/Library/LaunchDaemons/<label>.plist` land in the right places; a generated `Scripts/postinstall` runs `launchctl load -w` for each plist. On Linux we build it with `bomutils` + `xar` + `cpio`; the `Bom` may be empty if `mkbom` crashes on the host (modern glibc + bomutils 0.2 is incompatible). On a darwin host the format uses `pkgbuild` for a fully spec-compliant package. Signing is not performed (`rcodesign` / `productsign` integration is on the roadmap).
- **`brew`**: Works on **macOS and Linux** (linuxbrew). Produces a `Formula.rb` + `.tar.gz`. On darwin, if `info.services` is non-empty the formula gets a `service do ... end` block (Homebrew's built-in launchd integration); on linux the formula installs files only since linuxbrew doesn't manage system services.
- **`msi`**: Generated via `msitools`' `wixl`. `wixl-heat` scans the staged payload tree and emits the WiX component fragment. Install target is `%ProgramFiles%\<installDirName>`. A Start Menu shortcut and HKCU registry marker are added. The `UpgradeCode` is derived deterministically from `bundleId` — **pin `info.msiUpgradeCode` once you cut your first release** so future MSIs are seen as upgrades.

## Examples

`examples/hello/flake.nix` is a complete consumer flake. From this repo:

```sh
nix build .#hello-deb
nix build .#hello-rpm
nix build .#hello-archlinux
nix build .#hello-appimage
nix build .#hello-tar-gz
nix build .#hello-app
nix build .#hello-dmg
nix build .#hello-pkg
nix build .#hello-brew
nix build .#hello-nsis           # cross-compiled windows installer on linux
nix build .#hello-msi
nix build .#hello-all-linux      # all linux formats in one output dir
nix build .#hello-all-darwin
nix build .#hello-all-windows
```

## Tests

`tests/default.nix` is wired into `nix flake check` — it builds every format
against `pkgs.hello` and verifies the expected artifact filename exists.

```sh
nix flake check
```

## Auto-generated docs

The `info` schema is its own source of truth for the options reference:

- [`lib/schema.nix`](lib/schema.nix) is a NixOS-style module declaring every option with `type`, `default`, `description`, `example`.
- [`lib/docs.nix`](lib/docs.nix) feeds it to `pkgs.nixosOptionsDoc`, which is the same tool the NixOS manual uses, and emits a `share/doc/nix-bundle-app/options.{md,json}` pair.
- [`.github/workflows/docs.yml`](.github/workflows/docs.yml) rebuilds those files on every push that touches the schema and commits the diff back to `docs/`.

Build the docs locally with:

```sh
nix build .#docs
ls result/share/doc/nix-bundle-app/
# options.json  options.md
```

The committed copies live at [`docs/options.md`](docs/options.md) and [`docs/options.json`](docs/options.json). Don't hand-edit them — change [`lib/schema.nix`](lib/schema.nix) instead.

## Validation

`info` is validated at evaluation time via the NixOS-style module system. The schema lives in [`lib/schema.nix`](lib/schema.nix); `lib/info.nix` runs it through `lib.evalModules` before any derivation is built. You get:

- **Typos caught early**. `info.mantainer = "..."` → `error: The option `mantainer` does not exist. Did you mean `maintainer`?` from `nix-instantiate` before any IO.
- **Type checking**. `info.restartSec = -1` → `value -1 is not of type 'unsigned integer'`. `info.services[].restart = "sometimes"` → `not of the enum [ "always" "on-failure" "no" ]`.
- **Required fields**. `info.services = [ { exec = "..."; } ];` (missing `name`) → schema-level error.
- **Cross-field consistency**. `assertions` block in the schema fires for combinations like `format = "appimage"` + `info.services != []` (AppImages aren't system services) or `info.msiUpgradeCode = "not-a-guid"` (must match the GUID regex).

The full options reference is autogenerated to [`docs/options.md`](docs/options.md) — see [Auto-generated docs](#auto-generated-docs) below.

## Caveats / known limits

- **No signing.** Linux artifacts ship unsigned. macOS `.app`/`.dmg`/`.pkg` aren't codesigned or notarized. Windows `.exe`/`.msi` aren't authenticode-signed.
- **macOS `install_name_tool`** only runs on a darwin host. Linux→darwin bundles copy dylibs but skip load-path rewriting; the resulting `.app`/`.dmg`/`.pkg` works on darwin only if the original binary already used `@executable_path/...` references.
- **DMG on linux** is an HFS+ hybrid ISO built via `xorrisofs -hfsplus` (Finder mounts it transparently). It is not byte-identical to a real UDIF DMG.
- **macOS `.pkg` on linux**: built manually because `pkgbuild` is darwin-only. `bomutils-0.2` (the `mkbom` shipping in nixpkgs) crashes under modern glibc FORTIFY checks; when that happens we fall back to an empty `Bom`. Most flat-pkg installers tolerate this, but you lose the receipt file list. Build on darwin for a fully compliant Bom.
- **AppImage runtime** is pinned to AppImage's `continuous` release. If upstream rotates the binary the hash check fails — supply `info.appImageRuntime = pkgs.fetchurl { url=...; sha256=...; };` to pin your own.
- **MSI UpgradeCode** is derived from `info.bundleId` by default, which is stable as long as `bundleId` doesn't change. For released artifacts set `info.msiUpgradeCode` explicitly.
- **Library closure → distro deps**: we don't auto-map nix-store libraries to `Depends:` entries. Use `info.depends.{deb,rpm,archlinux,brew}` to override.

## Roadmap

- `lib.evalModules`-backed schema for `info` (eval-time type validation + assertions)
- MSI service install via `<ServiceInstall>` (native, no `.bat`)
- Codesigning hooks (`rcodesign` for macOS, `osslsigncode` for Windows, GPG-signed deb/rpm)
- macOS productbuild distribution (welcome / license / conclusion screens)
- Auto-mapping closure libs → distro package names (deb, rpm)
- AUR-publishable source tarball + signed SRCINFO
- Flatpak / Snap output

## License

MIT
