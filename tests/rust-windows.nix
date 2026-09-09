# End-to-end windows bundle tests for the Rust demo binary. Built via
# `pkgsCross.mingwW64.rustPlatform` on a linux host.
{ helpers }:

let
  inherit (helpers)
    e2e
    pkgs
    rustInfo
    rustName
    rustVersion
    rustWindows
    canNsis
    ;
  inherit (pkgs) lib;

  winTarget = {
    arch = "x86_64";
    os = "windows";
  };
in
lib.optionalAttrs canNsis {
  rust-nsis = e2e {
    name = "rust-nsis";
    format = "nsis";
    drv = rustWindows;
    info = rustInfo;
    target = winTarget;
    expect = "${rustName}-${rustVersion}-x64-setup.exe";
    assertScript = ''
      # NSIS installers begin with the MZ DOS-stub magic.
      test "$(head -c 2 "$artifact" | tr -d '\0')" = "MZ"
      test "$(stat -c '%s' "$artifact")" -gt 50000
    '';
  };
}
// {
  rust-msi = e2e {
    name = "rust-msi";
    format = "msi";
    drv = rustWindows;
    info = rustInfo // {
      services = [
        {
          name = "rust-demo";
          exec = "${rustName}.exe --daemon";
          description = "Rust demo service";
          windows.serviceName = "RustDemo";
        }
      ];
    };
    target = winTarget;
    expect = "${rustName}-${rustVersion}-x64.msi";
    probeInputs = [ pkgs.msitools ];
    assertScript = ''
      msiinfo export "$artifact" File           | grep -F "${rustName}.exe"
      msiinfo export "$artifact" ServiceInstall | grep -F "RustDemo"
      msiinfo export "$artifact" ServiceControl | grep -F "RustDemo"
    '';
  };

  rust-windows-zip = e2e {
    name = "rust-windows-zip";
    format = "zip";
    drv = rustWindows;
    info = rustInfo;
    target = winTarget;
    expect = "${rustName}-${rustVersion}-x86_64-windows.zip";
    probeInputs = [ pkgs.unzip ];
    assertScript = ''
      tmp=$(mktemp -d)
      unzip -q "$artifact" -d "$tmp"
      test -f "$tmp/${rustName}-${rustVersion}/${rustName}.exe"
    '';
  };
}
