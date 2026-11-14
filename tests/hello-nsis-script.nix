# The generated NSIS script: names with `"` or `$` stay literal, and the
# machine-wide install also puts its Start-menu shortcut machine-wide.
{ helpers }:

let
  inherit (helpers)
    bundler
    drvWin
    info
    pkgs
    ;

  # Eval-level: reading `.nsi` builds nothing, so it runs without makensis.
  nsi =
    (bundler.bundle {
      drv = drvWin;
      format = "nsis";
      info = info // {
        displayName = ''Say "hi" for $5'';
      };
      target = {
        arch = "x86_64";
        os = "windows";
      };
    }).nsi;
in
{
  nsis-script = pkgs.runCommand "e2e-nsis-script" { } ''
    nsi=${pkgs.writeText "installer.nsi" nsi}
    grep -qF '!define DISPLAYNAME "Say $\"hi$\" for $$5"' "$nsi"
    test "$(grep -c '^ *SetShellVarContext all$' "$nsi")" -eq 2
    # NSIS has no `$\{` escape; defines must reach makensis as `''${X}` and paths use single backslashes.
    grep -qF 'Name "''${DISPLAYNAME}"' "$nsi"
    if grep -qF '\\' "$nsi"; then exit 1; fi
    touch $out
  '';
}
