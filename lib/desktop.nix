{ lib }:

let
  # Render a single value to its .desktop string form.
  # null/empty → omit. bool → true/false. list → ";"-joined with trailing ;.
  formatValue = v:
    if v == null then null
    else if builtins.isBool v then (if v then "true" else "false")
    else if builtins.isList v then
      let items = builtins.filter (x: x != null && toString x != "") v;
      in if items == [] then null else lib.concatStringsSep ";" (map toString items) + ";"
    else
      let s = toString v;
      in if s == "" then null else s;

  # .desktop spec: backslashes, leading spaces, newlines must be escaped.
  escapeValue = s:
    builtins.replaceStrings
      [ "\\"   "\n"   "\r"   "\t"  ]
      [ "\\\\" "\\n"  "\\r"  "\\t" ]
      (toString s);

  kv = key: value:
    let s = formatValue value;
    in if s == null then null else "${key}=${escapeValue s}";

  renderSection = header: pairs:
    let
      lines = lib.mapAttrsToList kv pairs;
      kept = builtins.filter (l: l != null) lines;
    in [ "[${header}]" ] ++ kept;

  defaults = {
    type = "Application";
    terminal = false;
    categories = [ "Utility" ];
    extra = {};
    actions = {};
  };

  # Map struct → flat attrset of key=>value pairs for [Desktop Entry].
  mainPairs = e: {
    Type = e.type;
    Name = e.name;
    GenericName = e.genericName or null;
    Comment = e.comment or null;
    Exec = e.exec;
    TryExec = e.tryExec or null;
    Icon = e.icon or null;
    Terminal = e.terminal;
    Categories = e.categories;
    MimeType = e.mimeTypes or null;
    Keywords = e.keywords or null;
    StartupNotify = e.startupNotify or null;
    StartupWMClass = e.startupWMClass or null;
    Path = e.workingDirectory or null;
    NoDisplay = e.noDisplay or null;
    Hidden = e.hidden or null;
    SingleMainWindow = e.singleMainWindow or null;
    DBusActivatable = e.dbusActivatable or null;
    PrefersNonDefaultGPU = e.prefersNonDefaultGPU or null;
  };

  actionPairs = a: {
    Name = a.name;
    Exec = a.exec;
    Icon = a.icon or null;
  };

  # `null`-safe attr access. Schema-validated entries have all options
  # explicitly present (typically `null`), so plain `attr or fallback` no
  # longer falls through.
  pick = attrs: key: fallback:
    let v = attrs.${key} or null; in
    if v == null then fallback else v;

  renderEntry = raw:
    assert lib.assertMsg ((raw.name or null) != null && raw.name != "")
      "nix-bundle-app: desktop entry is missing a non-empty `name`.";
    assert lib.assertMsg ((raw.exec or null) != null && raw.exec != "")
      "nix-bundle-app: desktop entry '${raw.name}' is missing a non-empty `exec`.";
    let
      e = lib.recursiveUpdate defaults raw;
      actionNames = builtins.attrNames e.actions;
      mainKvs = mainPairs e
        // (lib.optionalAttrs (actionNames != []) { Actions = actionNames; })
        // e.extra;
      mainBlock = renderSection "Desktop Entry" mainKvs;
      actionBlock = name:
        renderSection "Desktop Action ${name}" (actionPairs e.actions.${name});
      actionBlocks =
        lib.concatMap (n: [ "" ] ++ actionBlock n) actionNames;
      content =
        lib.concatStringsSep "\n" (mainBlock ++ actionBlocks) + "\n";
      filename = (pick e "fileName" e.name) + ".desktop";
    in {
      inherit content filename;
      iconPath = pick e "iconPath" null;
      iconName = pick e "icon" null;
      name = e.name;
    };

  # Best-effort parser: read a real .desktop file into the same struct shape
  # that renderEntry consumes. Only the [Desktop Entry] section.
  fromFile = path:
    let
      raw = builtins.readFile path;
      lines = lib.splitString "\n" raw;
      bodyLines = builtins.filter
        (l: l != "" && !(lib.hasPrefix "#" l) && !(lib.hasPrefix "[" l))
        lines;
      parse = line:
        let
          parts = lib.splitString "=" line;
          k = builtins.head parts;
          v = lib.concatStringsSep "=" (builtins.tail parts);
        in { ${k} = v; };
      kvs = lib.foldl' (acc: l: acc // parse l) {} bodyLines;
      asList = s: builtins.filter (x: x != "") (lib.splitString ";" s);
      asBool = s: s == "true" || s == "1";
    in {
      name = kvs.Name or null;
      genericName = kvs.GenericName or null;
      comment = kvs.Comment or null;
      exec = kvs.Exec or null;
      tryExec = kvs.TryExec or null;
      icon = kvs.Icon or null;
      type = kvs.Type or "Application";
      terminal = asBool (kvs.Terminal or "false");
      categories = asList (kvs.Categories or "");
      mimeTypes = asList (kvs.MimeType or "");
      keywords = asList (kvs.Keywords or "");
    };
in
{
  inherit renderEntry fromFile;
}
