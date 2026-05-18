{ pkgs, lib }:

# Codesigning helpers. Bundles ship unsigned out of the Nix sandbox (secrets
# can't safely live in /nix/store). When `info.signing.<os>.enable = true`,
# each format drops a turnkey `sign.sh` next to the artifact. Users run it
# post-build, passing keys/passwords via env vars at runtime.

let
  # rcodesign — Apple-style signing without a macOS host. Works on linux.
  darwinScript = cfg: artifactGlob: ''
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(cd "$(dirname "$0")" && pwd)
    : "''${P12_FILE:=${if cfg.p12File != null then toString cfg.p12File else ""}}"
    : "''${P12_PASSWORD:=}"
    : "''${TEAM_ID:=${cfg.teamId}}"

    if ! command -v rcodesign >/dev/null 2>&1; then
      echo "rcodesign not in PATH. Install: 'cargo install apple-codesign' or nix shell nixpkgs#rcodesign" >&2
      exit 1
    fi
    if [ -z "$P12_FILE" ]; then
      echo "Set P12_FILE (or info.signing.darwin.p12File) to a .p12 signing identity." >&2
      exit 1
    fi
    if [ ! -f "$P12_FILE" ]; then
      echo "P12_FILE='$P12_FILE' does not exist." >&2
      exit 1
    fi

    args=( sign )
    args+=( --p12-file "$P12_FILE" )
    if [ -n "$P12_PASSWORD" ]; then
      args+=( --p12-password "$P12_PASSWORD" )
    else
      args+=( --p12-password-interactive )
    fi
    ${lib.optionalString cfg.hardenedRuntime "args+=( --code-signature-flags runtime )"}
    ${lib.optionalString (
      cfg.entitlements != null
    ) ''args+=( --entitlements-xml-path "${toString cfg.entitlements}" )''}
    ${lib.optionalString (cfg.teamId != "") ''args+=( --team-name "$TEAM_ID" )''}

    shopt -s nullglob
    hits=( "$here"/${artifactGlob} )
    if [ "''${#hits[@]}" -eq 0 ]; then
      echo "No artifact matching '${artifactGlob}' under $here." >&2
      exit 1
    fi
    for a in "''${hits[@]}"; do
      echo "==> rcodesign $(basename "$a")"
      rcodesign "''${args[@]}" "$a"
    done
    echo "Signed ''${#hits[@]} artifact(s)."
  '';

  # osslsigncode — Authenticode signing for Windows artifacts. Works on linux.
  windowsScript = cfg: artifactGlob: ''
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(cd "$(dirname "$0")" && pwd)
    : "''${PKCS12_FILE:=${if cfg.pkcs12File != null then toString cfg.pkcs12File else ""}}"
    : "''${PKCS12_PASSWORD:=}"
    : "''${TIMESTAMP_URL:=${cfg.timestampUrl}}"

    if ! command -v osslsigncode >/dev/null 2>&1; then
      echo "osslsigncode not in PATH. Install via 'nix shell nixpkgs#osslsigncode'." >&2
      exit 1
    fi
    if [ -z "$PKCS12_FILE" ]; then
      echo "Set PKCS12_FILE (or info.signing.windows.pkcs12File) to a .pfx/.p12 cert." >&2
      exit 1
    fi
    if [ ! -f "$PKCS12_FILE" ]; then
      echo "PKCS12_FILE='$PKCS12_FILE' does not exist." >&2
      exit 1
    fi

    args=( sign -pkcs12 "$PKCS12_FILE" )
    if [ -n "$PKCS12_PASSWORD" ]; then
      args+=( -pass "$PKCS12_PASSWORD" )
    fi
    ${lib.optionalString (cfg.description != "") ''args+=( -n "${cfg.description}" )''}
    ${lib.optionalString (cfg.url != "") ''args+=( -i "${cfg.url}" )''}
    if [ -n "$TIMESTAMP_URL" ]; then
      args+=( -t "$TIMESTAMP_URL" )
    fi

    shopt -s nullglob
    hits=( "$here"/${artifactGlob} )
    if [ "''${#hits[@]}" -eq 0 ]; then
      echo "No artifact matching '${artifactGlob}' under $here." >&2
      exit 1
    fi
    for a in "''${hits[@]}"; do
      signed="''${a}.signed"
      echo "==> osslsigncode $(basename "$a")"
      osslsigncode "''${args[@]}" -in "$a" -out "$signed"
      mv "$signed" "$a"
    done
    echo "Signed ''${#hits[@]} artifact(s)."
  '';

  # GPG-detached signing — applies to deb/rpm/appimage/archlinux + raw tarballs.
  # Produces `<artifact>.sig` (binary) next to the artifact.
  gpgScript = cfg: artifactGlob: ''
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(cd "$(dirname "$0")" && pwd)
    : "''${GPG_KEY_ID:=${cfg.keyId}}"
    : "''${GNUPGHOME:=''${GNUPGHOME:-$HOME/.gnupg}}"

    if ! command -v gpg >/dev/null 2>&1; then
      echo "gpg not in PATH. Install via 'nix shell nixpkgs#gnupg'." >&2
      exit 1
    fi
    if [ -z "$GPG_KEY_ID" ]; then
      echo "Set GPG_KEY_ID (or info.signing.linux.keyId) to your signing fingerprint." >&2
      exit 1
    fi

    shopt -s nullglob
    hits=( "$here"/${artifactGlob} )
    if [ "''${#hits[@]}" -eq 0 ]; then
      echo "No artifact matching '${artifactGlob}' under $here." >&2
      exit 1
    fi
    for a in "''${hits[@]}"; do
      echo "==> gpg --detach-sign $(basename "$a")"
      gpg --batch --yes --local-user "$GPG_KEY_ID" \
          --output "''${a}.sig" --detach-sign "$a"
    done
    echo "Signed ''${#hits[@]} artifact(s) (GPG detached)."
  '';

  # `dpkg-sig --sign builder` — embeds GPG sig directly inside the .deb.
  dpkgSigScript = cfg: artifactGlob: ''
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(cd "$(dirname "$0")" && pwd)
    : "''${GPG_KEY_ID:=${cfg.keyId}}"

    if ! command -v dpkg-sig >/dev/null 2>&1; then
      echo "dpkg-sig not in PATH. Install via 'nix shell nixpkgs#dpkg-sig'." >&2
      exit 1
    fi
    if [ -z "$GPG_KEY_ID" ]; then
      echo "Set GPG_KEY_ID (or info.signing.linux.keyId) to your signing fingerprint." >&2
      exit 1
    fi

    shopt -s nullglob
    hits=( "$here"/${artifactGlob} )
    for a in "''${hits[@]}"; do
      echo "==> dpkg-sig --sign builder $(basename "$a")"
      dpkg-sig -k "$GPG_KEY_ID" --sign builder "$a"
    done
    echo "Signed ''${#hits[@]} .deb(s) (embedded GPG sig)."
  '';

  # `rpmsign --addsign` — embeds GPG sig directly inside the .rpm.
  rpmsignScript = cfg: artifactGlob: ''
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(cd "$(dirname "$0")" && pwd)
    : "''${GPG_KEY_ID:=${cfg.keyId}}"

    if ! command -v rpmsign >/dev/null 2>&1; then
      echo "rpmsign not in PATH. Install via 'nix shell nixpkgs#rpm'." >&2
      exit 1
    fi
    if [ -z "$GPG_KEY_ID" ]; then
      echo "Set GPG_KEY_ID (or info.signing.linux.keyId) to your signing fingerprint." >&2
      exit 1
    fi

    shopt -s nullglob
    hits=( "$here"/${artifactGlob} )
    for a in "''${hits[@]}"; do
      echo "==> rpm --addsign $(basename "$a")"
      rpm --define "_gpg_name $GPG_KEY_ID" --addsign "$a"
    done
    echo "Signed ''${#hits[@]} .rpm(s) (embedded GPG sig)."
  '';

  # Emits a `sign.sh` into $out if the relevant per-OS signing block is enabled.
  # Pass at the end of any format's buildCommand:
  #   ${signing.emitSignScript { inherit meta format; artifactGlob = "*.deb"; }}
  emitSignScript =
    {
      meta,
      format,
      artifactGlob,
    }:
    let
      script = pickScript {
        signing = meta.signing;
        inherit format artifactGlob;
      };
    in
    if script == null then
      ""
    else
      ''
        cat > $out/sign.sh <<'SIGNEOF'
        ${script}
        SIGNEOF
        chmod +x $out/sign.sh
      '';

  pickScript =
    {
      signing,
      format,
      artifactGlob,
    }:
    let
      d = signing.darwin;
      w = signing.windows;
      l = signing.linux;
    in
    if format == "app" || format == "dmg" || format == "pkg" || format == "productbuild" then
      if d.enable then darwinScript d artifactGlob else null
    else if format == "nsis" || format == "exe" || format == "msi" then
      if w.enable then windowsScript w artifactGlob else null
    else if format == "deb" then
      if l.enable then
        (if l.style == "embedded" then dpkgSigScript l artifactGlob else gpgScript l artifactGlob)
      else
        null
    else if format == "rpm" then
      if l.enable then
        (if l.style == "embedded" then rpmsignScript l artifactGlob else gpgScript l artifactGlob)
      else
        null
    else if format == "appimage" || format == "archlinux" then
      if l.enable then gpgScript l artifactGlob else null
    else
      null;
  formatPlatform =
    format:
    if format == "app" || format == "dmg" || format == "pkg" || format == "productbuild" then
      "darwin"
    else if format == "nsis" || format == "exe" || format == "msi" then
      "windows"
    else if format == "deb" || format == "rpm" || format == "archlinux" || format == "appimage" then
      "linux"
    else
      null;

  # Tools the auto-sign wrapper needs on PATH for each style of signer.
  signerTools =
    {
      platform,
      style,
    }:
    if platform == "darwin" then
      [ pkgs.rcodesign ]
    else if platform == "windows" then
      [ pkgs.osslsigncode ]
    else if platform == "linux" then
      [ pkgs.gnupg ]
      ++ (
        if style == "embedded" then
          [
            pkgs.dpkg-sig
            pkgs.rpm
          ]
        else
          [ ]
      )
    else
      [ ];

  # Wrap a bundle derivation in an impure derivation that runs sign.sh
  # right after the build, producing a pre-signed output. Returns the bundle
  # unchanged if `auto` is not enabled for the relevant platform.
  wrapAutoSign =
    {
      meta,
      format,
      bundle,
    }:
    let
      platform = formatPlatform format;
      enabled =
        platform != null
        && meta.signing.${platform}.enable or false
        && meta.signing.${platform}.auto or false;
      style = meta.signing.linux.style or "detached";
      tools = signerTools { inherit platform style; };
    in
    if !enabled then
      bundle
    else
      pkgs.stdenv.mkDerivation {
        name = "${bundle.name}-signed";
        dontUnpack = true;

        # `__impure = true` requires `experimental-features =
        # impure-derivations ca-derivations` in nix config. Output is not
        # cached — every build re-runs the signer.
        __impure = true;

        # Pass secrets / cert paths through from the calling shell.
        impureEnvVars = [
          "P12_FILE"
          "P12_PASSWORD"
          "TEAM_ID"
          "PKCS12_FILE"
          "PKCS12_PASSWORD"
          "TIMESTAMP_URL"
          "GPG_KEY_ID"
          "GNUPGHOME"
          "GPG_TTY"
          "HOME"
        ];

        nativeBuildInputs = tools ++ [
          pkgs.coreutils
          pkgs.bash
        ];

        buildCommand = ''
          mkdir -p $out
          cp -r --no-preserve=mode,ownership ${bundle}/. $out/
          chmod -R u+w $out
          if [ -x "$out/sign.sh" ]; then
            ( cd $out && bash ./sign.sh )
            rm -f $out/sign.sh
          else
            echo "warning: auto-sign enabled but no sign.sh produced — bundle left unsigned." >&2
          fi
        '';

        passthru = (bundle.passthru or { }) // {
          unsignedBundle = bundle;
          signedAutomatically = true;
        };
      };
in
{
  inherit
    pickScript
    emitSignScript
    wrapAutoSign
    formatPlatform
    ;
}
