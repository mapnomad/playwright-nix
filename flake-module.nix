{
  inputs,
  lib,
  ...
}:
let
  playwrightLib = import ./lib {
    lib = inputs.nixpkgs.lib or lib;
    inherit inputs;
  };
in
{
  flake = {
    lib = playwrightLib;
    flakeModules.default = ./flake-module.nix;
    flakeModule = ./flake-module.nix;
  };

  perSystem =
    {
      ...
    }:
    {
      _module.args.playwrightLib = playwrightLib;
      _module.args.playwright = playwrightLib;
    };
}
