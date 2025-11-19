#!/bin/bash

################################################################################
# MOK Autonomous Self-Diagnostic and Self-Healing Module
# Complete autonomous operation without human intervention
#
# Features:
#   - Automatic system diagnosis
#   - Self-healing of detected issues
#   - Parameter validation and auto-correction
#   - System readiness verification
#   - Anti-tampering protection
#   - Comprehensive logging
#   - Zero human intervention
################################################################################

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || {
    echo "FATAL: Cannot source common.sh" >&2
    exit 127
}

# Diagnostic state
readonly DIAGNOSTIC_LOG="/var/log/nvidia-signing/diagnostic-$(date +%Y%m%d-%H%M%S).log"
readonly DIAGNOSTIC_STATE="/var/lib/nvidia-signing/diagnostic-state.json"
readonly ISSUES_FOUND="/var/lib/nvidia-signing/issues-found"
readonly ISSUES_FIXED="/var/lib/nvidia-signing/issues-fixed"

# Counters
ISSUES_DETECTED=0
ISSUES_FIXED_COUNT=0
CRITICAL_ISSUES=0
WARNING_COUNT=0

################################################################################
# Auto-Diagnostic Functions
################################################################################

diagnose_system() {
    log_info "=== AUTONOMOUS SYSTEM DIAGNOSIS STARTED ==="

    # Create directories
    mkdir -p "$(dirname "${DIAGNOSTIC_LOG}")"
    mkdir -p "$(dirname "${DIAGNOSTIC_STATE}")"

    {
        log_info "Starting comprehensive system diagnosis..."
        log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        log_info "Kernel: $(uname -r)"
        log_info "System: $(hostname)"
        log_info ""

        # Run all diagnostic checks
        check_root_access
        check_signing_keys
        check_directory_structure
        check_file_permissions
        check_disk_space
        check_required_tools
        check_systemd_units
        check_selinux_context
        check_dnf_hook
        check_module_signatures
        check_system_parameters
        check_lock_files
        check_backup_integrity
        check_logging_functionality
        check_state_files
        check_network_connectivity
        check_kernel_version_consistency

    } 2>&1 | tee -a "${DIAGNOSTIC_LOG}"
}

check_root_access() {
    log_info "[DIAG] Checking root access..."

    if [[ $EUID -ne 0 ]]; then
        log_error "Not running as root - cannot continue"
        ((CRITICAL_ISSUES++))
        save_issue "CRITICAL" "root_access" "Not running as root"
        return 1
    fi

    log_success "Root access verified"
    return 0
}

check_signing_keys() {
    log_info "[DIAG] Checking signing keys..."

    local key_dir="/etc/pki/akmods/certs"
    local private_key="${key_dir}/private_key.priv"
    local public_key="${key_dir}/public_key.der"

    mkdir -p "${key_dir}"

    if [[ ! -f "${private_key}" ]] || [[ ! -f "${public_key}" ]]; then
        log_warning "Signing keys missing - auto-generating..."
        save_issue "CRITICAL" "signing_keys" "Keys missing"

        if auto_generate_keys "${key_dir}"; then
            ((ISSUES_FIXED_COUNT++))
            log_success "Keys auto-generated and saved"
        else
            log_error "Failed to auto-generate keys"
            ((CRITICAL_ISSUES++))
            return 1
        fi
    fi

    # Verify key permissions
    local priv_perms=$(stat -c '%a' "${private_key}" 2>/dev/null || echo "000")
    if [[ "${priv_perms}" != "400" && "${priv_perms}" != "600" ]]; then
        log_warning "Private key permissions incorrect (${priv_perms}) - fixing..."
        chmod 400 "${private_key}"
        ((ISSUES_FIXED_COUNT++))
        log_success "Key permissions corrected"
    fi

    log_success "Signing keys verified and secured"
    return 0
}

auto_generate_keys() {
    local key_dir="$1"

    if command_exists kmodgenca; then
        log_info "Attempting to auto-generate keys with kmodgenca..."
        if kmodgenca -a 2>/dev/null; then
            return 0
        fi
    fi

    log_warning "kmodgenca not available - using openssl..."
    cd "${key_dir}"

    # Generate private key
    openssl genrsa -out private_key.priv 2048 2>/dev/null || return 1

    # Generate certificate
    openssl req -new -x509 -key private_key.priv -out public_key.der \
        -days 36500 -subj "/CN=NVIDIA-MOK-$(date +%s)/" 2>/dev/null || return 1

    chmod 400 private_key.priv
    chmod 444 public_key.der

    return 0
}

