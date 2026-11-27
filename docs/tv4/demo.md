# Kịch bản demo TV4 (2–3 phút)

Chuẩn bị trước: VM srv-main đang chạy, console dự phòng, hai hostname đã ánh xạ, chứng chỉ công khai được xác minh, mở sẵn terminal và ảnh minh chứng.

| Thời lượng | Nội dung |
|---|---|
| 0:00–0:40 | Hai virtual host, HTTPS và redirect 301 |
| 0:40–1:20 | Fail2ban và Auditd: chính sách, nhật ký ban/unban và event |
| 1:20–2:00 | Lynis Before/After, giải thích 3 nhóm hardening |
| 2:00–3:00 | verify.sh 34 bài kiểm tra, ShellCheck và bằng chứng rollback |

Minh chứng dự phòng: [6 ảnh thực tế](../../screenshots/tv4/README.md). Ảnh/log không thay thế yêu cầu demo trực tiếp.

## Lệnh trình diễn
```bash
curl -I -H 'Host: app.linux.local' http://127.0.0.1/health
sudo curl --cacert /etc/nginx/ssl/linux-lab.crt \
  --resolve app.linux.local:443:127.0.0.1 https://app.linux.local/health
sudo openssl x509 -in /etc/nginx/ssl/linux-lab.crt -noout -dates -ext subjectAltName
sudo fail2ban-client status sshd
sudo grep -E '\[sshd\].*(Ban|Unban)' /var/log/fail2ban.log
sudo auditctl -l
sudo ausearch -k passwd_changes -i | tail -n 20
./scripts/run_lynis.sh compare
sudo ./scripts/verify.sh
```

Mục 3.3 của đề bài yêu cầu trình diễn ban trực tiếp. Khi live ban, dùng máy test riêng có quyền và console VM dự phòng; không dùng kết nối quản trị duy nhất. Khôi phục IP test sau demo. Nếu cần live audit, dùng tài khoản thử nghiệm riêng rồi dọn dẹp; không thay đổi tài khoản thật. Nếu log đã rotate, dùng minh chứng đã lưu. Không trình bày ảnh hoặc output minh họa như kết quả thật.
