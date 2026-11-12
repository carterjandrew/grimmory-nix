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

      # Build an aarch64 guest entirely on x86_64. Unlike using
      # legacyPackages.aarch64-linux directly, this does not require binfmt or
      # a remote ARM builder for the small derivations that assemble NixOS.
      aarch64CrossPkgs = import nixpkgs {
        localSystem = "x86_64-linux";
        crossSystem = nixpkgs.lib.systems.examples.aarch64-multiplatform;
      };

      mkNixosTest =
        {
          hostPkgs,
          guestPkgs,
          guestSystem,
          package,
          name,
        }:
        hostPkgs.testers.runNixOSTest {
          inherit name;

          # runNixOSTest normally makes the guest match the test driver. Making
          # this explicit lets an x86_64 driver boot an aarch64 guest under
          # qemu-system-aarch64 for the manual cross-architecture test target.
          node.pkgs = hostPkgs.lib.mkForce guestPkgs;

          nodes.machine = {
            imports = [ self.nixosModules.grimmory ];
            services.grimmory = {
              enable = true;
              inherit package;
              port = 7777;
              database.passwordFile = guestPkgs.writeText "grimmory-test-database-password" "test-password";
            };
          };

          testScript = ''
            expected_arch = "${if guestSystem == "aarch64-linux" then "aarch64" else "x86_64"}"
          ''
          + builtins.readFile ./nixos/test.py;
        };
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
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          aarch64-vm-test = mkNixosTest {
            name = "grimmory-aarch64";
            hostPkgs = pkgs;
            guestPkgs = aarch64CrossPkgs;
            guestSystem = "aarch64-linux";
            package = aarch64CrossPkgs.callPackage ./package.nix { };
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          package = self.packages.${system}.grimmory;
          nixos-module = mkNixosTest {
            name = "grimmory";
            hostPkgs = pkgs;
            guestPkgs = pkgs;
            guestSystem = system;
            package = self.packages.${system}.grimmory;
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