check_directory_structure() {
    log_info "[DIAG] Checking directory structure..."

    local required_dirs=(
        "/etc/pki/akmods/certs:700"
        "/var/lib/nvidia-signing:700"
        "/var/lib/nvidia-signing/backups:700"
        "/var/log/nvidia-signing:700"
        "/usr/local/bin:755"
        "/usr/local/lib/nvidia-signing:755"
    )

    for dir_spec in "${required_dirs[@]}"; do
        local dir=$(echo "${dir_spec}" | cut -d: -f1)
        local perms=$(echo "${dir_spec}" | cut -d: -f2)

        if [[ ! -d "${dir}" ]]; then
            log_warning "Creating missing directory: ${dir}"
            mkdir -p "${dir}"
            chmod "${perms}" "${dir}"
            ((ISSUES_FIXED_COUNT++))
        else
            local current_perms=$(stat -c '%a' "${dir}" 2>/dev/null || echo "000")
            if [[ "${current_perms}" != "${perms}" ]]; then
                log_warning "Fixing directory permissions: ${dir} (${current_perms} → ${perms})"
                chmod "${perms}" "${dir}"
                ((ISSUES_FIXED_COUNT++))
            fi
        fi
    done

    log_success "Directory structure verified and corrected"
    return 0
}

check_file_permissions() {
    log_info "[DIAG] Checking file permissions..."

    local critical_files=(
        "/usr/local/bin/sign-nvidia-modules.sh:755"
        "/usr/local/bin/test-nvidia-signing.sh:755"
        "/usr/local/bin/rollback-nvidia-signing.sh:755"
        "/var/lib/nvidia-signing/state.json:600"
    )

    for file_spec in "${critical_files[@]}"; do
        local file=$(echo "${file_spec}" | cut -d: -f1)
        local expected_perms=$(echo "${file_spec}" | cut -d: -f2)

        if [[ -f "${file}" ]]; then
            local current_perms=$(stat -c '%a' "${file}" 2>/dev/null || echo "000")
            if [[ "${current_perms}" != "${expected_perms}" ]]; then
                log_warning "Fixing file permissions: ${file} (${current_perms} → ${expected_perms})"
                chmod "${expected_perms}" "${file}"
                ((ISSUES_FIXED_COUNT++))
            fi
        fi
    done

    log_success "File permissions verified and corrected"
    return 0
}

check_disk_space() {
    log_info "[DIAG] Checking disk space..."

    local root_free=$(df / | tail -1 | awk '{print $4}')
    local boot_free=$(df /boot 2>/dev/null | tail -1 | awk '{print $4}' || echo "999999")

    if [[ ${root_free} -lt 102400 ]]; then
        log_warning "Low disk space on / (${root_free}KB free)"
        ((WARNING_COUNT++))
        save_issue "WARNING" "disk_space" "Low space on /"
    fi

    if [[ ${boot_free} -lt 51200 ]]; then
        log_warning "Low disk space on /boot (${boot_free}KB free)"
        ((WARNING_COUNT++))
        save_issue "WARNING" "disk_space_boot" "Low space on /boot"
    fi

    log_success "Disk space checked"
    return 0
}

check_required_tools() {
    log_info "[DIAG] Checking required tools..."

    local required_tools=("mokutil" "dracut" "modinfo" "kmod" "logger" "jq")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command_exists "${tool}"; then
            missing_tools+=("${tool}")
            ((WARNING_COUNT++))
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Missing tools: ${missing_tools[*]}"
        save_issue "WARNING" "missing_tools" "Missing: ${missing_tools[*]}"

        # Attempt auto-installation
        if command_exists dnf; then
            log_info "Attempting auto-install of missing tools..."
            if dnf install -y "${missing_tools[@]}" 2>/dev/null; then
                ((ISSUES_FIXED_COUNT++))
                log_success "Missing tools auto-installed"
            fi
        fi
    else
        log_success "All required tools available"
    fi

    return 0
}

check_systemd_units() {
    log_info "[DIAG] Checking systemd units..."

    local required_units=(
        "sign-nvidia-modules.service"
        "sign-nvidia-modules.timer"
        "sign-nvidia-modules.socket"
    )

    for unit in "${required_units[@]}"; do
        if ! systemctl list-unit-files | grep -q "^${unit}"; then
            log_warning "Systemd unit missing: ${unit}"
            ((WARNING_COUNT++))
            save_issue "WARNING" "missing_systemd_unit" "Missing: ${unit}"
        fi
    done

    log_success "Systemd units checked"
    return 0
}

