#!/bin/bash

################################################################################
# MOK - Common Functions Library
# Shared utilities for all MOK scripts
# Provides consistent logging, error handling, and utility functions
################################################################################

# Prevent multiple sourcing
if [[ "${MOK_COMMON_SOURCED:-0}" == "1" ]]; then
    return 0
fi
readonly MOK_COMMON_SOURCED="1"

################################################################################
# Color Codes (ANSI escape sequences)
################################################################################

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

# Function: log
# Purpose: Central logging function with timestamp and level
# Parameters:
#   $1 - Log level (INFO, WARNING, ERROR, SUCCESS, DEBUG)
#   $@ - Message to log
# Returns: 0 (always succeeds)
# Output: Writes to LOG_FILE and syslog if available
# Usage: log "INFO" "This is an info message"
# Notes: Automatically timestamps all messages and sends to multiple destinations
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Write to log file if it exists
    if [[ -n "${LOG_FILE:-}" ]] && [[ -w "$(dirname "${LOG_FILE}")" ]]; then
        echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    fi

    # Also write to syslog if available
    if command -v logger &>/dev/null; then
        logger -t "nvidia-signing" -p "user.${level,,}" "${message}" 2>/dev/null || true
    fi
}

# Function: log_info
# Purpose: Log informational message with blue color
# Parameters: $@ - Message to log
# Returns: 0
# Usage: log_info "Operation started"
log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log "INFO" "$@"
}

# Function: log_success
# Purpose: Log success message with green color and checkmark
# Parameters: $@ - Message to log
# Returns: 0
# Usage: log_success "Operation completed successfully"
log_success() {
    echo -e "${GREEN}[✓]${NC} $@"
    log "SUCCESS" "$@"
}

# Function: log_warning
# Purpose: Log warning message with yellow color
# Parameters: $@ - Message to log
# Returns: 0
# Usage: log_warning "This operation may have side effects"
log_warning() {
    echo -e "${YELLOW}[!]${NC} $@"
    log "WARNING" "$@"
}

# Function: log_error
# Purpose: Log error message with red color to stderr
# Parameters: $@ - Message to log
# Returns: 0
# Usage: log_error "An error occurred"
# Notes: Sends to stderr in addition to log file and syslog
log_error() {
    echo -e "${RED}[✗]${NC} $@" >&2
    log "ERROR" "$@"
}

# Function: log_debug
# Purpose: Log debug message (only if DEBUG=1 environment variable set)
# Parameters: $@ - Message to log
# Returns: 0
# Usage: log_debug "Detailed debug information"
# Notes: Only output when DEBUG environment variable is set to 1
log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $@"
        log "DEBUG" "$@"
    fi
}

################################################################################
# System Check Functions
################################################################################

# Function: check_root
# Purpose: Verify if script is running with root/sudo privileges
# Parameters: None
# Returns: 0 if running as root, 1 if not root
# Usage: check_root && echo "Running as root" || echo "Not root"
# Notes: Checks EUID variable; 0 means root privilege
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges"
        log_info "Try: sudo ${SCRIPT_NAME}"
        return 1
    fi
    return 0
}

# Function: command_exists
# Purpose: Check if a command exists and is executable in PATH
# Parameters:
#   $1 - Command name to check
# Returns: 0 if command exists and is executable, 1 if not found
# Usage: command_exists "curl" && echo "curl is installed"
# Notes: Uses 'command -v' for portability; redirects output to /dev/null
command_exists() {
    command -v "$1" &>/dev/null
    return $?
}

# Function: file_readable
# Purpose: Verify file exists and is readable by current user
# Parameters:
#   $1 - File path to check
# Returns: 0 if file exists and readable, 1 if not
# Usage: file_readable "/etc/config.conf" && source /etc/config.conf
# Notes: Checks both file existence and read permission
file_readable() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
        log_error "File not found: ${file}"
        return 1
    fi
    if [[ ! -r "${file}" ]]; then
        log_error "File not readable: ${file}"
        return 1
    fi
    return 0
}

