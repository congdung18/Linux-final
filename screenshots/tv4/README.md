# Minh chứng TV4

| Ảnh | Nội dung cần đối chiếu |
|---|---|
| [01 — HTTPS API](01_https_app.png) | HTTP 200, dữ liệu MariaDB qua Nginx và Flask |
| [02 — Status](02_https_status.png) | Virtual host tĩnh qua HTTPS |
| [03 — TLS và redirect](03_tls_redirect.png) | HTTP 301, chứng chỉ tự ký, hai SAN |
| [04 — Fail2ban](04_fail2ban.png) | Jail SSH và lịch sử ban/unban |
| [05 — Auditd](05_auditd.png) | Hai rule và sự kiện kiểm toán tài khoản |
| [06 — Lynis](06_lynis_comparison.png) | Index 63 → 69; suggestions 49 → 40 |

Kết quả kiểm thử và giới hạn: [test-cases.md](../../docs/tv4/test-cases.md).
Ảnh do thành viên thu thập; cần rà soát nội dung, không công khai mật khẩu, token, khóa riêng hoặc raw audit log.
