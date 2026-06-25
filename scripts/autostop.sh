#!/bin/bash
set -euo pipefail

# cron runs with a minimal PATH (/usr/bin:/bin). mcrcon is installed in
# /usr/local/bin, so without this the "list" query silently fails, COUNT comes
# back empty, and the script bails before ever counting idle time — the server
# then runs 24/7. Set an explicit PATH so cron behaves like a login shell.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin

source /etc/minecraft/rcon.env

IDLE_MINUTES=${IDLE_MINUTES:-60}

if [ "$(systemctl is-active minecraft)" != "active" ]; then
  exit 0
fi

if ! command -v mcrcon >/dev/null 2>&1; then
  echo "$(date -u) ERROR: mcrcon not found on PATH ($PATH) — cannot check players"
  exit 1
fi

RAW=$(mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "list" 2>/dev/null || true)
OUT=$(echo "$RAW" | sed -E 's/\x1B\[[0-9;]*[mGKHF]//g')

COUNT=$(echo "$OUT" | grep -oP 'There are \K\d+' | head -1)
if [ -z "$COUNT" ]; then
  echo "$(date -u) WARN: could not parse player list, skipping. Raw: $(echo "$RAW" | tr -d '\n' | head -c 200)"
  exit 0
fi
IDLE_FILE=/var/lib/minecraft/idle_ticks
THRESHOLD=$(( IDLE_MINUTES / 5 ))

if [ "$COUNT" -gt 0 ]; then
  echo 0 > "$IDLE_FILE"
  echo "$(date -u) Players online: $COUNT — resetting idle counter"
  exit 0
fi

TICKS=0
[ -f "$IDLE_FILE" ] && TICKS=$(cat "$IDLE_FILE")
TICKS=$(( TICKS + 1 ))
echo "$TICKS" > "$IDLE_FILE"
echo "$(date -u) No players. Idle ticks: $TICKS / $THRESHOLD"

if [ "$TICKS" -ge "$THRESHOLD" ]; then
  echo "$(date -u) Idle threshold reached — shutting down"
  mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" \
    "say Server idle, shutting down in 30 seconds." || true
  sleep 30
  mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "stop" || true
  sleep 10
  /sbin/shutdown -h now
fi
