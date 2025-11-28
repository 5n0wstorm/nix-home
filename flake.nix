{
  # ============================================================================
  # FLAKE INPUTS - External dependencies and packages
  # ============================================================================

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
  };

  # ============================================================================
  # FLAKE OUTPUTS - What this flake provides
  # ============================================================================

  outputs =
    { nixpkgs, colmena, ... }:
    let
      # Import host definitions from single source of truth
      hosts = import ./hosts.nix;

      # For scaling up your homelab, you'd likely want automated host generation:
      # mkHost = name: hostConfig: {
      #   deployment = {
      #     targetHost = hostConfig.ip;
      #     targetUser = hostConfig.user;
      #     tags = hostConfig.tags;
      #   };
      #   imports = [ ./hosts/${name}/configuration.nix ];
      # };
      # hostConfigs = builtins.mapAttrs mkHost hosts;
    in
    {
      # ==========================================================================
      # DEVELOPMENT SHELL - Local development environment
      # ==========================================================================

      devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
        buildInputs = [ colmena.packages.x86_64-linux.colmena ];
      };

      # ==========================================================================
      # COLMENA HIVE - Fleet deployment configuration
      # ==========================================================================

      colmenaHive = colmena.lib.makeHive {
        # ========================================================================
        # GLOBAL CONFIGURATION - Settings applied to all hosts
        # ========================================================================

        meta = {
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ ];
          };
        };

        # ========================================================================
        # HOST DEFINITIONS - Individual server configurations
        # ========================================================================

        galadriel = {
          deployment = {
            targetHost = hosts.galadriel.ip;
            targetUser = hosts.galadriel.user;
            tags = hosts.galadriel.tags;
          };

          imports = [
            ./hosts/galadriel/configuration.nix
          ];
        };

        frodo = {
          deployment = {
            targetHost = hosts.frodo.ip;
            targetUser = hosts.frodo.user;
            tags = hosts.frodo.tags;
          };

          imports = [
            ./hosts/frodo/configuration.nix
          ];
        };

        sam = {
          deployment = {
            targetHost = hosts.sam.ip;
            targetUser = hosts.sam.user;
            tags = hosts.sam.tags;
          };

          imports = [
            ./hosts/sam/configuration.nix
          ];
        };
      };
    };
}
