{ pkgs, lib, utils }:

let
  # Libraries assumed to exist on every target system. Never bundled.
  linuxBaseLibs = [
    "libc" "libm" "libdl" "libpthread" "librt" "libutil"
    "libresolv" "libnsl" "libcrypt" "libanl"
    "ld-linux" "libgcc_s" "libthread_db"
  ];

  darwinBaseLibs = [
    "libSystem" "libobjc" "libc++" "libc++abi"
  ];

  # Returns a closureInfo derivation for drv (drv may also be a list).
  closureOf = drv:
    pkgs.closureInfo { rootPaths = if builtins.isList drv then drv else [ drv ]; };

  # Shell snippet that walks the closure of `drv` and copies any
  # shared libraries that are NOT base system libs into `destLibDir`.
  # Skips: the package containing libc (glibc itself), the bundled drv
  # itself (its libs travel under the bundle's bin layout), and direct
  # subdirs of lib/ (avoids dragging gconv/locale/.../*.so plugins).
  copyLinuxLibs = drv: destLibDir:
    let closure = closureOf drv; in ''
      mkdir -p "${destLibDir}"
      while IFS= read -r path; do
        [ "$path" = "${drv}" ] && continue
        [ -d "$path/lib" ] || continue
        # Skip glibc itself — it provides base libs we don't bundle.
        if [ -e "$path/lib/libc.so.6" ] || [ -e "$path/lib/libc-2".*.so ]; then
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

  copyDarwinLibs = drv: destLibDir:
    let closure = closureOf drv; in ''
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

  copyWindowsDlls = drv: destDir:
    let closure = closureOf drv; in ''
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

  # Re-link every ELF binary under $1 so that its dynamic loader is the
  # system one and its RPATH points to a peer "lib" dir.
  # Args: binDir, target attrs ({ arch, ... }), keepInterpreter (bool)
  patchLinuxBinaries = binDir: target: keepInterpreter:
    let interp = utils.linuxInterp target.arch; in ''
      for bin in ${binDir}/*; do
        [ -f "$bin" ] || continue
        if ${pkgs.file}/bin/file -b "$bin" | ${pkgs.gnugrep}/bin/grep -q "ELF"; then
          if ${pkgs.patchelf}/bin/patchelf --print-interpreter "$bin" >/dev/null 2>&1; then
            ${lib.optionalString (!keepInterpreter && interp != null) ''
              ${pkgs.patchelf}/bin/patchelf --set-interpreter "${interp}" "$bin" || true
            ''}
            ${pkgs.patchelf}/bin/patchelf --set-rpath '$ORIGIN/../lib' "$bin" || true
          fi
        fi
      done
    '';

  # Rewrite mach-o load commands so that bundled dylibs are looked up
  # relative to @executable_path/../Frameworks.
  patchDarwinBinaries = binDir: ''
    have_tool() { command -v "$1" >/dev/null 2>&1; }
    if ! have_tool install_name_tool; then
      echo "install_name_tool not available on host (need darwin)." >&2
    fi
    for bin in ${binDir}/*; do
      [ -f "$bin" ] || continue
      if ${pkgs.file}/bin/file -b "$bin" | ${pkgs.gnugrep}/bin/grep -q "Mach-O"; then
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

  # Generic: copy all binaries from drv into destBinDir, marking exec.
  copyBinaries = drv: destBinDir: ''
    mkdir -p "${destBinDir}"
    if [ -d "${drv}/bin" ]; then
      for bin in ${drv}/bin/*; do
        [ -e "$bin" ] || continue
        install -Dm755 "$bin" "${destBinDir}/$(basename "$bin")"
      done
    fi
  '';

  # Generic resource copy (icons, data, share/) if present.
  copyResources = drv: destShareDir: ''
    if [ -d "${drv}/share" ]; then
      mkdir -p "${destShareDir}"
      ${pkgs.rsync}/bin/rsync -a --copy-links "${drv}/share/" "${destShareDir}/" || true
    fi
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
    copyBinaries
    copyResources
    ;
}
