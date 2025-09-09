# Architecture

Playwright tools (CLI, MCP, Node, .NET, Python) release separately and pin conflicting `playwright-core` versions. Nixpkgs provides only one browser set. This flake builds a dedicated browser set for each tool to exactly match its core version.

## Browser Alignment

Playwright expects browsers in `PLAYWRIGHT_BROWSERS_PATH/${name}-${revision}`. If the revisions do not match, Playwright downloads the missing browsers at runtime.

Example divergence:

| Consumer          | Latest | Core Pin                   | chromium | webkit |
| ----------------- | ------ | -------------------------- | -------- | ------ |
| `@playwright/cli` | 0.1.5  | 1.60.0-alpha-1775237291000 | 1219     | 2276   |
| `@playwright/mcp` | 0.0.70 | 1.60.0-alpha-1774999321000 | 1217     | 2272   |

## Structure

```
flake.nix                           # flake-parts definition
packages/default.nix                # builds packages from packages.lock
packages/*.nix                      # package derivations
packages.lock                       # tool/core/browser version mapping
lib/mkBrowsers.nix                  # builds browser linkFarm
scripts/sync.ts                     # updates packages.lock
scripts/push-browsers.ts            # pushes closures to Cachix
```

## Packages Lockfile

`packages.lock` maps tools to core versions, and core versions to browser revisions.

```json
{
  "tools": {
    "cli": { "versions": { "0.1.19": { "core": "1.63.0-alpha-..." } } }
  },
  "coreSets": { "1.63.0-alpha-...": { "chromium": "1243" } },
  "browsers": {
    "chromium": { "1243": { "hashes": { "x86_64-linux": "..." } } }
  }
}
```

## Packages

Derivations in `packages/` set `PLAYWRIGHT_BROWSERS_PATH` to prevent runtime downloads:

- **`playwright-cli`**: `buildNpmPackage` wrapper.
- **`playwright-mcp`**: `buildNpmPackage` wrapper.
- **`playwright-node`**: `stdenvNoCC` installing `playwright` and `playwright-core` tarballs.
- **`playwright-dotnet`**: `stdenvNoCC` extracting the NuGet `.nupkg`.
- **`playwright-python`**: `buildPythonPackage` embedding the JS driver from PyPI.

## Resolution

- **Node.js**: Resolves GitHub SHA or fetches npm tarballs, reading `browsers.json`.
- **.NET**: Extracts `browsers.json` directly from the `.nupkg`.
- **Python**: Reads `driver_version` from `setup.py` (or `DRIVER_VERSION`) to find the core hash.