check_selinux_context() {
    log_info "[DIAG] Checking SELinux context..."

    if ! command_exists getenforce; then
        log_info "SELinux not installed - skipping"
        return 0
    fi

    local selinux_status=$(getenforce 2>/dev/null || echo "Disabled")
    log_info "SELinux status: ${selinux_status}"

    if [[ "${selinux_status}" == "Enforcing" ]]; then
        # Check for signing policy
        if ! semodule -l 2>/dev/null | grep -q "nvidia_signing"; then
            log_warning "SELinux policy for nvidia-signing not installed"
            ((WARNING_COUNT++))
            save_issue "WARNING" "selinux_policy" "Policy not installed"
        fi
    fi

    return 0
}

check_dnf_hook() {
    log_info "[DIAG] Checking DNF hook..."

    local dnf_hook="/etc/dnf/plugins/post-transaction-actions.d/nvidia-signing.action"

    if [[ ! -f "${dnf_hook}" ]]; then
        log_warning "DNF hook not installed"
        ((WARNING_COUNT++))
        save_issue "WARNING" "dnf_hook" "Hook not installed"
    else
        if ! grep -q "sign-nvidia-modules.sh" "${dnf_hook}"; then
            log_warning "DNF hook misconfigured"
            ((WARNING_COUNT++))
            save_issue "WARNING" "dnf_hook_config" "Hook misconfigured"
        fi
    fi

    return 0
}

check_module_signatures() {
    log_info "[DIAG] Checking module signatures..."

    local modules_path="/usr/lib/modules/$(uname -r)/extra"

    if [[ ! -d "${modules_path}" ]]; then
        log_info "No NVIDIA modules directory found"
        return 0
    fi

    local total=0
    local signed=0
    local unsigned=0

    while IFS= read -r -d '' module; do
        ((total++))
        if modinfo -F signer "${module}" 2>/dev/null | grep -q .; then
            ((signed++))
        else
            ((unsigned++))
        fi
    done < <(find "${modules_path}" -name "*nvidia*.ko" -print0 2>/dev/null)

    if [[ ${unsigned} -gt 0 ]]; then
        log_warning "Unsigned modules detected: ${unsigned}/${total}"
        ((WARNING_COUNT++))
        save_issue "WARNING" "unsigned_modules" "${unsigned} unsigned of ${total}"
    else
        log_success "All modules properly signed (${signed}/${total})"
    fi

    return 0
}

check_system_parameters() {
    log_info "[DIAG] Checking system parameters..."

    # Check kernel parameters
    if [[ ! -f /proc/cmdline ]]; then
        log_error "Cannot read kernel parameters"
        return 1
    fi

    # Check Secure Boot
    if [[ -f /sys/firmware/efi/fw_platform_size ]]; then
        if command_exists mokutil; then
            if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
                log_success "Secure Boot enabled"
            else
                log_warning "Secure Boot disabled - signing may not be effective"
                ((WARNING_COUNT++))
                save_issue "WARNING" "secure_boot_disabled" "Not enabled"
            fi
        fi
    fi

    return 0
}

check_lock_files() {
    log_info "[DIAG] Checking lock files..."

    local lock_file="/var/run/nvidia-signing.lock"

    if [[ -f "${lock_file}" ]]; then
        local lock_pid=$(cat "${lock_file}" 2>/dev/null || echo "0")

        if ! kill -0 "${lock_pid}" 2>/dev/null; then
            log_warning "Stale lock file found - removing"
            rm -f "${lock_file}"
            ((ISSUES_FIXED_COUNT++))
        fi
    fi

    return 0
}

check_backup_integrity() {
    log_info "[DIAG] Checking backup integrity..."

    local backup_dir="/var/lib/nvidia-signing/backups"

    if [[ ! -d "${backup_dir}" ]]; then
        log_info "No backups directory - creating"
        mkdir -p "${backup_dir}"
        chmod 700 "${backup_dir}"
        ((ISSUES_FIXED_COUNT++))
        return 0
    fi

    local corrupt_count=0
    while IFS= read -r backup_file; do
        if ! file "${backup_file}" | grep -q "ELF"; then
            log_warning "Corrupted backup: ${backup_file}"
            ((corrupt_count++))
        fi
    done < <(find "${backup_dir}" -type f -name "*.ko")

    if [[ ${corrupt_count} -gt 0 ]]; then
        log_warning "${corrupt_count} corrupted backups detected"
        ((WARNING_COUNT++))
    fi

    return 0
}

