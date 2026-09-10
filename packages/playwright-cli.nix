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

  # 1. Patch installSkills in coreBundle.js: files copied from Nix store are read-only (0444/0555).
  #    Ensure existing destination files are made writable before cp (preventing EACCES on overwrite)
  #    and make newly installed skills files writable (0644/0755) so users/agents can edit them.
  # 2. Inject --browser chromium to fix NixOS failure (defaults to hardcoded chrome), unless passed by user.
  postFixup = ''
    node -e '
      const fs = require("fs");
      const path = require("path");

      function patchFile(file) {
        if (!fs.existsSync(file)) return;
        let content = fs.readFileSync(file, "utf8");
        const pattern = /await\s+([\w.]+)\.cp\(sourceDir,\s*destDir,\s*\{\s*recursive:\s*true\s*\}\);/;
        if (!pattern.test(content)) return;
        const replacement = `await (async () => {
          const _fs = require("fs");
          const _path = require("path");
          async function _makeWritable(p) {
            try {
              const stat = await _fs.promises.stat(p);
              if (stat.isDirectory()) {
                await _fs.promises.chmod(p, 0o755).catch(() => {});
                const entries = await _fs.promises.readdir(p);
                for (const entry of entries) {
                  await _makeWritable(_path.join(p, entry));
                }
              } else {
                await _fs.promises.chmod(p, 0o644).catch(() => {});
              }
            } catch {}
          }
          await _makeWritable(destDir);
          await _fs.promises.cp(sourceDir, destDir, { recursive: true });
          await _makeWritable(destDir);
        })()`;
        content = content.replace(pattern, replacement);
        fs.writeFileSync(file, content, "utf8");
      }

      function findAndPatch(dir) {
        if (!fs.existsSync(dir)) return;
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          const full = path.join(dir, entry.name);
          if (entry.isDirectory()) {
            findAndPatch(full);
          } else if (entry.name === "coreBundle.js") {
            patchFile(full);
          }
        }
      }

      findAndPatch(process.argv[1]);
    ' "$out"

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

    if [ "\$command" = install-browser ] || [ "\$command" = install-browsers ]; then
      if [ "\$wants_help" = 0 ]; then
        echo "Browsers are pre-bundled in the Nix store (\$PLAYWRIGHT_BROWSERS_PATH). Runtime browser installation is disabled."
        exit 0
      fi
    fi

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
