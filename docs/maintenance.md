# Maintenance

Update manually with `nix run .#sync`, test with `nix flake check --no-build`, and commit.

## Sync Script

`scripts/sync.ts` handles the sync.

```sh
nix run .#sync                  # All tools
nix run .#sync -- cli           # Specific tool
nix run .#sync -- cli 0.1.19    # Specific version
```

Steps:

1. Query registry (npm, PyPI, NuGet) for `targetVersion` or latest.
2. Exit if the version is already in `packages.lock`.
3. Resolve git SHA or release URLs.
4. Read `browsers.json` from matching `playwright-core`.
5. Prefetch browser closures across supported systems.
6. Update `packages.lock`.

## CI

`.github/workflows/sync.yml` runs daily and commits directly to `main`.

1. **`sync-latest`**: Runs `nix run .#sync` and commits. Builds/pushes `x86_64-linux` closures.
2. **`cache-arm`** & **`cache-darwin`**: Push `aarch64-linux` and `aarch64-darwin` closures.
3. Pushes the commit to `main`.
