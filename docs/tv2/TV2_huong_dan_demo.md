# TV2 - Cơ sở dữ liệu, Sao lưu và Khôi phục: cài đặt, demo, vấn đáp

## 1. Cài đặt (trên srv-main)

```bash
# 1. MariaDB và cấu hình bind
sudo apt update && sudo apt install -y mariadb-server
sudo cp configs/database/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf   # hoặc chỉ sửa dòng bind-address
sudo systemctl restart mariadb
ss -tulpn | grep 3306            # phải thấy 127.0.0.1:3306

# 2. Khởi tạo CSDL và user
sudo mariadb < configs/database/init_db.sql

# 3. Cài script và cấu hình sao lưu
sudo mkdir -p /opt/scripts
sudo install -m 755 scripts/backup.sh scripts/restore.sh /opt/scripts/
sudo install -m 600 configs/backup/backup.conf.example /etc/backup.conf
sudo nano /etc/backup.conf       # đặt REMOTE_HOST = IP thật của srv-backup
```

## 2. SSH key từ srv-main sang srv-backup (một lần)

Script chạy bằng root nên khóa nằm ở `/root/.ssh`.

```bash
sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_backup
# Chép public key sang srv-backup (đổi cổng nếu srv-backup chưa dùng 2222)
sudo ssh-copy-id -i /root/.ssh/id_backup.pub -p 2222 ubuntu@<IP_srv-backup>
# Ghi nhận host key để script chạy với StrictHostKeyChecking=yes
sudo sh -c 'ssh-keyscan -p 2222 <IP_srv-backup> >> /root/.ssh/known_hosts'
# Kiểm tra
sudo ssh -p 2222 -i /root/.ssh/id_backup ubuntu@<IP_srv-backup> hostname
```

Lưu ý: srv-backup cũng phải lắng nghe SSH ở cổng 2222 (hoặc đổi `REMOTE_PORT`
trong `/etc/backup.conf`).

## 3. Lịch chạy tự động (systemd timer)

```bash
sudo cp configs/systemd/backup.service configs/systemd/backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer
systemctl list-timers backup.timer
```

## 4. Kịch bản demo (08:00 - 11:00)

Chuẩn bị trước giờ demo: chạy thử `sudo /opt/scripts/backup.sh` ít nhất một lần
để chắc chắn rsync và SSH key hoạt động.

```bash
# Phần 02:00 - 05:00: chứng minh CSDL chỉ nghe cục bộ
ss -tulpn | grep 3306

# Phần 08:00 - 11:00
# a) Tạo bản sao lưu mới và đồng bộ sang VM 2
sudo /opt/scripts/backup.sh
ls -lh /mnt/data_backup/
ssh -p 2222 -i /root/.ssh/id_backup ubuntu@<IP_srv-backup> ls -lh /home/ubuntu/backups/   # chạy bằng sudo

# b) Chứng minh retention (tạo sẵn một file giả cũ 10 ngày trước buổi demo)
sudo touch -d "10 days ago" /mnt/data_backup/backup_20000101_000000.tar.gz
sudo /opt/scripts/backup.sh      # dòng "Retention" sẽ in ra file bị xóa

# c) Thảm họa và khôi phục
sudo mariadb -e "SELECT COUNT(*) FROM appdb.items;"
sudo mariadb -e "DROP TABLE appdb.items;"
sudo mariadb -e "SELECT * FROM appdb.items;"          # báo lỗi bảng không tồn tại
sudo /opt/scripts/restore.sh /mnt/data_backup/backup_<timestamp>.tar.gz
sudo mariadb -e "SELECT * FROM appdb.items;"          # dữ liệu đã trở lại

# d) Chứng minh đặc quyền tối thiểu (nếu được hỏi)
mariadb -u appuser -p'StudentAppPassword123!' -e "DELETE FROM appdb.items;"   # phải bị từ chối
```

Mẹo: restore hỏi xác nhận, gõ `yes`. Dùng `-y` nếu muốn chạy nhanh khi tập.

## 5. Câu hỏi vấn đáp thường gặp

**Nếu đĩa đầy vào lúc backup thì script xử lý thế nào?**
Ba lớp bảo vệ. (1) Dữ liệu sao lưu nằm trên phân vùng riêng `/mnt/data_backup`
(`/dev/vdb`), nên đầy cũng không làm sập hệ điều hành. (2) Script kiểm tra
`mountpoint` để không ghi nhầm vào `/` khi ổ chưa mount, và so dung lượng trống
với kích thước dump + mã nguồn trước khi nén. (3) `set -euo pipefail` cùng
`trap EXIT` xóa file nén dở dang nếu `tar` vẫn lỗi, nên không để lại bản sao
lưu hỏng; script thoát với mã lỗi khác 0 để timer/journal ghi nhận thất bại.

**Tại sao không dùng tài khoản root DB cho ứng dụng?**
Nguyên tắc đặc quyền tối thiểu. Nếu app bị khai thác (ví dụ SQL injection),
kẻ tấn công chỉ có `SELECT, INSERT` trên `appdb`, không thể `DROP`, `DELETE`,
đọc CSDL khác hay tạo user. Việc sao lưu/khôi phục cần quyền cao hơn nên chỉ
chạy bằng root qua unix_socket, không lưu mật khẩu root ở đâu cả.

**Vì sao dùng `--single-transaction`?** Dump nhất quán trên InnoDB mà không
khóa bảng, ứng dụng vẫn ghi được trong lúc sao lưu.

**Vì sao rsync có `--delete`?** Để retention áp dụng đồng bộ: bản đã hết hạn ở
srv-main cũng biến mất ở srv-backup. Chỉ các file `backup_*` bị ảnh hưởng.

**Vì sao thêm file `.sha256`?** Restore kiểm tra checksum trước khi ghi đè dữ
liệu đang chạy, tránh khôi phục từ bản bị hỏng khi truyền qua mạng.
