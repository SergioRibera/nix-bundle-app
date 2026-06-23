# Bundle checks for `info.extraFiles` — system-level extras (udev
# rules, modprobe.d snippets, modules-load.d) materialised next to
# the staged binaries by the linux installer formats.
{ helpers }:

let
  inherit (helpers)
    check
    drv
    info
    pkgs
    ;

  inlineModprobe = "options demo_mod debug=1\n";
  inlineModulesLoad = "demo_mod\n";
  udevRulePath = pkgs.writeText "61-hello.rules" ''
    KERNEL=="demo0", GROUP="video", MODE="0660"
  '';

  extraInfo = info // {
    extraFiles = {
      "/lib/udev/rules.d/61-hello.rules" = udevRulePath;
      "/etc/modprobe.d/hello.conf" = inlineModprobe;
      "/etc/modules-load.d/hello.conf" = inlineModulesLoad;
    };
  };
in
{
  bundle-extra-files-deb = check {
    name = "extra-files-deb";
    format = "deb";
    inherit drv;
    info = extraInfo;
    expect = "hello_*_amd64.deb";
  };

  bundle-extra-files-rpm = check {
    name = "extra-files-rpm";
    format = "rpm";
    inherit drv;
    info = extraInfo;
    expect = "hello-*-1.x86_64.rpm";
  };

  bundle-extra-files-archlinux = check {
    name = "extra-files-archlinux";
    format = "archlinux";
    inherit drv;
    info = extraInfo;
    expect = "hello-*-1-x86_64.pkg.tar.zst";
  };
}
