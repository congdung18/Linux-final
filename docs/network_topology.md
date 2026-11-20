# Sơ Đồ Topo Mạng & Kiến Trúc Hệ Thống (Thành viên 1)

## 1. Danh Sách & Vai Trò Máy Ảo
- **Trình ảo hóa:** KVM / QEMU (libvirt trên nền Arch Linux host).
- **Hệ điều hành khách:** Ubuntu 22.04 LTS Server (Cloud Image, không giao diện đồ họa).
- **Mạng ảo hóa:** Libvirt Virtual Network `default` (Bridge `virbr0`, dải mạng `192.168.122.0/24`).

| Máy ảo | Hostname | IP Address | Vai trò & Dịch vụ phụ trách |
| :--- | :--- | :--- | :--- |
| **VM 1** | `srv-main` | `192.168.122.117` | Máy chủ dịch vụ chính: Nginx Reverse Proxy (80, 443), Backend Flask App (5000), MariaDB (3306), Fail2ban, Auditd, Bash Ops Toolkit. |
| **VM 2** | `srv-backup` | `192.168.122.x` | Máy chủ lưu trữ từ xa: Nhận dữ liệu sao lưu định kỳ qua `rsync` trên SSH Key, đóng vai trò Bastion/Backup server. |

---

## 2. Bảng Phân Tách Cổng Dịch Vụ & Chính Sách Tường Lửa (UFW)
Chính sách chung: **Mặc định chặn toàn bộ chiều vào (`default deny incoming`)**, chỉ mở cổng tối thiểu có lý do giải trình trong báo cáo:

| Cổng | Giao thức | Dịch vụ | Trạng thái UFW | Lý do giải trình |
| :---: | :---: | :--- | :---: | :--- |
| **2222** | TCP | Custom SSH | **ALLOW** | Cổng quản trị SSH từ xa đã đổi từ 22 mặc định sang 2222 để giảm 90%+ lưu lượng quét tự động từ Internet; tắt root login và chỉ cho phép user `ubuntu`. |
| **80** | TCP | HTTP Web | **ALLOW** | Lắng nghe request HTTP thông thường và chuyển hướng 301 tự động sang HTTPS 443. |
| **443** | TCP | HTTPS Web | **ALLOW** | Kênh giao tiếp chính mã hóa TLS cho 2 Virtual Hosts (`app.linux.local` và `status.linux.local`). |
| **3306** | TCP | MariaDB | **BLOCKED** | CSDL quan hệ tuyệt đối không mở ra mạng ngoài; chỉ `bind-address 127.0.0.1` phục vụ cục bộ cho Backend App (nguyên tắc đặc quyền tối thiểu). |
| **5000** | TCP | Flask App | **BLOCKED** | Ứng dụng Backend lắng nghe cục bộ `127.0.0.1`, Nginx đứng trước làm Reverse Proxy chuyển tiếp request vào. |

---

## 3. Cấu Hình Phân Vùng Lưu Trữ Riêng (`/etc/fstab`)
- Đĩa cứng hệ điều hành: `/dev/vda` (20GB).
- Đĩa cứng phụ phân vùng riêng: `/dev/vdb` (10GB) định dạng `ext4`.
- Điểm gắn kết (Mount Point): `/mnt/data_backup`.
- Cấu hình trong `/etc/fstab`:
  ```text
  UUID=752f02e2-b8ee-4e01-a1e9-21c7786da006 /mnt/data_backup ext4 defaults 0 2
  ```
- **Mục đích kỹ thuật:** Cô lập hoàn toàn dữ liệu sao lưu (backup) khỏi phân vùng gốc (`/`). Nếu dữ liệu backup bị đầy 100%, chỉ phân vùng `/mnt/data_backup` bị đầy; hệ điều hành chính và các dịch vụ khác vẫn hoạt động bình thường, không xảy ra hiệu ứng sập dây chuyền (cascading failure).
