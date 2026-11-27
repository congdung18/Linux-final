#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_FILE=""
STAGING_DIR=""
BACKUP_DIR=""
TRANSACTION_ACTIVE=false
NGINX_WAS_ACTIVE=false

MANAGED_FILES=(
    /etc/nginx/sites-available/app.conf
    /etc/nginx/sites-available/status.conf
    /etc/nginx/sites-available/catch-all.conf
    /etc/nginx/sites-enabled/app.conf
    /etc/nginx/sites-enabled/status.conf
    /etc/nginx/sites-enabled/catch-all.conf
    /etc/nginx/sites-enabled/default
    /etc/nginx/conf.d/proxy-log.conf
    /etc/nginx/snippets/linux-lab-tls.conf
    /etc/nginx/ssl/linux-lab.crt
    /etc/nginx/ssl/linux-lab.key
    /var/www/status/index.html
)

usage() {
    cat <<'EOF'
Usage: setup_web.sh [OPTIONS]

Deploy Nginx, virtual hosts and TLS for Linux Final Lab.

Options:
  -c, --config FILE   Use a custom configuration file
  -h, --help         Show this help message
EOF
}

prepare_dependencies() {
    local package
    local -a missing=()

    for package in nginx openssl gettext-base curl; do
        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
            grep -qx 'install ok installed'; then
            missing+=("$package")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log_info "Installing: ${missing[*]}"
        apt-get update
        apt-get install -y "${missing[@]}"
    else
        log_success "All dependencies are installed."
    fi
}

validate_config() {
    validate_domain "${APP_DOMAIN:?APP_DOMAIN is required}"
    validate_domain "${STATUS_DOMAIN:?STATUS_DOMAIN is required}"

    [[ "${APP_DOMAIN,,}" != "${STATUS_DOMAIN,,}" ]] ||
        die "Virtual host domains must be different"

    validate_port "${HTTP_PORT:?HTTP_PORT is required}"
    validate_port "${HTTPS_PORT:?HTTPS_PORT is required}"
    validate_port "${BACKEND_PORT:?BACKEND_PORT is required}"

    [[ "$HTTP_PORT" != "$HTTPS_PORT" ]] ||
        die "HTTP and HTTPS ports must be different"

    [[ "${BACKEND_HOST:?BACKEND_HOST is required}" == "127.0.0.1" ]] ||
        die "Backend must use the IPv4 loopback address"

    if [[ "$HTTPS_PORT" == "443" ]]; then
        HTTPS_REDIRECT_PORT=""
    else
        HTTPS_REDIRECT_PORT=":$HTTPS_PORT"
    fi

    export APP_DOMAIN STATUS_DOMAIN
    export HTTP_PORT HTTPS_PORT
    export BACKEND_HOST BACKEND_PORT
    export HTTPS_REDIRECT_PORT
}

render_templates() {
    local site
    local variables

    # Keep variable names literal for envsubst.
    # shellcheck disable=SC2016
    variables='${APP_DOMAIN} ${STATUS_DOMAIN} ${HTTP_PORT} ${HTTPS_PORT} ${BACKEND_HOST} ${BACKEND_PORT} ${HTTPS_REDIRECT_PORT}'

    STAGING_DIR="$(mktemp -d)"

    for site in app status catch-all; do
        envsubst "$variables" \
            < "$PROJECT_ROOT/configs/nginx/sites-available/$site.conf.template" \
            > "$STAGING_DIR/$site.conf"
    done

    log_success "Nginx templates rendered."
}

backup_configuration() {
    local path

    install -d -m 700 /var/backups/linux-final

    BACKUP_DIR="$(
        mktemp -d /var/backups/linux-final/web.XXXXXXXX
    )"

    for path in "${MANAGED_FILES[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
            mkdir -p "$BACKUP_DIR$(dirname "$path")"

            cp -a -- "$path" "$BACKUP_DIR$path"
        fi
    done

    if systemctl is-active --quiet nginx; then
        NGINX_WAS_ACTIVE=true
    fi

    TRANSACTION_ACTIVE=true

    log_info "Backup created: $BACKUP_DIR"
}

