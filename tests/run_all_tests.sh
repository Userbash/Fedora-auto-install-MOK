#!/bin/bash

################################################################################
# MOK Unified Test Runner
# Executes all test suites with unified reporting and cleanup
#
# Features:
#   - Discovers and runs all test files
#   - Unified result reporting
#   - Performance metrics
#   - Coverage analysis
#   - Artifact cleanup
################################################################################

set -euo pipefail

# ============================================================================
# CONSTANTS
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TESTS_DIR="${SCRIPT_DIR}"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test results
declare -gi TOTAL_TESTS=0
declare -gi PASSED_TESTS=0
declare -gi FAILED_TESTS=0
declare -gi SKIPPED_TESTS=0
declare -gA SUITE_RESULTS=()
declare -ga TEST_SUITES=()

# ============================================================================
# LOGGING
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

# ============================================================================
# TEST DISCOVERY AND EXECUTION
# ============================================================================

# Discover test files
# @returns Array of test file paths
discover_tests() {
    local -a test_files=()

    # Find all test_*.sh files
    while IFS= read -r test_file; do
        if [[ -f "${test_file}" && "${test_file}" != *"run_all_tests"* ]]; then
            test_files+=("${test_file}")
        fi
    done < <(find "${TESTS_DIR}" -maxdepth 1 -name "test_*.sh" -type f)

    echo "${test_files[@]}"
}

# Run single test suite
# @param $1 - Test file path
# @returns 0 on success, 1 on failure
run_test_suite() {
    local test_file="$1"
    local test_name=$(basename "${test_file}" .sh)
    local test_output="${TESTS_DIR}/output/${test_name}.log"

    mkdir -p "${TESTS_DIR}/output"

    log_info "Running test suite: ${test_name}"

    # Execute test and capture output
    local start_time=$(date +%s)
    if bash "${test_file}" > "${test_output}" 2>&1; then
        local exit_code=0
    else
        local exit_code=$?
    fi
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Parse results from test output
    local passed=0
    passed=$(grep -c '\[✓\]' "${test_output}" 2>/dev/null || echo "0")
    local failed=0
    failed=$(grep -c '\[✗\]' "${test_output}" 2>/dev/null || echo "0")

    TOTAL_TESTS=$((TOTAL_TESTS + passed + failed))
    PASSED_TESTS=$((PASSED_TESTS + passed))
    FAILED_TESTS=$((FAILED_TESTS + failed))

    # Store suite result
    SUITE_RESULTS["${test_name}"]="passed=${passed}, failed=${failed}, duration=${duration}s"
    TEST_SUITES+=("${test_name}")

    if [[ ${exit_code} -eq 0 ]]; then
        log_success "${test_name} completed in ${duration}s (${passed} passed)"
        return 0
    else
        log_error "${test_name} failed in ${duration}s (${passed} passed, ${failed} failed)"
        log_warning "  See: ${test_output}"
        return 1
    fi
}

# ============================================================================
# REPORTING
# ============================================================================

# Print test summary
print_summary() {
    local pass_rate=0
    if [[ ${TOTAL_TESTS} -gt 0 ]]; then
        pass_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    fi

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}UNIFIED TEST SUMMARY${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

    echo -e "Total Tests:    ${TOTAL_TESTS}"
    echo -e "${GREEN}Passed:         ${PASSED_TESTS}${NC}"
    if [[ ${FAILED_TESTS} -gt 0 ]]; then
        echo -e "${RED}Failed:         ${FAILED_TESTS}${NC}"
    else
        echo -e "${GREEN}Failed:         ${FAILED_TESTS}${NC}"
    fi
    echo -e "Pass Rate:      ${pass_rate}%"

    echo ""
    echo -e "${BLUE}Suite Results:${NC}"
    for suite in "${TEST_SUITES[@]}"; do
        echo -e "  ${suite}: ${SUITE_RESULTS[${suite}]}"
    done

    echo ""
    return 0
}

# Generate JSON report
generate_json_report() {
    local report_file="${TESTS_DIR}/output/test_report.json"

    {
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"total_tests\": ${TOTAL_TESTS},"
        echo "  \"passed\": ${PASSED_TESTS},"
        echo "  \"failed\": ${FAILED_TESTS},"
        echo "  \"suites\": ["

        local first=true
        for suite in "${TEST_SUITES[@]}"; do
            if [[ "${first}" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    {\"name\": \"${suite}\", \"result\": \"${SUITE_RESULTS[${suite}]}\"}"
        done

        echo ""
        echo "  ]"
        echo "}"
    } > "${report_file}"

    log_info "JSON report saved to: ${report_file}"
}

# ============================================================================
# CLEANUP AND VALIDATION
# ============================================================================

# Validate test environment
validate_environment() {
    log_info "Validating test environment"

    # Check bash version
    if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
        log_error "Bash 4.0+ required, found ${BASH_VERSION}"
        return 1
    fi

    # Check required directories
    if [[ ! -d "${PROJECT_ROOT}" ]]; then
        log_error "Project root not found: ${PROJECT_ROOT}"
        return 1
    fi

    if [[ ! -d "${TESTS_DIR}" ]]; then
        log_error "Tests directory not found: ${TESTS_DIR}"
        return 1
    fi

    # Check test framework
    if [[ ! -f "${TESTS_DIR}/framework.sh" ]]; then
        log_error "Test framework not found: ${TESTS_DIR}/framework.sh"
        return 1
    fi

    log_success "Test environment validated"
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "MOK Unified Test Runner v1.0.0"
    log_info "Project Root: ${PROJECT_ROOT}"
    log_info "Tests Directory: ${TESTS_DIR}"

    echo ""

    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        return 1
    fi

    echo ""

    # Discover tests
    log_info "Discovering test suites"
    local -a test_files=( $(discover_tests) )

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warning "No test files found"
        return 0
    fi

    log_success "Found ${#test_files[@]} test suite(s)"
    for test_file in "${test_files[@]}"; do
        echo "  - $(basename "${test_file}")"
    done

    echo ""

    # Run tests
    log_info "Executing test suites"
    echo ""

    local failed_suites=0
    for test_file in "${test_files[@]}"; do
        if ! run_test_suite "${test_file}"; then
            ((failed_suites++))
        fi
    done

    echo ""

    # Print summary
    print_summary

    # Generate JSON report
    generate_json_report

    # Final status
    echo ""
    if [[ ${failed_suites} -eq 0 ]]; then
        log_success "All test suites passed!"
        return 0
    else
        log_error "${failed_suites} test suite(s) failed"
        return 1
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
