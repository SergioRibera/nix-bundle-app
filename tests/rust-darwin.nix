# End-to-end darwin bundle tests for the Rust demo binary. Only extracts the
# .app/.pkg/etc. payload to check structure, since running the binary
# requires a darwin host.
{ helpers }:

let
  inherit (helpers)
    e2e
    pkgs
    rustInfo
    rustDarwin
    rustName
    rustVersion
    ;

  darwinTarget = {
    arch = "x86_64";
    os = "darwin";
  };
in
{
  rust-app = e2e {
    name = "rust-app";
    format = "app";
    drv = rustDarwin;
    info = rustInfo;
    target = darwinTarget;
    expect = "${rustName}.app";
    assertScript = ''
      test -d "$artifact"
      test -f "$artifact/Contents/Info.plist"
      test -x "$artifact/Contents/MacOS/${rustName}"
      grep -q "CFBundleIdentifier" "$artifact/Contents/Info.plist"
    '';
  };

  rust-pkg = e2e {
    name = "rust-pkg";
    format = "pkg";
    drv = rustDarwin;
    info = rustInfo;
    target = darwinTarget;
    expect = "${rustName}-${rustVersion}-x86_64.pkg";
    probeInputs = [ pkgs.xar ];
    assertScript = ''
      tmp=$(mktemp -d)
      ( cd "$tmp" && xar -xf "$artifact" )
      test -f "$tmp/PackageInfo"
      test -f "$tmp/Payload"
      grep -q '${rustName}' "$tmp/PackageInfo"
    '';
  };

  rust-productbuild = e2e {
    name = "rust-productbuild";
    format = "productbuild";
    drv = rustDarwin;
    info = rustInfo // {
      productbuild = {
        title = "Rust Demo Installer";
        license = pkgs.writeText "license.txt" "BSD-2-Clause.";
        welcome = pkgs.writeText "welcome.html" "<html><body>Welcome.</body></html>";
      };
    };
    target = darwinTarget;
    expect = "${rustName}-${rustVersion}-x86_64-install.pkg";
    probeInputs = [ pkgs.xar ];
    assertScript = ''
      tmp=$(mktemp -d)
      ( cd "$tmp" && xar -xf "$artifact" )
      test -f "$tmp/Distribution"
      test -f "$tmp/Resources/welcome.html"
      test -f "$tmp/Resources/license.txt"
      test -f "$tmp/${rustName}-${rustVersion}-x86_64.pkg"
      grep -q "Rust Demo Installer" "$tmp/Distribution"
    '';
  };

  rust-brew = e2e {
    name = "rust-brew";
    format = "brew";
    drv = rustDarwin;
    info = rustInfo;
    target = darwinTarget;
    expect = "${rustName}.rb";
    assertScript = ''
      grep -q "class .* < Formula" "$artifact"
      grep -q "sha256 \".*\"" "$artifact"
    '';
  };
}
