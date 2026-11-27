#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_FILE=""
BACKUP_DIR=""
STAGING_DIR=""
TRANSACTION_ACTIVE=false
RESTART_BACKEND=false
AUDIT_CHANGED=false
BACKEND_RESTARTED=false

MANAGED_FILES=()

usage() {
    cat <<'EOF'
Usage: setup_security.sh [OPTIONS]

Deploy security configuration for Linux Final Lab.

Options:
  -c, --config FILE   Use a custom configuration file
  --restart-backend   Restart the backend to apply limits
  -h, --help          Show this help message
EOF
}

prepare_dependencies() {
    local package
    local -a missing=()

    for package in \
        fail2ban \
        auditd \
        audispd-plugins \
        debsums \
        lynis \
        gettext-base \
        rsyslog
    do
        if ! dpkg-query -W -f='${Status}' \
            "$package" 2>/dev/null |
            grep -qx 'install ok installed'; then

            missing+=("$package")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log_info "Installing: ${missing[*]}"

        apt-get update
        apt-get install -y "${missing[@]}"
    else
        log_success "All security dependencies are installed."
    fi
}

validate_positive_integer() {
    local value="$1"
    local name="$2"

    [[ "$value" =~ ^[1-9][0-9]{0,8}$ ]] ||
        die "Invalid value for $name: $value"
}

validate_config() {
    validate_port "${SSH_PORT:?SSH_PORT is required}"

    validate_positive_integer \
        "${F2B_MAXRETRY:?F2B_MAXRETRY is required}" \
        F2B_MAXRETRY

    validate_positive_integer \
        "${F2B_FINDTIME:?F2B_FINDTIME is required}" \
        F2B_FINDTIME

    validate_positive_integer \
        "${F2B_BANTIME:?F2B_BANTIME is required}" \
        F2B_BANTIME

    [[ "${BACKEND_SERVICE:?BACKEND_SERVICE is required}" \
        =~ ^[a-zA-Z0-9_-]+$ ]] ||
        die "Invalid backend service name"

    BACKEND_UNIT="${BACKEND_SERVICE}.service"

    SSH_CONFIG="/etc/ssh/sshd_config.d/50-tv4-hardening.conf"
    F2B_CONFIG="/etc/fail2ban/jail.d/sshd.local"
    AUDIT_CONFIG="/etc/audit/rules.d/50-identity.rules"
    CORE_CONFIG="/etc/security/limits.d/50-tv4-core.conf"

    SYSTEMD_CONFIG="/etc/systemd/system/$BACKEND_UNIT.d/50-security.conf"

    MANAGED_FILES=(
        "$SSH_CONFIG"
        "$F2B_CONFIG"
        "$AUDIT_CONFIG"
        "$CORE_CONFIG"
        "$SYSTEMD_CONFIG"
    )

    export SSH_PORT
    export F2B_MAXRETRY F2B_FINDTIME F2B_BANTIME
}

preflight() {
    local effective
    local audit_status
    local load_state

    sshd -t

    effective="$(sshd -T)"

    grep -Fxq "port $SSH_PORT" <<< "$effective" ||
        die "SSH_PORT does not match the effective SSH configuration"

    systemctl is-active --quiet ssh ||
        die "SSH service is not active"

    systemctl is-active --quiet rsyslog ||
        die "rsyslog service is not active"

    [[ -f /var/log/auth.log ]] ||
        die "SSH authentication log is missing"

    audit_status="$(auditctl -s)"

    grep -qx 'enabled 1' <<< "$audit_status" ||
        die "Audit subsystem must be enabled and mutable"

    systemctl is-active --quiet auditd ||
        die "Auditd service is not active"

    load_state="$(
        systemctl show "$BACKEND_UNIT" \
            -p LoadState --value
    )"

    [[ "$load_state" == loaded ]] ||
        die "Backend service is not installed: $BACKEND_UNIT"

    log_success "Security preflight passed."
}

