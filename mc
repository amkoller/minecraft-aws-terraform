#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TF_CACHE="/tmp/mc-tfout.$USER.json"
TF_CACHE_TTL=60

usage() {
  cat <<EOF
Usage: ./mc <command> [args]

Commands:
  start               Start the instance, wait for port, print connect address
  stop                Gracefully stop Minecraft, then stop instance
  status              Show instance state, current IP, and server status
  deploy              Rsync config/ to instance, restart server
  ssh [cmd...]        SSH to instance (pass-through)
  logs [--no-follow]  Stream (or dump) server journal
  backup-now          Run backup script on server
  restore <timestamp> Restore world from S3 backup
  rcon <cmd...>       Run RCON command on server
EOF
}

get_tf_output() {
  local now
  now=$(date +%s)
  if [ -f "$TF_CACHE" ]; then
    local mtime
    mtime=$(stat -f %m "$TF_CACHE" 2>/dev/null || stat -c %Y "$TF_CACHE" 2>/dev/null || echo 0)
    if [ $(( now - mtime )) -lt $TF_CACHE_TTL ]; then
      cat "$TF_CACHE"
      return
    fi
  fi
  (cd "$TF_DIR" && terraform output -json) | tee "$TF_CACHE"
}

get_field() {
  get_tf_output | jq -r ".$1.value"
}

get_instance_id() { get_field instance_id; }
get_bucket()      { get_field s3_backup_bucket; }
get_region()      { get_field region; }
get_ssh_user()    { get_field ssh_user; }

get_public_ip() {
  local instance_id region
  instance_id=$(get_instance_id)
  region=$(get_region)
  aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --region "$region" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text
}

get_ssh_key() {
  # Try to find the key — check common paths
  local key_path
  key_path=$(cd "$TF_DIR" && terraform output -json 2>/dev/null | jq -r '.ssh_key_path.value // empty' 2>/dev/null || true)
  if [ -z "$key_path" ] && [ -f ~/.ssh/minecraft ]; then
    echo ~/.ssh/minecraft
  elif [ -n "$key_path" ]; then
    echo "$key_path"
  else
    echo ~/.ssh/minecraft
  fi
}

ssh_cmd() {
  local ip user key
  ip=$(get_public_ip)
  user=$(get_ssh_user)
  key=$(get_ssh_key)
  ssh -i "$key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${user}@${ip}" "$@"
}

