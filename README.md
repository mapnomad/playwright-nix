# Playwright for Nix

[![sync](https://github.com/mapnomad/playwright-nix/actions/workflows/sync.yml/badge.svg)](https://github.com/mapnomad/playwright-nix/actions/workflows/sync.yml)
[![playwright-cli](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmapnomad%2Fplaywright-nix%2Fmain%2Fpackages.lock&query=%24.tools.cli.latest&label=playwright-cli&color=blue&logo=npm)](https://www.npmjs.com/package/@playwright/cli)
[![playwright-mcp](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmapnomad%2Fplaywright-nix%2Fmain%2Fpackages.lock&query=%24.tools.mcp.latest&label=playwright-mcp&color=blue&logo=npm)](https://www.npmjs.com/package/@playwright/mcp)
[![playwright-node](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmapnomad%2Fplaywright-nix%2Fmain%2Fpackages.lock&query=%24.tools.node.latest&label=playwright-node&color=339933&logo=nodedotjs&logoColor=white)](https://www.npmjs.com/package/playwright)
[![playwright-dotnet](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmapnomad%2Fplaywright-nix%2Fmain%2Fpackages.lock&query=%24.tools.dotnet.latest&label=playwright-dotnet&color=512BD4&logo=nuget&logoColor=white)](https://www.nuget.org/packages/Microsoft.Playwright)
[![playwright-python](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmapnomad%2Fplaywright-nix%2Fmain%2Fpackages.lock&query=%24.tools.python.latest&label=playwright-python&color=3776AB&logo=python&logoColor=white)](https://pypi.org/project/playwright/)
[![camoufox](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmapnomad%2Fplaywright-nix%2Fmain%2Fpackages.lock&query=%24.tools.camoufox.latest&label=camoufox&color=3776AB&logo=python&logoColor=white)](https://pypi.org/project/camoufox/)
[![camoufox-browsers](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmapnomad%2Fplaywright-nix%2Fmain%2Fpackages.lock&query=%24.tools%5B%22camoufox-browsers%22%5D.latest&label=camoufox-browsers&color=ff7139&logo=firefoxbrowser&logoColor=white)](https://github.com/daijro/camoufox)

This flake packages `@playwright/cli`, `@playwright/mcp`, Node.js `playwright`, .NET `Microsoft.Playwright`, and PyPI `playwright`. It pre-bundles the exact browser revisions each tool needs, preventing runtime downloads and manual path configuration.

It also packages PyPI `camoufox` and the Camoufox browser.

Systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`. Camoufox supports only `aarch64-linux`.

See [packages.lock](./packages.lock) for versions.

## Usage

```nix
inputs.playwright.url = "github:mapnomad/playwright-nix";
```

Version attributes use underscores (`0.1.6` becomes `0_1_6`).

- `playwright-cli` (latest)
- `playwright-cli-0_1_6` (pinned)
- `playwright-cli-browsers` (browser closure for derivations)
- `camoufox-cli` (Camoufox Playwright CLI wrapper)

### Shell

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    playwright.url = "github:mapnomad/playwright-nix";
  };

  outputs = { self, nixpkgs, playwright }:
    let system = "x86_64-linux"; in {
      devShells.${system}.default =
        nixpkgs.legacyPackages.${system}.mkShell {
          packages = [
            playwright.packages.${system}.playwright-cli
            playwright.packages.${system}.playwright-mcp-0_0_70
            playwright.packages.${system}.playwright-node
            playwright.packages.${system}.playwright-dotnet
            playwright.packages.${system}.playwright-python-1_58_0
          ];
        };
    };
}
```

```sh
$ nix develop
$ playwright-cli open --browser=chromium https://example.com
$ playwright-node --version
$ playwright-dotnet --version
$ playwright --version
```

### Run CLI

```sh
nix run github:mapnomad/playwright-nix#playwright-cli-0_1_5 -- open https://example.com
```

### List versions

```sh
nix flake show github:mapnomad/playwright-nix
```

## Cachix

Browser closures are cached at `https://playwright.cachix.org` and enabled by default.

## Documentation

- [Architecture](docs/architecture.md): Version resolution and repository layout.
- [Maintenance](docs/maintenance.md): CI sync and caching.
- [NixOS Notes](docs/nixos.md): Platform workarounds.