# Function: dir_accessible
# Purpose: Verify directory exists and is accessible by current user
# Parameters:
#   $1 - Directory path to check
# Returns: 0 if directory exists and accessible, 1 if not
# Usage: dir_accessible "/var/log" && ls /var/log
# Notes: Checks both directory existence and execute permission (for traversal)
dir_accessible() {
    local dir="$1"
    if [[ ! -d "${dir}" ]]; then
        log_error "Directory not found: ${dir}"
        return 1
    fi
    if [[ ! -x "${dir}" ]]; then
        log_error "Directory not accessible: ${dir}"
        return 1
    fi
    return 0
}

################################################################################
# File and Directory Management
################################################################################

# Function: safe_mkdir
# Purpose: Create directory with specified permissions, handling existing dirs safely
# Parameters:
#   $1 - Directory path to create
#   $2 - (Optional) Permission mode (default: 700)
# Returns: 0 on success, 1 on failure
# Usage: safe_mkdir "/var/lib/myapp" "755"
# Notes: Creates parent directories as needed; does not error if dir exists
safe_mkdir() {
    local dir="$1"
    local perms="${2:-700}"

    if [[ ! -d "${dir}" ]]; then
        if ! mkdir -p "${dir}"; then
            log_error "Failed to create directory: ${dir}"
            return 1
        fi
    fi

    if ! chmod "${perms}" "${dir}"; then
        log_error "Failed to set permissions on directory: ${dir}"
        return 1
    fi

    return 0
}

# Function: backup_file
# Purpose: Create timestamped backup copy of file before modification
# Parameters:
#   $1 - File to backup
#   $2 - (Optional) Backup directory (default: same as source file)
# Returns: 0 on success, 1 on failure; outputs backup file path to stdout
# Usage: backup_path=$(backup_file "/etc/app.conf")
# Notes: Creates .backup.YYYYMMDD-HHMMSS suffix; preserves file permissions
backup_file() {
    local file="$1"
    local backup_dir="${2:-$(dirname "$file")}"

    if [[ ! -f "${file}" ]]; then
        log_warning "File does not exist for backup: ${file}"
        return 1
    fi

    local backup_file="${backup_dir}/$(basename "$file").backup.$(date +%Y%m%d-%H%M%S)"

    if ! cp -p "${file}" "${backup_file}"; then
        log_error "Failed to backup file: ${file}"
        return 1
    fi

    log_debug "Backup created: ${backup_file}"
    echo "${backup_file}"  # Return backup path
    return 0
}

# Function: safe_copy
# Purpose: Copy file with optional verification to ensure successful copy
# Parameters:
#   $1 - Source file path
#   $2 - Destination file path
#   $3 - (Optional) Verify copy (true/false, default: true)
# Returns: 0 on success, 1 on failure
# Usage: safe_copy "/home/user/.ssh/id_rsa" "/root/.ssh/id_rsa" "true"
# Notes: Preserves source file permissions; verifies using cmp if requested
safe_copy() {
    local src="$1"
    local dst="$2"
    local verify="${3:-true}"

    if [[ ! -e "${src}" ]]; then
        log_error "Source file does not exist: ${src}"
        return 1
    fi

    if ! cp -p "${src}" "${dst}"; then
        log_error "Failed to copy file: ${src} -> ${dst}"
        return 1
    fi

    # Verify copy if requested
    if [[ "${verify}" == "true" ]]; then
        if ! cmp -s "${src}" "${dst}"; then
            log_error "Copy verification failed: ${src} != ${dst}"
            rm -f "${dst}"
            return 1
        fi
    fi

    log_debug "File copied successfully: ${src} -> ${dst}"
    return 0
}

################################################################################
# Lock Management
################################################################################

# Global lock variables (can be overridden per script)
LOCK_FILE="${LOCK_FILE:-/var/run/nvidia-signing.lock}"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-30}"

