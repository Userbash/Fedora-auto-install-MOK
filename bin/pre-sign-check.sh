#!/bin/bash

################################################################################
# Pre-Signing Checks and Safety Verification
# Ensures system is ready for signing operations
################################################################################

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" || exit 1

RATE_LIMIT_FILE="/var/lib/nvidia-signing/last-signing-attempt"
RATE_LIMIT_SECONDS=300  # 5 minutes

################################################################################
# Safety Checks
################################################################################

check_rate_limiting() {
    log_info "Checking rate limiting..."

    if [[ ! -f "${RATE_LIMIT_FILE}" ]]; then
        # First run - no rate limiting
        touch "${RATE_LIMIT_FILE}"
        return 0
    fi

    local last_attempt=$(stat -c '%Y' "${RATE_LIMIT_FILE}")
    local now=$(date +%s)
    local elapsed=$((now - last_attempt))

    if [[ ${elapsed} -lt ${RATE_LIMIT_SECONDS} ]]; then
        log_error "Rate limit exceeded - last attempt was ${elapsed}s ago (minimum ${RATE_LIMIT_SECONDS}s required)"
        return 1
    fi

    touch "${RATE_LIMIT_FILE}"
    return 0
}

check_disk_space() {
    log_info "Checking disk space..."

    local root_available=$(df / | tail -1 | awk '{print $4}')
    local boot_available=$(df /boot | tail -1 | awk '{print $4}')

    # Require at least 100MB on root
    if [[ ${root_available} -lt 102400 ]]; then
        log_error "Insufficient disk space on / (${root_available}KB available, need 100MB)"
        return 1
    fi

    # Require at least 50MB on /boot
    if [[ ${boot_available} -lt 51200 ]]; then
        log_error "Insufficient disk space on /boot (${boot_available}KB available, need 50MB)"
        return 1
    fi

    log_success "Sufficient disk space available"
    return 0
}

check_key_permissions() {
    log_info "Checking signing key permissions..."

    local key_dir="/etc/pki/akmods/certs"
    local private_key="${key_dir}/private_key.priv"
    local public_key="${key_dir}/public_key.der"

    if [[ ! -f "${private_key}" ]]; then
        log_error "Private key not found: ${private_key}"
        return 1
    fi

    if [[ ! -f "${public_key}" ]]; then
        log_error "Public key not found: ${public_key}"
        return 1
    fi

    # Check private key is readable only by root
    local key_perms=$(stat -c '%a' "${private_key}")
    if [[ "${key_perms}" != "400" && "${key_perms}" != "600" ]]; then
        log_warning "Private key has unusual permissions: ${key_perms}"
    fi

    log_success "Signing keys verified"
    return 0
}

check_lock_file() {
    log_info "Checking for concurrent execution..."

    local lock_file="/var/run/nvidia-signing.lock"

    if [[ -f "${lock_file}" ]]; then
        local lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "")

        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            log_error "Another instance is running (PID: ${lock_pid})"
            return 1
        else
            log_warning "Stale lock file found, removing..."
            rm -f "${lock_file}"
        fi
    fi

    return 0
}

check_previous_failures() {
    log_info "Checking for previous failures..."

    local failure_count=0
    local failure_file="/var/lib/nvidia-signing/failure-count"

    if [[ -f "${failure_file}" ]]; then
        failure_count=$(cat "${failure_file}" 2>/dev/null || echo "0")
    fi

    if [[ ${failure_count} -ge 3 ]]; then
        log_error "Multiple previous failures detected (${failure_count}). Please investigate."
        log_info "Reset with: rm /var/lib/nvidia-signing/failure-count"
        return 1
    fi

    return 0
}

check_secure_boot_enabled() {
    log_info "Checking Secure Boot status..."

    if ! command_exists mokutil; then
        log_warning "mokutil not available - cannot verify Secure Boot"
        return 0
    fi

    if ! mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
        log_warning "Secure Boot is not enabled - signing may not be necessary"
    fi

    return 0
}

check_keys_enrolled() {
    log_info "Checking MOK key enrollment..."

    if ! command_exists mokutil; then
        log_warning "mokutil not available - cannot verify MOK enrollment"
        return 0
    fi

    if ! mokutil --list-enrolled 2>/dev/null | grep -q "SHA256"; then
        log_warning "MOK keys not enrolled - signing will have no effect until enrolled"
    fi

    return 0
}

################################################################################
# Main Safety Verification
################################################################################

main() {
    log_info "================== Pre-Signing Safety Checks =================="

    # Run all checks, fail if any critical check fails
    local all_ok=true

    check_rate_limiting || all_ok=false
    check_disk_space || all_ok=false
    check_key_permissions || all_ok=false
    check_lock_file || all_ok=false
    check_previous_failures || all_ok=false
    check_secure_boot_enabled || true  # Warning only
    check_keys_enrolled || true        # Warning only

    log_info "==================== Pre-Check Complete ===================="

    if [[ "${all_ok}" == "true" ]]; then
        log_success "All safety checks passed"
        return 0
    else
        log_error "Safety checks failed - aborting signing operation"
        return 1
    fi
}

main "$@"
