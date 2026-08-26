---
name: nix-bundle-app
description: Use this skill whenever the user wants to bundle, package, distribute, or produce native installers from a Nix derivation — `.deb`, `.rpm`, AppImage, archlinux/AUR, `.dmg`, `.pkg`, `.app`, productbuild, NSIS `.exe`, `.msi`, flatpak, snap, brew/linuxbrew, plain `tar.gz`/`tar.xz`/`tar.zst`/`zip`, or a `cargo-dist`-style release matrix with `install.sh`/`install.ps1`. Triggers on phrases like "bundle my app", "make a deb/rpm/dmg/msi/appimage", "ship installers", "release matrix", "distribute my Rust/Go binary cross-platform", "sign my installer", or any mention of `nix-bundle-app`, `bundler.bundle`, `bundler.bundleAll`, `bundler.release`. Trigger even if the user names only one format (e.g. "I just need a .deb"). Use proactively when the user is working inside this repository or consumes it.
---

# nix-bundle-app

An overlay ([`overlay.nix`](../../overlay.nix)) that turns any pre-built derivation (`pkgs.hello`, a crane/cargo build, a Go binary, anything with `bin/`) into native installers for Linux, macOS, and Windows. **It does not build the program** — it stages, patches load paths, generates manifests, and packs. No flakes, no separate library entry point — apply the overlay to a `pkgs` and use `pkgs.nixBundleApp`.

## When to use this skill

Use it whenever the user is producing distributable artifacts from Nix — regardless of which OS or format. If they mention a single format ("just give me a deb"), still use the skill; the snippets are uniform across formats.

Do **not** use it for:
- Building the program itself (use `pkgs.stdenv.mkDerivation`, crane, buildGoModule, etc.).
- Signing keys / cert management (the skill emits a `sign.sh` to run *after* the bundle is built).

## Quickstart

```nix
let
  nix-bundle-app = builtins.fetchTarball {
    url = "https://github.com/SergioRibera/nix-bundle-app/archive/<rev>.tar.gz";
    sha256 = "..."; # pin a real commit + hash
  };
  pkgs = import <nixpkgs> {
    overlays = [ (import "${nix-bundle-app}/overlay.nix") ];
  };
in
pkgs.nixBundleApp.bundle {
  drv = pkgs.hello;
  format = "deb";
  info.maintainer = "You <you@example.com>";
}
```

`nix-build -E '...' -A hello-deb` → artifact in `result/`. See [`examples/hello`](../../examples/hello) for a complete consumer.

## API

```nix
bundler.bundle    { drv; format; info ? {}; target ? null; }
bundler.bundleAll { drv; formats; info ? {}; target ? null; }   # returns derivation that produces every format
bundler.release   { info; matrix; releaseUrl; installScripts ? true; }
bundler.signedApp { bundle; name ? "${bundle.name}-sign"; }     # returns a runnable derivation that signs in user shell

bundler.formats          # [ "app" "appimage" "archlinux" "brew" "deb" "dmg" "flatpak" "msi" "nsis" "pkg" "productbuild" "rpm" "snap" "tar.gz" "tar.xz" "tar.zst" "zip" ]
bundler.linuxTargets     # formats producible for target.os = "linux"
bundler.darwinTargets    # ... darwin
bundler.windowsTargets   # ... windows
bundler.targets.<os>     # grouped form
bundler.formatOS         # raw { format = os | "any" | [os…]; } map
```

`bundler` is `pkgs.nixBundleApp` once the overlay is applied — everything here builds derivations or shells out. Pure, pkgs-independent helpers (rendering, schema validation, no building) live under `pkgs.lib.nixBundleApp` instead — `utils`, `desktop`, `services`, `normalize`.

`target` defaults to `drv.system`. Pass `{ arch = "x86_64"; os = "windows"; }` (etc.) for cross-bundling.

## Format → OS matrix

| OS      | Formats |
|---------|---------|
| linux   | `deb`, `rpm`, `archlinux`, `appimage`, `flatpak`, `snap`, `brew` (linuxbrew), `tar.gz`, `tar.xz`, `tar.zst`, `zip` |
| darwin  | `app`, `dmg`, `pkg`, `productbuild`, `brew`, `tar.gz`, `tar.xz`, `tar.zst`, `zip` |
| windows | `nsis` (`.exe`), `msi`, `tar.gz`, `tar.xz`, `tar.zst`, `zip` |

Wildcards (`tar.gz`, `tar.xz`, `tar.zst`, `zip`) are host-agnostic. `brew` works on macOS + linuxbrew. Everything else is OS-specific.

## Picking a format

