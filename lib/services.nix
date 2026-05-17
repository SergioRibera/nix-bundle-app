{ lib, utils }:

let
  serviceDefaults = {
    description = "";
    user = null;
    group = null;
    workingDirectory = null;
    environment = {};
    restart = "on-failure";       # always | on-failure | no
    restartSec = 5;
    startAtBoot = true;
    after = [ "network.target" ];
    requires = [ ];
    wants = [ ];
    type = "simple";              # simple | forking | oneshot | notify | dbus
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
      processType = null;        # Background | Standard | Adaptive | Interactive
    };

    windows = {
      serviceName = null;
      displayName = null;
      account = "LocalSystem";   # LocalSystem | LocalService | NetworkService
      start = "auto";            # auto | demand | disabled
      depends = [ ];
      errorControl = "normal";   # normal | severe | critical | ignore
    };
  };

  normalize = svc: lib.recursiveUpdate serviceDefaults svc;

  # ---------- systemd ----------

  iniLine = k: v:
    if v == null then null
    else if v == "" then null
    else if builtins.isList v then
      if v == [] then null else "${k}=${lib.concatStringsSep " " (map toString v)}"
    else if builtins.isBool v then "${k}=${if v then "yes" else "no"}"
    else "${k}=${toString v}";

  iniSection = header: pairs:
    let
      lines = builtins.filter (l: l != null)
        (lib.mapAttrsToList iniLine pairs);
    in if lines == [] then null
       else lib.concatStringsSep "\n" ([ "[${header}]" ] ++ lines);

  renderSystemd = raw:
    let
      s = normalize raw;
      envLines = lib.mapAttrsToList
        (k: v: ''Environment="${k}=${toString v}"'') s.environment;
      envBlock =
        if envLines == [] then null else lib.concatStringsSep "\n" envLines;

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
        WantedBy = if s.startAtBoot then s.systemd.wantedBy else [];
      } s.systemd.installOverrides;

      unitBlock = iniSection "Unit" unitKv;
      serviceBlockBase = iniSection "Service" serviceKv;
      serviceBlock =
        if envBlock == null then serviceBlockBase
        else "${serviceBlockBase}\n${envBlock}";
      installBlock = iniSection "Install" installKv;

      sections = builtins.filter (b: b != null)
        [ unitBlock serviceBlock installBlock ];
      content = lib.concatStringsSep "\n\n" sections + "\n";
    in {
      filename = "${s.name}.service";
      content = content;
      name = s.name;
      enable = s.startAtBoot;
    };

  # ---------- launchd ----------

  xmlEsc = utils.xmlEscape;

  renderLaunchd = raw:
    let
      s = normalize raw;
      label =
        if (s.launchd.label or null) != null && s.launchd.label != ""
        then s.launchd.label else s.name;
      argv = builtins.filter (x: x != "") (lib.splitString " " s.exec);
      argvLines = map (a: "    <string>${xmlEsc a}</string>") argv;

      optStr = k: v:
        if v == null then null
        else "  <key>${k}</key><string>${xmlEsc (toString v)}</string>";

      optBool = k: v:
        "  <key>${k}</key><${if v then "true" else "false"}/>";

      optInt = k: v:
        if v == null then null
        else "  <key>${k}</key><integer>${toString v}</integer>";

      envBlock =
        if s.environment == {} then [] else
        [ "  <key>EnvironmentVariables</key>" "  <dict>" ]
        ++ lib.mapAttrsToList
            (k: v: "    <key>${xmlEsc k}</key><string>${xmlEsc (toString v)}</string>")
            s.environment
        ++ [ "  </dict>" ];

      mainLines = [
        ''<?xml version="1.0" encoding="UTF-8"?>''
        ''<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">''
        ''<plist version="1.0">''
        "<dict>"
        "  <key>Label</key><string>${xmlEsc label}</string>"
        "  <key>ProgramArguments</key>"
        "  <array>"
      ] ++ argvLines ++ [
        "  </array>"
        (optBool "KeepAlive" s.launchd.keepAlive)
        (optBool "RunAtLoad" s.launchd.runAtLoad)
      ] ++ (lib.optional s.launchd.abandonProcessGroup
              (optBool "AbandonProcessGroup" true))
        ++ [
        (optStr "UserName" s.user)
        (optStr "GroupName" s.group)
        (optStr "WorkingDirectory" s.workingDirectory)
        (optStr "StandardOutPath" s.stdout)
        (optStr "StandardErrorPath" s.stderr)
        (optStr "ProcessType" s.launchd.processType)
        (optInt "ThrottleInterval" s.launchd.throttleInterval)
      ] ++ envBlock ++ [
        "</dict>"
        "</plist>"
      ];

      kept = builtins.filter (l: l != null) mainLines;
      content = lib.concatStringsSep "\n" kept + "\n";
    in {
      filename = "${label}.plist";
      content = content;
      label = label;
      name = s.name;
    };

  # ---------- windows (sc.exe) ----------

  renderWindowsInstall = raw: { exeRelative ? null }:
    let
      s = normalize raw;
      svcName = if s.windows.serviceName != null then s.windows.serviceName else s.name;
      display =
        if s.windows.displayName != null then s.windows.displayName
        else if s.description != "" then s.description
        else svcName;
      depends =
        if s.windows.depends == [] then ""
        else "depend= " + lib.concatStringsSep "/" s.windows.depends + " ";

      # Parse `s.exec` as "<binary> [<args>...]" and rebuild it so the binary
      # path becomes %~dp0<exeRelative> when supplied.
      execTokens = builtins.filter (x: x != "") (lib.splitString " " s.exec);
      execArgs = lib.concatStringsSep " " (builtins.tail execTokens);
      fullBinPath =
        if exeRelative != null
        then "%~dp0${exeRelative}" + (lib.optionalString (execArgs != "") " ${execArgs}")
        else s.exec;
      # sc.exe wants the *entire* command line — binary + args — as a single
      # quoted string after binPath=.
      binPathQuoted = ''"${fullBinPath}"'';
      startCmd = if s.startAtBoot then ''sc start "${svcName}"'' else "";
    in ''
      sc create "${svcName}" binPath= ${binPathQuoted} start= ${s.windows.start} ^
        DisplayName= "${display}" obj= ${s.windows.account} ^
        error= ${s.windows.errorControl} ${depends}
      ${lib.optionalString (s.description != "") ''sc description "${svcName}" "${s.description}"''}
      ${startCmd}
    '';

  renderWindowsUninstall = raw:
    let
      s = normalize raw;
      svcName = if s.windows.serviceName != null then s.windows.serviceName else s.name;
    in ''
      sc stop "${svcName}" 1>nul 2>nul
      sc delete "${svcName}"
    '';

  # Aggregate helpers — render all of `services` for a given OS.
  renderAllSystemd = services: map renderSystemd services;
  renderAllLaunchd = services: map renderLaunchd services;

  renderWindowsBundleBat = services: { exeRelative ? null }:
    if services == [] then null else ''
      @echo off
      rem nix-bundle-app: install Windows services
      ${lib.concatMapStringsSep "\n"
        (s: renderWindowsInstall s { inherit exeRelative; })
        services}
    '';

  renderWindowsUninstallBat = services:
    if services == [] then null else ''
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
    renderAllSystemd
    renderAllLaunchd
    renderWindowsBundleBat
    renderWindowsUninstallBat
    ;
}
