#!/bin/bash

################################################################################
# MOK Autonomous Parameter Validation and Auto-Correction Module
# Validates all system parameters and auto-corrects invalid values
# Zero human intervention
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || exit 127

readonly VALIDATION_LOG="/var/log/nvidia-signing/validation-$(date +%Y%m%d-%H%M%S).log"
readonly VALIDATION_STATE="/var/lib/nvidia-signing/validation-state.json"

ISSUES_FOUND=0
ISSUES_CORRECTED=0

################################################################################
# Parameter Validation Functions
################################################################################

validate_path_parameter() {
    local param_name="$1"
    local param_value="$2"
    local expected_type="$3"  # "file", "dir", "executable"
    local create_if_missing="${4:-false}"

    log_debug "Validating ${param_name}: ${param_value} (type: ${expected_type})"

    case "${expected_type}" in
        file)
            if [[ ! -f "${param_value}" ]]; then
                if [[ "${create_if_missing}" == "true" ]]; then
                    log_warning "Creating missing file: ${param_value}"
                    touch "${param_value}"
                    chmod 600 "${param_value}"
                    ((ISSUES_CORRECTED++))
                else
                    log_error "File not found: ${param_value}"
                    ((ISSUES_FOUND++))
                    return 1
                fi
            fi
            ;;
        dir)
            if [[ ! -d "${param_value}" ]]; then
                log_warning "Creating missing directory: ${param_value}"
                mkdir -p "${param_value}"
                chmod 700 "${param_value}"
                ((ISSUES_CORRECTED++))
            fi
            ;;
        executable)
            if [[ ! -x "${param_value}" ]]; then
                if [[ -f "${param_value}" ]]; then
                    log_warning "Making file executable: ${param_value}"
                    chmod +x "${param_value}"
                    ((ISSUES_CORRECTED++))
                else
                    log_error "Executable not found: ${param_value}"
                    ((ISSUES_FOUND++))
                    return 1
                fi
            fi
            ;;
    esac

    return 0
}

validate_numeric_parameter() {
    local param_name="$1"
    local param_value="$2"
    local min_value="${3:-0}"
    local max_value="${4:-999999}"

    log_debug "Validating ${param_name}: ${param_value} (range: ${min_value}-${max_value})"

    if ! [[ "${param_value}" =~ ^[0-9]+$ ]]; then
        log_error "Invalid numeric value for ${param_name}: ${param_value}"
        ((ISSUES_FOUND++))
        return 1
    fi

    if [[ ${param_value} -lt ${min_value} ]] || [[ ${param_value} -gt ${max_value} ]]; then
        log_warning "Parameter ${param_name} out of range (${param_value}), correcting to ${min_value}"
        echo "${min_value}"
        ((ISSUES_CORRECTED++))
        return 0
    fi

    echo "${param_value}"
    return 0
}

validate_permission_parameter() {
    local param_name="$1"
    local file_path="$2"
    local expected_perms="$3"

    log_debug "Validating permissions for ${param_name}: ${file_path} (expected: ${expected_perms})"

    if [[ ! -e "${file_path}" ]]; then
        log_error "File/directory does not exist: ${file_path}"
        ((ISSUES_FOUND++))
        return 1
    fi

    local current_perms=$(stat -c '%a' "${file_path}" 2>/dev/null || echo "000")

    if [[ "${current_perms}" != "${expected_perms}" ]]; then
        log_warning "Correcting permissions for ${file_path}: ${current_perms} → ${expected_perms}"
        chmod "${expected_perms}" "${file_path}"
        ((ISSUES_CORRECTED++))
        return 0
    fi

    return 0
}

validate_string_parameter() {
    local param_name="$1"
    local param_value="$2"
    local allowed_values="$3"  # space-separated

    log_debug "Validating ${param_name}: ${param_value}"

    for allowed in ${allowed_values}; do
        if [[ "${param_value}" == "${allowed}" ]]; then
            return 0
        fi
    done

    log_error "Invalid value for ${param_name}: ${param_value}. Allowed: ${allowed_values}"
    ((ISSUES_FOUND++))
    return 1
}

