#!/usr/bin/env bash
# mount_photos_backup.sh
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
  --gocryptfs-keychain NAME   macOS keychain service for gocryptfs password
  --help                    Show this help text and exit
  --version                 Show script version and exit

This script mounts the remote encrypted photo folder using SSHFS and gocryptfs.
EOF
  exit 0
fi

if [[ "${1:-}" == "--version" ]]; then
  echo "$(basename "$0") version $VERSION"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/photos_backup.conf"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-user)          SSH_USER="$2";         shift 2;;
    --ssh-host)          SSH_HOST="$2";         shift 2;;
    --identity-file)     IDENTITY_FILE="$2";    shift 2;;
    --remote-dir)        REMOTE_DIR="$2";       shift 2;;
    --mount-point)       MOUNT_POINT="$2";      shift 2;;
    --decrypted-mount)   DECRYPTED_MOUNT="$2";  shift 2;;
    --gocryptfs-keychain) GOCRYPTFS_KEYCHAIN="$2"; shift 2;;
    --borg-keychain)     BORG_KEYCHAIN="$2";    shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

LOG_FILE="/tmp/inspect_backup_$(whoami).log"
mkdir -p "$(dirname "$LOG_FILE")" "$MOUNT_POINT" "$DECRYPTED_MOUNT"
rm -f "$LOG_FILE" 2>/dev/null || true

PIPE="$(mktemp -u)"
mkfifo "$PIPE"
tee -a "$LOG_FILE" <"$PIPE" &
TEE_PID=$!
exec >"$PIPE" 2>&1

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
is_mounted() { mount | grep -q " on $1 "; }

cleanup_mounts() {
  pkill -f "sshfs.*${MOUNT_POINT}"        2>/dev/null || true
  pkill -f "gocryptfs.*${DECRYPTED_MOUNT}" 2>/dev/null || true
  sleep .2
  while is_mounted "$DECRYPTED_MOUNT"; do
    umount -f "$DECRYPTED_MOUNT" 2>/dev/null || true
    diskutil unmount force "$DECRYPTED_MOUNT" 2>/dev/null || true
  done
  while is_mounted "$MOUNT_POINT"; do
    umount -f "$MOUNT_POINT" 2>/dev/null || true
    diskutil unmount force "$MOUNT_POINT" 2>/dev/null || true
  done
}

cleanup() {
  echo "[$(timestamp)] INFO: Cleaning up…" >&2
  cleanup_mounts
  kill "$TEE_PID" 2>/dev/null || true
  rm -f "$PIPE"
  exit 1
}
error_handler() {
  echo "[$(timestamp)] ERROR: '$BASH_COMMAND' failed." >&2
  cleanup
}
trap cleanup SIGINT SIGTERM
trap error_handler ERR

echo "[$(timestamp)] INFO: Removing old mounts…"
cleanup_mounts
sleep 1

echo "[$(timestamp)] INFO: Mounting SSHFS…"
/opt/homebrew/bin/sshfs \
  -o reconnect,auto_cache,follow_symlinks,defer_permissions \
  -o ConnectTimeout=10,ServerAliveInterval=5,ServerAliveCountMax=1 \
  -o IdentityFile="$IDENTITY_FILE" \
  "${SSH_USER}@${SSH_HOST}:$REMOTE_DIR" "$MOUNT_POINT" &
SSHFS_PID=$!
wait "$SSHFS_PID"

for i in {1..10}; do
  if is_mounted "$MOUNT_POINT"; then
    echo "[$(timestamp)] INFO: SSHFS mounted at $MOUNT_POINT"
    break
  fi
  echo "[$(timestamp)] INFO: Waiting for SSHFS mount ($i/10)…"
  sleep 10
done
if ! is_mounted "$MOUNT_POINT"; then
  echo "[$(timestamp)] ERROR: SSHFS mount failed."
  cleanup
fi

if [[ ! -f "$MOUNT_POINT/gocryptfs.conf" ]]; then
  echo "[$(timestamp)] ERROR: gocryptfs.conf not found."
  cleanup
fi

echo "[$(timestamp)] INFO: Mounting gocryptfs…"
/opt/homebrew/bin/gocryptfs \
  -extpass "security find-generic-password -s $GOCRYPTFS_KEYCHAIN -w" \
  "$MOUNT_POINT" "$DECRYPTED_MOUNT" &
GOCYPTFS_PID=$!
wait "$GOCYPTFS_PID"

for i in {1..10}; do
  if is_mounted "$DECRYPTED_MOUNT"; then
    echo "[$(timestamp)] INFO: gocryptfs mounted at $DECRYPTED_MOUNT"
    break
  fi
  echo "[$(timestamp)] INFO: Waiting for gocryptfs mount ($i/10)…"
  sleep 10
done
if ! is_mounted "$DECRYPTED_MOUNT"; then
  echo "[$(timestamp)] ERROR: gocryptfs mount failed."
  cleanup
fi

echo "[$(timestamp)] INFO: Decrypted mount ready at $DECRYPTED_MOUNT"
