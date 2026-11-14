{ lib }:

# AppStream metainfo (`/usr/share/metainfo/<bundleId>.metainfo.xml`): what
# GNOME Software, KDE Discover and Flathub read for the app's listing.
let
  utils = import ./utils.nix { inherit lib; };
  desktop = import ./desktop.nix { inherit lib; };
  esc = utils.xmlEscape;

  path = meta: "/usr/share/metainfo/${meta.bundleId}.metainfo.xml";

  enabled =
    meta: if meta.appstream.enable != null then meta.appstream.enable else meta.desktopEntries != [ ];

  # Blank lines split paragraphs; AppStream wants `<p>` per paragraph.
  paragraphs =
    text:
    builtins.filter (p: p != "") (
      map lib.trim (lib.splitString "\n\n" (lib.replaceStrings [ "\r" ] [ "" ] text))
    );

  render =
    meta:
    let
      as = meta.appstream;
      gui = meta.desktopEntries != [ ];
      idParts = lib.splitString "." meta.bundleId;
      developerId = lib.concatStringsSep "." (lib.take (builtins.length idParts - 1) idParts);
      description = paragraphs (
        if meta.longDescription != "" then meta.longDescription else meta.summary
      );
      launchable = (desktop.renderEntry (builtins.head meta.desktopEntries)).filename;
      screenshot =
        i: s:
        "    <screenshot${lib.optionalString (i == 1) " type=\"default\""}>\n"
        + "      <image>${esc s.image}</image>\n"
        + lib.optionalString (s.caption != null) "      <caption>${esc s.caption}</caption>\n"
        + "    </screenshot>\n";
    in
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    + "<component type=\"${if gui then "desktop-application" else "console-application"}\">\n"
    + "  <id>${esc meta.bundleId}</id>\n"
    + "  <name>${esc meta.displayName}</name>\n"
    + "  <summary>${esc meta.summary}</summary>\n"
    + "  <metadata_license>${esc as.metadataLicense}</metadata_license>\n"
    + "  <project_license>${esc meta.license}</project_license>\n"
    + "  <developer id=\"${esc developerId}\">\n"
    + "    <name>${esc meta.publisher}</name>\n"
    + "  </developer>\n"
    + "  <description>\n"
    + lib.concatMapStrings (p: "    <p>${esc p}</p>\n") description
    + "  </description>\n"
    + lib.optionalString gui "  <launchable type=\"desktop-id\">${esc launchable}</launchable>\n"
    + lib.optionalString (meta.homepage != "") "  <url type=\"homepage\">${esc meta.homepage}</url>\n"
    + "  <provides>\n"
    + "    <binary>${esc meta.name}</binary>\n"
    + "  </provides>\n"
    + lib.optionalString (as.screenshots != [ ]) (
      "  <screenshots>\n" + lib.concatStrings (lib.imap1 screenshot as.screenshots) + "  </screenshots>\n"
    )
    + lib.optionalString (as.releaseDate != null) (
      "  <releases>\n"
      + "    <release version=\"${esc meta.version}\" date=\"${as.releaseDate}\"/>\n"
      + "  </releases>\n"
    )
    + "  <content_rating type=\"oars-1.1\"/>\n"
    + "</component>\n";

  # Shell lines writing the metainfo under `root`, or nothing when disabled.
  write =
    meta: root:
    lib.optionalString (enabled meta) ''
      mkdir -p "${root}/usr/share/metainfo"
      cat > "${root}${path meta}" <<'METAINFO_EOF'
      ${render meta}
      METAINFO_EOF
      chmod 644 "${root}${path meta}"
    '';
in
{
  inherit
    path
    enabled
    render
    write
    ;
}
