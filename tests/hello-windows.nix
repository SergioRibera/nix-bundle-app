# `info.windows` + `info.permissions.network.local` on MSI and NSIS: install
# scope, publisher, "Apps & features" fields, shortcuts and firewall rules.
{ helpers }:

let
  inherit (helpers)
    bundler
    canNsis
    drvWin
    e2e
    info
    pkgs
    ;
  inherit (pkgs) lib;

  winTarget = {
    arch = "x86_64";
    os = "windows";
  };

  machineInfo = info // {
    windows = {
      publisher = "Example Corp";
      shortcuts.desktop = true;
      arp = {
        helpUrl = "https://example.com/help";
        contact = "support@example.com";
      };
    };
    permissions.network.local = {
      reason = "Finds apps on your network.";
      udp = [
        7701
        7720
      ];
      tcp = [ 8080 ];
    };
  };
  userInfo = lib.recursiveUpdate machineInfo {
    windows.scope = "perUser";
  };

  nsi =
    extra:
    pkgs.writeText "installer.nsi"
      (bundler.bundle {
        drv = drvWin;
        format = "nsis";
        info = extra;
        target = winTarget;
      }).nsi;
in
{
  windows-msi-machine = e2e {
    name = "windows-msi-machine";
    format = "msi";
    drv = drvWin;
    info = machineInfo;
    target = winTarget;
    expect = "hello-*-x64.msi";
    probeInputs = [ pkgs.msitools ];
    assertScript = ''
      props=$(msiinfo export "$artifact" Property | tr -d '\r')
      grep -P "^Manufacturer\tExample Corp$" <<<"$props"
      grep -P "^ARPHELPLINK\thttps://example.com/help$" <<<"$props"
      grep -P "^ARPCONTACT\tsupport@example.com$" <<<"$props"
      grep -P "^ARPURLINFOABOUT\thttps://example.com$" <<<"$props"
      actions=$(msiinfo export "$artifact" CustomAction | tr -d '\r')
      grep -F "protocol=UDP localport=7701,7720" <<<"$actions"
      grep -F "protocol=TCP localport=8080" <<<"$actions"
      grep -F "firewall delete rule" <<<"$actions"
      msiinfo export "$artifact" InstallExecuteSequence | grep -F FirewallRemove
      shortcuts=$(msiinfo export "$artifact" Shortcut)
      grep -F ApplicationShortcutLink <<<"$shortcuts"
      grep -F DesktopShortcutLink <<<"$shortcuts"
      msiinfo export "$artifact" Directory | grep -F ProgramFiles64Folder
    '';
  };

  # Per user: %LOCALAPPDATA%\Programs, no admin, so no firewall rules.
  windows-msi-user = e2e {
    name = "windows-msi-user";
    format = "msi";
    drv = drvWin;
    info = userInfo;
    target = winTarget;
    expect = "hello-*-x64.msi";
    probeInputs = [ pkgs.msitools ];
    assertScript = ''
      msiinfo export "$artifact" Directory | grep -F LocalAppDataFolder
      if msiinfo export "$artifact" Directory | grep -F ProgramFiles64Folder; then exit 1; fi
      if msiinfo export "$artifact" CustomAction | grep -F netsh; then exit 1; fi
      if msiinfo export "$artifact" Property | grep -F ALLUSERS; then exit 1; fi
    '';
  };

  # The pre-`windows` names keep working (with a deprecation warning).
  windows-msi-legacy = e2e {
    name = "windows-msi-legacy";
    format = "msi";
    drv = drvWin;
    info = info // {
      installDirName = "Legacy Dir";
      msiUpgradeCode = "12345678-1234-1234-1234-123456789ABC";
    };
    target = winTarget;
    expect = "hello-*-x64.msi";
    probeInputs = [ pkgs.msitools ];
    assertScript = ''
      msiinfo export "$artifact" Directory | grep -F "Legacy Dir"
      msiinfo export "$artifact" Property | grep -F "{12345678-1234-1234-1234-123456789ABC}"
    '';
  };

  windows-nsis-script =
    pkgs.runCommand "e2e-windows-nsis-script"
      {
        machine = nsi machineInfo;
        user = nsi userInfo;
      }
      ''
        set -euo pipefail
        grep -qF 'RequestExecutionLevel admin' "$machine"
        grep -qF 'InstallDir "$PROGRAMFILES64\hello"' "$machine"
        grep -qF '!define COMPANYNAME "Example Corp"' "$machine"
        grep -qF '"HelpLink" "https://example.com/help"' "$machine"
        grep -qF 'CreateShortCut "$DESKTOP\''${DISPLAYNAME}.lnk"' "$machine"
        grep -qF 'protocol=UDP localport=7701,7720' "$machine"
        grep -qF 'firewall delete rule' "$machine"

        grep -qF 'RequestExecutionLevel user' "$user"
        grep -qF 'InstallDir "$LOCALAPPDATA\Programs\hello"' "$user"
        test "$(grep -c '^ *SetShellVarContext current$' "$user")" -eq 2
        if grep -q 'HKLM\|netsh' "$user"; then exit 1; fi
        touch $out
      '';
}
// lib.optionalAttrs canNsis {
  # makensis accepts both scripts.
  windows-nsis-user = e2e {
    name = "windows-nsis-user";
    format = "nsis";
    drv = drvWin;
    info = userInfo;
    target = winTarget;
    expect = "hello-*-x64-setup.exe";
    assertScript = "true";
  };
  windows-nsis-machine = e2e {
    name = "windows-nsis-machine";
    format = "nsis";
    drv = drvWin;
    info = machineInfo;
    target = winTarget;
    expect = "hello-*-x64-setup.exe";
    assertScript = "true";
  };
}
