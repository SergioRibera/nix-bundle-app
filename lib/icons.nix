# Every platform's app icon, derived from the single square PNG in
# `info.icon`:
#
#   $out/hicolor/<s>x<s>/apps/icon.png   freedesktop sizes, 16–512
#   $out/icon.ico                        Windows, 16–256 (PNG frames)
#   $out/icon.icns                       macOS, 16–1024
#
# Formats install these under their own names (`meta.iconName` on Linux,
# `AppIcon.icns` in a `.app`, …); this derivation only renders them.
{
  runCommand,
  imagemagick,
  libicns,
  source,
}:

let
  hicolorSizes = [
    16
    24
    32
    48
    64
    128
    256
    512
  ];
  icoSizes = [
    16
    24
    32
    48
    64
    256
  ];
  # The sizes `png2icns` knows an ICNS element type for.
  icnsSizes = [
    16
    32
    48
    128
    256
    512
    1024
  ];
  sizesArg = sizes: builtins.concatStringsSep " " (map toString sizes);
in
runCommand "nix-bundle-app-icons"
  {
    nativeBuildInputs = [
      imagemagick
      libicns
    ];
  }
  ''
    render() {
      magick "${source}" -background none -resize "$1x$1" -gravity center -extent "$1x$1" \
        -define png:color-type=6 "$2"
    }

    for s in ${sizesArg hicolorSizes}; do
      mkdir -p "$out/hicolor/''${s}x''${s}/apps"
      render "$s" "$out/hicolor/''${s}x''${s}/apps/icon.png"
    done

    mkdir -p work
    for s in ${sizesArg icoSizes}; do render "$s" "work/ico-$s.png"; done
    magick ${builtins.concatStringsSep " " (map (s: "work/ico-${toString s}.png") icoSizes)} \
      "$out/icon.ico"

    for s in ${sizesArg icnsSizes}; do render "$s" "work/icns-$s.png"; done
    png2icns "$out/icon.icns" \
      ${builtins.concatStringsSep " " (map (s: "work/icns-${toString s}.png") icnsSizes)}
  ''
