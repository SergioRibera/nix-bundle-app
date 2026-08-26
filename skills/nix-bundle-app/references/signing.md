# Codesigning

Secrets (private keys, p12 passwords) can't safely live in `/nix/store`. The bundle derivations stay pure & cacheable; `bundler.bundle` drops a turnkey `sign.sh` next to the artifact when `info.signing.<os>.enable = true`. You run `sign.sh` after building the bundle with env vars supplying the secrets.

## Enable signing

```nix
info.signing = {
  darwin = {
    enable = true;
    p12File = ./certs/developer-id.p12;
    teamId = "ABC1234567";                    # 10-char Team ID
    hardenedRuntime = true;
    entitlements = ./entitlements.plist;      # optional
  };
  windows = {
    enable = true;
    pkcs12File = ./certs/auth.pfx;
    timestampUrl = "http://timestamp.sectigo.com";
    description = "My App Installer";         # signtool /d
    url = "https://example.com";              # signtool /du
  };
  linux = {
    enable = true;
    keyId = "0xABCDEF1234567890";
    style = "embedded";                       # `embedded` → dpkg-sig/rpmsign; `detached` → *.sig
  };
};
```

## Run `sign.sh`

After `nix-build -A my-app-deb`:

```sh
# darwin / windows
P12_PASSWORD="$(cat ~/.secrets/p12.pw)" ./result/sign.sh

# linux
GPG_KEY_ID=0xABCDEF1234567890 ./result/sign.sh
```

The script reads:

| OS | Env vars |
|----|----------|
| darwin | `P12_PASSWORD` (required), `APPLE_ID` + `APPLE_TEAM_ID` + `NOTARIZATION_PASSWORD` (optional, for notarization). |
| windows | `P12_PASSWORD` (required for the PKCS12). |
| linux | `GPG_KEY_ID` (required, overrides `info.signing.linux.keyId` if set). |

Signers under the hood:
- `rcodesign` — macOS app/dmg/pkg/productbuild (cross-platform, no Apple host needed).
- `osslsigncode` — Authenticode for `.exe`/`.msi`.
- `dpkg-sig` (embedded deb), `rpmsign --addsign` (embedded rpm), `gpg --detach-sign` (detached `.sig` for any).

## One-shot build + sign (`bundler.signedApp`)

`signedApp` returns a runnable derivation that stages a copy of the bundle and signs it. The bundle stays cached; only the sign step runs impure in your shell.

```nix
my-app-deb-signed = bundler.signedApp { bundle = my-app-deb; };
```

```sh
nix-build -A my-app-deb-signed -o sign-my-app-deb
GPG_KEY_ID=0xABCDEF1234567890 ./sign-my-app-deb/bin/my-app-deb-sign -- ./dist
# → ./dist/<name>.deb (signed). sign.sh removed from output.
```

Pass `--` followed by a target directory; omit for a fresh `mktemp -d`.

Use this in CI so signing is one command instead of two-step `build` → `./result/sign.sh`.

## Notarization (macOS)

`rcodesign` handles notarization when given Apple ID credentials. The generated `sign.sh` calls `rcodesign notary-submit` when `APPLE_ID` + `NOTARIZATION_PASSWORD` are set in the env, then `rcodesign notary-staple`. Skip the env vars to sign without notarizing.

## Gotchas

- `signing.darwin.p12File` and `signing.windows.pkcs12File` are nix paths — they end up in `/nix/store` (the file, *not* the password). That's fine for cert files (public) but **never put the password in `info`**.
- `signing.linux.style = "embedded"` only works for `deb` (via `dpkg-sig`) and `rpm` (via `rpmsign`). For other formats it silently falls back to detached `.sig`.
- `bundleId` and `info.maintainer` must match the cert subject for some windows CAs (DigiCert etc.) — otherwise `signtool` complains.
- `msiUpgradeCode` — sign-related but for upgrades: pin a UUID before publishing any MSI; signing won't help if the upgrade code changes between releases.