render_configuration() {
    STAGING_DIR="$(mktemp -d)"

    # Keep variable names literal for envsubst.
    # shellcheck disable=SC2016
    local variables='${SSH_PORT} ${F2B_MAXRETRY} ${F2B_FINDTIME} ${F2B_BANTIME}'

    envsubst "$variables" \
        < "$PROJECT_ROOT/configs/fail2ban/sshd.local.template" \
        > "$STAGING_DIR/sshd.local"

    log_success "Fail2ban template rendered."
}

backup_configuration() {
    local path

    install -d -o root -g root -m 700 \
        /var/backups/linux-final

    BACKUP_DIR="$(
        mktemp -d \
            /var/backups/linux-final/security.XXXXXXXX
    )"

    for path in "${MANAGED_FILES[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
            mkdir -p "$BACKUP_DIR$(dirname "$path")"

            cp -a -- "$path" "$BACKUP_DIR$path"
        fi
    done

    sshd -T > "$BACKUP_DIR/sshd-effective.txt"

    auditctl -l > "$BACKUP_DIR/audit-active.txt"

    TRANSACTION_ACTIVE=true

    log_info "Backup created: $BACKUP_DIR"
}

install_managed_file() {
    local source_file="$1"
    local target_file="$2"
    local mode="${3:-644}"

    mkdir -p "$(dirname "$target_file")"

    install -o root -g root -m "$mode" \
        "$source_file" "$target_file"
}

install_configuration() {
    install_managed_file \
        "$PROJECT_ROOT/configs/ssh/50-tv4-hardening.conf" \
        "$SSH_CONFIG"

    install_managed_file \
        "$STAGING_DIR/sshd.local" \
        "$F2B_CONFIG"

    if ! cmp -s \
        "$PROJECT_ROOT/configs/auditd/50-identity.rules" \
        "$AUDIT_CONFIG"; then

        AUDIT_CHANGED=true
    fi

    install_managed_file \
        "$PROJECT_ROOT/configs/auditd/50-identity.rules" \
        "$AUDIT_CONFIG" 640

    install_managed_file \
        "$PROJECT_ROOT/configs/security/core-limits.conf" \
        "$CORE_CONFIG"

    install_managed_file \
        "$PROJECT_ROOT/configs/systemd/myapp.service.d/50-security.conf" \
        "$SYSTEMD_CONFIG"

    log_success "Security configuration installed."
}

verify_ssh_policy() {
    local effective
    local expected

    effective="$(sshd -T)"

    local -a required=(
        "port $SSH_PORT"
        "permitrootlogin no"
        "pubkeyauthentication yes"
        "allowtcpforwarding no"
        "allowagentforwarding no"
        "compression no"
        "clientaliveinterval 300"
        "clientalivecountmax 2"
        "tcpkeepalive no"
        "loglevel VERBOSE"
        "maxsessions 2"
    )

    for expected in "${required[@]}"; do
        grep -Fxq "$expected" <<< "$effective" ||
            die "Effective SSH policy mismatch: $expected"
    done

    # Ensure existing authentication and access policies
    # have not changed.
    local auth_pattern

    auth_pattern='^(port|allowusers|allowgroups|denyusers|denygroups|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|authenticationmethods|permitpasswordlesslogin|permitemptypasswords|maxauthtries|x11forwarding) '

    diff -u \
        <(grep -E "$auth_pattern" \
            "$BACKUP_DIR/sshd-effective.txt") \
        <(grep -E "$auth_pattern" \
            <<< "$effective") ||
        die "Existing SSH access policy changed"

    log_success "Effective SSH policy verified."
}

validate_configuration() {
    sshd -t

    verify_ssh_policy

    fail2ban-client -t

    log_success "Security configuration validation passed."
}

audit_rules_present() {
    local rules

    rules="$(auditctl -l)" || return 1

    grep -Fxq -- \
        '-w /etc/passwd -p wa -k passwd_changes' \
        <<< "$rules" &&
    grep -Fxq -- \
        '-w /etc/shadow -p wa -k shadow_changes' \
        <<< "$rules"
}

