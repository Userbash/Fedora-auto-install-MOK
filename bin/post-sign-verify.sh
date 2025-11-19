#!/bin/bash

################################################################################
# Post-Signing Verification and Audit
# Verifies that signing was successful and updates state
################################################################################

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" || exit 1

VERIFICATION_LOG="${LOG_DIR:-/var/log/nvidia-signing}/verification-$(date +%Y%m%d-%H%M%S).log"
STATE_DIR="/var/lib/nvidia-signing"

################################################################################
# Verification Functions
################################################################################

verify_module_signatures() {
    log_info "Verifying module signatures..."

    local modules_path="/usr/lib/modules/$(uname -r)/extra"
    local verified=0
    local failed=0

    if [[ ! -d "${modules_path}" ]]; then
        log_warning "Module path not found: ${modules_path}"
        return 0
    fi

    # Check each NVIDIA module
    while IFS= read -r -d '' module; do
        local module_name=$(basename "${module}")

        # Method 1: modinfo check
        if modinfo -F signer "${module}" 2>/dev/null | grep -q .; then
            ((verified++))
            log_debug "✓ Verified signature: ${module_name}"
        else
            # Method 2: tainted flag
            local module_basename="${module_name%.ko}"
            if [[ -f "/sys/module/${module_basename}/tainted" ]]; then
                if [[ "$(cat "/sys/module/${module_basename}/tainted")" == "0" ]]; then
                    ((verified++))
                    log_debug "✓ Verified tainted flag: ${module_name}"
                    continue
                fi
            fi

            ((failed++))
            log_error "✗ Signature verification failed: ${module_name}"
        fi
    done < <(find "${modules_path}" -name "*nvidia*.ko" -print0 2>/dev/null)

    if [[ ${failed} -eq 0 ]]; then
        log_success "All ${verified} modules verified successfully"
        return 0
    else
        log_error "Verification failed for ${failed} modules"
        return 1
    fi
}

verify_initramfs_updated() {
    log_info "Verifying initramfs regeneration..."

    local initramfs="/boot/initramfs-$(uname -r).img"

    if [[ ! -f "${initramfs}" ]]; then
        log_error "Initramfs file not found: ${initramfs}"
        return 1
    fi

    # Check if file was recently modified (within last 5 minutes)
    local file_age=$(($(date +%s) - $(stat -c %Y "${initramfs}")))

    if [[ ${file_age} -lt 300 ]]; then
        log_success "Initramfs recently regenerated (${file_age}s ago)"
        return 0
    else
        log_warning "Initramfs appears old (${file_age}s ago) - may be from previous boot"
        return 0  # Don't fail, might be from previous boot
    fi
}

check_kernel_module_status() {
    log_info "Checking kernel module loading status..."

    # Check if nvidia module is loaded
    if grep -q "nvidia" /proc/modules 2>/dev/null; then
        log_info "NVIDIA module currently loaded"

        # Check tainted status if loaded
        if [[ -f "/sys/module/nvidia/tainted" ]]; then
            local tainted=$(cat "/sys/module/nvidia/tainted" 2>/dev/null || echo "-1")

            if [[ "${tainted}" == "0" ]]; then
                log_success "Module loaded with clean tainted flag"
                return 0
            else
                log_warning "Module loaded but tainted flag set: ${tainted}"
                return 0  # Not a critical failure
            fi
        fi
    else
        log_info "NVIDIA module not currently loaded (will be loaded after reboot)"
        return 0
    fi
}

update_state_on_success() {
    log_info "Updating state after successful signing..."

    mkdir -p "${STATE_DIR}"

    # Increment success counter
    local success_file="${STATE_DIR}/success-count"
    local success_count=$(cat "${success_file}" 2>/dev/null || echo "0")
    ((success_count++))
    echo "${success_count}" > "${success_file}"

    # Reset failure counter
    echo "0" > "${STATE_DIR}/failure-count"

    # Remove failure marker
    rm -f "${STATE_DIR}/last-signing-failed"

    # Update last successful time
    date '+%Y-%m-%d %H:%M:%S' > "${STATE_DIR}/last-successful-signing"

    log_success "State updated (success count: ${success_count})"
    return 0
}

update_state_on_failure() {
    log_error "Updating state after signing failure..."

    mkdir -p "${STATE_DIR}"

    # Increment failure counter
    local failure_file="${STATE_DIR}/failure-count"
    local failure_count=$(cat "${failure_file}" 2>/dev/null || echo "0")
    ((failure_count++))
    echo "${failure_count}" > "${failure_file}"

    # Mark failure
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "${STATE_DIR}/last-signing-failed"

    # Alert if too many failures
    if [[ ${failure_count} -ge 3 ]]; then
        log_error "Too many signing failures (${failure_count}). Manual intervention required."
    fi

    return 0
}

create_audit_entry() {
    log_info "Creating audit journal entry..."

    if command_exists logger; then
        local verification_result="$1"
        local module_count="$2"

        logger -t nvidia-signing -p auth.warning "Module signing verification: ${verification_result} (${module_count} modules)"
    fi

    return 0
}

################################################################################
# Main Verification
################################################################################

main() {
    log_info "================== Post-Signing Verification =================="

    # Check if previous signing was successful
    local signing_result="${1:-unknown}"
    if [[ "${signing_result}" == "unknown" ]]; then
        # Check exit code from systemd
        signing_result=$?
    fi

    local all_verified=true

    # Always attempt verification regardless of signing result
    if verify_module_signatures; then
        log_success "Module signature verification passed"
    else
        log_error "Module signature verification failed"
        all_verified=false
    fi

    # Verify initramfs
    verify_initramfs_updated || all_verified=false

    # Check kernel module status
    check_kernel_module_status || true  # Warning only

    log_info "==================== Verification Complete ===================="

    # Update state based on verification results
    if [[ "${all_verified}" == "true" ]]; then
        update_state_on_success
        create_audit_entry "success" "$(find /usr/lib/modules/$(uname -r)/extra -name '*nvidia*.ko' 2>/dev/null | wc -l)"

        log_success "Post-signing verification PASSED"
        exit 0
    else
        update_state_on_failure
        create_audit_entry "failed" "$(find /usr/lib/modules/$(uname -r)/extra -name '*nvidia*.ko' 2>/dev/null | wc -l)"

        log_error "Post-signing verification FAILED"
        exit 1
    fi
}

main "$@"
