# ĐỒ ÁN THỰC HÀNH: HỆ ĐIỀU HÀNH LINUX & ỨNG DỤNG
**ĐHQG-HCM — Trường Đại học Khoa học Tự nhiên — Khoa Công nghệ Thông tin**

---

## 1. Hướng Đồ Án & Kiến Trúc Tổng Thể (Unified System)
Dự án xây dựng một hệ thống máy chủ Linux tích hợp hoàn chỉnh gồm ba thành phần bắt buộc:
1. **Hạ tầng, Web & Bảo mật:** Nền tảng ảo hóa đa máy ảo (2 VM), tường lửa UFW siết chặt, SSH gia cố, phân vùng lưu trữ mount `/etc/fstab`, Nginx Reverse Proxy phục vụ $\ge 2$ Virtual Hosts mã hóa SSL/TLS tự ký, hệ thống phòng thủ Fail2ban và truy vết Auditd.
2. **Ứng dụng & CSDL:** CSDL quan hệ MariaDB chỉ bind nội bộ `127.0.0.1` với đặc quyền tối thiểu, ứng dụng Python Flask xử lý đọc/ghi API, quản trị vòng đời tự hồi sinh qua `systemd` và bảo vệ bí mật qua `EnvironmentFile` (`chmod 600`).
3. **Vận hành & Tự động hóa:** Bộ công cụ Bash quản trị tập trung (menu CLI, deploy an toàn có rollback tự động, sao lưu định kỳ kèm lưu giữ và rsync sang VM 2, khôi phục thảm họa, giám sát sức khỏe phát cảnh báo, xoay vòng log, sạch 100% `shellcheck`).

---

## 2. Bảng Phân Công Công Việc 5 Thành Viên

Chi tiết kế hoạch xem tại: [PHAN_CONG_CONG_VIEC.md](./PHAN_CONG_CONG_VIEC.md)

| Thành viên | Vai trò phụ trách | Trách nhiệm chính |
| :--- | :--- | :--- |
| **TV 1** | **Hạ tầng, Mạng & Nền tảng OS** | Cài đặt 2 VM, cấu hình mạng KVM, hostname, user sudo, phân vùng đĩa cứng `/etc/fstab`, tường lửa UFW, gia cố SSH (port 2222, tắt root, key auth). |
| **TV 2** | **Cơ sở dữ liệu & Sao lưu / Khôi phục** | Cài đặt MariaDB 127.0.0.1, tạo database `appdb` & user đặc quyền tối thiểu, viết script `backup.sh` (retention + rsync VM2) và `restore.sh`. |
| **TV 3** | **Ứng dụng Backend & Quản trị Systemd** | Phát triển ứng dụng Python Flask (GET/POST), quản lý daemon qua `systemd` (`Restart=on-failure`), tách bí mật ra `EnvironmentFile` (`chmod 600`). |
| **TV 4** | **Reverse Proxy, TLS & An ninh Web** | Cấu hình Nginx 2 Virtual Hosts, sinh chứng chỉ TLS tự ký `openssl`, chuyển hướng HTTP $\rightarrow$ HTTPS 301, cấu hình `fail2ban` và `auditd`, quét `lynis`. |
| **TV 5** | **Bộ công cụ CLI Vận hành & Giám sát** | Thiết kế `menu.sh`, `deploy.sh` (rollback tự động), `health_check.sh` (gửi cảnh báo Telegram/Email), `log_rotate.sh`, kiểm chuẩn `shellcheck`. |

---

## 3. Sơ Đồ Máy Ảo & Luồng Xử Lý Dữ Liệu

```text
[ Client / Evaluator ]
         │
         │ HTTPS (Port 443) / SSH (Port 2222)
         ▼
┌────────────────────────────────────────────────────────────────────────┐
│ VM 1: srv-main (192.168.122.117)                                       │
│ ├── Tường lửa: UFW (Default Deny, chỉ mở 2222, 80, 443)                 │
│ ├── Web Server: Nginx Reverse Proxy (2 VHosts: app & status, TLS)      │
│ │    └── proxy_pass 127.0.0.1:5000 (Forward headers)                   │
│ ├── Backend: Python Flask App (Quản trị bởi myapp.service)             │
│ │    └── EnvironmentFile: /etc/myapp/app.env (chmod 600)               │
│ ├── CSDL: MariaDB (127.0.0.1:3306, user: appuser, db: appdb)           │
│ ├── An ninh: Fail2ban (chống brute-force) & Auditd (giám sát /etc/shadow)│
│ └── Phân vùng đĩa phụ: /dev/vdb mount /mnt/data_backup qua /etc/fstab   │
└────────────────────────────────────────────────────────────────────────┘
         │
         │ rsync backup qua SSH Key
         ▼
┌────────────────────────────────────────────────────────────────────────┐
│ VM 2: srv-backup (192.168.122.x)                                       │
│ └── Lưu trữ các bản sao lưu từ xa (Remote Backup Target / Bastion)     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Hướng Dẫn Tái Tạo Hệ Thống (Reproducibility Guide)

### 4.1 Khởi tạo Máy ảo & Mạng (Yêu cầu KVM/QEMU hoặc VirtualBox)
```bash
# 1. Tạo đĩa ảo từ Ubuntu 22.04 Cloud Image
qemu-img create -f qcow2 -F qcow2 -b ubuntu-22.04-server-cloudimg-amd64.img srv-main.qcow2 20G
qemu-img create -f qcow2 -F qcow2 -b ubuntu-22.04-server-cloudimg-amd64.img srv-backup.qcow2 20G

# 2. Khởi động 2 VM dùng cloud-init
sudo virt-install --name srv-main --ram 2048 --vcpus 2 \
  --disk path=/path/to/srv-main.qcow2,bus=virtio \
  --os-variant ubuntu22.04 --network network=default,model=virtio \
  --cloud-init user-data=configs/cloud-init/user-data-main.yaml \
  --graphics none --import

sudo virt-install --name srv-backup --ram 1024 --vcpus 1 \
  --disk path=/path/to/srv-backup.qcow2,bus=virtio \
  --os-variant ubuntu22.04 --network network=default,model=virtio \
  --cloud-init user-data=configs/cloud-init/user-data-backup.yaml \
  --graphics none --import
```

### 4.2 Cấu hình Ổ cứng phụ & fstab trên VM 1
```bash
# Gắn ổ cứng phụ 10GB và mount
sudo mkfs.ext4 /dev/vdb
sudo mkdir -p /mnt/data_backup
UUID_VAL=$(sudo blkid -s UUID -o value /dev/vdb)
echo "UUID=$UUID_VAL /mnt/data_backup ext4 defaults 0 2" | sudo tee -a /etc/fstab
sudo mount -a
```

### 4.3 Áp dụng Tường lửa & SSH Hardening
```bash
# Cấu hình SSH cổng 2222 và nạp luật UFW
sudo bash scripts/setup_firewall.sh
```