| User wants | Format |
|------------|--------|
| Debian/Ubuntu install | `deb` |
| Fedora/RHEL/SUSE install | `rpm` |
| Arch / Manjaro | `archlinux` (emits both `*.pkg.tar.zst` and AUR `PKGBUILD`) |
| Single portable Linux binary, no install | `appimage` |
| Sandboxed Linux GUI app | `flatpak` (emits manifest + tarball + `build.sh`) |
| Ubuntu Store app | `snap` (emits `snapcraft.yaml` + payload + `build.sh`) |
| macOS app bundle (no installer) | `app` |
| macOS drag-to-install disk image | `dmg` |
| macOS pkg installer | `pkg`, or `productbuild` for the wizard-style one |
| Homebrew formula | `brew` |
| Windows installer with wizard | `nsis` |
| Windows MSI (group policy, services) | `msi` |
| Just a tarball / zip | `tar.gz` / `tar.xz` / `tar.zst` / `zip` |
| Everything at once + install scripts | `bundler.release { matrix; releaseUrl; }` |

## The `info` attrset

`info` is validated at evaluation time via `lib.evalModules` against `lib/schema.nix`. Typos → eval error with "Did you mean …?" hints.

**Identity** (auto-derived from `drv` when omitted):
- `name`, `version`, `summary`, `description`, `longDescription`
- `license`, `maintainer`, `homepage`
- `bundleId` (reverse-DNS, default `com.example.<name>`), `bundleSignature` (macOS 4-char code)

**Layout**:
- `binDir = "bin"`, `libDir = "lib"`, `installDirName = name`

**Dependencies**:
- `autoDepends = true` — scan staged binaries with `patchelf --print-needed`, map SONAMEs via `lib/lib-map.nix`, merge into `depends`. Auto-detected entries never override user ones.
- `depends.deb`, `depends.debRecommends`
- `depends.rpm`, `depends.rpmRecommends`, `depends.rpmGroup`
- `depends.archlinux`, `depends.archlinuxOptional`
- `depends.brew`, `depends.nsis`

**Desktop entries** (XDG `.desktop`) — `desktopEntries = [ { name; exec; categories; icon ? ; ... } ]`. Materialises on linux into `/usr/share/applications/<file>.desktop` + icons under `/usr/share/icons/hicolor/`. See `references/services-desktop.md`.

**Services** (cross-OS) — `services = [ { name; exec; description; ... } ]`. One struct → systemd unit (linux), launchd plist (`pkg`), NSIS `.bat`s or native MSI `<ServiceInstall>` (windows). See `references/services-desktop.md`.

**Extra system files** (linux installer formats only) — `extraFiles = { "/lib/udev/rules.d/61-foo.rules" = ./foo.rules; "/etc/modprobe.d/foo.conf" = "options foo bar=1\n"; }`. Keys are absolute install paths, values are Nix paths/store paths or inline strings. Honoured by `deb`, `rpm`, `archlinux`; ignored by `appimage`, `flatpak`, `snap` (no system install location). When any key lands under a known udev rules dir, the post-install hook also runs `udevadm control --reload-rules && udevadm trigger`.

**Format-specific**:
- `msiUpgradeCode` — pin a UUID for released MSIs (otherwise derived from `bundleId`).
- `appImageRuntime`, `appImageTerminal`.
- `flatpak.{runtime,runtimeVersion,sdk,command,finishArgs,extraModules}`.
- `snap.{base,confinement,grade,plugs,summary}`.
- `archlinux.output = "pkg" | "aur" | "both"` (default `"both"`).
- `productbuild = { welcome; license; readme; conclusion; background; title; organization; allowCustomize; }`.
- `macOsIcon`, `minimumSystemVersion`.

**Other**:
- `downloadUrl` — used by archlinux AUR `source=()` + `sha256sums=()`.
- `keepInterpreter = false` — if `true`, skip `patchelf --set-interpreter` on linux.
- `signing.{darwin,windows,linux}` — see `references/signing.md`.

Full reference: `docs/options.md` (autogenerated from `lib/schema.nix`).

## Common patterns

### Single format

```nix
packages.app-deb = bundler.bundle {
  drv = my-app;
  format = "deb";
  info = {
    maintainer = "You <you@example.com>";
    homepage = "https://example.com";
    license = "MIT";
  };
};
```

### Multiple formats from one drv

```nix
packages.app-all = bundler.bundleAll {
  drv = my-app;
  formats = [ "deb" "rpm" "archlinux" "appimage" "tar.gz" ];
  inherit info;
};
```

### Cross-bundling (build on linux, ship for windows)

```nix
packages.app-msi = bundler.bundle {
  drv = pkgs.pkgsCross.mingwW64.my-app;
  format = "msi";
  target = { arch = "x86_64"; os = "windows"; };
  inherit info;
};
```

### Full release matrix + install scripts

