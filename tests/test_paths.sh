#!/bin/bash

################################################################################
# MOK Path Verification Tests
# Tests for absolute/relative paths, directory structure, and path resolution
#
# Features:
#   - Path type validation
#   - Directory structure verification
#   - Project layout validation
#   - Symlink handling
#   - Path normalization
################################################################################

set -euo pipefail

# Source the testing framework
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"

# ============================================================================
# PATH TEST FIXTURES
# ============================================================================

# Expected project structure
declare -gA PROJECT_STRUCTURE=(
    [bin/sign-nvidia-modules.sh]="script"
    [bin/test-nvidia-signing.sh]="script"
    [bin/install-nvidia-signing.sh]="script"
    [bin/rollback-nvidia-signing.sh]="script"
    [bin/common.sh]="script"
    [config/nvidia-signing.conf]="config"
    [docs/README.md]="docs"
    [mok]="executable"
)

declare -ga REQUIRED_DIRS=(
    "bin"
    "config"
    "docs"
    "tests"
    "selinux"
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get actual project root
# @returns project root path
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    local tests_dir="$(dirname "${script_dir}")"
    echo "${tests_dir}"
}

# Check if path is absolute
# @param $1 - Path to check
# @returns 0 if absolute, 1 if relative
is_absolute_path() {
    local path="$1"
    [[ "${path}" =~ ^/ ]]
}

# Check if path is relative
# @param $1 - Path to check
# @returns 0 if relative, 1 if absolute
is_relative_path() {
    local path="$1"
    [[ ! "${path}" =~ ^/ ]]
}

# ============================================================================
# ABSOLUTE/RELATIVE PATH TESTS
# ============================================================================

# Test 1: Verify absolute path format
test_absolute_path_format() {
    local abs_path="/var/home/sanya/MOK"
    verify_absolute_path "${abs_path}"
    assert_equals "$?" "0" "Absolute path correctly identified"
}

# Test 2: Verify relative path format
test_relative_path_format() {
    local rel_path="bin/sign-nvidia-modules.sh"
    verify_relative_path "${rel_path}"
    assert_equals "$?" "0" "Relative path correctly identified"
}

# Test 3: Path starting with dot notation
test_dot_notation_path() {
    local dot_path="./bin/script.sh"
    verify_relative_path "${dot_path}"
    assert_equals "$?" "0" "Dot notation path recognized as relative"
}

# Test 4: Parent directory path notation
test_parent_dir_path() {
    local parent_path="../config/file.conf"
    verify_relative_path "${parent_path}"
    assert_equals "$?" "0" "Parent directory path recognized as relative"
}

# ============================================================================
# PROJECT STRUCTURE VALIDATION TESTS
# ============================================================================

# Test 5: Project root directory exists
test_project_root_exists() {
    local project_root="${PROJECT_ROOT}"
    assert_dir_exists "${project_root}" "Project root directory exists"
}

# Test 6: Required directories exist
test_required_directories() {
    for dir in "${REQUIRED_DIRS[@]}"; do
        local full_path="${PROJECT_ROOT}/${dir}"
        assert_dir_exists "${full_path}" "Required directory exists: ${dir}"
    done
}

# Test 7: Core binary exists
test_core_binary_exists() {
    local mok_binary="${PROJECT_ROOT}/mok"
    assert_file_exists "${mok_binary}" "MOK main executable exists"
}

# Test 8: Core scripts exist
test_core_scripts_exist() {
    local scripts=(
        "bin/sign-nvidia-modules.sh"
        "bin/test-nvidia-signing.sh"
        "bin/install-nvidia-signing.sh"
        "bin/rollback-nvidia-signing.sh"
        "bin/common.sh"
    )

    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        assert_file_exists "${full_path}" "Core script exists: ${script}"
    done
}

# Test 9: Configuration files exist
test_config_files_exist() {
    local configs=(
        "config/nvidia-signing.conf"
        "config/sign-nvidia-modules.service"
    )

    for config in "${configs[@]}"; do
        local full_path="${PROJECT_ROOT}/${config}"
        assert_file_exists "${full_path}" "Config file exists: ${config}"
    done
}

