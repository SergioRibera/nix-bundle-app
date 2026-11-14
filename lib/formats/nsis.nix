{
  stdenv,
  lib,
  utils,
  services,
  signing,
  drv,
  format,
  meta,
  target,
  nsis,
  coreutils,
  gnused,
  rsync,
  file,
  gnugrep,
  gawk,
  patchelf,
  closureInfo,
  ...
}:

let
  deps = import ../deps.nix {
    inherit
      lib
      utils
      closureInfo
      coreutils
      file
      gawk
      gnugrep
      gnused
      patchelf
      rsync
      ;
  };
  win = meta.windows;
  perUser = win.scope == "perUser";
  installDirName = meta.installDirName;
  # Per user: no admin, %LOCALAPPDATA%\Programs and HKCU, like MSI's perUser.
  regRoot = if perUser then "HKCU" else "HKLM";
  shellContext = if perUser then "current" else "all";
  installRoot = if perUser then "$LOCALAPPDATA\\Programs" else "$PROGRAMFILES64";
  uninstallKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${APPNAME}";
  winArch = if target.arch == "x86_64" then "x64" else target.arch;
  outFile = "${meta.name}-${meta.version}-${winArch}-setup.exe";

  uninstallerName = "Uninstall.exe";

  exeRel = "${meta.name}.exe";
  installBat = services.renderWindowsBundleBat meta.services { exeRelative = exeRel; };
  uninstallBat = services.renderWindowsUninstallBat meta.services;
  hasServices = meta.services != [ ];
  hasIcon = meta.iconSet != null;
  # Installed next to the binary: shortcuts and "Apps & features" use it.
  iconRel = "${meta.name}.ico";
  shortcutIcon = "$INSTDIR\\${if hasIcon then iconRel else exeRel}";

  fileAssociations = import ../file-associations.nix { inherit lib; };
  esc = utils.nsisEscape;

  arpValues = lib.filterAttrs (_: v: v != null && v != "") {
    HelpLink = win.arp.helpUrl;
    URLUpdateInfo = win.arp.updateUrl;
    Contact = win.arp.contact;
    Comments = win.arp.comments;
  };

  # Same rules as the MSI: inbound allow for the declared ports, admin only.
  local = meta.permissions.network.local;
  firewallRules = lib.optionals (local != null && !perUser) (
    lib.optional (local.udp != [ ]) {
      protocol = "UDP";
      ports = local.udp;
    }
    ++ lib.optional (local.tcp != [ ]) {
      protocol = "TCP";
      ports = local.tcp;
    }
  );
  firewallAdd = lib.concatMapStrings (r: ''
    nsExec::ExecToLog 'netsh advfirewall firewall add rule name="''${DISPLAYNAME}" dir=in action=allow protocol=${r.protocol} localport=${
      lib.concatMapStringsSep "," toString r.ports
    } program="$INSTDIR\${exeRel}" enable=yes'
  '') firewallRules;
  firewallRemove = lib.optionalString (firewallRules != [ ]) ''
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="''${DISPLAYNAME}"'
  '';

  nsi = ''
    !define APPNAME "${esc meta.name}"
    !define DISPLAYNAME "${esc meta.displayName}"
    !define APPVERSION "${esc meta.version}"
    !define COMPANYNAME "${esc meta.publisher}"
    !define DESCRIPTION "${esc meta.summary}"
    !define HOMEPAGE "${esc meta.homepage}"

    Name "''${DISPLAYNAME}"
    ${lib.optionalString hasIcon ''
      Icon "payload\${iconRel}"
      UninstallIcon "payload\${iconRel}"
    ''}
    OutFile "${outFile}"
    InstallDir "${installRoot}\${esc installDirName}"
    InstallDirRegKey ${regRoot} "Software\''${APPNAME}" "Install_Dir"
    RequestExecutionLevel ${if perUser then "user" else "admin"}
    SetCompressor /SOLID lzma
    Unicode true

    Page directory
    Page instfiles
    UninstPage uninstConfirm
    UninstPage instfiles

    Section "Install"
      ; Shortcuts and SHCTX follow the install scope.
      SetShellVarContext ${shellContext}
      SetOutPath "$INSTDIR"
      File /r "payload\*"

      WriteRegStr ${regRoot} "Software\''${APPNAME}" "Install_Dir" "$INSTDIR"
      WriteRegStr ${regRoot} "${uninstallKey}" "DisplayName" "''${DISPLAYNAME}"
      ${lib.optionalString hasIcon ''
        WriteRegStr ${regRoot} "${uninstallKey}" "DisplayIcon" "$INSTDIR\${iconRel}"
      ''}
      WriteRegStr ${regRoot} "${uninstallKey}" "DisplayVersion" "''${APPVERSION}"
      WriteRegStr ${regRoot} "${uninstallKey}" "Publisher" "''${COMPANYNAME}"
      WriteRegStr ${regRoot} "${uninstallKey}" "URLInfoAbout" "''${HOMEPAGE}"
      ${lib.concatStrings (
        lib.mapAttrsToList (k: v: ''
          WriteRegStr ${regRoot} "${uninstallKey}" "${k}" "${esc v}"
        '') arpValues
      )}
      WriteRegStr ${regRoot} "${uninstallKey}" "UninstallString" '"$INSTDIR\${uninstallerName}"'

      WriteUninstaller "$INSTDIR\${uninstallerName}"

      ${lib.optionalString win.shortcuts.startMenu ''
        CreateShortCut "$SMPROGRAMS\''${DISPLAYNAME}.lnk" "$INSTDIR\${exeRel}" "" "${shortcutIcon}" 0
      ''}
      ${lib.optionalString win.shortcuts.desktop ''
        CreateShortCut "$DESKTOP\''${DISPLAYNAME}.lnk" "$INSTDIR\${exeRel}" "" "${shortcutIcon}" 0
      ''}

      ${fileAssociations.nsisInstall meta}
      ${firewallAdd}

      ${lib.optionalString hasServices ''
        ; Register Windows services declared in info.services
        nsExec::ExecToLog '"$INSTDIR\install-services.bat"'
      ''}
    SectionEnd

    Section "Uninstall"
      SetShellVarContext ${shellContext}
      ${lib.optionalString hasServices ''
        nsExec::ExecToLog '"$INSTDIR\uninstall-services.bat"'
      ''}
      ${firewallRemove}
      Delete "$INSTDIR\${uninstallerName}"
      RMDir /r "$INSTDIR"
      Delete "$SMPROGRAMS\''${DISPLAYNAME}.lnk"
      Delete "$DESKTOP\''${DISPLAYNAME}.lnk"
      ${fileAssociations.nsisUninstall meta}
      DeleteRegKey ${regRoot} "${uninstallKey}"
      DeleteRegKey ${regRoot} "Software\''${APPNAME}"
    SectionEnd
  '';
