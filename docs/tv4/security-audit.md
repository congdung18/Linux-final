# Lynis Security Audit

Công cụ: Lynis 3.0.7 trên Ubuntu 22.04.5 LTS. Baseline được lấy sau khi đã triển khai các thành phần web và bảo mật cơ bản, không phải hệ điều hành sạch.

| Chỉ số | Before | After | Thay đổi |
|---|---:|---:|---:|
| Hardening Index | 63 | 69 | +6 |
| Warnings | 1 | 1 | 0 |
| Suggestions | 49 | 40 | -9 |

## Ba nhóm biện pháp
| Test ID | Biện pháp thực tế | Số suggestion không còn xuất hiện |
|---|---|---:|
| KRNL-5820 | PAM core limits và systemd LimitCORE=0 cho backend | 1 |
| PKGS-7370 | Cài debsums để kiểm tra tính toàn vẹn package | 1 |
| SSH-7408 | AllowAgentForwarding no, AllowTcpForwarding no, ClientAliveCountMax 2, Compression no, LogLevel VERBOSE, MaxSessions 2, TCPKeepAlive no | 7 |

ClientAliveInterval=300 được cấu hình bổ sung. Báo cáo so sánh không có suggestion mới. Các mã thực tế khác danh sách ví dụ trong tài liệu phân công; cần thống nhất báo cáo nhóm theo kết quả đo thực tế.

TIME-3185 xuất hiện ở lần quét trung gian. NTP đã được xác minh đồng bộ và sau lần quét kế tiếp cảnh báo biến mất. Bản quét mới được dùng làm after chính thức. PKGS-7392 vẫn còn, chưa xác định/gỡ bỏ toàn bộ package dễ bị tổn thương. Không che giấu cảnh báo này.

Minh chứng: [Lynis Before/After](../../screenshots/tv4/06_lynis_comparison.png).

## Tái lập và lưu báo cáo
```bash
sudo ./scripts/run_lynis.sh before
# Áp dụng các biện pháp hardening đã chọn.
sudo ./scripts/run_lynis.sh after
./scripts/run_lynis.sh compare
```

Trên VM hiện tại chỉ chạy compare; before/after đã tồn tại và không được ghi đè. Có thể dùng --output DIR cho thử nghiệm riêng. Báo cáo nằm tại ~/security-audit/lynis; raw log giữ cục bộ, không commit. Chức năng tạo báo cáo mới bằng script chưa được kiểm thử trực tiếp; so sánh và chống ghi đè đã đạt. Điểm 69 là chỉ số Lynis, không phải tỷ lệ an toàn tuyệt đối.
