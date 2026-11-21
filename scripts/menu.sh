#!/usr/bin/env bash

set -euo pipefail

SCRIPTS_DIR="/opt/scripts"

trap 'echo -e "\nExisting dashboard. Goodbye!"; exit 0' SIGINT

print_header() {
	clear
	echo "Operating system and automated Linux"
	echo "Host: $(hostname) | IP: $(hostname -I | awk '{print $1}') | Time: $(date '+%Y-%m-%d %H:%M:%S')"
}

show_menu() {
	echo "[1] Health check and warning"
	echo "[2] Backup database and application"
	echo "[3] Restore data from backup"
	echo "[4] Deploy safely with automated rollback"
	echo "[5] Rotate and compress logs"
	echo "[6] Scan check source code quality"
	echo "[7] Exit"
}

pause_screen() {
	echo ""
	read -rp "Press [Enter] to return to menu..." _
}

while true; do
	print_header
	show_menu
	read -rp "Choose feature [1] - [7]: " choice
	printf "\n---\n"

	case "$choice" in
		1)
			echo -e "--- [1] Health check ---"
			if [[ -x "$SCRIPTS_DIR/health_check.sh" ]]; then
				"$SCRIPTS_DIR/health_check.sh"
			else
				echo "[!] Error $SCRIPTS_DIR/health_check.sh does not exist or not authorized"
			fi
			pause_screen ;;
		2)
			echo -e "--- [2] Backup ---"
			if [[ -x "$SCRIPTS_DIR/backup.sh" ]]; then
				"$SCRIPTS_DIR/backup.sh"
			else
				echo "[!] Error $SCRIPTS_DIR/backup.sh does not exist or not authorized"
			fi
			pause_screen ;;
		3)
			echo -e "--- [3] Disaster data restore ---"
			read -rp "Input backup file needed to restore: " archive_file
			if [[ -n "$archive_file" && -x "$SCRIPTS_DIR/restore.sh" ]]; then
				"$SCRIPTS_DIR/restore.sh" "$archive_file"
			else
				echo "[!] Error: Invalid directory or no restore.sh file"
			fi
			pause_screen ;;
		4)
			echo -e "--- [4] Safe deploy with rollback ---"
			read -rp "Input source release: " release_path
			if [[ -n "$release_path" && -x "$SCRIPTS_DIR/deploy.sh" ]];
			then
				"$SCRIPTS_DIR/deploy.sh" "$release_path"
			else
				echo "[!] Error release folder is invalid or no deploy.sh file"
			fi
			pause_screen ;;
		5)
			echo -e "--- [5] Rotation and compress logs ---"
			read -rp "Input log file directory needs to be rotated: " target_log
			read -rp "Compress copies needed to store [default 5]: " keep_cnt
			keep_cnt="${keep_cnt:-5}"
			if [[ -n "$target_log" && -x "$SCRIPTS_DIR/log_rotate.sh" ]]; then
				"$SCRIPTS_DIR/log_rotate.sh" -f "$target_log" -n "$keep_cnt"
			else
				echo "[!] Error invalid information or no log_rotate.sh file"
			fi
			pause_screen ;;
		6)
			echo -e "--- [6] Scan the whole scripts by shellcheck ---"
			if command -v shellcheck >/dev/null 2>&1; then
				shellcheck "$SCRIPTS_DIR"/*.sh && echo -e "\nSuccess: all scripts in $SCRIPTS_DIR qualified 100% clean"
			else
				echo "[!] Not yet installed shellcheck (type 'sudo apt install -y shellcheck')"
			fi
			pause_screen ;;
		7)
			echo -e "Closing managing dashboard. Goodbye"
			exit 0 ;;
		*)
			echo -e "[-] Warning invalid choice: '$choice'. Only type from 1 to 7"
			sleep 2 ;;
	esac
done
