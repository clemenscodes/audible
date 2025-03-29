{
  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };
  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    devShells = {
      ${system} = {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.audible-cli
            pkgs.aaxtomp3
          ];
          shellHook = ''
            export AUDIBLE_CONFIG_DIR="$(pwd)/.audible"
            mkdir -p $AUDIBLE_CONFIG_DIR
            touch $AUDIBLE_CONFIG_DIR/config.toml
          '';
        };
      };
    };
  };
}
