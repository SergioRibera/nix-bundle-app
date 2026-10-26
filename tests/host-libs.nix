# `info.hostLibs`: GPU-stack / config-path libraries in the closure must
# stay out of linux bundles by default, and come back when the list is
# emptied. The fixture drags libGL + fontconfig into the closure through
# a store reference next to the binary.
{ helpers }:

let
  inherit (helpers)
    e2e
    pkgs
    rustInfo
    rustLinux
    rustName
    rustVersion
    ;

  withGpuClosure = pkgs.runCommand "${rustName}-${rustVersion}" { } ''
    mkdir -p $out/bin $out/share/${rustName}
    cp ${rustLinux}/bin/${rustName} $out/bin/
    echo ${pkgs.libGL} ${pkgs.fontconfig.lib} ${pkgs.libpng} > $out/share/${rustName}/refs
  '';

  tarball =
    {
      name,
      info,
      assertScript,
    }:
    e2e {
      inherit name info assertScript;
      format = "tar.gz";
      drv = withGpuClosure;
      target = {
        arch = "x86_64";
        os = "linux";
      };
      expect = "${rustName}-${rustVersion}-x86_64-linux.tar.gz";
    };
in
{
  host-libs-default = tarball {
    name = "host-libs-default";
    info = rustInfo;
    assertScript = ''
      tmp=$(mktemp -d)
      tar -xzf "$artifact" -C "$tmp"
      libs=$(find "$tmp" -path '*/lib/*' -name '*.so*' -printf '%f\n')
      echo "$libs" | grep -q '^libpng16\.so' || { echo "libpng should be bundled" >&2; exit 1; }
      if echo "$libs" | grep -E '^lib(GL|GLX|GLdispatch|EGL|fontconfig)\.so'; then
        echo "host libraries leaked into the bundle" >&2
        exit 1
      fi
    '';
  };

  host-libs-empty = tarball {
    name = "host-libs-empty";
    info = rustInfo // {
      hostLibs = [ ];
    };
    assertScript = ''
      tmp=$(mktemp -d)
      tar -xzf "$artifact" -C "$tmp"
      libs=$(find "$tmp" -path '*/lib/*' -name '*.so*' -printf '%f\n')
      echo "$libs" | grep -q '^libGL\.so' || { echo "libGL should be bundled with hostLibs = [ ]" >&2; exit 1; }
      echo "$libs" | grep -q '^libfontconfig\.so' || { echo "libfontconfig should be bundled with hostLibs = [ ]" >&2; exit 1; }
    '';
  };
}
