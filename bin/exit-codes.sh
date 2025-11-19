#!/bin/bash

################################################################################
# MOK Exit Code System
# Provides standardized, granular exit codes for all operations
#
# Exit Code Reference:
#   0 - SUCCESS: All operations completed successfully
#   1 - GENERAL_FAILURE: Unspecified error
#   2 - PREREQUISITES_FAILED: Required tools, keys, or configuration missing
#   3 - PARTIAL_SUCCESS: Some operations succeeded but some failed
#   4 - SYSTEM_NOT_READY: System state prevents operation (no modules, etc.)
#   5 - PERMISSION_DENIED: Insufficient privileges or access denied
#   6 - RATE_LIMITED: Operation blocked by rate limiting
#   7 - CONFIGURATION_ERROR: Invalid configuration or parameters
#   130 - INTERRUPTED: Script terminated by SIGINT (Ctrl+C)
#   143 - TERMINATED: Script terminated by SIGTERM
################################################################################

# Exit code constants
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_FAILURE=1
readonly EXIT_PREREQUISITES_FAILED=2
readonly EXIT_PARTIAL_SUCCESS=3
readonly EXIT_SYSTEM_NOT_READY=4
readonly EXIT_PERMISSION_DENIED=5
readonly EXIT_RATE_LIMITED=6
readonly EXIT_CONFIGURATION_ERROR=7
readonly EXIT_INTERRUPTED=130
readonly EXIT_TERMINATED=143

# Description mappings
declare -A EXIT_DESCRIPTIONS=(
    [0]="Success: All operations completed successfully"
    [1]="General Failure: Unspecified error occurred"
    [2]="Prerequisites Failed: Required tools, keys, or configuration missing"
    [3]="Partial Success: Some operations succeeded but some failed"
    [4]="System Not Ready: System state prevents operation"
    [5]="Permission Denied: Insufficient privileges or access denied"
    [6]="Rate Limited: Operation blocked by rate limiting"
    [7]="Configuration Error: Invalid configuration or parameters"
    [130]="Interrupted: Script terminated by user (Ctrl+C)"
    [143]="Terminated: Script terminated by system"
)

# Global exit code variable
MOK_EXIT_CODE="${EXIT_SUCCESS}"

################################################################################
# Exit Code Functions
################################################################################

set_exit_code() {
    local code="$1"
    local reason="${2:-}"

    MOK_EXIT_CODE="${code}"

    if [[ -n "${reason}" ]]; then
        log_debug "Setting exit code ${code}: ${reason}"
    fi
}

exit_with_code() {
    local code="${1:-${MOK_EXIT_CODE}}"
    local message="${2:-}"

    if [[ -n "${message}" ]]; then
        log_info "Exit: ${message} (code ${code})"
    fi

    exit "${code}"
}

exit_success() {
    local message="${1:-Operation completed successfully}"
    log_success "${message}"
    exit_with_code ${EXIT_SUCCESS} "${message}"
}

exit_general_failure() {
    local message="${1:-An error occurred}"
    log_error "${message}"
    exit_with_code ${EXIT_GENERAL_FAILURE} "${message}"
}

exit_prerequisites_failed() {
    local missing="${1:-prerequisites}"
    log_error "Required ${missing} not found or not available"
    exit_with_code ${EXIT_PREREQUISITES_FAILED} "Prerequisites failed: ${missing}"
}

exit_partial_success() {
    local message="${1:-Some operations failed}"
    log_warning "${message}"
    exit_with_code ${EXIT_PARTIAL_SUCCESS} "${message}"
}

exit_system_not_ready() {
    local reason="${1:-System state prevents operation}"
    log_warning "${reason}"
    exit_with_code ${EXIT_SYSTEM_NOT_READY} "${reason}"
}

exit_permission_denied() {
    local reason="${1:-Permission denied}"
    log_error "${reason}"
    exit_with_code ${EXIT_PERMISSION_DENIED} "${reason}"
}

exit_rate_limited() {
    local reason="${1:-Operation blocked by rate limiting}"
    log_error "${reason}"
    exit_with_code ${EXIT_RATE_LIMITED} "${reason}"
}

exit_configuration_error() {
    local reason="${1:-Configuration error}"
    log_error "${reason}"
    exit_with_code ${EXIT_CONFIGURATION_ERROR} "${reason}"
}

exit_interrupted() {
    log_warning "Operation interrupted by user"
    exit_with_code ${EXIT_INTERRUPTED} "Interrupted"
}

exit_terminated() {
    log_warning "Operation terminated by system"
    exit_with_code ${EXIT_TERMINATED} "Terminated"
}

################################################################################
# Decision Helper
################################################################################

determine_exit_code() {
    local modules_total="$1"
    local modules_signed="$2"
    local modules_failed="$3"

    # All successful
    if [[ ${modules_failed} -eq 0 && ${modules_signed} -gt 0 ]]; then
        return ${EXIT_SUCCESS}
    fi

    # No modules to sign
    if [[ ${modules_total} -eq 0 ]]; then
        return ${EXIT_SYSTEM_NOT_READY}
    fi

    # Partial success
    if [[ ${modules_failed} -gt 0 && ${modules_signed} -gt 0 ]]; then
        return ${EXIT_PARTIAL_SUCCESS}
    fi

    # All failed
    if [[ ${modules_failed} -gt 0 ]]; then
        return ${EXIT_GENERAL_FAILURE}
    fi

    # Default success (nothing to sign but prerequisites okay)
    return ${EXIT_SUCCESS}
}

################################################################################
# Signal Handlers
################################################################################

setup_signal_handlers() {
    trap 'exit_interrupted' INT   # Ctrl+C
    trap 'exit_terminated' TERM   # Kill signal
    trap 'trap_exit' EXIT          # Normal exit
}

trap_exit() {
    # Save final exit code before cleanup
    local final_code=$?

    # Run any cleanup operations
    if declare -f cleanup_on_exit &>/dev/null; then
        cleanup_on_exit || true
    fi

    # Ensure lock is released
    if declare -f release_lock &>/dev/null; then
        release_lock || true
    fi

    # Use final code if not already set
    if [[ ${final_code} -ne 0 && ${MOK_EXIT_CODE} -eq 0 ]]; then
        MOK_EXIT_CODE=${final_code}
    fi

    exit "${MOK_EXIT_CODE}"
}

################################################################################
# Display exit information
################################################################################

print_exit_summary() {
    local code="${1:-${MOK_EXIT_CODE}}"

    echo ""
    echo "================== Execution Summary =================="
    echo "Exit Code: ${code}"
    echo "Status: ${EXIT_DESCRIPTIONS[${code}]:-Unknown error code}"
    echo "====================================================="
}

# Export all functions and constants
export -f set_exit_code exit_with_code
export -f exit_success exit_general_failure exit_prerequisites_failed
export -f exit_partial_success exit_system_not_ready exit_permission_denied
export -f exit_rate_limited exit_configuration_error
export -f exit_interrupted exit_terminated
export -f determine_exit_code
export -f setup_signal_handlers trap_exit
export -f print_exit_summary

export MOK_EXIT_CODE EXIT_SUCCESS EXIT_GENERAL_FAILURE
export EXIT_PREREQUISITES_FAILED EXIT_PARTIAL_SUCCESS EXIT_SYSTEM_NOT_READY
export EXIT_PERMISSION_DENIED EXIT_RATE_LIMITED EXIT_CONFIGURATION_ERROR
export EXIT_INTERRUPTED EXIT_TERMINATED