```nix
packages.release = bundler.release {
  info = { name = "my-app"; version = "1.2.0"; license = "MIT"; };
  releaseUrl = "https://github.com/user/repo/releases/download/v\${VERSION}";

  matrix = {
    "x86_64-linux"   = { drv = appLinuxX64;  formats = [ "tar.gz" "deb" "rpm" "appimage" ]; };
    "aarch64-linux"  = { drv = appLinuxArm;  formats = [ "tar.gz" "deb" ]; };
    "x86_64-darwin"  = { drv = appMacX64;    formats = [ "tar.gz" "dmg" ]; };
    "aarch64-darwin" = { drv = appMacArm;    formats = [ "tar.gz" "dmg" ]; };
    "x86_64-windows" = { drv = appWinX64;    formats = [ "zip" "msi" ]; };
  };

  installScripts = true;
};
```

Produces a flat directory with every artifact + `install.sh` + `install.ps1` + `SHA256SUMS`. End-users do:

```sh
curl -fsSL https://github.com/user/repo/releases/latest/download/install.sh | sh
# or:
iwr https://github.com/user/repo/releases/latest/download/install.ps1 | iex
```

Scripts auto-detect arch/OS, download, verify, extract to `~/.local/bin` (Unix) or `%LOCALAPPDATA%\Programs\<name>` (Windows). Flags: `--version vX.Y.Z`, `--dir <path>`, `--uninstall`. See `references/release-matrix.md`.

`bundler.installScripts { … }` (same args) → just the scripts, no bundles.

### GUI app with desktop entry + icon

```nix
info = {
  maintainer = "You <you@example.com>";
  desktopEntries = [{
    name = "My App";
    exec = "/opt/my-app/bin/my-app %F";
    categories = [ "Utility" "Development" ];
    icon = "my-app";
    iconPath = ./assets/icon.png;     # → /usr/share/icons/hicolor/512x512/apps/my-app.png
    mimeTypes = [ "text/x-myproject" ];
  }];
};
```

### Background daemon (cross-OS service)

```nix
info.services = [{
  name = "my-agent";
  exec = "/opt/my-app/bin/my-app --daemon";
  description = "Background worker";
  restart = "always";
  environment = { LOG_LEVEL = "info"; PORT = 8080; };
  type = "simple";   # systemd Type
}];
```

One struct produces: systemd unit on linux (enabled in `postinst`), launchd plist on darwin `pkg` (loaded by `postinstall`), `install-services.bat`/`uninstall-services.bat` on NSIS, native `<ServiceInstall>`/`<ServiceControl>` on MSI. Per-OS overrides via `services.*.systemd.{unitOverrides,serviceOverrides}`, `services.*.launchd.{processType,keepAlive,...}`, `services.*.windows.{account,start,errorControl}`.

### Sign-then-build-in-one-shot

```nix
app-deb-signed = bundler.signedApp { bundle = app-deb; };
```

```sh
nix-build -A app-deb-signed -o sign-app-deb
GPG_KEY_ID=0xABCDEF1234567890 ./sign-app-deb/bin/app-deb-sign -- ./dist
```

Bundle stays pure & cacheable; sign step runs in user shell where secrets live. See `references/signing.md`.

## Codesigning — quick rules

Secrets cannot live in `/nix/store`. Signing runs **after** `nix build`. Enable per OS:

```nix
info.signing = {
  darwin = {
    enable = true;
    p12File = ./certs/developer-id.p12;
    teamId = "ABC1234567";
    hardenedRuntime = true;
    entitlements = ./entitlements.plist;
  };
  windows = {
    enable = true;
    pkcs12File = ./certs/auth.pfx;
    timestampUrl = "http://timestamp.sectigo.com";
  };
  linux = {
    enable = true;
    keyId = "0xABCDEF1234567890";
    style = "embedded";    # `embedded` → dpkg-sig/rpmsign; `detached` → *.sig
  };
};
```

```sh
nix-build -A app-deb
P12_PASSWORD="$(cat ~/.secrets/p12.pw)" ./result/sign.sh   # darwin/windows
GPG_KEY_ID=0xABCDEF1234567890           ./result/sign.sh   # linux
```

Full env-var matrix in `references/signing.md`.

## Format-specific notes (read when picking that format)

