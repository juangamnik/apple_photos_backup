#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "Usage: $0 baseFolder backupFolder dateTaken creationTime modifiedTime fullFileName" >&2
  exit 1
fi

baseFolder="$1"
backupFolder="$2"
dateTaken="$3"
creationTime="$4"
modifiedTime="$5"
fullFileName="$6"

yearTaken="${dateTaken%%-*}"
destDir="$baseFolder/$backupFolder/$yearTaken/$dateTaken"
tmpDir="$baseFolder/$backupFolder/tmp"
destFile="$destDir/$fullFileName"

mkdir -p "$destDir" "$tmpDir"

# Phase 1: write to tmp
tmpFile=$(mktemp --tmpdir="$tmpDir" "${fullFileName}.XXXXXXXX")
trap 'rm -f "$tmpFile"' EXIT
cat > "$tmpFile"

# Phase 2: move atomically
mv "$tmpFile" "$destFile"
trap - EXIT

# Set metadata
touch -a -d "$creationTime" "$destFile"
touch -m -d "$modifiedTime" "$destFile"

exit 0
