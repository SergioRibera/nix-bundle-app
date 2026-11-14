# `info.fileAssociations`: desktop `MimeType=` + shared-mime-info on linux,
# document types in Info.plist, ProgIDs in the MSI and NSIS installers.
{ helpers }:

let
  inherit (helpers)
    e2e
    bundler
    drv
    drvWin
    info
    pkgs
    canNsis
    canRpm
    ;
  inherit (pkgs) lib;

  assocInfo = info // {
    bundleId = "org.example.Hello";
    desktopEntries = [
      {
        name = "Hello";
        exec = "hello";
        fileName = "org.example.Hello";
      }
      {
        name = "Hello Text";
        exec = "hello --text %f";
        fileName = "org.example.Hello.text";
        mimeTypes = [ "text/plain" ];
      }
    ];
    fileAssociations = [
      {
        id = "org.example.hello.document";
        name = "Hello document";
        extensions = [ "hello" ];
        mimeTypes = [ "application/x-hello" ];
        role = "editor";
        rank = "owner";
        exported = true;
      }
      {
        id = "com.adobe.pdf";
        name = "PDF document";
        extensions = [ "pdf" ];
        mimeTypes = [
          "application/pdf"
          "application/x-hello"
        ];
      }
      {
        id = "org.example.other.sheet";
        name = "Other sheet";
        extensions = [ "sheet" ];
      }
    ];
  };

  winTarget = {
    arch = "x86_64";
    os = "windows";
  };

  # Eval-level: the `.app` needs a darwin binary to build, the plist doesn't.
  plist =
    (bundler.bundle {
      inherit drv;
      format = "app";
      info = assocInfo;
      target = {
        arch = "x86_64";
        os = "darwin";
      };
    }).infoPlist;

  nsi =
    (bundler.bundle {
      drv = drvWin;
      format = "nsis";
      info = assocInfo;
      target = winTarget;
    }).nsi;

  linuxAsserts = root: ''
    desktop="${root}/usr/share/applications/org.example.Hello.desktop"
    grep -qx "MimeType=application/x-hello;application/pdf;" "$desktop"
    grep -qx "Exec=hello %F" "$desktop"
    grep -qx "MimeType=text/plain;" "${root}/usr/share/applications/org.example.Hello.text.desktop"
    mime="${root}/usr/share/mime/packages/org.example.Hello.xml"
    xmllint --noout "$mime"
    grep -q '<mime-type type="application/x-hello">' "$mime"
    grep -q '<glob pattern="\*.hello"/>' "$mime"
    grep -q '<comment>Hello document</comment>' "$mime"
    if grep -q 'application/pdf' "$mime"; then exit 1; fi
  '';
