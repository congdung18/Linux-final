#!/usr/bin/env bash
# restore.sh - Khôi phục CSDL + mã nguồn app từ bản sao lưu của backup.sh (TV2).
# Chạy bằng root (sudo) để mariadb dùng unix_socket.
set -euo pipefail

CONFIG_FILE="${BACKUP_CONF:-/etc/backup.conf}"

# Giá trị mặc định, có thể ghi đè trong /etc/backup.conf
APP_DIR="/opt/myapp"
DB_NAME="appdb"
APP_SERVICE="myapp"

if [[ -r "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

DB_ONLY=0
ASSUME_YES=0
WORK_DIR=""

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Su dung: $0 [-d] [-y] [-h | --help] <backup_YYYYmmdd_HHMMSS.tar.gz>

  -d          Chi khoi phuc CSDL, khong ghi de thu muc app
  -y          Khong hoi xac nhan
  -h, --help  Hien thi tro giup
EOF
}

# Dọn thư mục giải nén tạm khi kết thúc (kể cả khi lỗi)
on_exit() {
    local rc=$?
    if [[ -n "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi
    if (( rc != 0 )); then
        err "Khoi phuc that bai (ma loi ${rc})"
    fi
}
trap on_exit EXIT

if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

while getopts ":dyh" opt; do
    case "${opt}" in
        d) DB_ONLY=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage; exit 0 ;;
        *) err "Tuy chon khong hop le: -${OPTARG}"; usage; exit 2 ;;
    esac
done
shift $(( OPTIND - 1 ))

if (( $# != 1 )); then
    usage
    exit 2
fi

ARCHIVE="$1"

if (( EUID != 0 )); then
    err "Hay chay bang root: sudo $0 ..."
    exit 1
fi

if [[ ! -f "${ARCHIVE}" ]]; then
    err "Khong tim thay file: ${ARCHIVE}"
    exit 1
fi

# 1. Kiểm tra toàn vẹn trước khi động vào dữ liệu đang chạy
if [[ -f "${ARCHIVE}.sha256" ]]; then
    ( cd "$(dirname "${ARCHIVE}")" && sha256sum -c --quiet "$(basename "${ARCHIVE}").sha256" )
    ok "Checksum SHA256 hop le"
else
    info "Khong co file .sha256, bo qua kiem tra checksum"
fi
tar -tzf "${ARCHIVE}" > /dev/null
ok "File nen toan ven"

if (( ASSUME_YES == 0 )); then
    read -r -p "Ghi de CSDL '${DB_NAME}' bang ban sao luu nay? Go 'yes' de tiep tuc: " answer
    if [[ "${answer}" != "yes" ]]; then
        info "Da huy"
        exit 0
    fi
fi

# 2. Giải nén vào thư mục tạm
WORK_DIR="$(mktemp -d /tmp/restore_stage.XXXXXX)"
tar -xzf "${ARCHIVE}" -C "${WORK_DIR}"

mapfile -t sql_files < <(find "${WORK_DIR}" -maxdepth 1 -type f -name '*.sql')
if (( ${#sql_files[@]} != 1 )); then
    err "Ban sao luu phai chua dung 1 file .sql (tim thay ${#sql_files[@]})"
    exit 1
fi

# 3. Nạp lại CSDL (file dump có DROP TABLE + CREATE TABLE + CREATE DATABASE)
info "Nap lai CSDL ${DB_NAME} tu $(basename "${sql_files[0]}")"
mariadb < "${sql_files[0]}"
ok "Da khoi phuc CSDL"

if rows="$(mariadb -N -e "SELECT COUNT(*) FROM items" "${DB_NAME}" 2>/dev/null)"; then
    info "Bang items hien co ${rows} ban ghi"
fi

# 4. Khôi phục thư mục app (giữ nguyên owner và quyền như lúc sao lưu)
app_name="$(basename "${APP_DIR}")"
if (( DB_ONLY == 0 )) && [[ -d "${WORK_DIR}/${app_name}" ]]; then
    info "Khoi phuc ma nguon app vao ${APP_DIR}"
    mkdir -p "${APP_DIR}"
    cp -a "${WORK_DIR}/${app_name}/." "${APP_DIR}/"
    if systemctl is-active --quiet "${APP_SERVICE}"; then
        systemctl restart "${APP_SERVICE}"
        ok "Da restart ${APP_SERVICE}"
    fi
fi

ok "Hoan tat khoi phuc"
