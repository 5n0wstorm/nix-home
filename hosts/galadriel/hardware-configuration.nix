# ============================================================================
# HARDWARE CONFIGURATION - galadriel (bare metal server)
# ============================================================================
#
# This file contains hardware-specific settings for a bare metal server.
# Disk configuration is handled by disko.nix - do not define fileSystems here.
#
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # ============================================================================
  # KERNEL MODULES
  # ============================================================================

  boot.initrd.availableKernelModules = [
    # Storage controllers
    "nvme"
    "ahci"
    "sd_mod"
    "sr_mod"
    # USB (for keyboard/recovery)
    "xhci_pci"
    "ehci_pci"
    "usbhid"
    "usb_storage"
    # LVM support
    "dm_mod"
    "dm_snapshot"
    "dm_mirror"
  ];

  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"]; # or kvm-amd if AMD CPU
  boot.extraModulePackages = [];

  # ============================================================================
  # HARDWARE SETTINGS
  # ============================================================================

  # Enable firmware updates
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # CPU microcode updates (uncomment the appropriate one)
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # ============================================================================
  # NETWORKING
  # ============================================================================

  networking.useDHCP = lib.mkDefault true;
}