apply_configuration() {
    systemctl reload ssh

    systemctl is-active --quiet ssh

    systemctl enable --now fail2ban

    fail2ban-client reload

    fail2ban-client status sshd >/dev/null

    if [[ "$AUDIT_CHANGED" == true ]] ||
        ! audit_rules_present; then

        AUDIT_CHANGED=true

        augenrules --load
    else
        log_info "Existing audit rules are already active."
    fi

    systemctl enable auditd

    systemctl daemon-reload

    if [[ "$RESTART_BACKEND" == true ]]; then
        BACKEND_RESTARTED=true

        systemctl restart "$BACKEND_UNIT"
    fi

    log_success "Security configuration applied."
}

verify_security() {
    local service
    local pid
    local limit

    for service in ssh fail2ban auditd; do
        systemctl is-active --quiet "$service" ||
            die "Service is inactive: $service"

        log_success "$service is active."
    done

    fail2ban-client status sshd >/dev/null

    audit_rules_present ||
        die "Required audit rules are missing"

    limit="$(
        systemctl show "$BACKEND_UNIT" \
            -p LimitCORE --value
    )"

    [[ "$limit" == 0 ]] ||
        die "Backend LimitCORE is not zero"

    pid="$(
        systemctl show "$BACKEND_UNIT" \
            -p MainPID --value
    )"

    if [[ "$pid" =~ ^[1-9][0-9]*$ ]] &&
        [[ -r "/proc/$pid/limits" ]]; then

        if grep -Eq \
            '^Max core file size[[:space:]]+0[[:space:]]+0' \
            "/proc/$pid/limits"; then

            log_success "Backend process core limits verified."
        else
            if [[ "$RESTART_BACKEND" == true ]]; then
                die "Backend process core limits were not applied"
            fi

            log_warning "Backend restart required to apply core limits."
        fi
    else
        if [[ "$RESTART_BACKEND" == true ]]; then
            die "Backend process is not running"
        fi

        log_warning "Backend process is not running."
    fi

    log_success "Security verification completed."
}

restore_configuration() {
    local path
    local failed=0

    log_warning "Restoring previous security configuration..."

    for path in "${MANAGED_FILES[@]}"; do
        rm -f -- "$path" || {
            failed=1
            continue
        }

        if [[ -e "$BACKUP_DIR$path" ||
              -L "$BACKUP_DIR$path" ]]; then

            mkdir -p "$(dirname "$path")" || {
                failed=1
                continue
            }

            cp -a -- "$BACKUP_DIR$path" "$path" ||
                failed=1
        fi
    done

    if (( failed != 0 )); then
        log_warning "Some configuration files could not be restored."
        return 1
    fi

    if sshd -t; then
        systemctl reload ssh || failed=1
    else
        failed=1
    fi

    if fail2ban-client -t; then
        fail2ban-client reload || failed=1
    else
        failed=1
    fi

    if [[ "$AUDIT_CHANGED" == true ]]; then
        augenrules --load || failed=1
    fi

    systemctl daemon-reload || failed=1

    if [[ "$BACKEND_RESTARTED" == true ]]; then
        systemctl restart "$BACKEND_UNIT" || failed=1
    fi

    (( failed == 0 )) || return 1

    log_success "Previous configuration restored."
}

cleanup() {
    local exit_code=$?

    trap - EXIT
    set +e

    if (( exit_code != 0 )) &&
        [[ "$TRANSACTION_ACTIVE" == true ]]; then

        restore_configuration ||
            log_warning "Rollback incomplete. Check $BACKUP_DIR"
    fi

    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi

    exit "$exit_code"
}

while (( $# > 0 )); do
    case "$1" in
        -c|--config)
            (( $# >= 2 )) ||
                die "Missing configuration path"

            CONFIG_FILE="$2"
            shift 2
            ;;
        --restart-backend)
            RESTART_BACKEND=true
            shift
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

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

install -d -o root -g root -m 700 \
    /run/linux-final

exec 9>/run/linux-final/security.lock

flock -n 9 ||
    die "Another security deployment is running"

prepare_dependencies

require_command \
    sshd \
    fail2ban-client \
    auditctl \
    augenrules \
    systemctl \
    envsubst \
    flock \
    cmp \
    diff

preflight
render_configuration
backup_configuration
install_configuration
validate_configuration
apply_configuration
verify_security

TRANSACTION_ACTIVE=false

log_success "Security deployment completed."
log_info "Backup: $BACKUP_DIR"
