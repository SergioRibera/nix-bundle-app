# A prerelease `version` (`1.2.0-alpha.1`) packaged for managers that
# reject `-` in versions.
{ helpers }:

let
  inherit (helpers)
    e2e
    drv
    drvWin
    info
    pkgs
    canRpm
    ;
  inherit (pkgs) lib;

  alpha = info // {
    version = "1.2.0-alpha.1";
  };
in
{
  prerelease-deb = e2e {
    name = "prerelease-deb";
    format = "deb";
    inherit drv;
    info = alpha;
    expect = "hello_1.2.0~alpha.1_amd64.deb";
    probeInputs = [ pkgs.dpkg ];
    assertScript = ''
      test "$(dpkg-deb -f "$artifact" Version)" = "1.2.0~alpha.1"
    '';
  };

  prerelease-archlinux = e2e {
    name = "prerelease-archlinux";
    format = "archlinux";
    inherit drv;
    info = alpha;
    expect = "hello-1.2.0_alpha.1-1-x86_64.pkg.tar.zst";
    probeInputs = [ pkgs.libarchive ];
    assertScript = ''
      tmp=$(mktemp -d)
      bsdtar --zstd -xf "$artifact" -C "$tmp" .PKGINFO
      grep -qx "pkgver = 1.2.0_alpha.1-1" "$tmp/.PKGINFO"
    '';
  };

  prerelease-msi = e2e {
    name = "prerelease-msi";
    format = "msi";
    drv = drvWin;
    info = alpha;
    target = {
      arch = "x86_64";
      os = "windows";
    };
    expect = "hello-1.2.0-alpha.1-x64.msi";
    probeInputs = [ pkgs.msitools ];
    assertScript = ''
      msiinfo export "$artifact" Property | grep -P "ProductVersion\t1.2.0\r?$"
    '';
  };
}
// lib.optionalAttrs canRpm {
  prerelease-rpm = e2e {
    name = "prerelease-rpm";
    format = "rpm";
    inherit drv;
    info = alpha;
    expect = "hello-1.2.0~alpha.1-1.x86_64.rpm";
    probeInputs = [ pkgs.rpm ];
    assertScript = ''
      test "$(rpm -qp --queryformat '%{VERSION}' "$artifact")" = "1.2.0~alpha.1"
    '';
  };
}
