# End-to-end linux bundle tests: build a real Rust binary, bundle it, then
# extract the artifact and assert the binary + manifest land correctly.
{ helpers }:

let
  inherit (helpers)
    e2e
    pkgs
    rustInfo
    rustLinux
    rustName
    rustVersion
    ;
in
{
  rust-deb = e2e {
    name = "rust-deb";
    format = "deb";
    drv = rustLinux;
    info = rustInfo;
    expect = "${rustName}_${rustVersion}_amd64.deb";
    probeInputs = [ pkgs.dpkg ];
    assertScript = ''
      tmp=$(mktemp -d)
      dpkg-deb -x "$artifact" "$tmp"
      test -x "$tmp/opt/${rustName}/bin/${rustName}"
      dpkg-deb -e "$artifact" "$tmp/CONTROL"
      grep -q "Package: ${rustName}" "$tmp/CONTROL/control"
      grep -q "Depends:" "$tmp/CONTROL/control"
    '';
  };

  rust-rpm = e2e {
    name = "rust-rpm";
    format = "rpm";
    drv = rustLinux;
    info = rustInfo;
    expect = "${rustName}-${rustVersion}-1.x86_64.rpm";
    probeInputs = [
      pkgs.rpm
      pkgs.cpio
    ];
    assertScript = ''
      tmp=$(mktemp -d)
      ( cd "$tmp" && rpm2cpio "$artifact" | cpio -idm 2>/dev/null )
      test -x "$tmp/opt/${rustName}/bin/${rustName}"
    '';
  };

  rust-archlinux = e2e {
    name = "rust-archlinux";
    format = "archlinux";
    drv = rustLinux;
    info = rustInfo;
    expect = "${rustName}-${rustVersion}-1-x86_64.pkg.tar.zst";
    probeInputs = [ pkgs.libarchive ];
    assertScript = ''
      tmp=$(mktemp -d)
      bsdtar --zstd -xf "$artifact" -C "$tmp"
      test -x "$tmp/opt/${rustName}/bin/${rustName}"
      grep -q "pkgname = ${rustName}" "$tmp/.PKGINFO"
    '';
  };

  rust-appimage = e2e {
    name = "rust-appimage";
    format = "appimage";
    drv = rustLinux;
    info = rustInfo;
    expect = "${rustName}-${rustVersion}-x86_64.AppImage";
    assertScript = ''
      # type2-runtime ELF prefix + appended squashfs. Both should be present
      # (file size > the runtime alone, which is ~200KB).
      sz=$(stat -c '%s' "$artifact")
      test "$sz" -gt 250000
      head -c 4 "$artifact" | grep -q ELF || \
        head -c 4 "$artifact" | od -c | head -1 | grep -q '177 E L F'
    '';
  };

  rust-tar-gz = e2e {
    name = "rust-tar-gz";
    format = "tar.gz";
    drv = rustLinux;
    info = rustInfo;
    expect = "${rustName}-${rustVersion}-x86_64-linux.tar.gz";
    assertScript = ''
      tmp=$(mktemp -d)
      tar -xzf "$artifact" -C "$tmp"
      test -x "$tmp/${rustName}-${rustVersion}/opt/${rustName}/bin/${rustName}"
    '';
  };

  rust-zip = e2e {
    name = "rust-zip";
    format = "zip";
    drv = rustLinux;
    info = rustInfo;
    expect = "${rustName}-${rustVersion}-x86_64-linux.zip";
    probeInputs = [ pkgs.unzip ];
    assertScript = ''
      tmp=$(mktemp -d)
      unzip -q "$artifact" -d "$tmp"
      test -x "$tmp/${rustName}-${rustVersion}/bin/${rustName}"
    '';
  };
}
