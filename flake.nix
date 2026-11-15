{
  description = "Development and OS image build tools for desktop-os";

  # Keep build-tool updates independent of future Home Manager input updates.
  inputs.nixpkgs-tools.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs-tools, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs-tools { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          actionlint
          bashInteractive
          coreutils
          git
          jq
          just
          nixfmt
          podman
          shellcheck
          skopeo
        ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
