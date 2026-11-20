#!/usr/bin/env bash
# ==============================================================================
# Script Thiet Lap Tuong Lua UFW (Member 1: Ha tang & Mang)
# Du an: He dieu hanh Linux & Ung dung - DHQG-HCM KHTN
# ==============================================================================

set -euo pipefail

echo "[+] Bat dau cau hinh tuong lua UFW..."

# 1. Mac dinh chan tat ca ket noi chieu vao, cho phep chieu ra
echo "[+] Thiet lap default deny incoming, default allow outgoing..."
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 2. Mo cac cong dich vu can thiet theo dung bao cao
echo "[+] Mo cac cong dich vu:"
# Port 2222: Cổng SSH tuy chỉnh gia cố bảo mật (thay cổng 22)
sudo ufw allow 2222/tcp comment 'Custom SSH Service'

# Port 80: HTTP de tiep nhan va chuyen huong 301 sang HTTPS
sudo ufw allow 80/tcp comment 'HTTP Web Service'

# Port 443: HTTPS dich vu Web chinh phuc vu cac Virtual Hosts
sudo ufw allow 443/tcp comment 'HTTPS Web Service'

# 3. Kich hoat tuong lua
echo "[+] Kich hoat va ap dung luat UFW..."
sudo ufw --force enable

# 4. Kiem tra trang thai
sudo ufw status verbose

echo "[✓] Hoan tat cau hinh tuong lua UFW an toan."
