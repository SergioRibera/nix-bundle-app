{ pkgs, bundler }:

let
  helloLinux = pkgs.hello;
  helloWindows = if pkgs.stdenv.isLinux then pkgs.pkgsCross.mingwW64.hello else pkgs.hello;

  commonInfo = {
    description = "GNU Hello, the canonical example program";
    homepage = "https://www.gnu.org/software/hello/";
    license = "GPL-3.0-or-later";
    maintainer = "nix-bundle-app demo <noreply@example.com>";
    summary = "Prints a friendly greeting";
    longDescription = ''
      GNU Hello is a program that produces a familiar, friendly greeting.
      Repackaged by nix-bundle-app to demonstrate native installer generation.
    '';
  };

  serviceInfo = commonInfo // {
    desktopEntries = [
      {
        name = "Hello Demo";
        exec = "/opt/hello/bin/hello %F";
        comment = "Friendly greeter (demo of declarative bundle metadata)";
        icon = "hello";
        categories = [
          "Utility"
          "Education"
        ];
        keywords = [
          "demo"
          "greeting"
          "hello"
        ];
        terminal = false;
        actions = {
          "Verbose" = {
            name = "Run verbose";
            exec = "/opt/hello/bin/hello --verbose";
          };
        };
      }
    ];
    services = [
      {
        name = "hello-agent";
        description = "Hello background greeter";
        exec = "/opt/hello/bin/hello --daemon";
        user = "hello";
        environment = {
          LOG_LEVEL = "info";
          HELLO_INTERVAL = "60";
        };
        restart = "always";
        restartSec = 10;
        after = [ "network-online.target" ];

        windows = {
          serviceName = "HelloAgent";
          displayName = "Hello Greeter Agent";
          start = "auto";
        };
        launchd = {
          keepAlive = true;
          runAtLoad = true;
          processType = "Background";
        };
      }
    ];
  };