restore_configuration() {
    local path
    local failed=0

    log_warning "Restoring previous configuration..."

    for path in "${MANAGED_FILES[@]}"; do
        if ! rm -f -- "$path"; then
            failed=1
            continue
        fi

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
        log_warning "Some files could not be restored."
        return 1
    fi

    if [[ "$NGINX_WAS_ACTIVE" == true ]]; then
        nginx -t || return 1
        systemctl reload-or-restart nginx || return 1
    else
        systemctl stop nginx || return 1
    fi

    log_success "Previous configuration restored."
}

cleanup() {
    local exit_code=$?

    trap - EXIT
    set +e

    if (( exit_code != 0 )) &&
        [[ "$TRANSACTION_ACTIVE" == true ]]; then

        restore_configuration ||
            log_warning "Automatic rollback failed. Check $BACKUP_DIR"
    fi

    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi

    exit "$exit_code"
}

prepare_tls() {
    local -a args=()

    if [[ -n "$CONFIG_FILE" ]]; then
        args+=(--config "$CONFIG_FILE")
    fi

    bash "$SCRIPT_DIR/generate_tls.sh" "${args[@]}"
}

install_configuration() {
    local site

    install -d -m 755 \
        /etc/nginx/sites-available \
        /etc/nginx/sites-enabled \
        /etc/nginx/conf.d \
        /etc/nginx/snippets \
        /var/www/status

    for site in app status catch-all; do
        install -o root -g root -m 644 \
            "$STAGING_DIR/$site.conf" \
            "/etc/nginx/sites-available/$site.conf"

        ln -sfn \
            "/etc/nginx/sites-available/$site.conf" \
            "/etc/nginx/sites-enabled/$site.conf"
    done

    install -o root -g root -m 644 \
        "$PROJECT_ROOT/configs/nginx/conf.d/proxy-log.conf" \
        /etc/nginx/conf.d/proxy-log.conf

    install -o root -g root -m 644 \
        "$PROJECT_ROOT/configs/nginx/snippets/linux-lab-tls.conf" \
        /etc/nginx/snippets/linux-lab-tls.conf

    install -o root -g root -m 644 \
        "$PROJECT_ROOT/configs/nginx/html/status/index.html" \
        /var/www/status/index.html

    rm -f /etc/nginx/sites-enabled/default

    log_success "Nginx configuration installed."
}

activate_nginx() {
    log_info "Validating Nginx configuration..."

    nginx -t

    systemctl reload-or-restart nginx
    systemctl is-active --quiet nginx

    log_success "Nginx is running."
}

verify_web() {
    local cert="/etc/nginx/ssl/linux-lab.crt"
    local redirect
    local expected

    expected="https://$APP_DOMAIN$HTTPS_REDIRECT_PORT/health"

    redirect="$(
        curl --silent --show-error \
            --noproxy '*' \
            --connect-timeout 5 \
            --max-time 15 \
            --resolve "$APP_DOMAIN:$HTTP_PORT:127.0.0.1" \
            --output /dev/null \
            --write-out '%{http_code} %{redirect_url}' \
            "http://$APP_DOMAIN:$HTTP_PORT/health"
    )"

    [[ "$redirect" == "301 $expected" ]] ||
        die "Unexpected HTTP redirect: $redirect"

    curl --fail --silent --show-error \
        --noproxy '*' \
        --connect-timeout 5 \
        --max-time 15 \
        --cacert "$cert" \
        --resolve "$STATUS_DOMAIN:$HTTPS_PORT:127.0.0.1" \
        "https://$STATUS_DOMAIN:$HTTPS_PORT/" \
        >/dev/null

    log_success "HTTP redirect and HTTPS status site verified."
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

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_command flock install

LOCK_DIR="/run/linux-final"
LOCK_FILE="$LOCK_DIR/web.lock"

install -d -o root -g root -m 700 "$LOCK_DIR"

exec 9>"$LOCK_FILE"

flock -n 9 ||
    die "Another web deployment is running"

prepare_dependencies

require_command nginx openssl envsubst curl

render_templates
backup_configuration
prepare_tls
install_configuration
activate_nginx
verify_web

systemctl enable nginx

TRANSACTION_ACTIVE=false

log_success "Web deployment completed."
log_info "Application: https://$APP_DOMAIN$HTTPS_REDIRECT_PORT"
log_info "Status: https://$STATUS_DOMAIN$HTTPS_REDIRECT_PORT"
log_info "Backup: $BACKUP_DIR"
