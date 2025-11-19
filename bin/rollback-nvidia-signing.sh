#!/bin/bash

################################################################################
# NVIDIA Signing Recovery and Rollback Script
# Fedora 43 with Secure Boot and TPM2 Support
#
# Purpose: Recover from failed signing operations and rollback to known-good state
# Features:
#   - Restore backed-up modules
#   - Verify rollback integrity
#   - Clean up corrupted state
#   - Provide detailed audit trail
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
readonly SCRIPT_VERSION="1.0.0"
readonly BACKUP_DIR="/var/lib/nvidia-signing/backups"
readonly STATE_FILE="/var/lib/nvidia-signing/state.json"
readonly LOG_DIR="/var/log/nvidia-signing"
readonly RECOVERY_LOG="${LOG_DIR}/recovery-$(date +%Y%m%d-%H%M%S).log"

# Runtime variables
MODULES_RESTORED=0
MODULES_FAILED=0

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $@" >> "${RECOVERY_LOG}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $@" >> "${RECOVERY_LOG}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $@" >> "${RECOVERY_LOG}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $@" >> "${RECOVERY_LOG}"
}

################################################################################
# System Checks
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        return 1
    fi
}

check_backup_dir() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_error "Backup directory not found: ${BACKUP_DIR}"
        return 1
    fi

    local backup_count=$(find "${BACKUP_DIR}" -name "*.ko" 2>/dev/null | wc -l)
    if [[ ${backup_count} -eq 0 ]]; then
        log_warning "No backups found in ${BACKUP_DIR}"
        return 1
    fi

    log_success "Found ${backup_count} backup module(s)"
}

################################################################################
# Backup Listing
################################################################################

list_backups() {
    log_info "Available backups:"
    echo ""

    if [[ ! -d "${BACKUP_DIR}" ]] || [[ ! "$(ls -A ${BACKUP_DIR})" ]]; then
        log_warning "No backups available"
        return 1
    fi

    local index=1
    while IFS= read -r backup_file; do
        local timestamp=$(basename "${backup_file}" | cut -d_ -f1)
        local module_name=$(basename "${backup_file}" | sed "s/^[0-9]*_//")
        local file_size=$(stat -c %s "${backup_file}")
        echo "  [$index] ${module_name} (size: ${file_size} bytes, backup: $(date -d @${timestamp} 2>/dev/null || echo 'unknown'))"
        ((index++))
    done < <(find "${BACKUP_DIR}" -type f -name "*.ko" | sort -r)

    echo ""
}

################################################################################
# Verification Functions
################################################################################

verify_backup_integrity() {
    local backup_file="$1"
    local module_name="$2"

    log_info "Verifying backup integrity for ${module_name}..."

    # Check file exists and is readable
    if [[ ! -r "${backup_file}" ]]; then
        log_error "Backup file is not readable: ${backup_file}"
        return 1
    fi

    # Check file size
    local file_size=$(stat -c %s "${backup_file}")
    if [[ ${file_size} -lt 1000 ]]; then
        log_error "Backup file seems corrupted (too small): ${file_size} bytes"
        return 1
    fi

    # Verify it's a valid ELF binary (kernel module)
    if file "${backup_file}" | grep -q "ELF"; then
        log_success "Backup file is valid ELF binary"
        return 0
    else
        log_warning "Backup file type check inconclusive (file command output: $(file "${backup_file}"))"
        return 0
    fi
}

verify_module_location() {
    local module_name="$1"
    local kernel_release=$(uname -r)
    local module_path="/usr/lib/modules/${kernel_release}/extra/${module_name}"

    if [[ ! -f "${module_path}" ]]; then
        log_error "Current module not found at expected location: ${module_path}"
        return 1
    fi

    log_success "Module location verified: ${module_path}"
    return 0
}

################################################################################
# Restore Functions
################################################################################

