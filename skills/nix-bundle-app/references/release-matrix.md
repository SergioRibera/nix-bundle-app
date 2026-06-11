# `bundler.release` — release matrix + install scripts

`bundler.release` produces a flat directory containing every bundle artifact + `install.sh` + `install.ps1` + `SHA256SUMS`. Drop the directory into a GitHub release in one shot.

## Anatomy

```nix
packages.release = bundler.release {
  info = {
    name = "my-app";
    version = "1.2.0";
    license = "MIT";
    homepage = "https://example.com";
    maintainer = "You <you@example.com>";
  };

  releaseUrl = "https://github.com/user/repo/releases/download/v\${VERSION}";

  matrix = {
    "x86_64-linux"   = { drv = appLinuxX64;  formats = [ "tar.gz" "deb" "rpm" "appimage" ]; };
    "aarch64-linux"  = { drv = appLinuxArm;  formats = [ "tar.gz" "deb" ]; };
    "x86_64-darwin"  = { drv = appMacX64;    formats = [ "tar.gz" "dmg" ]; };
    "aarch64-darwin" = { drv = appMacArm;    formats = [ "tar.gz" "dmg" ]; };
    "x86_64-windows" = { drv = appWinX64;    formats = [ "zip" "msi" ]; };
  };

  installScripts = true;   # default; false → bundles + SHA256SUMS only.
};
```

## How it works

1. For every `(arch-os, format)` pair, calls `bundler.bundle { inherit drv format info; target = parsed arch-os; }`.
2. Reads each artifact's `passthru.outFile` (its filename — `bundler.bundle` sets this).
3. Hashes every artifact into `SHA256SUMS`.
4. Bakes the `(arch, os) → filename` table into the generated `install.sh` / `install.ps1`.

You never manually plumb filenames between the bundler and the install scripts — the matrix is the single source of truth.

## `releaseUrl`

A template. `${VERSION}` is substituted by the install script at runtime. Typical values:

- `"https://github.com/user/repo/releases/download/v${VERSION}"` — GitHub releases (recommended).
- `"https://cdn.example.com/my-app/${VERSION}"` — your own CDN.

Don't pre-substitute `${VERSION}` in nix — the install script needs to see the literal `${VERSION}` token so it can swap in `--version` flags at runtime.

## Install scripts

End-users:

```sh
curl -fsSL https://github.com/user/repo/releases/latest/download/install.sh | sh
```

```powershell
iwr https://github.com/user/repo/releases/latest/download/install.ps1 | iex
```

Both scripts:
- Auto-detect arch (`uname -m`, `$env:PROCESSOR_ARCHITECTURE`) + OS (`uname -s`).
- Pick the right bundle from the baked-in matrix table.
- Download, verify against `SHA256SUMS`.
- Extract, drop the binary into `~/.local/bin` (Unix) / `%LOCALAPPDATA%\Programs\<name>` (Windows).

Flags:

| Flag | Meaning |
|------|---------|
| `--version vX.Y.Z` | Install a specific version instead of latest. |
| `--dir <path>` | Override install dir. |
| `--uninstall` | Remove installed binary + cleanup. |

## `bundler.installScripts`

Same args as `bundler.release`. Returns *just* the scripts (`install.sh`, `install.ps1`, `SHA256SUMS`) without the bundle artifacts. Use when you publish bundles separately (e.g. each platform's CI uploads its own bundles, then a central job assembles the scripts).

```nix
packages.release-scripts = bundler.installScripts {
  info       = { name = "my-app"; version = "1.2.0"; license = "MIT"; };
  releaseUrl = "...";
  matrix     = { ... };   # same shape
};
```

## Format selection per target

The format must be producible for that OS — `bundler.linuxTargets`, `bundler.darwinTargets`, `bundler.windowsTargets` enumerate the valid choices. Wildcards (`tar.gz`, `tar.xz`, `tar.zst`, `zip`) always work.

The install script prefers a binary archive format when picking what to download — `tar.gz` on Unix, `zip` on Windows. Other formats (`deb`, `dmg`, `msi`, `appimage`, …) ship for users who want them but the script defaults to the portable archive. So **always include `tar.gz` for each Unix target and `zip` for each Windows target**, even if you also ship native installers.

## CI integration

```yaml
- run: nix build .#release
- uses: softprops/action-gh-release@v2
  with:
    files: result/*
```

The entire `result/` directory uploads to the release as-is. Users can then `curl … install.sh | sh`.
