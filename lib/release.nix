{ pkgs, lib }:

# Generates a "ready-to-upload" release directory for cargo-dist-style
# distribution: a flat dir containing every bundle artifact, an `install.sh`
# (Linux/macOS), an `install.ps1` (Windows), and a `SHA256SUMS` file.
#
# Inputs come straight from `bundler.bundle` outputs — we read
# `passthru.{info,target,format,outFile}` so the caller doesn't have to
# duplicate naming logic.

let
  # Maps a (target.arch, target.os) tuple to (uname -m, uname -s) — what the
  # install.sh case-statement will compare against on the user's host.
  archToUname =
    a:
    {
      "x86_64" = "x86_64";
      "aarch64" = "aarch64";
      "armv7l" = "armv7l";
    }
    .${a} or a;

  osToUname =
    o:
    {
      "linux" = "Linux";
      "darwin" = "Darwin";
      "windows" = "Windows";
    }
    .${o} or o;

  # The format we want install.sh / install.ps1 to download for a given target.
  # Linux/Darwin → prefer tar.gz; Windows → prefer zip. Falls back to first
  # available format if neither is present.
  pickInstallFormat =
    formats:
    if builtins.elem "tar.gz" formats then
      "tar.gz"
    else if builtins.elem "zip" formats then
      "zip"
    else
      builtins.head formats;

  # Flattens matrix `{ "x86_64-linux" = { drv; formats }; ... }` into a list of
  # `{ targetKey; arch; os; drv; format; }` entries — one per (target, format).
  flattenMatrix =
    matrix:
    lib.concatMap (
      targetKey:
      let
        entry = matrix.${targetKey};
        parts = lib.splitString "-" targetKey;
        arch = builtins.head parts;
        os = lib.concatStringsSep "-" (builtins.tail parts);
      in
      map (format: {
        inherit
          targetKey
          arch
          os
          format
          ;
        drv = entry.drv;
      }) entry.formats
    ) (builtins.attrNames matrix);

  buildBundle =
    bundlerBundle: info:
    {
      drv,
      arch,
      os,
      format,
      ...
    }:
    bundlerBundle {
      inherit drv format info;
      target = { inherit arch os; };
    };

  # Generates the bash install.sh script. Reads matrix to know what (arch,os)
  # combos exist, and which file to download for each.
  mkInstallSh =
    {
      name,
      version,
      baseUrl,
      installEntries,
    }:
    let
      caseBranches = lib.concatMapStringsSep "\n" (e: ''
        "${archToUname e.arch}|${osToUname e.os}")
          file="${e.outFile}"
          format="${e.format}"
          ;;'') installEntries;
    in
    ''
      #!/bin/sh
      # nix-bundle-app universal installer — generated, do not hand-edit.
      set -eu

      NAME='${name}'
      VERSION='${version}'
      BASE_URL='${baseUrl}'
      INSTALL_DIR=''${INSTALL_DIR:-"$HOME/.local/bin"}

      # CLI flags ---------------------------------------------------------------
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --version)  VERSION="$2"; shift 2 ;;
          --dir)      INSTALL_DIR="$2"; shift 2 ;;
          --uninstall) UNINSTALL=1; shift ;;
          --help|-h)
            cat <<EOF
      $NAME installer.
      Usage: install.sh [--version vX.Y.Z] [--dir <bin-dir>] [--uninstall]
      Env vars: INSTALL_DIR, BASE_URL.
      EOF
            exit 0
            ;;
          *) echo "Unknown arg: $1" >&2; exit 1 ;;
        esac
      done

      if [ "''${UNINSTALL:-0}" = "1" ]; then
        rm -f "$INSTALL_DIR/$NAME" && echo "Removed $INSTALL_DIR/$NAME" || true
        exit 0
      fi

      # Detect host -------------------------------------------------------------
      OS=$(uname -s)
      ARCH=$(uname -m)
      # Normalize a few common aliases.
      case "$ARCH" in amd64) ARCH=x86_64 ;; arm64) ARCH=aarch64 ;; esac

      file=""
      format=""
      case "$ARCH|$OS" in
        ${caseBranches}
        *) echo "Unsupported platform: $ARCH on $OS" >&2; exit 1 ;;
      esac

      URL=$(printf '%s/%s' "$BASE_URL" "$file" | sed "s#\''${VERSION}#$VERSION#g")
      echo "Downloading $URL"

      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT

      if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$URL" -o "$tmp/bundle"
      elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp/bundle" "$URL"
      else
        echo "Need curl or wget on PATH" >&2; exit 1
      fi

      # SHA256 check ------------------------------------------------------------
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$BASE_URL/SHA256SUMS" -o "$tmp/sums" 2>/dev/null || true
      fi
      if [ -f "$tmp/sums" ] && command -v sha256sum >/dev/null 2>&1; then
        expected=$(awk -v f="$file" '$2==f {print $1}' "$tmp/sums" || true)
        if [ -n "$expected" ]; then
          actual=$(sha256sum "$tmp/bundle" | awk '{print $1}')
          if [ "$expected" != "$actual" ]; then
            echo "SHA256 mismatch for $file" >&2
            echo "  expected: $expected" >&2
            echo "  got:      $actual" >&2
            exit 1
          fi
          echo "SHA256 verified."
        fi
      fi

      # Extract + place ---------------------------------------------------------
      case "$format" in
        tar.gz|tar.xz|tar.zst)
          mkdir -p "$tmp/extract"
          tar -xf "$tmp/bundle" -C "$tmp/extract"
          ;;
        zip)
          mkdir -p "$tmp/extract"
          unzip -q "$tmp/bundle" -d "$tmp/extract"
          ;;
        *)
          echo "Format $format isn't extractable by this script (use the native installer)." >&2
          exit 1
          ;;
      esac

      bin=$(find "$tmp/extract" -type f \( -name "$NAME" -o -name "$NAME.exe" \) -perm -100 | head -n1)
      if [ -z "$bin" ]; then
        bin=$(find "$tmp/extract" -type f -name "$NAME" | head -n1)
      fi
      if [ -z "$bin" ]; then
        echo "Could not locate binary '$NAME' inside the extracted bundle." >&2
        exit 1
      fi

      mkdir -p "$INSTALL_DIR"
      install -m 0755 "$bin" "$INSTALL_DIR/$NAME"
      echo "Installed $NAME $VERSION → $INSTALL_DIR/$NAME"

      case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *) echo "Note: $INSTALL_DIR is not on \$PATH. Add it to your shell profile." ;;
      esac
    '';

  mkInstallPs1 =
    {
      name,
      version,
      baseUrl,
      installEntries,
    }:
    let
      branches = lib.concatMapStringsSep "\n" (e: ''
        "${archToUname e.arch}|${osToUname e.os}" {
          $File = "${e.outFile}"
          $Format = "${e.format}"
        }'') installEntries;
    in
    ''
      #!/usr/bin/env pwsh
      # nix-bundle-app universal installer — generated, do not hand-edit.
      $ErrorActionPreference = 'Stop'

      param(
        [string]$Version = '${version}',
        [string]$Dir = $null,
        [switch]$Uninstall
      )

      $Name = '${name}'
      $BaseUrl = '${baseUrl}'
      if (-not $Dir) { $Dir = Join-Path $env:LOCALAPPDATA "Programs\$Name" }

      if ($Uninstall) {
        if (Test-Path "$Dir/$Name.exe") { Remove-Item "$Dir/$Name.exe" }
        if (Test-Path "$Dir/$Name")     { Remove-Item "$Dir/$Name" }
        Write-Host "Removed $Name from $Dir"
        exit 0
      }

      $Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
      $Os = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) { 'Windows' } else { (uname -s) }
      $Key = "$Arch|$Os"

      $File = $null; $Format = $null
      switch ($Key) {
        ${branches}
        default { Write-Error "Unsupported platform: $Key"; exit 1 }
      }

      $Url = "$BaseUrl/$File".Replace('$' + '{VERSION}', $Version)
      Write-Host "Downloading $Url"

      $Tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "$Name-$(Get-Random)")
      $Bundle = Join-Path $Tmp.FullName 'bundle'
      Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Bundle

      # SHA256 check
      try {
        $sums = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/SHA256SUMS" | Select-Object -ExpandProperty Content
        $expected = ($sums -split "`n" | Where-Object { $_ -match "  $File$" } | ForEach-Object { ($_ -split '\s+')[0] })
        if ($expected) {
          $actual = (Get-FileHash -Algorithm SHA256 $Bundle).Hash.ToLower()
          if ($actual -ne $expected.ToLower()) {
            Write-Error "SHA256 mismatch for $File (expected $expected, got $actual)"
            exit 1
          }
          Write-Host "SHA256 verified."
        }
      } catch { }

      $Extract = Join-Path $Tmp.FullName 'extract'
      New-Item -ItemType Directory -Path $Extract | Out-Null
      switch ($Format) {
        'zip' { Expand-Archive -Path $Bundle -DestinationPath $Extract -Force }
        default {
          if (Get-Command tar -ErrorAction SilentlyContinue) { tar -xf $Bundle -C $Extract }
          else { Write-Error "Cannot extract $Format on this host"; exit 1 }
        }
      }

      $Bin = Get-ChildItem -Path $Extract -Recurse -File |
             Where-Object { $_.Name -in @("$Name.exe", $Name) } |
             Select-Object -First 1
      if (-not $Bin) { Write-Error "Binary '$Name' not found inside bundle"; exit 1 }

      New-Item -ItemType Directory -Path $Dir -Force | Out-Null
      Copy-Item $Bin.FullName -Destination (Join-Path $Dir $Bin.Name) -Force
      Write-Host "Installed $Name $Version -> $Dir\$($Bin.Name)"

      $userPath = [Environment]::GetEnvironmentVariable('Path','User')
      if ($userPath -notlike "*$Dir*") {
        Write-Host "Note: $Dir is not on PATH. Add it: setx PATH `"$userPath;$Dir`""
      }

      Remove-Item -Recurse -Force $Tmp.FullName
    '';

  # Builds a release derivation from the matrix.
  release =
    bundlerBundle:
    {
      info ? { },
      baseUrl,
      matrix,
      installScripts ? true,
    }:
    let
      entries = flattenMatrix matrix;

      # Build every bundle.
      built = map (
        e:
        let
          bundle = buildBundle bundlerBundle info e;
        in
        {
          inherit (e)
            targetKey
            arch
            os
            format
            ;
          drv = bundle;
          outFile =
            bundle.passthru.outFile
              or (throw "Bundle ${e.targetKey}/${e.format} lacks passthru.outFile; can't include in release");
        }
      ) entries;

      # Pick one entry per target for the install scripts to download (the
      # "universal" format — tar.gz on unix, zip on windows).
      perTarget = lib.groupBy (e: e.targetKey) built;
      installEntries = lib.mapAttrsToList (
        _: targetEntries:
        let
          fmts = map (e: e.format) targetEntries;
          chosen = pickInstallFormat fmts;
          entry = lib.head (builtins.filter (e: e.format == chosen) targetEntries);
        in
        entry
      ) perTarget;

      # Derive a name + version for the scripts from the first built bundle.
      headInfo = (lib.head built).drv.passthru.info;
      scriptName = headInfo.name;
      scriptVersion = headInfo.version;

      installShText = mkInstallSh {
        name = scriptName;
        version = scriptVersion;
        inherit baseUrl installEntries;
      };
      installPs1Text = mkInstallPs1 {
        name = scriptName;
        version = scriptVersion;
        inherit baseUrl installEntries;
      };

      cpLines = lib.concatMapStringsSep "\n" (b: ''
        cp -L "${b.drv}/${b.outFile}" "$out/${b.outFile}"
        chmod u+w "$out/${b.outFile}"
      '') built;
    in
    pkgs.runCommand "${scriptName}-${scriptVersion}-release"
      {
        passthru = {
          bundles = built;
          info = headInfo;
          inherit baseUrl;
        };
      }
      ''
        mkdir -p $out
        ${cpLines}

        # SHA256SUMS — `<hash>  <filename>` lines, one per artifact.
        ( cd $out && ${pkgs.coreutils}/bin/sha256sum * > SHA256SUMS )

        ${lib.optionalString installScripts ''
          cp ${pkgs.writeText "install.sh" installShText} $out/install.sh
          chmod +x $out/install.sh
          cp ${pkgs.writeText "install.ps1" installPs1Text} $out/install.ps1

          # Append the install scripts to SHA256SUMS too so users can verify them.
          ( cd $out && ${pkgs.coreutils}/bin/sha256sum install.sh install.ps1 >> SHA256SUMS )
        ''}
      '';

  # Standalone installScripts helper — same as `release` but doesn't bundle
  # the artifacts into the output; returns only install.sh + install.ps1.
  # Useful when you publish bundles separately and just want the scripts.
  installScripts =
    bundlerBundle: args:
    let
      r = release bundlerBundle (args // { installScripts = true; });
    in
    pkgs.runCommand "${r.passthru.info.name}-install-scripts" { } ''
      mkdir -p $out
      cp ${r}/install.sh $out/install.sh
      cp ${r}/install.ps1 $out/install.ps1
      chmod +x $out/install.sh
    '';
in
{
  inherit release installScripts;
}
