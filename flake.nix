{
  description = "Nix package and NixOS module for Grimmory";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          grimmory = pkgs.callPackage ./package.nix { };
        in
        {
          inherit grimmory;
          default = grimmory;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          package = self.packages.${system}.grimmory;
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          nixos-module = pkgs.testers.runNixOSTest {
            name = "grimmory";
            nodes.machine = {
              imports = [ self.nixosModules.grimmory ];
              services.grimmory = {
                enable = true;
                package = self.packages.${system}.grimmory;
                port = 7777;
                database.passwordFile = pkgs.writeText "grimmory-test-database-password" "test-password";
              };
            };
            testScript = builtins.readFile ./nixos/test.py;
          };
        }
      );

      nixosModules = {
        grimmory = import ./nixos/module.nix;
        default = self.nixosModules.grimmory;
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
