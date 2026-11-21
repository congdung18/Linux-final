#!/usr/bin/env bash

set -euo pipefail

trap 'echo "[!] Error: log rotation failed at $LINENO" >&2' ERR

LOG_FILE=""
KEEP_COUNT=5

usage() {
	cat << "EOF"
Usage: log_rotate.sh -f <log_file> [-n <keep_count>]

Options:
 -f <path>	Path to the target log file to rotate (required)
 -n <number>	Number of compressed archives to retain (default: 5)
 -h, --help	Display this help message
EOF
	exit 0
}

# Parse options
while getopts "f:n:h-:" opt; do
	case "$opt" in
		f) LOG_FILE="$OPTARG" ;;
		n) KEEP_COUNT="$OPTARG" ;;
		h) usage ;;
		-)
			case "$OPTARG" in
				help) usage ;;
				*) echo "[!] Error: unknown option --$OPTARG" >&2; exit 1 ;;
			esac
			;;
		*) usage ;;
	esac
done

if [[ -z "$LOG_FILE" ]]; then
	echo "[!] Error: missing target log file. Use -f <path>" >&2
	usage
fi

if [[ ! -f "$LOG_FILE" ]]; then
	echo "[!] Error: target file does not exist: $LOG_FILE" >&2
	exit 1
fi

if ! [[ "$KEEP_COUNT" =~ ^[1-9][0-9]*$ ]]; then
	echo "[!] Error: invalid retain count: $KEEP_COUNT (must be integer >= 1)" >&2
	exit 1
fi

echo "[+] Starting log rotation for: $LOG_FILE (Retain: $KEEP_COUNT versions)"

# 1. Purge old activities
for (( i = KEEP_COUNT; i <= KEEP_COUNT + 10; i++ )); do
	old_archive="${LOG_FILE}.${i}.gz"
	if [[ -f "$old_archive" ]]; then
		rm -f "$old_archive"
		echo "Purged expired archive: $old_archive"
	fi
done

# 2. Shift existing compressed archives upwards
for (( i = KEEP_COUNT - 1; i >= 1; i-- )); do
	current="${LOG_FILE}.${i}.gz"
	next="${LOG_FILE}.$(( i + 1 )).gz"
	if [[ -f "$current" ]]; then
		mv "$current" "$next"
	fi
done

# 3. Rotate and compress current log file
if [[ -s "$LOG_FILE" ]]; then
	target_archive="${LOG_FILE}.1"
	cp "$LOG_FILE" "$target_archive"
	gzip -f "$target_archive"

	cat /dev/null > "$LOG_FILE"
	chmod 644 "$LOG_FILE"
	echo "Successfully rotated to ${LOG_FILE}.1.gz and reset active log file"
else
	echo "Target log file is empty, skipping rotation"
fi
