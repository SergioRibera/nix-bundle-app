# Per-format details

Read the entry for whichever format you're producing. Each section lists: required host, packing tool, output filename, gotchas.

## linux

### `deb`
- Host: any (linux preferred — no special tooling on darwin).
- Tool: `dpkg-deb`.
- Output: `<name>_<version>_<arch>.deb` (arch = `amd64`/`arm64`).
- Layout: payload at `/opt/<installDirName>`, symlinks in `/usr/bin/`.
- Maintainer scripts: `postinst` enables systemd services; `prerm`/`postrm` clean up. Also runs `udevadm control --reload-rules && udevadm trigger` when `info.extraFiles` writes under `/lib/udev/rules.d/`.
- `info.depends.deb` merged with auto-detected SONAME deps.
- `info.extraFiles` materialises raw system files (udev rules, modprobe.d snippets, modules-load.d, …) at the destination paths inside the package.
- Sign: `dpkg-sig` (embedded) or `gpg --detach-sign` (detached `.sig`).

### `rpm`
- Tool: `rpmbuild`.
- Output: `<name>-<version>-1.<arch>.rpm`.
- `info.depends.rpmGroup` defaults to `Applications`.
- `info.extraFiles` entries are enumerated in `%files` and trigger the same udev reload in `%post`/`%postun` as `deb`.
- Sign: `rpmsign --addsign` (embedded) or detached `.sig`.

### `archlinux`
- Tool: `bsdtar` + `zstd`.
- Default `info.archlinux.output = "both"` → emits *both* a binary `*.pkg.tar.zst` (install via `pacman -U`) **and** an `aur/` subdir with `PKGBUILD`, `.SRCINFO`, `<name>-bin-<ver>-<arch>.tar.gz`.
- `info.extraFiles` adds the destination top-level dirs (`/etc`, `/lib/udev`, …) to the `package()` copy loop in PKGBUILD and ships them inside the `.pkg.tar.zst`. udev reload lives in `.INSTALL`'s `post_install`/`post_remove`.
- Set `info.downloadUrl` so PKGBUILD `source=()` + `sha256sums=()` point at your real release tarball.
- AUR repo convention: `aur:<name>-bin.git`.

### `appimage`
- Tool: `mksquashfs` + cat onto type2-runtime ELF.
- Output: `<Name>-<version>-<arch>.AppImage`.
- AppDir layout: `AppRun`, `usr/`, `<bundleId>.desktop`, icon.
- `AppRun` exports `LD_LIBRARY_PATH` so bundled libs win over host libs.
- Runtime pinned to AppImage's `continuous` release — override via `info.appImageRuntime` for stable releases.
- Cannot host services (schema-rejected).

### `flatpak`
- Output: **build-ready layout, not the final `.flatpak`.** Emits `<bundleId>.yaml` + `<name>-<ver>.tar.gz` + `build.sh`. Final `.flatpak` needs network to fetch runtimes, which Nix sandbox forbids.
- Run `./result/build.sh` on a flatpak-builder-enabled host. It shells out to `flatpak-builder --repo=repo build <appid>.yaml && flatpak build-bundle …`.
- Tune sandbox permissions via `info.flatpak.finishArgs` (e.g. `[ "--socket=wayland" "--filesystem=home" ]`).

### `snap`
- Output: build-ready layout, not the final `.snap`. Emits `snap/snapcraft.yaml`, `payload/`, `build.sh`. Real `.snap` needs `snapcraft pack`, which spins an LXD/multipass VM.
- Tune via `info.snap.confinement` (`strict`/`classic`/`devmode`), `info.snap.plugs`, `info.snap.base` (e.g. `core22`).

### `brew` (linuxbrew side)
- Output: `Formula.rb` + `.tar.gz`.
- Same generator as macOS brew; linuxbrew users do `brew install --build-from-source ./Formula.rb`.

## darwin

### `app`
- Output: `<Name>.app/Contents/{MacOS,Frameworks,Resources}`.
- No installer wrapper — drag-to-Applications.
- `Info.plist` populated from `bundleId`, version, `bundleSignature`, `minimumSystemVersion`, icon.

### `dmg`
- Tool on darwin: `hdiutil`. Tool on linux: `xorrisofs -hfsplus` (hybrid ISO, not byte-identical UDIF; Finder mounts fine).
- Wraps the `.app`.

### `pkg`
- Flat `.pkg` (xar). Linux host: `xar+cpio+bomutils`. Darwin host: `pkgbuild`.
- Without services: `.app` lands at `/Applications/<name>.app`.
- With services: `install-location="/"`, `postinstall` `launchctl load -w`s each plist.
- **`mkbom`** in nixpkgs (bomutils 0.2) crashes under modern glibc FORTIFY → linux-built `.pkg` falls back to an empty Bom. Most installers tolerate it; for compliance, build on darwin.

### `productbuild`
- Distribution-style installer wrapping the component `pkg`.
- On darwin: real `productbuild`. On linux: hand-assembles the outer xar (Distribution.xml + Resources/ + component .pkg).
- `info.productbuild = { welcome; license; readme; conclusion; background; title; organization; allowCustomize; }`.

### `brew` (macOS side)
- `Formula.rb` + `.tar.gz`. With `info.services` adds a `service do … end` block (launchd integration).

## windows

### `nsis` (`.exe`)
- Tool: `makensis`.
- Output: `<Name>-<version>-setup.exe`.
- Service support: emits `install-services.bat` / `uninstall-services.bat`, run from installer sections via `sc.exe create … binPath= "…"`.
- `info.depends.nsis` materialises as install-time prerequisite checks.

### `msi`
- Tool: `msitools`' `wixl`.
- Output: `<Name>-<version>-<arch>.msi`.
- `UpgradeCode` derived from `bundleId` — **pin `info.msiUpgradeCode` for released artifacts** or upgrades break across releases.
- Services materialise as native `<ServiceInstall>` + `<ServiceControl>` (no `.bat`).

## host-agnostic wildcards

### `tar.gz`, `tar.xz`, `tar.zst`
- Plain tarball of the staged tree under `<name>-<version>/`.
- Used as the source artifact for the cargo-dist-style `install.sh`.

### `zip`
- Same, zip form. Used by `install.ps1` on windows.

## Producing all formats for a drv

```nix
bundler.bundleAll {
  drv = my-app;
  formats = bundler.linuxTargets;   # or any subset
  inherit info;
};
```

## Producing a release with one format-per-target

See `release-matrix.md`.
