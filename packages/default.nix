{
  pkgs,
  lib ? import ../lib { inherit (pkgs) lib; },
}:
let
  mkBrowsers = lib.mkBrowsers pkgs;
  lock = builtins.fromJSON (builtins.readFile ../packages.lock);

  # Map core revision to mkBrowsers attrset.
  resolveBrowsersForCore =
    coreName:
    let
      coreRevisions = lock.coreSets.${coreName};
    in
    builtins.mapAttrs (
      browserName: revision:
      let
        browserEntry = lock.browsers.${browserName}.${revision};
      in
      {
        inherit revision;
        inherit (browserEntry) hashes;
      }
      // (if browserEntry ? browserVersion then { inherit (browserEntry) browserVersion; } else { })
    ) coreRevisions;

  mkCli =
    version: pin:
    pkgs.callPackage ./playwright-cli.nix { } {
      inherit version;
      inherit (pin) packageSha srcHash npmDepsHash;
      browsers = mkBrowsers (resolveBrowsersForCore pin.core);
    };

  mkMcp =
    version: pin:
    pkgs.callPackage ./playwright-mcp.nix { } {
      inherit version;
      inherit (pin) packageSha srcHash npmDepsHash;
      browsers = mkBrowsers (resolveBrowsersForCore pin.core);
    };

  mkNode =
    version: pin:
    pkgs.callPackage ./playwright-node.nix { } {
      inherit version;
      inherit (pin) packageHash coreHash;
      browsers = mkBrowsers (resolveBrowsersForCore pin.core);
    };

  mkDotnet =
    version: pin:
    pkgs.callPackage ./playwright-dotnet.nix { } {
      inherit version;
      inherit (pin) packageHash;
      browsers = mkBrowsers (resolveBrowsersForCore pin.core);
    };

  mkPython =
    version: pin:
    pkgs.callPackage ./playwright-python.nix { } {
      inherit version;
      driverVersion = pin.core;
      inherit (pin) srcHash driverHashes;
      driverUrls = pin.driverUrls or null;
      browsers = mkBrowsers (resolveBrowsersForCore pin.core);
    };

  mkCamoufoxBrowsers =
    version: pin:
    pkgs.callPackage ./camoufox.nix { } {
      inherit version;
      inherit (pin) tag sources;
    };

  mkCamoufox =
    version: pin:
    pkgs.callPackage ./camoufox-wrapper.nix {
      inherit version;
      inherit (pin) pypi url hash;
      src = null;
      browser = buildCamoufoxBrowsers.camoufox-browsers;
    };

  mkCamoufoxPlaywrightCli =
    camoufox:
    pkgs.callPackage ./camoufox-playwright-cli.nix { } {
      inherit camoufox;
      playwrightCli = cliOutputs.playwright-cli;
    };

  # Replace dots with underscores for Nix CLI compat.
  toAttr = v: builtins.replaceStrings [ "." ] [ "_" ] v;

  # Build tool attrset from lockfile.
  buildTool =
    {
      prefix,
      toolData,
      mk,
    }:
    let
      versions = builtins.attrNames toolData.versions;
      versionedPkgs = map (v: {
        name = "${prefix}-${toAttr v}";
        value = mk v toolData.versions.${v};
      }) versions;
      versionedBrowsers = map (v: {
        name = "${prefix}-${toAttr v}-browsers";
        value = mkBrowsers (resolveBrowsersForCore toolData.versions.${v}.core);
      }) versions;
      latestPin = toolData.versions.${toolData.latest};
    in
    builtins.listToAttrs (versionedPkgs ++ versionedBrowsers)
    // {
      "${prefix}" = mk toolData.latest latestPin;
      "${prefix}-browsers" = mkBrowsers (resolveBrowsersForCore latestPin.core);
    };

  cliOutputs = buildTool {
    prefix = "playwright-cli";
    toolData = lock.tools.cli;
    mk = mkCli;
  };

  mcpOutputs = buildTool {
    prefix = "playwright-mcp";
    toolData = lock.tools.mcp;
    mk = mkMcp;
  };

  nodeOutputs = buildTool {
    prefix = "playwright-node";
    toolData = lock.tools.node;
    mk = mkNode;
  };

  dotnetOutputs = buildTool {
    prefix = "playwright-dotnet";
    toolData = lock.tools.dotnet;
    mk = mkDotnet;
  };

  pythonOutputs = buildTool {
    prefix = "playwright-python";
    toolData = lock.tools.python;
    mk = mkPython;
  };

  buildCamoufoxBrowsers =
    let
      toolData = lock.tools."camoufox-browsers";
      versions = builtins.attrNames toolData.versions;
      versionedPkgs = map (v: {
        name = "camoufox-browsers-${toAttr v}";
        value = mkCamoufoxBrowsers v toolData.versions.${v};
      }) versions;
      latestPin = toolData.versions.${toolData.latest};
    in
    builtins.listToAttrs versionedPkgs
    // {
      camoufox-browsers = mkCamoufoxBrowsers toolData.latest latestPin;
    };

  buildCamoufox =
    let
      toolData = lock.tools.camoufox;
      versions = builtins.attrNames toolData.versions;
      versionedPkgs = map (v: {
        name = "camoufox-${toAttr v}";
        value = mkCamoufox v toolData.versions.${v};
      }) versions;
      latestPin = toolData.versions.${toolData.latest};
    in
    builtins.listToAttrs versionedPkgs
    // {
      camoufox = mkCamoufox toolData.latest latestPin;
    };

  buildCamoufoxPlaywrightCli =
    let
      toolData = lock.tools.camoufox;
      versions = builtins.attrNames toolData.versions;
      versionedPkgs = map (v: {
        name = "camoufox-cli-${toAttr v}";
        value = mkCamoufoxPlaywrightCli (mkCamoufox v toolData.versions.${v});
      }) versions;
      latestPin = toolData.versions.${toolData.latest};
    in
    builtins.listToAttrs versionedPkgs
    // {
      camoufox-cli = mkCamoufoxPlaywrightCli (mkCamoufox toolData.latest latestPin);
    };

  camoufoxOutputs =
    if
      (builtins.hasAttr "camoufox" lock.tools)
      && (builtins.hasAttr "camoufox-browsers" lock.tools)
      && pkgs.stdenv.hostPlatform.system == "aarch64-linux"
    then
      {
        inherit (buildCamoufox) camoufox;
        inherit (buildCamoufoxBrowsers) camoufox-browsers;
        inherit (buildCamoufoxPlaywrightCli) camoufox-cli;
      }
      // builtins.removeAttrs buildCamoufox [ "camoufox" ]
      // builtins.removeAttrs buildCamoufoxBrowsers [ "camoufox-browsers" ]
      // builtins.removeAttrs buildCamoufoxPlaywrightCli [ "camoufox-cli" ]
    else
      { };
in
cliOutputs
// mcpOutputs
// nodeOutputs
// dotnetOutputs
// pythonOutputs
// camoufoxOutputs
// {
  default = cliOutputs."playwright-cli";
}
