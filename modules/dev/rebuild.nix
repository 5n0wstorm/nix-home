{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.dev.rebuild;

  rebuildScript = pkgs.writeShellScriptBin "rebuild-system" ''
    #!/usr/bin/env bash

    # A rebuild script that commits on a successful build
    set -e

    # Default hostname if not provided
    HOSTNAME=''${1:-$(hostname)}

    echo "Hostname: $HOSTNAME"

    # Find the git repository root (where flake.nix is located)
    REPO_ROOT="$(pwd)"
    while [ "$REPO_ROOT" != "/" ] && [ ! -f "$REPO_ROOT/flake.nix" ]; do
        REPO_ROOT="$(dirname "$REPO_ROOT")"
    done

    if [ ! -f "$REPO_ROOT/flake.nix" ]; then
        echo "Error: Could not find flake.nix in current directory or parent directories"
        echo "Current directory: $(pwd)"
        echo "Make sure you're running this from your nix-home git repository or a subdirectory"
        exit 1
    fi

    cd "$REPO_ROOT"
    echo "Repository root: $(pwd)"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        echo "Current directory: $(pwd)"
        echo "Make sure you're running this from your nix-home git repository"
        exit 1
    fi

    # Early return if no changes were detected
    if git diff --quiet --exit-code -- "hosts/$HOSTNAME" "modules" "flake.nix" "flake.lock" "hosts.nix"; then
        echo "No changes detected in configuration files, exiting."
        exit 0
    fi

    echo "Analysing changes..."
    git diff --name-only -- "hosts/$HOSTNAME" "modules" "flake.nix" "flake.lock" "hosts.nix"

    echo "Rebuilding NixOS..."
    # Autoformat nix files
    ${pkgs.alejandra}/bin/alejandra --quiet hosts/ modules/ flake.nix hosts.nix 2>/dev/null || true

    # Rebuild system
    sudo nixos-rebuild switch --flake ".#$HOSTNAME" --show-trace

    echo "NixOS Rebuild Completed!"

    # Get current generation info
    current=$(sudo nixos-rebuild list-generations --json | ${pkgs.jq}/bin/jq -r '.[] | select(.current == true) | .generation')

    # Commit changes
    git add hosts/ modules/ flake.nix flake.lock hosts.nix
    git commit -m "rebuild($HOSTNAME): generation $current"

    echo "Changes committed successfully!"
  '';
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.dev.rebuild = {
    enable = mkEnableOption "NixOS rebuild script with auto-commit functionality";

    package = mkOption {
      type = types.package;
      default = rebuildScript;
      description = "The rebuild script package";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # INSTALL REBUILD SCRIPT
    # --------------------------------------------------------------------------

    environment.systemPackages = [
      cfg.package
      pkgs.alejandra  # Nix formatter
      pkgs.jq         # JSON processor for generation info
    ];

    # --------------------------------------------------------------------------
    # SHELL ALIASES
    # --------------------------------------------------------------------------

    environment.shellAliases = {
      rebuild = "rebuild-system";
    };
  };
}

