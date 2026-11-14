{ lib }:

# `info.urlSchemes` rendered per platform. The linux half lives in
# file-associations.nix, since schemes join the same `MimeType=` list.
let
  utils = import ./utils.nix { inherit lib; };
  esc = utils.xmlEscape;
  nsisEsc = utils.nsisEscape;

  schemesOf = meta: meta.urlSchemes or [ ];

  # Info.plist keys as an attribute set, for `lib.generators.toPlist`.
  plistKeys =
    meta:
    lib.optionalAttrs (schemesOf meta != [ ]) {
      CFBundleURLTypes = map (s: {
        CFBundleURLName = "${meta.bundleId}.${s.scheme}";
        CFBundleURLSchemes = [ s.scheme ];
        CFBundleTypeRole = "Viewer";
      }) (schemesOf meta);
    };

  # `<Component>` for the MSI under HKCR, like the file associations.
  wixComponent =
    meta:
    let
      exe = "[INSTALLFOLDER]${meta.name}.exe";
      value =
        attrs:
        "      <RegistryValue Root=\"HKCR\" Type=\"string\""
        + lib.concatStrings (lib.mapAttrsToList (k: v: " ${k}=\"${esc v}\"") attrs)
        + "/>\n";
      scheme =
        i: s:
        value (
          {
            Key = s.scheme;
            Value = "URL:${s.name}";
          }
          // lib.optionalAttrs (i == 1) { KeyPath = "yes"; }
        )
        + value {
          Key = s.scheme;
          Name = "URL Protocol";
          Value = "";
        }
        + value {
          Key = "${s.scheme}\\DefaultIcon";
          Value = "${exe},0";
        }
        + value {
          Key = "${s.scheme}\\shell\\open\\command";
          Value = "\"${exe}\" \"%1\"";
        };
    in
    lib.optionalString (schemesOf meta != [ ]) (
      "<DirectoryRef Id=\"INSTALLFOLDER\">\n"
      + "  <Component Id=\"UrlSchemes\" Guid=\"*\">\n"
      + lib.concatStrings (lib.imap1 scheme (schemesOf meta))
      + "  </Component>\n"
      + "</DirectoryRef>\n"
    );

  # NSIS lines under SHCTX\Software\Classes, like the file associations.
  nsisInstall =
    meta:
    let
      exe = "$INSTDIR\\${meta.name}.exe";
      scheme =
        s:
        let
          key = "Software\\Classes\\${s.scheme}";
        in
        ''
          WriteRegStr SHCTX "${key}" "" "URL:${nsisEsc s.name}"
          WriteRegStr SHCTX "${key}" "URL Protocol" ""
          WriteRegStr SHCTX "${key}\DefaultIcon" "" "${exe},0"
          WriteRegStr SHCTX "${key}\shell\open\command" "" '"${exe}" "%1"'
        '';
    in
    lib.concatMapStrings scheme (schemesOf meta);

  nsisUninstall =
    meta:
    lib.concatMapStrings (s: ''
      DeleteRegKey SHCTX "Software\Classes\${s.scheme}"
    '') (schemesOf meta);
in
{
  inherit
    plistKeys
    wixComponent
    nsisInstall
    nsisUninstall
    ;
}
