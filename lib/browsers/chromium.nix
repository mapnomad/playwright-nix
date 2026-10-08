# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/chromium.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` uses an attrset keyed by system instead of a hardcoded string.
#   - Supports x86_64-linux, aarch64-linux, and aarch64-darwin.
{
  stdenv,
  lib,
  fetchzip,
  makeWrapper,
  fontconfig_file,
  autoPatchelfHook,
  patchelf,
  alsa-lib,
  at-spi2-atk,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gobject-introspection,
  libGL,
  libgbm,
  libgcc,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pciutils,
  systemd,
  vulkan-loader,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxcb,
}:
{
  browserVersion,
  revision,
  hashes,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/chromium: unsupported system ${system}";

  # Upstream moved linux-arm64 to Chrome for Testing builds and layout at
  # revision 1243. Revision 1243 is pinned to the legacy playwright archive,
  # because the CFT archive was not yet in use when it was locked.
  # Keep in sync with scripts/sync.ts.
  rev = lib.toInt revision;
  cftArm64Source = rev >= 1244;
  cftArm64Layout = rev >= 1243;

  # The CDN URL structure depends on the platform:
  #   x86_64-linux uses Google's chrome-for-testing (CFT) path, keyed by browserVersion.
  #   aarch64-linux uses CFT, or playwright's own builds keyed by revision before 1244.
  #   aarch64-darwin uses CFT with the macOS arm64 archive layout.
  src = fetchzip {
    stripRoot = !stdenv.hostPlatform.isDarwin;
    url =
      {
        x86_64-linux = "https://cdn.playwright.dev/builds/cft/${browserVersion}/linux64/chrome-linux64.zip";
        aarch64-linux =
          if cftArm64Source then
            "https://cdn.playwright.dev/builds/cft/${browserVersion}/linux-arm64/chrome-linux-arm64.zip"
          else
            "https://cdn.playwright.dev/builds/chromium/${revision}/chromium-linux-arm64.zip";
        aarch64-darwin = "https://cdn.playwright.dev/builds/cft/${browserVersion}/mac-arm64/chrome-mac-arm64.zip";
      }
      .${system} or throwSystem;
    hash = hashes.${system} or throwSystem;
  };

  # Playwright expects this directory name inside the browser dir, and launches this binary.
  # See playwright-core/src/server/registry/index.ts:
  #   EXECUTABLE_PATHS.chromium = {
  #     'linux-x64': ['chrome-linux64', 'chrome'],
  #     'linux-arm64': ['chrome-linux-arm64', 'chrome'],  // ['chrome-linux', 'chrome'] before 1243
  #   }
  layoutDir =
    {
      x86_64-linux = "chrome-linux64";
      aarch64-linux = if cftArm64Layout then "chrome-linux-arm64" else "chrome-linux";
      aarch64-darwin = "chrome-mac-arm64";
    }
    .${system} or throwSystem;
in
stdenv.mkDerivation {
  name = "playwright-chromium-${revision}";

  inherit src;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    patchelf
    makeWrapper
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    at-spi2-atk
    atk
    cairo
    cups
    dbus
    expat
    glib
    gobject-introspection
    libgbm
    libgcc
    libxkbcommon
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    systemd
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxcb
  ];

  installPhase = ''
    runHook preInstall

    if [ "${toString stdenv.hostPlatform.isDarwin}" = 1 ]; then
      mkdir -p "$out"
      cp -R . "$out/"
    else
      mkdir -p "$out/${layoutDir}"
      cp -R . "$out/${layoutDir}"

      wrapProgram "$out/${layoutDir}/chrome" \
        --set-default SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt \
        --set-default FONTCONFIG_FILE ${fontconfig_file}
    fi

    runHook postInstall
  '';

  appendRunpaths = lib.optionalString stdenv.hostPlatform.isLinux (
    lib.makeLibraryPath [
      libGL
      vulkan-loader
      pciutils
    ]
  );

  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    # Replace the bundled vulkan-loader with the one in RPATH.
    if [ -e "$out/${layoutDir}/libvulkan.so.1" ]; then
      rm "$out/${layoutDir}/libvulkan.so.1"
      ln -s -t "$out/${layoutDir}" "${lib.getLib vulkan-loader}/lib/libvulkan.so.1"
    fi
  '';
}
