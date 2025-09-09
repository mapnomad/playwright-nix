# mkBrowsers :: { browsers } -> derivation
#
# Creates a linkFarm matching the `${name}-${revision}` layout expected by
# PLAYWRIGHT_BROWSERS_PATH (e.g., `chromium_headless_shell-<rev>`).
#
# Input shape (omitted entries are skipped):
#
#   {
#     chromium                = { revision = "1219"; browserVersion = "147.0.7727.49"; hash = "sha256-..."; };
#     chromium-headless-shell = { revision = "1219"; browserVersion = "147.0.7727.49"; hash = "sha256-..."; };
#     firefox                 = { revision = "1511"; hash = "sha256-..."; };
#     webkit                  = { revision = "2276"; hash = "sha256-..."; };
#     ffmpeg                  = { revision = "1011"; hash = "sha256-..."; };
#   }
{
  lib,
  callPackage,
  linkFarm,
  makeFontsConf,
  freefont_ttf,
}:
browsers:
let
  # Playwright normalizes dashes to underscores for directories.
  dirPrefix = name: builtins.replaceStrings [ "-" ] [ "_" ] name;

  # Minimal fontconfig suppresses Chromium warnings.
  fontconfig_file = makeFontsConf {
    fontDirectories = [ freefont_ttf ];
  };

  # Only chromium accepts fontconfig_file.
  fetcherOverrides = {
    chromium = { inherit fontconfig_file; };
  };

  mkEntry =
    name: spec:
    let
      fetcher = callPackage (./browsers + "/${name}.nix") (fetcherOverrides.${name} or { });
      drv = fetcher spec;
    in
    {
      name = "${dirPrefix name}-${spec.revision}";
      path = drv;
    };

  entries = lib.mapAttrsToList mkEntry browsers;
in
linkFarm "playwright-browsers" entries