# Function: acquire_lock
# Purpose: Acquire exclusive lock with timeout, preventing parallel execution
# Parameters: None (uses global LOCK_FILE and LOCK_TIMEOUT)
# Returns: 0 if lock acquired, 1 if timeout expires
# Usage: acquire_lock || exit 1; cleanup_code; release_lock
# Notes: Registers trap handler for automatic cleanup on EXIT/INT/TERM
acquire_lock() {
    local elapsed=0

    while [[ -f "${LOCK_FILE}" ]]; do
        if [[ $elapsed -ge $LOCK_TIMEOUT ]]; then
            log_error "Failed to acquire lock after ${LOCK_TIMEOUT}s"
            return 1
        fi
        log_warning "Waiting for lock... (${elapsed}s/${LOCK_TIMEOUT}s)"
        sleep 1
        ((elapsed++))
    done

    echo $$ > "${LOCK_FILE}" || {
        log_error "Failed to create lock file: ${LOCK_FILE}"
        return 1
    }

    # Register cleanup handler
    trap 'release_lock' EXIT INT TERM
    log_debug "Lock acquired (PID: $$)"
    return 0
}

# Function: release_lock
# Purpose: Release exclusive lock by removing lock file
# Parameters: None (uses global LOCK_FILE)
# Returns: 0 (always succeeds)
# Usage: release_lock  (usually called via trap)
# Notes: Safe to call multiple times; idempotent
release_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        rm -f "${LOCK_FILE}" || log_warning "Failed to remove lock file: ${LOCK_FILE}"
        log_debug "Lock released"
    fi
}

################################################################################
# State Management
################################################################################

# Function: save_json_state
# Purpose: Save execution state to JSON file with proper escaping and permissions
# Parameters:
#   $1 - State file path
#   $2+ - Key-value pairs (alternating: key1 value1 key2 value2 ...)
# Returns: 0 on success, 1 on failure
# Usage: save_json_state "/var/lib/app/state.json" "status" "running" "count" "42"
# Notes: Creates file with 600 permissions; escapes backslashes and quotes
save_json_state() {
    local state_file="$1"
    shift

    # Build JSON object from key=value arguments
    local json="{\n"
    local first=true

    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        shift 2

        if [[ "${first}" != "true" ]]; then
            json="${json},\n"
        fi
        first=false

        # Safely escape JSON values
        value="${value//\\/\\\\}"  # Escape backslashes
        value="${value//\"/\\\"}"  # Escape quotes
        json="${json}  \"${key}\": \"${value}\""
    done

    json="${json}\n}"

    if ! echo -e "${json}" > "${state_file}"; then
        log_error "Failed to save state to: ${state_file}"
        return 1
    fi

    chmod 600 "${state_file}"
    log_debug "State saved to: ${state_file}"
    return 0
}

# Function: load_json_state
# Purpose: Load and display JSON state file for inspection or parsing
# Parameters:
#   $1 - State file path
# Returns: 0 on success, 1 if file not found or unreadable
# Usage: state_content=$(load_json_state "/var/lib/app/state.json")
# Notes: Outputs JSON content to stdout for use with jq or similar tools
load_json_state() {
    local state_file="$1"

    if [[ ! -f "${state_file}" ]]; then
        log_debug "State file not found: ${state_file}"
        return 1
    fi

    if ! cat "${state_file}" 2>/dev/null; then
        log_warning "Failed to read state file: ${state_file}"
        return 1
    fi

    return 0
}

################################################################################
# Error Handling Utilities
################################################################################

# Function: die
# Purpose: Log error message and exit script immediately
# Parameters:
#   $1 - Error message
#   $2 - (Optional) Exit code (default: 1)
# Returns: Does not return (calls exit)
# Usage: die "Fatal error occurred" 2
# Notes: Logs error before exiting; always terminates script
die() {
    local message="${1:-Unknown error}"
    local exit_code="${2:-1}"

    log_error "${message}"
    exit "${exit_code}"
}