cmd_start() {
  local instance_id region
  instance_id=$(get_instance_id)
  region=$(get_region)

  echo "Starting instance $instance_id..."
  aws ec2 start-instances --instance-ids "$instance_id" --region "$region" > /dev/null
  echo "Waiting for instance to reach running state..."
  aws ec2 wait instance-running --instance-ids "$instance_id" --region "$region"

  local ip
  ip=$(get_public_ip)
  echo "Instance running. IP: $ip"
  echo "Waiting for port 25565 to open (up to 5 min)..."

  local deadline
  deadline=$(( $(date +%s) + 300 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if nc -z -w 3 "$ip" 25565 2>/dev/null; then
      echo ""
      echo "Connect: $ip:25565"
      if command -v pbcopy &>/dev/null; then
        echo "$ip:25565" | pbcopy
        echo "(Copied to clipboard)"
      fi
      return 0
    fi
    printf '.'
    sleep 5
  done
  echo ""
  echo "WARNING: Port 25565 not yet open, but server may still be starting."
  echo "Connect: $ip:25565"
}

cmd_stop() {
  local instance_id region ip user key
  instance_id=$(get_instance_id)
  region=$(get_region)
  ip=$(get_public_ip)
  user=$(get_ssh_user)
  key=$(get_ssh_key)

  echo "Sending graceful stop via RCON..."
  ssh -i "$key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${user}@${ip}" \
    "sudo systemctl stop minecraft" || echo "WARN: graceful stop returned non-zero"

  echo "Stopping EC2 instance..."
  aws ec2 stop-instances --instance-ids "$instance_id" --region "$region" > /dev/null
  echo "Instance stop initiated."
}

cmd_status() {
  local instance_id region
  instance_id=$(get_instance_id)
  region=$(get_region)

  local state
  state=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --region "$region" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

  local ip
  ip=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --region "$region" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

  echo "Instance: $instance_id"
  echo "State:    $state"
  echo "IP:       ${ip:-none}"

  if [ "$state" = "running" ] && [ -n "$ip" ] && [ "$ip" != "None" ]; then
    echo "Connect:  $ip:25565"
    if nc -z -w 3 "$ip" 25565 2>/dev/null; then
      echo "Port 25565: OPEN"
    else
      echo "Port 25565: CLOSED (server may be starting)"
    fi
    local active
    active=$(ssh_cmd "systemctl is-active minecraft" 2>/dev/null || echo "unknown")
    echo "minecraft.service: $active"
    # Handle --ip flag
    if [ "${1:-}" = "--ip" ]; then
      echo "$ip"
    fi
  fi
}

cmd_deploy() {
  local ip user key
  ip=$(get_public_ip)
  user=$(get_ssh_user)
  key=$(get_ssh_key)

  echo "Syncing config/ to $ip..."
  rsync -avz --delete-after \
    --exclude='world*' \
    --exclude='plugins/*.jar' \
    -e "ssh -i $key -o StrictHostKeyChecking=no" \
    "$SCRIPT_DIR/config/" \
    "${user}@${ip}:/tmp/mc-stage/"

  echo "Installing config on server..."
  ssh -i "$key" -o StrictHostKeyChecking=no "${user}@${ip}" bash <<'REMOTE'
sudo rsync -a /tmp/mc-stage/ /opt/minecraft/server/
# Re-inject rcon.password from rcon.env (read with sudo — file is root-owned)
RCON_PASSWORD=$(sudo sed -n 's/^RCON_PASSWORD=//p' /etc/minecraft/rcon.env)
PROPS=/opt/minecraft/server/server.properties
# Remove any existing rcon.password line, then append the correct one
sudo sed -i '/^rcon\.password=/d' "$PROPS"
echo "rcon.password=$RCON_PASSWORD" | sudo tee -a "$PROPS" > /dev/null
sudo chown -R minecraft:minecraft /opt/minecraft/server
sudo systemctl restart minecraft
REMOTE

  echo "Deploy complete. Server restarting."
}

cmd_ssh() {
  local ip user key
  ip=$(get_public_ip)
  user=$(get_ssh_user)
  key=$(get_ssh_key)
  exec ssh -i "$key" -o StrictHostKeyChecking=no "${user}@${ip}" "$@"
}

cmd_logs() {
  local follow="-f"
  if [ "${1:-}" = "--no-follow" ]; then
    follow=""
  fi
  ssh_cmd "sudo journalctl -u minecraft -n 200 $follow"
}

cmd_backup_now() {
  echo "Running backup on server..."
  ssh_cmd "sudo /usr/local/sbin/backup.sh"
}

cmd_restore() {
  local ts="${1:?Usage: ./mc restore <timestamp>}"
  local bucket region instance_id key user ip
  bucket=$(get_bucket)
  region=$(get_region)
  ip=$(get_public_ip)
  user=$(get_ssh_user)
  key=$(get_ssh_key)

  echo "WARNING: This will REPLACE the current world with backup $ts"
  echo "Are you sure? (yes/no)"
  read -r confirm
  [ "$confirm" = "yes" ] || { echo "Aborted."; exit 1; }

  echo "Stopping Minecraft..."
  ssh -i "$key" -o StrictHostKeyChecking=no "${user}@${ip}" \
    "sudo systemctl stop minecraft" || true

  echo "Restoring world from s3://$bucket/world/$ts/..."
  for WORLD in world world_nether world_the_end; do
    if aws s3 ls "s3://$bucket/world/$ts/$WORLD/" --region "$region" &>/dev/null; then
      ssh -i "$key" -o StrictHostKeyChecking=no "${user}@${ip}" \
        "sudo aws s3 sync s3://$bucket/world/$ts/$WORLD/ /opt/minecraft/server/$WORLD/ --delete --region $region"
    fi
  done

  echo "Starting Minecraft..."
  ssh -i "$key" -o StrictHostKeyChecking=no "${user}@${ip}" \
    "sudo systemctl start minecraft"

  echo "Restore complete."
}

cmd_rcon() {
  local rcon_password
  rcon_password=$(get_tf_output | jq -r '.rcon_password.value')
  ssh_cmd "mcrcon -H 127.0.0.1 -P 25575 -p '$rcon_password' $(printf '%q ' "$@")"
}

CMD="${1:-}"
shift || true

case "$CMD" in
  start)       cmd_start "$@" ;;
  stop)        cmd_stop "$@" ;;
  status)      cmd_status "$@" ;;
  deploy)      cmd_deploy "$@" ;;
  ssh)         cmd_ssh "$@" ;;
  logs)        cmd_logs "$@" ;;
  backup-now)  cmd_backup_now "$@" ;;
  restore)     cmd_restore "$@" ;;
  rcon)        cmd_rcon "$@" ;;
  *)           usage; exit 1 ;;
esac
