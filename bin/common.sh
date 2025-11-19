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

# Central log function with timestamp and level
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

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $@"
    log "SUCCESS" "$@"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $@"
    log "WARNING" "$@"
}

log_error() {
    echo -e "${RED}[✗]${NC} $@" >&2
    log "ERROR" "$@"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $@"
        log "DEBUG" "$@"
    fi
}

################################################################################
# System Check Functions
################################################################################

# Check if running as root (requires root)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges"
        log_info "Try: sudo ${SCRIPT_NAME}"
        return 1
    fi
    return 0
}

# Check if a command exists and is executable
command_exists() {
    command -v "$1" &>/dev/null
    return $?
}

# Check if file exists and is readable
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

# Check if directory exists and is accessible
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

# Create directory with proper permissions
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

# Safe file backup before modification
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

# Safe file copy with verification
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

# Acquire exclusive lock
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

# Release lock
release_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        rm -f "${LOCK_FILE}" || log_warning "Failed to remove lock file: ${LOCK_FILE}"
        log_debug "Lock released"
    fi
}

################################################################################
# State Management
################################################################################

# Save execution state to JSON file
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

# Load and display JSON state file
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

# Exit with error message and code
die() {
    local message="${1:-Unknown error}"
    local exit_code="${2:-1}"

    log_error "${message}"
    exit "${exit_code}"
}

# Execute command with error handling
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

# Execute with timeout
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

# Check if string matches pattern
string_matches() {
    local string="$1"
    local pattern="$2"

    [[ "${string}" =~ ${pattern} ]]
}

# Trim leading and trailing whitespace
string_trim() {
    local string="$1"
    string="${string#"${string%%[![:space:]]*}"}"  # Remove leading whitespace
    string="${string%"${string##*[![:space:]]}"}"  # Remove trailing whitespace
    echo "${string}"
}

# Convert string to lowercase
string_lower() {
    tr '[:upper:]' '[:lower:]' <<< "$1"
}

# Convert string to uppercase
string_upper() {
    tr '[:lower:]' '[:upper:]' <<< "$1"
}

################################################################################
# Array Utilities
################################################################################

# Check if array contains element
array_contains() {
    local needle="$1"
    shift
    local element

    for element in "$@"; do
        [[ "${element}" == "${needle}" ]] && return 0
    done

    return 1
}

# Join array elements with delimiter
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

# Validate is valid integer
is_integer() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]]
}

# Validate is valid percentage (0-100)
is_valid_percentage() {
    local value="$1"

    if ! is_integer "${value}"; then
        return 1
    fi

    [[ ${value} -ge 0 && ${value} -le 100 ]]
}

# Validate is valid email
is_valid_email() {
    local email="$1"
    [[ "${email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

################################################################################
# System Information
################################################################################

# Get kernel version
get_kernel_version() {
    uname -r
}

# Get system uptime in seconds
get_uptime() {
    awk '{print $1}' /proc/uptime | cut -d. -f1
}

# Get available memory in MB
get_available_memory() {
    awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo
}

# Get CPU count
get_cpu_count() {
    nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo
}

################################################################################
# Print Formatting
################################################################################

# Print banner with title
print_banner() {
    local title="$1"
    local width="${2:-60}"

    echo -e "${MAGENTA}"
    echo "╔$(printf '═%.0s' $(seq 1 $((width-2))))╗"
    printf "║ %-$((width-3))s║\n" "${title}"
    echo "╚$(printf '═%.0s' $(seq 1 $((width-2))))╝"
    echo -e "${NC}"
}

# Print section header
print_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}▶ ${title}${NC}"
    echo -e "${CYAN}$(printf '─%.0s' $(seq 1 $((${#title}+2))))${NC}"
    echo ""
}

# Print simple separator
print_separator() {
    echo -e "${BLUE}─────────────────────────────────────────────────────${NC}"
}

################################################################################
# Reporting Utilities
################################################################################

# Print summary statistics
print_summary() {
    local label="$1"
    local value="$2"
    local color="${3:-${BLUE}}"

    printf "  ${color}%-30s${NC}: %s\n" "${label}" "${value}"
}

# Print result with checkmark or cross
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

# Check if NVIDIA module exists
nvidia_module_exists() {
    local module_name="$1"
    [[ -f "/sys/module/${module_name}/tainted" ]] || [[ -f "/sys/module/${module_name}/version" ]]
}

# Get NVIDIA module tainted status
get_nvidia_module_tainted() {
    local module_name="$1"

    if [[ -f "/sys/module/${module_name}/tainted" ]]; then
        cat "/sys/module/${module_name}/tainted"
    fi
}

################################################################################
# Return with success
return 0
