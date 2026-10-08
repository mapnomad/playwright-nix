# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/chromium-headless-shell.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` uses an attrset keyed by system instead of a hardcoded string.
#   - Supports x86_64-linux, aarch64-linux, and aarch64-darwin.
{
  lib,
  stdenv,
  fetchzip,
  autoPatchelfHook,
  patchelfUnstable,
  alsa-lib,
  at-spi2-atk,
  expat,
  glib,
  libXcomposite,
  libXdamage,
  libXfixes,
  libXrandr,
  libgbm,
  libgcc,
  libxkbcommon,
  nspr,
  nss,
}:
{
  revision,
  hashes,
  urls,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/chromium-headless-shell: unsupported system ${system}";

  src = fetchzip {
    # scripts/sync.ts records the archive URL per system in packages.lock.
    url = urls.${system} or throwSystem;
    stripRoot = false;
    hash = hashes.${system} or throwSystem;
  };
in
stdenv.mkDerivation {
  name = "playwright-chromium-headless-shell-${revision}";

  inherit src;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    patchelfUnstable
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    at-spi2-atk
    expat
    glib
    libXcomposite
    libXdamage
    libXfixes
    libXrandr
    libgbm
    libgcc.lib
    libxkbcommon
    nspr
    nss
  ];

  # Layout notes (playwright-core/src/server/registry/index.ts):
  #   linux-x64:   chrome-headless-shell-linux64/chrome-headless-shell
  #   linux-arm64: chrome-headless-shell-linux-arm64/chrome-headless-shell (CFT, revision >= 1243)
  #                chrome-linux/headless_shell (legacy build, revision < 1243)
  #   mac-arm64:   chrome-headless-shell-mac-arm64/chrome-headless-shell
  # The zips already contain the expected top-level directory (stripRoot=false),
  # so they can be copied directly.
  buildPhase = ''
    cp -R . $out
  '';
}
