#!/usr/bin/env bash
# newest_or_date.sh: Outputs the later of two dates — either the newest modification time of any file
# in the given directory (recursively), or the optional passed date (YYYY-MM-DD). Fallback: 1970-01-01.

set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $0 <directory> [YYYY-MM-DD]" >&2
  exit 1
fi

dir="$1"

# Check if the directory exists
if [ ! -d "$dir" ]; then
  echo "Error: '$dir' is not a directory." >&2
  exit 2
fi

# Optional second date in seconds since Epoch
if [ $# -eq 2 ]; then
  date_str="$2"
  if ! second_epoch=$(date -d "$date_str" +%s 2>/dev/null); then
    echo "Error: Invalid date format '$date_str'." >&2
    exit 3
  fi
fi

# Disable pipefail temporarily to avoid SIGPIPE exit codes from head
set +o pipefail
latest_epoch=$(find "$dir" -type f -printf '%T@ %p\n' \
               | sort -nr \
               | head -n1 \
               | awk '{print int($1)}')
set -o pipefail

# Determine the later of the two timestamps, or fallback to 1970-01-01
if [ -n "${latest_epoch:-}" ] && [ -n "${second_epoch:-}" ]; then
  if (( latest_epoch >= second_epoch )); then
    chosen_epoch=$latest_epoch
  else
    chosen_epoch=$second_epoch
  fi
elif [ -n "${latest_epoch:-}" ]; then
  chosen_epoch=$latest_epoch
elif [ -n "${second_epoch:-}" ]; then
  chosen_epoch=$second_epoch
else
  chosen_epoch=0
fi

# Output in ISO 8601 format with time and timezone
date -d "@$chosen_epoch" --iso-8601=seconds
