# TV4 — Web Proxy, TLS & Security

## Phạm vi
TV4 phụ trách Nginx, hai virtual host, TLS tự ký, HTTP redirect, Fail2ban, Auditd và Lynis. Các script hỗ trợ triển khai và xác minh trên Ubuntu Server 22.04 LTS. Không thay thế firewall của TV1, database của TV2, backend của TV3 hay CLI vận hành của TV5.

## Điều kiện triển khai
- Có quyền sudo; SSH và UFW do TV1 cấu hình, mặc định SSH 2222, HTTP 80, HTTPS 443.
- MariaDB và Flask đã được triển khai; backend lắng nghe tại 127.0.0.1:5000, unit myapp.service.
- Có rsyslog và /var/log/auth.log; Auditd cho phép nạp rule (không immutable).
- Kiểm tra mã nguồn và cấu hình trước khi chạy với quyền root. File cấu hình Bash được đọc bằng source, chỉ dùng file đáng tin cậy.

## Triển khai
Từ thư mục gốc repository:

```bash
cp -n configs/security/tv4.conf.example configs/security/tv4.conf
# Chỉnh tv4.conf nếu cần; đồng bộ domain, port với TV1/TV3.
sudo ./scripts/setup_web.sh
sudo ./scripts/setup_security.sh
sudo ./scripts/verify.sh
```

Nếu backend chưa nhận giới hạn core dump, phối hợp TV3 rồi chạy `sudo ./scripts/setup_security.sh --restart-backend`. Giữ console VM dự phòng khi thay đổi SSH. Không ghi đè cấu hình xác thực của TV1. Nếu SSH drop-in cũ đã đặt các directive Hardening, kiểm tra thứ tự Include và di chuyển có kiểm soát.

Trên máy client, ánh xạ IP thực tế của srv-main đến app.linux.local và status.linux.local trong hosts hoặc DNS nội bộ. Sao chép **chứng chỉ công khai** `/etc/nginx/ssl/linux-lab.crt` qua kênh tin cậy, xác minh fingerprint; không sao chép private key. Ví dụ kiểm tra ngay trên server:

```bash
sudo curl --cacert /etc/nginx/ssl/linux-lab.crt \
  --resolve app.linux.local:443:127.0.0.1 https://app.linux.local/health
```

## Tham số
| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| APP_DOMAIN / STATUS_DOMAIN | app.linux.local / status.linux.local | Virtual host và SAN |
| BACKEND_HOST / BACKEND_PORT | 127.0.0.1 / 5000 | Upstream Flask |
| HTTP_PORT / HTTPS_PORT | 80 / 443 | Cổng web, phối hợp UFW |
| SSH_PORT | 2222 | Phải khớp SSH thực tế |
| TLS_DAYS / TLS_KEY_BITS | 365 / 2048 | Hạn và kích thước khóa RSA |
| TLS_COUNTRY / TLS_ORGANIZATION | VN / Linux Final Lab | Subject |
| F2B_MAXRETRY / F2B_FINDTIME / F2B_BANTIME | 3 / 600 / 600 | Chính sách jail, thời gian tính bằng giây |
| BACKEND_SERVICE | myapp | Tên unit không gồm .service |

## Công cụ
| Script | Chức năng |
|---|---|
| generate_tls.sh | Sinh hoặc tái sử dụng TLS; ưu tiên gọi qua setup_web.sh |
| setup_web.sh | Render template, backup, validate, reload, rollback cấu hình web |
| setup_security.sh | Triển khai và xác minh cấu hình bảo mật |
| verify.sh | Kiểm thử không phá hủy, exit 0 khi đạt tất cả |
| run_lynis.sh | Quét và so sánh báo cáo, không ghi đè kết quả cũ |
| lib/common.sh | Hàm dùng chung |

## Tài liệu liên quan
- [Kiến trúc](architecture.md)
- [Kiểm toán bảo mật](security-audit.md)
- [Kiểm thử](test-cases.md)
- [Demo](demo.md)
- [Xử lý lỗi](troubleshooting.md)
- [Vấn đáp](qa.md)
- [Minh chứng](../../screenshots/tv4/README.md)

## Đối chiếu đề bài
| Mục | Nội dung TV4 |
|---|---|
| 2.2 | SSH, Fail2ban, Auditd và Lynis: [kiểm thử](test-cases.md), [kiểm toán](security-audit.md) |
| 3.2–3.3 | Reverse proxy, hai virtual host và demo bảo mật: [kiến trúc](architecture.md), [demo](demo.md) |
| 6.2 | HTTPS tự ký và HTTP redirect: [minh chứng](../../screenshots/tv4/03_tls_redirect.png) |
| 7–8 | File cấu hình thật, script, ảnh có chú thích và demo trực tiếp |

Markdown này là tài liệu thành phần; nhóm vẫn cần báo cáo PDF 6–12 trang (không kể phụ lục), README chung và gói nộp theo mục 1.3.

## Trạng thái và giới hạn
SSH password authentication vẫn bật để demo; cần kiểm tra xác thực khóa và ghi nhận đánh đổi với TV1. 34/34 kiểm thử đạt trên srv-main ngày 27/11/2026; 9 script toàn repository vượt qua Bash syntax và ShellCheck tại thời điểm kiểm tra. Chưa xác nhận cài đặt trên VM sạch hoặc tích hợp đầy đủ TV1–TV5. Không dùng kết quả lab như chứng nhận production. Hệ thống thử nghiệm dùng QEMU/KVM; đề bài quy định VirtualBox/VMware, cần xác nhận giảng viên chấp thuận môi trường này. TLS 1.0/1.1 vẫn được khai báo trên VM theo lựa chọn lab, chưa kiểm tra handshake thực tế; package warning PKGS-7392 còn tồn tại. TLS độc lập chưa chia sẻ lock và rollback đầy đủ với web deployment. Backup cấu hình cần quản lý lưu giữ thủ công. Flask development server chỉ phục vụ demo.