# Function: execute
# Purpose: Execute command with error logging and checking
# Parameters:
#   $1 - Description of operation
#   $2+ - Command and arguments to execute
# Returns: 0 if command succeeds, 1 if command fails
# Usage: execute "Copying files" cp /src /dst
# Notes: Logs execution with debug level; logs failures with error level
execute() {
    local description="$1"
    shift

    log_debug "Executing: $@"

    if ! "$@"; then
        log_error "${description} failed (exit code: $?)"
        return 1
    fi

    log_debug "${description} completed successfully"
    return 0
}

# Function: execute_with_timeout
# Purpose: Execute command with configurable timeout protection
# Parameters:
#   $1 - Timeout in seconds
#   $2 - Description of operation
#   $3+ - Command and arguments to execute
# Returns: 0 if command succeeds before timeout, 1 if timeout or failure
# Usage: execute_with_timeout 30 "Long operation" long_running_command
# Notes: Uses timeout command if available; graceful fallback if not present
execute_with_timeout() {
    local timeout="$1"
    local description="$2"
    shift 2

    log_debug "Executing with ${timeout}s timeout: $@"

    # Use timeout command if available, otherwise run directly
    if command -v timeout &>/dev/null; then
        if ! timeout "${timeout}" "$@"; then
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                log_error "${description} timed out after ${timeout}s"
            else
                log_error "${description} failed (exit code: ${exit_code})"
            fi
            return 1
        fi
    else
        if ! "$@"; then
            log_error "${description} failed (exit code: $?)"
            return 1
        fi
    fi

    log_debug "${description} completed successfully"
    return 0
}

################################################################################
# String Utilities
################################################################################

# Function: string_matches
# Purpose: Check if string matches regular expression pattern
# Parameters:
#   $1 - String to check
#   $2 - Regular expression pattern
# Returns: 0 if matches, 1 if no match
# Usage: string_matches "hello123" "[0-9]+" && echo "Has digits"
# Notes: Uses bash [[ ]] regex matching; patterns follow extended regex syntax
string_matches() {
    local string="$1"
    local pattern="$2"

    [[ "${string}" =~ ${pattern} ]]
}

# Function: string_trim
# Purpose: Remove leading and trailing whitespace from string
# Parameters:
#   $1 - String to trim
# Returns: 0 (always succeeds); outputs trimmed string to stdout
# Usage: trimmed=$(string_trim "  hello world  ")
# Notes: Removes spaces, tabs, newlines; uses character class matching
string_trim() {
    local string="$1"
    string="${string#"${string%%[![:space:]]*}"}"  # Remove leading whitespace
    string="${string%"${string##*[![:space:]]}"}"  # Remove trailing whitespace
    echo "${string}"
}

# Function: string_lower
# Purpose: Convert string to all lowercase characters
# Parameters:
#   $1 - String to convert
# Returns: 0 (always succeeds); outputs lowercase string to stdout
# Usage: lower=$(string_lower "HELLO World")  # Outputs: hello world
# Notes: Uses tr command for character translation
string_lower() {
    tr '[:upper:]' '[:lower:]' <<< "$1"
}

# Function: string_upper
# Purpose: Convert string to all uppercase characters
# Parameters:
#   $1 - String to convert
# Returns: 0 (always succeeds); outputs uppercase string to stdout
# Usage: upper=$(string_upper "hello WORLD")  # Outputs: HELLO WORLD
# Notes: Uses tr command for character translation
string_upper() {
    tr '[:lower:]' '[:upper:]' <<< "$1"
}

################################################################################
# Array Utilities
################################################################################

# Function: array_contains
# Purpose: Check if array contains specified element
# Parameters:
#   $1 - Element to search for
#   $2+ - Array elements to search within
# Returns: 0 if element found, 1 if not found
# Usage: array_contains "needle" "${array[@]}" && echo "Found"
# Notes: Compares elements as complete strings; case-sensitive
array_contains() {
    local needle="$1"
    shift
    local element

    for element in "$@"; do
        [[ "${element}" == "${needle}" ]] && return 0
    done

    return 1
}

# Function: array_join
# Purpose: Join array elements into single string with delimiter
# Parameters:
#   $1 - Delimiter string
#   $2+ - Elements to join
# Returns: 0 (always succeeds); outputs joined string to stdout
# Usage: result=$(array_join "," "a" "b" "c")  # Outputs: a,b,c
# Notes: No trailing delimiter; elements printed without newlines
array_join() {
    local delimiter="$1"
    shift
    local first=true

    for element in "$@"; do
        if [[ "${first}" != "true" ]]; then
            echo -n "${delimiter}"
        fi
        first=false
        echo -n "${element}"
    done
}

################################################################################
# Validation Utilities
################################################################################

# Function: is_integer
# Purpose: Check if string represents valid non-negative integer
# Parameters:
#   $1 - Value to validate
# Returns: 0 if valid integer, 1 if not integer
# Usage: is_integer "42" && echo "Valid integer"
# Notes: Accepts only digits 0-9; rejects negative numbers and decimals
is_integer() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]]
}