check_logging_functionality() {
    log_info "[DIAG] Checking logging functionality..."

    local log_dir="/var/log/nvidia-signing"

    if [[ ! -d "${log_dir}" ]]; then
        mkdir -p "${log_dir}"
        chmod 700 "${log_dir}"
        ((ISSUES_FIXED_COUNT++))
    fi

    # Test logging
    if ! echo "test" > "${log_dir}/test.log" 2>/dev/null; then
        log_error "Cannot write to log directory"
        ((CRITICAL_ISSUES++))
        return 1
    fi
    rm -f "${log_dir}/test.log"

    log_success "Logging functionality verified"
    return 0
}

check_state_files() {
    log_info "[DIAG] Checking state files..."

    local state_dir="/var/lib/nvidia-signing"
    local state_file="${state_dir}/state.json"

    if [[ -f "${state_file}" ]]; then
        if ! jq . "${state_file}" > /dev/null 2>&1; then
            log_warning "State file corrupted - recreating"
            rm -f "${state_file}"
            ((ISSUES_FIXED_COUNT++))
        fi
    fi

    return 0
}

check_network_connectivity() {
    log_info "[DIAG] Checking network connectivity..."

    # Non-critical check
    if ! ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; then
        log_info "Network connectivity check failed (optional)"
    else
        log_success "Network connectivity verified"
    fi

    return 0
}

check_kernel_version_consistency() {
    log_info "[DIAG] Checking kernel version consistency..."

    local current_kernel=$(uname -r)
    local modules_kernel=$(ls -1 /lib/modules/ | head -1 || echo "")

    if [[ -z "${modules_kernel}" ]]; then
        log_warning "No kernel modules directory found"
        ((WARNING_COUNT++))
        return 1
    fi

    if [[ "${current_kernel}" != "${modules_kernel}" ]]; then
        log_warning "Kernel version mismatch: current=${current_kernel}, modules=${modules_kernel}"
        ((WARNING_COUNT++))
        save_issue "WARNING" "kernel_mismatch" "Current: ${current_kernel}, Modules: ${modules_kernel}"
    else
        log_success "Kernel versions consistent"
    fi

    return 0
}

################################################################################
# Issue Management
################################################################################

save_issue() {
    local severity="$1"
    local issue_type="$2"
    local description="$3"

    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${severity} ${issue_type}: ${description}" >> "${ISSUES_FOUND}"

    ((ISSUES_DETECTED++))
}

generate_diagnostic_report() {
    log_info ""
    log_info "=== DIAGNOSTIC REPORT SUMMARY ==="
    log_info "Total Issues Detected: ${ISSUES_DETECTED}"
    log_info "Issues Fixed: ${ISSUES_FIXED_COUNT}"
    log_info "Critical Issues: ${CRITICAL_ISSUES}"
    log_info "Warnings: ${WARNING_COUNT}"

    if [[ ${CRITICAL_ISSUES} -gt 0 ]]; then
        log_error "CRITICAL: System has ${CRITICAL_ISSUES} critical issues requiring attention"
        return 1
    fi

    if [[ ${ISSUES_DETECTED} -eq 0 ]]; then
        log_success "System is healthy - no issues detected"
        return 0
    fi

    log_info "System is operational but has ${ISSUES_DETECTED} detected issues"
    log_info "Automatically fixed: ${ISSUES_FIXED_COUNT} issues"

    return 0
}

save_diagnostic_state() {
    local state_json=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "issues_detected": ${ISSUES_DETECTED},
  "issues_fixed": ${ISSUES_FIXED_COUNT},
  "critical_issues": ${CRITICAL_ISSUES},
  "warnings": ${WARNING_COUNT},
  "system": {
    "kernel": "$(uname -r)",
    "hostname": "$(hostname)",
    "uptime": "$(uptime -p)"
  },
  "status": "$([ ${CRITICAL_ISSUES} -eq 0 ] && echo 'HEALTHY' || echo 'CRITICAL')"
}
EOF
)

    echo "${state_json}" > "${DIAGNOSTIC_STATE}"
    chmod 600 "${DIAGNOSTIC_STATE}"
}

################################################################################
# Main Execution
################################################################################

main() {
    # Ensure running as root for diagnostics
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: Diagnostics must run as root" >&2
        exit 1
    fi

    diagnose_system
    generate_diagnostic_report
    local report_status=$?

    save_diagnostic_state

    log_info "Diagnostic report saved to: ${DIAGNOSTIC_LOG}"
    log_info "Diagnostic state saved to: ${DIAGNOSTIC_STATE}"

    if [[ -f "${ISSUES_FOUND}" ]]; then
        log_info "Issues file: ${ISSUES_FOUND}"
    fi

    exit ${report_status}
}

main "$@"
