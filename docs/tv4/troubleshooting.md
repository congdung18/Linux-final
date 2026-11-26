# Xử lý lỗi

| Triệu chứng | Nguyên nhân / cách xử lý |
|---|---|
| SSH timeout khi ssh srv-main | Kiểm tra ssh -G srv-main; port phải là 2222; kiểm tra UFW và jail trước khi kết luận lỗi mạng. |
| Illegal option -o pipefail / SC1128 | Shebang phải nằm dòng đầu, không BOM; chạy bằng Bash, không xóa pipefail. |
| SC2016 ở envsubst | Dấu nháy đơn có chủ đích để truyền tên biến; chỉ suppress tại câu lệnh liên quan. |
| Permission denied /run/lock | File cũ thuộc user trong thư mục sticky; dùng /run/linux-final root 700; không tắt fs.protected_regular. |
| grep invalid option khi kiểm tra audit rule | Pattern bắt đầu bằng -; dùng grep -Fxq -- "$pattern". |
| SC1087 | Dùng ${type}[]= thay cho $type[]=. |
| Nginx 502 | Kiểm tra myapp.service và listener 127.0.0.1:5000. |
| /health 200 nhưng /api/items 500 | Health chỉ kiểm tra Flask; kiểm tra MariaDB và kết nối DB. |
| TLS không được tin cậy | Dùng đúng public certificate và hostname; xác minh fingerprint qua kênh tin cậy. |
| SSH hardening không có hiệu lực | Kiểm tra sshd -t, sshd -T, thứ tự Include và Match; không sửa tùy tiện auth policy. |
| Lynis TIME-3185 | Kiểm tra timedatectl và timesync-status; không thay đổi NTP nếu hoạt động đúng. |
| Lynis báo report already exists | Cơ chế bảo vệ minh chứng; dùng compare hoặc thư mục thử nghiệm riêng. |

## Khôi phục triển khai
Script in đường dẫn backup khi chạy. Kiểm tra file backup tương ứng và trạng thái dịch vụ. Nếu rollback tự động thất bại, dùng console VM, khôi phục các file được quản lý từ backup phù hợp, chạy nginx -t hoặc sshd -t trước khi reload. Không xóa lock file đang được tiến trình sử dụng. Backup chứa khóa TLS cần được bảo vệ.
