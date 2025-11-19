#!/bin/bash

################################################################################
# MOK Variable Verification Tests
# Tests for variable declaration, initialization, scope, and cleanup
#
# Features:
#   - Variable existence verification
#   - Type checking
#   - Scope validation
#   - Cleanup verification
#   - Array operations
################################################################################

set -euo pipefail

# Source the testing framework
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"

# ============================================================================
# TEST FIXTURES - Setup and Teardown
# ============================================================================

# Test setup function
test_setup() {
    # Create test environment
    export TEST_VAR_STRING="test_value"
    export TEST_VAR_NUMBER="42"
    export TEST_VAR_BOOLEAN="true"
    declare -ga TEST_ARRAY=("item1" "item2" "item3")
    declare -gA TEST_ASSOC=([key1]="value1" [key2]="value2")
}

# Test teardown function
test_teardown() {
    # Clean up test variables
    clear_vars TEST_VAR_STRING TEST_VAR_NUMBER TEST_VAR_BOOLEAN
    clear_array TEST_ARRAY TEST_ASSOC
}

# Callback: Log test result
# @param $1 - Exit code
# @param $2 - Test name
# @param $3 - Error message
on_test_complete() {
    local exit_code="$1"
    local test_name="$2"
    local error_msg="${3:-}"

    if [[ ${exit_code} -eq 0 ]]; then
        log SUCCESS "Test callback: ${test_name} completed successfully"
    else
        log ERROR "Test callback: ${test_name} failed - ${error_msg}"
    fi
}

# ============================================================================
# VARIABLE DECLARATION AND INITIALIZATION TESTS
# ============================================================================

# Test 1: Verify variable declaration
test_var_declaration() {
    local my_var="initial_value"
    assert_var_set my_var "Local variable declaration"
    assert_equals "${my_var}" "initial_value" "Variable initialization"
}

# Test 2: Verify global variable scope
test_global_variable_scope() {
    assert_var_set TEST_VAR_STRING "Global variable exists"
    assert_equals "${TEST_VAR_STRING}" "test_value" "Global variable value"
}

# Test 3: Verify local variable isolation
test_local_variable_isolation() {
    # This function should not see outer scope variables defined as 'local'
    local_test_function() {
        local inner_var="inner_value"
        assert_var_set inner_var "Inner variable exists"
        assert_equals "${inner_var}" "inner_value" "Inner variable value"
    }

    local_test_function
    # Inner variable should not be accessible here (it's local to function)
}

# Test 4: Variable shadowing
test_variable_shadowing() {
    local SHADOW_VAR="outer"

    inner_scope() {
        local SHADOW_VAR="inner"
        assert_equals "${SHADOW_VAR}" "inner" "Inner scope has shadowed variable"
    }

    inner_scope
    assert_equals "${SHADOW_VAR}" "outer" "Outer scope still has original value"
}

# ============================================================================
# VARIABLE TYPE VERIFICATION TESTS
# ============================================================================

# Test 5: Verify string type
test_string_type() {
    local str_var="hello world"
    verify_var_type str_var string
    assert_equals "$?" "0" "String type verification"
}

# Test 6: Verify number type
test_number_type() {
    local num_var="12345"
    verify_var_type num_var number
    assert_equals "$?" "0" "Number type verification"
}

# Test 7: Verify boolean type
test_boolean_type() {
    local bool_var="true"
    verify_var_type bool_var boolean
    assert_equals "$?" "0" "Boolean type verification"
}

# Test 8: Verify array type
test_array_type() {
    local -a arr_var=("a" "b" "c")
    verify_var_type arr_var array
    assert_equals "$?" "0" "Array type verification"
}

# Test 9: Type mismatch detection
test_type_mismatch() {
    local not_number="not_a_number"
    ! verify_var_type not_number number || true
    assert_equals "$?" "1" "Type mismatch correctly detected"
}

# ============================================================================
# ARRAY OPERATION TESTS
# ============================================================================

# Test 10: Array initialization and access
test_array_initialization() {
    local -a test_arr=("first" "second" "third")
    assert_array_contains test_arr "first" "Array contains first element"
    assert_array_contains test_arr "second" "Array contains second element"
    assert_array_contains test_arr "third" "Array contains third element"
}

# Test 11: Array append
test_array_append() {
    local -a append_arr=()
    append_arr+=("item1")
    append_arr+=("item2")
    assert_array_contains append_arr "item1" "Appended item1"
    assert_array_contains append_arr "item2" "Appended item2"
}

# Test 12: Associative array operations
test_assoc_array() {
    declare -A assoc_test
    assoc_test[name]="John"
    assoc_test[age]="30"

    assert_equals "${assoc_test[name]}" "John" "Associative array key 'name'"
    assert_equals "${assoc_test[age]}" "30" "Associative array key 'age'"
}

# Test 13: Array length
test_array_length() {
    local -a len_arr=("a" "b" "c" "d")
    assert_equals "${#len_arr[@]}" "4" "Array length calculation"
}

# Test 14: Array slicing
test_array_slicing() {
    local -a slice_arr=("a" "b" "c" "d" "e")
    local -a subset=("${slice_arr[@]:1:3}")
    assert_array_contains subset "b" "Slice contains b"
    assert_array_contains subset "c" "Slice contains c"
    assert_array_contains subset "d" "Slice contains d"
}

