#!/usr/bin/env bash
# Push a gallery-dl tree to Fleet Gitea (git.sn0wstorm.com / local bare repo).
# Prefer a full checkout path as $1; default used to be vendor/ but that must
# not live in the public nix-home repo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if [ -z "$SRC" ]; then
  for candidate in \
    "$HOME/gallery-dl" \
    /tmp/gallery-dl-push \
    "$REPO_ROOT/vendor/gallery-dl"; do
    if [ -d "$candidate/gallery_dl" ]; then
      SRC="$candidate"
      break
    fi
  done
fi

if [ -z "${SRC:-}" ] || [ ! -d "$SRC/gallery_dl" ]; then
  echo "Missing gallery_dl source. Pass a path: $0 /path/to/gallery-dl" >&2
  exit 1
fi

rsync -a --delete --exclude .git "$SRC/" "$WORKDIR/"
cd "$WORKDIR"
git init -q
git config user.email "dominik@sn0wstorm.com"
git config user.name "Dominik"
git add -A
git commit -q -m "sync gallery-dl to Gitea"

for url in \
  "ssh://gitea@192.168.178.88/Dominik/gallery-dl.git" \
  "ssh://gitea@127.0.0.1/Dominik/gallery-dl.git" \
  "https://git.sn0wstorm.com/Dominik/gallery-dl.git"; do
  echo "Trying $url ..."
  if git push -u "$url" HEAD:master --force; then
    echo "Pushed to $url"
    exit 0
  fi
done

# Last resort on galadriel: update the local bare repo directly
BARE="/var/lib/gitea/git/repositories/dominik/gallery-dl.git"
if [ -d "$BARE" ]; then
  NEW="$(git rev-parse HEAD)"
  sudo git -c safe.directory="*" --git-dir="$BARE" fetch "$WORKDIR/.git" "+HEAD:refs/heads/master"
  sudo git -c safe.directory="*" --git-dir="$BARE" update-ref refs/heads/master "$NEW"
  echo "Updated local bare repo $BARE to $NEW"
  exit 0
fi

echo "Push failed — no Gitea remote reachable." >&2
exit 1