restore_module() {
    local backup_file="$1"
    local module_name="$2"
    local kernel_release=$(uname -r)
    local module_path="/usr/lib/modules/${kernel_release}/extra/${module_name}"

    log_info "Restoring module: ${module_name}..."

    # Verify backup integrity
    if ! verify_backup_integrity "${backup_file}" "${module_name}"; then
        log_error "Backup integrity check failed"
        return 1
    fi

    # Verify module location
    if ! verify_module_location "${module_name}"; then
        log_error "Module location verification failed"
        return 1
    fi

    # Create safety backup of current module before restore
    local current_backup="${BACKUP_DIR}/pre-restore-$(date +%s)_${module_name}"
    if ! cp "${module_path}" "${current_backup}"; then
        log_error "Failed to create pre-restore backup"
        return 1
    fi
    log_debug "Pre-restore backup created: ${current_backup}"

    # Perform restore
    if ! cp "${backup_file}" "${module_path}"; then
        log_error "Failed to restore module from backup"
        return 1
    fi

    # Verify restore
    local backup_size=$(stat -c %s "${backup_file}")
    local restored_size=$(stat -c %s "${module_path}")

    if [[ ${backup_size} -ne ${restored_size} ]]; then
        log_error "Restored module size mismatch (expected: ${backup_size}, got: ${restored_size})"
        # Restore from current backup
        if cp "${current_backup}" "${module_path}"; then
            log_warning "Rollback reverted to previous state"
        fi
        return 1
    fi

    log_success "Module restored successfully: ${module_name}"
    return 0
}

restore_all_modules() {
    log_info "Restoring all backed-up modules..."

    if [[ ! -d "${BACKUP_DIR}" ]] || [[ ! "$(ls -A ${BACKUP_DIR})" ]]; then
        log_warning "No backups available to restore"
        return 1
    fi

    local processed=0
    local failed=0

    # Get the most recent backups
    declare -A latest_backups

    while IFS= read -r backup_file; do
        local module_name=$(basename "${backup_file}" | sed "s/^[0-9]*_//")

        # Keep only the latest backup for each module
        if [[ ! -v "latest_backups[${module_name}]" ]]; then
            latest_backups["${module_name}"]="${backup_file}"
        fi
    done < <(find "${BACKUP_DIR}" -type f -name "*.ko" | sort -r)

    # Restore each module
    for module_name in "${!latest_backups[@]}"; do
        local backup_file="${latest_backups[${module_name}]}"

        if restore_module "${backup_file}" "${module_name}"; then
            ((MODULES_RESTORED++))
        else
            ((MODULES_FAILED++))
            ((failed++))
        fi
        ((processed++))
    done

    log_info "Restore summary:"
    log_info "  - Processed: ${processed}"
    log_info "  - Restored: ${MODULES_RESTORED}"
    log_info "  - Failed: ${MODULES_FAILED}"

    return $((failed > 0 ? 1 : 0))
}

################################################################################
# Initramfs Regeneration
################################################################################

regenerate_initramfs() {
    log_info "Regenerating initramfs after rollback..."

    if ! command -v dracut &>/dev/null; then
        log_error "dracut utility not found"
        return 1
    fi

    if dracut --force 2>&1 | tee -a "${RECOVERY_LOG}"; then
        log_success "Initramfs regenerated successfully"
        return 0
    else
        log_error "Failed to regenerate initramfs"
        return 1
    fi
}

################################################################################
# State Management
################################################################################

load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        log_info "Loaded previous execution state"
        cat "${STATE_FILE}"
    else
        log_warning "State file not found: ${STATE_FILE}"
    fi
}

clear_corrupted_state() {
    log_info "Clearing corrupted state..."

    if [[ -f "${STATE_FILE}" ]]; then
        rm -f "${STATE_FILE}"
        log_success "State file cleared"
    fi

    # Clear lock file if present
    if [[ -f /var/run/nvidia-signing.lock ]]; then
        rm -f /var/run/nvidia-signing.lock
        log_warning "Lock file cleared (forced)"
    fi
}

################################################################################
# Recovery Modes
################################################################################