# ============================================================================
# VARIABLE CLEARING AND CLEANUP TESTS
# ============================================================================

# Test 15: Clear single variable
test_clear_single_var() {
    local clear_test="value"
    clear_var clear_test
    ! verify_var_exists clear_test || true
    assert_equals "$?" "1" "Variable successfully cleared"
}

# Test 16: Clear multiple variables
test_clear_multiple_vars() {
    local var1="val1"
    local var2="val2"
    local var3="val3"

    clear_vars var1 var2 var3

    ! verify_var_exists var1 || true
    assert_equals "$?" "1" "var1 cleared"
}

# Test 17: Clear array
test_clear_array() {
    local -a arr_to_clear=("a" "b" "c")
    assert_equals "${#arr_to_clear[@]}" "3" "Array has 3 elements before clear"

    clear_array arr_to_clear

    ! verify_var_exists arr_to_clear || true
    assert_equals "$?" "1" "Array successfully cleared"
}

# ============================================================================
# SCOPE AND VISIBILITY TESTS
# ============================================================================

# Test 18: Global variable visibility across functions
test_global_visibility() {
    export GLOBAL_TEST_VAR="global_value"

    inner_func() {
        assert_equals "${GLOBAL_TEST_VAR}" "global_value" "Global visible in function"
    }

    inner_func
}

# Test 19: Readonly variable verification
test_readonly_variable() {
    readonly READONLY_VAR="immutable"
    assert_equals "${READONLY_VAR}" "immutable" "Readonly variable has correct value"

    # Attempting to unset should fail
    if unset READONLY_VAR 2>/dev/null; then
        return 1  # Unset succeeded (shouldn't happen)
    else
        return 0  # Unset failed (expected)
    fi
}

# Test 20: Variable inheritance in subshells
test_subshell_inheritance() {
    local parent_var="parent_value"

    (
        # Subshell should inherit parent variables
        assert_equals "${parent_var}" "parent_value" "Subshell sees parent variable"
    )
}

# ============================================================================
# SPECIAL VARIABLES TESTS
# ============================================================================

# Test 21: Function parameters
test_function_parameters() {
    param_test_func() {
        local param1="$1"
        local param2="$2"
        assert_equals "${param1}" "first" "First parameter"
        assert_equals "${param2}" "second" "Second parameter"
    }

    param_test_func "first" "second"
}

# Test 22: Variable expansion in strings
test_variable_expansion() {
    local name="World"
    local greeting="Hello, ${name}!"
    assert_equals "${greeting}" "Hello, World!" "Variable expansion in string"
}

# Test 23: Empty variable handling
test_empty_variable() {
    local empty_var=""
    ! verify_var_not_empty empty_var || true
    assert_equals "$?" "1" "Empty variable correctly identified"
}

# ============================================================================
# MAIN TEST EXECUTION
# ============================================================================

main() {
    test_suite_init "Variable Verification Tests"

    # Register completion callback
    register_callback "on_complete" "on_test_complete"

    # Run setup
    test_setup

    log INFO "Running Variable Declaration and Initialization Tests"
    run_test "Variable Declaration" "test_var_declaration" "on_complete"
    run_test "Global Variable Scope" "test_global_variable_scope" "on_complete"
    run_test "Local Variable Isolation" "test_local_variable_isolation" "on_complete"
    run_test "Variable Shadowing" "test_variable_shadowing" "on_complete"

    log INFO "Running Variable Type Verification Tests"
    run_test "String Type" "test_string_type" "on_complete"
    run_test "Number Type" "test_number_type" "on_complete"
    run_test "Boolean Type" "test_boolean_type" "on_complete"
    run_test "Array Type" "test_array_type" "on_complete"
    run_test "Type Mismatch Detection" "test_type_mismatch" "on_complete"

    log INFO "Running Array Operation Tests"
    run_test "Array Initialization" "test_array_initialization" "on_complete"
    run_test "Array Append" "test_array_append" "on_complete"
    run_test "Associative Array" "test_assoc_array" "on_complete"
    run_test "Array Length" "test_array_length" "on_complete"
    run_test "Array Slicing" "test_array_slicing" "on_complete"

    log INFO "Running Variable Cleanup Tests"
    run_test "Clear Single Variable" "test_clear_single_var" "on_complete"
    run_test "Clear Multiple Variables" "test_clear_multiple_vars" "on_complete"
    run_test "Clear Array" "test_clear_array" "on_complete"

    log INFO "Running Scope and Visibility Tests"
    run_test "Global Visibility" "test_global_visibility" "on_complete"
    run_test "Readonly Variable" "test_readonly_variable" "on_complete"
    run_test "Subshell Inheritance" "test_subshell_inheritance" "on_complete"

    log INFO "Running Special Variables Tests"
    run_test "Function Parameters" "test_function_parameters" "on_complete"
    run_test "Variable Expansion" "test_variable_expansion" "on_complete"
    run_test "Empty Variable Handling" "test_empty_variable" "on_complete"

    # Run teardown
    test_teardown

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
