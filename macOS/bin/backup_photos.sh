#!/usr/bin/env bash
# backup_photos.sh
set -euo pipefail

VERSION="1.0.0"

if [[ "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options (override values from photos_backup.conf):
  --ssh-user USER           SSH username
  --ssh-host HOST           SSH host or IP address
  --identity-file PATH      Path to SSH private key
  --remote-dir PATH         Remote encrypted directory (via SSHFS)
  --mount-point PATH        Local mount point for SSHFS
  --decrypted-mount PATH    Local mount point for decrypted gocryptfs volume
  --keychain-service NAME   macOS keychain service for gocryptfs password
  --local-export-dir PATH   Temporary local export directory
  --date-threshold YYYY-MM-DD
                            Only export photos taken or modified after this date
  --dry-run                 Run without syncing any data
  --help                    Show this help text and exit
  --version                 Show script version and exit
EOF
  exit 0
fi

if [[ "${1:-}" == "--version" ]]; then
  echo "$(basename "$0") version $VERSION"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/photos_backup.conf"

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-user|--ssh-host|--identity-file|--remote-dir|--mount-point|--decrypted-mount|--keychain-service)
      VAR="${1/--/}"; declare "$VAR"="$2"; shift 2;;
    --local-export-dir)   LOCAL_EXPORT_DIR="$2"; shift 2;;
    --date-threshold)     DATE_THRESHOLD="$2"; shift 2;;
    --dry-run)            DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

default_log_setup() {
  LOG_FILE="/tmp/backup_$(whoami).log"
  ERROR_LOCAL="${LOCAL_EXPORT_DIR}/error.log"
  ERROR_DECRYPTED="${DECRYPTED_MOUNT}/error.log"
}
default_log_setup

mkdir -p "$LOCAL_EXPORT_DIR" "$MOUNT_POINT" "$DECRYPTED_MOUNT"
rm -f "$LOG_FILE" "$ERROR_LOCAL" "$ERROR_DECRYPTED" || true

exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

error_handler() {
  code=$?; ts=$(date '+%Y-%m-%d %H:%M:%S'); cmd="$BASH_COMMAND"

  error_block=$(cat <<EOF
[$ts] ERROR: Backup failed (exit $code)
[$ts] ERROR: Command: $cmd
[$ts] ERROR: Last 20 lines of log:
$(tail -n20 "$LOG_FILE")
------------------------------------------------
EOF
)

  echo "$error_block" >> "$ERROR_LOCAL"

  if mount | grep -q "on $DECRYPTED_MOUNT "; then
    echo "$error_block" >> "$ERROR_DECRYPTED" 2>/dev/null || true
  fi

  launchctl asuser "$(id -u)" osascript -e "display notification \"Backup failed (code $code)\" with title \"Photo Backup\" subtitle \"Check error.log\""
  /sbin/umount "$DECRYPTED_MOUNT" 2>/dev/null || true
  /sbin/umount "$MOUNT_POINT"       2>/dev/null || true
  exit $code
}
trap error_handler ERR

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Starting backup"

"$SCRIPT_DIR/mount_photos_backup.sh" \
  --ssh-user "$SSH_USER" \
  --ssh-host "$SSH_HOST" \
  --identity-file "$IDENTITY_FILE" \
  --remote-dir "$REMOTE_DIR" \
  --mount-point "$MOUNT_POINT" \
  --decrypted-mount "$DECRYPTED_MOUNT" \
  --keychain-service "$KEYCHAIN_SERVICE"

DECRYPTED_DATE_FILE="$DECRYPTED_MOUNT/date_threshold"
if [[ -f "$DECRYPTED_DATE_FILE" ]]; then
  cp "$DECRYPTED_DATE_FILE" "$LOCAL_EXPORT_DIR/date_threshold"
fi

DATE_FILE="$LOCAL_EXPORT_DIR/date_threshold"
if [[ -f "$DATE_FILE" ]]; then
  DATE_THRESHOLD=$(<"$DATE_FILE")
fi
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Using date threshold: $DATE_THRESHOLD"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Exporting photos..."
"$SCRIPT_DIR/export_photos.sh" \
  --date-threshold "$DATE_THRESHOLD" \
  --export-dir "$LOCAL_EXPORT_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Export completed"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Syncing to $DECRYPTED_MOUNT..."
RSYNC_OPTS="-a --delete --no-perms --stats"
$DRY_RUN && RSYNC_OPTS+=" --dry-run"

/opt/homebrew/bin/rsync $RSYNC_OPTS "$LOCAL_EXPORT_DIR"/ "$DECRYPTED_MOUNT"/
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Sync completed"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Unmounting volumes..."
(/sbin/umount "$DECRYPTED_MOUNT" && /sbin/umount "$MOUNT_POINT") || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Backup finished successfully"
