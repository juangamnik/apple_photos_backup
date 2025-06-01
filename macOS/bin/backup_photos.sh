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
  --gocryptfs-keychain NAME macOS keychain service for gocryptfs password
  --borg-keychain NAME      macOS keychain service for borg backup password
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

# Always remove old error logs at the start of the backup (except ERROR_DECRYPTED)
rm -f "$LOG_FILE" "$ERROR_LOCAL" 2>/dev/null || true

mkdir -p "$LOCAL_EXPORT_DIR" "$MOUNT_POINT" "$DECRYPTED_MOUNT"

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

  # Fehler beim Schreiben in error.log ignorieren, ggf. auf stderr ausgeben
  { echo "$error_block" >> "$ERROR_LOCAL"; } 2>/dev/null || echo "$error_block" >&2

  if mount | grep -q "on $DECRYPTED_MOUNT "; then
    { echo "$error_block" >> "$ERROR_DECRYPTED"; } 2>/dev/null || true
  fi

  launchctl asuser "$(id -u)" osascript -e "display notification \"Backup failed (code $code)\" with title \"Photo Backup\" subtitle \"Check error.log\"" || true

  # Mounts immer aushängen, Fehler ignorieren
  /sbin/umount "$DECRYPTED_MOUNT" 2>/dev/null || /usr/sbin/diskutil unmount force "$DECRYPTED_MOUNT" 2>/dev/null || true
  /sbin/umount "$MOUNT_POINT" 2>/dev/null || /usr/sbin/diskutil unmount force "$MOUNT_POINT" 2>/dev/null || true

  rm -f "$LOG_FILE" 2>/dev/null || true # Fehler ignorieren
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
  --gocryptfs-keychain "$GOCRYPTFS_KEYCHAIN" \
  --borg-keychain "$BORG_KEYCHAIN"

# Remove old error log from decrypted mount after it is mounted
rm -f "$ERROR_DECRYPTED" 2>/dev/null || true

DECRYPTED_DATE_FILE="$DECRYPTED_MOUNT/date_threshold"
if [[ -f "$DECRYPTED_DATE_FILE" ]]; then
  cp "$DECRYPTED_DATE_FILE" "$LOCAL_EXPORT_DIR/date_threshold" 2>/dev/null || true
fi

DATE_FILE="$LOCAL_EXPORT_DIR/date_threshold"
if [[ -f "$DATE_FILE" ]]; then
  DATE_THRESHOLD=$(<"$DATE_FILE")
fi
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Using date threshold: $DATE_THRESHOLD"

# Check if DATE_THRESHOLD is not from the current month
if [[ -n "$DATE_THRESHOLD" ]]; then
  threshold_month=$(date -jf "%Y-%m-%d" "$DATE_THRESHOLD" +%Y-%m 2>/dev/null || date -d "$DATE_THRESHOLD" +%Y-%m)
  current_month=$(date +%Y-%m)
  if [[ "$threshold_month" != "$current_month" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: date_threshold is not from current month, will run Borg backup after a final sync with Apple Photos."
    # Continue to export and sync before Borg backup
  fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Exporting photos..."
EXPORT_PHOTOS_ARGS=(
  --date-threshold "$DATE_THRESHOLD"
  --export-dir "$LOCAL_EXPORT_DIR"
)
$DRY_RUN && EXPORT_PHOTOS_ARGS+=(--dry-run)
"$SCRIPT_DIR/export_photos.sh" "${EXPORT_PHOTOS_ARGS[@]}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Export completed"

# Write current date_threshold to LOCAL_EXPORT_DIR before rsync
if [[ -n "$DATE_THRESHOLD" ]]; then
  echo "$DATE_THRESHOLD" > "$LOCAL_EXPORT_DIR/date_threshold"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Syncing to $DECRYPTED_MOUNT..."
RSYNC_OPTS="-a --delete --no-perms --stats"
$DRY_RUN && RSYNC_OPTS+=" --dry-run"

/opt/homebrew/bin/rsync $RSYNC_OPTS "$LOCAL_EXPORT_DIR"/ "$DECRYPTED_MOUNT"/
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Sync completed"

# After the final sync, check if Borg backup is needed (date_threshold not from current month)
if [[ -n "$DATE_THRESHOLD" ]]; then
  threshold_month=$(date -jf "%Y-%m-%d" "$DATE_THRESHOLD" +%Y-%m 2>/dev/null || date -d "$DATE_THRESHOLD" +%Y-%m)
  current_month=$(date +%Y-%m)
  if [[ "$threshold_month" != "$current_month" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Running Borg backup after final sync..."

    "$SCRIPT_DIR/borg_photos_backup.sh" \
      --decrypted-mount "$DECRYPTED_MOUNT" \
      --local-export-dir "$LOCAL_EXPORT_DIR" \
      --borg-repo "${BORG_REPO:-}" \
      --borg-keychain "${BORG_KEYCHAIN:-}" \
      --dry-run "$DRY_RUN"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Borg backup finished."

    # After successful Borg backup: delete files and update date_threshold
    if [[ "$DRY_RUN" != "true" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Deleting backed up files from $LOCAL_EXPORT_DIR and $DECRYPTED_MOUNT"
      find "$LOCAL_EXPORT_DIR" -mindepth 1 -delete

      # Empty DECRYPTED_MOUNT using rsync --delete with empty LOCAL_EXPORT_DIR
      /opt/homebrew/bin/rsync -a --delete "$LOCAL_EXPORT_DIR"/ "$DECRYPTED_MOUNT"/

      FIRST_OF_MONTH=$(date +%Y-%m-01)
      echo "$FIRST_OF_MONTH" > "$LOCAL_EXPORT_DIR/date_threshold"
      echo "$FIRST_OF_MONTH" > "$DECRYPTED_MOUNT/date_threshold"
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Updated date_threshold to $FIRST_OF_MONTH"
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] DRY-RUN: Would delete all files in $LOCAL_EXPORT_DIR and $DECRYPTED_MOUNT"
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] DRY-RUN: Would update date_threshold to first of current month in both locations"
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Unmounting volumes after Borg backup..."
    (/sbin/umount "$DECRYPTED_MOUNT" && /sbin/umount "$MOUNT_POINT") || true

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Backup mode (not current month) finished."
    exit 0
  fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Unmounting volumes..."
(/sbin/umount "$DECRYPTED_MOUNT" && /sbin/umount "$MOUNT_POINT") || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Backup finished successfully"
rm -f "$LOG_FILE" # Delete LOG_FILE after successful completion
