#!/usr/bin/env bash

set -euo pipefail

show_help() {
	cat << "HELP"
Using: health_check.sh
Checking CPU, RAM, disk, network ports and service status
Announce alert when detected anomaly surpassing the threshold

Options:
 -c, --cpu NUM	percentage of CPU used
 -m, --mem NUM	percentage of RAM used
 -d, --disk NUM	percentage of disk used
 -h, --help	display helps
HELP
	exit 0
}

CPU_THRESHOLD=80
MEM_THRESHOLD=85
DISK_THRESHOLD=80
LOG_FILE="/var/log/system_health.log"
ALERT_TRIGGERED=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		-c|--cpu) CPU_THRESHOLD="$2"; shift 2 ;;
		-m|--mem) MEM_THRESHOLD="$2"; shift 2 ;;
		-d|--disk) DISK_THRESHOLD="$2"; shift 2 ;;
		-h|--help) show_help ;;
		*) echo "Invalid option: $1" >&2; exit 1 ;;
	esac
done

# Error handling
trap 'echo "[!] Error: unexpected error occured during exam at $LINENO" >&2; exit 1' ERR

send_alert() {
	local level="$1"
	local message="$2"
	local alert_msg
	ALERT_TRIGGERED=1
	alert_msg="[ALERT ${level}] $(date '+%Y-%m-%d %H:%M:%S') - ${message}"
	echo "${alert_msg}" >&2
	echo "${alert_msg}" | sudo tee -a "${LOG_FILE}" > /dev/null
}

echo "[+] Starting health checking the system: $(date '+%Y-%m-%d %H:%M:%S')"

# Check disk usage
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
echo "[+] Original disk capacity: ${DISK_USAGE}% (Disk threshold: ${DISK_THRESHOLD}%)"
if (( DISK_USAGE > DISK_THRESHOLD )); then
	send_alert "DISK" "Disk capacity surpasses the threshold: ${DISK_USAGE}%"
fi

# Check RAM usage
MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
echo "[+] RAM used: ${MEM_USAGE}% (RAM threshold: ${MEM_THRESHOLD}%)"
if (( MEM_USAGE > MEM_THRESHOLD )); then
	send_alert "RAM" "RAM memory surpasses: ${MEM_USAGE}%"
fi

# Check CPU usage
CPU_USAGE=$(top -bn1 | awk '/Cpu\(s\)/ {printf("%.0f"), $2 + $4}')
echo "[+] CPU usage: ${CPU_USAGE}% (CPU threshold: ${CPU_THRESHOLD}%)"
if (( CPU_USAGE > CPU_THRESHOLD )); then
	send_alert "CPU" "CPU usaege surpasses: ${CPU_USAGE}%"
fi

# Check listening ports
echo "[+] Checking listening ports..."
REQUIRED_PORTS=(2222 80 443 3306 5000)
for port in "${REQUIRED_PORTS[@]}"; do
	if ss -tulpn | grep -q "${port} "; then
		echo "[/] Port ${port}: working"
	else
		send_alert "PORT" "Port ${port} is not listening"
	fi
done

# Check systemd services
echo "[+] Checking services status..."
SERVICES=(nginx mariadb myapp fail2ban auditd)
for srv in "${SERVICES[@]}"; do
	if systemctl is-active --quiet "${srv}"; then
		echo "[/] Service ${srv}: working"
	else
		send_alert "SERVICE" "Service ${srv} is not working"
	fi
done

if (( ALERT_TRIGGERED == 0 )); then
	echo "[/] System is totally fine, all services healty"
else
	echo "[!] Error: reported in ${LOG_FILE}"
fi
