{
  pkgs,
  lib,
  deps,
  services,
  drv,
  format,
  meta,
  target,
  ...
}:

let
  installDirName = meta.installDirName;
  winArch = if target.arch == "x86_64" then "x64" else target.arch;
  outFile = "${meta.name}-${meta.version}-${winArch}-setup.exe";

  uninstallerName = "Uninstall.exe";

  exeRel = "${meta.name}.exe";
  installBat = services.renderWindowsBundleBat meta.services { exeRelative = exeRel; };
  uninstallBat = services.renderWindowsUninstallBat meta.services;
  hasServices = meta.services != [ ];

  nsi = ''
    !define APPNAME "${meta.name}"
    !define APPVERSION "${meta.version}"
    !define COMPANYNAME "${meta.maintainer}"
    !define DESCRIPTION "${meta.summary}"
    !define HOMEPAGE "${meta.homepage}"

    Name "$\{APPNAME}"
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
      SetOutPath "$INSTDIR"
      File /r "payload\\*"

      WriteRegStr HKLM "Software\\$\{APPNAME}" "Install_Dir" "$INSTDIR"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "DisplayName" "$\{APPNAME}"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "DisplayVersion" "$\{APPVERSION}"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "Publisher" "$\{COMPANYNAME}"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "URLInfoAbout" "$\{HOMEPAGE}"
      WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}" \
                       "UninstallString" '"$INSTDIR\\${uninstallerName}"'

      WriteUninstaller "$INSTDIR\\${uninstallerName}"

      CreateShortCut "$SMPROGRAMS\\$\{APPNAME}.lnk" "$INSTDIR\\${meta.name}.exe" "" "$INSTDIR\\${meta.name}.exe" 0

      ${lib.optionalString hasServices ''
        ; Register Windows services declared in info.services
        nsExec::ExecToLog '"$INSTDIR\\install-services.bat"'
      ''}
    SectionEnd

    Section "Uninstall"
      ${lib.optionalString hasServices ''
        nsExec::ExecToLog '"$INSTDIR\\uninstall-services.bat"'
      ''}
      Delete "$INSTDIR\\${uninstallerName}"
      RMDir /r "$INSTDIR"
      Delete "$SMPROGRAMS\\$\{APPNAME}.lnk"
      DeleteRegKey HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$\{APPNAME}"
      DeleteRegKey HKLM "Software\\$\{APPNAME}"
    SectionEnd
  '';
in
pkgs.stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.nsis
    pkgs.coreutils
    pkgs.gnused
    pkgs.rsync
  ];

  buildCommand = ''
        mkdir -p payload
        ${deps.copyBinaries drv "payload"}
        ${deps.copyWindowsDlls drv "payload"}
        if [ -d "${drv}/share" ]; then
          ${pkgs.rsync}/bin/rsync -a --copy-links "${drv}/share/" "payload/share/" || true
        fi
        chmod -R u+w payload

        ${lib.optionalString hasServices ''
          cp ${pkgs.writeText "install-services.bat" installBat}   payload/install-services.bat
          cp ${pkgs.writeText "uninstall-services.bat" uninstallBat} payload/uninstall-services.bat
        ''}

        cat > installer.nsi <<'NSIEOF'
    ${nsi}
    NSIEOF
        ${pkgs.gnused}/bin/sed -i 's/^    //' installer.nsi

        makensis -V2 -INPUTCHARSET UTF8 installer.nsi

        mkdir -p $out
        cp "${outFile}" "$out/${outFile}"
  '';

  passthru = {
    info = meta;
    inherit target format;
  };
}