in
{
  file-associations-deb = e2e {
    name = "file-associations-deb";
    format = "deb";
    inherit drv;
    info = assocInfo;
    expect = "hello_*_amd64.deb";
    probeInputs = [
      pkgs.dpkg
      pkgs.libxml2
    ];
    assertScript = ''
      tmp=$(mktemp -d)
      dpkg-deb -x "$artifact" "$tmp"
      ${linuxAsserts "$tmp"}
    '';
  };

  file-associations-plist =
    pkgs.runCommand "e2e-file-associations-plist"
      {
        nativeBuildInputs = [ pkgs.libxml2 ];
        plist = pkgs.writeText "Info.plist" plist;
      }
      ''
        set -euo pipefail
        xmllint --noout "$plist"
        # One string per `<key>` lookup: the value that follows the key.
        value() { xmllint --xpath "string(($1)[1])" "$plist"; }
        docs='/plist/dict/key[.="CFBundleDocumentTypes"]/following-sibling::array[1]/dict'
        test "$(xmllint --xpath "count($docs)" "$plist")" = 3
        test "$(value "$docs[1]/key[.='CFBundleTypeRole']/following-sibling::string[1]")" = Editor
        test "$(value "$docs[1]/key[.='LSHandlerRank']/following-sibling::string[1]")" = Owner
        test "$(value "$docs[2]/key[.='LSItemContentTypes']/following-sibling::array[1]/string")" = com.adobe.pdf
        test "$(value "$docs[2]/key[.='CFBundleTypeRole']/following-sibling::string[1]")" = Viewer
        exported='/plist/dict/key[.="UTExportedTypeDeclarations"]/following-sibling::array[1]/dict'
        test "$(xmllint --xpath "count($exported)" "$plist")" = 1
        test "$(value "$exported/key[.='UTTypeIdentifier']/following-sibling::string[1]")" = org.example.hello.document
        test "$(value "$exported//key[.='public.filename-extension']/following-sibling::array[1]/string")" = hello
        imported='/plist/dict/key[.="UTImportedTypeDeclarations"]/following-sibling::array[1]/dict'
        # com.adobe.pdf is a system type and stays out of the imports.
        test "$(xmllint --xpath "count($imported)" "$plist")" = 1
        test "$(value "$imported/key[.='UTTypeIdentifier']/following-sibling::string[1]")" = org.example.other.sheet
        mkdir -p $out
        echo "ok file-associations-plist" > $out/result
      '';

  file-associations-msi = e2e {
    name = "file-associations-msi";
    format = "msi";
    drv = drvWin;
    info = assocInfo;
    target = winTarget;
    expect = "hello-*-x64.msi";
    probeInputs = [ pkgs.msitools ];
    assertScript = ''
      reg=$(msiinfo export "$artifact" Registry | tr -d '\r')
      echo "$reg"
      has() { printf '%s\n' "$reg" | grep -qP "$1"; }
      has '\t0\torg\.example\.hello\.document\t\tHello document\tFileAssociations$'
      has '\t0\torg\.example\.hello\.document\\shell\\open\\command\t\t"\[INSTALLFOLDER\]hello\.exe" "%1"\t'
      has '\t0\t\.hello\\OpenWithProgids\torg\.example\.hello\.document\t\t'
      has '\t0\t\.hello\t\torg\.example\.hello\.document\t'
      has '\t0\t\.pdf\\OpenWithProgids\torg\.example\.Hello\.pdf\t\t'
      # Only `owner` types take the extension default.
      if has '\t0\t\.pdf\t\t'; then exit 1; fi
    '';
  };
}
// lib.optionalAttrs canRpm {
  file-associations-rpm = e2e {
    name = "file-associations-rpm";
    format = "rpm";
    inherit drv;
    info = assocInfo;
    expect = "hello-*-1.x86_64.rpm";
    probeInputs = [
      pkgs.rpm
      pkgs.cpio
      pkgs.libxml2
    ];
    assertScript = ''
      tmp=$(mktemp -d)
      ( cd "$tmp" && rpm2cpio "$artifact" | cpio -idm --quiet )
      ${linuxAsserts "$tmp"}
    '';
  };
}
// lib.optionalAttrs canNsis {
  file-associations-nsis = e2e {
    name = "file-associations-nsis";
    format = "nsis";
    drv = drvWin;
    info = assocInfo;
    target = winTarget;
    expect = "hello-*-x64-setup.exe";
    assertScript = ''
      nsi=${pkgs.writeText "installer.nsi" nsi}
      grep -qF 'Software\Classes\org.example.hello.document\shell\open\command" ""' "$nsi"
      grep -qF '"$INSTDIR\hello.exe" "%1"' "$nsi"
      grep -qF 'WriteRegStr SHCTX "Software\Classes\.hello" "" "org.example.hello.document"' "$nsi"
      grep -qF 'WriteRegStr SHCTX "Software\Classes\.pdf\OpenWithProgids" "org.example.Hello.pdf" ""' "$nsi"
      if grep -qF 'WriteRegStr SHCTX "Software\Classes\.pdf" ""' "$nsi"; then exit 1; fi
      grep -qF 'DeleteRegKey SHCTX "Software\Classes\org.example.hello.document"' "$nsi"
      grep -qF 'StrCmp $0 "org.example.hello.document" 0 +2' "$nsi"
    '';
  };
}
