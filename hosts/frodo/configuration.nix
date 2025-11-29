{
  config,
  pkgs,
  ...
}: let
  hosts = import ../../hosts.nix;
in {
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/dev/gitea.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "frodo";

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.dev.gitea = {
    enable = true;
    domain = hosts.frodo.ip;
    appName = "Fleet Git Repository";
  };

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking = {
    useDHCP = false;
    interfaces.enp1s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = hosts.frodo.ip;
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "192.168.2.1";
    nameservers = ["8.8.8.8" "1.1.1.1"];
  };

  networking.firewall.allowedTCPPorts = [];

  # ============================================================================
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  system.stateVersion = "25.05";
}
