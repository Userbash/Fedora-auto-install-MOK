#!/bin/bash

################################################################################
# MOK System Detection and State Tracking Module
# Provides comprehensive system analysis and state management
#
# Purpose: Detect system configuration, driver/kernel versions, and state
# Usage: Source this file or execute for system report
################################################################################

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" || exit 1

# State and detection results
readonly STATE_DIR="${STATE_DIR:-/var/lib/nvidia-signing}"
readonly DETECTION_STATE="${STATE_DIR}/detection-state.json"
readonly PREVIOUS_STATE="${STATE_DIR}/previous-state.json"

################################################################################
# System Information Gathering
################################################################################

get_kernel_version() {
    uname -r
}

get_kernel_release() {
    uname -v | grep -oP 'release \K[^ ]+' || echo "unknown"
}

get_fedora_version() {
    if [[ -f /etc/fedora-release ]]; then
        grep -oP 'release \K\d+' /etc/fedora-release || echo "unknown"
    else
        echo "unknown"
    fi
}

get_uefi_firmware_info() {
    if [[ -f /sys/firmware/efi/fw_platform_size ]]; then
        echo "UEFI"
        local size=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "unknown")
        echo "$size-bit"
    elif [[ -d /sys/firmware/efi ]]; then
        echo "EFI"
    else
        echo "BIOS"
    fi
}

get_secure_boot_status() {
    if ! command_exists mokutil; then
        echo "unavailable"
        return 1
    fi

    if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
        echo "enabled"
    elif mokutil --sb-state 2>/dev/null | grep -q "SecureBoot disabled"; then
        echo "disabled"
    else
        echo "unknown"
    fi
}

get_mok_enrollment_status() {
    if ! command_exists mokutil; then
        echo "unavailable"
        return 1
    fi

    local enrolled_count=$(mokutil --list-enrolled 2>/dev/null | grep -c "SHA256" || echo "0")
    if [[ ${enrolled_count} -gt 0 ]]; then
        echo "enrolled"
    else
        echo "not_enrolled"
    fi
}

get_tpm_status() {
    if ! command_exists tpm2_getcap; then
        echo "tools_not_installed"
        return 1
    fi

    if tpm2_getcap handles-persistent 2>/dev/null | grep -q "0x"; then
        echo "available"
    else
        echo "not_available"
    fi
}

get_tpm_version() {
    if ! command_exists tpm2_getcap; then
        echo "unknown"
        return 1
    fi

    # Try to get TPM version
    tpm2_getcap properties-fixed 2>/dev/null | grep -i "TPM2_PT_FIRMWARE_VERSION" | head -1 || echo "unknown"
}

get_selinux_status() {
    if command_exists getenforce; then
        getenforce 2>/dev/null || echo "unknown"
    else
        echo "not_installed"
    fi
}

get_driver_version() {
    if ! command_exists modinfo; then
        return 1
    fi

    # Try to get NVIDIA driver version
    if [[ -f /usr/lib/modules/$(uname -r)/extra/nvidia/nvidia.ko ]]; then
        modinfo /usr/lib/modules/$(uname -r)/extra/nvidia/nvidia.ko 2>/dev/null | \
            grep "^version:" | awk '{print $2}' || echo "unknown"
    else
        echo "not_installed"
    fi
}

get_signing_keys_info() {
    local key_dir="/etc/pki/akmods/certs"
    local private_key="${key_dir}/private_key.priv"
    local public_key="${key_dir}/public_key.der"

    if [[ -f "${private_key}" && -f "${public_key}" ]]; then
        local priv_date=$(stat -c '%y' "${private_key}" 2>/dev/null | cut -d' ' -f1-2)
        local pub_date=$(stat -c '%y' "${public_key}" 2>/dev/null | cut -d' ' -f1-2)
        echo "present|${priv_date}|${pub_date}"
    else
        echo "missing"
    fi
}

get_last_signing_time() {
    if [[ -f "${DETECTION_STATE}" ]]; then
        grep '"last_signing_time"' "${DETECTION_STATE}" 2>/dev/null | \
            grep -oP ':\s*"\K[^"]+' || echo "never"
    else
        echo "never"
    fi
}

################################################################################
# Module Detection
################################################################################

detect_nvidia_modules() {
    local modules_path="/usr/lib/modules/$(uname -r)/extra"
    local module_count=0
    local signed_count=0
    local unsigned_count=0

    if [[ ! -d "${modules_path}" ]]; then
        echo "none"
        return 0
    fi

    # Count modules
    while IFS= read -r -d '' module; do
        ((module_count++))

        # Check if signed using modinfo
        if modinfo -F signer "${module}" 2>/dev/null | grep -q .; then
            ((signed_count++))
        else
            ((unsigned_count++))
        fi
    done < <(find "${modules_path}" -name "*nvidia*.ko" -print0 2>/dev/null)

    echo "${module_count}|${signed_count}|${unsigned_count}"
}

################################################################################
# State Management and Comparison
################################################################################

