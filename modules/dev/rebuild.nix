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
#   setup-age-key                          # Interactive age key setup for sops-nix
#   setup-age-key                          # Interactive age key setup for sops-nix
#
# OPTIONS:
#   --force, -f      Force rebuild even without changes
#   --attached, -a   Run in foreground (default: detached via systemd)
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
# The rebuild script automatically:
# - Handles SSH setup for git operations
# - Checks for age key before proceeding
# - Manages SSH agent and key loading
# ============================================================================
  let
    cfg = config.fleet.dev.rebuild;

    ageKeySetupScript = pkgs.writeShellScriptBin "setup-age-key" ''
      #!/usr/bin/env bash

      # Script to interactively set up age key for sops-nix
      set -e

      KEY_FILE="/home/dominik/.config/sops/age/keys.txt"

      if [ -f "$KEY_FILE" ]; then
        echo "Age key already exists at $KEY_FILE"
        echo "Remove it first if you want to replace it: rm $KEY_FILE"
        exit 0
      fi

      echo "Setting up age key for sops-nix secrets decryption..."
      echo ""
      echo "This key is required to decrypt secrets stored in the repository."
      echo "Get your age private key from: ~/.config/sops/age/keys.txt on your host machine"
      echo ""
      echo "The key should look like:"
      echo "AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
      echo ""

      # Create directory if it doesn't exist
      mkdir -p /home/dominik/.config/sops/age

      # Read age key interactively
      echo -n "Enter your age private key: "
      read -r AGE_KEY

      if [ -z "$AGE_KEY" ]; then
        echo "No key provided. Aborting."
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
      } > "$KEY_FILE"

      chmod 600 "$KEY_FILE"

      echo ""
      echo "✅ Age key saved successfully to $KEY_FILE"
      echo "You can now run: rebuild -f"
    '';

    rebuildScript = pkgs.writeShellScriptBin "rebuild-system" ''
        #!/usr/bin/env bash

        # A rebuild script that commits on a successful build
        # Usage: rebuild-system [hostname] [--force|-f] [--hostname|-h <host>]
        set -e

        # Parse command line arguments
        FORCE_REBUILD=false
        ATTACHED=false
        HOSTNAME=$(hostname)

        while [[ $# -gt 0 ]]; do
            case $1 in
                --force|-f)
                    FORCE_REBUILD=true
                    shift
                    ;;
                --attached|-a)
                    ATTACHED=true
                    shift
                    ;;
                --hostname|-h)
                    HOSTNAME="$2"
                    shift 2
                    ;;
                --help)
                    echo "Usage: rebuild-system [hostname] [options]"
                    echo "Options:"
                    echo "  --force, -f        Force rebuild even without changes"
                    echo "  --attached, -a     Run in foreground (default: detached systemd unit)"
                    echo "  --hostname, -h     Specify hostname (default: current hostname)"
                    echo "  --help             Show this help message"
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

        # Age key is required before rebuild (sops-nix secrets)
        if [ ! -f "/home/dominik/.config/sops/age/keys.txt" ]; then
            echo "Age key not found at /home/dominik/.config/sops/age/keys.txt"
            echo "This is required for decrypting secrets with sops-nix."
            echo ""
            echo "Run: setup-age-key"
            echo "Or copy your age key to ~/.config/sops/age/keys.txt"
            exit 1
        fi

        # State file to track last deployed commit per host
        STATE_DIR="/var/lib/nixos-rebuild"
        STATE_FILE="$STATE_DIR/$HOSTNAME-last-deployed"
        CURRENT_COMMIT=$(git rev-parse HEAD)

        # Check for changes (unless force rebuild is enabled)
        if [ "$FORCE_REBUILD" = false ]; then
            NEEDS_REBUILD=false

            # Check 1: Uncommitted local changes in config files
            if ! git diff --quiet --exit-code -- "hosts/$HOSTNAME" "modules" "flake.nix" "flake.lock" "hosts.nix" 2>/dev/null; then
                echo "Uncommitted local changes detected."
                NEEDS_REBUILD=true
            fi

            # Check 2: Staged but uncommitted changes
            if ! git diff --cached --quiet --exit-code -- "hosts/$HOSTNAME" "modules" "flake.nix" "flake.lock" "hosts.nix" 2>/dev/null; then
                echo "Staged changes detected."
                NEEDS_REBUILD=true
            fi

            # Check 3: Current commit differs from last deployed commit
            if [ -f "$STATE_FILE" ]; then
                LAST_DEPLOYED=$(cat "$STATE_FILE")
                if [ "$CURRENT_COMMIT" != "$LAST_DEPLOYED" ]; then
                    echo "New commits detected since last deploy (last: ''${LAST_DEPLOYED:0:8}, current: ''${CURRENT_COMMIT:0:8})."
                    NEEDS_REBUILD=true
                fi
            else
                echo "No previous deploy recorded for $HOSTNAME - first deploy or state was cleared."
                NEEDS_REBUILD=true
            fi

            if [ "$NEEDS_REBUILD" = false ]; then
                echo "No changes detected in configuration files, exiting."
                echo "Use --force or -f to rebuild anyway."
                exit 0
            fi
        fi

        if [ "$FORCE_REBUILD" = true ]; then
            echo "Force rebuilding - skipping change analysis"
        else
            echo "Analysing changes..."
            git diff --name-only -- "hosts/$HOSTNAME" "modules" "flake.nix" "flake.lock" "hosts.nix" 2>/dev/null || true
            if [ -f "$STATE_FILE" ]; then
                LAST_DEPLOYED=$(cat "$STATE_FILE")
                if [ "$CURRENT_COMMIT" != "$LAST_DEPLOYED" ]; then
                    echo "Commits since last deploy:"
                    git log --oneline "$LAST_DEPLOYED".."$CURRENT_COMMIT" -- "hosts/$HOSTNAME" "modules" "flake.nix" "flake.lock" "hosts.nix" 2>/dev/null || true
                fi
            fi
        fi

        # Detached rebuild survives SSH loss while network units restart.
        if [ -z "''${NIXOS_REBUILD_CHILD:-}" ] && [ "$ATTACHED" = false ]; then
            UNIT="nixos-rebuild-''${HOSTNAME}"
            LOG_FILE="''${STATE_DIR}/last-rebuild.log"
            if systemctl is-active "''${UNIT}.service" &>/dev/null; then
                echo "Rebuild already running on $HOSTNAME."
                echo "  journalctl -fu ''${UNIT}"
                echo "  sudo tail -f ''${LOG_FILE}"
                exit 1
            fi
            sudo mkdir -p "$STATE_DIR"
            FORCE_FLAG=""
            if [ "$FORCE_REBUILD" = true ]; then
                FORCE_FLAG="--force"
            fi
            echo "Starting detached rebuild (continues if SSH drops during activation)..."
            sudo systemd-run \
                --unit="$UNIT" \
                --collect \
                --working-directory="$REPO_ROOT" \
                --property=User="$(id -un)" \
                --property=Group="$(id -gn)" \
                --setenv=HOME="$HOME" \
                --setenv=NIXOS_REBUILD_CHILD=1 \
                bash -c "cd '$REPO_ROOT' && exec \"$(command -v rebuild-system)\" --attached $FORCE_FLAG $HOSTNAME >> '$LOG_FILE' 2>&1"
            echo "Detached rebuild started."
            echo "  journalctl -fu ''${UNIT}"
            echo "  sudo tail -f ''${LOG_FILE}"
            exit 0
        fi

        echo "Rebuilding NixOS..."
        ${pkgs.alejandra}/bin/alejandra --quiet hosts/ modules/ flake.nix hosts.nix 2>/dev/null || true

        nh os switch . -H "$HOSTNAME"

        echo "NixOS Rebuild Completed!"

        sudo mkdir -p "$STATE_DIR"
        echo "$CURRENT_COMMIT" | sudo tee "$STATE_FILE" > /dev/null
        echo "Recorded deploy commit: ''${CURRENT_COMMIT:0:8}"

        current=$(nixos-rebuild list-generations --json | ${pkgs.jq}/bin/jq -r '.[] | select(.current == true) | .generation')

        git add hosts/ modules/ flake.nix flake.lock hosts.nix
        if ! git diff --cached --quiet; then
            git commit -m "rebuild($HOSTNAME): generation $current"
            echo "Changes committed successfully!"
        else
            echo "No formatting changes to commit."
        fi

        # SSH for git push (works in detached systemd-run without agent)
        export GIT_SSH_COMMAND="ssh -i /home/dominik/.ssh/id_ed25519 -o IdentitiesOnly=yes"

        if [ -z "''${SSH_AUTH_SOCK:-}" ] || [ ! -S "''${SSH_AUTH_SOCK}" ]; then
            if [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ -S "''${XDG_RUNTIME_DIR}/ssh-agent" ]; then
                export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR}/ssh-agent"
            else
                eval "$(ssh-agent -s)" > /dev/null
            fi
        fi

        if ! ssh-add -l 2>/dev/null | grep -q "id_ed25519"; then
            ssh-add /home/dominik/.ssh/id_ed25519 2>/dev/null || true
        fi

        push_remote="origin"
        push_url="$(git remote get-url "$push_remote" 2>/dev/null || true)"
        if [[ "$push_url" == https://github.com/* ]]; then
            push_remote="git@github.com:''${push_url#https://github.com/}"
        fi

        echo "Syncing with remote before push..."
        git pull --rebase "$push_remote" main

        echo "Pushing changes to remote repository..."
        if git push "$push_remote" main; then
            echo "Changes pushed successfully!"
        else
            echo "Error: Failed to push changes to main."
            echo "Try: ssh-add /home/dominik/.ssh/id_ed25519 && git push git@github.com:5n0wstorm/nix-home.git main"
            exit 1
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
        ageKeySetupScript
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
        setup-age = "setup-age-key";
      };
    };
  }
