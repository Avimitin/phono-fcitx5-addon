{
  description = "Phono Pinyin and Shuangpin input methods for Fcitx5";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      # The addon and source-built core are tested on Linux x86-64.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      coreSdk = pkgs.callPackage ./nix/core-sdk.nix { };
      addon = pkgs.callPackage ./nix/package.nix { phono-core-sdk = coreSdk; };
      model = pkgs.callPackage ./nix/model.nix { };
    in
    {
      packages.${system} = {
        default = addon;
        phono-fcitx5-addon = addon;
        phono-core-sdk = coreSdk;
        phono-model = model;
      };

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ addon ];
        packages = with pkgs; [
          clang-tools
          gdb
          nixfmt
        ];
        PHONO_SDK_PREFIX = "${coreSdk}";
        inherit (addon) FCITX_DATA_DIRS FCITX_ADDON_DIRS;
      };

      checks.${system}.default = addon;
      formatter.${system} = pkgs.nixfmt-tree;
    };
}
