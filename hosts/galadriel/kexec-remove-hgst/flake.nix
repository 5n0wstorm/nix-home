{
  description = "Galadriel one-shot kexec env to shrink root and remove HGST from LVM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-images.url = "github:nix-community/nixos-images";
  };

  nixConfig = {
    extra-substituters = ["https://nix-community.cachix.org"];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs = {
    self,
    nixpkgs,
    nixos-images,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    shrinkScript = pkgs.writeShellScriptBin "hdd-remove-lvm-offline" ''
      set -euo pipefail
      export PATH=${pkgs.lvm2}/bin:${pkgs.e2fsprogs}/bin:${pkgs.util-linux}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gawk}/bin:$PATH

      TARGET_SIZE="''${1:-400G}"
      HGST_PV="''${HGST_PV:-/dev/sda1}"
      NVME_PV="''${NVME_PV:-/dev/nvme0n1p2}"
      VG=vg_galadriel
      LV_PATH=/dev/''${VG}/root

      echo "=== activate VG ==="
      vgchange -ay "$VG" || true
      sleep 1

      echo "=== preflight ==="
      pvs -o+pv_pe_alloc_count,pv_pe_count
      lvs -a -o+devices
      lsblk

      if findmnt "$LV_PATH" >/dev/null 2>&1 || findmnt /dev/mapper/''${VG}-root >/dev/null 2>&1; then
        echo "ERROR: root LV is mounted — refuse to shrink."
        exit 1
      fi

      echo "=== fsck ==="
      e2fsck -f -y "$LV_PATH"

      echo "=== shrink filesystem to ''${TARGET_SIZE} ==="
      resize2fs "$LV_PATH" "$TARGET_SIZE"

      echo "=== shrink LV to ''${TARGET_SIZE} ==="
      lvresize -L "$TARGET_SIZE" "$LV_PATH"

      echo "=== allocation after shrink ==="
      pvs -o+pv_pe_alloc_count,pv_pe_count
      lvs -a -o+devices

      NVME_FREE=$(pvs --noheadings -o pv_pe_count,pv_pe_alloc_count "$NVME_PV" | awk '{print $1-$2}')
      echo "NVMe free PEs: $NVME_FREE"
      if [ "''${NVME_FREE}" -lt 1000 ]; then
        echo "=== freeing space on NVMe by moving root extents onto HGST free space ==="
        pvmove -n root "$NVME_PV" "$HGST_PV" || true
        pvs -o+pv_pe_alloc_count,pv_pe_count
      fi

      echo "=== pvmove all extents off HGST onto NVMe ==="
      pvmove -v "$HGST_PV"

      echo "=== remove HGST PV ==="
      vgreduce "$VG" "$HGST_PV"
      pvremove "$HGST_PV"

      echo "=== final ==="
      pvs -o+pv_pe_alloc_count,pv_pe_count
      vgs
      lvs -a -o+devices
      lsblk
      echo "DONE — reboot into normal NixOS (power cycle / reboot)"
    '';

    kexecModule = {
      _file = ./flake.nix;
      system.kexec-installer.name = "galadriel-hgst-remove";
      imports = [
        nixos-images.nixosModules.kexec-installer
      ];

      # Keep SSH reachable even if restore-network misses NM-managed addrs.
      systemd.network.enable = true;
      networking.useNetworkd = true;
      networking.useDHCP = false;
      systemd.network.networks."10-eno1" = {
        matchConfig.Name = "eno1";
        networkConfig = {
          Address = "192.168.178.88/24";
          Gateway = "192.168.178.1";
          DNS = ["8.8.8.8" "1.1.1.1"];
        };
        linkConfig.RequiredForOnline = "routable";
      };

      environment.systemPackages = [
        pkgs.lvm2
        pkgs.e2fsprogs
        pkgs.util-linux
        pkgs.tmux
        pkgs.htop
        shrinkScript
      ];

      # Drop the shrink script at a stable path in the RAM system.
      environment.etc."hdd-remove-lvm-offline.sh".source = "${shrinkScript}/bin/hdd-remove-lvm-offline";
    };

    kexecTarball =
      (pkgs.nixos [kexecModule]).config.system.build.kexecInstallerTarball;
  in {
    packages.${system}.default = kexecTarball;
    packages.${system}.kexec = kexecTarball;
  };
}
