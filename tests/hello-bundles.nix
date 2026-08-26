# Filename-only smoke checks for the canonical `pkgs.hello` drv across every
# format. Asserts that the bundler produces the expected artifact name under
# `result/`.
{ helpers }:

let
  inherit (helpers)
    check
    drv
    drvWin
    drvDarwin
    info
    pkgs
    canNsis
    canRpm
    ;
  inherit (pkgs) lib;
in
lib.optionalAttrs canNsis {
  bundle-nsis = check {
    name = "nsis";
    format = "nsis";
    drv = drvWin;
    inherit info;
    target = {
      arch = "x86_64";
      os = "windows";
    };
    expect = "hello-*-x64-setup.exe";
  };
}
// lib.optionalAttrs canRpm {
  bundle-rpm = check {
    name = "rpm";
    format = "rpm";
    inherit drv info;
    expect = "hello-*-1.x86_64.rpm";
  };
}
// {
  bundle-deb = check {
    name = "deb";
    format = "deb";
    inherit drv info;
    expect = "hello_*_amd64.deb";
  };

  bundle-archlinux = check {
    name = "archlinux";
    format = "archlinux";
    inherit drv info;
    expect = "hello-*-1-x86_64.pkg.tar.zst";
  };

  bundle-tar-gz = check {
    name = "tar-gz";
    format = "tar.gz";
    inherit drv info;
    expect = "hello-*-x86_64-linux.tar.gz";
  };

  bundle-zip = check {
    name = "zip";
    format = "zip";
    inherit drv info;
    expect = "hello-*-x86_64-linux.zip";
  };

  bundle-appimage = check {
    name = "appimage";
    format = "appimage";
    inherit drv info;
    expect = "hello-*-x86_64.AppImage";
  };

  bundle-app = check {
    name = "app";
    format = "app";
    drv = drvDarwin;
    inherit info;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
    expect = "hello.app";
  };

  bundle-pkg = check {
    name = "pkg";
    format = "pkg";
    drv = drvDarwin;
    inherit info;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
    expect = "hello-*-x86_64.pkg";
  };

  bundle-productbuild = check {
    name = "productbuild";
    format = "productbuild";
    drv = drvDarwin;
    info = info // {
      productbuild = {
        title = "Hello Installer";
        license = pkgs.writeText "license.txt" "MIT.";
      };
    };
    target = {
      arch = "x86_64";
      os = "darwin";
    };
    expect = "hello-*-x86_64-install.pkg";
  };

  bundle-brew = check {
    name = "brew";
    format = "brew";
    drv = drvDarwin;
    inherit info;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
    expect = "hello.rb";
  };

  bundle-brew-linux = check {
    name = "brew-linux";
    format = "brew";
    inherit drv info;
    target = {
      arch = "x86_64";
      os = "linux";
    };
    expect = "hello.rb";
  };

  bundle-msi = check {
    name = "msi";
    format = "msi";
    drv = drvWin;
    inherit info;
    target = {
      arch = "x86_64";
      os = "windows";
    };
    expect = "hello-*-x64.msi";
  };
}
