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
# SSH KEY SETUP:
# 1. SSH Agent Forwarding (current): SSH keys are stored on your host machine
#    and forwarded to WSL. This is the most secure option for development.
#
# 2. sops-nix (recommended for production): Encrypt SSH keys and store them
#    in the repository. Add to flake inputs and configure secrets.
#
# 3. GitHub Deploy Keys: Use repository-specific deploy keys instead of
#    personal SSH keys.
#
# To use SSH agent forwarding:
# - Ensure your SSH key is added to ssh-agent on your host
# - The WSL configuration enables SSH agent forwarding automatically
# ============================================================================

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
      pkgs.sops       # Secrets encryption/decryption
      pkgs.age        # Age encryption tool
    ];

    # --------------------------------------------------------------------------
    # SHELL ALIASES
    # --------------------------------------------------------------------------

    environment.shellAliases = {
      rebuild = "rebuild-system";
    };
  };
}

