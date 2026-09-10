# PyPI playwright wrapper. Bundles the JS driver and browsers.
# Replaces the bundled Node binary with nixpkgs nodejs.
{
  lib,
  stdenv,
  python3Packages,
  fetchFromGitHub,
  fetchzip,
  autoPatchelfHook,
  makeWrapper,
  nodejs,
}:
{
  version,
  driverVersion ? version,
  srcHash,
  driverUrls ? null,
  driverHashes,
  browsers,
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-python: unsupported system ${system}";
  driverSourceIsWheel = driverUrls != null;
  driverZipName =
    {
      x86_64-linux = "linux";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "mac-arm64";
    }
    .${system} or throwSystem;

  # JS driver layout matching _driver.py:
  #   ./node           -- replaced with nixpkgs nodejs
  #   ./package/cli.js -- core entry point
  driver = stdenv.mkDerivation {
    pname = "playwright-driver";
    version = driverVersion;

    src = fetchzip {
      url =
        if driverSourceIsWheel then
          driverUrls.${system} or throwSystem
        else
          "https://cdn.playwright.dev/builds/driver/${lib.optionalString (lib.hasInfix "-" driverVersion) "next/"}playwright-${driverVersion}-${driverZipName}.zip";
      extension = if driverSourceIsWheel then "zip" else null;
      stripRoot = false;
      hash = driverHashes.${system} or throwSystem;
    };

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      ${if driverSourceIsWheel then "cp -R playwright/driver/. $out/" else "cp -R . $out/"}
      # Replace bundled node with nixpkgs nodejs.
      rm -f $out/node
      ln -s ${lib.getExe nodejs} $out/node
      runHook postInstall
    '';
  };
in
python3Packages.buildPythonPackage {
  pname = "playwright";
  inherit version;
  pyproject = true;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-python";
    rev = "v${version}";
    hash = srcHash;
  };

  postPatch = ''
    # Driver is already fetched; stub out CDN download and relax deps.
    sed -i -E \
      -e 's/, "auditwheel==[0-9]+(\.[0-9]+)*"//g' \
      -e 's/"setuptools-scm==[0-9]+(\.[0-9]+)*"/"setuptools-scm"/g' \
      -e 's/"setuptools==[0-9]+(\.[0-9]+)*"/"setuptools"/g' \
      -e 's/"wheel==[0-9]+(\.[0-9]+)*"/"wheel"/g' \
      pyproject.toml
    rm setup.py
  '';

  nativeBuildInputs = [ makeWrapper ];

  build-system = with python3Packages; [
    setuptools
    setuptools-scm
  ];

  pythonRelaxDeps = [
    "greenlet"
    "pyee"
  ];

  dependencies = with python3Packages; [
    greenlet
    pyee
  ];

  doCheck = false;
  pythonImportsCheck = [ "playwright" ];

  postInstall = ''
    # Embed driver into package for _driver.py.
    mkdir -p $out/${python3Packages.python.sitePackages}/playwright/driver
    cp -R ${driver}/. $out/${python3Packages.python.sitePackages}/playwright/driver/

    # Set env vars in __init__.py so library consumers use bundled browsers.
    init=$out/${python3Packages.python.sitePackages}/playwright/__init__.py
    {
      echo "import os as _nix_os"
      echo "_nix_os.environ.setdefault('PLAYWRIGHT_BROWSERS_PATH', '${browsers}')"
      echo "_nix_os.environ.setdefault('PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD', '1')"
      echo "del _nix_os"
      cat $init
    } > $init.new && mv $init.new $init
  '';

  postFixup = ''
    mv $out/bin/playwright $out/bin/.playwright-real
    cat > $out/bin/playwright <<WRAPPER
    #!/bin/sh
    export PLAYWRIGHT_BROWSERS_PATH="${browsers}"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

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

    exec "$out/bin/.playwright-real" "\$@"
    WRAPPER
    chmod +x $out/bin/playwright
  '';

  passthru = {
    inherit driver;
  };

  meta = {
    description = "playwright ${version} (PyPI) bundled with revision-matched browsers";
    homepage = "https://github.com/microsoft/playwright-python";
    mainProgram = "playwright";
  };
}
