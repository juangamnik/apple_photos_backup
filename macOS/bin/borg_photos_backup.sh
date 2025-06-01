#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --decrypted-mount PATH   Path to decrypted gocryptfs mount (required)
  --local-export-dir PATH  Path to local export dir (required)
  --borg-repo REPO         Borg repository (required)
  --borg-keychain NAME     macOS keychain service for borg password (required)
  --dry-run true|false     Dry-run mode (default: false)
  --help                   Show this help text and exit
EOF
  exit 0
fi

# Default values
DRY_RUN=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --decrypted-mount)   DECRYPTED_MOUNT="$2"; shift 2;;
    --local-export-dir)  LOCAL_EXPORT_DIR="$2"; shift 2;;
    --borg-repo)         BORG_REPO="$2"; shift 2;;
    --borg-keychain)     BORG_KEYCHAIN="$2"; shift 2;;
    --dry-run)           DRY_RUN="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

# Validate required args
if [[ -z "${DECRYPTED_MOUNT:-}" || -z "${LOCAL_EXPORT_DIR:-}" || -z "${BORG_REPO:-}" || -z "${BORG_KEYCHAIN:-}" ]]; then
  echo "ERROR: Missing required arguments. Use --help for usage."
  exit 2
fi

ARCHIVE_NAME="backup-{now:%Y-%m-%d_%H-%M}"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY-RUN: Would run Borg backup:"
  echo "  /opt/homebrew/bin/borg create --stats --compression lz4 \"$BORG_REPO::$ARCHIVE_NAME\" . (in $DECRYPTED_MOUNT)"
  echo "DRY-RUN: Would delete all files in $LOCAL_EXPORT_DIR and $DECRYPTED_MOUNT"
  echo "DRY-RUN: Would update date_threshold to first of current month in both locations"
  exit 0
fi

# Get passphrase from Apple Keychain (never store in file or log)
BORG_PASSPHRASE_MAIN="$(security find-generic-password -s "$BORG_KEYCHAIN" -w 2>/dev/null || true)"
BORG_PASSPHRASE_EXTRA=""
if security find-generic-password -s "${BORG_KEYCHAIN}_1" -w >/dev/null 2>&1; then
  BORG_PASSPHRASE_EXTRA="$(security find-generic-password -s "${BORG_KEYCHAIN}_1" -w)"
  export BORG_PASSPHRASE="${BORG_PASSPHRASE_MAIN}${BORG_PASSPHRASE_EXTRA}"
else
  export BORG_PASSPHRASE="$BORG_PASSPHRASE_MAIN"
fi

(
  cd "$DECRYPTED_MOUNT"
  /opt/homebrew/bin/borg create --stats --compression lz4 "$BORG_REPO::$ARCHIVE_NAME" .
)
unset BORG_PASSPHRASE

borg_status=$?
if [[ $borg_status -eq 0 ]]; then
  echo "INFO: Borg backup completed: $ARCHIVE_NAME"
else
  echo "ERROR: Borg backup failed, not deleting files or updating date_threshold."
  exit 1
fi
