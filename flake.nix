{
  description = "Elixir implementation of the Maty actor language";
  inputs = { nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/*"; };
  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f { pkgs = import nixpkgs { inherit system; }; });
    in {
      devShells = forEachSupportedSystem ({ pkgs }:
        let
          # One BEAM package set, so Erlang, Elixir and tooling all agree on OTP
          beamPkgs = pkgs.beam.packages.erlang_27;
          elixir = beamPkgs.elixir_1_19;
        in {
          default = pkgs.mkShell {
            packages = [
              beamPkgs.erlang
              elixir
              (beamPkgs.elixir-ls.override { inherit elixir; })
              pkgs.nixpkgs-fmt
            ];

            # Keep Mix/Hex state inside the project rather than in ~/.mix
            shellHook = ''
              export MIX_HOME="$PWD/.nix-mix"
              export HEX_HOME="$PWD/.nix-hex"
              export ERL_AFLAGS="-kernel shell_history enabled"
            '';
          };
        });
    };
}