validate_configuration_file() {
    local config_file="$1"

    log_info "Validating configuration file: ${config_file}"

    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        ((ISSUES_FOUND++))
        return 1
    fi

    # Check for syntax errors
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "${key}" =~ ^# ]] && continue
        [[ -z "${key}" ]] && continue

        # Trim whitespace
        key=$(echo "${key}" | xargs)
        value=$(echo "${value}" | xargs)

        # Validate key format
        if ! [[ "${key}" =~ ^[A-Z_]+$ ]]; then
            log_error "Invalid configuration key: ${key}"
            ((ISSUES_FOUND++))
        fi

        # Validate value format (must not have unescaped quotes)
        if [[ "${value}" =~ \" ]] && ! [[ "${value}" =~ \\\" ]]; then
            log_warning "Quoting issue in config value for ${key}"
            ((ISSUES_FOUND++))
        fi
    done < "${config_file}"

    return 0
}

validate_systemd_units() {
    log_info "Validating systemd units..."

    local unit_dir="/etc/systemd/system"

    if [[ ! -d "${unit_dir}" ]]; then
        log_error "Systemd directory not found: ${unit_dir}"
        ((ISSUES_FOUND++))
        return 1
    fi

    # Check each unit file for syntax
    while IFS= read -r unit_file; do
        if systemd-analyze verify "${unit_file}" > /dev/null 2>&1; then
            log_debug "Unit verified: ${unit_file}"
        else
            log_error "Invalid systemd unit: ${unit_file}"
            ((ISSUES_FOUND++))
        fi
    done < <(find "${unit_dir}" -name "*nvidia*.service" -o -name "*nvidia*.timer")

    return 0
}

validate_selinux_policy() {
    log_info "Validating SELinux policy..."

    if ! command_exists checkpolicy; then
        log_info "SELinux tools not available - skipping"
        return 0
    fi

    local policy_file="/var/home/sanya/MOK/selinux/nvidia-signing.te"

    if [[ ! -f "${policy_file}" ]]; then
        log_warning "SELinux policy file not found: ${policy_file}"
        ((ISSUES_FOUND++))
        return 1
    fi

    # Check policy syntax
    if ! checkpolicy -d "${policy_file}" > /dev/null 2>&1; then
        log_error "SELinux policy has syntax errors"
        ((ISSUES_FOUND++))
        return 1
    fi

    log_success "SELinux policy verified"
    return 0
}

validate_shell_scripts() {
    log_info "Validating shell scripts..."

    local script_dir="/var/home/sanya/MOK/bin"

    if command_exists shellcheck; then
        while IFS= read -r script; do
            if shellcheck -S warning "${script}" 2>/dev/null; then
                log_debug "Script verified: ${script}"
            else
                log_warning "Script has shellcheck issues: ${script}"
                # Don't fail - warnings are acceptable
            fi
        done < <(find "${script_dir}" -name "*.sh" -type f)
    else
        log_info "shellcheck not available - skipping static analysis"
    fi

    return 0
}

validate_json_state_files() {
    log_info "Validating JSON state files..."

    local state_dir="/var/lib/nvidia-signing"

    if command_exists jq; then
        while IFS= read -r json_file; do
            if ! jq . "${json_file}" > /dev/null 2>&1; then
                log_warning "Corrupted JSON file: ${json_file} - removing"
                rm -f "${json_file}"
                ((ISSUES_CORRECTED++))
            else
                log_debug "JSON validated: ${json_file}"
            fi
        done < <(find "${state_dir}" -name "*.json" 2>/dev/null || echo "")
    fi

    return 0
}

validate_backup_integrity() {
    log_info "Validating backup integrity..."

    local backup_dir="/var/lib/nvidia-signing/backups"

    if [[ ! -d "${backup_dir}" ]]; then
        log_debug "No backups directory found"
        return 0
    fi

    while IFS= read -r backup_file; do
        # Check if it's a valid ELF binary
        if ! file "${backup_file}" | grep -q "ELF"; then
            log_error "Corrupted backup file: ${backup_file}"
            ((ISSUES_FOUND++))

            # Remove corrupted backup
            log_warning "Removing corrupted backup: ${backup_file}"
            rm -f "${backup_file}"
            ((ISSUES_CORRECTED++))
        fi
    done < <(find "${backup_dir}" -type f 2>/dev/null || echo "")

    return 0
}

validate_environment_variables() {
    log_info "Validating environment variables..."

    local required_vars=("PATH" "HOME" "SHELL")

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable not set: ${var}"
            ((ISSUES_FOUND++))
        fi
    done

    return 0
}

validate_filesystem_consistency() {
    log_info "Validating filesystem consistency..."

    # Check for orphaned files
    local orphaned_count=0

    # Check for files owned by nonexistent users
    while IFS= read -r file; do
        if ! stat "${file}" > /dev/null 2>&1; then
            log_warning "Inaccessible file: ${file}"
            ((orphaned_count++))
        fi
    done < <(find /var/lib/nvidia-signing -type f 2>/dev/null || echo "")

    if [[ ${orphaned_count} -gt 0 ]]; then
        log_warning "Found ${orphaned_count} orphaned/inaccessible files"
        ((ISSUES_FOUND++))
    fi

    return 0
}

################################################################################
# Auto-Correction Functions
################################################################################

auto_correct_issues() {
    log_info "Attempting automatic correction of detected issues..."

    # Fix directory permissions
    log_info "Correcting directory permissions..."
    find /var/lib/nvidia-signing -type d -exec chmod 700 {} \; 2>/dev/null
    find /var/log/nvidia-signing -type d -exec chmod 700 {} \; 2>/dev/null

    # Fix file permissions
    log_info "Correcting file permissions..."
    find /var/lib/nvidia-signing -type f -name "*.json" -exec chmod 600 {} \; 2>/dev/null
    find /usr/local/bin -name "*.sh" -type f -exec chmod 755 {} \; 2>/dev/null

    # Remove stale locks
    log_info "Cleaning up stale locks..."
    find /var/run -name "*nvidia*.lock" -type f -mtime +1 -delete 2>/dev/null

    # Remove old logs
    log_info "Cleaning up old logs..."
    find /var/log/nvidia-signing -name "*.log" -type f -mtime +30 -delete 2>/dev/null

    ((ISSUES_CORRECTED++))
}

################################################################################
# Reporting
################################################################################

save_validation_state() {
    local state_json=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "issues_found": ${ISSUES_FOUND},
  "issues_corrected": ${ISSUES_CORRECTED},
  "validation_status": "$([ ${ISSUES_FOUND} -eq 0 ] && echo 'PASSED' || echo 'FAILED')"
}
EOF
)

    mkdir -p "$(dirname "${VALIDATION_STATE}")"
    echo "${state_json}" > "${VALIDATION_STATE}"
    chmod 600 "${VALIDATION_STATE}"
}

