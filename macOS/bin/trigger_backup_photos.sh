#!/usr/bin/env bash
# trigger_backup_photos.sh
# This script triggers backup_photos.sh only if the SSH host is known and reachable

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Load central configuration
# shellcheck source=/dev/null
source "$SCRIPT_DIR/photos_backup.conf"

# SSH configuration (hardcoded options, user/host from config)
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5"

# Check if host key is present in known_hosts
if ! /usr/bin/ssh-keygen -F "$SSH_HOST" >/dev/null 2>&1; then
  echo "Error: Host $SSH_HOST not found in known_hosts. Aborting." >&2
  exit 1
fi

# Test SSH connectivity
if ! /usr/bin/ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" exit >/dev/null 2>&1; then
  # Host unreachable or authentication failed — exit silently
  exit 1
fi

# Trigger the actual backup script
"$SCRIPT_DIR/backup_photos.sh"

exit $?
