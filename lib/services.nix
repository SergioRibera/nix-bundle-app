{ lib, utils }:

let
  serviceDefaults = {
    description = "";
    user = null;
    group = null;
    workingDirectory = null;
    environment = { };
    restart = "on-failure";
    restartSec = 5;
    startAtBoot = true;
    after = [ "network.target" ];
    requires = [ ];
    wants = [ ];
    type = "simple";
    stdout = null;
    stderr = null;

    systemd = {
      unitOverrides = { };
      serviceOverrides = { };
      installOverrides = { };
      wantedBy = [ "multi-user.target" ];
    };

    launchd = {
      label = null;
      keepAlive = true;
      runAtLoad = true;
      abandonProcessGroup = false;
      throttleInterval = null;
      processType = null;
    };

    windows = {
      serviceName = null;
      displayName = null;
      account = "LocalSystem";
      start = "auto";
      depends = [ ];
      errorControl = "normal";
    };
  };

  normalize = svc: lib.recursiveUpdate serviceDefaults svc;

  iniLine =
    k: v:
    if v == null then
      null
    else if v == "" then
      null
    else if builtins.isList v then
      if v == [ ] then null else "${k}=${lib.concatStringsSep " " (map toString v)}"
    else if builtins.isBool v then
      "${k}=${if v then "yes" else "no"}"
    else
      "${k}=${toString v}";

  iniSection =
    header: pairs:
    let
      lines = builtins.filter (l: l != null) (lib.mapAttrsToList iniLine pairs);
    in
    if lines == [ ] then null else lib.concatStringsSep "\n" ([ "[${header}]" ] ++ lines);

  renderSystemd =
    raw:
    let
      s = normalize raw;
      envLines = lib.mapAttrsToList (k: v: ''Environment="${k}=${toString v}"'') s.environment;
      envBlock = if envLines == [ ] then null else lib.concatStringsSep "\n" envLines;

      unitKv = lib.recursiveUpdate {
        Description = s.description;
        After = s.after;
        Requires = s.requires;
        Wants = s.wants;
      } s.systemd.unitOverrides;

      serviceKv = lib.recursiveUpdate {
        Type = s.type;
        ExecStart = s.exec;
        User = s.user;
        Group = s.group;
        WorkingDirectory = s.workingDirectory;
        Restart = s.restart;
        RestartSec = s.restartSec;
        StandardOutput = if s.stdout != null then "append:${s.stdout}" else null;
        StandardError = if s.stderr != null then "append:${s.stderr}" else null;
      } s.systemd.serviceOverrides;

      installKv = lib.recursiveUpdate {
        WantedBy = if s.startAtBoot then s.systemd.wantedBy else [ ];
      } s.systemd.installOverrides;

      unitBlock = iniSection "Unit" unitKv;
      serviceBlockBase = iniSection "Service" serviceKv;
      serviceBlock = if envBlock == null then serviceBlockBase else "${serviceBlockBase}\n${envBlock}";
      installBlock = iniSection "Install" installKv;

      sections = builtins.filter (b: b != null) [
        unitBlock
        serviceBlock
        installBlock
      ];
      content = lib.concatStringsSep "\n\n" sections + "\n";
    in
    {
      filename = "${s.name}.service";
      content = content;
      name = s.name;
      enable = s.startAtBoot;
    };

  xmlEsc = utils.xmlEscape;

  renderLaunchd =
    raw:
    let
      s = normalize raw;
      label =
        if (s.launchd.label or null) != null && s.launchd.label != "" then s.launchd.label else s.name;
      argv = builtins.filter (x: x != "") (lib.splitString " " s.exec);
      argvLines = map (a: "    <string>${xmlEsc a}</string>") argv;

      optStr =
        k: v: if v == null then null else "  <key>${k}</key><string>${xmlEsc (toString v)}</string>";

      optBool = k: v: "  <key>${k}</key><${if v then "true" else "false"}/>";

      optInt = k: v: if v == null then null else "  <key>${k}</key><integer>${toString v}</integer>";

      envBlock =
        if s.environment == { } then
          [ ]
        else
          [
            "  <key>EnvironmentVariables</key>"
            "  <dict>"
          ]
          ++ lib.mapAttrsToList (
            k: v: "    <key>${xmlEsc k}</key><string>${xmlEsc (toString v)}</string>"
          ) s.environment
          ++ [ "  </dict>" ];

      mainLines = [
        ''<?xml version="1.0" encoding="UTF-8"?>''
        ''<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">''
        ''<plist version="1.0">''
        "<dict>"
        "  <key>Label</key><string>${xmlEsc label}</string>"
        "  <key>ProgramArguments</key>"
        "  <array>"
      ]
      ++ argvLines
      ++ [
        "  </array>"
        (optBool "KeepAlive" s.launchd.keepAlive)
        (optBool "RunAtLoad" s.launchd.runAtLoad)
      ]
      ++ (lib.optional s.launchd.abandonProcessGroup (optBool "AbandonProcessGroup" true))
      ++ [
        (optStr "UserName" s.user)
        (optStr "GroupName" s.group)
        (optStr "WorkingDirectory" s.workingDirectory)
        (optStr "StandardOutPath" s.stdout)
        (optStr "StandardErrorPath" s.stderr)
        (optStr "ProcessType" s.launchd.processType)
        (optInt "ThrottleInterval" s.launchd.throttleInterval)
      ]
      ++ envBlock
      ++ [
        "</dict>"
        "</plist>"
      ];

      kept = builtins.filter (l: l != null) mainLines;
      content = lib.concatStringsSep "\n" kept + "\n";
    in
    {
      filename = "${label}.plist";
      content = content;
      label = label;
      name = s.name;
    };

  # Returns service identity values used by both the .bat shim and native
  # MSI <ServiceInstall>. Both paths must agree on these names or upgrades
  # mismatch.
  windowsServiceFields =
    raw:
    let
      s = normalize raw;
      svcName = if s.windows.serviceName != null then s.windows.serviceName else s.name;
      display =
        if s.windows.displayName != null then
          s.windows.displayName
        else if s.description != "" then
          s.description
        else
          svcName;
      execTokens = builtins.filter (x: x != "") (lib.splitString " " s.exec);
      execArgs = lib.concatStringsSep " " (builtins.tail execTokens);
    in
    {
      inherit svcName display;
      inherit (s)
        description
        startAtBoot
        environment
        user
        group
        windows
        ;
      args = execArgs;
    };

  renderWindowsInstall =
    raw:
    {
      exeRelative ? null,
    }:
    let
      f = windowsServiceFields raw;
      depends =
        if f.windows.depends == [ ] then
          ""
        else
          "depend= " + lib.concatStringsSep "/" f.windows.depends + " ";
      fullBinPath =
        if exeRelative != null then
          "%~dp0${exeRelative}" + (lib.optionalString (f.args != "") " ${f.args}")
        else
          (normalize raw).exec;
      # sc.exe needs the full command-line as a single quoted string after binPath=.
      binPathQuoted = ''"${fullBinPath}"'';
      startCmd = if f.startAtBoot then ''sc start "${f.svcName}"'' else "";
    in
    ''
      sc create "${f.svcName}" binPath= ${binPathQuoted} start= ${f.windows.start} ^
        DisplayName= "${f.display}" obj= ${f.windows.account} ^
        error= ${f.windows.errorControl} ${depends}
      ${lib.optionalString (f.description != "") ''sc description "${f.svcName}" "${f.description}"''}
      ${startCmd}
    '';

  renderWindowsUninstall =
    raw:
    let
      f = windowsServiceFields raw;
    in
    ''
      sc stop "${f.svcName}" 1>nul 2>nul
      sc delete "${f.svcName}"
    '';

  renderAllSystemd = services: map renderSystemd services;
  renderAllLaunchd = services: map renderLaunchd services;

  renderWindowsBundleBat =
    services:
    {
      exeRelative ? null,
    }:
    if services == [ ] then
      null
    else
      ''
        @echo off
        rem nix-bundle-app: install Windows services
        ${lib.concatMapStringsSep "\n" (s: renderWindowsInstall s { inherit exeRelative; }) services}
      '';

  renderWindowsUninstallBat =
    services:
    if services == [ ] then
      null
    else
      ''
        @echo off
        rem nix-bundle-app: uninstall Windows services
        ${lib.concatMapStringsSep "\n" renderWindowsUninstall services}
      '';
in
{
  inherit
    normalize
    renderSystemd
    renderLaunchd
    renderWindowsInstall
    renderWindowsUninstall
    windowsServiceFields
    renderAllSystemd
    renderAllLaunchd
    renderWindowsBundleBat
    renderWindowsUninstallBat
    ;
}
