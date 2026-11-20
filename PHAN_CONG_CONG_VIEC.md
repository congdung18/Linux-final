# KẾ HOẠCH PHÂN CÔNG CÔNG VIỆC ĐỒ ÁN LINUX & ỨNG DỤNG (5 THÀNH VIÊN)
**Môn học:** Hệ điều hành Linux & Ứng dụng — ĐHQG-HCM, Trường ĐH Khoa học Tự nhiên  
**Tài liệu tham chiếu:** [Do_An_Thuc_Hanh_Linux.pdf](file:///home/archlinux/Downloads/Do_An_Thuc_Hanh_Linux.pdf)

---

## 1. Nguyên Tắc Phân Chia Công Việc
1. **Bám sát luồng phát triển tự nhiên (Bottom-Up Architecture):**
   * **Tầng 1 (Hạ tầng & OS - TV 1):** Dựng VM, mạng, đĩa cứng `fstab`, firewall cơ bản.
   * **Tầng 2 (Dữ liệu & Bền vững - TV 2):** Khởi tạo CSDL MySQL/PostgreSQL, thiết lập sao lưu & khôi phục thảm họa.
   * **Tầng 3 (Dịch vụ Backend - TV 3):** Viết App Flask kết nối CSDL tầng 2, đóng gói systemd tự hồi sinh.
   * **Tầng 4 (Cổng vào & An ninh Web - TV 4):** Dựng Nginx Reverse Proxy trước App tầng 3, bọc TLS/HTTPS, cấu hình Fail2ban, Auditd, Lynis.
   * **Tầng 5 (Vận hành & Tự động hóa - TV 5):** Viết bộ CLI quản trị vòng đời (Deploy rollback, Health-check cảnh báo, ShellCheck).
2. **Không giẫm chân nhau:** Phối hợp qua Git repository. Mỗi thành viên sở hữu thư mục cấu hình và script riêng.
3. **Mỗi người sở hữu 1 phần Demo & Vấn đáp riêng:** Đảm bảo khi giảng viên vấn đáp ngẫu nhiên, ai cũng bảo vệ được phần của mình và hiểu bức tranh toàn cảnh (tránh bị trừ điểm cá nhân).

---

## 2. Bảng Ánh Xạ 5 Vai Trò (Workload Breakdown Mới)

| Thành viên | Vai trò phụ trách | Thành phần liên quan | Trọng số barem liên đới |
| :--- | :--- | :--- | :--- |
| **TV 1** | **Hạ tầng, Mạng & Nền tảng OS** | Nền tảng (Mục 2.1) & Hạ tầng (Mục 3) | Hệ thống (30%) + Bảo mật (20%) |
| **TV 2** | **Cơ sở dữ liệu & Sao lưu / Khôi phục** | CSDL (Mục 4.1) & Sao lưu (Mục 2.3, 5.1) | Sao lưu & Khôi phục (20%) |
| **TV 3** | **Ứng dụng Backend & Quản trị Systemd** | Ứng dụng & CSDL (Mục 4.1, 4.2) | Hệ thống (30%) |
| **TV 4** | **Reverse Proxy, TLS & An ninh Phòng thủ** | Hạ tầng, Web (Mục 3), TLS (Mục 6), Bảo mật (Mục 2.2) | Bảo mật (20%) + Hệ thống (30%) |
| **TV 5** | **Bộ công cụ CLI Tự động hóa & Giám sát** | Vận hành & Tự động hóa (Mục 2.4, 5.1) | Tự động hóa (15%) |

---

## 3. Chi Tiết Nhiệm Vụ & Sản Phẩm Của Từng Thành Viên

### Thành viên 1: Kỹ sư Hạ tầng, Mạng & Nền tảng OS (Infrastructure & OS)
* **Nhiệm vụ kỹ thuật:**
  * Khởi tạo 2 VM trên KVM/VirtualBox (Ubuntu 22.04 LTS Server):
    * **VM 1:** Máy chủ dịch vụ chính (`srv-main`).
    * **VM 2:** Máy chủ lưu trữ sao lưu / Bastion host (`srv-backup`).
  * Thiết lập mạng nội bộ để 2 VM thấy nhau và ra được Internet khi cần cài gói.
  * Cấu hình hostname có ý nghĩa trên cả 2 VM (`srv-main`, `srv-backup`).
  * Tạo tài khoản quản trị non-root, cấp quyền `sudo`, vô hiệu hóa đăng nhập trực tiếp bằng `root`.
  * Cấu hình phân vùng lưu trữ/backup chuyên biệt, mount tự động qua `/etc/fstab` (chứng minh tồn tại sau reboot).
  * Thiết lập tường lửa (UFW): Mặc định chặn chiều vào (`default deny incoming`), chỉ mở các port dịch vụ cần thiết (SSH tùy chỉnh 2222, HTTP 80, HTTPS 443).
  * Gia cố SSH (`sshd_config`): Tắt root login, đổi cổng mặc định sang 2222, thiết lập SSH Key, giới hạn `AllowUsers`.
* **Sản phẩm bàn giao:**
  * File cấu hình `/etc/ssh/sshd_config`, `/etc/fstab`, script thiết lập luật tường lửa UFW.
  * Sơ đồ mạng & topo kết nối 2 VM (đưa vào báo cáo).
* **Nhiệm vụ lúc Demo & Vấn đáp (1–2 phút):**
  * Show trạng thái 2 VM, lệnh `lsblk` và `mount` chứng minh phân vùng trong `fstab`.
  * Show trạng thái UFW (`ufw status verbose`).
  * Trả lời câu hỏi: *Vì sao mở các cổng đó? Đổi cổng SSH và tắt root login ngăn chặn được loại tấn công nào?*

---

### Thành viên 2: Kỹ sư CSDL & Sao lưu / Khôi phục Thảm họa (Database & Disaster Recovery)
* **Nhiệm vụ kỹ thuật:**
  * Cài đặt & cấu hình MariaDB/MySQL:
    * Tạo database riêng `appdb` cho ứng dụng và bảng dữ liệu mẫu `items`.
    * Tạo user riêng `appuser` áp dụng **nguyên tắc đặc quyền tối thiểu** (chỉ cấp `SELECT`, `INSERT` trên `appdb.*`, không cấp quyền SUPERUSER / GRANT ALL).
    * Cấu hình CSDL **chỉ lắng nghe cục bộ trên `127.0.0.1`** (kiểm tra qua `bind-address`).
  * Viết script **sao lưu (`backup.sh`)**:
    * Dump dữ liệu CSDL (`mysqldump`) + nén cùng với thư mục mã nguồn web/app thành file `.tar.gz` có gắn timestamp.
    * Lưu vào phân vùng `/mnt/data_backup/`.
    * Áp dụng chính sách lưu giữ (retention policy): Tự động tìm và xóa các bản backup cũ hơn $X$ ngày (ví dụ 7 ngày).
    * Đồng bộ bản backup sang VM 2 an toàn bằng `rsync` qua SSH.
    * Thiết lập lịch chạy tự động bằng `cron` hoặc `systemd timer`.
  * Viết script **khôi phục thảm họa (`restore.sh`)**:
    * Tiếp nhận đường dẫn bản sao lưu, giải nén, phục hồi lại dữ liệu CSDL và thư mục web.
* **Sản phẩm bàn giao:**
  * File script khởi tạo database và phân quyền người dùng (`init_db.sql`).
  * File cấu hình CSDL (`50-server.cnf`).
  * Hai script chính: `backup.sh` và `restore.sh`.
  * File crontab hoặc `.timer` file của systemd.
* **Nhiệm vụ lúc Demo & Vấn đáp (2–3 phút):**
  * Chạy `ss -tulpn | grep 3306` chứng minh CSDL chỉ bind trên `127.0.0.1`.
  * Chạy `backup.sh` tạo bản sao lưu mới, show file đã sang VM 2 và show bước xóa bản lưu cũ.
  * **Live Disaster Recovery Drill:** Xóa/làm hỏng bảng dữ liệu đang chạy $\rightarrow$ Chạy `restore.sh` phục hồi trực tiếp trước mặt giảng viên $\rightarrow$ Truy vấn lại DB chứng minh dữ liệu còn nguyên vẹn.
  * Trả lời câu hỏi: *Nếu đĩa đầy vào lúc backup thì script xử lý thế nào? Tại sao không dùng tài khoản root DB cho ứng dụng?*

---

### Thành viên 3: Lập trình viên Ứng dụng & Quản trị Systemd (App & Systemd)
* **Nhiệm vụ kỹ thuật:**
  * Viết một ứng dụng Web nhỏ, hoàn chỉnh bằng Python (Flask):
    * Có tối thiểu **1 endpoint đọc (GET `/api/items`)** lấy dữ liệu từ CSDL do TV 2 tạo.
    * Có tối thiểu **1 endpoint ghi (POST `/api/items`)** thêm dữ liệu mới vào CSDL.
    * Có endpoint kiểm tra sức khỏe `GET /health`.
  * Quản lý dịch vụ bằng `systemd` (`myapp.service`):
    * Thiết lập `Restart=on-failure` và thời gian chờ restart (`RestartSec=3s`).
    * Tách toàn bộ chuỗi kết nối và mật khẩu DB ra `EnvironmentFile` riêng (`/etc/myapp/app.env`) đặt quyền hạn chế `chmod 600` (không hard-code trong source code).
    * Đẩy toàn bộ log `stdout`/`stderr` về `journald`.
* **Sản phẩm bàn giao:**
  * Thư mục mã nguồn ứng dụng (`/opt/myapp/app.py`).
  * File service `/etc/systemd/system/myapp.service` và file môi trường `/etc/myapp/app.env`.
* **Nhiệm vụ lúc Demo & Vấn đáp (2–3 phút):**
  * Show trạng thái `systemctl status myapp.service` (active & enabled).
  * Thao tác gửi dữ liệu ghi (POST) và đọc (GET) qua `curl` thông qua Nginx.
  * **Mô phỏng sự cố ứng dụng bị sập:** Chạy lệnh `kill -9 <PID_app>`, sau đó chứng minh systemd lập tức phát hiện và tự động spawn lại tiến trình mới, show log bằng `journalctl -u myapp.service -n 20 --no-pager`.
  * Trả lời câu hỏi: *Vòng đời của systemd service diễn ra như thế nào? Quyền của EnvironmentFile tại sao phải là 600?*

---

### Thành viên 4: Kỹ sư Web Proxy, TLS & An ninh Phòng thủ (Web, TLS & Security)
* **Nhiệm vụ kỹ thuật:**
  * Cấu hình Nginx chạy $\ge 2$ Virtual Hosts:
    * VHost 1 (`app.linux.local`): Reverse proxy chuyển tiếp request vào Backend App (cổng 5000 do TV 3 tạo), cấu hình đúng HTTP headers (`X-Forwarded-For`, `X-Forwarded-Proto`, `Host`).
    * VHost 2 (`status.linux.local`): Trang trạng thái tĩnh (Static HTML).
  * Tạo chứng chỉ và khóa tự ký chuẩn bằng `openssl` (hạn 1 năm, subject đúng chuẩn phòng lab).
  * Cấu hình TLS/HTTPS trên web server và luật chuyển hướng tự động HTTP (80) $\rightarrow$ HTTPS (443) (mã 301).
  * Cài đặt & cấu hình `fail2ban`: Tạo jail bảo vệ SSH (chặn IP sau 3 lần gõ sai mật khẩu).
  * Cài đặt & cấu hình `auditd`: Thiết lập rule giám sát 2 tệp nhạy cảm `/etc/passwd` và `/etc/shadow`.
  * Chạy công cụ kiểm toán **Lynis**, xuất báo cáo, khắc phục tối thiểu 3 khuyến nghị bảo mật (`BANNER-7126`, `AUTH-9286`, `FILE-6310`).
* **Sản phẩm bàn giao:**
  * File cấu hình Nginx VHosts (`app.conf`, `status.conf`), cặp khóa TLS tự ký.
  * File `/etc/fail2ban/jail.local`, rule file `/etc/audit/rules.d/audit.rules`.
  * Báo cáo log Lynis trước và sau khi khắc phục 3 lỗi.
* **Nhiệm vụ lúc Demo & Vấn đáp (2–3 phút):**
  * Dùng `curl -k -I` test truy cập cả 2 VHost, kiểm tra HTTP tự nhảy sang HTTPS 301.
  * **Trực tiếp kích hoạt 1 lần ban fail2ban** (gõ sai pass SSH nhiều lần từ máy host/VM 2 để bị jail ban IP).
  * Đọc log `ausearch -k sensitive_auth_changes -i` để chứng minh `auditd` ghi lại vết truy cập tệp nhạy cảm.
  * Trả lời câu hỏi: *Vì sao dùng chứng chỉ tự ký thay vì Let's Encrypt trong mạng lab? Các header proxy chuyển tiếp để làm gì?*

---

### Thành viên 5: Kỹ sư Tự động hóa, Giám sát & Quản trị Hệ thống (DevOps & Automation)
* **Nhiệm vụ kỹ thuật:**
  * Thiết kế **Menu CLI tương tác (`menu.sh`)**: Làm điểm vào (entrypoint) giao diện text thân thiện, điều hướng gọi các script con, xử lý bắt lỗi nhập sai.
  * Viết script **triển khai an toàn (`deploy.sh`)**:
    * Đưa code/vhost mới vào thư mục chạy, phân quyền sở hữu chuẩn (`chown`/`chmod`).
    * Cơ chế reload an toàn: Kiểm tra cú pháp cấu hình (`nginx -t`, cú pháp unit) $\rightarrow$ nếu lỗi thì **tự động rollback** về bản chạy tốt gần nhất $\rightarrow$ nếu đúng mới thực hiện restart/reload.
  * Viết script **kiểm tra sức khỏe (`health_check.sh`)**:
    * Giám sát CPU, RAM, dung lượng Disk, trạng thái các cổng mạng, trạng thái các dịch vụ (`nginx`, `myapp`, `mariadb`).
    * So sánh với ngưỡng cảnh báo cấu hình được (VD: Disk > 80%, RAM > 85%, service INACTIVE).
    * Tích hợp kênh phát cảnh báo: Gửi tin nhắn thông báo qua bot Telegram Webhook (hoặc email `msmtp`).
  * Viết script **xoay vòng log (`log_rotate.sh`)**:
    * Xoay và nén các file log chỉ định, duy trì $N$ thế hệ log gần nhất và dọn dẹp log quá cũ.
  * Chuẩn hóa toàn bộ mã nguồn script trong dự án:
    * Sử dụng `#!/usr/bin/env bash`, `set -euo pipefail`, thiết lập `trap ... ERR/EXIT`.
    * Hỗ trợ cờ tham số bằng `getopts` và tùy chọn `--help`.
    * Đảm bảo **tất cả script trong dự án vượt qua kiểm tra `shellcheck` với 0 lỗi**.
* **Sản phẩm bàn giao:**
  * Bộ script: `menu.sh`, `deploy.sh`, `health_check.sh`, `log_rotate.sh`.
  * File cấu hình cảnh báo (token bot Telegram).
  * Báo cáo log kết quả chạy `shellcheck` sạch 100%.
* **Nhiệm vụ lúc Demo & Vấn đáp (2–3 phút):**
  * Trình chiếu menu CLI điều khiển hệ thống mượt mà.
  * **Demo Deploy có Rollback:** Thử deploy một cấu hình Nginx cố tình viết sai cú pháp $\rightarrow$ Script phát hiện lỗi, ngăn chặn restart và rollback về config cũ an toàn.
  * **Demo Cảnh báo:** Cố tình tắt một dịch vụ hoặc tạo file giả lập đầy ổ đĩa $\rightarrow$ Kích hoạt `health_check.sh` và nhận được cảnh báo gửi về Telegram ngay tại chỗ.
  * Chạy trực tiếp lệnh `shellcheck scripts/*.sh` chứng minh code sạch chuẩn.
  * Trả lời câu hỏi: *`set -euo pipefail` giải quyết bài toán gì? Cơ chế trap ERR hoạt động như thế nào?*

---

## 4. Kế Hoạch Phối Hợp & Quy Trình Tránh Xung Đột

```
┌─────────────────────────────────────────────────────────────────┐
│                    GIT REPOSITORY CHUNG                        │
├─────────────────┬──────────────────┬────────────────────────────┤
│ app/ (TV 3)     │ configs/ (TV 1,4)│ scripts/ (TV 2,5)          │
│ • app.py        │ • nginx/         │ • menu.sh                  │
│ • requirements  │ • systemd/       │ • deploy.sh                │
│ • app.env.ex    │ • fail2ban/      │ • backup.sh & restore.sh   │
│                 │ • auditd/        │ • health_check.sh          │
│                 │ • firewall/      │ • log_rotate.sh            │
└─────────────────┴──────────────────┴────────────────────────────┘
         │                                       │
         ▼                                       ▼
  [Sandbox riêng]                        [VM 1 Production]
(Thử nghiệm trên máy con)             (Chạy deploy.sh để áp dụng)
```

---

## 5. Kịch Bản Khớp Lệnh Khi Demo (12–15 Phút)

| Thời gian | Người thuyết trình | Nội dung trình diễn trực tiếp trên máy ảo |
| :---: | :---: | :--- |
| **00:00 – 02:00** | **TV 1** | Giới thiệu sơ đồ 2 VM, show `fstab` mount, show UFW đang chặn cổng và chỉ mở cổng cần thiết. |
| **02:00 – 05:00** | **TV 2 & TV 3** | • **TV 2:** Show lệnh `ss -tulpn \| grep 3306` chứng minh DB chỉ nghe trên `127.0.0.1`.<br>• **TV 3:** Demo ứng dụng ghi (POST) và đọc (GET) dữ liệu qua API.<br>• **TV 3:** Kill tiến trình app $\rightarrow$ show `journalctl` app tự khởi động lại. |
| **05:00 – 08:00** | **TV 4** | • Demo truy cập 2 Virtual Hosts qua HTTPS, show chứng chỉ tự ký và chuyển hướng 301.<br>• Dùng máy khác gõ sai mật khẩu SSH để fail2ban đưa IP vào jail.<br>• Đọc log `auditd` bắt được vết can thiệp vào `/etc/passwd`. |
| **08:00 – 11:00** | **TV 2** | • Chạy `backup.sh` tạo nén CSDL + code, rsync sang VM 2 + xóa bản cũ theo retention.<br>• **Xóa/làm hỏng dữ liệu DB $\rightarrow$ chạy `restore.sh` khôi phục dữ liệu nguyên vẹn trực tiếp trước mặt thầy.** |
| **11:00 – 14:00** | **TV 5** | • Mở `menu.sh` điều khiển toàn bộ hệ thống.<br>• Demo deploy có lỗi cú pháp $\rightarrow$ cơ chế an toàn rollback thành công.<br>• Kích hoạt cảnh báo quá ngưỡng gửi tin nhắn về Telegram.<br>• Chạy `shellcheck` trực tiếp cho kết quả 100% clean. |
| **14:00 – 15:00** | **Cả nhóm** | Kết thúc phần demo, sẵn sàng bước vào phần Vấn đáp (Q&A) cá nhân của Giảng viên. |
