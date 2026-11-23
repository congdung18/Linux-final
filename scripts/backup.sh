#!/usr/bin/env bash
# backup.sh - Sao lưu CSDL + mã nguồn app (TV2).
# Dump CSDL, nén cùng thư mục app kèm timestamp, áp dụng retention,
# đồng bộ sang srv-backup bằng rsync qua SSH key.
# Chạy bằng root (sudo) để mysqldump dùng unix_socket, không cần mật khẩu.
set -euo pipefail

CONFIG_FILE="${BACKUP_CONF:-/etc/backup.conf}"

# Giá trị mặc định, có thể ghi đè trong /etc/backup.conf
BACKUP_DIR="/mnt/data_backup"
APP_DIR="/opt/myapp"
DB_NAME="appdb"
RETENTION_DAYS=7
REMOTE_USER="ubuntu"
REMOTE_HOST=""
REMOTE_PORT=2222
REMOTE_DIR="/home/ubuntu/backups"
SSH_KEY="/root/.ssh/id_backup"
LOCK_FILE="/var/lock/backup.lock"

if [[ -r "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

SKIP_REMOTE=0
STAGING_DIR=""
PARTIAL_FILE=""

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Su dung: $0 [-d SO_NGAY] [-s] [-h | --help]

  -d SO_NGAY  So ngay luu giu ban sao luu (mac dinh: ${RETENTION_DAYS})
  -s          Bo qua buoc rsync sang srv-backup (chi sao luu cuc bo)
  -h, --help  Hien thi tro giup

Cau hinh doc tu ${CONFIG_FILE} (xem configs/backup/backup.conf.example).
EOF
}

# Dọn thư mục tạm và file nén dở dang nếu script bị lỗi giữa chừng
on_exit() {
    local rc=$?
    if [[ -n "${STAGING_DIR}" ]]; then
        rm -rf "${STAGING_DIR}"
    fi
    if (( rc != 0 )); then
        if [[ -n "${PARTIAL_FILE}" ]]; then
            rm -f "${PARTIAL_FILE}" "${PARTIAL_FILE}.sha256"
        fi
        err "Sao luu that bai (ma loi ${rc})"
    fi
}
trap on_exit EXIT

if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

while getopts ":d:sh" opt; do
    case "${opt}" in
        d) RETENTION_DAYS="${OPTARG}" ;;
        s) SKIP_REMOTE=1 ;;
        h) usage; exit 0 ;;
        :) err "Tuy chon -${OPTARG} can co gia tri"; usage; exit 2 ;;
        *) err "Tuy chon khong hop le: -${OPTARG}"; usage; exit 2 ;;
    esac
done

if ! [[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
    err "SO_NGAY phai la so nguyen khong am"
    exit 2
fi

if (( EUID != 0 )); then
    err "Hay chay bang root: sudo $0"
    exit 1
fi

# Chặn ghi nhầm vào phân vùng gốc nếu /dev/vdb chưa được mount
if ! mountpoint -q "${BACKUP_DIR}"; then
    err "${BACKUP_DIR} chua duoc mount (kiem tra /etc/fstab, lenh: mount -a)"
    exit 1
fi

if [[ ! -d "${APP_DIR}" ]]; then
    err "Khong tim thay thu muc app: ${APP_DIR}"
    exit 1
fi

if (( SKIP_REMOTE == 0 )) && [[ -z "${REMOTE_HOST}" ]]; then
    err "Chua dat REMOTE_HOST trong ${CONFIG_FILE} (hoac dung -s de bo qua rsync)"
    exit 1
fi

# Không cho hai tiến trình sao lưu chạy chồng nhau (cron/timer + chạy tay)
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    err "Mot tien trinh sao luu khac dang chay"
    exit 1
fi

TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
ARCHIVE_NAME="backup_${TIMESTAMP}.tar.gz"
ARCHIVE="${BACKUP_DIR}/${ARCHIVE_NAME}"
SQL_NAME="${DB_NAME}_${TIMESTAMP}.sql"
STAGING_DIR="$(mktemp -d /tmp/backup_stage.XXXXXX)"

info "Bat dau sao luu: ${TIMESTAMP}"

# 1. Dump CSDL (--databases để file dump có cả CREATE DATABASE;
#    --single-transaction để dữ liệu nhất quán mà không khóa bảng)
mysqldump --single-transaction --routines --triggers \
    --databases "${DB_NAME}" > "${STAGING_DIR}/${SQL_NAME}"

if [[ ! -s "${STAGING_DIR}/${SQL_NAME}" ]]; then
    err "File dump rong"
    exit 1
fi
ok "Da dump CSDL ${DB_NAME}"

# 2. Kiểm tra dung lượng trống trước khi nén (tránh làm đầy đĩa giữa chừng)
need=$(( $(stat -c %s "${STAGING_DIR}/${SQL_NAME}") + $(du -sb "${APP_DIR}" | cut -f1) ))
avail="$(df --output=avail -B1 "${BACKUP_DIR}" | tail -n 1 | tr -d ' ')"
if (( avail < need )); then
    err "Khong du dung luong tren ${BACKUP_DIR}: can toi da ${need} byte, con ${avail} byte"
    exit 1
fi

# 3. Nén CSDL + mã nguồn app
PARTIAL_FILE="${ARCHIVE}"
tar -czf "${ARCHIVE}" \
    --exclude='__pycache__' \
    -C "${STAGING_DIR}" "${SQL_NAME}" \
    -C "$(dirname "${APP_DIR}")" "$(basename "${APP_DIR}")"

# 4. Kiểm tra toàn vẹn file nén và ghi checksum
tar -tzf "${ARCHIVE}" > /dev/null
( cd "${BACKUP_DIR}" && sha256sum "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256" )
PARTIAL_FILE=""
ok "Da tao ban sao luu: ${ARCHIVE} ($(du -h "${ARCHIVE}" | cut -f1))"

# 5. Retention: xóa bản sao lưu cũ hơn RETENTION_DAYS ngày
info "Retention: xoa ban sao luu cu hon ${RETENTION_DAYS} ngay"
find "${BACKUP_DIR}" -maxdepth 1 -type f \
    \( -name 'backup_*.tar.gz' -o -name 'backup_*.tar.gz.sha256' \) \
    -mtime +"${RETENTION_DAYS}" -print -delete

# 6. Đồng bộ sang srv-backup (chỉ gửi file backup_*, --delete để VM 2 cũng
#    xóa các bản đã hết hạn; file khác như lost+found không bị đụng tới)
if (( SKIP_REMOTE == 1 )); then
    info "Bo qua rsync (-s)"
else
    info "Rsync sang ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
    rsync -rtz --partial --mkpath --delete \
        --include='backup_*.tar.gz' --include='backup_*.tar.gz.sha256' \
        --exclude='*' \
        -e "ssh -p ${REMOTE_PORT} -i ${SSH_KEY} -o BatchMode=yes -o StrictHostKeyChecking=yes" \
        "${BACKUP_DIR}/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"
    ok "Da dong bo sang srv-backup"
fi

ok "Hoan tat sao luu"
