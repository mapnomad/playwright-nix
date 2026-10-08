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
  revision,
  hashes,
  urls,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/chromium: unsupported system ${system}";

  # scripts/sync.ts records the archive URL per system in packages.lock.
  url = urls.${system} or throwSystem;

  src = fetchzip {
    stripRoot = !stdenv.hostPlatform.isDarwin;
    inherit url;
    hash = hashes.${system} or throwSystem;
  };

  # Playwright expects the archive's root directory inside the browser dir, and
  # launches `<root>/chrome`. See playwright-core/src/server/registry/index.ts:
  #   EXECUTABLE_PATHS.chromium = {
  #     'linux-x64': ['chrome-linux64', 'chrome'],
  #     'linux-arm64': ['chrome-linux-arm64', 'chrome'],  // CFT builds, revision >= 1243
  #   }
  # The legacy linux-arm64 archive (`chromium-linux-arm64.zip`, revision < 1243)
  # has the root `chrome-linux`; CFT archives are named after their root.
  archive = baseNameOf url;
  layoutDir =
    if archive == "chromium-linux-arm64.zip" then "chrome-linux" else lib.removeSuffix ".zip" archive;
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
