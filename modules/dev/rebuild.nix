{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
# ============================================================================
# REBUILD MODULE - Enhanced NixOS rebuild script with git integration
#
# USAGE:
#   rebuild-system [hostname] [options]
#
# OPTIONS:
#   --force, -f      Force rebuild even without changes
#   --hostname, -h   Specify hostname (default: current hostname)
#   --help           Show help message
#
# EXAMPLES:
#   rebuild-system                    # Rebuild current host if changes detected
#   rebuild-system --force           # Force rebuild current host
#   rebuild-system galadriel         # Rebuild galadriel if changes detected
#   rebuild-system galadriel --force # Force rebuild galadriel
#
# SSH KEY SETUP OPTIONS:
# 1. SSH Agent Forwarding: SSH keys stored on host machine, forwarded to WSL
#    - Most secure for development
#    - Requires: ssh-add on host, SSH agent forwarding in WSL
#
# 2. sops-nix (implemented): Encrypted SSH keys stored in repository
#    - Production-ready, keys encrypted with age
#    - Setup: Generate age key, configure .sops.yaml, encrypt secrets
#    - Currently configured for elrond host
#
# 3. GitHub Deploy Keys: Repository-specific keys instead of personal keys
#    - Best for CI/CD, limits access scope
#
# The rebuild script automatically handles SSH setup for git operations.
# ============================================================================
  let
    cfg = config.fleet.dev.rebuild;

    rebuildScript = pkgs.writeShellScriptBin "rebuild-system" ''
      #!/usr/bin/env bash

      # A rebuild script that commits on a successful build
      # Usage: rebuild-system [hostname] [--force|-f] [--hostname|-h <host>]
      set -e

      # Parse command line arguments
      FORCE_REBUILD=false
      HOSTNAME=$(hostname)

      while [[ $# -gt 0 ]]; do
          case $1 in
              --force|-f)
                  FORCE_REBUILD=true
                  shift
                  ;;
              --hostname|-h)
                  HOSTNAME="$2"
                  shift 2
                  ;;
              --help)
                  echo "Usage: rebuild-system [hostname] [options]"
                  echo "Options:"
                  echo "  --force, -f      Force rebuild even without changes"
                  echo "  --hostname, -h   Specify hostname (default: current hostname)"
                  echo "  --help           Show this help message"
                  exit 0
                  ;;
              *)
                  HOSTNAME="$1"
                  shift
                  ;;
          esac
      done

      echo "Hostname: $HOSTNAME"
      if [ "$FORCE_REBUILD" = true ]; then
          echo "Force rebuild enabled - will rebuild even without changes"
      fi

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

      # Check for changes (unless force rebuild is enabled)
      if [ "$FORCE_REBUILD" = false ]; then
          if git diff --quiet --exit-code -- "hosts/$HOSTNAME" "modules" "flake.nix" "flake.lock" "hosts.nix"; then
              echo "No changes detected in configuration files, exiting."
              echo "Use --force or -f to rebuild anyway."
              exit 0
          fi
      fi

      if [ "$FORCE_REBUILD" = true ]; then
          echo "Force rebuilding - skipping change analysis"
      else
          echo "Analysing changes..."
          git diff --name-only -- "hosts/$HOSTNAME" "modules" "flake.nix" "flake.lock" "hosts.nix"
      fi

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

    # Check if age key exists for sops-nix
    if [ ! -f "/var/lib/sops-nix/key.txt" ]; then
        echo "Age key not found at /var/lib/sops-nix/key.txt"
        echo "This is required for decrypting secrets with sops-nix."
        echo ""
        echo "Please provide your age private key (from ~/.config/sops/age/keys.txt on your host):"
        echo "The key should look like: AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
        echo ""

        # Create directory if it doesn't exist
        sudo mkdir -p /var/lib/sops-nix

        # Read age key interactively
        echo -n "Enter your age private key: "
        read -r AGE_KEY

        if [ -z "$AGE_KEY" ]; then
            echo "No key provided. Skipping secrets setup."
            echo "You can set up the age key later and run rebuild again."
            exit 1
        fi

        # Get the comment line if it exists
        echo -n "Enter the comment line (optional, press Enter to skip): "
        read -r AGE_COMMENT

        # Create the key file
        {
            if [ -n "$AGE_COMMENT" ]; then
                echo "$AGE_COMMENT"
            fi
            echo "$AGE_KEY"
        } | sudo tee /var/lib/sops-nix/key.txt > /dev/null

        sudo chmod 600 /var/lib/sops-nix/key.txt
        sudo chown root:root /var/lib/sops-nix/key.txt

        echo "Age key saved successfully!"
        echo ""
    fi

    # Set up SSH for git operations
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
    if [ -z "$SSH_AUTH_SOCK" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
        # Start SSH agent if not running
        eval "$(ssh-agent -s)" > /dev/null
        export SSH_AUTH_SOCK="$SSH_AGENT_PID"
    fi

    # Add SSH key to agent if not already added
    if ! ssh-add -l | grep -q "id_ed25519"; then
        ssh-add /home/dominik/.ssh/id_ed25519 2>/dev/null || true
    fi

      # Push to remote repository
      echo "Pushing changes to remote repository..."
      if git push origin main 2>/dev/null; then
          echo "Changes pushed successfully!"
      else
          echo "Warning: Failed to push changes. SSH key may not be properly configured."
          echo "Try: ssh-add /home/dominik/.ssh/id_ed25519 && git push origin main"
      fi
    '';
  in {
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
        pkgs.alejandra # Nix formatter
        pkgs.jq # JSON processor for generation info
        pkgs.sops # Secrets encryption/decryption
        pkgs.age # Age encryption tool
      ];

      # --------------------------------------------------------------------------
      # SHELL ALIASES
      # --------------------------------------------------------------------------

      environment.shellAliases = {
        rebuild = "rebuild-system";
      };
    };
  }
