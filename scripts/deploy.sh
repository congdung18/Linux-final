#!/usr/bin/env bash

set -euo pipefail

show_help() {
	cat << "HELP"
Using: deploy.sh
Deploying new sources, checking syntax and permission.
Automatic rollback into the old state if found errors.

Options:
 -h, --help	Display helps
HELP
	exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	show_help
fi

SRC_DIR="${1:-/opt/myapp}"
TARGET_DIR="/opt/myapp"
BACKUP_SNAPSHOT="/tmp/deploy_snapshot_$(date +%s)"

# Start the deploy process
echo "[+] Start the safe deploy process: $(date '+%Y-%m-%d %H:%M:%S')"

# 1. Backup the current state to prevent threats
echo "[+] Step 1/5. creating snapshots storing latest safe run..."
rm -rf "${BACKUP_SNAPSHOT}"
mkdir -p "${BACKUP_SNAPSHOT}"
cp -r "${TARGET_DIR}"/* "${BACKUP_SNAPSHOT}/"

rollback() {
	local exit_code=$?
	echo "" >&2
	echo "[-] Warning: detect deploy incidents (Exit code: ${exit_code})" >&2
	echo "[-] Activating rollback ..." >&2

	cp -r "${BACKUP_SNAPSHOT}"/* "${TARGET_DIR}/"
	chown -R ubuntu:ubuntu "${TARGET_DIR}"
	chmod -R 755 "${TARGET_DIR}"

	sudo systemctl restart myapp.servic || true
	echo "[/] Successfully rolled back into the stable version" >&2
	rm -rf "${BACKUP_SNAPSHOT}"
	exit "${exit_code}"
}
trap rollback ERR

# 2. Synchronize source code into the active folder
if [[ "${SRC_DIR}" != "${TARGET_DIR}" ]]; then
	echo "[+] Step 2/5. Synchronizing source code from ${SRC_DIR}..."
	cp -r "${SRC_DIR}"/* "${TARGET_DIR}/"
fi

# 3. Initialize ownership and authorization
echo "[+] Step 3/5. Initalize safe authorization..."
chown -R ubuntu:ubuntu "${TARGET_DIR}/app.py"
chmod -R 755 "${TARGET_DIR}"

# 4. Pre-flight checks
echo "[+] Step 4/5. Pre-flight verification..."
python3 -m py_compile "${TARGET_DIR}/app.py"
echo "[/] Python syntax: valid"

sudo nginx -t
echo "[/] Nginx configuration: valid"

# 5. Restart services and smoke test
echo "[+] Step 5/5. Restart myapp.service and run smoke test API..."
sudo systemctl restart myapp.service

sleep 1
curl -sf http://127.0.0.1:5000/health > /dev/null
echo "[/] API /health response: healthy"

trap - ERR
rm -rf "${BACKUP_SNAPSHOT}"

echo "[/] Deploy successfully"
