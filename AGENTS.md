# AI Agent Instructions

This file guides AI agents in this repository.

## Context

This flake packages `@playwright/cli`, `@playwright/mcp`, Node.js `playwright`, .NET `Microsoft.Playwright`, and PyPI `playwright`. It pre-bundles the exact browser revisions each tool needs, preventing runtime downloads, extra environment variables, and package manager installs.

## Documentation

- **[README.md](./README.md)**: Quickstart.
- **[docs/architecture.md](./docs/architecture.md)**: Version resolution, lockfile schema, and repository layout.
- **[docs/maintenance.md](./docs/maintenance.md)**: CI sync and caching.
- **[docs/nixos.md](./docs/nixos.md)**: Platform workarounds.

## Rules

1. **No runtime downloads**: Fetch browsers at build time using `packages.lock`.
2. **Avoid npm**: Extract sub-packages or files using `fetchzip` or GitHub tarballs.
3. **Respect `packages.lock`**: Only `scripts/sync.ts` mutates it.
