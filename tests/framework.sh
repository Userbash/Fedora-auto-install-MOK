#!/bin/bash

################################################################################
# MOK Testing Framework
# Comprehensive test suite with callbacks and async support
# Purpose: Unified testing for all MOK components
#
# Features:
#   - Test discovery and execution
#   - Callback-based assertions
#   - Asynchronous test execution
#   - Variable verification
#   - Path validation
#   - Comprehensive reporting
################################################################################

set -euo pipefail

# ============================================================================
# CONSTANTS AND CONFIGURATION
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"

# Determine script location
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
else
    SCRIPT_DIR=$(pwd)
fi
readonly SCRIPT_DIR

PROJECT_ROOT=$(dirname "${SCRIPT_DIR}")
readonly PROJECT_ROOT

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Test directories
readonly TEST_TEMP_DIR=$(mktemp -d) || exit 1
readonly TEST_OUTPUT_DIR="${TEST_TEMP_DIR}/output"
mkdir -p "${TEST_OUTPUT_DIR}"

# Test state
declare -g TEST_SUITE_NAME=""
declare -gA TEST_RESULTS=()
declare -ga TEST_NAMES=()
declare -gi TESTS_TOTAL=0
declare -gi TESTS_PASSED=0
declare -gi TESTS_FAILED=0
declare -gi TESTS_SKIPPED=0
declare -gA TEST_TIMINGS=()

# Callback registry
declare -gA CALLBACKS=()

# ============================================================================
# CLEANUP AND TRAP HANDLERS
# ============================================================================

cleanup() {
    # Clean up temporary files
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

trap cleanup EXIT

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Log message with timestamp
# @param $1 - Log level (INFO, SUCCESS, WARNING, ERROR, DEBUG)
# @param $* - Message text
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "${level}" in
        INFO)
            echo -e "${BLUE}[${timestamp}] [INFO]${NC} ${message}" >&1
            ;;
        SUCCESS)
            echo -e "${GREEN}[${timestamp}] [✓]${NC} ${message}" >&1
            ;;
        WARNING)
            echo -e "${YELLOW}[${timestamp}] [!]${NC} ${message}" >&1
            ;;
        ERROR)
            echo -e "${RED}[${timestamp}] [✗]${NC} ${message}" >&2
            ;;
        DEBUG)
            if [[ "${DEBUG:-0}" == "1" ]]; then
                echo -e "${CYAN}[${timestamp}] [DEBUG]${NC} ${message}" >&1
            fi
            ;;
    esac
}

# ============================================================================
# TEST FRAMEWORK CORE
# ============================================================================

# Initialize test suite
# @param $1 - Suite name
# @returns 0 on success
test_suite_init() {
    local suite_name="${1:?Suite name required}"
    TEST_SUITE_NAME="${suite_name}"
    TESTS_TOTAL=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
    TEST_RESULTS=()
    TEST_NAMES=()

    log INFO "═══════════════════════════════════════════════════════════"
    log INFO "Starting Test Suite: ${suite_name}"
    log INFO "═══════════════════════════════════════════════════════════"
    return 0
}

# Run a single test with callback support
# @param $1 - Test name
# @param $2 - Test function name
# @param $3 - Callback function (optional)
# @returns 0 if test passes, 1 if fails
run_test() {
    local test_name="${1:?Test name required}"
    local test_func="${2:?Test function required}"
    local callback="${3:-}"

    TEST_NAMES+=("${test_name}")
    ((TESTS_TOTAL++))

    local start_time=$(date +%s%N)
    local exit_code=0
    local error_msg=""

    log DEBUG "Running test: ${test_name}"

    # Execute test with error handling
    if ! error_msg=$(${test_func} 2>&1); then
        exit_code=$?
    fi

    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))
    TEST_TIMINGS["${test_name}"]="${duration}ms"

    # Invoke callback if provided
    if [[ -n "${callback}" ]] && declare -f "${callback}" &>/dev/null; then
        ${callback} "${exit_code}" "${test_name}" "${error_msg}"
    fi

    # Process result
    if [[ ${exit_code} -eq 0 ]]; then
        ((TESTS_PASSED++))
        TEST_RESULTS["${test_name}"]="PASSED"
        echo -e "${GREEN}[✓]${NC} ${test_name} (${duration}ms)"
        return 0
    else
        ((TESTS_FAILED++))
        TEST_RESULTS["${test_name}"]="FAILED: ${error_msg}"
        echo -e "${RED}[✗]${NC} ${test_name} (${duration}ms)"
        echo -e "  Error: ${error_msg}"
        return 1
    fi
}

