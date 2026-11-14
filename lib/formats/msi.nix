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
  msitools,
  coreutils,
  gnused,
  gawk,
  rsync,
  findutils,
  file,
  gnugrep,
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
  winArch = if target.arch == "x86_64" then "x64" else target.arch;
  outFile = "${meta.name}-${meta.version}-${winArch}.msi";

  win = meta.windows;
  perUser = win.scope == "perUser";

  upgradeCode =
    if win.upgradeCode != null then
      win.upgradeCode
    else
      let
        h = builtins.hashString "md5" meta.bundleId;
      in
      lib.toUpper "${builtins.substring 0 8 h}-${builtins.substring 8 4 h}-${builtins.substring 12 4 h}-${builtins.substring 16 4 h}-${builtins.substring 20 12 h}";

  msiArchAttr = if target.arch == "x86_64" then ''Platform="x64"'' else "";
  programFilesId = if target.arch == "x86_64" then "ProgramFiles64Folder" else "ProgramFilesFolder";

  esc = utils.xmlEscape;
  hasIcon = meta.iconSet != null;

  svcXmlByBin = services.msiServiceXmlByBin meta.services;
  svcBinNames = builtins.attrNames svcXmlByBin;

  fileAssociations = import ../file-associations.nix { inherit lib; };
  urlSchemes = import ../url-schemes.nix { inherit lib; };
  assocComponent = fileAssociations.wixComponent meta;
  schemeComponent = urlSchemes.wixComponent meta;

  # Inbound allow rules for the declared ports, added after the files land and
  # dropped before they go. netsh comes from the system PATH (CustomAction
  # type 50); rules need admin, so per-user installs get none.
  local = meta.permissions.network.local;
  firewallRules = lib.optionals (local != null && !perUser) (
    lib.optional (local.udp != [ ]) {
      id = "Udp";
      protocol = "UDP";
      ports = local.udp;
    }
    ++ lib.optional (local.tcp != [ ]) {
      id = "Tcp";
      protocol = "TCP";
      ports = local.tcp;
    }
  );
  ruleName = esc meta.displayName;
  firewallXml = lib.optionalString (firewallRules != [ ]) ''
    <Property Id="NETSH" Value="netsh.exe"/>
    ${lib.concatMapStrings (r: ''
      <CustomAction Id="FirewallAdd${r.id}" Property="NETSH" Execute="deferred" Impersonate="no" Return="ignore"
                    ExeCommand="advfirewall firewall add rule name=&quot;${ruleName}&quot; dir=in action=allow protocol=${r.protocol} localport=${
                      lib.concatMapStringsSep "," toString r.ports
                    } program=&quot;[INSTALLFOLDER]${esc meta.name}.exe&quot; enable=yes"/>
    '') firewallRules}
    <CustomAction Id="FirewallRemove" Property="NETSH" Execute="deferred" Impersonate="no" Return="ignore"
                  ExeCommand="advfirewall firewall delete rule name=&quot;${ruleName}&quot;"/>
    <InstallExecuteSequence>
      ${lib.concatMapStrings (r: ''
        <Custom Action="FirewallAdd${r.id}" After="InstallFiles">NOT Installed</Custom>
      '') firewallRules}
      <Custom Action="FirewallRemove" Before="RemoveFiles">REMOVE="ALL"</Custom>
    </InstallExecuteSequence>
  '';

  arpProperties = lib.filterAttrs (_: v: v != null && v != "") {
    ARPURLINFOABOUT = meta.homepage;
    ARPHELPLINK = win.arp.helpUrl;
    ARPURLUPDATEINFO = win.arp.updateUrl;
    ARPCONTACT = win.arp.contact;
    ARPCOMMENTS = win.arp.comments;
  };

  # Shortcut components need a registry KeyPath; HKCU is what Windows
  # Installer expects for shortcuts.
  shortcutComponent = id: dir: ''
    <DirectoryRef Id="${dir}">
      <Component Id="${id}" Guid="*">
        <Shortcut Id="${id}Link"
                  Name="${esc meta.displayName}"
                  Description="${esc meta.summary}"
                  Target="[INSTALLFOLDER]${esc meta.name}.exe"
                  ${lib.optionalString hasIcon ''Icon="AppIcon.ico"''}
                  WorkingDirectory="INSTALLFOLDER"/>
        ${lib.optionalString (
          dir == "ApplicationProgramsFolder"
        ) ''<RemoveFolder Id="RemoveAppMenuFolder" On="uninstall"/>''}
        <RegistryValue Root="HKCU"
                       Key="Software\${esc meta.name}"
                       Name="${id}"
                       Type="integer"
                       Value="1"
                       KeyPath="yes"/>
      </Component>
    </DirectoryRef>
  '';
  shortcuts =
    lib.optional win.shortcuts.startMenu {
      id = "ApplicationShortcut";
      dir = "ApplicationProgramsFolder";
    }
    ++ lib.optional win.shortcuts.desktop {
      id = "DesktopShortcut";
      dir = "DesktopFolder";
    };

  wxs = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
      <Product Id="*"
               Name="${esc meta.displayName}"
               Language="1033"
               Version="${esc meta.numericVersion}"
               Manufacturer="${esc meta.publisher}"
               UpgradeCode="${upgradeCode}">
        <Package InstallerVersion="200"
                 Compressed="yes"
                 InstallScope="${win.scope}"
                 ${msiArchAttr}
                 Description="${esc meta.summary}"
                 Manufacturer="${esc meta.publisher}"/>
        <MajorUpgrade DowngradeErrorMessage="A newer version of ${esc meta.displayName} is already installed."/>
        <MediaTemplate EmbedCab="yes"/>
        ${lib.optionalString hasIcon ''
          <Icon Id="AppIcon.ico" SourceFile="app-icon.ico"/>
          <Property Id="ARPPRODUCTICON" Value="AppIcon.ico"/>
        ''}
        ${lib.concatStrings (
          lib.mapAttrsToList (k: v: ''
            <Property Id="${k}" Value="${esc v}"/>
          '') arpProperties
        )}

        <Directory Id="TARGETDIR" Name="SourceDir">
          ${
            if perUser then
              ''
                <Directory Id="LocalAppDataFolder">
                  <Directory Id="UserProgramsFolder" Name="Programs">
                    <Directory Id="INSTALLFOLDER" Name="${esc meta.installDirName}"/>
                  </Directory>
                </Directory>
              ''
            else
              ''
                <Directory Id="${programFilesId}">
                  <Directory Id="INSTALLFOLDER" Name="${esc meta.installDirName}"/>
                </Directory>
              ''
          }
          <Directory Id="ProgramMenuFolder">
            <Directory Id="ApplicationProgramsFolder" Name="${esc meta.displayName}"/>
          </Directory>
          <Directory Id="DesktopFolder"/>
        </Directory>

        ${lib.concatMapStrings (s: shortcutComponent s.id s.dir) shortcuts}
        ${assocComponent}
        ${schemeComponent}
        ${firewallXml}
        <Feature Id="MainFeature" Title="${esc meta.displayName}" Level="1">
          <ComponentGroupRef Id="MainComponents"/>
          ${lib.concatMapStrings (s: ''<ComponentRef Id="${s.id}"/>'') shortcuts}
          ${lib.optionalString (assocComponent != "") ''<ComponentRef Id="FileAssociations"/>''}
          ${lib.optionalString (schemeComponent != "") ''<ComponentRef Id="UrlSchemes"/>''}
        </Feature>
      </Product>
    </Wix>
  '';

  writeServiceXmlFiles = lib.concatStrings (
    lib.imap1 (i: bn: ''
      cat > "$svcdir/${bn}.xml" <<'SVCXML_${toString i}_EOF'
      ${svcXmlByBin.${bn}}
      SVCXML_${toString i}_EOF
    '') svcBinNames
  );

  injectScript = ''
    awk -v inj_dir="$svcdir" -v binnames="${lib.concatStringsSep " " svcBinNames}" '
      BEGIN {
        n = split(binnames, arr, " ")
        for (i = 1; i <= n; i++) has[arr[i]] = 1
        armed = ""
      }
      /<File / {
        if (match($0, /Source="[^"]*"/)) {
          src = substr($0, RSTART + 8, RLENGTH - 9)
          np = split(src, parts, "/")
          bn = parts[np]
          if (has[bn]) armed = inj_dir "/" bn ".xml"
        }
        print
        next
      }
      /<\/Component>/ {
        if (armed != "") {
          while ((getline line < armed) > 0) print line
          close(armed)
          armed = ""
        }
        print
        next
      }
      { print }
    ' components.wxs > components.wxs.new
    mv components.wxs.new components.wxs
  '';
