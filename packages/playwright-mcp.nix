# @playwright/mcp wrapper bundled with browsers.
#
# Workspace symlink fallback supports v0.0.65..v0.0.70 structure.
{
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
}:
{
  version,
  packageSha,
  srcHash,
  npmDepsHash,
  browsers,
}:
buildNpmPackage {
  pname = "playwright-mcp";
  inherit version;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-mcp";
    rev = packageSha;
    hash = srcHash;
  };

  inherit npmDepsHash;
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    if [ ! -e $out/bin/playwright-mcp ]; then
      mkdir -p $out/bin
      ln -s $out/lib/node_modules/playwright-mcp-internal/packages/playwright-mcp/cli.js \
        $out/bin/playwright-mcp
    fi
  '';

  postFixup = ''
    wrapProgram $out/bin/playwright-mcp \
      --set PLAYWRIGHT_BROWSERS_PATH ${browsers} \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1
  '';

  meta = {
    description = "playwright-mcp ${version} (MCP server) bundled with revision-matched browsers";
    homepage = "https://github.com/microsoft/playwright-mcp";
    mainProgram = "playwright-mcp";
  };
}
