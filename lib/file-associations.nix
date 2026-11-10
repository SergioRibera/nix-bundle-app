{ lib }:

# `info.fileAssociations` rendered per platform. Pure string helpers: the
# format modules decide where each piece lands.
let
  esc = (import ./utils.nix { inherit lib; }).xmlEscape;

  # Every MIME type the app opens, in declaration order.
  mimeTypesOf = meta: lib.unique (lib.concatMap (a: a.mimeTypes) (meta.fileAssociations or [ ]));

  # Without a field code the desktop launches the app without the file.
  hasFieldCode = exec: builtins.match ".*%[fFuU].*" exec != null;

  # Desktop entries that list no MIME types of their own take every
  # association's; entries with explicit `mimeTypes` are left alone.
  withMimeTypes =
    meta: entry:
    let
      mimes = mimeTypesOf meta;
    in
    if mimes == [ ] || (entry.mimeTypes or [ ]) != [ ] then
      entry
    else
      entry
      // {
        mimeTypes = mimes;
        exec = if hasFieldCode entry.exec then entry.exec else "${entry.exec} %F";
      };

  exportedOf = meta: builtins.filter (a: a.exported) (meta.fileAssociations or [ ]);

  # shared-mime-info package declaring the exported types, or null when the
  # app defines none with a MIME type.
  mimePackage =
    meta:
    let
      declare =
        a: mime:
        "  <mime-type type=\"${esc mime}\">\n"
        + "    <comment>${esc a.name}</comment>\n"
        + lib.concatMapStrings (e: "    <glob pattern=\"*.${esc e}\"/>\n") a.extensions
        + "  </mime-type>\n";
      body = lib.concatMapStrings (a: lib.concatMapStrings (declare a) a.mimeTypes) (exportedOf meta);
    in
    if body == "" then
      null
    else
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      + "<mime-info xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\">\n"
      + body
      + "</mime-info>\n";

  # Path of `mimePackage` inside the staged tree. flatpak only exports MIME
  # packages named after the app id, which is the bundle id.
  mimePackagePath = meta: "/usr/share/mime/packages/${meta.bundleId}.xml";

  capitalize = s: lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (-1) s;

  plistArray = xs: "<array>${lib.concatMapStrings (x: "<string>${esc x}</string>") xs}</array>";

  # UTIs macOS already declares; importing them again is noise.
  isSystemUti =
    id: lib.hasPrefix "public." id || lib.hasPrefix "com.apple." id || id == "com.adobe.pdf";

  utiDeclaration =
    a:
    "    <dict>\n"
    + "      <key>UTTypeIdentifier</key><string>${esc a.id}</string>\n"
    + "      <key>UTTypeDescription</key><string>${esc a.name}</string>\n"
    + "      <key>UTTypeConformsTo</key>${plistArray a.conformsTo}\n"
    + "      <key>UTTypeTagSpecification</key>\n"
    + "      <dict>\n"
    + lib.optionalString (
      a.extensions != [ ]
    ) "        <key>public.filename-extension</key>${plistArray a.extensions}\n"
    + lib.optionalString (
      a.mimeTypes != [ ]
    ) "        <key>public.mime-type</key>${plistArray a.mimeTypes}\n"
    + "      </dict>\n"
    + "    </dict>\n";

  documentType =
    a:
    "    <dict>\n"
    + "      <key>CFBundleTypeName</key><string>${esc a.name}</string>\n"
    + "      <key>CFBundleTypeRole</key><string>${capitalize a.role}</string>\n"
    + "      <key>LSHandlerRank</key><string>${capitalize a.rank}</string>\n"
    + (
      if a.id != null then
        "      <key>LSItemContentTypes</key>${plistArray [ a.id ]}\n"
      else
        lib.optionalString (
          a.extensions != [ ]
        ) "      <key>CFBundleTypeExtensions</key>${plistArray a.extensions}\n"
        + lib.optionalString (
          a.mimeTypes != [ ]
        ) "      <key>CFBundleTypeMIMETypes</key>${plistArray a.mimeTypes}\n"
    )
    + "    </dict>\n";

  # Info.plist keys, placed directly inside the top-level `<dict>` at a
  # two-space indent.
  plistKeys =
    meta:
    let
      assocs = meta.fileAssociations or [ ];
      exported = exportedOf meta;
      imported = builtins.filter (a: !a.exported && a.id != null && !isSystemUti a.id) assocs;
      section =
        key: items: render:
        lib.optional (items != [ ]) (
          "<key>${key}</key>\n  <array>\n" + lib.concatMapStrings render items + "  </array>"
        );
    in
    lib.concatStringsSep "\n  " (
      section "CFBundleDocumentTypes" assocs documentType
      ++ section "UTExportedTypeDeclarations" exported utiDeclaration
      ++ section "UTImportedTypeDeclarations" imported utiDeclaration
    );

  # Windows: one ProgID per association that names extensions. Exported
  # types own their id; any other type gets an app-scoped ProgID so two
  # apps opening PDFs don't overwrite each other's `shell\open\command`.
  windowsProgIds =
    meta:
    map (a: {
      inherit (a) name extensions;
      owner = a.rank == "owner";
      progId = if a.exported then a.id else "${meta.bundleId}.${builtins.head a.extensions}";
    }) (builtins.filter (a: a.extensions != [ ]) (meta.fileAssociations or [ ]));

  # `<Component>` for the MSI, written under HKCR (HKLM\Software\Classes in
  # this per-machine install). Windows Installer drops the values on
  # uninstall.
  wixComponent =
    meta:
    let
      exe = "[INSTALLFOLDER]${meta.name}.exe";
      value =
        attrs:
        "      <RegistryValue Root=\"HKCR\" Type=\"string\""
        + lib.concatStrings (lib.mapAttrsToList (k: v: " ${k}=\"${esc v}\"") attrs)
        + "/>\n";
      progId =
        i: p:
        value (
          {
            Key = p.progId;
            Value = p.name;
          }
          // lib.optionalAttrs (i == 1) { KeyPath = "yes"; }
        )
        + value {
          Key = p.progId;
          Name = "FriendlyTypeName";
          Value = p.name;
        }
        + value {
          Key = "${p.progId}\\DefaultIcon";
          Value = "${exe},0";
        }
        + value {
          Key = "${p.progId}\\shell\\open\\command";
          Value = "\"${exe}\" \"%1\"";
        }
        + lib.concatMapStrings (
          e:
          value {
            Key = ".${e}\\OpenWithProgids";
            Name = p.progId;
            Value = "";
          }
          + lib.optionalString p.owner (value {
            Key = ".${e}";
            Value = p.progId;
          })
        ) p.extensions;
      progIds = windowsProgIds meta;
    in
    lib.optionalString (progIds != [ ]) (
      "<DirectoryRef Id=\"INSTALLFOLDER\">\n"
      + "  <Component Id=\"FileAssociations\" Guid=\"*\">\n"
      + lib.concatStrings (lib.imap1 progId progIds)
      + "  </Component>\n"
      + "</DirectoryRef>\n"
    );

  # NSIS install/uninstall lines, under HKLM\Software\Classes like the rest
  # of this per-machine installer. Uninstall only clears an extension's
  # default when it still points at our ProgID.
  # NSIS string literal: `$` starts a variable, `$\"` is a quote.
  nsisEsc = builtins.replaceStrings [ "$" "\"" ] [ "$$" "$\\\"" ];

  nsisInstall =
    meta:
    let
      exe = "$INSTDIR\\${meta.name}.exe";
      progIds = windowsProgIds meta;
      progId =
        p:
        let
          key = "Software\\Classes\\${p.progId}";
        in
        ''
          WriteRegStr HKLM "${key}" "" "${nsisEsc p.name}"
          WriteRegStr HKLM "${key}" "FriendlyTypeName" "${nsisEsc p.name}"
          WriteRegStr HKLM "${key}\DefaultIcon" "" "${exe},0"
          WriteRegStr HKLM "${key}\shell\open\command" "" '"${exe}" "%1"'
        ''
        + lib.concatMapStrings (e: ''
          WriteRegStr HKLM "Software\Classes\.${e}\OpenWithProgids" "${p.progId}" ""
          ${lib.optionalString p.owner ''WriteRegStr HKLM "Software\Classes\.${e}" "" "${p.progId}"''}
        '') p.extensions;
    in
    lib.optionalString (progIds != [ ]) (
      lib.concatMapStrings progId progIds
      + "System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'\n"
    );

  nsisUninstall =
    meta:
    let
      progIds = windowsProgIds meta;
      progId =
        p:
        lib.concatMapStrings (e: ''
          DeleteRegValue HKLM "Software\Classes\.${e}\OpenWithProgids" "${p.progId}"
          ${lib.optionalString p.owner ''
            ReadRegStr $0 HKLM "Software\Classes\.${e}" ""
            StrCmp $0 "${p.progId}" 0 +2
            DeleteRegValue HKLM "Software\Classes\.${e}" ""
          ''}
        '') p.extensions
        + ''
          DeleteRegKey HKLM "Software\Classes\${p.progId}"
        '';
    in
    lib.optionalString (progIds != [ ]) (
      lib.concatMapStrings progId progIds
      + "System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'\n"
    );
in
{
  inherit
    mimeTypesOf
    withMimeTypes
    mimePackage
    mimePackagePath
    plistKeys
    windowsProgIds
    wixComponent
    nsisInstall
    nsisUninstall
    ;
}