# Function: is_valid_percentage
# Purpose: Check if value is valid percentage (integer between 0-100)
# Parameters:
#   $1 - Value to validate
# Returns: 0 if valid percentage, 1 if not
# Usage: is_valid_percentage "75" && echo "Valid percentage"
# Notes: First checks if integer, then validates range 0-100
is_valid_percentage() {
    local value="$1"

    if ! is_integer "${value}"; then
        return 1
    fi

    [[ ${value} -ge 0 && ${value} -le 100 ]]
}

# Function: is_valid_email
# Purpose: Check if string matches basic email address pattern
# Parameters:
#   $1 - Email address to validate
# Returns: 0 if matches pattern, 1 if not
# Usage: is_valid_email "user@example.com" && echo "Valid email"
# Notes: Uses regex pattern; not comprehensive RFC validation
is_valid_email() {
    local email="$1"
    [[ "${email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

################################################################################
# System Information
################################################################################

# Function: get_kernel_version
# Purpose: Get current kernel version string
# Parameters: None
# Returns: 0 (always succeeds); outputs kernel version to stdout
# Usage: kernel=$(get_kernel_version)  # Example: 5.10.0-13-generic
# Notes: Uses uname -r; format varies by Linux distribution
get_kernel_version() {
    uname -r
}

# Function: get_uptime
# Purpose: Get system uptime in seconds since last boot
# Parameters: None
# Returns: 0 (always succeeds); outputs uptime in seconds to stdout
# Usage: uptime_secs=$(get_uptime); echo "Uptime: $uptime_secs seconds"
# Notes: Reads /proc/uptime; rounds down to whole seconds
get_uptime() {
    awk '{print $1}' /proc/uptime | cut -d. -f1
}

# Function: get_available_memory
# Purpose: Get available system memory in megabytes
# Parameters: None
# Returns: 0 (always succeeds); outputs memory in MB to stdout
# Usage: available_mb=$(get_available_memory); echo "Available: ${available_mb}MB"
# Notes: Reads MemAvailable from /proc/meminfo; converts from KB to MB
get_available_memory() {
    awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo
}

# Function: get_cpu_count
# Purpose: Get number of logical CPU cores available
# Parameters: None
# Returns: 0 (always succeeds); outputs CPU count to stdout
# Usage: cpus=$(get_cpu_count); echo "CPUs: $cpus"
# Notes: Uses nproc if available, falls back to /proc/cpuinfo parsing
get_cpu_count() {
    nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo
}

################################################################################
# Print Formatting
################################################################################

# Function: print_banner
# Purpose: Print decorative banner with title and optional custom width
# Parameters:
#   $1 - Title text to display in banner
#   $2 - (Optional) Banner width in characters (default: 60)
# Returns: 0 (always succeeds)
# Usage: print_banner "MOK System Initialization"
# Notes: Uses box drawing characters (╔═╗║╚); outputs in magenta color
print_banner() {
    local title="$1"
    local width="${2:-60}"

    echo -e "${MAGENTA}"
    echo "╔$(printf '═%.0s' $(seq 1 $((width-2))))╗"
    printf "║ %-$((width-3))s║\n" "${title}"
    echo "╚$(printf '═%.0s' $(seq 1 $((width-2))))╝"
    echo -e "${NC}"
}

# Function: print_section
# Purpose: Print section header with title and underline
# Parameters:
#   $1 - Section title to display
# Returns: 0 (always succeeds)
# Usage: print_section "Configuration Files"
# Notes: Adds blank lines before and after; uses cyan color with arrow
print_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}▶ ${title}${NC}"
    echo -e "${CYAN}$(printf '─%.0s' $(seq 1 $((${#title}+2))))${NC}"
    echo ""
}

# Function: print_separator
# Purpose: Print horizontal line separator for output formatting
# Parameters: None
# Returns: 0 (always succeeds)
# Usage: print_separator  (outputs dashed line)
# Notes: Fixed width 54 characters; colored blue for visual clarity
print_separator() {
    echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
}

################################################################################
# Reporting Utilities
################################################################################

# Function: print_summary
# Purpose: Print formatted label-value pair for status/summary output
# Parameters:
#   $1 - Label text (left side)
#   $2 - Value text (right side)
#   $3 - (Optional) Color code (default: BLUE)
# Returns: 0 (always succeeds)
# Usage: print_summary "Status" "Running" "${GREEN}"
# Notes: Label left-padded to 30 chars; uses color codes for styling
print_summary() {
    local label="$1"
    local value="$2"
    local color="${3:-${BLUE}}"

    printf "  ${color}%-30s${NC}: %s\n" "${label}" "${value}"
}

# Function: print_result
# Purpose: Print test/operation result with checkmark or error symbol
# Parameters:
#   $1 - Result message
#   $2 - (Optional) Success flag: "true" or "false" (default: true)
# Returns: 0 (always succeeds)
# Usage: print_result "Configuration loaded" "true"
# Notes: Green [✓] for success, Red [✗] for failure
print_result() {
    local message="$1"
    local success="${2:-true}"

    if [[ "${success}" == "true" ]]; then
        echo -e "  ${GREEN}[✓]${NC} ${message}"
    else
        echo -e "  ${RED}[✗]${NC} ${message}"
    fi
}

################################################################################
# Module Utilities (NVIDIA-specific)
################################################################################

# Function: nvidia_module_exists
# Purpose: Check if NVIDIA kernel module is loaded on system
# Parameters:
#   $1 - Module name (e.g., "nvidia", "nvidia_uvm")
# Returns: 0 if module exists, 1 if not found
# Usage: nvidia_module_exists "nvidia" && echo "NVIDIA driver loaded"
# Notes: Checks /sys/module for tainted or version file
nvidia_module_exists() {
    local module_name="$1"
    [[ -f "/sys/module/${module_name}/tainted" ]] || [[ -f "/sys/module/${module_name}/version" ]]
}

# Function: get_nvidia_module_tainted
# Purpose: Get tainted status of NVIDIA kernel module
# Parameters:
#   $1 - Module name to check
# Returns: 0 (always succeeds); outputs tainted status to stdout
# Usage: status=$(get_nvidia_module_tainted "nvidia")
# Notes: Output indicates kernel module integrity; values: Y/N or numeric flags
get_nvidia_module_tainted() {
    local module_name="$1"

    if [[ -f "/sys/module/${module_name}/tainted" ]]; then
        cat "/sys/module/${module_name}/tainted"
    fi
}

################################################################################
# Return with success
return 0
