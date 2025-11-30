# ============================================================================
# DISKO CONFIGURATION - Declarative disk partitioning for galadriel
# ============================================================================
#
# NVMe disk with LVM layout:
#   /dev/nvme0n1p1 - BIOS boot partition (1MB)
#   /dev/nvme0n1p2 - /boot ext4 (1GB)
#   /dev/nvme0n1p3 - LVM PV (remaining space)
#     └─ vg_galadriel
#        ├─ lv_swap (8GB)
#        └─ lv_root (remaining - ext4)
#
# To verify disk path before deployment:
#   ssh root@192.168.2.3 lsblk
#   ssh root@192.168.2.3 ls -la /dev/nvme*
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
            # BIOS boot partition for GRUB (required for legacy BIOS boot)
            boot = {
              size = "1M";
              type = "EF02";
            };
            # Separate /boot partition (outside LVM for bootloader compatibility)
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["defaults"];
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