save_detection_state() {
    log_debug "Saving system detection state..."

    mkdir -p "${STATE_DIR}"
    chmod 700 "${STATE_DIR}"

    local kernel_ver=$(get_kernel_version)
    local fedora_ver=$(get_fedora_version)
    local firmware=$(get_uefi_firmware_info)
    local secure_boot=$(get_secure_boot_status)
    local mok_status=$(get_mok_enrollment_status)
    local tpm=$(get_tpm_status)
    local selinux=$(get_selinux_status)
    local driver_ver=$(get_driver_version)
    local keys_info=$(get_signing_keys_info)
    local modules_info=$(detect_nvidia_modules)

    # Parse module counts
    IFS='|' read -r module_count signed_count unsigned_count <<< "${modules_info}"

    local state_json=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_signing_time": "$(get_last_signing_time)",
  "system": {
    "kernel_version": "${kernel_ver}",
    "fedora_version": "${fedora_ver}",
    "firmware_type": "$(echo "${firmware}" | head -1)",
    "firmware_bits": "$(echo "${firmware}" | tail -1)"
  },
  "security": {
    "secure_boot": "${secure_boot}",
    "mok_enrollment": "${mok_status}",
    "tpm": "${tpm}",
    "selinux": "${selinux}"
  },
  "nvidia": {
    "driver_version": "${driver_ver}",
    "modules_total": ${module_count:-0},
    "modules_signed": ${signed_count:-0},
    "modules_unsigned": ${unsigned_count:-0}
  },
  "keys": {
    "status": "$(echo "${keys_info}" | cut -d'|' -f1)",
    "private_key_date": "$(echo "${keys_info}" | cut -d'|' -f2)",
    "public_key_date": "$(echo "${keys_info}" | cut -d'|' -f3)"
  }
}
EOF
)

    echo "${state_json}" > "${DETECTION_STATE}"
    chmod 600 "${DETECTION_STATE}"

    log_debug "Detection state saved to ${DETECTION_STATE}"
    return 0
}

compare_with_previous_state() {
    if [[ ! -f "${PREVIOUS_STATE}" ]]; then
        log_debug "No previous state found - this is first run"
        return 0
    fi

    # Compare kernel versions
    local prev_kernel=$(jq -r '.system.kernel_version' "${PREVIOUS_STATE}" 2>/dev/null || echo "unknown")
    local curr_kernel=$(get_kernel_version)

    if [[ "${prev_kernel}" != "${curr_kernel}" ]]; then
        log_warning "Kernel version changed: ${prev_kernel} → ${curr_kernel}"
        echo "kernel_changed"
        return 1
    fi

    # Compare driver versions
    local prev_driver=$(jq -r '.nvidia.driver_version' "${PREVIOUS_STATE}" 2>/dev/null || echo "unknown")
    local curr_driver=$(get_driver_version)

    if [[ "${prev_driver}" != "${curr_driver}" ]]; then
        log_warning "Driver version changed: ${prev_driver} → ${curr_driver}"
        echo "driver_changed"
        return 1
    fi

    # Compare module count
    local prev_modules=$(jq -r '.nvidia.modules_total' "${PREVIOUS_STATE}" 2>/dev/null || echo "0")
    local curr_modules=$(detect_nvidia_modules | cut -d'|' -f1)

    if [[ "${prev_modules}" != "${curr_modules}" ]]; then
        log_warning "Module count changed: ${prev_modules} → ${curr_modules}"
        echo "modules_changed"
        return 1
    fi

    log_success "System state unchanged from previous detection"
    return 0
}

check_if_resigning_needed() {
    # Check if modules are still signed as expected
    local modules_info=$(detect_nvidia_modules)
    IFS='|' read -r total signed unsigned <<< "${modules_info}"

    if [[ ${unsigned} -gt 0 ]]; then
        log_warning "Unsigned modules detected: ${unsigned} of ${total}"
        return 1
    fi

    # Check if last signing failed
    if [[ -f "${STATE_DIR}/last-signing-failed" ]]; then
        log_warning "Previous signing operation failed"
        return 1
    fi

    log_success "All modules properly signed"
    return 0
}

################################################################################
# System Report
################################################################################

print_system_report() {
    print_banner "MOK System Detection Report"

    echo ""
    print_section "System Information"
    print_summary "Kernel Version" "$(get_kernel_version)"
    print_summary "Fedora Version" "$(get_fedora_version)"
    print_summary "Firmware Type" "$(get_uefi_firmware_info | head -1)"

    echo ""
    print_section "Security Status"
    print_summary "Secure Boot" "$(get_secure_boot_status)"
    print_summary "MOK Enrollment" "$(get_mok_enrollment_status)"
    print_summary "TPM2" "$(get_tpm_status)"
    print_summary "SELinux" "$(get_selinux_status)"

    echo ""
    print_section "NVIDIA Driver"
    print_summary "Driver Version" "$(get_driver_version)"

    local modules_info=$(detect_nvidia_modules)
    IFS='|' read -r total signed unsigned <<< "${modules_info}"
    print_summary "Total Modules" "${total}"
    print_summary "Signed Modules" "${signed}"
    print_summary "Unsigned Modules" "${unsigned}"

    echo ""
    print_section "Signing Keys"
    print_summary "Keys Status" "$(get_signing_keys_info | cut -d'|' -f1)"

    echo ""
    print_section "Previous State Comparison"
    if compare_with_previous_state > /dev/null; then
        print_result "System state unchanged" true
    else
        local reason=$(compare_with_previous_state)
        print_result "System state: ${reason}" false
    fi

    echo ""
}

################################################################################
# Initialization
################################################################################

main() {
    if [[ "${1:-}" == "--report" ]]; then
        print_system_report
    elif [[ "${1:-}" == "--save-state" ]]; then
        save_detection_state
        log_success "Detection state saved"
    elif [[ "${1:-}" == "--compare" ]]; then
        compare_with_previous_state
    elif [[ "${1:-}" == "--check-resigning" ]]; then
        check_if_resigning_needed
    else
        save_detection_state
    fi
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
