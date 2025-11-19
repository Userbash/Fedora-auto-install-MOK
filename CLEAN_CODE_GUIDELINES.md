# MOK Clean Code Guidelines
**Version:** 1.0
**Purpose:** Establish unified code quality standards for the MOK project
**Status:** Standard for all contributions

---

## Table of Contents
1. [General Principles](#general-principles)
2. [Variable Management](#variable-management)
3. [Function Design](#function-design)
4. [Error Handling](#error-handling)
5. [Path Management](#path-management)
6. [Testing Requirements](#testing-requirements)
7. [Documentation Standards](#documentation-standards)
8. [Code Review Checklist](#code-review-checklist)

---

## General Principles

### 1. Single Responsibility Principle
Each function should have one clear purpose.

**Bad:**
```bash
# Function does multiple unrelated things
process_and_sign_and_backup() {
    detect_modules
    sign_modules
    backup_modules
    regenerate_initramfs
}
```

**Good:**
```bash
# Focused function with single purpose
sign_nvidia_modules() {
    local modules_array=("$@")
    # Sign implementation only
}

# Separate orchestrator function
main() {
    local modules
    modules=$(detect_modules) || return 1
    sign_nvidia_modules "${modules[@]}" || return 1
    backup_modules || return 1
}
```

### 2. DRY - Don't Repeat Yourself
Extract repeated code into reusable functions.

**Bad:**
```bash
# Code duplication
if [[ ! -d "${STATE_DIR}" ]]; then
    mkdir -p "${STATE_DIR}"
    chmod 700 "${STATE_DIR}"
fi

if [[ ! -d "${LOG_DIR}" ]]; then
    mkdir -p "${LOG_DIR}"
    chmod 755 "${LOG_DIR}"
fi
```

**Good:**
```bash
# Reusable function
ensure_directory() {
    local dir="$1"
    local perms="${2:-755}"

    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}" || return 1
        chmod "${perms}" "${dir}" || return 1
    fi
}

# Usage
ensure_directory "${STATE_DIR}" 700
ensure_directory "${LOG_DIR}" 755
```

### 3. Clarity Over Cleverness
Write code that is easy to understand, not clever.

**Bad:**
```bash
# Overly clever one-liner
[[ -f "$f" ]] && [[ -r "$f" ]] && [[ $(wc -l < "$f") -gt 0 ]] && process_file "$f" || return 1
```

**Good:**
```bash
# Clear, readable code
if [[ ! -f "$f" ]]; then
    log_error "File not found: $f"
    return 1
fi

if [[ ! -r "$f" ]]; then
    log_error "File not readable: $f"
    return 1
fi

local line_count
line_count=$(wc -l < "$f") || return 1

if [[ ${line_count} -eq 0 ]]; then
    log_warning "File is empty: $f"
    return 1
fi

process_file "$f"
```

### 4. Fail Fast
Check preconditions early and return with appropriate error codes.

**Bad:**
```bash
function process() {
    # Lots of processing
    do_something_complex
    # Check preconditions late
    if [[ ! -v required_var ]]; then
        return 1
    fi
}
```

**Good:**
```bash
function process() {
    # Check preconditions first
    if [[ ! -v required_var ]]; then
        log_error "Required variable not set"
        return 1
    fi

    # Then do processing
    do_something_complex
}
```

---

## Variable Management

### 1. Variable Declaration

#### Always declare variables explicitly
**Bad:**
```bash
some_function() {
    var="value"  # Is this local or global?
}
```

**Good:**
```bash
some_function() {
    local var="value"  # Clearly local to this function
}

# Global declaration at top of script
readonly CONFIG_FILE="/etc/nvidia-signing/config.conf"
```

#### Use meaningful names
**Bad:**
```bash
local x="$1"
local y="$2"
local z=()
```

**Good:**
```bash
local module_path="$1"
local backup_dir="$2"
local signed_modules=()
```

### 2. Variable Scope

#### Mark global variables explicitly
```bash
# At top of script
declare -gr PROJECT_ROOT="/var/home/sanya/MOK"
declare -gi RETRY_COUNT=3
declare -ga REQUIRED_COMMANDS=("mokutil" "dracut" "modinfo")
```

#### Use function-local variables
```bash
sign_module() {
    local module_file="$1"
    local temp_backup
    local signature_status

    # All processing variables are local
}
```

#### Clear variables when done
```bash
process_data() {
    local temporary_data
    # ... use temporary_data

    # Explicitly clear when done
    clear_var temporary_data
}
```

### 3. Array Operations

#### Proper array syntax
**Bad:**
```bash
modules=$array  # Loses array structure
for item in $array; do  # Unquoted expansion
    process "$item"
done
```

**Good:**
```bash
local -a modules=("${original_array[@]}")

for item in "${modules[@]}"; do
    process "${item}"
done
```

#### Array function parameter passing
**Bad:**
```bash
my_func "$array"  # Doesn't pass array structure
```

**Good:**
```bash
# Pass array elements with proper syntax
my_func "${array[@]}"

# Or use nameref for complex scenarios
process_array() {
    local -n arr=$1  # Nameref to array
    for element in "${arr[@]}"; do
        echo "$element"
    done
}

process_array my_array_var
```

---

## Function Design

### 1. Function Structure
Every function should follow this pattern:

```bash
# Function: descriptive_name
# Purpose: Clear description of what it does
# Parameters:
#   $1 - First parameter description
#   $2 - Second parameter description (optional)
# Returns:
#   0 - Success (with description of state changes if any)
#   1 - Error condition (with description)
# Example: descriptive_name "/path/to/file" "option"
descriptive_name() {
    local param1="${1:?First parameter required}"
    local param2="${2:-default_value}"

    # Implementation
    if some_condition; then
        return 0
    else
        log_error "Detailed error message"
        return 1
    fi
}
```

### 2. Callback Functions
Use callbacks for async-like behavior in bash:

```bash
# Define callback handler
on_operation_complete() {
    local exit_code="$1"
    local operation_name="$2"

    if [[ ${exit_code} -eq 0 ]]; then
        log_success "Operation complete: ${operation_name}"
    else
        log_error "Operation failed: ${operation_name}"
    fi
}

# Use with callback registration
run_with_callback() {
    local command="$1"
    local callback="$2"

    local exit_code=0
    if ! output=$($command 2>&1); then
        exit_code=$?
    fi

    # Invoke callback
    if declare -f "${callback}" &>/dev/null; then
        ${callback} ${exit_code} "${command}"
    fi

    return ${exit_code}
}

# Usage
register_callback "on_operation_complete"
run_with_callback "some_operation" "on_operation_complete"
```

### 3. Function Parameters

#### Use parameter validation
```bash
create_backup() {
    local source_file="${1:?Source file required}"
    local backup_dir="${2:?Backup directory required}"

    # Parameters are validated above
    if [[ ! -f "${source_file}" ]]; then
        log_error "Source file not found: ${source_file}"
        return 1
    fi

    # Safe to proceed
}
```

#### Support optional parameters with defaults
```bash
log_message() {
    local level="${1:?Log level required}"
    local message="${2:?Message required}"
    local tag="${3:-MOK}"  # Optional parameter with default

    echo "[${tag}] [${level}] ${message}"
}
```

---

## Error Handling

### 1. Standard Exit Codes
Always use meaningful exit codes:

```bash
# Source exit codes file
source "${PROJECT_ROOT}/bin/exit-codes.sh"

# Use standardized codes
check_requirements || return "$E_PREREQUISITES_FAILED"
verify_secure_boot || return "$E_SECURE_BOOT_REQUIRED"
```

### 2. Error Messages

#### Always explain what went wrong and how to fix it
**Bad:**
```bash
log_error "Failed"
return 1
```

**Good:**
```bash
log_error "Failed to create backup directory: ${backup_dir}"
log_error "Ensure parent directory exists and is writable"
return "$E_IO_ERROR"
```

### 3. Error Recovery

#### Implement recovery where possible
```bash
acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-30}"

    # Check for stale lock
    if [[ -f "${lock_file}" ]]; then
        local lock_age=$(($(date +%s) - $(stat -c %Y "${lock_file}")))
        if [[ ${lock_age} -gt 3600 ]]; then
            log_warning "Removing stale lock file (${lock_age}s old)"
            rm "${lock_file}"
        fi
    fi

    # Atomic lock creation
    if mkdir "${lock_file}.dir" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}
```

---

## Path Management

### 1. Path Variables

#### Use absolute paths for critical operations
```bash
# Define at top of script
readonly STATE_DIR="/var/lib/nvidia-signing"
readonly BACKUP_DIR="${STATE_DIR}/backups"
readonly LOG_DIR="/var/log/nvidia-signing"

# Allow override for testing
: "${STATE_DIR:=/var/lib/nvidia-signing}"
```

#### Verify paths exist before use
```bash
ensure_path() {
    local path="$1"

    if [[ ! -e "${path}" ]]; then
        log_error "Path does not exist: ${path}"
        return 1
    fi

    echo "${path}"
}
```

### 2. Relative Paths

#### Resolve relative paths early
```bash
resolve_to_absolute() {
    local relative_path="$1"
    local base_dir="${2:-.}"

    # Resolve to absolute path
    cd "${base_dir}" || return 1
    pwd
    cd - > /dev/null || return 1
}
```

#### Document path assumptions
```bash
# Assumes PROJECT_ROOT is set
# Uses relative paths based on PROJECT_ROOT
readonly BIN_DIR="${PROJECT_ROOT}/bin"
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
```

### 3. Path Validation

#### Always validate paths before operations
```bash
backup_file() {
    local source="$1"
    local destination="$2"

    # Validate source
    if [[ ! -f "${source}" ]]; then
        log_error "Source file not found: ${source}"
        return 1
    fi

    # Validate destination directory exists
    local dest_dir
    dest_dir=$(dirname "${destination}") || return 1

    if [[ ! -d "${dest_dir}" ]]; then
        log_error "Destination directory does not exist: ${dest_dir}"
        return 1
    fi

    # Safe to backup
    cp "${source}" "${destination}" || return 1
}
```

---

## Testing Requirements

### 1. Function Testability
Design functions to be easily testable:

```bash
# Testable: No global side effects, clear inputs/outputs
calculate_hash() {
    local file="$1"
    sha256sum "${file}" | awk '{print $1}'
}

# Less testable: Modifies global state
hash_file_global() {
    file_hash=$(sha256sum "$1" | awk '{print $1}')
}
```

### 2. Test Coverage
Write tests for:
- Happy path (success case)
- Error conditions
- Edge cases
- Boundary conditions

```bash
# Test example
test_module_detection() {
    # Setup
    local test_module="${TEST_TEMP_DIR}/test.ko"
    touch "${test_module}"

    # Test success case
    find_unsigned_modules
    assert_var_set found_modules "Found unsigned modules"

    # Test empty case
    rm "${test_module}"
    find_unsigned_modules
    assert_equals "${#found_modules[@]}" "0" "No modules found when none exist"

    # Cleanup
    clear_array found_modules
}
```

### 3. Use Testing Framework
All tests must use the MOK testing framework:

```bash
#!/bin/bash
source "$(dirname "$0")/framework.sh"

test_suite_init "My Test Suite"

run_test "First test" "test_function_one"
run_test "Second test" "test_function_two"

report_test_summary
report_json
```

---

## Documentation Standards

### 1. Inline Comments
Comment WHY, not WHAT:

**Bad:**
```bash
# Increment counter
((counter++))

# Check if file exists
if [[ -f "$file" ]]; then
```

**Good:**
```bash
# Increment counter to track retry attempts
((retry_count++))

# Only process regular files, skip symlinks and directories
if [[ -f "$file" ]]; then
```

### 2. Function Headers
Every public function must have documentation:

```bash
# Function: verify_secure_boot
# Purpose: Check if Secure Boot is enabled in firmware
# Parameters: None
# Returns:
#   0 - Secure Boot is enabled
#   1 - Secure Boot is disabled or cannot be determined
# Dependencies: mokutil command must be available
# Example: verify_secure_boot && log_success "Secure Boot enabled"
verify_secure_boot() {
    # Implementation
}
```

### 3. Complex Logic Explanation
For non-obvious logic, explain the approach:

```bash
# Lock file cleanup strategy:
# 1. Check if lock file exists and is stale (>1 hour old)
# 2. If stale, remove it (another process likely crashed)
# 3. Attempt atomic lock directory creation
# 4. Return immediately if we own the lock
acquire_lock_with_recovery() {
    # Implementation following above strategy
}
```

---

## Code Review Checklist

Use this checklist for all code submissions:

### Variables
- [ ] All variables are explicitly declared (local/global)
- [ ] Variable names are descriptive and meaningful
- [ ] Variables are scoped appropriately (local to function or global)
- [ ] No variable shadowing or unintended overwrites
- [ ] Variables are cleared when no longer needed

### Functions
- [ ] Function has single, clear responsibility
- [ ] Function is documented with header comment
- [ ] Function parameters are validated
- [ ] Error handling is present and meaningful
- [ ] Function can be tested independently

### Paths
- [ ] All paths are absolute or clearly relative to a base
- [ ] Paths are validated before use
- [ ] Path assumptions are documented
- [ ] Special path variables are defined at top of file

### Error Handling
- [ ] All error conditions return appropriate exit codes
- [ ] Error messages are descriptive and actionable
- [ ] Resources are cleaned up on error
- [ ] Stack trace or context is provided when possible

### Testing
- [ ] New code has corresponding tests
- [ ] Tests cover success and failure cases
- [ ] Tests verify variable state correctly
- [ ] Tests clean up after themselves
- [ ] Tests use the MOK testing framework

### Documentation
- [ ] Code has meaningful comments explaining WHY
- [ ] Functions have documentation headers
- [ ] Complex logic is explained
- [ ] README/docs are updated if behavior changed

### Security
- [ ] No hardcoded secrets or credentials
- [ ] User input is validated and escaped
- [ ] File operations use safe defaults
- [ ] Temporary files use secure creation (mktemp)
- [ ] Permissions are appropriate and validated

### Performance
- [ ] No unnecessary subshells or command substitutions
- [ ] Loops don't repeat expensive operations
- [ ] Large files are processed efficiently
- [ ] Logging doesn't impact performance

---

## Examples - Complete Function

Here's a complete example following all guidelines:

```bash
# Function: backup_module_file
# Purpose: Create atomic backup of kernel module with verification
# Parameters:
#   $1 - Source module file path (absolute)
#   $2 - Backup directory path (must exist and be writable)
#   $3 - Optional: backup name suffix (defaults to timestamp)
# Returns:
#   0 - Backup created successfully (path echoed)
#   1 - Source file not found or not readable
#   2 - Backup directory doesn't exist or not writable
#   3 - Backup creation failed
# Dependencies: mktemp, cp, chmod
# Example:
#   backup_path=$(backup_module_file "/path/to/module.ko" "/var/backups")
#   if [[ $? -ne 0 ]]; then
#       log_error "Failed to backup module"
#       return 1
#   fi
backup_module_file() {
    local source_file="${1:?Source file required}"
    local backup_dir="${2:?Backup directory required}"
    local backup_suffix="${3:-$(date +%Y%m%d-%H%M%S)}"

    # Validate source file
    if [[ ! -f "${source_file}" ]]; then
        log_error "Source file not found: ${source_file}"
        return 1
    fi

    if [[ ! -r "${source_file}" ]]; then
        log_error "Source file not readable: ${source_file}"
        return 1
    fi

    # Validate backup directory
    if [[ ! -d "${backup_dir}" ]]; then
        log_error "Backup directory does not exist: ${backup_dir}"
        return 2
    fi

    if [[ ! -w "${backup_dir}" ]]; then
        log_error "Backup directory not writable: ${backup_dir}"
        return 2
    fi

    # Create backup with secure temporary file
    local module_basename
    module_basename=$(basename "${source_file}") || return 3

    local backup_file="${backup_dir}/${module_basename}.${backup_suffix}"
    local temp_backup
    temp_backup=$(mktemp "${backup_file}.tmp.XXXXXX") || {
        log_error "Failed to create temporary file"
        return 3
    }

    # Atomic backup
    if ! cp "${source_file}" "${temp_backup}"; then
        log_error "Failed to copy file to backup location"
        rm -f "${temp_backup}"
        return 3
    fi

    # Move to final location (atomic on same filesystem)
    if ! mv "${temp_backup}" "${backup_file}"; then
        log_error "Failed to finalize backup"
        rm -f "${temp_backup}"
        return 3
    fi

    # Set appropriate permissions
    chmod 600 "${backup_file}" || {
        log_warning "Failed to secure backup file permissions"
    }

    # Verify backup integrity
    if ! cmp -s "${source_file}" "${backup_file}"; then
        log_error "Backup verification failed"
        rm -f "${backup_file}"
        return 3
    fi

    # Success - echo the backup path for caller to capture
    echo "${backup_file}"
    log_debug "Backup created: ${backup_file}"
    return 0
}
```

---

## Summary

Clean code in bash means:
1. **Clarity** - Easy to read and understand
2. **Safety** - Proper error handling and validation
3. **Maintainability** - Well-documented and testable
4. **Security** - No hardcoded secrets, secure defaults
5. **Simplicity** - Not overly clever, straightforward logic

Following these guidelines ensures MOK remains a high-quality, maintainable project.

---

**End of Clean Code Guidelines**
