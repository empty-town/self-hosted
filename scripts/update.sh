#!/usr/bin/env bash
# Pull the newest image for each pinned tag and redeploy every stack.
# Run manually or from a cron/systemd timer.
# Safer alternative to Watchtower: no Docker socket in a container.
# Example cron (Sunday 04:00):  0 4 * * 0  /path/to/scripts/update.sh
#
# Images are pinned by tag (e.g. mariadb:11), not by digest, so `pull` advances
# them to the newest build of that tag. `build --pull` rebuilds the Caddy image
# and pulls newer base layers too. Review the changelogs for any app that can
# cross a major version (Nextcloud, Immich) before you run this unattended.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for dir in "$REPO_DIR" "$REPO_DIR"/stacks/*/; do
  [[ -f "$dir/docker-compose.yml" ]] || continue
  case "$dir" in
    */stacks/immich/*)
      echo "-- skipping immich: update it by hand (pre-1.0, frequent breaking changes)"
      continue ;;
  esac
  echo "== $dir =="
  docker compose --project-directory "$dir" --env-file "$REPO_DIR/.env" pull
  docker compose --project-directory "$dir" --env-file "$REPO_DIR/.env" build --pull
  docker compose --project-directory "$dir" --env-file "$REPO_DIR/.env" up -d
done

docker image prune -f
# The Caddy rebuild leaves xcaddy build cache behind each run; on a small
# disk it accumulates until apps hit free-space floors (Jellyfin 10.11+
# refuses to start with <2GiB free). Keep only the latest build's cache.
docker builder prune -f --keep-storage 1GB
echo "[ok] update complete: $(date -Is)"
