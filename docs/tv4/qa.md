# Câu hỏi vấn đáp TV4

**1. Reverse proxy khác forward proxy thế nào?** Reverse proxy đại diện server phía sau; forward proxy đại diện client đi ra ngoài.

**2. Vì sao backend chỉ bind loopback?** Để client không truy cập trực tiếp, đi qua Nginx; UFW là lớp bảo vệ bổ sung.

**3. SAN có ý nghĩa gì?** Danh sách danh tính DNS được certificate xác nhận; certificate lab có cả app và status.

**4. Self-signed có mã hóa không?** Có, nhưng client phải thiết lập tin cậy chủ động; không có chuỗi CA công cộng mặc định.

**5. 301 khác 302?** 301 là chuyển hướng lâu dài; 302 là tạm thời. Client có thể đổi phương thức POST thành GET khi theo 301, nên API nên gọi HTTPS trực tiếp.

**6. Fail2ban hoạt động ra sao?** Filter đọc log, jail áp dụng chính sách và action chặn IP. Không thay thế SSH key authentication hoặc firewall.

**7. Auditd khác Fail2ban?** Auditd ghi bằng chứng sự kiện để truy vết, không mặc định ngăn thao tác; Fail2ban phản ứng bằng chặn IP.

**8. auid khác uid?** auid là login UID ban đầu, hữu ích truy vết qua sudo; uid phản ánh danh tính tiến trình hiện tại.

**9. Vì sao cần cả sshd -t và sshd -T?** Một lệnh kiểm tra hợp lệ, một lệnh hiển thị cấu hình hiệu lực; Match cần kiểm tra theo ngữ cảnh bổ sung.

**10. flock giải quyết gì?** Ngăn các tiến trình cùng tuân thủ một lock triển khai đồng thời. Không ngăn người sửa file thủ công hoặc script dùng lock khác.

**11. Idempotency là gì?** Cùng cấu hình đầu vào cho cùng trạng thái mong muốn; script vẫn có thể reload và tạo backup.

**12. Rollback có đảm bảo mọi thứ không?** Không. File được quản lý có thể phục hồi, nhưng trạng thái kernel, APT và sự cố mất điện không được bảo đảm hoàn toàn.

**13. Vì sao dùng envsubst có whitelist?** Để chỉ thay biến triển khai và giữ nguyên biến runtime Nginx.

**14. Lynis tăng từ 63 lên 69 nói lên gì?** Chỉ số hardening cải thiện theo công cụ; 9 suggestion biến mất, không chứng minh hệ thống không còn lỗ hổng.

**15. Vì sao health và API read đều cần kiểm tra?** Health chứng minh Flask phản hồi; API read kiểm tra thêm đường kết nối database.

**16. PAM limits khác LimitCORE?** PAM áp dụng cho phiên đăng nhập mới; systemd áp dụng cho tiến trình service được khởi tạo với limit tương ứng.

**17. Hạn chế production?** TLS cũ còn khai báo, package warning chưa xử lý, Flask development server, chứng chỉ tự ký và chưa kiểm thử trên VM sạch.
