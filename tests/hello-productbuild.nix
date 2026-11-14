# The productbuild Distribution XML follows `productbuild.*`.
{ helpers }:

let
  inherit (helpers)
    bundler
    drv
    info
    pkgs
    ;

  # Eval-level: reading `.distribution` builds nothing, so it runs off darwin.
  distribution =
    productbuild:
    pkgs.writeText "Distribution"
      (bundler.bundle {
        inherit drv;
        format = "productbuild";
        info = info // {
          inherit productbuild;
        };
        target = {
          arch = "x86_64";
          os = "darwin";
        };
      }).distribution;
in
{
  productbuild-customize = pkgs.runCommand "e2e-productbuild-customize" { } ''
    grep -qF 'customize="never"' ${distribution { }}
    grep -qF 'customize="allow"' ${distribution { allowCustomize = true; }}
    touch $out
  '';
}
