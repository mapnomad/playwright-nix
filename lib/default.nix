{
  ...
}:
{
  # Build a linkFarm derivation of browser revisions that match playwright-core's expectations.
  # Usage: (lib.mkBrowsers pkgs) pin.browsers
  mkBrowsers = pkgs: pkgs.callPackage ./mkBrowsers.nix { };
}