in
stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = [
    nsis
    coreutils
    gnused
    rsync
  ];

  buildCommand = ''
        mkdir -p payload
        ${deps.copyBinaries drv "payload"}
        ${deps.copyWindowsDlls drv "payload"}
        if [ -d "${drv}/share" ]; then
          ${rsync}/bin/rsync -a --copy-links "${drv}/share/" "payload/share/" || true
        fi
        chmod -R u+w payload
        ${lib.optionalString hasIcon ''
          cp "${meta.iconSet}/icon.ico" "payload/${iconRel}"
        ''}

        ${lib.optionalString hasServices ''
          cat > payload/install-services.bat <<'INSTALL_SERVICES_EOF'
          ${installBat}
          INSTALL_SERVICES_EOF
          cat > payload/uninstall-services.bat <<'UNINSTALL_SERVICES_EOF'
          ${uninstallBat}
          UNINSTALL_SERVICES_EOF
        ''}

        cat > installer.nsi <<'NSIEOF'
    ${nsi}
    NSIEOF
        ${gnused}/bin/sed -i 's/^    //' installer.nsi

        makensis -V2 -INPUTCHARSET UTF8 installer.nsi

        mkdir -p $out
        cp "${outFile}" "$out/${outFile}"

        ${signing.emitSignScript {
          inherit meta format;
          artifactGlob = "*-setup.exe";
        }}
  '';

  passthru = {
    info = meta;
    inherit
      target
      format
      outFile
      nsi
      ;
  };
}
