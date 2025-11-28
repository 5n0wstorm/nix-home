# ============================================================================
# ELROND - WSL Development Environment
# ============================================================================

{ config, lib, pkgs, nixos-wsl, ... }:

{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    # include NixOS-WSL modules
    nixos-wsl.nixosModules.default
    # include sops-nix for secrets management
    sops-nix.nixosModules.sops
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "elrond";
  users.motd = "WSL Development Environment";

  # ============================================================================
  # WSL CONFIGURATION
  # ============================================================================

  wsl.enable = true;
  wsl.defaultUser = "dominik";

  # ============================================================================
  # SECRETS MANAGEMENT (SOPS-NIX)
  # ============================================================================

  # SOPS configuration for encrypted secrets
  sops = {
    # Default secrets location
    defaultSopsFile = ../../secrets/elrond.yaml;

    # Age key for decryption (this should match your .sops.yaml)
    age.keyFile = "/var/lib/sops-nix/key.txt";

    # SSH key secrets
    secrets = {
      "ssh_key" = {
        path = "/home/dominik/.ssh/id_ed25519";
        owner = "dominik";
        group = "users";
        mode = "0600";
      };
      "ssh_key_pub" = {
        path = "/home/dominik/.ssh/id_ed25519.pub";
        owner = "dominik";
        group = "users";
        mode = "0644";
      };
    };
  };

  # ============================================================================
  # SSH CONFIGURATION
  # ============================================================================

  # SSH client configuration for git
  programs.ssh = {
    startAgent = true;
    agentTimeout = "1h";

    extraConfig = ''
      Host github.com
        IdentityFile /home/dominik/.ssh/id_ed25519
        User git
    '';
  };

  # Ensure SSH directory exists
  systemd.tmpfiles.rules = [
    "d /home/dominik/.ssh 0700 dominik users"
  ];

  # ============================================================================
  # DEVELOPMENT PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    git
    colmena
  ];

  # ============================================================================
  # NIX SETTINGS
  # ============================================================================

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ============================================================================
  # SYSTEM
  # ============================================================================

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}