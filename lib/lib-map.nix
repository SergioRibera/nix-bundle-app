{
  # Maps shared-library SONAME → per-distro package name. Lookup is exact:
  # if the SONAME isn't here, no entry is added (the user can supply their
  # own via `info.depends.<distro>`).
  # Conservative pin: each row points at the most widely-shipped package.
  sonameMap = {
    "libc.so.6"          = { deb = "libc6";                 rpm = "glibc";           archlinux = "glibc"; };
    "libm.so.6"          = { deb = "libc6";                 rpm = "glibc";           archlinux = "glibc"; };
    "libdl.so.2"         = { deb = "libc6";                 rpm = "glibc";           archlinux = "glibc"; };
    "libpthread.so.0"    = { deb = "libc6";                 rpm = "glibc";           archlinux = "glibc"; };
    "librt.so.1"         = { deb = "libc6";                 rpm = "glibc";           archlinux = "glibc"; };
    "libutil.so.1"       = { deb = "libc6";                 rpm = "glibc";           archlinux = "glibc"; };
    "libresolv.so.2"     = { deb = "libc6";                 rpm = "glibc";           archlinux = "glibc"; };
    "libnsl.so.1"        = { deb = "libnsl2";               rpm = "libnsl";          archlinux = "libnsl"; };
    "libcrypt.so.1"      = { deb = "libcrypt1";             rpm = "libxcrypt";       archlinux = "libxcrypt"; };
    "libanl.so.1"        = { deb = "libc6";                 rpm = "glibc";           archlinux = "glibc"; };
    "libgcc_s.so.1"      = { deb = "libgcc-s1";             rpm = "libgcc";          archlinux = "gcc-libs"; };
    "libstdc++.so.6"     = { deb = "libstdc++6";            rpm = "libstdc++";       archlinux = "gcc-libs"; };

    "libz.so.1"          = { deb = "zlib1g";                rpm = "zlib";            archlinux = "zlib"; };
    "libzstd.so.1"       = { deb = "libzstd1";              rpm = "libzstd";         archlinux = "zstd"; };
    "libbz2.so.1.0"      = { deb = "libbz2-1.0";            rpm = "bzip2-libs";      archlinux = "bzip2"; };
    "liblzma.so.5"       = { deb = "liblzma5";              rpm = "xz-libs";         archlinux = "xz"; };

    "libssl.so.3"        = { deb = "libssl3";               rpm = "openssl-libs";    archlinux = "openssl"; };
    "libcrypto.so.3"     = { deb = "libssl3";               rpm = "openssl-libs";    archlinux = "openssl"; };
    "libssl.so.1.1"      = { deb = "libssl1.1";             rpm = "openssl-libs";    archlinux = "openssl-1.1"; };
    "libcrypto.so.1.1"   = { deb = "libssl1.1";             rpm = "openssl-libs";    archlinux = "openssl-1.1"; };
    "libcurl.so.4"       = { deb = "libcurl4";              rpm = "libcurl";         archlinux = "curl"; };
    "libsqlite3.so.0"    = { deb = "libsqlite3-0";          rpm = "sqlite-libs";     archlinux = "sqlite"; };
    "libgmp.so.10"       = { deb = "libgmp10";              rpm = "gmp";             archlinux = "gmp"; };

    "libpng16.so.16"     = { deb = "libpng16-16";           rpm = "libpng";          archlinux = "libpng"; };
    "libjpeg.so.8"       = { deb = "libjpeg-turbo8";        rpm = "libjpeg-turbo";   archlinux = "libjpeg-turbo"; };
    "libtiff.so.6"       = { deb = "libtiff6";              rpm = "libtiff";         archlinux = "libtiff"; };
    "libfreetype.so.6"   = { deb = "libfreetype6";          rpm = "freetype";        archlinux = "freetype2"; };
    "libfontconfig.so.1" = { deb = "libfontconfig1";        rpm = "fontconfig";      archlinux = "fontconfig"; };
    "libharfbuzz.so.0"   = { deb = "libharfbuzz0b";         rpm = "harfbuzz";        archlinux = "harfbuzz"; };

    "libglib-2.0.so.0"   = { deb = "libglib2.0-0";          rpm = "glib2";           archlinux = "glib2"; };
    "libgio-2.0.so.0"    = { deb = "libglib2.0-0";          rpm = "glib2";           archlinux = "glib2"; };
    "libgobject-2.0.so.0"= { deb = "libglib2.0-0";          rpm = "glib2";           archlinux = "glib2"; };
    "libgthread-2.0.so.0"= { deb = "libglib2.0-0";          rpm = "glib2";           archlinux = "glib2"; };
    "libgmodule-2.0.so.0"= { deb = "libglib2.0-0";          rpm = "glib2";           archlinux = "glib2"; };

    "libgtk-3.so.0"      = { deb = "libgtk-3-0";            rpm = "gtk3";            archlinux = "gtk3"; };
    "libgtk-4.so.1"      = { deb = "libgtk-4-1";            rpm = "gtk4";            archlinux = "gtk4"; };
    "libgdk-3.so.0"      = { deb = "libgtk-3-0";            rpm = "gtk3";            archlinux = "gtk3"; };
    "libgdk_pixbuf-2.0.so.0" = { deb = "libgdk-pixbuf-2.0-0"; rpm = "gdk-pixbuf2";   archlinux = "gdk-pixbuf2"; };
    "libcairo.so.2"      = { deb = "libcairo2";             rpm = "cairo";           archlinux = "cairo"; };
    "libpango-1.0.so.0"  = { deb = "libpango-1.0-0";        rpm = "pango";           archlinux = "pango"; };
    "libpangocairo-1.0.so.0" = { deb = "libpangocairo-1.0-0"; rpm = "pango";         archlinux = "pango"; };

    "libqt5core.so.5"    = { deb = "libqt5core5a";          rpm = "qt5-qtbase";      archlinux = "qt5-base"; };
    "libqt5gui.so.5"     = { deb = "libqt5gui5";            rpm = "qt5-qtbase";      archlinux = "qt5-base"; };
    "libqt5widgets.so.5" = { deb = "libqt5widgets5";        rpm = "qt5-qtbase";      archlinux = "qt5-base"; };
    "libqt6core.so.6"    = { deb = "libqt6core6";           rpm = "qt6-qtbase";      archlinux = "qt6-base"; };
    "libqt6gui.so.6"     = { deb = "libqt6gui6";            rpm = "qt6-qtbase";      archlinux = "qt6-base"; };

    "libx11.so.6"        = { deb = "libx11-6";              rpm = "libX11";          archlinux = "libx11"; };
    "libxext.so.6"       = { deb = "libxext6";              rpm = "libXext";         archlinux = "libxext"; };
    "libxrender.so.1"    = { deb = "libxrender1";           rpm = "libXrender";      archlinux = "libxrender"; };
    "libxrandr.so.2"     = { deb = "libxrandr2";            rpm = "libXrandr";       archlinux = "libxrandr"; };
    "libxcb.so.1"        = { deb = "libxcb1";               rpm = "libxcb";          archlinux = "libxcb"; };
    "libxkbcommon.so.0"  = { deb = "libxkbcommon0";         rpm = "libxkbcommon";    archlinux = "libxkbcommon"; };
    "libwayland-client.so.0" = { deb = "libwayland-client0"; rpm = "libwayland-client"; archlinux = "wayland"; };
    "libwayland-cursor.so.0" = { deb = "libwayland-cursor0"; rpm = "libwayland-cursor"; archlinux = "wayland"; };

    "libdbus-1.so.3"     = { deb = "libdbus-1-3";           rpm = "dbus-libs";       archlinux = "dbus"; };
    "libudev.so.1"       = { deb = "libudev1";              rpm = "systemd-libs";    archlinux = "systemd-libs"; };
    "libsystemd.so.0"    = { deb = "libsystemd0";           rpm = "systemd-libs";    archlinux = "systemd-libs"; };
  };
}
