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

    has_browser=0
    wants_help=0
    command=
    skip_next=0

    for arg in "\$@"; do
      if [ "\$skip_next" = 1 ]; then
        skip_next=0
        continue
      fi
      case "\$arg" in
        -s|--session)
          skip_next=1
          ;;
        --browser)
          has_browser=1
          skip_next=1
          ;;
        --browser=*)
          has_browser=1
          ;;
        --help|-h|--version)
          wants_help=1
          ;;
        -*)
          ;;
        *)
          if [ -z "\$command" ]; then
            command="\$arg"
          fi
          ;;
      esac
    done

    if [ "\$command" = open ] && [ "\$has_browser" = 0 ] && [ "\$wants_help" = 0 ]; then
      exec "$out/bin/.playwright-cli-real" --browser chromium "\$@"
    fi

    exec "$out/bin/.playwright-cli-real" "\$@"
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
