#!/usr/bin/env bash
# Script: backup.sh - backup database and website data into VM 2

set -euo pipefail

# Show help function
show_help() {
	cat << "HELP"
Using: backup.sh
Backing up MariaDB and website data, storing locally and synchronizing into VM2

Options:
 -h, --help	Printing help 
HELP
	exit 0
}

# Handling input arguments
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	show_help
fi

# Error handling
trap 'echo "[!] Error: synchronizing process failed at line $LINENO" >&2;
exit 1' ERR

BACKUP_DIR="/mnt/data_backup"
REMOTE_USER="ubuntu"
REMOTE_HOST="192.168.122.12"
REMOTE_DEST_DIR="/home/ubuntu/remote_backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_DUMP="/tmp/db_dump_${TIMESTAMP}.sql"
ARCHIVE_NAME="backup_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

echo "[+] Starting to backing up system: ${TIMESTAMP}"

# 1. Checking available storage before synchronize
AVAIL_STORE_KB=$(df "${BACKUP_DIR}" | awk 'NR==2 {print $4}')
if [[ "${AVAIL_STORE_KB}" -lt 51200 ]]; then
	echo "[-] Warning: back up disk is almost full!" >&2
	exit 1
fi

# 2. Dump the database
echo "[+] Step 1/4. Dumping database..."
mysqldump -u root appdb > "${TEMP_DUMP}"

# 3. Packaging and compressing: database, source code and web static content
echo "[+] Step 2/4. Compressing data into ${ARCHIVE_NAME}..."
tar -czf "${ARCHIVE_PATH}" \
-C /tmp "db_dump_${TIMESTAMP}.sql" \
-C /opt myapp \
-C /var/www status
rm -rf "${TEMP_DUMP}"
echo "[/] Created back up at: ${ARCHIVE_PATH}"

# 4. Applying retention policy: removing backups older than 7 days
echo "[+] Step 3/4. Applying rentention policy: removing backups older than 7 days..."
DELETED_COUNT=$(find "${BACKUP_DIR}" -type f -name "backup_*.tar.gz" -mtime +7 -print -delete | wc -l)
echo "[/] Removed ${DELETED_COUNT} old backups."

# 5. Synchronizing into VM 2 by rsync through SSH
echo "[+] Step 4/4. Synchronizing into VM 2 (${REMOTE_HOST})..."
if ping -c 1 -W 2 "${REMOTE_HOST}" > /dev/null 2>&1; then
	rsync -avz -e "ssh -p 2222 -o StrictHostKeyChecking=no -o ConnectTimeout=5" \
"${BACKUP_DIR}/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DEST_DIR}/" || {
echo "[-] Warning: cannont rsync into VM 2, keeping the local version." >&2
}
else
	echo "[!] Error: VM 2 is not responding, skipping rsync."
fi

echo "[/] Successfully backup: ${ARCHIVE_NAME}"