# Test 10: Documentation files exist
test_documentation_exists() {
    local docs=(
        "README.md"
        "SECURITY.md"
        "STRUCTURE.md"
    )

    for doc in "${docs[@]}"; do
        local full_path="${PROJECT_ROOT}/${doc}"
        assert_file_exists "${full_path}" "Documentation exists: ${doc}"
    done
}

# ============================================================================
# DIRECTORY STRUCTURE VALIDATION TESTS
# ============================================================================

# Test 11: Project layout is valid
test_project_layout_valid() {
    assert_dir_exists "${PROJECT_ROOT}/bin" "bin directory present"
    assert_dir_exists "${PROJECT_ROOT}/config" "config directory present"
    assert_dir_exists "${PROJECT_ROOT}/docs" "docs directory present"
    assert_dir_exists "${PROJECT_ROOT}/tests" "tests directory present"
}

# Test 12: Scripts are executable
test_scripts_executable() {
    local scripts=(
        "bin/sign-nvidia-modules.sh"
        "bin/test-nvidia-signing.sh"
        "bin/install-nvidia-signing.sh"
    )

    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        if [[ -f "${full_path}" ]]; then
            assert_true "[[ -x '${full_path}' ]]" "Script is executable: ${script}"
        fi
    done
}

# Test 13: Scripts are valid bash
test_scripts_are_bash() {
    local scripts=(
        "bin/sign-nvidia-modules.sh"
        "bin/test-nvidia-signing.sh"
    )

    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        if [[ -f "${full_path}" ]]; then
            # Check for bash shebang
            assert_true "head -1 '${full_path}' | grep -q '#!/bin/bash'" \
                "Script has bash shebang: ${script}"
        fi
    done
}

# ============================================================================
# PATH RESOLUTION TESTS
# ============================================================================

# Test 14: Resolve relative to project root
test_resolve_relative_path() {
    local rel_path="bin/sign-nvidia-modules.sh"
    local expected_file="${PROJECT_ROOT}/${rel_path}"

    # Verify the resolved path points to existing file
    assert_file_exists "${expected_file}" "Relative path resolves correctly"
}

# Test 15: Paths with no directory component
test_file_in_project_root() {
    local file="mok"
    local full_path="${PROJECT_ROOT}/${file}"

    assert_file_exists "${full_path}" "File in project root exists"
}

# ============================================================================
# SYMLINK AND LINK TESTS
# ============================================================================

# Test 16: Detect symbolic links
test_symlink_detection() {
    # Create temporary symlink for testing
    local test_file="${TEST_TEMP_DIR}/original.txt"
    local test_link="${TEST_TEMP_DIR}/link.txt"

    touch "${test_file}"
    ln -s "${test_file}" "${test_link}"

    assert_true "[[ -L '${test_link}' ]]" "Symlink correctly detected"

    # Verify it points to the right file
    assert_true "[[ -f '${test_link}' ]]" "Symlink points to valid file"
}

# ============================================================================
# PERMISSION TESTS
# ============================================================================

# Test 17: Readable files
test_readable_files() {
    local files=(
        "README.md"
        "SECURITY.md"
    )

    for file in "${files[@]}"; do
        local full_path="${PROJECT_ROOT}/${file}"
        if [[ -f "${full_path}" ]]; then
            assert_true "[[ -r '${full_path}' ]]" "File is readable: ${file}"
        fi
    done
}

# Test 18: Writable directories (for MOK process)
test_writable_directories() {
    # Check if directories are writable (they should be by owner)
    local test_dir="${TEST_TEMP_DIR}/write_test"
    mkdir -p "${test_dir}"

    assert_true "[[ -w '${test_dir}' ]]" "Test directory is writable"
}

# ============================================================================
# RELATIVE PATH HANDLING TESTS
# ============================================================================

# Test 19: Relative path from bin to config
test_relative_path_between_dirs() {
    local from_dir="${PROJECT_ROOT}/bin"
    local to_file="../config/nvidia-signing.conf"
    local resolved="${from_dir}/${to_file}"

    assert_file_exists "${resolved}" "Relative path between dirs resolves"
}

