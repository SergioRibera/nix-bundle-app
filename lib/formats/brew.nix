{
  callPackage,
  stdenv,
  lib,
  utils,
  desktop,
  services,
  drv,
  format,
  meta,
  target,
  coreutils,
  gnused,
  writeText,
  ...
}:

let
  tarball = callPackage ./tarball.nix {
    inherit
      utils
      desktop
      services
      drv
      target
      ;
    format = "tar.gz";
    meta = meta // {
      format = "tar.gz";
    };
  };

  tarballFilename = "${meta.name}-${meta.version}-${target.arch}-${target.os}.tar.gz";
  className =
    let
      s = meta.name;
      head = lib.toUpper (builtins.substring 0 1 s);
      tail = builtins.substring 1 (builtins.stringLength s) s;
    in
    head + tail;

  url =
    if meta.downloadUrl != "" then
      meta.downloadUrl
    else
      "https://example.com/releases/${meta.version}/${tarballFilename}";

  brewDeps = meta.depends.brew or [ ];

  # Brew formula has to work on both macOS and Linuxbrew. Differences:
  # macOS uses `service` blocks for launchd, Linuxbrew can't register
  # system services. We emit `service do ... end` only if the user gave
  # darwin services; on linux brew it's a no-op and ignored gracefully.
  serviceBlock =
    if meta.services == [ ] || target.os != "darwin" then
      ""
    else
      let
        s = builtins.head meta.services;
        argv = builtins.filter (x: x != "") (lib.splitString " " s.exec);
        rubyArgs = lib.concatMapStringsSep ", " (a: ''"${if lib.hasPrefix "/" a then a else a}"'') argv;
      in
      ''

        service do
          run [${rubyArgs}]
          run_type :immediate
          keep_alive true
          log_path var/"log/${meta.name}.log"
          error_log_path var/"log/${meta.name}.err.log"
        end'';

  formula = lib.concatStringsSep "\n" (
    [
      "class ${className} < Formula"
      "  desc \"${meta.summary}\""
      "  homepage \"${meta.homepage}\""
      "  url \"${url}\""
      "  sha256 \"PLACEHOLDER_SHA256_REPLACE_AFTER_UPLOAD\""
      "  version \"${meta.version}\""
      "  license \"${meta.license}\""
    ]
    ++ map (d: "  depends_on \"" + d + "\"") brewDeps
    ++ [
      ""
      "  def install"
      "    bin.install Dir[\"bin/*\"]"
      "    lib.install Dir[\"lib/*\"] if Dir.exist?(\"lib\")"
      "    share.install Dir[\"share/*\"] if Dir.exist?(\"share\")"
      "  end"
    ]
    ++ (if serviceBlock == "" then [ ] else [ serviceBlock ])
    ++ [
      ""
      "  test do"
      "    system \"#{bin}/${meta.name}\", \"--version\""
      "  end"
      "end"
      ""
    ]
  );
in
stdenv.mkDerivation {
  name = "${meta.name}-${meta.version}-brew";
  dontUnpack = true;
  nativeBuildInputs = [
    coreutils
    gnused
  ];

  buildCommand = ''
    mkdir -p $out
    cp ${tarball}/${tarballFilename} "$out/${tarballFilename}"

    sha=$(${coreutils}/bin/sha256sum "$out/${tarballFilename}" | ${coreutils}/bin/cut -d' ' -f1)

    cp ${writeText "formula.rb" formula} "$out/${meta.name}.rb"
    chmod u+w "$out/${meta.name}.rb"
    ${gnused}/bin/sed -i "s/PLACEHOLDER_SHA256_REPLACE_AFTER_UPLOAD/$sha/" "$out/${meta.name}.rb"

    cp ${writeText "README-brew.txt" ''
      Upload ${tarballFilename} to a public URL.
      Edit ${meta.name}.rb and set the 'url' field to that URL.
      Then publish ${meta.name}.rb in a tap repo, e.g. homebrew-tap.

      Install with:
        brew install --formula ./${meta.name}.rb
    ''} "$out/README-brew.txt"
  '';

  passthru = {
    info = meta;
    inherit target format tarball;
    outFile = "${meta.name}.rb";
  };
}
