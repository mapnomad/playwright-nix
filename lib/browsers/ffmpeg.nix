# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/ffmpeg.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` uses an attrset keyed by system instead of a hardcoded string.
#   - Supports x86_64-linux, aarch64-linux, and aarch64-darwin.
{
  stdenv,
  fetchzip,
}:
{
  hashes,
  urls,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/ffmpeg: unsupported system ${system}";
in
fetchzip {
  url = urls.${system} or throwSystem;
  stripRoot = false;
  hash = hashes.${system} or throwSystem;
}
