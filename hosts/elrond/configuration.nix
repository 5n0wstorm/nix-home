# ============================================================================
# ELROND - WSL Development Environment
# ============================================================================

{ config, lib, pkgs, ... }:

{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    # include NixOS-WSL modules
    <nixos-wsl/modules>
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