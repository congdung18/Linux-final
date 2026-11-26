#!/usr/bin/env bash

PROJECT_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

log_info() {
    printf '[INFO] %s\n' "$*"
}

log_success() {
    printf '[OK] %s\n' "$*"
}

log_warning() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

require_root() {
    if (( EUID != 0 )); then
        die "This script must be run as root."
    fi
}

require_command() {
    local cmd

    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "Required command not found: $cmd"
    done
}

load_config() {
    local config_file="${1:-}"

    if [[ -z "$config_file" ]]; then
        config_file="$PROJECT_ROOT/configs/security/tv4.conf"

        if [[ ! -f "$config_file" ]]; then
            config_file="$PROJECT_ROOT/configs/security/tv4.conf.example"
        fi
    fi

    [[ -f "$config_file" ]] ||
        die "Configuration not found: $config_file"

    # Only load trusted administrator-controlled configuration files.
    # shellcheck disable=SC1090
    source "$config_file"
}

validate_domain() {
    local domain="$1"
    local label
    local -a labels

    [[ ${#domain} -le 253 ]] ||
        die "Domain is too long: $domain"

    [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] ||
        die "Invalid domain: $domain"

    [[ "$domain" != .* &&
       "$domain" != *. &&
       "$domain" != *..* ]] ||
        die "Invalid domain: $domain"

    IFS='.' read -r -a labels <<< "$domain"

    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 &&
           "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] ||
            die "Invalid domain label: $label"
    done
}

validate_port() {
    local port="$1"

    [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] ||
        die "Invalid port: $port"

    (( port <= 65535 )) ||
        die "Port out of range: $port"
}
