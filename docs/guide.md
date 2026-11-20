# HƯỚNG DẪN THỰC HIỆN CHI TIẾT TỪNG BƯỚC (END-TO-END LAB GUIDE)
**Đồ án:** Hệ điều hành Linux & Ứng dụng — ĐHQG-HCM, Trường ĐH Khoa học Tự nhiên  
**Tài liệu tham chiếu:** [Do_An_Thuc_Hanh_Linux.pdf](file:///home/archlinux/Downloads/Do_An_Thuc_Hanh_Linux.pdf)  
**Phân công vai trò:** [PHAN_CONG_CONG_VIEC.md](../PHAN_CONG_CONG_VIEC.md)

---

## MỤC LỤC
1. [GIAI ĐOẠN 1: Hạ Tầng 2 VM, Mạng & Lưu Trữ (Thành viên 1)](#giai-đoạn-1-hạ-tầng-2-vm-mạng--lưu-trữ-thành-viên-1)
2. [GIAI ĐOẠN 2: Cơ Sở Dữ Liệu & Sao Lưu / Khôi Phục (Thành viên 2)](#giai-đoạn-2-cơ-sở-dữ-liệu--sao-lưu--khôi-phục-thành-viên-2)
3. [GIAI ĐOẠN 3: Ứng Dụng Backend & Quản Trị Systemd (Thành viên 3)](#giai-đoạn-3-ứng-dụng-backend--quản-trị-systemd-thành-viên-3)
4. [GIAI ĐOẠN 4: Web Proxy Nginx, TLS/HTTPS & An Ninh Phòng Thủ (Thành viên 4)](#giai-đoạn-4-web-proxy-nginx-tlshttps--an-ninh-phòng-thủ-thành-viên-4)
5. [GIAI ĐOẠN 5: Bộ Công Cụ Vận Hành CLI & Giám Sát (Thành viên 5)](#giai-đoạn-5-bộ-công-cụ-vận-hành-cli--giám-sát-thành-viên-5)
6. [GIAI ĐOẠN 6: Kịch Bản Diễn Tập Demo Trực Tiếp (12–15 Phút)](#giai-đoạn-6-kịch-bản-diễn-tập-demo-trực-tiếp-1215-phút)
7. [GIAI ĐOẠN 7: Đóng Gói Sản Phẩm Nộp Báo Cáo](#giai-đoạn-7-đóng-gói-sản-phẩm-nộp-báo-cáo)

---

## GIAI ĐOẠN 1: Hạ Tầng 2 VM, Mạng & Lưu Trữ (Thành viên 1)

### 1.1 Tạo 2 Máy Ảo bằng KVM/QEMU (Ubuntu 22.04 LTS Server)
Thực hiện trên máy thật (Host Linux):
```bash
cd ~/vms

# 1. Tạo 2 đĩa ảo qcow2 từ file Ubuntu 22.04 Cloud Image (kế thừa Copy-on-Write)
qemu-img create -f qcow2 -F qcow2 -b ubuntu-22.04-server-cloudimg-amd64.img srv-main.qcow2 20G
qemu-img create -f qcow2 -F qcow2 -b ubuntu-22.04-server-cloudimg-amd64.img srv-backup.qcow2 20G

# 2. Khởi động VM 1: srv-main (2 vCPU, 2GB RAM)
sudo virt-install \
  --name srv-main \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/home/archlinux/vms/srv-main.qcow2,bus=virtio \
  --os-variant ubuntu22.04 \
  --network network=default,model=virtio \
  --cloud-init user-data=/home/archlinux/vms/user-data.yaml \
  --graphics none \
  --import

# 3. Khởi động VM 2: srv-backup (1 vCPU, 1GB RAM)
sudo virt-install \
  --name srv-backup \
  --ram 1024 \
  --vcpus 1 \
  --disk path=/home/archlinux/vms/srv-backup.qcow2,bus=virtio \
  --os-variant ubuntu22.04 \
  --network network=default,model=virtio \
  --cloud-init user-data=/home/archlinux/vms/user-data-backup.yaml \
  --graphics none \
  --import
```
*(Thoát màn hình text console của máy ảo về lại máy thật: nhấn `Ctrl + ]`)*.

### 1.2 Gắn Đĩa Ảo Phụ & Cấu Hình Tự Động Mount qua `/etc/fstab` (trên `srv-main`)
Đề bài yêu cầu: *Có vùng dữ liệu/sao lưu riêng mount qua `/etc/fstab`, tồn tại sau reboot*.

1. **Trên máy Host (Arch Linux):**
   ```bash
   # Tạo ổ phụ 10GB và gắn nóng vào srv-main
   qemu-img create -f qcow2 /home/archlinux/vms/srv-main-data.qcow2 10G
   sudo virsh attach-disk srv-main \
     --source /home/archlinux/vms/srv-main-data.qcow2 \
     --target vdb \
     --persistent \
     --subdriver qcow2
   ```

2. **Bên trong máy ảo `srv-main`:**
   ```bash
   # Định dạng ext4 cho /dev/vdb
   sudo mkfs.ext4 /dev/vdb

   # Tạo thư mục mount
   sudo mkdir -p /mnt/data_backup

   # Lấy UUID chuẩn và ghi vào /etc/fstab
   UUID_VAL=$(sudo blkid -s UUID -o value /dev/vdb)
   echo "UUID=$UUID_VAL /mnt/data_backup ext4 defaults 0 2" | sudo tee -a /etc/fstab

   # Mount và kiểm tra
   sudo mount -a
   lsblk -f
   ```

### 1.3 Gia Cố SSH & Thiết Lập Tường Lửa UFW (trên `srv-main`)
1. **Gia cố SSH (`/etc/ssh/sshd_config`):**
   ```bash
   sudo nano /etc/ssh/sshd_config
   ```
   Cấu hình các dòng:
   ```text
   Port 2222
   PermitRootLogin no
   PubkeyAuthentication yes
   PasswordAuthentication yes
   AllowUsers ubuntu
   ```
   Restart SSH: `sudo systemctl restart ssh`.

2. **Thiết lập UFW Tường lửa (Default Deny Incoming):**
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow 2222/tcp comment 'SSH Custom'
   sudo ufw allow 80/tcp comment 'HTTP'
   sudo ufw allow 443/tcp comment 'HTTPS'
   sudo ufw --force enable
   sudo ufw status verbose
   ```

---

## GIAI ĐOẠN 2: Cơ Sở Dữ Liệu & Sao Lưu / Khôi Phục (Thành viên 2)

### 2.1 Cài Đặt MariaDB & Phân Quyền Đặc Quyền Tối Thiểu (Least Privilege)
1. Cài đặt MariaDB trên `srv-main`:
   ```bash
   sudo apt update && sudo apt install mariadb-server -y
   ```
2. Đảm bảo CSDL **chỉ nghe trên `127.0.0.1`**:
   Kiểm tra trong `/etc/mysql/mariadb.conf.d/50-server.cnf` có dòng:
   ```text
   bind-address = 127.0.0.1
   ```
   Kiểm chứng: `ss -tulpn | grep 3306` (phải thấy `127.0.0.1:3306`).

3. Khởi tạo Database và User ứng dụng:
   ```bash
   sudo mariadb
   ```
   Chạy các câu lệnh SQL:
   ```sql
   CREATE DATABASE IF NOT EXISTS appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   USE appdb;
   CREATE TABLE IF NOT EXISTS items (
       id INT AUTO_INCREMENT PRIMARY KEY,
       name VARCHAR(255) NOT NULL,
       created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   INSERT INTO items (name) VALUES ('Ban ghi khoi tao mac dinh');

   -- NGUYÊN TẮC ĐẶC QUYỀN TỐI THIỂU: Chỉ cấp quyền SELECT, INSERT
   CREATE USER 'appuser'@'localhost' IDENTIFIED BY 'StudentAppPassword123!';
   GRANT SELECT, INSERT ON appdb.* TO 'appuser'@'localhost';
   FLUSH PRIVILEGES;
   EXIT;
   ```

### 2.2 Viết Script Sao Lưu Tự Động (`scripts/backup.sh`)
Đề bài yêu cầu: *Dump CSDL + nội dung web, nén kèm timestamp, chính sách lưu giữ (retention xóa bản > 7 ngày), và rsync sang VM 2*.

Tạo file `/opt/scripts/backup.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/mnt/data_backup"
REMOTE_USER="ubuntu"
REMOTE_HOST="192.168.122.x" # IP của srv-backup
REMOTE_DIR="/home/ubuntu/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TAR_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.tar.gz"
TEMP_SQL="/tmp/appdb_${TIMESTAMP}.sql"

echo "[+] Bat dau quy trinh sao luu: ${TIMESTAMP}"

# 1. Dump database
mysqldump -u root appdb > "${TEMP_SQL}"

# 2. Dong goi nén CSDL + Ma nguon web/app
tar -czf "${TAR_FILE}" -C /tmp "appdb_${TIMESTAMP}.sql" -C /opt myapp
rm -f "${TEMP_SQL}"

echo "[+] Da tao ban sao luu: ${TAR_FILE}"

# 3. Chinh sach luu giu (Retention): Xoa ban sao luu cu hon 7 ngay
find "${BACKUP_DIR}" -name "backup_*.tar.gz" -mtime +7 -delete

# 4. Dong bo sang VM 2 (srv-backup) qua rsync
rsync -avz -e "ssh -p 2222 -o StrictHostKeyChecking=no" "${BACKUP_DIR}/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"

echo "[✓] Sao luu va dong bo sang VM 2 thanh cong!"
```

### 2.3 Viết Script Khôi Phục Thảm Họa (`scripts/restore.sh`)
Đề bài yêu cầu: *Phục hồi CSDL/nội dung từ bản sao lưu do chính bộ công cụ tạo ra*.

Tạo file `/opt/scripts/restore.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Su dung: $0 <duong_dan_file_backup.tar.gz>"
    exit 1
fi

BACKUP_ARCHIVE="$1"
TEMP_RESTORE_DIR="/tmp/restore_temp"

if [ ! -f "${BACKUP_ARCHIVE}" ]; then
    echo "Loi: Khong tim thay file ${BACKUP_ARCHIVE}"
    exit 1
fi

echo "[+] Bat dau khoi phuc tu ${BACKUP_ARCHIVE}..."
mkdir -p "${TEMP_RESTORE_DIR}"
tar -xzf "${BACKUP_ARCHIVE}" -C "${TEMP_RESTORE_DIR}"

# 1. Khoi phuc database
SQL_FILE=$(find "${TEMP_RESTORE_DIR}" -name "*.sql" | head -n 1)
if [ -n "${SQL_FILE}" ]; then
    echo "[+] Nap lai du lieu vao MariaDB..."
    mariadb -u root appdb < "${SQL_FILE}"
fi

# 2. Khoi phuc thu muc app (neu can)
if [ -d "${TEMP_RESTORE_DIR}/myapp" ]; then
    echo "[+] Khoi phuc ma nguon app..."
    cp -r "${TEMP_RESTORE_DIR}/myapp" /opt/
fi

rm -rf "${TEMP_RESTORE_DIR}"
echo "[✓] Phuc hoi he thong thanh cong!"
```

---

## GIAI ĐOẠN 3: Ứng Dụng Backend & Quản Trị Systemd (Thành viên 3)

### 3.1 Cài Thư Viện & Tạo File Bí Mật (`/etc/myapp/app.env`)
```bash
sudo apt install python3-flask python3-pymysql -y

sudo mkdir -p /etc/myapp
sudo tee /etc/myapp/app.env > /dev/null << 'EOF'
DB_HOST=127.0.0.1
DB_NAME=appdb
DB_USER=appuser
DB_PASS=StudentAppPassword123!
APP_PORT=5000
EOF

# SIẾT CHẶT PHÂN QUYỀN (chmod 600 - không hard-code)
sudo chown ubuntu:ubuntu /etc/myapp/app.env
sudo chmod 600 /etc/myapp/app.env
```

### 3.2 Viết Mã Nguồn Flask App (`/opt/myapp/app.py`)
```python
import os
import pymysql
from flask import Flask, jsonify, request

app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
DB_NAME = os.getenv("DB_NAME")
APP_PORT = int(os.getenv("APP_PORT", 5000))

def get_db_connection():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor
    )

# Endpoint Đọc (GET)
@app.route("/", methods=["GET"])
@app.route("/api/items", methods=["GET"])
def get_items():
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute("SELECT id, name, created_at FROM items ORDER BY id DESC")
        items = cursor.fetchall()
    conn.close()
    return jsonify({"status": "success", "data": items}), 200

# Endpoint Ghi (POST)
@app.route("/api/items", methods=["POST"])
def create_item():
    data = request.get_json(silent=True) or {}
    name = data.get("name") or request.form.get("name")
    if not name:
        return jsonify({"status": "error", "message": "Missing 'name'"}), 400

    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute("INSERT INTO items (name) VALUES (%s)", (name,))
        conn.commit()
        new_id = cursor.lastrowid
    conn.close()
    return jsonify({"status": "success", "id": new_id, "name": name}), 201

# Endpoint Healthcheck
@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=APP_PORT)
```

### 3.3 Đóng Gói Dịch Vụ Systemd (`/etc/systemd/system/myapp.service`)
```ini
[Unit]
Description=Flask Backend Service
After=network.target mariadb.service
Wants=mariadb.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/myapp
EnvironmentFile=/etc/myapp/app.env
ExecStart=/usr/bin/python3 /opt/myapp/app.py
Restart=on-failure
RestartSec=3s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```
Kích hoạt:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myapp.service
sudo systemctl status myapp.service
```

---

## GIAI ĐOẠN 4: Web Proxy Nginx, TLS/HTTPS & An Ninh Phòng Thủ (Thành viên 4)

### 4.1 Sinh Chứng Chỉ TLS Tự Ký bằng OpenSSL
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/lab-selfsigned.key \
  -out /etc/ssl/certs/lab-selfsigned.crt \
  -subj "/C=VN/ST=HCMC/O=HCMUS-Lab/CN=lab.local"
```

### 4.2 Cấu Hình 2 Virtual Hosts trên Nginx
Cài Nginx: `sudo apt install nginx -y`.

1. **VHost 1: Reverse Proxy App (`/etc/nginx/sites-available/app.conf`):**
   ```nginx
   server {
       listen 80;
       server_name app.linux.local;
       return 301 https://$host$request_uri;
   }

   server {
       listen 443 ssl;
       server_name app.linux.local;

       ssl_certificate /etc/ssl/certs/lab-selfsigned.crt;
       ssl_certificate_key /etc/ssl/private/lab-selfsigned.key;
       ssl_protocols TLSv1.2 TLSv1.3;

       location / {
           proxy_pass http://127.0.0.1:5000;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

2. **VHost 2: Trang tĩnh (`/etc/nginx/sites-available/status.conf`):**
   ```nginx
   server {
       listen 80;
       server_name status.linux.local;
       return 301 https://$host$request_uri;
   }

   server {
       listen 443 ssl;
       server_name status.linux.local;

       ssl_certificate /etc/ssl/certs/lab-selfsigned.crt;
       ssl_certificate_key /etc/ssl/private/lab-selfsigned.key;
       ssl_protocols TLSv1.2 TLSv1.3;

       root /var/www/status;
       index index.html;
       location / { try_files $uri $uri/ =404; }
   }
   ```
   Tạo thư mục & phân quyền an toàn:
   ```bash
   sudo mkdir -p /var/www/status
   echo "<h1>System Status: ALL SERVICES OPERATIONAL (VHost 2)</h1>" | sudo tee /var/www/status/index.html
   sudo chown -R www-data:www-data /var/www/status
   sudo chmod -R 755 /var/www/status
   ```

3. Kích hoạt & reload:
   ```bash
   sudo rm -f /etc/nginx/sites-enabled/default
   sudo ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/
   sudo ln -sf /etc/nginx/sites-available/status.conf /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl reload nginx
   ```

### 4.3 Cấu Hình Fail2ban & Auditd
1. **Fail2ban (`/etc/fail2ban/jail.local`):**
   ```ini
   [DEFAULT]
   bantime = 10m
   findtime = 5m
   maxretry = 3

   [sshd]
   enabled = true
   port = 2222
   mode = aggressive
   logpath = %(sshd_log)s
   backend = systemd
   ```
   Bật service: `sudo systemctl enable --now fail2ban`.

2. **Auditd (`/etc/audit/rules.d/audit.rules`):**
   ```text
   -w /etc/passwd -p wa -k sensitive_auth_changes
   -w /etc/shadow -p wa -k sensitive_auth_changes
   ```
   Nạp rule: `sudo augenrules --load && sudo systemctl restart auditd`.

---

## GIAI ĐOẠN 5: Bộ Công Cụ Vận Hành CLI & Giám Sát (Thành viên 5)

Tất cả các script đặt trong `/opt/scripts/` và tuân thủ: `set -euo pipefail`, bẫy `trap`, và **vượt qua 100% `shellcheck`**.

### 5.1 Script Kiểm Tra Sức Khỏe & Cảnh Báo (`health_check.sh`)
```bash
#!/usr/bin/env bash
set -euo pipefail

CPU_THRESHOLD=80
MEM_THRESHOLD=85
DISK_THRESHOLD=80
LOG_FILE="/var/log/system_health.log"

send_alert() {
    local msg="$1"
    echo "$(date): ALERT - ${msg}" | tee -a "${LOG_FILE}"
    # Có thể kết nối bot Telegram Webhook tại đây:
    # curl -s -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" -d "chat_id=<ID>&text=${msg}" > /dev/null || true
}

# 1. Kiem tra Disk
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "${DISK_USAGE}" -gt "${DISK_THRESHOLD}" ]; then
    send_alert "Dung luong o dia vuot nguong: ${DISK_USAGE}%"
fi

# 2. Kiem tra RAM
MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
if [ "${MEM_USAGE}" -gt "${MEM_THRESHOLD}" ]; then
    send_alert "Bo nho RAM vuot nguong: ${MEM_USAGE}%"
fi

# 3. Kiem tra trang thai dich vu
for srv in nginx mariadb myapp; do
    if ! systemctl is-active --quiet "${srv}"; then
        send_alert "Dich vu ${srv} bi dung bat thuong!"
    fi
done

echo "Health check hoan tat luc $(date)" >> "${LOG_FILE}"
```

### 5.2 Script Triển Khai An Toàn có Rollback (`deploy.sh`)
```bash
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/myapp"
BACKUP_DIR="/tmp/app_backup_deploy"

echo "[+] Bat dau quy trinh Deploy..."

# 1. Sao luu ban hien tai phong ngua rui ro
rm -rf "${BACKUP_DIR}" && mkdir -p "${BACKUP_DIR}"
cp -r "${APP_DIR}"/* "${BACKUP_DIR}/"

# 2. Thu cap nhat va kiem tra loi
trap 'echo "[!] Phat hien loi! Dang tu dong Rollback ve trang thai cu..."; cp -r "${BACKUP_DIR}"/* "${APP_DIR}/"; sudo systemctl restart myapp; echo "[✓] Da Rollback an toan."; exit 1' ERR

echo "[+] Nạp cấu hình mới và kiểm tra cú pháp Nginx..."
sudo nginx -t

echo "[+] Khoi dong lai dich vu myapp..."
sudo systemctl restart myapp

# 3. Test smoke API
curl -sf http://127.0.0.1:5000/health > /dev/null

echo "[✓] Deploy thanh cong 100%!"
```

### 5.3 Menu CLI Điều Phối Tập Trung (`menu.sh`)
```bash
#!/usr/bin/env bash
set -euo pipefail

show_menu() {
    clear
    echo "=============================================="
    echo "   LINUX LAB: HE THONG DIEU KHIEN VAN HANH    "
    echo "=============================================="
    echo "1. Chay Health-Check he thong"
    echo "2. Chay Sao luu du lieu (Backup & Rsync)"
    echo "3. Khoi phuc du lieu (Restore)"
    echo "4. Deploy ung dung (Kem co che Rollback)"
    echo "5. Xoay vong va nen log (Log Rotate)"
    echo "6. Thoat"
    echo "=============================================="
}

while true; do
    show_menu
    read -rp "Chon thao tac [1-6]: " choice
    case "${choice}" in
        1) sudo /opt/scripts/health_check.sh; read -rp "Nhan Enter de tiep tuc..." ;;
        2) sudo /opt/scripts/backup.sh; read -rp "Nhan Enter de tiep tuc..." ;;
        3) read -rp "Nhap file backup: " bf; sudo /opt/scripts/restore.sh "${bf}"; read -rp "Nhan Enter de tiep tuc..." ;;
        4) sudo /opt/scripts/deploy.sh; read -rp "Nhan Enter de tiep tuc..." ;;
        5) sudo /opt/scripts/log_rotate.sh; read -rp "Nhan Enter de tiep tuc..." ;;
        6) echo "Tam biet!"; exit 0 ;;
        *) echo "Lua chon khong hop le!"; sleep 1 ;;
    esac
done
```

---

## GIAI ĐOẠN 6: Kịch Bản Diễn Tập Demo Trực Tiếp (12–15 Phút)

| Thời gian | Thành viên | Thao tác lệnh demo trực tiếp trên máy ảo |
| :---: | :---: | :--- |
| **00:00 – 02:00** | **TV 1** | • `virsh list` show 2 VM đang chạy.<br>• `lsblk -f` và `cat /etc/fstab` chứng minh ổ phụ mount tự động.<br>• `sudo ufw status verbose` chứng minh cổng 2222, 80, 443. |
| **02:00 – 05:00** | **TV 2 & TV 3** | • **TV 2:** `ss -tulpn \| grep 3306` chứng minh DB chỉ nghe trên `127.0.0.1`.<br>• **TV 3:** Dùng `curl` POST ghi bản ghi mới vào CSDL, rồi GET đọc dữ liệu.<br>• **TV 3:** Chạy `kill -9 <PID_app>` $\rightarrow$ show `journalctl -u myapp -f` app tự hồi sinh. |
| **05:00 – 08:00** | **TV 4** | • `curl -k -I https://192.168.122.117` phản hồi 2 VHosts và HTTPS chuyển hướng 301.<br>• Từ máy ngoài gõ sai pass SSH 3 lần $\rightarrow$ show `fail2ban-client status sshd` bắt IP vào tù.<br>• `touch /etc/passwd` $\rightarrow$ `ausearch -k sensitive_auth_changes -i` show vết log. |
| **08:00 – 11:00** | **TV 2** | • Chạy `./backup.sh` tạo file nén và `rsync` sang VM 2.<br>• **Vào MySQL chạy `DROP TABLE items;` $\rightarrow$ Chạy `./restore.sh` $\rightarrow$ Query DB chứng minh dữ liệu khôi phục 100%!** |
| **11:00 – 14:00** | **TV 5** | • Mở `./menu.sh` điều khiển hệ thống.<br>• Cố tình viết sai file Nginx rồi chạy `./deploy.sh` $\rightarrow$ show cơ chế Rollback tự động.<br>• Stop dịch vụ $\rightarrow$ chạy `./health_check.sh` kích hoạt cảnh báo.<br>• Chạy `shellcheck /opt/scripts/*.sh` cho kết quả sạch không lỗi. |
| **14:00 – 15:00** | **Cả nhóm** | Trả lời 3–5 câu hỏi vấn đáp (Q&A) kỹ thuật từ Giảng viên. |

---

## GIAI ĐOẠN 7: Đóng Gói Sản Phẩm Nộp Báo Cáo

Trước ngày nộp bài, chạy lệnh đóng gói toàn bộ dự án thành file `.tar.gz`:
```bash
tar -czvf MSSV1_MSSV2_MSSV3_MSSV4_MSSV5.tar.gz \
  README.md \
  PHAN_CONG_CONG_VIEC.md \
  configs/ \
  scripts/ \
  docs/ \
  Bao_Cao_Ky_Thuat.pdf
```
Kiểm tra cấu trúc bên trong file nén:
```bash
tar -ztvf MSSV1_MSSV2_MSSV3_MSSV4_MSSV5.tar.gz
```
*(Đảm bảo đầy đủ file cấu hình thật, script thật giữ nguyên shebang, và báo cáo PDF đúng quy định của Khoa)*.
