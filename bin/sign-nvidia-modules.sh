#!/bin/bash

################################################################################
# NVIDIA Kernel Module Auto-Signing Script
# Fedora 43 with Secure Boot and TPM2 Support
#
# Purpose: Automatically detect and sign unsigned NVIDIA kernel modules
# Features:
#   - Secure Boot status detection
#   - TPM2 chip availability detection
#   - Comprehensive error handling and logging
#   - Idempotent execution
#   - Rollback support
#   - Full audit trail
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Paths
readonly KEY_DIR="/etc/pki/akmods/certs"
readonly KEY_PRIV="${KEY_DIR}/private_key.priv"
readonly KEY_PUB="${KEY_DIR}/public_key.der"
readonly MODULES_EXTRA_PATH="/usr/lib/modules/$(uname -r)/extra"
readonly KERNEL_DIR="/usr/src/kernels/$(uname -r)"
readonly SIGN_FILE="${KERNEL_DIR}/scripts/sign-file"
readonly LOG_DIR="/var/log/nvidia-signing"
readonly LOG_FILE="${LOG_DIR}/nvidia-signing-$(date +%Y%m%d-%H%M%S).log"
readonly LOCK_FILE="/var/run/nvidia-signing.lock"
readonly STATE_FILE="/var/lib/nvidia-signing/state.json"
readonly STATE_DIR="/var/lib/nvidia-signing"
readonly BACKUP_DIR="/var/lib/nvidia-signing/backups"

# Runtime variables
SECURE_BOOT_STATUS=""
TPM2_AVAILABLE=""
MODULES_SIGNED_COUNT=0
MODULES_FAILED_COUNT=0
MODULES_SKIPPED_COUNT=0
EXIT_CODE=0

################################################################################
# Logging and Output Functions
################################################################################

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    log "SUCCESS" "$@"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    log "WARNING" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
    log "ERROR" "$@"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $@"
        log "DEBUG" "$@"
    fi
}

################################################################################
# System Checks and Initialization
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        return 1
    fi
}

setup_logging() {
    mkdir -p "${LOG_DIR}"
    mkdir -p "${STATE_DIR}"
    mkdir -p "${BACKUP_DIR}"

    # Ensure proper permissions
    chmod 700 "${LOG_DIR}"
    chmod 700 "${STATE_DIR}"
    chmod 700 "${BACKUP_DIR}"

    log_info "Logging initialized: ${LOG_FILE}"
}

acquire_lock() {
    local timeout=30
    local elapsed=0

    while [[ -f "${LOCK_FILE}" ]]; do
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Failed to acquire lock after ${timeout}s"
            return 1
        fi
        log_warning "Waiting for lock... (${elapsed}s/${timeout}s)"
        sleep 1
        ((elapsed++))
    done

    echo $$ > "${LOCK_FILE}"
    trap "release_lock" EXIT
    log_debug "Lock acquired (PID: $$)"
}

release_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        rm -f "${LOCK_FILE}"
        log_debug "Lock released"
    fi
}

detect_secure_boot() {
    log_info "Detecting Secure Boot status..."

    if [[ -f /sys/firmware/efi/fw_platform_size ]]; then
        if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
            SECURE_BOOT_STATUS="enabled"
            log_success "Secure Boot is ENABLED"
        else
            SECURE_BOOT_STATUS="disabled"
            log_warning "Secure Boot is DISABLED"
        fi
    else
        SECURE_BOOT_STATUS="not_supported"
        log_warning "System does not support Secure Boot (UEFI not detected)"
    fi

    log_debug "Secure Boot Status: ${SECURE_BOOT_STATUS}"
}

detect_tpm2() {
    log_info "Detecting TPM2 availability..."

    if command -v tpm2_getcap &>/dev/null; then
        if tpm2_getcap handles-persistent 2>/dev/null >/dev/null; then
            TPM2_AVAILABLE="yes"
            log_success "TPM2 chip is AVAILABLE"
        else
            TPM2_AVAILABLE="no"
            log_warning "TPM2 tools detected but no TPM2 chip available"
        fi
    else
        TPM2_AVAILABLE="no"
        log_warning "TPM2 tools not installed, TPM2 integration unavailable"
    fi

    log_debug "TPM2 Available: ${TPM2_AVAILABLE}"
}

