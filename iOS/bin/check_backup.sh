#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
  echo "Usage: $0 baseFolder backupFolder dateTaken creationTime modifiedTime fullFileName hashSum" >&2
  exit 1
fi

baseFolder="$1"
backupFolder="$2"
dateTaken="$3"     # ISO-8601 (YYYY-MM-DD)
creationTime="$4"  # ISO-8601 with time
modifiedTime="$5"  # ISO-8601 with time
fullFileName="$6"
hashSum="$7"

yearTaken="${dateTaken%%-*}"
destFile="$baseFolder/$backupFolder/$yearTaken/$dateTaken/$fullFileName"

if [ -f "$destFile" ] && [ "$(md5sum "$destFile" | cut -d' ' -f1)" = "$hashSum" ]; then
  # adjust metadata if necessary only
  current_atime=$(stat -c %X "$destFile")
  desired_atime=$(date -d "$creationTime" +%s)
  [ "$current_atime" -ne "$desired_atime" ] && touch -a -d "$creationTime" "$destFile"

  current_mtime=$(stat -c %Y "$destFile")
  desired_mtime=$(date -d "$modifiedTime" +%s)
  [ "$current_mtime" -ne "$desired_mtime" ] && touch -m -d "$modifiedTime" "$destFile"

  echo "0"
else
  echo "1"
fi
