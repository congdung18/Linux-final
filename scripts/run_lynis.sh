#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ACTION=""
OUTPUT_DIR=""
STAGING_DIR=""

usage() {
    cat <<'EOF'
Usage: run_lynis.sh ACTION [OPTIONS]

Actions:
  before              Run baseline security audit
  after               Run post-hardening security audit
  compare             Compare before and after reports

Options:
  -o, --output DIR    Custom report directory
  -h, --help          Show this help message

Default directory:
  ~/security-audit/lynis

Existing reports are never overwritten.
EOF
}

resolve_output_directory() {
    if [[ -n "$OUTPUT_DIR" ]]; then
        return 0
    fi

    local target_user
    local target_home

    target_user="${SUDO_USER:-$(id -un)}"

    target_home="$(
        getent passwd "$target_user" | cut -d: -f6
    )"

    [[ -n "$target_home" ]] ||
        die "Cannot determine user home directory"

    OUTPUT_DIR="$target_home/security-audit/lynis"
}

cleanup() {
    if [[ -n "$STAGING_DIR" &&
          -d "$STAGING_DIR" ]]; then

        rm -rf -- "$STAGING_DIR"
    fi
}

get_index() {
    local report="$1"

    awk -F= '
        $1 == "hardening_index" {
            print $2
            exit
        }
    ' "$report"
}

count_entries() {
    local type="$1"
    local report="$2"

    awk -v prefix="${type}[]=" '
        index($0, prefix) == 1 {
            count++
        }

        END {
            print count + 0
        }
    ' "$report"
}

validate_report() {
    local report="$1"
    local index

    [[ -s "$report" ]] ||
        die "Report missing or empty: $report"

    index="$(get_index "$report")"

    [[ "$index" =~ ^[0-9]{1,3}$ ]] ||
        die "Invalid hardening index in $report"

    (( 10#$index <= 100 )) ||
        die "Hardening index is out of range"
}

print_report() {
    local report="$1"

    validate_report "$report"

    printf '\nHardening Index : %s\n' \
        "$(get_index "$report")"

    printf 'Warnings        : %s\n' \
        "$(count_entries warning "$report")"

    printf 'Suggestions     : %s\n' \
        "$(count_entries suggestion "$report")"
}

run_audit() {
    require_root

    require_command \
        lynis flock install mktemp \
        awk tee getent cut

    local target="$OUTPUT_DIR/$ACTION"
    local target_user
    local target_group

    target_user="${SUDO_USER:-root}"
    target_group="$(id -gn "$target_user")"

    umask 077

    install -d -o root -g root -m 700 \
        /run/linux-final

    exec 9>/run/linux-final/audit.lock

    flock -n 9 ||
        die "Another security audit is running"

    if [[ -e "$target" || -L "$target" ]]; then
        die "Report already exists: $target"
    fi

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        install -d \
            -o "$target_user" \
            -g "$target_group" \
            -m 700 "$OUTPUT_DIR"
    fi

    STAGING_DIR="$(mktemp -d)"

    log_info "Running Lynis audit: $ACTION"

    lynis audit system \
        --quick \
        --no-colors \
        --logfile "$STAGING_DIR/lynis.log" \
        --report-file "$STAGING_DIR/lynis-report.dat" \
        | tee "$STAGING_DIR/terminal.txt"

    validate_report "$STAGING_DIR/lynis-report.dat"

    [[ -s "$STAGING_DIR/lynis.log" ]] ||
        die "Lynis log was not generated"

    mkdir -m 700 -- "$target" ||
        die "Cannot create report directory"

    install -o "$target_user" \
        -g "$target_group" -m 600 \
        "$STAGING_DIR/lynis.log" \
        "$STAGING_DIR/lynis-report.dat" \
        "$STAGING_DIR/terminal.txt" \
        "$target/"

    chown "$target_user:$target_group" "$target"

    print_report "$target/lynis-report.dat"

    log_success "Audit report saved: $target"
}

compare_reports() {
    local before="$OUTPUT_DIR/before/lynis-report.dat"
    local after="$OUTPUT_DIR/after/lynis-report.dat"

    validate_report "$before"
    validate_report "$after"

    local index_before
    local index_after
    local warnings_before
    local warnings_after
    local suggestions_before
    local suggestions_after

    index_before="$(get_index "$before")"
    index_after="$(get_index "$after")"

    warnings_before="$(count_entries warning "$before")"
    warnings_after="$(count_entries warning "$after")"

    suggestions_before="$(count_entries suggestion "$before")"
    suggestions_after="$(count_entries suggestion "$after")"

    printf '\n===============================================\n'
    printf '          LYNIS SECURITY AUDIT COMPARISON\n'
    printf '===============================================\n'

    printf '%-20s %8s %8s %8s\n' \
        "Metric" "Before" "After" "Change"

    printf '%-20s %8d %8d %+8d\n' \
        "Hardening Index" \
        "$index_before" "$index_after" \
        "$((index_after - index_before))"

    printf '%-20s %8d %8d %+8d\n' \
        "Warnings" \
        "$warnings_before" "$warnings_after" \
        "$((warnings_after - warnings_before))"

    printf '%-20s %8d %8d %+8d\n' \
        "Suggestions" \
        "$suggestions_before" "$suggestions_after" \
        "$((suggestions_after - suggestions_before))"

    printf '===============================================\n'

    printf '\n=== RESOLVED SUGGESTIONS ===\n'

    comm -23 \
        <(sed -n '/^suggestion\[\]=/p' "$before" | sort -u) \
        <(sed -n '/^suggestion\[\]=/p' "$after" | sort -u)

    printf '\n=== NEW SUGGESTIONS ===\n'

    comm -13 \
        <(sed -n '/^suggestion\[\]=/p' "$before" | sort -u) \
        <(sed -n '/^suggestion\[\]=/p' "$after" | sort -u)

    printf '\n=== REMAINING WARNINGS ===\n'

    sed -n '/^warning\[\]=/p' "$after"

    printf '\n'

    log_success "Report comparison completed."
}

while (( $# > 0 )); do
    case "$1" in
        before|after|compare)
            [[ -z "$ACTION" ]] ||
                die "Only one action is allowed"

            ACTION="$1"
            shift
            ;;
        -o|--output)
            (( $# >= 2 )) ||
                die "Missing output directory"

            OUTPUT_DIR="$2"
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

[[ -n "$ACTION" ]] ||
    die "Specify before, after or compare"

resolve_output_directory

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

case "$ACTION" in
    before|after)
        run_audit
        ;;
    compare)
        compare_reports
        ;;
esac
