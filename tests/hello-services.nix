# Service-aware bundle checks: same `pkgs.hello` drv but with `info.services`
# wired up, exercising the systemd / launchd / windows-service code paths.
{ helpers }:

let
  inherit (helpers)
    check
    drv
    drvWin
    info
    ;
in
{
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
}
