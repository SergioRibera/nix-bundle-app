{ lib }:

rec {
  parseSystem =
    system:
    let
      parts = builtins.split "-" system;
      arch = builtins.elemAt parts 0;
      os = builtins.elemAt parts 2;
    in
    {
      inherit arch;
      os = if os == "darwin" then "darwin" else os;
    };

  detectTargetFromDrv =
    drv:
    let
      sys = drv.system or drv.stdenv.hostPlatform.system or "x86_64-linux";
      p = parseSystem sys;
    in
    normalizeTarget p;

  normalizeTarget =
    t:
    if builtins.isString t then
      parseSystem t
    else
      let
        os' = t.os;
        os = if os' == "macos" then "darwin" else os';
      in
      {
        inherit (t) arch;
        inherit os;
      };

  debArch =
    arch:
    {
      "x86_64" = "amd64";
      "aarch64" = "arm64";
      "armv7l" = "armhf";
      "armv6l" = "armel";
      "i686" = "i386";
      "riscv64" = "riscv64";
    }
    .${arch} or arch;

  rpmArch =
    arch:
    {
      "x86_64" = "x86_64";
      "aarch64" = "aarch64";
      "armv7l" = "armv7hl";
      "i686" = "i386";
      "riscv64" = "riscv64";
    }
    .${arch} or arch;

  archArch =
    arch:
    {
      "x86_64" = "x86_64";
      "aarch64" = "aarch64";
      "i686" = "i686";
      "armv7l" = "armv7h";
      "armv6l" = "armv6h";
    }
    .${arch} or arch;

  darwinArch =
    arch:
    {
      "x86_64" = "x86_64";
      "aarch64" = "arm64";
    }
    .${arch} or arch;

  linuxInterp =
    arch:
    {
      "x86_64" = "/lib64/ld-linux-x86-64.so.2";
      "aarch64" = "/lib/ld-linux-aarch64.so.1";
      "i686" = "/lib/ld-linux.so.2";
      "armv7l" = "/lib/ld-linux-armhf.so.3";
      "armv6l" = "/lib/ld-linux-armhf.so.3";
      "riscv64" = "/lib/ld-linux-riscv64-lp64d.so.1";
    }
    .${arch} or null;

  shellQuote = s: "'" + builtins.replaceStrings [ "'" ] [ "'\\''" ] s + "'";

  xmlEscape =
    s: builtins.replaceStrings [ "&" "<" ">" "\"" "'" ] [ "&amp;" "&lt;" "&gt;" "&quot;" "&apos;" ] s;

  sanitizeName =
    s:
    let
      ok =
        c:
        (c >= "a" && c <= "z")
        || (c >= "A" && c <= "Z")
        || (c >= "0" && c <= "9")
        || c == "-"
        || c == "_"
        || c == ".";
      chars = lib.stringToCharacters s;
    in
    lib.concatStrings (map (c: if ok c then c else "-") chars);

  # Debian package-name policy: lowercase alphanumerics + `-+.` only,
  # must start with an alphanumeric. dpkg-deb --build rejects anything
  # else (notably `_`). Used by the deb format to derive a valid
  # `Package:` field + asset filename from `meta.name` when the caller's
  # chosen name isn't already debian-compliant. Install paths stay on
  # the upstream `meta.name` so symlink locations are consistent across
  # distros — only the deb-visible identifier is rewritten.
  debName =
    s:
    let
      lower = lib.toLower s;
      ok =
        c:
        (c >= "a" && c <= "z")
        || (c >= "0" && c <= "9")
        || c == "-"
        || c == "+"
        || c == ".";
      chars = lib.stringToCharacters lower;
      mapped = lib.concatStrings (map (c: if ok c then c else "-") chars);
      # Strip leading non-alphanumeric to satisfy the "must start with
      # alphanumeric" rule. Cheap belt-and-suspenders — typical inputs
      # already start with a letter.
      startsAlnum =
        c: (c >= "a" && c <= "z") || (c >= "0" && c <= "9");
      stripped =
        if mapped == "" || startsAlnum (builtins.substring 0 1 mapped)
        then mapped
        else "p-" + mapped;
    in
    stripped;
}
