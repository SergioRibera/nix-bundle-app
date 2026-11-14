# `info.icon` + `info.displayName`: every format derives its icon from one
# PNG and shows the human name, while `name` keeps driving paths.
{ helpers }:

let
  inherit (helpers)
    e2e
    drv
    drvWin
    info
    pkgs
    canNsis
    canRpm
    ;
  inherit (pkgs) lib;

  # 64 px opaque square: enough for imagemagick to scale up to 1024.
  iconPng = pkgs.runCommand "icon.png" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    magick -size 64x64 xc:'#C0482F' png32:$out
  '';

  iconInfo = info // {
    displayName = "Hello World";
    bundleId = "org.example.Hello";
    icon = iconPng;
    desktopEntries = [
      {
        name = "Hello World";
        exec = "hello";
        fileName = "org.example.Hello";
      }
    ];
  };

  winTarget = {
    arch = "x86_64";
    os = "windows";
  };
in
{
  icon-deb = e2e {
    name = "icon-deb";
    format = "deb";
    inherit drv;
    info = iconInfo;
    expect = "hello_*_amd64.deb";
    probeInputs = [ pkgs.dpkg ];
    assertScript = ''
      tmp=$(mktemp -d)
      dpkg-deb -x "$artifact" "$tmp"
      for s in 16 32 48 256 512; do
        test -f "$tmp/usr/share/icons/hicolor/''${s}x''${s}/apps/org.example.Hello.png"
      done
      grep -qx "Icon=org.example.Hello" "$tmp/usr/share/applications/org.example.Hello.desktop"
      test -x "$tmp/opt/hello/bin/hello"
    '';
  };

  icon-appimage = e2e {
    name = "icon-appimage";
    format = "appimage";
    inherit drv;
    info = iconInfo;
    expect = "*.AppImage";
    probeInputs = [ pkgs.squashfsTools ];
    assertScript = ''
      # The runtime ELF may contain the magic too; the image is the first
      # offset unsquashfs accepts.
      listing=""
      for offset in $(grep -abo 'hsqs' "$artifact" | cut -d: -f1); do
        if listing=$(unsquashfs -o "$offset" -l "$artifact" 2>/dev/null); then break; fi
      done
      echo "$listing" | grep -q "squashfs-root/org.example.Hello.png"
      echo "$listing" | grep -q "squashfs-root/.DirIcon"
      echo "$listing" | grep -q "usr/share/icons/hicolor/256x256/apps/org.example.Hello.png"
    '';
  };

  icon-snap = e2e {
    name = "icon-snap";
    format = "snap";
    inherit drv;
    info = iconInfo;
    expect = "snap";
    assertScript = ''
      test -f "$artifact/gui/icon.png"
      grep -qx "title: Hello World" "$artifact/snapcraft.yaml"
    '';
  };

  icon-msi = e2e {
    name = "icon-msi";
    format = "msi";
    drv = drvWin;
    info = iconInfo;
    target = winTarget;
    expect = "hello-*-x64.msi";
    probeInputs = [ pkgs.msitools ];
    assertScript = ''
      msiinfo export "$artifact" Icon | grep -F "AppIcon.ico"
      msiinfo export "$artifact" Property | grep -F "ARPPRODUCTICON"
      msiinfo export "$artifact" Property | grep -P "ProductName\tHello World"
      msiinfo export "$artifact" Shortcut | grep -F "AppIcon.ico"
    '';
  };
}
// lib.optionalAttrs canRpm {
  # rpm lists its files explicitly; every size `info.icon` stages must be in it.
  icon-rpm = e2e {
    name = "icon-rpm";
    format = "rpm";
    inherit drv;
    info = iconInfo;
    expect = "hello-*-1.x86_64.rpm";
    probeInputs = [
      pkgs.rpm
      pkgs.cpio
    ];
    assertScript = ''
      tmp=$(mktemp -d)
      ( cd "$tmp" && rpm2cpio "$artifact" | cpio -idm --quiet )
      for s in 16 32 48 256 512; do
        test -f "$tmp/usr/share/icons/hicolor/''${s}x''${s}/apps/org.example.Hello.png"
      done
    '';
  };
}
// lib.optionalAttrs canNsis {
  icon-nsis = e2e {
    name = "icon-nsis";
    format = "nsis";
    drv = drvWin;
    info = iconInfo;
    target = winTarget;
    expect = "hello-*-x64-setup.exe";
    probeInputs = [ pkgs.p7zip ];
    assertScript = ''
      7z l "$artifact" | grep -F "hello.ico"
    '';
  };
}
