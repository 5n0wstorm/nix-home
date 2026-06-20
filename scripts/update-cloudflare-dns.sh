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

  # Fetch ALL records for this name (any type), so we can clear conflicts.
  local resp
  resp=$(curl -sG "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
    --data-urlencode "name=${name}" \
    -H "Authorization: Bearer ${TOKEN}")

  # A name cannot hold both a CNAME and an A record. Delete any non-A records
  # (e.g. a stale wildcard CNAME) that would block the A record below.
  local del_ids
  del_ids=$(echo "$resp" | python3 -c 'import sys,json
d=json.load(sys.stdin)["result"]
print("\n".join(r["id"] for r in d if r["type"]!="A"))')
  local del_id
  for del_id in $del_ids; do
    curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${del_id}" \
      -H "Authorization: Bearer ${TOKEN}" >/dev/null
    echo "${name} deleted conflicting non-A record ${del_id}"
  done

  local rid
  rid=$(echo "$resp" | python3 -c 'import sys,json
d=json.load(sys.stdin)["result"]
a=[r for r in d if r["type"]=="A"]
print(a[0]["id"] if a else "")')

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
