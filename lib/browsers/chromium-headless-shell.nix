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
  browserVersion,
  revision,
  hashes,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/chromium-headless-shell: unsupported system ${system}";

  # Upstream moved linux-arm64 to Chrome for Testing builds and layout at
  # revision 1243. Revision 1243 is pinned to the legacy playwright archive,
  # because the CFT archive was not yet in use when it was locked.
  # Keep in sync with scripts/sync.ts.
  rev = lib.toInt revision;
  cftArm64Source = rev >= 1244;
  legacyArm64WithCftLayout = system == "aarch64-linux" && rev >= 1243 && !cftArm64Source;

  src = fetchzip {
    url =
      {
        x86_64-linux = "https://cdn.playwright.dev/builds/cft/${browserVersion}/linux64/chrome-headless-shell-linux64.zip";
        aarch64-linux =
          if cftArm64Source then
            "https://cdn.playwright.dev/builds/cft/${browserVersion}/linux-arm64/chrome-headless-shell-linux-arm64.zip"
          else
            "https://cdn.playwright.dev/builds/chromium/${revision}/chromium-headless-shell-linux-arm64.zip";
        aarch64-darwin = "https://cdn.playwright.dev/builds/cft/${browserVersion}/mac-arm64/chrome-headless-shell-mac-arm64.zip";
      }
      .${system} or throwSystem;
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
  #   linux-arm64: chrome-headless-shell-linux-arm64/chrome-headless-shell
  #                (chrome-linux/headless_shell before 1243)
  #   mac-arm64:   chrome-headless-shell-mac-arm64/chrome-headless-shell
  # The zips already contain the expected top-level directory (stripRoot=false),
  # so they can be copied directly. The legacy archive of revision 1243 is
  # moved into the CFT layout.
  buildPhase = ''
    cp -R . $out
  ''
  + lib.optionalString legacyArm64WithCftLayout ''
    mv $out/chrome-linux $out/chrome-headless-shell-linux-arm64
    ln -s headless_shell $out/chrome-headless-shell-linux-arm64/chrome-headless-shell
  '';
}
