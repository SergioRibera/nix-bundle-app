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
  installDirName = meta.installDirName;
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

  fileAssociations = import ../file-associations.nix { inherit lib; };
  esc = utils.nsisEscape;

  nsi = ''
    !define APPNAME "${esc meta.name}"
    !define DISPLAYNAME "${esc meta.displayName}"
    !define APPVERSION "${esc meta.version}"
    !define COMPANYNAME "${esc meta.maintainer}"
    !define DESCRIPTION "${esc meta.summary}"
    !define HOMEPAGE "${esc meta.homepage}"

    Name "$\{DISPLAYNAME}"
    ${lib.optionalString hasIcon ''
      Icon "payload\\${iconRel}"
      UninstallIcon "payload\\${iconRel}"
    ''}
    OutFile "${outFile}"
    InstallDir "$PROGRAMFILES64\\${installDirName}"
    InstallDirRegKey HKLM "Software\\$\{APPNAME}" "Install_Dir"
    RequestExecutionLevel admin
    SetCompressor /SOLID lzma
    Unicode true

    Page directory
    Page instfiles
    UninstPage uninstConfirm
    UninstPage instfiles

    Section "Install"
      ; HKLM, admin and $PROGRAMFILES: the Start-menu shortcut is machine-wide too.
      SetShellVarContext all
      SetOutPath "$INSTDIR"
      File /r "payload\\*"

      WriteRegStr HKLM "Software\\$\{APPNAME}" "Install_Dir" "$INSTDIR"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "DisplayName" "$\{DISPLAYNAME}"
      ${lib.optionalString hasIcon ''
        WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                         "DisplayIcon" "$INSTDIR\\${iconRel}"
      ''}
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "DisplayVersion" "$\{APPVERSION}"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "Publisher" "$\{COMPANYNAME}"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "URLInfoAbout" "$\{HOMEPAGE}"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "UninstallString" '"$INSTDIR\\${uninstallerName}"'

      WriteUninstaller "$INSTDIR\\${uninstallerName}"

      CreateShortCut "$SMPROGRAMS\\$\{DISPLAYNAME}.lnk" "$INSTDIR\\${meta.name}.exe" "" "$INSTDIR\\${
        if hasIcon then iconRel else "${meta.name}.exe"
      }" 0

      ${fileAssociations.nsisInstall meta}

      ${lib.optionalString hasServices ''
        ; Register Windows services declared in info.services
        nsExec::ExecToLog '"$INSTDIR\\install-services.bat"'
      ''}
    SectionEnd

    Section "Uninstall"
      SetShellVarContext all
      ${lib.optionalString hasServices ''
        nsExec::ExecToLog '"$INSTDIR\\uninstall-services.bat"'
      ''}
      Delete "$INSTDIR\\${uninstallerName}"
      RMDir /r "$INSTDIR"
      Delete "$SMPROGRAMS\\$\{DISPLAYNAME}.lnk"
      ${fileAssociations.nsisUninstall meta}
      DeleteRegKey HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}"
      DeleteRegKey HKLM "Software\\$\{APPNAME}"
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
