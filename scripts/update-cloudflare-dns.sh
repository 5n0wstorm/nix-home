#!/usr/bin/env bash
set -euo pipefail
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/home/dominik/.config/sops/age/keys.txt}"
REPO="${1:-/home/dominik/nix-home}"
cd "$REPO"
TOKEN=$(sops -d --extract '["cloudflare_api_token"]' secrets/secrets.yaml)
ZONE=$(sops -d --extract '["cloudflare_zone_id"]' secrets/secrets.yaml)
IP="178.254.38.246"

upsert_a() {
  local name="$1"
  local rid
  rid=$(curl -sG "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
    --data-urlencode "type=A" \
    --data-urlencode "name=${name}" \
    -H "Authorization: Bearer ${TOKEN}" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin)["result"]; print(d[0]["id"] if d else "")')

  local payload
  payload=$(python3 -c "import json; print(json.dumps({'type':'A','name':'${name}','content':'${IP}','ttl':120,'proxied':False}))")

  if [[ -n "${rid}" ]]; then
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${rid}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      --data "${payload}"
  else
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      --data "${payload}"
  fi | python3 -c "import sys,json; r=json.load(sys.stdin); print('${name}', r.get('success'), r.get('errors'))"
}

upsert_a sn0wstorm.com
upsert_a "*.sn0wstorm.com"
upsert_a headscale.sn0wstorm.com
upsert_a mail.sn0wstorm.com