interactive_recovery() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} NVIDIA Signing Recovery - Interactive Mode"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}\n"

    # List available backups
    list_backups || {
        log_error "No backups available for recovery"
        return 1
    }

    # Prompt user
    echo "Recovery options:"
    echo "  1) Restore all modules from latest backups"
    echo "  2) Restore specific module"
    echo "  3) List available backups"
    echo "  4) Clear corrupted state only"
    echo "  5) Show system status"
    echo "  6) Exit"
    echo ""

    read -p "Select option [1-6]: " option

    case "${option}" in
        1)
            log_info "Restoring all modules..."
            if restore_all_modules; then
                regenerate_initramfs
                log_success "Full recovery completed"
            else
                log_error "Some modules failed to restore"
                return 1
            fi
            ;;
        2)
            read -p "Enter module name (e.g., nvidia-drm.ko): " module_name
            local backup_file=$(find "${BACKUP_DIR}" -name "*_${module_name}" | head -1)
            if [[ -n "${backup_file}" ]]; then
                restore_module "${backup_file}" "${module_name}"
                regenerate_initramfs
            else
                log_error "No backup found for ${module_name}"
                return 1
            fi
            ;;
        3)
            list_backups
            ;;
        4)
            clear_corrupted_state
            log_success "State cleared"
            ;;
        5)
            show_system_status
            ;;
        6)
            log_info "Exiting recovery"
            return 0
            ;;
        *)
            log_error "Invalid option"
            return 1
            ;;
    esac
}

show_system_status() {
    echo -e "\n${BLUE}System Status:${NC}\n"

    echo "Kernel version: $(uname -r)"
    echo "Secure Boot status: $(mokutil --sb-state 2>/dev/null | grep SecureBoot || echo "unknown")"

    if command -v tpm2_getcap &>/dev/null; then
        echo "TPM2 status: $(tpm2_getcap handles-persistent 2>/dev/null && echo "Available" || echo "Not available")"
    fi

    echo ""
    echo "NVIDIA modules:"
    find /usr/lib/modules/$(uname -r)/extra -name "*nvidia*.ko" 2>/dev/null | while read mod; do
        local signer=$(modinfo -F signer "$mod" 2>/dev/null || echo "unsigned")
        echo "  - $(basename $mod): $signer"
    done

    echo ""
    echo "Backup directory: ${BACKUP_DIR}"
    echo "State file: ${STATE_FILE}"
    echo "Recovery log: ${RECOVERY_LOG}"

    if [[ -d "${BACKUP_DIR}" ]]; then
        local backup_count=$(find "${BACKUP_DIR}" -type f | wc -l)
        echo "Available backups: ${backup_count}"
    fi

    echo ""
}

automatic_recovery() {
    log_info "Automatic recovery mode activated"

    if check_backup_dir; then
        log_info "Attempting automatic recovery..."
        if restore_all_modules; then
            regenerate_initramfs
            log_success "Automatic recovery completed successfully"
            clear_corrupted_state
            return 0
        else
            log_error "Automatic recovery failed"
            return 1
        fi
    else
        log_error "No backups available for automatic recovery"
        return 1
    fi
}

################################################################################
# Main Entry
################################################################################

main() {
    # Ensure we have a log directory
    mkdir -p "${LOG_DIR}"

    log_info "==============================================="
    log_info "NVIDIA Signing Recovery Script v${SCRIPT_VERSION}"
    log_info "==============================================="
    log_info "Started at: $(date)"

    # Check root
    check_root || { log_error "Recovery aborted"; return 1; }

    # Show help if requested
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --auto              Automatic recovery (restore all from latest backups)"
        echo "  --interactive       Interactive recovery mode (default)"
        echo "  --list              List available backups"
        echo "  --status            Show system status"
        echo "  --clear-state       Clear corrupted state files"
        echo "  --help, -h          Show this help message"
        echo ""
        return 0
    fi

    # Handle command-line modes
    case "${1:-interactive}" in
        --auto)
            automatic_recovery
            ;;
        --list)
            list_backups
            ;;
        --status)
            show_system_status
            ;;
        --clear-state)
            clear_corrupted_state
            ;;
        --interactive|*)
            interactive_recovery
            ;;
    esac

    log_info "Recovery script completed at: $(date)"
    log_info "Recovery log: ${RECOVERY_LOG}"
}

main "$@"