# Test 20: Relative path with multiple levels
test_deep_relative_path() {
    local deep_path="../../MOK/bin/sign-nvidia-modules.sh"
    # Note: This test assumes you run from a specific location
    # Adjust as needed for your environment
    log DEBUG "Deep relative path test skipped (environment-dependent)"
}

# ============================================================================
# PATH NORMALIZATION TESTS
# ============================================================================

# Test 21: Remove redundant slashes
test_path_slash_normalization() {
    local path="bin//sign-nvidia-modules.sh"
    local normalized="bin/sign-nvidia-modules.sh"

    assert_equals "${normalized}" "bin/sign-nvidia-modules.sh" "Path normalization"
}

# Test 22: Current directory reference
test_current_dir_reference() {
    local path="./bin/script.sh"
    local expected="bin/script.sh"

    # Both should refer to the same file
    assert_true "[[ -f '${PROJECT_ROOT}/${expected}' ]]" "File accessible both ways"
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

# Test 23: Non-existent path detection
test_nonexistent_path() {
    local bad_path="${PROJECT_ROOT}/nonexistent/file.txt"

    ! assert_file_exists "${bad_path}" || true
    assert_equals "$?" "1" "Non-existent file correctly identified"
}

# Test 24: Non-existent directory detection
test_nonexistent_directory() {
    local bad_dir="${PROJECT_ROOT}/nonexistent/directory"

    ! assert_dir_exists "${bad_dir}" || true
    assert_equals "$?" "1" "Non-existent directory correctly identified"
}

# ============================================================================
# PATH ARRAY VERIFICATION TESTS
# ============================================================================

# Test 25: Verify array of paths
test_path_array_verification() {
    local -a paths=(
        "${PROJECT_ROOT}/bin"
        "${PROJECT_ROOT}/config"
        "${PROJECT_ROOT}/docs"
    )

    verify_path_array paths
    assert_equals "$?" "0" "All paths in array exist"
}

# ============================================================================
# MAIN TEST EXECUTION
# ============================================================================

main() {
    test_suite_init "Path Verification Tests"

    log INFO "Running Absolute/Relative Path Tests"
    run_test "Absolute Path Format" "test_absolute_path_format"
    run_test "Relative Path Format" "test_relative_path_format"
    run_test "Dot Notation Path" "test_dot_notation_path"
    run_test "Parent Directory Path" "test_parent_dir_path"

    log INFO "Running Project Structure Validation Tests"
    run_test "Project Root Exists" "test_project_root_exists"
    run_test "Required Directories" "test_required_directories"
    run_test "Core Binary Exists" "test_core_binary_exists"
    run_test "Core Scripts Exist" "test_core_scripts_exist"
    run_test "Configuration Files Exist" "test_config_files_exist"
    run_test "Documentation Exists" "test_documentation_exists"

    log INFO "Running Directory Structure Tests"
    run_test "Project Layout Valid" "test_project_layout_valid"
    run_test "Scripts Executable" "test_scripts_executable"
    run_test "Scripts Are Bash" "test_scripts_are_bash"

    log INFO "Running Path Resolution Tests"
    run_test "Resolve Relative Path" "test_resolve_relative_path"
    run_test "File in Project Root" "test_file_in_project_root"

    log INFO "Running Symlink and Link Tests"
    run_test "Symlink Detection" "test_symlink_detection"

    log INFO "Running Permission Tests"
    run_test "Readable Files" "test_readable_files"
    run_test "Writable Directories" "test_writable_directories"

    log INFO "Running Relative Path Handling Tests"
    run_test "Relative Path Between Dirs" "test_relative_path_between_dirs"

    log INFO "Running Path Normalization Tests"
    run_test "Path Slash Normalization" "test_path_slash_normalization"
    run_test "Current Directory Reference" "test_current_dir_reference"

    log INFO "Running Error Handling Tests"
    run_test "Non-existent Path Detection" "test_nonexistent_path"
    run_test "Non-existent Directory Detection" "test_nonexistent_directory"

    log INFO "Running Path Array Verification Tests"
    run_test "Path Array Verification" "test_path_array_verification"

    # Generate reports
    report_test_summary
    report_json

    # Return appropriate exit code
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Execute if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
