# Kết quả kiểm thử TV4

## Kiểm thử chức năng
Môi trường srv-main, kết quả terminal ngày 27/11/2026 lúc 03:19:49 +07.

| Nhóm | Đạt / Tổng |
|---|---:|
| System services | 6/6 |
| Nginx và Virtual Hosts | 5/5 |
| TLS certificate | 4/4 |
| Backend integration | 2/2 |
| Fail2ban | 4/4 |
| Auditd | 3/3 |
| SSH hardening | 8/8 |
| Core dump protection | 2/2 |
| Tổng | 34/34 |

Minh chứng chức năng: [HTTPS API](../../screenshots/tv4/01_https_app.png), [Status](../../screenshots/tv4/02_https_status.png), [TLS/301](../../screenshots/tv4/03_tls_redirect.png), [Fail2ban](../../screenshots/tv4/04_fail2ban.png), [Auditd](../../screenshots/tv4/05_auditd.png), [Lynis](../../screenshots/tv4/06_lynis_comparison.png).

## Kiểm thử triển khai
| ID | Kịch bản | Kết quả / bằng chứng |
|---|---|---|
| T01 | Bash syntax toàn repository | 9/9 PASS |
| T02 | ShellCheck toàn repository | Không có diagnostic |
| T03 | TLS reuse hai lần | Fingerprint không đổi |
| T04 | Web lock đã bị giữ | Exit 1, triển khai bị từ chối |
| T05 | Web idempotency | 7/7 checksum không đổi |
| T06 | Nginx directive không hợp lệ | Bị từ chối; 7/7 checksum phục hồi, HTTPS healthy |
| T07 | Security deployment | Thành công; audit rule đã có được tái sử dụng |
| T08 | Security rollback khi lỗi grep | 6 dịch vụ active, 2 audit rule còn tồn tại, lost=0, API đọc 4 bản ghi |
| T09 | Security lock/idempotency/rollback có chủ đích | Người thực hiện xác nhận hoàn thành; chưa lưu output chi tiết trong cuộc trao đổi |
| T10 | Lynis compare | 63→69, 49→40, warning 1→1 |
| T11 | Lynis chống ghi đè | before và after đều exit 1 |
| T12 | Fail2ban live ban/unban | Đã ghi nhận 1 lượt ban thực tế |
| T13 | Auditd event | Đã ghi nhận useradd/passwd/userdel qua audit key |
| T14 | Fresh VM deployment | Chưa kiểm thử |
| T15 | Sinh TLS mới bằng script và tạo audit mới | Chưa kiểm thử độc lập |
| T16 | verify.sh phát hiện policy sai | Chưa có output xác nhận |

## Tái kiểm tra an toàn
```bash
find scripts -type f -name '*.sh' -print0 | xargs -0 -r shellcheck -x
sudo ./scripts/verify.sh
./scripts/run_lynis.sh compare
sudo ss -lntp
sudo ufw status verbose
```

Kiểm tra PAM bằng phiên SSH mới: ulimit -Sc và ulimit -Hc phải bằng 0; chưa có output xác nhận sau migration. Kiểm thử ghi dữ liệu/ban IP/tạo tài khoản là thao tác thay đổi trạng thái, không nằm trong verify mặc định. Không chạy fault injection trên server production.
