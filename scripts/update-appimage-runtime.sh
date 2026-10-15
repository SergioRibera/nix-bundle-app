#!/usr/bin/env bash
# Refresh the vendored AppImage runtimes from AppImage/type2-runtime's
# rolling `continuous` release tag. Run this and commit the result when
# upstream publishes a new build.
set -euo pipefail

cd "$(dirname "$0")/.."
dest=vendor/appimage-runtime
mkdir -p "$dest"

base=https://github.com/AppImage/type2-runtime/releases/download/continuous
for arch in x86_64 aarch64 armhf i686; do
  echo "fetching runtime-$arch…"
  curl -fsSL "$base/runtime-$arch" -o "$dest/runtime-$arch"
done

sha256sum "$dest"/runtime-* > "$dest/SHA256SUMS"
echo
echo "updated vendor/appimage-runtime/:"
cat "$dest/SHA256SUMS"
