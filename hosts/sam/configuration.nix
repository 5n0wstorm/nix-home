{
  config,
  pkgs,
  ...
}: {
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/apps/freshrss.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "sam";
  users.motd = "sam is calling";

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.apps.freshrss = {
    enable = true;
    port = 8080;
    timezone = "America/New_York";
  };

  virtualisation.oci-containers.containers = {};

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking = {
    useDHCP = false;
    interfaces.enp1s0 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = hosts.sam.ip;
        prefixLength = 24;
      }];
    };
    defaultGateway = "192.168.2.1";
    nameservers = ["8.8.8.8" "1.1.1.1"];
  };

  networking.firewall.allowedTCPPorts = [];

  # ============================================================================
  # VIRTUALIZATION
  # ============================================================================

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
  virtualisation.oci-containers.backend = "podman";

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
