{
  # ============================================================================
  # FLAKE INPUTS - External dependencies and packages
  # ============================================================================

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    sops-nix.url = "github:Mic92/sops-nix";

    # Pinned nixpkgs for SABnzbd 4.5.3 (Nov 2025)
    # Change the commit hash to get a different version:
    # - 4.5.5: ee09932cedcef15aaf476f9343d1dea2cb77e261
    # - 4.5.3: 12c1f0253aa9a54fdf8ec8aecaafada64a111e24
    # - 4.4.0: 7e4a1594489d41bf8e16046b28e14a0e264c9baa
    # - 4.3.3: 5a48e3c2e435e95103d56590188cfed7b70e108c
    nixpkgs-sabnzbd.url = "github:NixOS/nixpkgs/12c1f0253aa9a54fdf8ec8aecaafada64a111e24";
  };

  # ============================================================================
  # FLAKE OUTPUTS - What this flake provides
  # ============================================================================

  outputs = {
    nixpkgs,
    nixpkgs-sabnzbd,
    colmena,
    nixos-wsl,
    sops-nix,
    ...
  }: let
    # Import host definitions from single source of truth
    hosts = import ./hosts.nix;

    # Pinned packages for specific versions
    pinnedPkgs = import nixpkgs-sabnzbd {
      system = "x86_64-linux";
    };
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
  in {
    # ==========================================================================
    # DEVELOPMENT SHELL - Local development environment
    # ==========================================================================

    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = [colmena.packages.x86_64-linux.colmena];
    };

    # ==========================================================================
    # NIXOS CONFIGURATIONS - Direct system configurations for nixos-rebuild
    # ==========================================================================

    nixosConfigurations.elrond = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit nixos-wsl;
      };
      modules = [
        ./hosts/elrond/configuration.nix
        sops-nix.nixosModules.sops
      ];
    };

    nixosConfigurations.galadriel = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit pinnedPkgs;
      };
      modules = [
        ./hosts/galadriel/configuration.nix
        sops-nix.nixosModules.sops
      ];
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
          overlays = [];
        };
      };

      # ========================================================================
      # HOST DEFINITIONS - Individual server configurations
      # ========================================================================

      galadriel = {name, ...}: {
        deployment = {
          targetHost = hosts.galadriel.ip;
          targetUser = hosts.galadriel.user;
          tags = hosts.galadriel.tags;
        };

        _module.args.pinnedPkgs = pinnedPkgs;

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

      elrond = {
        deployment = {
          targetUser = hosts.elrond.user;
          tags = hosts.elrond.tags;
        };

        imports = [
          ./hosts/elrond/configuration.nix
        ];
      };
    };
  };
}