# Skip a test
# @param $1 - Test name
# @param $2 - Skip reason
skip_test() {
    local test_name="${1:?Test name required}"
    local reason="${2:-No reason provided}"

    TEST_NAMES+=("${test_name}")
    ((TESTS_TOTAL++))
    ((TESTS_SKIPPED++))
    TEST_RESULTS["${test_name}"]="SKIPPED: ${reason}"

    echo -e "${YELLOW}[~]${NC} ${test_name} - ${reason}"
}

# Register callback function
# @param $1 - Callback name
# @param $2 - Function name
register_callback() {
    local callback_name="${1:?Callback name required}"
    local function_name="${2:?Function name required}"

    if ! declare -f "${function_name}" &>/dev/null; then
        log ERROR "Callback function not found: ${function_name}"
        return 1
    fi

    CALLBACKS["${callback_name}"]="${function_name}"
    log DEBUG "Registered callback: ${callback_name} -> ${function_name}"
    return 0
}

# Invoke registered callback
# @param $1 - Callback name
# @param $* - Arguments to pass
invoke_callback() {
    local callback_name="${1:?Callback name required}"
    shift

    if [[ -z "${CALLBACKS[${callback_name}]:-}" ]]; then
        log WARNING "Callback not found: ${callback_name}"
        return 1
    fi

    local func="${CALLBACKS[${callback_name}]}"
    ${func} "$@"
}

# ============================================================================
# ASSERTION FUNCTIONS
# ============================================================================

# Assert equality
# @param $1 - Actual value
# @param $2 - Expected value
# @param $3 - Assertion description (optional)
# @returns 0 if equal, 1 if not
assert_equals() {
    local actual="${1:?Actual value required}"
    local expected="${2:?Expected value required}"
    local description="${3:-Equality assertion}"

    if [[ "${actual}" == "${expected}" ]]; then
        log DEBUG "✓ ${description}: '${actual}' == '${expected}'"
        return 0
    else
        log ERROR "✗ ${description}: '${actual}' != '${expected}'"
        return 1
    fi
}

# Assert not equal
# @param $1 - Actual value
# @param $2 - Not expected value
# @param $3 - Assertion description (optional)
assert_not_equals() {
    local actual="${1:?Actual value required}"
    local not_expected="${2:?Not expected value required}"
    local description="${3:-Not equal assertion}"

    if [[ "${actual}" != "${not_expected}" ]]; then
        log DEBUG "✓ ${description}: '${actual}' != '${not_expected}'"
        return 0
    else
        log ERROR "✗ ${description}: '${actual}' == '${not_expected}'"
        return 1
    fi
}

# Assert true
# @param $1 - Command/condition to test
# @param $2 - Assertion description (optional)
assert_true() {
    local condition="${1:?Condition required}"
    local description="${2:-Truth assertion}"

    if eval "${condition}" 2>/dev/null; then
        log DEBUG "✓ ${description}: ${condition}"
        return 0
    else
        log ERROR "✗ ${description}: ${condition}"
        return 1
    fi
}

# Assert false
# @param $1 - Command/condition to test
# @param $2 - Assertion description (optional)
assert_false() {
    local condition="${1:?Condition required}"
    local description="${2:-Falsehood assertion}"

    if ! eval "${condition}" 2>/dev/null; then
        log DEBUG "✓ ${description}: NOT ${condition}"
        return 0
    else
        log ERROR "✗ ${description}: ${condition} (should be false)"
        return 1
    fi
}

# Assert file exists
# @param $1 - File path
# @param $2 - Assertion description (optional)
assert_file_exists() {
    local file="${1:?File path required}"
    local description="${2:-File exists: ${file}}"

    if [[ -f "${file}" ]]; then
        log DEBUG "✓ ${description}"
        return 0
    else
        log ERROR "✗ ${description}"
        return 1
    fi
}

# Assert directory exists
# @param $1 - Directory path
# @param $2 - Assertion description (optional)
assert_dir_exists() {
    local dir="${1:?Directory path required}"
    local description="${2:-Directory exists: ${dir}}"

    if [[ -d "${dir}" ]]; then
        log DEBUG "✓ ${description}"
        return 0
    else
        log ERROR "✗ ${description}"
        return 1
    fi
}

