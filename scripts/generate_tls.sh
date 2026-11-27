#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/linux-lab.crt"
KEY_FILE="$SSL_DIR/linux-lab.key"

CONFIG_FILE=""
FORCE=false
TEMP_DIR=""

usage() {
    cat <<'EOF'
Usage: generate_tls.sh [OPTIONS]

Generate a self-signed TLS certificate for Linux Final Lab.

Options:
  -c, --config FILE   Use a custom configuration file
  -f, --force        Regenerate the certificate
  -h, --help         Show this help message
EOF
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

certificate_valid() {
    [[ -s "$CERT_FILE" && -s "$KEY_FILE" ]] ||
        return 1

    local cert_hash
    local key_hash
    local san

    cert_hash="$(
        openssl x509 -in "$CERT_FILE" -pubkey -noout |
        sha256sum
    )" || return 1

    key_hash="$(
        openssl pkey -in "$KEY_FILE" -pubout |
        sha256sum
    )" || return 1

    [[ "$cert_hash" == "$key_hash" ]] ||
        return 1

    openssl pkey -in "$KEY_FILE" -check -noout \
        >/dev/null 2>&1 || return 1

    openssl x509 -in "$CERT_FILE" \
        -checkend 2592000 -noout \
        >/dev/null 2>&1 || return 1

    san="$(
        openssl x509 -in "$CERT_FILE" \
            -noout -ext subjectAltName |
        tr ',' '\n' |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    )" || return 1

    grep -Fqx "DNS:$APP_DOMAIN" <<< "$san" ||
        return 1

    grep -Fqx "DNS:$STATUS_DOMAIN" <<< "$san" ||
        return 1

    openssl verify -purpose sslserver \
        -CAfile "$CERT_FILE" \
        -verify_hostname "$APP_DOMAIN" \
        "$CERT_FILE" >/dev/null 2>&1 ||
        return 1

    openssl verify -purpose sslserver \
        -CAfile "$CERT_FILE" \
        -verify_hostname "$STATUS_DOMAIN" \
        "$CERT_FILE" >/dev/null 2>&1 ||
        return 1

    return 0
}

while (( $# > 0 )); do
    case "$1" in
        -c|--config)
            (( $# >= 2 )) ||
                die "Missing configuration path"

            CONFIG_FILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
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
require_command openssl sha256sum install mktemp grep sed

load_config "$CONFIG_FILE"

: "${APP_DOMAIN:?APP_DOMAIN is required}"
: "${STATUS_DOMAIN:?STATUS_DOMAIN is required}"
: "${TLS_DAYS:?TLS_DAYS is required}"
: "${TLS_KEY_BITS:?TLS_KEY_BITS is required}"
: "${TLS_COUNTRY:?TLS_COUNTRY is required}"
: "${TLS_ORGANIZATION:?TLS_ORGANIZATION is required}"

validate_domain "$APP_DOMAIN"
validate_domain "$STATUS_DOMAIN"

[[ "$APP_DOMAIN" != "$STATUS_DOMAIN" ]] ||
    die "Virtual host domains must be different"

[[ "$TLS_DAYS" =~ ^[0-9]{1,4}$ ]] ||
    die "Invalid certificate validity"

(( 10#$TLS_DAYS > 30 )) ||
    die "TLS_DAYS must exceed 30 days"

case "$TLS_KEY_BITS" in
    2048|3072|4096) ;;
    *) die "Unsupported RSA key size" ;;
esac

[[ "$TLS_COUNTRY" =~ ^[A-Z]{2}$ ]] ||
    die "Invalid TLS country code"

[[ "$TLS_ORGANIZATION" =~ ^[a-zA-Z0-9._\ -]+$ ]] ||
    die "Invalid TLS organization"

umask 077

install -d -o root -g root -m 700 "$SSL_DIR"

if [[ "$FORCE" == false ]] && certificate_valid; then
    chown root:root "$CERT_FILE" "$KEY_FILE"
    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"

    log_success "Existing certificate is valid."
    log_info "Certificate generation skipped."

    exit 0
fi

if [[ -e "$CERT_FILE" || -e "$KEY_FILE" ]]; then
    BACKUP_DIR="$(mktemp -d "$SSL_DIR/backup.XXXXXXXX")"

    for file in "$CERT_FILE" "$KEY_FILE"; do
        if [[ -f "$file" ]]; then
            cp -p -- "$file" "$BACKUP_DIR/"
        fi
    done

    log_info "Existing TLS files backed up to $BACKUP_DIR"
fi

TEMP_DIR="$(mktemp -d "$SSL_DIR/.tls.XXXXXXXX")"
trap cleanup EXIT

log_info "Generating self-signed TLS certificate..."

openssl req \
    -x509 \
    -newkey "rsa:$TLS_KEY_BITS" \
    -sha256 \
    -days "$TLS_DAYS" \
    -nodes \
    -keyout "$TEMP_DIR/linux-lab.key" \
    -out "$TEMP_DIR/linux-lab.crt" \
    -subj "/C=$TLS_COUNTRY/O=$TLS_ORGANIZATION/CN=$APP_DOMAIN" \
    -addext "subjectAltName=DNS:$APP_DOMAIN,DNS:$STATUS_DOMAIN" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth"

openssl pkey \
    -in "$TEMP_DIR/linux-lab.key" \
    -check -noout

install -o root -g root -m 600 \
    "$TEMP_DIR/linux-lab.key" "$KEY_FILE"

install -o root -g root -m 644 \
    "$TEMP_DIR/linux-lab.crt" "$CERT_FILE"

certificate_valid ||
    die "Generated certificate failed validation"

log_success "TLS certificate generated successfully."

openssl x509 \
    -in "$CERT_FILE" \
    -noout \
    -subject \
    -dates \
    -ext subjectAltName

log_info "Certificate: $CERT_FILE"
log_info "Private key: $KEY_FILE"
log_info "Nginx reload must be handled by setup_web.sh."
