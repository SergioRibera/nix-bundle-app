# `info.macos` + `info.permissions`: the generated Info.plist, the renamed
# macOS options and entitlements embedded in sign.sh.
{ helpers }:

let
  inherit (helpers)
    bundler
    drv
    info
    pkgs
    ;
  inherit (pkgs) lib;

  darwinTarget = {
    arch = "aarch64";
    os = "darwin";
  };

  # Eval-level: the `.app` needs a darwin binary to build, the plist doesn't.
  plist =
    extra:
    pkgs.writeText "Info.plist"
      (bundler.bundle {
        inherit drv;
        format = "app";
        info = info // extra;
        target = darwinTarget;
      }).infoPlist;

  macInfo = plist {
    displayName = ''Say <hi> & "bye"'';
    macos = {
      category = "public.app-category.developer-tools";
      copyright = "© 2026 Example";
      buildVersion = "42";
      infoPlist = {
        LSUIElement = true;
        # infoPlist wins over generated keys.
        NSPrincipalClass = "MyApplication";
      };
    };
    permissions.network.local.reason = "Finds apps on your network.";
  };

  # The pre-`macos` names keep working (with a deprecation warning).
  legacyInfo = plist {
    minimumSystemVersion = "11.0";
    bundleSignature = "HELO";
  };

  signScript = (import ../lib/signing.nix { inherit lib; }).pickScript {
    signing.darwin = {
      enable = true;
      p12File = null;
      teamId = "";
      hardenedRuntime = true;
      entitlements = null;
    };
    entitlements = {
      "com.apple.security.network.client" = true;
    };
    format = "app";
    artifactGlob = "*.app";
  };
in
{
  macos-plist =
    pkgs.runCommand "e2e-macos-plist"
      {
        nativeBuildInputs = [ pkgs.libxml2 ];
        inherit macInfo legacyInfo;
      }
      ''
        set -euo pipefail
        xmllint --noout "$macInfo"
        value() { xmllint --xpath "string(/plist/dict/key[.='$2']/following-sibling::*[1])" "$1"; }
        test "$(value "$macInfo" CFBundleName)" = 'Say <hi> & "bye"'
        test "$(value "$macInfo" LSApplicationCategoryType)" = public.app-category.developer-tools
        test "$(value "$macInfo" NSHumanReadableCopyright)" = '© 2026 Example'
        test "$(value "$macInfo" CFBundleVersion)" = 42
        test "$(value "$macInfo" NSLocalNetworkUsageDescription)" = 'Finds apps on your network.'
        test "$(value "$macInfo" NSPrincipalClass)" = MyApplication
        test "$(xmllint --xpath "name(/plist/dict/key[.='LSUIElement']/following-sibling::*[1])" "$macInfo")" = true
        test "$(value "$legacyInfo" LSMinimumSystemVersion)" = 11.0
        test "$(value "$legacyInfo" CFBundleSignature)" = HELO
        if grep -q NSLocalNetworkUsageDescription "$legacyInfo"; then exit 1; fi
        touch $out
      '';

  macos-entitlements =
    pkgs.runCommand "e2e-macos-entitlements"
      {
        nativeBuildInputs = [ pkgs.libxml2 ];
        signScript = pkgs.writeShellScript "sign.sh" signScript;
      }
      ''
        set -euo pipefail
        work=$(mktemp -d)
        cp "$signScript" "$work/sign.sh"
        mkdir "$work/Hello.app" "$work/bin"
        touch "$work/id.p12"
        # Stand-in for rcodesign: keep the entitlements file it is handed.
        cat > "$work/bin/rcodesign" <<'EOF'
        #!${pkgs.runtimeShell}
        while [ $# -gt 0 ]; do
          if [ "$1" = --entitlements-xml-path ]; then cp "$2" "$OUT_ENTITLEMENTS"; fi
          shift
        done
        EOF
        chmod +x "$work/bin/rcodesign"
        PATH="$work/bin:$PATH" P12_FILE="$work/id.p12" P12_PASSWORD=x \
          OUT_ENTITLEMENTS="$work/seen.plist" bash "$work/sign.sh"
        xmllint --noout "$work/seen.plist"
        test "$(xmllint --xpath "name(/plist/dict/key[.='com.apple.security.network.client']/following-sibling::*[1])" "$work/seen.plist")" = true
        touch $out
      '';
}
