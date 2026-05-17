{ pkgs, lib, deps, desktop, services, ... }:

let
  systemdRenderedUnits = meta: map services.renderSystemd meta.services;

  writeSystemdUnits = meta: destDir:
    let rendered = systemdRenderedUnits meta; in
      lib.optionalString (rendered != [ ]) ''
        mkdir -p "${destDir}"
        ${lib.concatMapStringsSep "\n" (u: ''
          cp ${pkgs.writeText u.filename u.content} "${destDir}/${u.filename}"
          chmod 644 "${destDir}/${u.filename}"
        '') rendered}
      '';

  writeDesktopEntries = meta: stage:
    lib.optionalString (meta.desktopEntries != [ ]) ''
      mkdir -p "${stage}/usr/share/applications"
      ${lib.concatMapStringsSep "\n" (e: ''
        cp ${pkgs.writeText e.filename e.content} \
           "${stage}/usr/share/applications/${e.filename}"
        chmod 644 "${stage}/usr/share/applications/${e.filename}"
        ${lib.optionalString (e.iconPath != null) ''
          mkdir -p "${stage}/usr/share/icons/hicolor/512x512/apps"
          cp "${e.iconPath}" \
             "${stage}/usr/share/icons/hicolor/512x512/apps/${
               if e.iconName != null then e.iconName else e.name}.png" || true
        ''}
      '') (map desktop.renderEntry meta.desktopEntries)}
    '';

  # The full /opt-style stage.
  stageLinux = { drv, meta, target, stage }: ''
    base="${stage}/opt/${meta.name}"
    mkdir -p "$base/bin" "$base/lib" "$base/share"

    ${deps.copyBinaries drv "$base/bin"}
    ${deps.copyLinuxLibs drv "$base/lib"}
    ${deps.copyResources drv "$base/share"}

    chmod -R u+w "$base"

    ${deps.patchLinuxBinaries "$base/bin" target meta.keepInterpreter}

    mkdir -p "${stage}/usr/bin"
    if [ -x "$base/bin/${meta.name}" ]; then
      ln -sf "/opt/${meta.name}/bin/${meta.name}" "${stage}/usr/bin/${meta.name}"
    else
      for f in "$base/bin"/*; do
        [ -e "$f" ] || continue
        ln -sf "/opt/${meta.name}/bin/$(basename "$f")" "${stage}/usr/bin/$(basename "$f")"
      done
    fi

    ${writeSystemdUnits meta "${stage}/lib/systemd/system"}
    ${writeDesktopEntries meta stage}
  '';

  enabledServiceNames = meta:
    map (u: u.name)
      (builtins.filter (u: u.enable) (systemdRenderedUnits meta));

  hasServices = meta: meta.services != [ ];

  postinstSnippet = meta:
    lib.optionalString (hasServices meta) ''
      if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload || true
        ${lib.concatMapStringsSep "\n  " (n: ''systemctl enable --now "${n}.service" 2>/dev/null || true'')
          (enabledServiceNames meta)}
      fi
    '';

  prermSnippet = meta:
    lib.optionalString (hasServices meta) ''
      if command -v systemctl >/dev/null 2>&1; then
        ${lib.concatMapStringsSep "\n  " (n: ''
          systemctl stop "${n}.service" 2>/dev/null || true
          systemctl disable "${n}.service" 2>/dev/null || true
        '') (enabledServiceNames meta)}
      fi
    '';

  postrmSnippet = meta:
    lib.optionalString (hasServices meta) ''
      if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload || true
      fi
    '';
in
{
  inherit
    stageLinux
    systemdRenderedUnits
    enabledServiceNames
    hasServices
    postinstSnippet
    prermSnippet
    postrmSnippet
    ;
}
