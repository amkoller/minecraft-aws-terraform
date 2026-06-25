#!/bin/bash
set -euo pipefail
source /etc/minecraft/rcon.env

S3_BUCKET="${S3_BUCKET:?S3_BUCKET not set}"
REGION="${AWS_REGION:-us-east-2}"

if [ "$(systemctl is-active minecraft)" = "active" ]; then
  trap 'mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "save-on" || true' EXIT
  mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "save-all flush"
  sleep 3
  mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "save-off"
fi

TS=$(date -u +%Y%m%dT%H%M%SZ)
BASE=/opt/minecraft/server

for WORLD in world world_nether world_the_end; do
  if [ -d "$BASE/$WORLD" ]; then
    aws s3 sync "$BASE/$WORLD/" "s3://$S3_BUCKET/world/$TS/$WORLD/" \
      --only-show-errors --region "$REGION"
  fi
done

echo "$(date -u) Backup $TS complete"
