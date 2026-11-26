#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_FILE=""
TOTAL=0
PASSED=0
FAILED=0

CERT_FILE="/etc/nginx/ssl/linux-lab.crt"
KEY_FILE="/etc/nginx/ssl/linux-lab.key"

RED=""
GREEN=""
CYAN=""
RESET=""

usage() {
    cat <<'EOF'
Usage: verify_tv4.sh [OPTIONS]

Verify Web, TLS and Security for Linux Final Lab.

Options:
  -c, --config FILE   Use a custom configuration file
  -h, --help         Show this help message

Exit codes:
  0   All checks passed
  1   One or more checks failed
EOF
}

init_colors() {
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        RED=$'\033[31m'
        GREEN=$'\033[32m'
        CYAN=$'\033[36m'
        RESET=$'\033[0m'
    fi
}

section() {
    printf '\n%s=== %s ===%s\n' \
        "$CYAN" "$1" "$RESET"
}

check() {
    local description="$1"
    shift

    local output

    TOTAL=$((TOTAL + 1))

    if output=$("$@" 2>&1); then
        PASSED=$((PASSED + 1))

        printf '%s[PASS]%s %s\n' \
            "$GREEN" "$RESET" "$description"
    else
        FAILED=$((FAILED + 1))

        printf '%s[FAIL]%s %s\n' \
            "$RED" "$RESET" "$description"

        if [[ -n "$output" ]]; then
            printf '       %s\n' "$output"
        fi
    fi
}

validate_config() {
    validate_domain "${APP_DOMAIN:?APP_DOMAIN is required}"
    validate_domain "${STATUS_DOMAIN:?STATUS_DOMAIN is required}"

    validate_port "${HTTP_PORT:?HTTP_PORT is required}"
    validate_port "${HTTPS_PORT:?HTTPS_PORT is required}"
    validate_port "${SSH_PORT:?SSH_PORT is required}"
    validate_port "${BACKEND_PORT:?BACKEND_PORT is required}"

    [[ "${BACKEND_HOST:?BACKEND_HOST is required}" == 127.0.0.1 ]] ||
        die "Backend must use IPv4 loopback"

    [[ "${BACKEND_SERVICE:?BACKEND_SERVICE is required}" \
        =~ ^[a-zA-Z0-9_-]+$ ]] ||
        die "Invalid backend service"

    BACKEND_UNIT="${BACKEND_SERVICE}.service"

    if [[ "$HTTPS_PORT" == 443 ]]; then
        HTTPS_REDIRECT_PORT=""
    else
        HTTPS_REDIRECT_PORT=":$HTTPS_PORT"
    fi
}

http_request() {
    local domain="$1"
    local path="$2"

    curl --silent --show-error \
        --noproxy '*' \
        --connect-timeout 5 \
        --max-time 15 \
        --resolve "$domain:$HTTP_PORT:127.0.0.1" \
        --output /dev/null \
        --write-out '%{http_code} %{redirect_url}' \
        "http://$domain:$HTTP_PORT$path"
}

https_request() {
    local domain="$1"
    local path="$2"

    curl --fail --silent --show-error \
        --noproxy '*' \
        --connect-timeout 5 \
        --max-time 15 \
        --cacert "$CERT_FILE" \
        --resolve "$domain:$HTTPS_PORT:127.0.0.1" \
        "https://$domain:$HTTPS_PORT$path"
}

check_redirect() {
    local domain="$1"
    local path="$2"
    local actual
    local expected

    actual="$(http_request "$domain" "$path")" ||
        return 1

    expected="301 https://$domain$HTTPS_REDIRECT_PORT$path"

    if [[ "$actual" != "$expected" ]]; then
        printf 'Expected: %s\nActual: %s\n' \
            "$expected" "$actual"
        return 1
    fi
}

check_status_site() {
    https_request "$STATUS_DOMAIN" "/" >/dev/null
}

check_unknown_host() {
    local code

    code="$(
        curl --silent --show-error \
            --noproxy '*' \
            --connect-timeout 5 \
            --max-time 15 \
            --header 'Host: unknown.invalid' \
            --output /dev/null \
            --write-out '%{http_code}' \
            "http://127.0.0.1:$HTTP_PORT/"
    )" || return 1

    [[ "$code" == 404 ]]
}

check_certificate() {
    openssl x509 \
        -in "$CERT_FILE" \
        -checkend 0 \
        -noout
}

check_certificate_domain() {
    local domain="$1"

    openssl verify \
        -purpose sslserver \
        -CAfile "$CERT_FILE" \
        -verify_hostname "$domain" \
        "$CERT_FILE"
}

check_private_key() {
    local cert_hash
    local key_hash

    cert_hash="$(
        openssl x509 -in "$CERT_FILE" -pubkey -noout |
        sha256sum
    )" || return 1

    key_hash="$(
        openssl pkey -in "$KEY_FILE" -pubout |
        sha256sum
    )" || return 1

    [[ "$cert_hash" == "$key_hash" ]]
}

check_health() {
    local response

    response="$(https_request "$APP_DOMAIN" /health)" ||
        return 1

    python3 -c '
import json
import sys

data = json.load(sys.stdin)
sys.exit(0 if data.get("status") == "healthy" else 1)
' <<< "$response"
}

check_database_api() {
    local response

    response="$(https_request "$APP_DOMAIN" /api/items)" ||
        return 1

    python3 -c '
import json
import sys

data = json.load(sys.stdin)
valid = (
    data.get("status") == "success"
    and isinstance(data.get("data"), list)
)

sys.exit(0 if valid else 1)
' <<< "$response"
}

