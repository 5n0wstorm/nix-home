# Temporary one-shot: shrink root LV and remove HGST PV during stage-1 initrd.
# Gated by /boot/do-remove-hgst flag on the ESP. Remove this import after success.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # ESP is vfat — not in hardware-configuration initrd modules by default.
  boot.initrd.kernelModules = lib.mkAfter ["vfat" "nls_cp437" "nls_iso8859-1"];

  boot.initrd.extraUtilsCommands = lib.mkIf (!config.boot.initrd.systemd.enable) ''
    copy_bin_and_libs ${pkgs.e2fsprogs}/bin/e2fsck
    copy_bin_and_libs ${pkgs.e2fsprogs}/bin/resize2fs
    copy_bin_and_libs ${pkgs.gawk}/bin/awk
  '';

  boot.initrd.postDeviceCommands = lib.mkIf (!config.boot.initrd.systemd.enable) ''
    echo "galadriel: checking /boot/do-remove-hgst flag"
    mkdir -p /mnt-esp

    i=0
    while [ ! -e /dev/nvme0n1p1 ] && [ "$i" -lt 30 ]; do
      i=$((i + 1))
      sleep 0.2
    done
    if [ ! -e /dev/nvme0n1p1 ]; then
      echo "galadriel: /dev/nvme0n1p1 not found — skipping HGST removal"
    elif ! mount -t vfat -o ro /dev/nvme0n1p1 /mnt-esp; then
      echo "galadriel: failed to mount ESP /dev/nvme0n1p1 — skipping HGST removal"
    elif [ ! -f /mnt-esp/do-remove-hgst ]; then
      echo "galadriel: flag /do-remove-hgst absent on ESP — normal boot"
      umount /mnt-esp
    else
      echo "galadriel: HGST removal flag present — shrinking root and removing /dev/sda1"
      export PATH=/bin:$PATH
      vgchange -ay vg_galadriel || true
      sleep 1
      TARGET_SIZE=400G
      HGST_PV=/dev/sda1
      NVME_PV=/dev/nvme0n1p2
      LV_PATH=/dev/vg_galadriel/root

      e2fsck -f -y "$LV_PATH"
      resize2fs "$LV_PATH" "$TARGET_SIZE"
      lvresize -L "$TARGET_SIZE" "$LV_PATH"

      NVME_FREE=$(pvs --noheadings -o pv_pe_count,pv_pe_alloc_count "$NVME_PV" | awk '{print $1-$2}')
      echo "galadriel: NVMe free PEs: $NVME_FREE"
      if [ "$NVME_FREE" -lt 1000 ]; then
        echo "galadriel: parking root extents on HGST before pvmove"
        pvmove -n root "$NVME_PV" "$HGST_PV" || true
      fi

      echo "galadriel: pvmove off HGST (this may take a long time)"
      pvmove -v "$HGST_PV"
      vgreduce vg_galadriel "$HGST_PV"
      pvremove "$HGST_PV"

      umount /mnt-esp
      mount -t vfat /dev/nvme0n1p1 /mnt-esp
      rm -f /mnt-esp/do-remove-hgst
      echo "galadriel: HGST removal complete" > /mnt-esp/hgst-remove-done
      umount /mnt-esp
      echo "galadriel: HGST PV removed — continuing boot"
    fi
  '';

  boot.initrd.systemd.extraBin = lib.mkIf config.boot.initrd.systemd.enable {
    e2fsck = "${pkgs.e2fsprogs}/bin/e2fsck";
    resize2fs = "${pkgs.e2fsprogs}/bin/resize2fs";
    awk = "${pkgs.gawk}/bin/awk";
  };

  boot.initrd.systemd.services.remove-hgst = lib.mkIf config.boot.initrd.systemd.enable {
    description = "Shrink root and remove HGST PV when /boot/do-remove-hgst exists";
    wantedBy = ["initrd.target"];
    before = ["sysroot.mount"];
    after = ["systemd-udev-settle.service"];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      mkdir -p /mnt-esp
      if mount -t vfat -o ro /dev/nvme0n1p1 /mnt-esp && [ -f /mnt-esp/do-remove-hgst ]; then
        echo "galadriel: HGST removal flag present"
        vgchange -ay vg_galadriel || true
        sleep 1
        TARGET_SIZE=400G
        HGST_PV=/dev/sda1
        NVME_PV=/dev/nvme0n1p2
        LV_PATH=/dev/vg_galadriel/root
        e2fsck -f -y "$LV_PATH"
        resize2fs "$LV_PATH" "$TARGET_SIZE"
        lvresize -L "$TARGET_SIZE" "$LV_PATH"
        NVME_FREE=$(pvs --noheadings -o pv_pe_count,pv_pe_alloc_count "$NVME_PV" | awk '{print $1-$2}')
        if [ "$NVME_FREE" -lt 1000 ]; then
          pvmove -n root "$NVME_PV" "$HGST_PV" || true
        fi
        pvmove -v "$HGST_PV"
        vgreduce vg_galadriel "$HGST_PV"
        pvremove "$HGST_PV"
        umount /mnt-esp
        mount -t vfat /dev/nvme0n1p1 /mnt-esp
        rm -f /mnt-esp/do-remove-hgst
        echo done > /mnt-esp/hgst-remove-done
        umount /mnt-esp
        echo "galadriel: HGST PV removed"
      elif mountpoint -q /mnt-esp; then
        umount /mnt-esp
      fi
    '';
  };
}
