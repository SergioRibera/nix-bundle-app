{
  pkgs,
  lib,
  deps,
  utils,
  services,
  signing,
  drv,
  format,
  meta,
  target,
  ...
}:

let
  winArch = if target.arch == "x86_64" then "x64" else target.arch;
  outFile = "${meta.name}-${meta.version}-${winArch}.msi";

  upgradeCode =
    if meta.msiUpgradeCode or null != null then
      meta.msiUpgradeCode
    else
      let
        h = builtins.hashString "md5" meta.bundleId;
      in
      lib.toUpper "${builtins.substring 0 8 h}-${builtins.substring 8 4 h}-${builtins.substring 12 4 h}-${builtins.substring 16 4 h}-${builtins.substring 20 12 h}";

  msiArchAttr = if target.arch == "x86_64" then ''Platform="x64"'' else "";
  programFilesId = if target.arch == "x86_64" then "ProgramFiles64Folder" else "ProgramFilesFolder";

  esc = utils.xmlEscape;

  svcXmlByBin = services.msiServiceXmlByBin meta.services;
  svcBinNames = builtins.attrNames svcXmlByBin;

  wxs = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
      <Product Id="*"
               Name="${esc meta.name}"
               Language="1033"
               Version="${esc meta.version}"
               Manufacturer="${esc meta.maintainer}"
               UpgradeCode="${upgradeCode}">
        <Package InstallerVersion="200"
                 Compressed="yes"
                 InstallScope="perMachine"
                 ${msiArchAttr}
                 Description="${esc meta.summary}"
                 Manufacturer="${esc meta.maintainer}"/>
        <MajorUpgrade DowngradeErrorMessage="A newer version of ${esc meta.name} is already installed."/>
        <MediaTemplate EmbedCab="yes"/>

        <Directory Id="TARGETDIR" Name="SourceDir">
          <Directory Id="${programFilesId}">
            <Directory Id="INSTALLFOLDER" Name="${esc meta.installDirName}"/>
          </Directory>
          <Directory Id="ProgramMenuFolder">
            <Directory Id="ApplicationProgramsFolder" Name="${esc meta.name}"/>
          </Directory>
        </Directory>

        <DirectoryRef Id="ApplicationProgramsFolder">
          <Component Id="ApplicationShortcut" Guid="*">
            <Shortcut Id="AppShortcut"
                      Name="${esc meta.name}"
                      Description="${esc meta.summary}"
                      Target="[INSTALLFOLDER]${esc meta.name}.exe"
                      WorkingDirectory="INSTALLFOLDER"/>
            <RemoveFolder Id="RemoveAppMenuFolder" On="uninstall"/>
            <RegistryValue Root="HKCU"
                           Key="Software\${esc meta.name}"
                           Name="installed"
                           Type="integer"
                           Value="1"
                           KeyPath="yes"/>
          </Component>
        </DirectoryRef>

        <Feature Id="MainFeature" Title="${esc meta.name}" Level="1">
          <ComponentGroupRef Id="MainComponents"/>
          <ComponentRef Id="ApplicationShortcut"/>
        </Feature>
      </Product>
    </Wix>
  '';

  writeServiceXmlFiles = lib.concatMapStringsSep "\n" (bn: ''
    cp ${pkgs.writeText "msi-svc-${bn}.xml" svcXmlByBin.${bn}} "$svcdir/${bn}.xml"
  '') svcBinNames;

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
pkgs.stdenv.mkDerivation {
  name = outFile;
  dontUnpack = true;
  nativeBuildInputs = with pkgs; [
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
      ${pkgs.rsync}/bin/rsync -a --copy-links "${drv}/share/" "payload/share/" || true
    fi
    chmod -R u+w payload

    cp ${pkgs.writeText "installer.wxs" wxs} installer.wxs
    ${pkgs.gnused}/bin/sed -i 's/^    //' installer.wxs

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
    inherit target format;
  };
}