- **`appimage`** — AppDir + SquashFS appended to a pinned [type2-runtime](https://github.com/AppImage/type2-runtime) ELF. Override via `info.appImageRuntime` for stable releases.
- **`pkg`** (macOS) — flat `.pkg` (xar). Without services, the `.app` lands in `/Applications/<name>.app`. With services, `install-location="/"` + a `postinstall` that `launchctl load -w`s each plist. Linux host uses `xar+cpio+bomutils`; darwin host uses `pkgbuild`.
- **`productbuild`** — distribution-style installer wrapping the component `pkg`. `info.productbuild` controls welcome/license/readme/conclusion/background screens. On darwin: real `productbuild`; on linux: hand-assembles the outer xar.
- **`brew`** — works on macOS *and* linuxbrew. Produces `Formula.rb` + `.tar.gz`. Darwin + `info.services` gets a `service do … end` block.
- **`msi`** — uses `msitools`' `wixl`. `UpgradeCode` derived from `bundleId` — **pin `info.msiUpgradeCode` for released artifacts** or upgrades break. Services materialise natively, no `.bat`.
- **`dmg`** on linux — HFS+ hybrid ISO via `xorrisofs -hfsplus`. Not a byte-identical UDIF DMG; Finder mounts fine.
- **`flatpak`** — emits build-ready layout (`<bundleId>.yaml` + source tarball + `build.sh`). **No final `.flatpak`** — needs network to fetch runtimes, forbidden in Nix sandbox. Run `./build.sh` on a flatpak-builder host.
- **`snap`** — emits `snap/snapcraft.yaml` + `payload/` + `build.sh`. Real `.snap` needs `snapcraft pack` which spins an LXD/multipass VM. Run `./build.sh` on a snapcraft host.
- **`archlinux`** — by default emits *both* a binary `*.pkg.tar.zst` and an AUR-publishable `aur/` subdir (`PKGBUILD` + `.SRCINFO` + tarball). Toggle via `info.archlinux.output`. Set `info.downloadUrl` so PKGBUILD `source=()` points at your real release tarball. Push `aur/` to `aur:<name>-bin.git`.

More detail per format: `references/formats.md`.

## How it works under the hood

1. Walk `drv`'s runtime closure via `pkgs.closureInfo`.
2. Copy every shared lib into `/opt/<name>/lib` (linux), `Contents/Frameworks` (darwin), next-to-`.exe` (windows), skipping base libs each target ships (libc, libm, libpthread, libdl, ld-linux, libSystem, libobjc, …).
3. Patch binaries — linux: `patchelf --set-interpreter` + `--set-rpath '$ORIGIN/../lib'`. darwin: `install_name_tool -change` rewrites `/nix/store/...` to `@executable_path/../Frameworks/<lib>`. windows: no patching.
4. Generate manifest (control, spec, PKGINFO, Info.plist, Distribution xml, `.nsi`, `.wxs`, AppRun, …).
5. Pack with the right tool (`dpkg-deb`, `rpmbuild`, `bsdtar+zstd`, `xorrisofs`, `makensis`, `wixl`, `xar+cpio+bomutils`, `mksquashfs`, `tar`, `zip`).

## Caveats

- **`install_name_tool`** only runs on a darwin host. Linux→darwin bundles copy dylibs but skip load-path rewriting (the binary still references `/nix/store/...`).
- **`mkbom`** (bomutils 0.2 in nixpkgs) crashes under modern glibc FORTIFY. Linux-built `.pkg` falls back to an empty Bom — most installers tolerate it. Build on darwin for a compliant Bom.
- **AppImage runtime** is pinned to a numbered type2-runtime release (`runtimeRelease` in `lib/formats/appimage.nix`); pass your own via `info.appImageRuntime` to override.
- **SONAME map** is curated, not exhaustive. Add unknowns via `info.depends.<distro>`.
- **`msiUpgradeCode`** — leaving it derived from `bundleId` is fine for first release but locks you in. Pin a UUID before publishing.
- **`flatpak`/`snap`** never produce final artifacts inside Nix — they always need a post-build `./build.sh` step.
- **Target mismatches fail the build, not silently**: deb/rpm/archlinux/appimage/app/dmg/pkg/productbuild/tar.gz/zip all verify the staged binary against `target.{os,arch}` via `file` before packing — e.g. accidentally bundling a darwin `drv` with `target.os = "linux"` errors out instead of shipping a broken artifact. `msi`/`nsis` can't be checked this way (binary is embedded in the installer container).

## Validation & tests

- `info` runs through `lib.evalModules` before any derivation builds. Typos and cross-field assertions (`format = "appimage"` + non-empty `info.services` is rejected, malformed `msiUpgradeCode` rejected, etc.) fail at `nix-instantiate` time.
- `nix-build tests` builds every format against `pkgs.hello` + a sample Rust binary, verifies filenames + payload sanity.
- `nix run nixpkgs#nixfmt-rfc-style -- $(git ls-files '*.nix')` formats the tree.
- `nix-build lib/docs.nix` regenerates `docs/options.md` from the schema.

## Reference files

Read on demand:

- `references/info-schema.md` — condensed `info` field reference (read when picking unfamiliar options).
- `references/formats.md` — per-format gotchas + required tooling per host.
- `references/signing.md` — full signing env vars + `sign.sh` semantics per OS.
- `references/release-matrix.md` — `bundler.release` matrix semantics + install-script flags.
- `references/services-desktop.md` — desktop entry + cross-OS service field reference.

Full canonical option reference (large, autogenerated): `docs/options.md` at the repo root.
