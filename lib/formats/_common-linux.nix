{
  pkgs,
  lib,
  deps,
  desktop,
  services,
  ...
}:

let
  systemdRenderedUnits = meta: map services.renderSystemd meta.services;

  writeSystemdUnits =
    meta: destDir:
    let
      rendered = systemdRenderedUnits meta;
    in
    lib.optionalString (rendered != [ ]) ''
      mkdir -p "${destDir}"
      ${lib.concatMapStringsSep "\n" (u: ''
        cp ${pkgs.writeText u.filename u.content} "${destDir}/${u.filename}"
        chmod 644 "${destDir}/${u.filename}"
      '') rendered}
    '';

  writeDesktopEntries =
    meta: stage:
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
               if e.iconName != null then e.iconName else e.name
             }.png" || true
        ''}
      '') (map desktop.renderEntry meta.desktopEntries)}
    '';

  # Materialise meta.extraFiles into the staged tree. Each entry is
  # `<absolute dest path> = <Nix path | inline string>`. Inline strings
  # become a `pkgs.writeText` whose basename mirrors the destination's
  # so debug listings (`dpkg -c`, `rpm -qlp`) stay readable.
  writeExtraFiles =
    meta: stage:
    let
      entries = meta.extraFiles or { };
      materialise =
        dest: src:
        let
          # Strings get materialised via writeText; anything else
          # (Nix path, store path, derivation) coerces via the
          # interpolation below. Distinguishing on `isString`
          # (rather than `isPath`) keeps derivation-typed values
          # like `pkgs.writeText ...` out of the writeText path,
          # which would otherwise emit a deprecation warning.
          srcFile = if builtins.isString src then pkgs.writeText (baseNameOf dest) src else src;
        in
        # `${srcFile}` (no `toString`) is what forces Nix to copy a
        # raw filesystem path into the store AND register it as a
        # derivation input. Using `toString` returned the filesystem
        # path verbatim, which the sandboxed builder couldn't see —
        # `cp` would fail with `No such file or directory`.
        ''
          mkdir -p "$(dirname "${stage}${dest}")"
          cp -L "${srcFile}" "${stage}${dest}"
          chmod 644 "${stage}${dest}"
        '';
    in
    lib.optionalString (entries != { }) (
      lib.concatStringsSep "\n" (lib.mapAttrsToList materialise entries)
    );

  # True iff any meta.extraFiles destination lands under a known
  # udev rules directory — triggers a post-install `udevadm reload`.
  hasUdevRules =
    meta:
    lib.any (
      k:
      lib.hasPrefix "/lib/udev/rules.d/" k
      || lib.hasPrefix "/usr/lib/udev/rules.d/" k
      || lib.hasPrefix "/etc/udev/rules.d/" k
    ) (builtins.attrNames (meta.extraFiles or { }));

  udevReloadSnippet =
    meta:
    lib.optionalString (hasUdevRules meta) ''
      if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger 2>/dev/null || true
      fi
    '';

  stageLinux =
    {
      drv,
      meta,
      target,
      stage,
    }:
    ''
      base="${stage}/opt/${meta.name}"
      mkdir -p "$base/bin" "$base/lib" "$base/share"

      ${deps.copyBinaries drv "$base/bin"}
      ${deps.copyLinuxLibs drv "$base/lib"}
      ${deps.copyResources drv "$base/share"}

      chmod -R u+w "$base"

      ${deps.patchLinuxBinaries "$base/bin" target meta.keepInterpreter}

      mkdir -p "${stage}/usr/bin"
      # Relative symlinks (`../../opt/<name>/bin/<file>`) resolve both at the
      # staged-tree level (so consumers like snap/flatpak can `cp -L` or
      # dereference safely) and at install-time on the target system, since
      # `/usr/bin/X` and `/opt/<name>/bin/X` keep the same relative distance.
      if [ -x "$base/bin/${meta.name}" ]; then
        ln -srf "$base/bin/${meta.name}" "${stage}/usr/bin/${meta.name}"
      else
        for f in "$base/bin"/*; do
          [ -e "$f" ] || continue
          ln -srf "$f" "${stage}/usr/bin/$(basename "$f")"
        done
      fi

      ${writeSystemdUnits meta "${stage}/lib/systemd/system"}
      ${writeDesktopEntries meta stage}
      ${writeExtraFiles meta stage}
    '';

  enabledServiceNames =
    meta: map (u: u.name) (builtins.filter (u: u.enable) (systemdRenderedUnits meta));

  hasServices = meta: meta.services != [ ];

  postinstSnippet =
    meta:
    lib.concatStrings [
      (lib.optionalString (hasServices meta) ''
        if command -v systemctl >/dev/null 2>&1; then
          systemctl daemon-reload || true
          ${lib.concatMapStringsSep "\n  " (
            n: ''systemctl enable --now "${n}.service" 2>/dev/null || true''
          ) (enabledServiceNames meta)}
        fi
      '')
      (udevReloadSnippet meta)
    ];

  prermSnippet =
    meta:
    lib.optionalString (hasServices meta) ''
      if command -v systemctl >/dev/null 2>&1; then
        ${lib.concatMapStringsSep "\n  " (n: ''
          systemctl stop "${n}.service" 2>/dev/null || true
          systemctl disable "${n}.service" 2>/dev/null || true
        '') (enabledServiceNames meta)}
      fi
    '';

  postrmSnippet =
    meta:
    lib.concatStrings [
      (lib.optionalString (hasServices meta) ''
        if command -v systemctl >/dev/null 2>&1; then
          systemctl daemon-reload || true
        fi
      '')
      (udevReloadSnippet meta)
    ];

  # True iff the bundle has any reason to emit maintainer scripts —
  # services (systemctl daemon-reload + enable) and/or udev rules
  # (`udevadm control --reload-rules`) both need post-install hooks.
  needsPostScripts = meta: hasServices meta || hasUdevRules meta;

  # Destination paths from meta.extraFiles, used by rpm/archlinux to
  # enumerate files in the package manifest.
  extraFilesPaths = meta: builtins.attrNames (meta.extraFiles or { });

  # Top-level directories the staged tree touches, derived from
  # extraFiles + the canonical `opt|usr|lib` set the bundler always
  # writes to. Used by archlinux PKGBUILD `package()` to know which
  # `$srcdir/<top>` trees to copy into `$pkgdir/`.
  stageTopLevelDirs =
    meta:
    let
      base = [
        "opt"
        "usr"
        "lib"
      ];
      fromExtras = map (
        p: lib.head (lib.splitString "/" (lib.removePrefix "/" p))
      ) (extraFilesPaths meta);
    in
    lib.unique (base ++ fromExtras);
in
{
  inherit
    stageLinux
    systemdRenderedUnits
    enabledServiceNames
    hasServices
    hasUdevRules
    needsPostScripts
    postinstSnippet
    prermSnippet
    postrmSnippet
    extraFilesPaths
    stageTopLevelDirs
    ;
}
