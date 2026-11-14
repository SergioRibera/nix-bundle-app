# AppStream metainfo on the linux formats, and `permissions.network.local`
# as flatpak `finish-args` and snap plugs.
{ helpers }:

let
  inherit (helpers)
    canRpm
    drv
    e2e
    info
    pkgs
    ;
  inherit (pkgs) lib;

  guiInfo = info // {
    bundleId = "org.example.Hello";
    displayName = "Hello World";
    summary = "Says hello & waves";
    longDescription = ''
      Prints a friendly greeting.

      Also waves.
    '';
    desktopEntries = [
      {
        name = "Hello";
        exec = "hello";
        fileName = "org.example.Hello";
        categories = [ "Utility" ];
      }
    ];
    appstream.releaseDate = "2026-11-14";
    appstream.screenshots = [
      {
        image = "https://example.com/hello.png";
        caption = "Saying hello";
      }
    ];
    permissions.network.local = {
      reason = "Finds friends on your network.";
      udp = [ 7701 ];
    };
  };

  metainfo = "usr/share/metainfo/org.example.Hello.metainfo.xml";

  checkMetainfo = file: ''
    appstreamcli validate --no-net --explain "${file}"
    grep -qF '<launchable type="desktop-id">org.example.Hello.desktop</launchable>' "${file}"
    grep -qF '<summary>Says hello &amp; waves</summary>' "${file}"
    grep -qF '<p>Also waves.</p>' "${file}"
    grep -qF '<developer id="org.example">' "${file}"
    grep -qF '<release version="2.12.3" date="2026-11-14"/>' "${file}"
  '';
in
{
  linux-metainfo-deb = e2e {
    name = "linux-metainfo-deb";
    format = "deb";
    inherit drv;
    info = guiInfo;
    expect = "hello_*_amd64.deb";
    probeInputs = [
      pkgs.dpkg
      pkgs.appstream
    ];
    assertScript = ''
      tmp=$(mktemp -d)
      dpkg-deb -x "$artifact" "$tmp"
      ${checkMetainfo "$tmp/${metainfo}"}
    '';
  };

  # No desktop entry: no metainfo unless asked for, then a console app.
  linux-metainfo-console = e2e {
    name = "linux-metainfo-console";
    format = "deb";
    inherit drv;
    info = info // {
      appstream.enable = true;
    };
    expect = "hello_*_amd64.deb";
    probeInputs = [
      pkgs.dpkg
      pkgs.appstream
    ];
    assertScript = ''
      tmp=$(mktemp -d)
      dpkg-deb -x "$artifact" "$tmp"
      file=$(echo "$tmp"/usr/share/metainfo/*.metainfo.xml)
      grep -qF '<component type="console-application">' "$file"
      grep -qF '<binary>hello</binary>' "$file"
      appstreamcli validate --no-net "$file"
    '';
  };

  linux-metainfo-appimage = e2e {
    name = "linux-metainfo-appimage";
    format = "appimage";
    inherit drv;
    info = guiInfo;
    expect = "*.AppImage";
    probeInputs = [
      pkgs.squashfsTools
      pkgs.appstream
    ];
    assertScript = ''
      tmp=$(mktemp -d)
      for offset in $(grep -abo 'hsqs' "$artifact" | cut -d: -f1); do
        if unsquashfs -q -o "$offset" -d "$tmp/root" "$artifact" >/dev/null 2>&1; then break; fi
      done
      ${checkMetainfo "$tmp/root/${metainfo}"}
    '';
  };

  linux-network-flatpak = e2e {
    name = "linux-network-flatpak";
    format = "flatpak";
    inherit drv;
    info = guiInfo;
    expect = "org.example.Hello.yaml";
    assertScript = ''
      grep -qx '  - --share=network' "$artifact"
      grep -qF 'install -Dm644 -t /app/share/metainfo' "$artifact"
      # appstream compose needs the desktop entry installed and runnable
      # from /app/bin.
      grep -qF 'install -Dm644 -t /app/share/applications' "$artifact"
      grep -qF "sed -i 's|=/opt/" "$artifact"
    '';
  };

  linux-network-snap = e2e {
    name = "linux-network-snap";
    format = "snap";
    inherit drv;
    info = guiInfo;
    expect = "snap/snapcraft.yaml";
    assertScript = ''
      grep -qx '      - network-bind' "$artifact"
      test "$(grep -cx '      - network' "$artifact")" -ge 1
    '';
  };
}
// lib.optionalAttrs canRpm {
  linux-metainfo-rpm = e2e {
    name = "linux-metainfo-rpm";
    format = "rpm";
    inherit drv;
    info = guiInfo;
    expect = "hello-*-1.x86_64.rpm";
    probeInputs = [ pkgs.rpm ];
    assertScript = ''
      rpm -qlp "$artifact" | grep -qx "/${metainfo}"
    '';
  };
}
