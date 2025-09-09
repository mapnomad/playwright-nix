# @playwright/cli wrapper bundled with browsers.
{
  buildNpmPackage,
  fetchFromGitHub,
}:
{
  version,
  packageSha,
  srcHash,
  npmDepsHash,
  browsers,
}:
buildNpmPackage {
  pname = "playwright-cli";
  inherit version;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-cli";
    rev = packageSha;
    hash = srcHash;
  };

  inherit npmDepsHash;
  dontNpmBuild = true;

  # Inject --browser chromium to fix NixOS failure (defaults to hardcoded chrome), unless passed by user.
  postFixup = ''
    mv $out/bin/playwright-cli $out/bin/.playwright-cli-real
    cat > $out/bin/playwright-cli <<WRAPPER
    #!/bin/sh
    export PLAYWRIGHT_BROWSERS_PATH="${browsers}"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    for _arg in "\$@"; do
      case "\$_arg" in
        --browser|--browser=*)
          exec "$out/bin/.playwright-cli-real" "\$@"
          ;;
      esac
    done
    exec "$out/bin/.playwright-cli-real" --browser chromium "\$@"
    WRAPPER
    chmod +x $out/bin/playwright-cli
  '';

  passthru = {
    inherit browsers;
  };

  meta = {
    description = "playwright-cli ${version} bundled with revision-matched browsers";
    homepage = "https://github.com/microsoft/playwright-cli";
    mainProgram = "playwright-cli";
  };
}