# Assert variable is set
# @param $1 - Variable name
# @param $2 - Assertion description (optional)
assert_var_set() {
    local var_name="${1:?Variable name required}"
    local description="${2:-Variable is set: ${var_name}}"

    if [[ -v "${var_name}" ]]; then
        log DEBUG "✓ ${description}"
        return 0
    else
        log ERROR "✗ ${description}"
        return 1
    fi
}

# Assert variable is not empty
# @param $1 - Variable name
# @param $2 - Assertion description (optional)
assert_var_not_empty() {
    local var_name="${1:?Variable name required}"
    local description="${2:-Variable not empty: ${var_name}}"

    if [[ -v "${var_name}" ]] && [[ -n "${!var_name}" ]]; then
        log DEBUG "✓ ${description}"
        return 0
    else
        log ERROR "✗ ${description}"
        return 1
    fi
}

# Assert array contains element
# @param $1 - Array name
# @param $2 - Element to find
# @param $3 - Assertion description (optional)
assert_array_contains() {
    local array_name="${1:?Array name required}"
    local element="${2:?Element required}"
    local description="${3:-Array contains: ${element}}"

    # Indirect reference to array
    eval "local -n arr=${array_name}"

    for item in "${arr[@]}"; do
        if [[ "${item}" == "${element}" ]]; then
            log DEBUG "✓ ${description}"
            return 0
        fi
    done

    log ERROR "✗ ${description}"
    return 1
}

# ============================================================================
# PATH VALIDATION FUNCTIONS
# ============================================================================

# Verify relative path
# @param $1 - Relative path
# @returns 0 if valid relative path, 1 otherwise
verify_relative_path() {
    local path="${1:?Path required}"

    # Check if path doesn't start with /
    if [[ ! "${path}" =~ ^/ ]]; then
        return 0
    else
        return 1
    fi
}

# Verify absolute path
# @param $1 - Absolute path
# @returns 0 if valid absolute path, 1 otherwise
verify_absolute_path() {
    local path="${1:?Path required}"

    # Check if path starts with /
    if [[ "${path}" =~ ^/ ]]; then
        return 0
    else
        return 1
    fi
}

# Resolve relative path
# @param $1 - Relative path
# @param $2 - Base directory (optional, defaults to PROJECT_ROOT)
# @returns resolved absolute path
resolve_path() {
    local rel_path="${1:?Relative path required}"
    local base_dir="${2:-.}"

    # Get absolute path of base directory
    local abs_base
    abs_base=$(cd "${base_dir}" && pwd) || return 1

    # Combine and normalize
    local resolved="${abs_base}/${rel_path}"
    cd "$(dirname "${resolved}")" && pwd && echo "/$(basename "${resolved}")" || return 1
}

# Verify paths in array
# @param $1 - Array name (local variable reference)
# @returns 0 if all paths exist, 1 otherwise
verify_path_array() {
    local array_name="${1:?Array name required}"

    eval "local -n paths=${array_name}"

    for path in "${paths[@]}"; do
        if [[ ! -e "${path}" ]]; then
            log ERROR "Path not found: ${path}"
            return 1
        fi
    done

    return 0
}

# ============================================================================
# VARIABLE VALIDATION AND CLEANUP
# ============================================================================

# Verify variable existence
# @param $1 - Variable name
# @returns 0 if variable exists, 1 otherwise
verify_var_exists() {
    local var_name="${1:?Variable name required}"

    if [[ -v "${var_name}" ]]; then
        log DEBUG "Variable exists: ${var_name}"
        return 0
    else
        log ERROR "Variable not found: ${var_name}"
        return 1
    fi
}

# Verify variable type
# @param $1 - Variable name
# @param $2 - Expected type (string, number, boolean, array)
# @returns 0 if type matches, 1 otherwise
verify_var_type() {
    local var_name="${1:?Variable name required}"
    local expected_type="${2:?Type required}"

    if [[ ! -v "${var_name}" ]]; then
        log ERROR "Variable not set: ${var_name}"
        return 1
    fi

    local value="${!var_name}"

    case "${expected_type}" in
        number)
            if [[ "${value}" =~ ^[0-9]+$ ]]; then
                return 0
            fi
            ;;
        boolean)
            if [[ "${value}" =~ ^(true|false|yes|no|1|0)$ ]]; then
                return 0
            fi
            ;;
        string)
            if [[ -n "${value}" ]]; then
                return 0
            fi
            ;;
        array)
            if declare -p "${var_name}" 2>/dev/null | grep -q "declare -a"; then
                return 0
            fi
            ;;
    esac

    log ERROR "Type mismatch for ${var_name}: expected ${expected_type}, got ${value}"
    return 1
}