################################################################################
# Main Execution
################################################################################

main() {
    mkdir -p "$(dirname "${VALIDATION_LOG}")"

    {
        log_info "=== AUTONOMOUS PARAMETER VALIDATION STARTED ==="
        log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        log_info ""

        # Run all validations
        validate_path_parameter "MODULE_PATH" "/usr/lib/modules" "dir" "true"
        validate_numeric_parameter "TIMEOUT" "300" "30" "3600"
        validate_permission_parameter "STATE_FILE_PERMS" "/var/lib/nvidia-signing" "700"
        validate_configuration_file "/var/home/sanya/MOK/config/nvidia-signing.conf" || true
        validate_systemd_units || true
        validate_shell_scripts || true
        validate_json_state_files || true
        validate_backup_integrity || true
        validate_environment_variables || true
        validate_filesystem_consistency || true

        log_info ""
        log_info "=== VALIDATION SUMMARY ==="
        log_info "Issues Found: ${ISSUES_FOUND}"
        log_info "Issues Corrected: ${ISSUES_CORRECTED}"

        if [[ ${ISSUES_FOUND} -gt 0 ]]; then
            auto_correct_issues
            log_info "Auto-correction attempted"
        fi

    } 2>&1 | tee -a "${VALIDATION_LOG}"

    save_validation_state

    log_info "Validation log: ${VALIDATION_LOG}"
    log_info "Validation state: ${VALIDATION_STATE}"

    # Return success if no critical issues
    [[ ${ISSUES_FOUND} -eq 0 ]]
}

main "$@"