check_fail2ban_value() {
    local property="$1"
    local expected="$2"
    local actual

    actual="$(
        fail2ban-client get sshd "$property"
    )" || return 1

    if [[ "$actual" != "$expected" ]]; then
        printf 'Expected: %s\nActual: %s\n' \
            "$expected" "$actual"
        return 1
    fi
}

check_audit_rule() {
    local expected="$1"
    local rules

    rules="$(auditctl -l)" || return 1

    grep -Fxq -- "$expected" <<< "$rules"
}

check_audit_enabled() {
    local status

    status="$(auditctl -s)" || return 1

    grep -Eq '^enabled [12]$' <<< "$status"
}

check_ssh_setting() {
    local expected="$1"
    local effective

    effective="$(sshd -T)" || return 1

    grep -Fxq -- "$expected" <<< "$effective"
}

check_systemd_core_limit() {
    local hard
    local soft

    hard="$(
        systemctl show "$BACKEND_UNIT" \
            -p LimitCORE --value
    )" || return 1

    soft="$(
        systemctl show "$BACKEND_UNIT" \
            -p LimitCORESoft --value
    )" || return 1

    [[ "$hard" == 0 && "$soft" == 0 ]]
}

check_process_core_limit() {
    local pid

    pid="$(
        systemctl show "$BACKEND_UNIT" \
            -p MainPID --value
    )" || return 1

    [[ "$pid" =~ ^[1-9][0-9]*$ ]] ||
        return 1

    grep -Eq \
        '^Max core file size[[:space:]]+0[[:space:]]+0[[:space:]]' \
        "/proc/$pid/limits"
}

print_summary() {
    printf '\n========================================\n'
    printf '          VERIFICATION SUMMARY\n'
    printf '========================================\n'
    printf 'Total checks : %d\n' "$TOTAL"
    printf '%sPassed       : %d%s\n' \
        "$GREEN" "$PASSED" "$RESET"
    printf '%sFailed       : %d%s\n' \
        "$RED" "$FAILED" "$RESET"
    printf '========================================\n'

    if (( FAILED == 0 )); then
        printf '%s[PASS] All checks passed.%s\n' \
            "$GREEN" "$RESET"
        return 0
    fi

    printf '%s[FAIL] Some checks failed.%s\n' \
        "$RED" "$RESET"

    return 1
}

while (( $# > 0 )); do
    case "$1" in
        -c|--config)
            (( $# >= 2 )) ||
                die "Missing configuration path"

            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

require_root

load_config "$CONFIG_FILE"
validate_config

require_command \
    nginx openssl curl python3 \
    systemctl sshd fail2ban-client \
    auditctl grep sha256sum

init_colors

printf '\n========================================\n'
printf '      LINUX FINAL - TV4 VERIFICATION\n'
printf '========================================\n'
printf 'Host: %s\n' "$(hostname)"
printf 'Time: %s\n' "$(date '+%F %T %Z')"

section "System Services"

for service in \
    nginx mariadb "$BACKEND_UNIT" \
    ssh fail2ban auditd
do
    check "$service is active" \
        systemctl is-active --quiet "$service"
done

section "Nginx and Virtual Hosts"

check "Nginx configuration valid" nginx -t

check "Application HTTP redirect" \
    check_redirect "$APP_DOMAIN" /health

check "Status HTTP redirect" \
    check_redirect "$STATUS_DOMAIN" /

check "HTTPS status website" \
    check_status_site

check "Unknown virtual host rejected" \
    check_unknown_host

section "TLS Certificate"

check "Certificate is not expired" \
    check_certificate

check "Certificate valid for $APP_DOMAIN" \
    check_certificate_domain "$APP_DOMAIN"

check "Certificate valid for $STATUS_DOMAIN" \
    check_certificate_domain "$STATUS_DOMAIN"

check "Certificate and private key match" \
    check_private_key

section "Backend Integration"

check "HTTPS backend health endpoint" \
    check_health

check "HTTPS database read endpoint" \
    check_database_api

section "Fail2ban"

check "SSH jail is active" \
    fail2ban-client status sshd

check "SSH maxretry policy" \
    check_fail2ban_value maxretry "$F2B_MAXRETRY"

check "SSH findtime policy" \
    check_fail2ban_value findtime "$F2B_FINDTIME"

check "SSH bantime policy" \
    check_fail2ban_value bantime "$F2B_BANTIME"

section "Auditd"

check "Audit subsystem enabled" \
    check_audit_enabled

check "Monitoring /etc/passwd" \
    check_audit_rule \
    '-w /etc/passwd -p wa -k passwd_changes'

check "Monitoring /etc/shadow" \
    check_audit_rule \
    '-w /etc/shadow -p wa -k shadow_changes'

section "SSH Hardening"

for setting in \
    "allowtcpforwarding no" \
    "allowagentforwarding no" \
    "compression no" \
    "clientaliveinterval 300" \
    "clientalivecountmax 2" \
    "tcpkeepalive no" \
    "loglevel VERBOSE" \
    "maxsessions 2"
do
    check "SSH $setting" \
        check_ssh_setting "$setting"
done

section "Core Dump Protection"

check "Systemd core dump limits" \
    check_systemd_core_limit

check "Running backend core dump limits" \
    check_process_core_limit

print_summary
