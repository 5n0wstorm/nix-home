#!/usr/bin/env bash
set -euo pipefail
REPO=/mnt/c/Users/Dominik/Documents/Repos/nix-home
HOST=dominik@192.168.178.88

echo "=== sync ==="
scp -o BatchMode=yes \
  "$REPO/hosts/galadriel/configuration.nix" \
  "$REPO/modules/system/hetzner-archive-mount.nix" \
  "$HOST:/tmp/hgst-sync-staging/"

ssh -o BatchMode=yes "$HOST" bash -s <<'EOF'
set -euo pipefail
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH
mkdir -p /tmp/hgst-sync-staging
cd /home/dominik/nix-home
cp /tmp/hgst-sync-staging/configuration.nix hosts/galadriel/
mkdir -p modules/system
cp /tmp/hgst-sync-staging/hetzner-archive-mount.nix modules/system/
EOF

echo "=== deploy ==="
ssh -o BatchMode=yes "$HOST" bash -s <<'EOF'
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH
cd /home/dominik/nix-home
sudo nixos-rebuild switch --flake .#galadriel 2>&1 | tail -40
EOF

echo "=== verify mount + services ==="
ssh -o BatchMode=yes "$HOST" bash -s <<'EOF'
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH
mountpoint /mnt/hetzner && ls -la /mnt/hetzner/archive | head -12
systemctl is-active hetzner-archive-mount.service
systemctl is-active sonarr.service radarr.service sabnzbd.service podman-gluetun.service 2>&1 || true
systemctl is-active gallery-dl-telegram.timer 2>&1 || true
EOF
