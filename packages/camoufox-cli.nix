{
  lib,
  runCommand,
  writeText,
}:
{
  camoufox,
  playwrightCli,
}:

let
  browser = camoufox.browser or (throw "camoufox-cli: camoufox package is missing browser passthru");
  browserExe = lib.getExe browser;
  config = writeText "camoufox-cli-config.json" (
    builtins.toJSON {
      browser = {
        browserName = "firefox";
        launchOptions = {
          executablePath = browserExe;
        };
      };
    }
  );
in
runCommand "camoufox-cli-${camoufox.version}"
  {
    passthru = {
      inherit
        browser
        camoufox
        config
        playwrightCli
        ;
    };

    meta = {
      description = "Playwright CLI wrapper configured to launch the Nix-packaged Camoufox browser";
      homepage = "https://github.com/daijro/camoufox";
      mainProgram = "camoufox-cli";
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share/camoufox-cli"
    ln -s ${config} "$out/share/camoufox-cli/config.json"

    cat > "$out/bin/camoufox-cli" <<'WRAPPER'
    #!/bin/sh
    set -eu

    has_config=0
    has_browser=0
    wants_help=0
    command=

    for arg in "$@"; do
      case "$arg" in
        --config|--config=*)
          has_config=1
          ;;
        --browser|--browser=*)
          has_browser=1
          ;;
        --help|-h|--version)
          wants_help=1
          ;;
        -*)
          ;;
        *)
          if [ -z "$command" ]; then
            command="$arg"
          fi
          ;;
      esac
    done

    export PLAYWRIGHT_BROWSERS_PATH="${playwrightCli.browsers}"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

    if [ "$command" = "install-browser" ] || [ "$command" = "install-browsers" ]; then
      if [ "$wants_help" = 0 ]; then
        echo "Browsers are pre-bundled in the Nix store ($PLAYWRIGHT_BROWSERS_PATH). Runtime browser installation is disabled."
        exit 0
      fi
    fi

    if [ "$command" = open ] && [ "$has_config" = 0 ] && [ "$has_browser" = 0 ] && [ "$wants_help" = 0 ]; then
      exec "${playwrightCli}/bin/.playwright-cli-real" --config "${config}" "$@"
    fi

    exec "${playwrightCli}/bin/.playwright-cli-real" "$@"
    WRAPPER
    chmod +x "$out/bin/camoufox-cli"
  ''
