#!/usr/bin/env bash
# Prepare and kexec into nixos installer RAM system, then run offline LVM script.
# WARNING: this reboots the machine into a temporary installer environment.
set -euo pipefail
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH

WORK=/home/dominik/hdd-remove-kexec
SCRIPT_SRC=/home/dominik/nix-home/.hdd-remove-lvm-offline.sh
mkdir -p "$WORK"
cd "$WORK"

if [[ ! -x ./kexec/run ]]; then
  echo "=== fetching nixos kexec installer ==="
  # nixos-images kexec installer (nixos unstable/stable variant)
  nix build --out-link "$WORK/kexec-result" 'github:nix-community/nixos-images#packages.x86_64-linux.kexec-installer-nixos-unstable-noninteractive' || \
  nix build --out-link "$WORK/kexec-result" 'github:nix-community/nixos-images#kexec-installer-nixos-unstable-noninteractive' || \
  nix build --out-link "$WORK/kexec-result" 'github:nix-community/nixos-images#packages.x86_64-linux.kexec-installer-nixos-unstable'

  # result is usually a directory or a tarball — normalize
  if [[ -d "$WORK/kexec-result" ]]; then
    rm -rf "$WORK/kexec"
    cp -a "$WORK/kexec-result" "$WORK/kexec"
  elif [[ -f "$WORK/kexec-result" ]]; then
    mkdir -p "$WORK/kexec"
    tar -C "$WORK/kexec" -xf "$WORK/kexec-result"
  fi
fi

cp -f "$SCRIPT_SRC" "$WORK/hdd-remove-lvm-offline.sh"
chmod +x "$WORK/hdd-remove-lvm-offline.sh"

echo "=== kexec tree ==="
ls -la "$WORK/kexec" | head
find "$WORK/kexec" -maxdepth 2 -type f | head -40

echo "Ready. To enter installer RAM env (drops SSH to current OS):"
echo "  cd $WORK && sudo ./kexec/kexec-installer || sudo ./kexec/run"
echo "Then from the installer SSH session, run:"
echo "  bash $WORK/hdd-remove-lvm-offline.sh 400G"
echo "(path may be under /mnt if installer remounts disks differently — copy script to /root first)"
