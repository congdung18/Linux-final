#!/usr/bin/env bash
# Script: restore.sh - restore system from backups

set -euo pipefail

show_help() {
	cat << "HELP"
Using: restore.sh <backup_directory.tar.gz>
Restoring all MariaDB database and web data from backup.

Example:
 restore.sh /mnt/data_backup/backup_20000101_093000.tar.gz
HELP
	exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]]; then
	show_help
fi

ARCHIVE="$1"
RESTORE_TEMP="/tmp/restore_workspace"

# Error handling
trap 'echo "[!] Error: restoring process failed!" >&2; rm -rf "${RESTORE_TEMP}"; exit 1' ERR

if [[ ! -f "${ARCHIVE}" ]]; then
	echo "[!] Error: cannot find back up file: ${ARCHIVE}" >&2
	exit 1
fi

echo "[+] Starting disaster recovery from: ${ARCHIVE}"

# 1. Decompress into temporary folder
rm -rf "${RESTORE_TEMP}"
mkdir -p "${RESTORE_TEMP}"
echo "[+] Step 1/3. Decompressing backup..."
tar -xzf "${ARCHIVE}" -C "${RESTORE_TEMP}"

# 2. Restore database
echo "[+] Step 2/3. Restoring database..."
SQL_FILE=$(find "${RESTORE_TEMP}" -type f -name "db_dump_*.sql" | head -n 1)
if [[ -n "${SQL_FILE}" && -f "${SQL_FILE}" ]]; then
	mariadb -u root appdb < "${SQL_FILE}"
	echo "[/] Restored SQL successfully into database."
else
	echo "[-] Warning: cannot find dump SQL in backup" >&2
fi

# 3. Restore source code and web static data
echo "[+] Step 3/3. Restoring source code and web resources..."
if [[ -d "${RESTORE_TEMP}/myapp" ]]; then
	cp -r "${RESTORE_TEMP}/myapp"/* /opt/myapp/
	chown -R ubuntu:ubuntu /opt/myapp
	chmod -R 755 /opt/myapp
fi

if [[ -d "${RESTORE_TEMP}/status" ]]; then
	cp -r "${RESTORE_TEMP}/status"/* /var/www/status/
	chown -R ubuntu:ubuntu /opt/myapp
	chmod -R 755 /opt/myapp
	chown -R www-data:www-data /var/www/status
fi

# Restart to apply changes
sudo systemctl restart myapp.service
sudo systemctl reload nginx

# Clean up
rm -rf "${RESTORE_TEMP}"

echo "[/] Restore system successfully"