# Verify local variable (function scope)
# @param $1 - Variable name
# @returns 0 if variable is local, 1 otherwise
verify_local_var() {
    local var_name="${1:?Variable name required}"

    # Check if variable is in current function scope
    if [[ ${#FUNCNAME[@]} -gt 1 ]]; then
        # We're in a function
        if [[ -v "${var_name}" ]]; then
            return 0
        fi
    fi

    return 1
}

# Clear variable
# @param $1 - Variable name
# @returns 0 on success
clear_var() {
    local var_name="${1:?Variable name required}"

    unset "${var_name}"
    log DEBUG "Cleared variable: ${var_name}"
    return 0
}

# Clear multiple variables
# @param $* - Variable names
# @returns 0 on success
clear_vars() {
    local var_names=("$@")

    for var_name in "${var_names[@]}"; do
        if [[ -v "${var_name}" ]]; then
            unset "${var_name}"
            log DEBUG "Cleared variable: ${var_name}"
        fi
    done

    return 0
}

# Clear array
# @param $1 - Array name
# @returns 0 on success
clear_array() {
    local array_name="${1:?Array name required}"

    unset "${array_name}"
    log DEBUG "Cleared array: ${array_name}"
    return 0
}

# ============================================================================
# TEST REPORTING
# ============================================================================

# Print test summary
# @returns 0
report_test_summary() {
    local total=${TESTS_TOTAL}
    local passed=${TESTS_PASSED}
    local failed=${TESTS_FAILED}
    local skipped=${TESTS_SKIPPED}

    echo ""
    log INFO "═══════════════════════════════════════════════════════════"
    log INFO "Test Suite: ${TEST_SUITE_NAME}"
    log INFO "═══════════════════════════════════════════════════════════"
    log INFO "Total Tests:   ${total}"
    log SUCCESS "Passed:        ${passed}"
    if [[ ${failed} -gt 0 ]]; then
        log ERROR "Failed:        ${failed}"
    else
        log SUCCESS "Failed:        ${failed}"
    fi
    log WARNING "Skipped:       ${skipped}"

    # Calculate pass rate
    if [[ ${total} -gt 0 ]]; then
        local pass_rate=$(( (passed * 100) / total ))
        log INFO "Pass Rate:     ${pass_rate}%"
    fi

    echo ""
    return 0
}

# Generate JSON report
# @param $1 - Output file path (optional)
# @returns 0 on success
report_json() {
    local output_file="${1:-${TEST_OUTPUT_DIR}/report.json}"

    {
        echo "{"
        echo "  \"suite\": \"${TEST_SUITE_NAME}\","
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"total\": ${TESTS_TOTAL},"
        echo "  \"passed\": ${TESTS_PASSED},"
        echo "  \"failed\": ${TESTS_FAILED},"
        echo "  \"skipped\": ${TESTS_SKIPPED},"
        echo "  \"results\": {"

        local first=true
        for test_name in "${TEST_NAMES[@]}"; do
            if [[ "${first}" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    \"${test_name}\": {"
            echo -n "\"status\": \"${TEST_RESULTS[${test_name}]}\""
            if [[ -v TEST_TIMINGS["${test_name}"] ]]; then
                echo -n ", \"duration\": \"${TEST_TIMINGS[${test_name}]}\""
            fi
            echo -n "}"
        done

        echo ""
        echo "  }"
        echo "}"
    } > "${output_file}"

    log INFO "JSON report saved to: ${output_file}"
    return 0
}

# ============================================================================
# EXPORTS
# ============================================================================

# Export framework functions for use in test files
export -f test_suite_init run_test skip_test register_callback invoke_callback
export -f assert_equals assert_not_equals assert_true assert_false
export -f assert_file_exists assert_dir_exists assert_var_set assert_var_not_empty
export -f assert_array_contains
export -f verify_relative_path verify_absolute_path resolve_path verify_path_array
export -f verify_var_exists verify_var_type verify_local_var
export -f clear_var clear_vars clear_array
export -f log report_test_summary report_json

export TEST_SUITE_NAME TEST_RESULTS TEST_NAMES TESTS_TOTAL TESTS_PASSED TESTS_FAILED TESTS_SKIPPED
export TEST_TIMINGS CALLBACKS PROJECT_ROOT TEST_TEMP_DIR

# ============================================================================
# END OF FRAMEWORK
# ============================================================================

return 0