in
stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = [
    msitools
    coreutils
    gnused
    gawk
    rsync
    findutils
  ];

  buildCommand = ''
    mkdir -p payload
    ${deps.copyBinaries drv "payload"}
    ${deps.copyWindowsDlls drv "payload"}
    if [ -d "${drv}/share" ]; then
      ${rsync}/bin/rsync -a --copy-links "${drv}/share/" "payload/share/" || true
    fi
    chmod -R u+w payload

    ${lib.optionalString hasIcon ''cp "${meta.iconSet}/icon.ico" app-icon.ico''}
    cat > installer.wxs <<'WXS_EOF'
    ${wxs}
    WXS_EOF
    ${gnused}/bin/sed -i 's/^    //' installer.wxs

    find payload -type f \
      | wixl-heat \
          --prefix "payload/" \
          --var "var.SourceDir" \
          --component-group MainComponents \
          --directory-ref INSTALLFOLDER \
          ${lib.optionalString (target.arch == "x86_64") "--win64"} \
        > components.wxs

    ${lib.optionalString (svcBinNames != [ ]) ''
      svcdir=$PWD/svc-xml
      mkdir -p "$svcdir"
      ${writeServiceXmlFiles}
      ${injectScript}
    ''}

    wixl --arch ${if target.arch == "x86_64" then "x64" else "x86"} \
         -D SourceDir=payload \
         -D Win64=${if target.arch == "x86_64" then "yes" else "no"} \
         -o "${outFile}" \
         installer.wxs components.wxs

    mkdir -p $out
    cp "${outFile}" "$out/${outFile}"

    ${signing.emitSignScript {
      inherit meta format;
      artifactGlob = "*.msi";
    }}
  '';

  passthru = {
    info = meta;
    inherit
      target
      format
      outFile
      wxs
      ;
  };
}
