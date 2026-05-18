{ pkgs, bundler }:

let
  drv = pkgs.hello;
  drvWin = if pkgs.stdenv.isLinux then pkgs.pkgsCross.mingwW64.hello else pkgs.hello;

  info = {
    homepage = "https://example.com";
    maintainer = "tests <noreply@example.com>";
    license = "GPL-3.0";
  };

  check =
    {
      name,
      format,
      drv,
      target ? null,
      info ? { },
      expect,
    }:
    let
      built = bundler.bundle {
        inherit
          drv
          format
          info
          target
          ;
      };
    in
    pkgs.runCommand "check-${name}" { } ''
      if [ ! -d "${built}" ]; then
        echo "bundle output missing: ${built}" >&2; exit 1
      fi
      found=0
      for f in ${built}/*; do
        name=$(basename "$f")
        case "$name" in
          ${expect}) found=1; break ;;
        esac
      done
      if [ $found -ne 1 ]; then
        echo "Expected artifact matching '${expect}' not found in:" >&2
        ls -1 "${built}" >&2
        exit 1
      fi
      mkdir -p $out
      echo "ok ${name}" > $out/result
    '';
in
{
  bundle-deb = check {
    name = "deb";
    format = "deb";
    inherit drv info;
    expect = "hello_*_amd64.deb";
  };

  bundle-rpm = check {
    name = "rpm";
    format = "rpm";
    inherit drv info;
    expect = "hello-*-1.x86_64.rpm";
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

  bundle-app = check {
    name = "app";
    format = "app";
    inherit drv info;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
    expect = "hello.app";
  };

  bundle-brew = check {
    name = "brew";
    format = "brew";
    inherit drv info;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
    expect = "hello.rb";
  };

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

  bundle-appimage = check {
    name = "appimage";
    format = "appimage";
    inherit drv info;
    expect = "hello-*-x86_64.AppImage";
  };

  bundle-pkg = check {
    name = "pkg";
    format = "pkg";
    inherit drv info;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
    expect = "hello-*-x86_64.pkg";
  };

  bundle-productbuild = check {
    name = "productbuild";
    format = "productbuild";
    inherit drv;
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

  bundle-service-deb = check {
    name = "service-deb";
    format = "deb";
    inherit drv;
    info = info // {
      desktopEntries = [
        {
          name = "Hello";
          exec = "/opt/hello/bin/hello";
          categories = [ "Utility" ];
        }
      ];
      services = [
        {
          name = "hello-agent";
          exec = "/opt/hello/bin/hello --daemon";
          description = "demo";
        }
      ];
    };
    expect = "hello_*_amd64.deb";
  };

  bundle-service-pkg = check {
    name = "service-pkg";
    format = "pkg";
    inherit drv;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
    info = info // {
      services = [
        {
          name = "hello-agent";
          exec = "/Applications/hello.app/Contents/MacOS/hello --daemon";
          description = "demo";
        }
      ];
    };
    expect = "hello-*-x86_64.pkg";
  };

  bundle-service-nsis = check {
    name = "service-nsis";
    format = "nsis";
    drv = drvWin;
    target = {
      arch = "x86_64";
      os = "windows";
    };
    info = info // {
      services = [
        {
          name = "hello-agent";
          exec = "hello.exe --daemon";
          description = "demo";
          windows.serviceName = "HelloAgent";
        }
      ];
    };
    expect = "hello-*-x64-setup.exe";
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
}
