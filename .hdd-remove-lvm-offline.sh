#!/usr/bin/env bash
# Offline LVM shrink + HGST removal for galadriel.
# Intended to run from a kexec/live environment where /dev/vg_galadriel/root is NOT mounted.
set -euo pipefail
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

TARGET_SIZE="${1:-400G}"
HGST_PV="${HGST_PV:-/dev/sda1}"
NVME_PV="${NVME_PV:-/dev/nvme0n1p2}"
VG=vg_galadriel
LV_PATH=/dev/${VG}/root

echo "=== activate VG ==="
vgchange -ay "$VG" || true
sleep 1

echo "=== preflight ==="
pvs -o+pv_pe_alloc_count,pv_pe_count
lvs -a -o+devices
lsblk

if findmnt "$LV_PATH" >/dev/null 2>&1 || findmnt /dev/mapper/${VG}-root >/dev/null 2>&1; then
  echo "ERROR: root LV is mounted — refuse to shrink. Boot a live/kexec env first."
  findmnt "$LV_PATH" || true
  findmnt /dev/mapper/${VG}-root || true
  exit 1
fi

echo "=== fsck ==="
e2fsck -f -y "$LV_PATH"

echo "=== shrink filesystem to ${TARGET_SIZE} ==="
resize2fs "$LV_PATH" "$TARGET_SIZE"

echo "=== shrink LV to ${TARGET_SIZE} ==="
lvresize -L "$TARGET_SIZE" "$LV_PATH"

echo "=== allocation after shrink ==="
pvs -o+pv_pe_alloc_count,pv_pe_count
lvs -a -o+devices

# Ensure NVMe has free PEs: if not, temporarily park some root extents on HGST free space.
NVME_FREE=$(pvs --noheadings -o pv_pe_count,pv_pe_alloc_count "$NVME_PV" | awk '{print $1-$2}')
echo "NVMe free PEs: $NVME_FREE"
if [[ "$NVME_FREE" -lt 1000 ]]; then
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
echo "DONE — reboot into normal NixOS"
