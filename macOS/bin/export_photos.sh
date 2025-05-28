#!/usr/bin/env bash
# export_photos.sh
set -euo pipefail

VERSION="1.0.0"

if [[ "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options (override values from photos_backup.conf):
  --date-threshold YYYY-MM-DD
                            Only export photos taken or modified after this date
  --export-dir PATH         Destination directory for exported photos
  --help                    Show this help text and exit
  --version                 Show script version and exit

This script uses osxphotos to export photos filtered by a given date threshold.
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
    --date-threshold) DATE_THRESHOLD="$2"; shift 2;;
    --export-dir)     EXPORT_DIR="$2"; shift 2;;
    *) echo "Usage: $0 [--date-threshold YYYY-MM-DD] [--export-dir DIR]"; exit 1;;
  esac
done

EXPORT_DIR="${EXPORT_DIR:-$LOCAL_EXPORT_DIR}"

if ! [[ "$DATE_THRESHOLD" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: --date-threshold must be in YYYY-MM-DD format."; exit 2
fi

DATE_EXPR=$(echo "$DATE_THRESHOLD" | awk -F- '{printf "datetime(%d, %d, %d, tzinfo=timezone.utc)", $1, $2, $3}')

mkdir -p "$EXPORT_DIR"
export TMPDIR=/tmp

echo "Exporting photos taken or modified since $DATE_THRESHOLD to $EXPORT_DIR"
"$SCRIPT_DIR/osxphotos.sh" export "$EXPORT_DIR" \
  --sidecar xmp \
  --export-aae \
  --download-missing \
  --update \
  --directory "{created.year}/{created.mm}/{created.dd}" \
  --query-eval "(photo.date and photo.date > $DATE_EXPR) or (photo.date_modified and photo.date_modified > $DATE_EXPR)" \
  --cleanup
