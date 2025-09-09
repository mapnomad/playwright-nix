# NixOS & Platform Notes

- **Chrome**: `--browser=chrome` fails on NixOS (hardcoded `/opt/google/chrome/chrome`). Use `--browser=chromium`.
- **WebKit**: Newer WebKit revisions need `libhyphen.so.0` and `libbacktrace.so.0` (included in `buildInputs`).
- **aarch64**: `playwright-python` uses the nixpkgs `nodejs` instead of the bundled binary for NixOS compatibility.
- **Darwin**: `aarch64-darwin` maps to the `webkit-mac-15-arm64` artifact.
