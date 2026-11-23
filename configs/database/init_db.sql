-- init_db.sql - Khởi tạo CSDL appdb và user appuser (TV2).
-- Chạy trên srv-main:  sudo mariadb < configs/database/init_db.sql
-- Có thể chạy lại nhiều lần (idempotent).
-- Mật khẩu phải khớp DB_PASS trong /etc/myapp/app.env (TV3). Khi nộp báo cáo
-- nên đổi sang mật khẩu riêng, không dùng mật khẩu mẫu này.

CREATE DATABASE IF NOT EXISTS appdb
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE appdb;

CREATE TABLE IF NOT EXISTS items (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO items (name)
SELECT 'Ban ghi khoi tao mac dinh' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM items);

-- Đặc quyền tối thiểu: ứng dụng chỉ đọc và thêm, không sửa/xóa/DDL,
-- không có GRANT OPTION, không có quyền trên CSDL khác.
CREATE USER IF NOT EXISTS 'appuser'@'localhost' IDENTIFIED BY 'StudentAppPassword123!';
ALTER USER 'appuser'@'localhost' IDENTIFIED BY 'StudentAppPassword123!';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'appuser'@'localhost';
GRANT SELECT, INSERT ON appdb.* TO 'appuser'@'localhost';
FLUSH PRIVILEGES;

SHOW GRANTS FOR 'appuser'@'localhost';
