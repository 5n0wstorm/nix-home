{
  # ============================================================================
  # FLAKE INPUTS - External dependencies and packages
  # ============================================================================

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    sops-nix.url = "github:Mic92/sops-nix";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    gallery-dl-src = {
      url = "git+ssh://gitea@192.168.2.10/Dominik/gallery-dl.git?ref=master";
      flake = false;
    };
  };

  # ============================================================================
  # FLAKE OUTPUTS - What this flake provides
  # ============================================================================

  outputs = {
    nixpkgs,
    colmena,
    nixos-wsl,
    sops-nix,
    disko,
    gallery-dl-src,
    ...
  }: let
    # Import host definitions from single source of truth
    hosts = import ./hosts.nix;

    # =========================================================================
    # OVERLAYS - Custom package overrides
    # =========================================================================

    overlays = [
      (final: prev: let
        galleryDlCustom = prev.gallery-dl.overrideAttrs (oldAttrs: {
          src = gallery-dl-src;
          version = "custom-${gallery-dl-src.shortRev or "unknown"}";

          # Some forks/patchsets include the telegram extractor raising
          # `gallery_dl.exception.MissingDependencyError`, but the exception class
          # isn't present. Patch it in at build time for robustness.
          postPatch =
            (oldAttrs.postPatch or "")
            + ''
                            if [ -f gallery_dl/exception.py ] && ! grep -q "MissingDependencyError" gallery_dl/exception.py; then
                              cat >> gallery_dl/exception.py <<'EOF'


              class MissingDependencyError(ImportError):
                  """Raised when an optional runtime dependency is missing."""
              EOF
                            fi
            '';

          # Telegram extractor needs telethon available in gallery-dl's Python env.
          propagatedBuildInputs =
            (oldAttrs.propagatedBuildInputs or [])
            ++ [
              prev.python3Packages.telethon
              prev.python3Packages.psycopg
            ];
        });
      in {
        gallery-dl-custom = galleryDlCustom;
        # Backwards-compatible name (now just the patched build, no extra wrapping needed).
        gallery-dl-custom-fixed = galleryDlCustom;
      })
    ];
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
        {nixpkgs.overlays = overlays;}
        ./hosts/elrond/configuration.nix
        sops-nix.nixosModules.sops
      ];
    };

    nixosConfigurations.galadriel = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {nixpkgs.overlays = overlays;}
        ./hosts/galadriel/configuration.nix
        ./hosts/galadriel/disko.nix
        disko.nixosModules.disko
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
          overlays = overlays;
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
          ./hosts/galadriel/disko.nix
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
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

      elrond = {name, ...}: {
        deployment = {
          targetUser = hosts.elrond.user;
          tags = hosts.elrond.tags;
        };

        _module.args.nixos-wsl = nixos-wsl;

        imports = [
          ./hosts/elrond/configuration.nix
          sops-nix.nixosModules.sops
        ];
      };
    };
  };
}