in
{
  hello-deb = bundler.bundle {
    drv = helloLinux;
    format = "deb";
    info = commonInfo;
  };

  hello-rpm = bundler.bundle {
    drv = helloLinux;
    format = "rpm";
    info = commonInfo;
  };

  hello-archlinux = bundler.bundle {
    drv = helloLinux;
    format = "archlinux";
    info = commonInfo;
  };

  hello-archlinux-pkg-only = bundler.bundle {
    drv = helloLinux;
    format = "archlinux";
    info = commonInfo // {
      archlinux.output = "pkg";
    };
  };

  hello-archlinux-aur-only = bundler.bundle {
    drv = helloLinux;
    format = "archlinux";
    info = commonInfo // {
      archlinux.output = "aur";
      downloadUrl = "https://example.com/releases/hello-bin-2.12.3-x86_64.tar.gz";
    };
  };

  hello-tar-gz = bundler.bundle {
    drv = helloLinux;
    format = "tar.gz";
    info = commonInfo;
  };

  hello-tar-xz = bundler.bundle {
    drv = helloLinux;
    format = "tar.xz";
    info = commonInfo;
  };

  hello-zip = bundler.bundle {
    drv = helloLinux;
    format = "zip";
    info = commonInfo;
  };

  hello-app = bundler.bundle {
    drv = helloLinux;
    format = "app";
    info = commonInfo;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
  };

  hello-brew = bundler.bundle {
    drv = helloLinux;
    format = "brew";
    info = commonInfo // {
      downloadUrl = "https://example.com/releases/hello.tar.gz";
    };
    target = {
      arch = "x86_64";
      os = "darwin";
    };
  };

  hello-dmg =
    if pkgs.stdenv.isLinux || pkgs.stdenv.isDarwin then
      bundler.bundle {
        drv = helloLinux;
        format = "dmg";
        info = commonInfo;
        target = {
          arch = "x86_64";
          os = "darwin";
        };
      }
    else
      null;

  hello-nsis = bundler.bundle {
    drv = helloWindows;
    format = "nsis";
    info = commonInfo;
    target = {
      arch = "x86_64";
      os = "windows";
    };
  };

  hello-windows-zip = bundler.bundle {
    drv = helloWindows;
    format = "zip";
    info = commonInfo;
    target = {
      arch = "x86_64";
      os = "windows";
    };
  };

  hello-appimage = bundler.bundle {
    drv = helloLinux;
    format = "appimage";
    info = commonInfo;
  };

  hello-flatpak = bundler.bundle {
    drv = helloLinux;
    format = "flatpak";
    info = commonInfo // {
      flatpak.finishArgs = [
        "--share=ipc"
        "--socket=fallback-x11"
      ];
    };
  };

  hello-snap = bundler.bundle {
    drv = helloLinux;
    format = "snap";
    info = commonInfo // {
      snap = {
        confinement = "strict";
        plugs = [
          "home"
          "network"
        ];
      };
    };
  };

  hello-pkg = bundler.bundle {
    drv = helloLinux;
    format = "pkg";
    info = commonInfo;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
  };

  hello-productbuild = bundler.bundle {
    drv = helloLinux;
    format = "productbuild";
    info = commonInfo // {
      productbuild = {
        title = "Hello Installer";
        organization = "com.example";
        welcome = pkgs.writeText "welcome.html" "<html><body><h1>Hello</h1></body></html>";
        license = pkgs.writeText "license.txt" "MIT.";
        conclusion = pkgs.writeText "conclusion.html" "<html><body>Installed.</body></html>";
      };
    };
    target = {
      arch = "x86_64";
      os = "darwin";
    };
  };

  hello-msi = bundler.bundle {
    drv = helloWindows;
    format = "msi";
    info = commonInfo;
    target = {
      arch = "x86_64";
      os = "windows";
    };
  };

  hello-all-linux = bundler.bundleAll {
    drv = helloLinux;
    formats = [
      "deb"
      "rpm"
      "archlinux"
      "appimage"
      "tar.gz"
      "tar.xz"
      "zip"
    ];
    info = commonInfo;
  };

  hello-all-windows = bundler.bundleAll {
    drv = helloWindows;
    formats = [
      "nsis"
      "msi"
      "zip"
    ];
    info = commonInfo;
    target = {
      arch = "x86_64";
      os = "windows";
    };
  };

  hello-all-darwin = bundler.bundleAll {
    drv = helloLinux;
    formats = [
      "app"
      "dmg"
      "pkg"
      "brew"
      "tar.gz"
    ];
    info = commonInfo;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
  };

  hello-service-deb = bundler.bundle {
    drv = helloLinux;
    format = "deb";
    info = serviceInfo;
  };
  hello-service-rpm = bundler.bundle {
    drv = helloLinux;
    format = "rpm";
    info = serviceInfo;
  };
  hello-service-archlinux = bundler.bundle {
    drv = helloLinux;
    format = "archlinux";
    info = serviceInfo;
  };
  # Intentionally no `hello-service-appimage`: schema asserts AppImage+services.
  hello-service-app = bundler.bundle {
    drv = helloLinux;
    format = "app";
    info = serviceInfo;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
  };
  hello-service-pkg = bundler.bundle {
    drv = helloLinux;
    format = "pkg";
    info = serviceInfo;
    target = {
      arch = "x86_64";
      os = "darwin";
    };
  };
  hello-service-nsis = bundler.bundle {
    drv = helloWindows;
    format = "nsis";
    info = serviceInfo;
    target = {
      arch = "x86_64";
      os = "windows";
    };
  };
  hello-service-msi = bundler.bundle {
    drv = helloWindows;
    format = "msi";
    info = serviceInfo;
    target = {
      arch = "x86_64";
      os = "windows";
    };
  };

  hello-brew-linux = bundler.bundle {
    drv = helloLinux;
    format = "brew";
    info = commonInfo // {
      downloadUrl = "https://example.com/releases/hello-linux.tar.gz";
    };
    target = {
      arch = "x86_64";
      os = "linux";
    };
  };
}
