# ============================================================================
# DISKO CONFIGURATION - Declarative disk partitioning for galadriel
# ============================================================================
#
# NVMe disk with UEFI + LVM layout:
#   /dev/nvme0n1p1 - EFI System Partition (512MB, vfat, /boot)
#   /dev/nvme0n1p2 - LVM PV (remaining space)
#     └─ vg_galadriel
#        ├─ lv_swap (8GB)
#        └─ lv_root (remaining - ext4)
#
# Verified: UEFI boot via `ls /sys/firmware/efi`
# Disk: /dev/nvme0n1 (476.9GB)
# Network: enp3s0f1
#
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            # EFI System Partition (ESP) for UEFI boot with systemd-boot
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["defaults" "umask=0077"];
              };
            };
            # LVM physical volume - all remaining space
            root = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "vg_galadriel";
              };
            };
          };
        };
      };
    };

    lvm_vg = {
      vg_galadriel = {
        type = "lvm_vg";
        lvs = {
          # Swap logical volume
          swap = {
            size = "8G";
            content = {
              type = "swap";
            };
          };
          # Root logical volume - all remaining space
          root = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = ["defaults" "noatime"];
            };
          };
        };
      };
    };
  };
}
