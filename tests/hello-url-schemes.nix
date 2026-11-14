# `info.urlSchemes`: `x-scheme-handler` + `%U` on linux, CFBundleURLTypes on
# macOS, `URL Protocol` keys in the MSI and NSIS installers.
{ helpers }:

let
  inherit (helpers)
    bundler
    drv
    drvWin
    e2e
    info
    pkgs
    ;

  schemeInfo = info // {
    bundleId = "org.example.Hello";
    displayName = "Hello World";
    desktopEntries = [
      {
        name = "Hello";
        exec = "hello";
        fileName = "org.example.Hello";
      }
    ];
    urlSchemes = [
      "hello"
      {
        scheme = "hello-dev";
        name = "Hello (dev)";
      }
    ];
  };

  winTarget = {
    arch = "x86_64";
    os = "windows";
  };

  plist =
    (bundler.bundle {
      inherit drv;
      format = "app";
      info = schemeInfo;
      target = {
        arch = "aarch64";
        os = "darwin";
      };
    }).infoPlist;

  nsi =
    (bundler.bundle {
      drv = drvWin;
      format = "nsis";
      info = schemeInfo;
      target = winTarget;
    }).nsi;
in
{
  url-schemes-deb = e2e {
    name = "url-schemes-deb";
    format = "deb";
    inherit drv;
    info = schemeInfo;
    expect = "hello_*_amd64.deb";
    probeInputs = [ pkgs.dpkg ];
    assertScript = ''
      tmp=$(mktemp -d)
      dpkg-deb -x "$artifact" "$tmp"
      desktop="$tmp/usr/share/applications/org.example.Hello.desktop"
      grep -qx "MimeType=x-scheme-handler/hello;x-scheme-handler/hello-dev;" "$desktop"
      grep -qx "Exec=hello %U" "$desktop"
    '';
  };

  url-schemes-plist =
    pkgs.runCommand "e2e-url-schemes-plist"
      {
        nativeBuildInputs = [ pkgs.libxml2 ];
        plist = pkgs.writeText "Info.plist" plist;
      }
      ''
        set -euo pipefail
        xmllint --noout "$plist"
        types='/plist/dict/key[.="CFBundleURLTypes"]/following-sibling::array[1]/dict'
        test "$(xmllint --xpath "count($types)" "$plist")" = 2
        test "$(xmllint --xpath "string($types[1]/key[.='CFBundleURLName']/following-sibling::string[1])" "$plist")" = org.example.Hello.hello
        test "$(xmllint --xpath "string($types[2]/key[.='CFBundleURLSchemes']/following-sibling::array[1]/string)" "$plist")" = hello-dev
        touch $out
      '';

  url-schemes-msi = e2e {
    name = "url-schemes-msi";
    format = "msi";
    drv = drvWin;
    info = schemeInfo;
    target = winTarget;
    expect = "hello-*-x64.msi";
    probeInputs = [ pkgs.msitools ];
    assertScript = ''
      reg=$(msiinfo export "$artifact" Registry | tr -d '\r')
      grep -P "\thello\t\tURL:Hello World\t" <<<"$reg"
      grep -P "\thello-dev\t\tURL:Hello \(dev\)\t" <<<"$reg"
      grep -P "\thello\tURL Protocol\t" <<<"$reg"
      grep -F 'hello-dev\shell\open\command' <<<"$reg"
    '';
  };

  url-schemes-nsis-script = pkgs.runCommand "e2e-url-schemes-nsis-script" { } ''
    nsi=${pkgs.writeText "installer.nsi" nsi}
    grep -qF 'WriteRegStr SHCTX "Software\Classes\hello" "URL Protocol" ""' "$nsi"
    grep -qF 'WriteRegStr SHCTX "Software\Classes\hello-dev" "" "URL:Hello (dev)"' "$nsi"
    grep -qF 'DeleteRegKey SHCTX "Software\Classes\hello-dev"' "$nsi"
    touch $out
  '';
}
