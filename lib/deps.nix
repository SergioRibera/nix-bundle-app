{
  lib,
  utils,
  closureInfo,
  coreutils,
  file,
  gawk,
  gnugrep,
  gnused,
  patchelf,
  rsync,
}:

let
  linuxBaseLibs = [
    "libc"
    "libm"
    "libdl"
    "libpthread"
    "librt"
    "libutil"
    "libresolv"
    "libnsl"
    "libcrypt"
    "libanl"
    "ld-linux"
    "libgcc_s"
    "libthread_db"
  ];

  darwinBaseLibs = [
    "libSystem"
    "libobjc"
    "libc++"
    "libc++abi"
  ];

  closureOf = drv: closureInfo { rootPaths = if builtins.isList drv then drv else [ drv ]; };

  copyLinuxLibs =
    drv: destLibDir:
    let
      closure = closureOf drv;
    in
    ''
      mkdir -p "${destLibDir}"
      while IFS= read -r path; do
        [ "$path" = "${drv}" ] && continue
        [ -d "$path/lib" ] || continue
        # Skip glibc itself — provides base libs we don't bundle. Use an
        # array because stdenv enables `nullglob`: an unmatched glob in
        # `set --` clears positional params and `$1` becomes unbound,
        # which trips `set -u` in buildCommand. Arrays give a clean
        # length check that works in both nullglob and default modes.
        libc2_matches=( "$path"/lib/libc-2.*.so )
        if [ -e "$path/lib/libc.so.6" ] || [ "''${#libc2_matches[@]}" -gt 0 ]; then
          continue
        fi
        for so in "$path"/lib/*.so*; do
          [ -e "$so" ] || continue
          [ -d "$so" ] && continue
          bn=$(basename "$so")
          skip=0
          ${lib.concatMapStrings (std: ''
            case "$bn" in
              ${std}.so*|${std}-*.so*|${std}_*.so*) skip=1 ;;
            esac
          '') linuxBaseLibs}
          [ $skip -eq 1 ] && continue
          if [ ! -e "${destLibDir}/$bn" ]; then
            cp -P "$so" "${destLibDir}/$bn"
            chmod u+w "${destLibDir}/$bn" 2>/dev/null || true
          fi
        done
      done < ${closure}/store-paths
    '';

  copyDarwinLibs =
    drv: destLibDir:
    let
      closure = closureOf drv;
    in
    ''
      mkdir -p "${destLibDir}"
      while IFS= read -r path; do
        [ "$path" = "${drv}" ] && continue
        [ -d "$path/lib" ] || continue
        for dylib in "$path"/lib/*.dylib; do
          [ -e "$dylib" ] || continue
          [ -d "$dylib" ] && continue
          bn=$(basename "$dylib")
          skip=0
          ${lib.concatMapStrings (std: ''
            case "$bn" in
              ${std}.dylib*|${std}.*.dylib*) skip=1 ;;
            esac
          '') darwinBaseLibs}
          [ $skip -eq 1 ] && continue
          if [ ! -e "${destLibDir}/$bn" ]; then
            cp -P "$dylib" "${destLibDir}/$bn"
            chmod u+w "${destLibDir}/$bn" 2>/dev/null || true
          fi
        done
      done < ${closure}/store-paths
    '';

  copyWindowsDlls =
    drv: destDir:
    let
      closure = closureOf drv;
    in
    ''
      mkdir -p "${destDir}"
      while IFS= read -r path; do
        for dll in "$path"/bin/*.dll "$path"/lib/*.dll; do
          [ -e "$dll" ] || continue
          bn=$(basename "$dll")
          if [ ! -e "${destDir}/$bn" ]; then
            cp "$dll" "${destDir}/$bn"
            chmod u+w "${destDir}/$bn" 2>/dev/null || true
          fi
        done
      done < ${closure}/store-paths
    '';

  patchLinuxBinaries =
    {
      binDir,
      target,
      keepInterpreter,
      setBundledRpath ? true,
    }:
    let
      interp = utils.linuxInterp target.arch;
    in
    ''
      for bin in ${binDir}/*; do
        [ -f "$bin" ] || continue
        if ${file}/bin/file -b "$bin" | ${gnugrep}/bin/grep -q "ELF"; then
          if ${patchelf}/bin/patchelf --print-interpreter "$bin" >/dev/null 2>&1; then
            ${lib.optionalString (!keepInterpreter && interp != null) ''
              ${patchelf}/bin/patchelf --set-interpreter "${interp}" "$bin" || true
            ''}
            ${
              if setBundledRpath then
                ''${patchelf}/bin/patchelf --set-rpath '$ORIGIN/../lib' "$bin" || true''
              else
                # bundleLibs=false: clear the embedded RPATH so the dynamic
                # loader falls through to the system path. Without this
                # patchelf may have stamped a /nix/store path from the
                # source derivation, which doesn't exist on the target.
                ''${patchelf}/bin/patchelf --remove-rpath "$bin" || true''
            }
          fi
        fi
      done
    '';

  patchDarwinBinaries = binDir: ''
    have_tool() { command -v "$1" >/dev/null 2>&1; }
    if ! have_tool install_name_tool; then
      echo "install_name_tool not available on host (need darwin)." >&2
    fi
    for bin in ${binDir}/*; do
      [ -f "$bin" ] || continue
      if ${file}/bin/file -b "$bin" | ${gnugrep}/bin/grep -q "Mach-O"; then
        if have_tool install_name_tool; then
          for dep in $(otool -L "$bin" | tail -n +2 | awk '{print $1}'); do
            case "$dep" in
              /nix/store/*)
                bn=$(basename "$dep")
                install_name_tool -change "$dep" "@executable_path/../Frameworks/$bn" "$bin" || true ;;
            esac
          done
        fi
      fi
    done
  '';

  # What `file -b` prints for a binary built for each target: container
  # format plus its arch string, which isn't uniform (Mach-O uses Apple's
  # own "x86_64"/"arm64" naming; ELF/PE use "x86-64"/"aarch64").
  binarySignature = {
    linux = {
      magic = "ELF";
      arch = {
        x86_64 = "x86-64";
        aarch64 = "aarch64";
      };
    };
    darwin = {
      magic = "Mach-O";
      arch = {
        x86_64 = "x86_64";
        aarch64 = "arm64";
      };
    };
    windows = {
      magic = "PE32";
      arch = {
        x86_64 = "x86-64";
        aarch64 = "aarch64";
      };
    };
  };

  # Fails the build if a staged binary doesn't match `target`. Non-binaries
  # (scripts, data files) are left alone.
  verifyStagedBinaries =
    { binDir, target }:
    let
      sig =
        binarySignature.${target.os}
          or (throw "nix-bundle-app: no binary-format signature for os '${target.os}'");
      archNeedle =
        sig.arch.${target.arch}
          or (throw "nix-bundle-app: no binary-format signature for ${target.os}/${target.arch}");
    in
    ''
      for __vb_bin in "${binDir}"/*; do
        [ -f "$__vb_bin" ] || continue
        __vb_desc=$(${file}/bin/file -b "$__vb_bin" 2>/dev/null) || continue
        case "$__vb_desc" in
          *ELF*|*Mach-O*|*PE32*) : ;;
          *) continue ;; # not a native binary (script, data, …) — nothing to verify
        esac
        if
          ! printf '%s' "$__vb_desc" | ${gnugrep}/bin/grep -qF -- "${sig.magic}" \
          || ! printf '%s' "$__vb_desc" | ${gnugrep}/bin/grep -qF -- "${archNeedle}"
        then
          echo "nix-bundle-app: '$__vb_bin' does not match target ${target.os}/${target.arch} (file: $__vb_desc)" >&2
          exit 1
        fi
      done
    '';

  copyBinaries = drv: destBinDir: ''
    mkdir -p "${destBinDir}"
    if [ -d "${drv}/bin" ]; then
      for bin in ${drv}/bin/*; do
        [ -e "$bin" ] || continue
        install -Dm755 "$bin" "${destBinDir}/$(basename "$bin")"
      done
    fi
  '';

  copyResources = drv: destShareDir: ''
    if [ -d "${drv}/share" ]; then
      mkdir -p "${destShareDir}"
      ${rsync}/bin/rsync -a --copy-links "${drv}/share/" "${destShareDir}/" || true
    fi
  '';

  libMap = (import ./lib-map.nix).sonameMap;

  # Plain string, not a derivation — `discoverLinuxDepsSnippet` heredocs
  # this straight into the caller's own build sandbox instead of spending a
  # separate store path just to `cat`/`awk` it back out again.
  distroLibMapFile =
    kind:
    let
      sonames = builtins.attrNames libMap;
    in
    lib.concatMapStringsSep "\n" (
      n:
      let
        pkg = libMap.${n}.${kind} or null;
      in
      if pkg == null then "" else "${n}\t${pkg}"
    ) sonames;

  discoverLinuxDepsSnippet =
    {
      kind,
      scanDirs,
      userDeps,
      outFile,
    }:
    let
      userList = lib.concatMapStrings (s: s + "\n") userDeps;
    in
    ''
      cat > libmap-${kind}.tsv <<'LIBMAP_EOF'
      ${distroLibMapFile kind}
      LIBMAP_EOF
      cat > user-deps-${kind}.txt <<'USERDEPS_EOF'
      ${userList}
      USERDEPS_EOF
      {
        for d in ${lib.concatStringsSep " " scanDirs}; do
          [ -d "$d" ] || continue
          find "$d" -type f \( -name '*.so*' -o -perm -u+x \) -print0 \
            | while IFS= read -r -d "" f; do
                if ${file}/bin/file -b "$f" | ${gnugrep}/bin/grep -q "ELF"; then
                  ${patchelf}/bin/patchelf --print-needed "$f" 2>/dev/null || true
                fi
              done
        done
      } | tr ' ' '\n' | sort -u > sonames.tmp
      ${gawk}/bin/awk -F'\t' \
        'NR==FNR { if (NF==2) m[$1]=$2; next } m[$0] { print m[$0] }' \
        libmap-${kind}.tsv sonames.tmp \
        | sort -u > auto-deps.tmp
      cat user-deps-${kind}.txt auto-deps.tmp \
        | ${gnused}/bin/sed 's/^ *//;s/ *$//' \
        | ${gnugrep}/bin/grep -v '^$' \
        | sort -u \
        | ${coreutils}/bin/paste -sd, - > "${outFile}"
    '';
in
{
  inherit
    closureOf
    linuxBaseLibs
    darwinBaseLibs
    copyLinuxLibs
    copyDarwinLibs
    copyWindowsDlls
    patchLinuxBinaries
    patchDarwinBinaries
    verifyStagedBinaries
    copyBinaries
    copyResources
    libMap
    distroLibMapFile
    discoverLinuxDepsSnippet
    ;
}