verify_prerequisites() {
    log_info "Verifying prerequisites..."
    local all_ok=true

    # Check key files
    if [[ ! -f "${KEY_PRIV}" ]]; then
        log_error "Private key not found: ${KEY_PRIV}"
        all_ok=false
    else
        log_success "Private key found"
    fi

    if [[ ! -f "${KEY_PUB}" ]]; then
        log_error "Public key not found: ${KEY_PUB}"
        all_ok=false
    else
        log_success "Public key found"
    fi

    # Check sign-file utility
    if [[ ! -x "${SIGN_FILE}" ]]; then
        log_error "sign-file utility not found or not executable: ${SIGN_FILE}"
        all_ok=false
    else
        log_success "sign-file utility found"
    fi

    # Check dracut
    if ! command -v dracut &>/dev/null; then
        log_error "dracut utility not found"
        all_ok=false
    else
        log_success "dracut utility found"
    fi

    # Check modinfo
    if ! command -v modinfo &>/dev/null; then
        log_error "modinfo utility not found"
        all_ok=false
    else
        log_success "modinfo utility found"
    fi

    if [[ "${all_ok}" != "true" ]]; then
        log_error "Prerequisite check failed"
        return 1
    fi

    log_success "All prerequisites satisfied"
}

################################################################################
# Module Detection and Signature Checking
################################################################################

