# Packages the Node.js `playwright` and `playwright-core` tarballs directly without npm.
{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
  nodejs,
}:
{
  version,
  packageHash,
  coreHash,
  browsers,
  ...
}:
let
  playwrightPackage = fetchzip {
    url = "https://registry.npmjs.org/playwright/-/playwright-${version}.tgz";
    hash = packageHash;
  };

  playwrightCorePackage = fetchzip {
    url = "https://registry.npmjs.org/playwright-core/-/playwright-core-${version}.tgz";
    hash = coreHash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "playwright-node";
  inherit version;
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/playwright"
    mkdir -p "$out/lib/node_modules/playwright-core"
    cp -R ${playwrightPackage}/. "$out/lib/node_modules/playwright/"
    cp -R ${playwrightCorePackage}/. "$out/lib/node_modules/playwright-core/"

    for entry in index.js index.mjs; do
      tmp="$out/lib/node_modules/playwright/$entry.nix"
      cat > "$tmp" <<EOF
    if (!process.env.PLAYWRIGHT_BROWSERS_PATH) process.env.PLAYWRIGHT_BROWSERS_PATH = '${browsers}';
    if (!process.env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD) process.env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = '1';
    EOF
      cat "$out/lib/node_modules/playwright/$entry" >> "$tmp"
      mv "$tmp" "$out/lib/node_modules/playwright/$entry"
    done

    mkdir -p "$out/bin"
    cat > "$out/bin/playwright-node" <<WRAPPER
    #!/bin/sh
    export PLAYWRIGHT_BROWSERS_PATH="${browsers}"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export NODE_PATH="$out/lib/node_modules''${NODE_PATH:+:\$NODE_PATH}"

    command=
    wants_help=0

    for arg in "\$@"; do
      case "\$arg" in
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

    if [ "\$command" = "install" ] || [ "\$command" = "install-deps" ] || [ "\$command" = "install-browser" ] || [ "\$command" = "install-browsers" ]; then
      if [ "\$wants_help" = 0 ]; then
        echo "Browsers are pre-bundled in the Nix store (\$PLAYWRIGHT_BROWSERS_PATH). Runtime browser installation is disabled."
        exit 0
      fi
    fi

    exec "${lib.getExe nodejs}" "$out/lib/node_modules/playwright/cli.js" "\$@"
    WRAPPER
    chmod +x "$out/bin/playwright-node"

    mkdir -p "$out/nix-support"
    cat > "$out/nix-support/setup-hook" <<EOF
    addToSearchPath NODE_PATH "$out/lib/node_modules"
    EOF

    runHook postInstall
  '';

  meta = {
    description = "playwright ${version} (Node.js) bundled with revision-matched browsers";
    homepage = "https://github.com/microsoft/playwright";
    mainProgram = "playwright-node";
  };
}
