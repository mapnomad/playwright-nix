{
  description = "Playwright with browsers.";

  nixConfig = {
    extra-substituters = [ "https://playwright.cachix.org" ];
    extra-trusted-public-keys = [
      "playwright.cachix.org-1:diVESWxleUZBGe96EWyUaUiQDuhqXQZgHx+bCb3Jh3o="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt.url = "github:numtide/treefmt-nix";
    treefmt.inputs.nixpkgs.follows = "nixpkgs";

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake-module.nix
        inputs.treefmt.flakeModule
        inputs.git-hooks.flakeModule
      ];

      # Linux plus Apple Silicon macOS. Darwin browser archives are currently
      # pinned to the GitHub Actions macOS 15 arm64 runner image.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          pkgs,
          playwrightLib,
          ...
        }:
        let
          syncApp = pkgs.writeShellApplication {
            name = "sync";
            runtimeInputs = with pkgs; [
              bun
              nix
              prefetch-npm-deps
              curl
              gnutar
              unzip
              git
            ];
            text = ''
              exec bun "${./scripts/sync.ts}" "$@"
            '';
          };
          pushBrowsersApp = pkgs.writeShellApplication {
            name = "push-browsers";
            runtimeInputs = with pkgs; [
              bun
              nix
              curl
              jq
              cachix
            ];
            text = ''
              exec bun "${./scripts/push-browsers.ts}" "$@"
            '';
          };
        in
        {
          packages = import ./packages {
            inherit pkgs;
            lib = playwrightLib;
          };

          checks = {
            playwright-cli-skills =
              pkgs.runCommand "test-playwright-cli-skills"
                {
                  nativeBuildInputs = [ config.packages.playwright-cli ];
                }
                ''
                  export HOME=$TMPDIR
                  playwright-cli --help > /dev/null
                  playwright-cli list > /dev/null
                  playwright-cli install --skills=agents
                  test -d .agents/skills/playwright-cli
                  test -f .agents/skills/playwright-cli/SKILL.md
                  touch $out
                '';
          };

          apps = {
            sync = {
              type = "app";
              program = pkgs.lib.getExe syncApp;
              meta.description = "Synchronize Playwright packages and browser closures in packages.lock";
            };
            push-browsers = {
              type = "app";
              program = pkgs.lib.getExe pushBrowsersApp;
              meta.description = "Build, push, and pin latest browser closures to Cachix";
            };
            default = config.apps.sync;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              deadnix.enable = true;
              shellcheck.enable = true;
              shfmt.enable = true;
              prettier.enable = true;
            };
            settings.formatter.shellcheck.options = [
              "-s"
              "bash"
              "-e"
              "SC1091"
            ];
          };

          pre-commit.settings = {
            package = pkgs.prek;
            hooks = {
              treefmt = {
                enable = true;
                package = config.treefmt.build.wrapper;
              };
              check-json.enable = true;
              check-merge-conflicts.enable = true;
              check-added-large-files.enable = true;
              end-of-file-fixer.enable = true;
              trim-trailing-whitespace = {
                enable = true;
                args = [ "--markdown-linebreak-ext=md" ];
              };
            };
          };

          devShells.default = pkgs.mkShell {
            name = "playwright-shell";
            packages = [
              config.pre-commit.settings.package
            ]
            ++ config.pre-commit.settings.enabledPackages;
            shellHook = config.pre-commit.installationScript;
          };
        };
    };
}
