#!/usr/bin/env bash
# Run ON galadriel (not from WSL — 192.168.178.88 may hit a local WSL clone there).
set -euo pipefail
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH

cd /home/dominik/nix-home

echo "=== preflight ==="
hostname
df -h /
ls /data
sudo du -sh /data/nextcloud
sudo pvs -o+pv_pe_alloc_count,pv_pe_count
sudo lvs -a -o+devices | head -6
test -f hosts/galadriel/remove-hgst-once.nix
grep -q remove-hgst-once hosts/galadriel/configuration.nix

echo "=== nixos-rebuild switch ==="
sudo nixos-rebuild switch --flake .#galadriel

echo "=== post-deploy checks ==="
test ! -f /boot/do-remove-hgst && echo "OK: removal flag not set (initrd hook inactive)"
systemctl --failed --no-pager || true

cat <<'EOF'

DEPLOY OK.

Next steps (from console recommended):

1) Smoke-test — reboot WITHOUT flag:
     sudo reboot
   After return: pvs should still show nvme + HGST; Nextcloud OK.

2) Execute HGST removal:
     sudo touch /boot/do-remove-hgst
     sudo reboot
   Initrd shrink + pvmove may take 30–120 min. Do NOT hard-reset.

3) After boot, verify:
     sudo pvs          # only /dev/nvme0n1p2
     ls /boot/hgst-remove-done
     sudo du -sh /data/nextcloud

4) Remove temporary import from configuration.nix and rebuild again.
EOF