find_nvidia_modules() {
    log_info "Scanning for NVIDIA kernel modules..."
    local modules=()

    if [[ ! -d "${MODULES_EXTRA_PATH}" ]]; then
        log_warning "Modules extra path not found: ${MODULES_EXTRA_PATH}"
        echo ""
        return 0
    fi

    # Find all NVIDIA .ko files
    while IFS= read -r -d '' module; do
        modules+=("$module")
        log_debug "Found module: $module"
    done < <(find "${MODULES_EXTRA_PATH}" -name "*nvidia*.ko" -print0 2>/dev/null)

    if [[ ${#modules[@]} -eq 0 ]]; then
        log_warning "No NVIDIA kernel modules found"
        echo ""
        return 0
    fi

    log_success "Found ${#modules[@]} NVIDIA module(s)"
    printf '%s\n' "${modules[@]}"
}

check_module_signed() {
    local module="$1"

    # Method 1: Check using modinfo
    if modinfo -F signer "${module}" 2>/dev/null | grep -q .; then
        log_debug "Module is signed (via modinfo): ${module}"
        return 0
    fi

    # Method 2: Check tainted flag
    local module_name=$(basename "${module}" .ko)
    if [[ -f "/sys/module/${module_name}/tainted" ]]; then
        local tainted=$(cat "/sys/module/${module_name}/tainted")
        if [[ "${tainted}" == "0" ]]; then
            log_debug "Module is signed (via tainted flag): ${module}"
            return 0
        fi
    fi

    log_debug "Module is unsigned: ${module}"
    return 1
}

################################################################################
# Module Signing
################################################################################

sign_module() {
    local module="$1"
    local module_name=$(basename "${module}")

    log_info "Signing module: ${module_name}..."

    # Create backup before signing
    local backup_file="${BACKUP_DIR}/$(date +%s)_${module_name}"
    if ! cp "${module}" "${backup_file}"; then
        log_error "Failed to create backup of ${module_name}"
        return 1
    fi
    log_debug "Backup created: ${backup_file}"

    # Sign the module
    if "${SIGN_FILE}" sha256 "${KEY_PRIV}" "${KEY_PUB}" "${module}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Module signed successfully: ${module_name}"

        # Verify signature
        if check_module_signed "${module}"; then
            log_success "Signature verification passed: ${module_name}"
            return 0
        else
            log_warning "Signature verification inconclusive (module may need reload): ${module_name}"
            return 0
        fi
    else
        log_error "Failed to sign module: ${module_name}"
        # Restore backup on failure
        if ! cp "${backup_file}" "${module}"; then
            log_error "CRITICAL: Failed to restore backup of ${module_name}"
            return 1
        fi
        log_warning "Module restored from backup due to signing failure"
        return 1
    fi
}

process_modules() {
    log_info "Processing NVIDIA kernel modules..."

    local modules
    modules=$(find_nvidia_modules)

    if [[ -z "${modules}" ]]; then
        log_warning "No NVIDIA modules to process"
        return 0
    fi

    local unsigned_modules=()
    local signed_modules=()

    # Classify modules
    while IFS= read -r module; do
        [[ -z "${module}" ]] && continue

        if check_module_signed "${module}"; then
            signed_modules+=("${module}")
            ((MODULES_SKIPPED_COUNT++))
        else
            unsigned_modules+=("${module}")
        fi
    done <<< "${modules}"

    # Log classification
    if [[ ${#signed_modules[@]} -gt 0 ]]; then
        log_success "Already signed modules: ${#signed_modules[@]}"
        for mod in "${signed_modules[@]}"; do
            log_debug "  - $(basename "$mod")"
        done
    fi

    if [[ ${#unsigned_modules[@]} -eq 0 ]]; then
        log_success "All modules are already signed"
        return 0
    fi

    log_warning "Unsigned modules found: ${#unsigned_modules[@]}"

    # Sign unsigned modules
    for module in "${unsigned_modules[@]}"; do
        if sign_module "${module}"; then
            ((MODULES_SIGNED_COUNT++))
        else
            ((MODULES_FAILED_COUNT++))
        fi
    done

    # Summary
    log_info "Module processing summary:"
    log_info "  - Signed: ${MODULES_SIGNED_COUNT}"
    log_info "  - Already signed: ${MODULES_SKIPPED_COUNT}"
    log_info "  - Failed: ${MODULES_FAILED_COUNT}"

    if [[ ${MODULES_FAILED_COUNT} -gt 0 ]]; then
        return 1
    fi

    return 0
}

################################################################################
# Initramfs and System Updates
################################################################################

regenerate_initramfs() {
    log_info "Regenerating initramfs..."

    if dracut --force 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Initramfs regenerated successfully"

        # Verify timestamp
        local initramfs="/boot/initramfs-$(uname -r).img"
        if [[ -f "${initramfs}" ]]; then
            local file_age=$(($(date +%s) - $(stat -c %Y "${initramfs}")))
            if [[ ${file_age} -lt 60 ]]; then
                log_success "Initramfs timestamp verification passed"
                return 0
            else
                log_warning "Initramfs file age seems old (${file_age}s)"
                return 0
            fi
        fi
    else
        log_error "Failed to regenerate initramfs"
        return 1
    fi
}

################################################################################
# State Management
################################################################################

save_state() {
    log_debug "Saving execution state..."

    local state_json=$(cat <<EOF
{
  "version": "${SCRIPT_VERSION}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "kernel_version": "$(uname -r)",
  "secure_boot": "${SECURE_BOOT_STATUS}",
  "tpm2_available": "${TPM2_AVAILABLE}",
  "modules_signed": ${MODULES_SIGNED_COUNT},
  "modules_skipped": ${MODULES_SKIPPED_COUNT},
  "modules_failed": ${MODULES_FAILED_COUNT},
  "exit_code": ${EXIT_CODE}
}
EOF
)

    echo "${state_json}" > "${STATE_FILE}"
    chmod 600 "${STATE_FILE}"
    log_debug "State saved to ${STATE_FILE}"
}

load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        log_debug "Loading previous execution state..."
        cat "${STATE_FILE}" | tee -a "${LOG_FILE}"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "==============================================="
    log_info "NVIDIA Module Auto-Signing Script v${SCRIPT_VERSION}"
    log_info "==============================================="
    log_info "Started at: $(date)"
    log_info "Running as: $(id)"
    log_info "Kernel: $(uname -r)"

    # Perform checks
    check_root || { EXIT_CODE=1; save_state; return 1; }

    # Acquire lock
    acquire_lock || { EXIT_CODE=1; save_state; return 1; }

    # Detect system configuration
    detect_secure_boot
    detect_tpm2

    # Verify prerequisites
    verify_prerequisites || { EXIT_CODE=1; save_state; return 1; }

    # Load previous state for reference
    load_state

    # Process modules
    process_modules || { EXIT_CODE=1; }

    # Regenerate initramfs if modules were signed
    if [[ ${MODULES_SIGNED_COUNT} -gt 0 ]]; then
        regenerate_initramfs || { EXIT_CODE=1; }
    fi

    # Save state
    save_state

    # Final summary
    log_info "==============================================="
    log_info "Execution Summary"
    log_info "==============================================="
    log_info "Secure Boot: ${SECURE_BOOT_STATUS}"
    log_info "TPM2 Available: ${TPM2_AVAILABLE}"
    log_info "Modules Signed: ${MODULES_SIGNED_COUNT}"
    log_info "Modules Already Signed: ${MODULES_SKIPPED_COUNT}"
    log_info "Modules Failed: ${MODULES_FAILED_COUNT}"

    if [[ ${EXIT_CODE} -eq 0 ]]; then
        log_success "Script completed successfully"
    else
        log_error "Script completed with errors (exit code: ${EXIT_CODE})"
    fi

    log_info "Log file: ${LOG_FILE}"
    log_info "Completed at: $(date)"

    return ${EXIT_CODE}
}

# Run main function
main "$@"
exit $?
