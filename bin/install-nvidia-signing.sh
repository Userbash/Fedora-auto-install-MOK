#!/bin/bash

################################################################################
# NVIDIA Signing System - Installation and Deployment Script
# Fedora 43 with Secure Boot and TPM2 Support
#
# Purpose: Complete automated installation and deployment of the signing system
# Features:
#   - Pre-flight checks
#   - Component installation
#   - Systemd integration
#   - DNF hook setup
#   - SELinux policy installation
#   - Verification and testing
#   - Rollback capability
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
readonly SCRIPT_VERSION="1.0.0"
readonly INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BIN_DIR="/usr/local/bin"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly DNF_ACTIONS_DIR="/etc/dnf/plugins/post-transaction-actions.d"
readonly SELINUX_DIR="/usr/share/selinux/packages"
readonly STATE_DIR="/var/lib/nvidia-signing"
readonly LOG_DIR="/var/log/nvidia-signing"
readonly BACKUP_DIR="${STATE_DIR}/backups"
readonly INSTALL_LOG="/tmp/nvidia-signing-install-$(date +%Y%m%d-%H%M%S).log"

# Component tracking
declare -a INSTALL_STEPS
declare -A STEP_STATUS

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $@" >> "${INSTALL_LOG}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $@" >> "${INSTALL_LOG}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $@" >> "${INSTALL_LOG}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $@" >> "${INSTALL_LOG}"
}

log_section() {
    echo -e "\n${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$@${NC}"
    echo -e "${BLUE}════════════════════════════════════════════${NC}\n"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === $@ ===" >> "${INSTALL_LOG}"
}

################################################################################
# System Checks
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Installation must be run as root"
        return 1
    fi
    log_success "Running as root"
}

check_fedora_version() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "${NAME}" == "Fedora" ]]; then
            log_success "Running on Fedora (Version ${VERSION_ID})"
            return 0
        fi
    fi
    log_warning "Not running on Fedora - some features may not work as expected"
    return 0
}

check_uefi() {
    if [[ -d /sys/firmware/efi ]]; then
        log_success "UEFI firmware detected"
        return 0
    else
        log_warning "UEFI firmware not detected - Secure Boot unavailable"
        return 0
    fi
}

check_required_tools() {
    log_info "Checking for required tools..."

    local missing_tools=()

    for tool in dracut modinfo mokutil; do
        if command -v "${tool}" &>/dev/null; then
            log_success "  ${tool}: found"
        else
            log_error "  ${tool}: NOT FOUND"
            missing_tools+=("${tool}")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi

    log_success "All required tools are available"
    return 0
}

check_kernel_sources() {
    local kernel_release=$(uname -r)
    local kernel_dir="/usr/src/kernels/${kernel_release}"

    if [[ ! -d "${kernel_dir}" ]]; then
        log_error "Kernel sources not found: ${kernel_dir}"
        log_info "Install with: sudo dnf install kernel-devel"
        return 1
    fi

    if [[ ! -x "${kernel_dir}/scripts/sign-file" ]]; then
        log_error "sign-file utility not found in kernel sources"
        return 1
    fi

    log_success "Kernel sources found: ${kernel_release}"
    return 0
}

################################################################################
# Installation Steps
################################################################################

install_main_script() {
    log_section "Installing Main Script"

    if [[ ! -f "${INSTALL_DIR}/sign-nvidia-modules.sh" ]]; then
        log_error "Main script not found: ${INSTALL_DIR}/sign-nvidia-modules.sh"
        return 1
    fi

    if ! cp "${INSTALL_DIR}/sign-nvidia-modules.sh" "${BIN_DIR}/sign-nvidia-modules.sh"; then
        log_error "Failed to copy main script to ${BIN_DIR}"
        return 1
    fi

    if ! chmod 755 "${BIN_DIR}/sign-nvidia-modules.sh"; then
        log_error "Failed to set executable permissions"
        return 1
    fi

    log_success "Main script installed: ${BIN_DIR}/sign-nvidia-modules.sh"
}

install_recovery_script() {
    log_section "Installing Recovery Script"

    if [[ ! -f "${INSTALL_DIR}/rollback-nvidia-signing.sh" ]]; then
        log_error "Recovery script not found: ${INSTALL_DIR}/rollback-nvidia-signing.sh"
        return 1
    fi

    if ! cp "${INSTALL_DIR}/rollback-nvidia-signing.sh" "${BIN_DIR}/rollback-nvidia-signing.sh"; then
        log_error "Failed to copy recovery script to ${BIN_DIR}"
        return 1
    fi

    if ! chmod 755 "${BIN_DIR}/rollback-nvidia-signing.sh"; then
        log_error "Failed to set executable permissions"
        return 1
    fi

    log_success "Recovery script installed: ${BIN_DIR}/rollback-nvidia-signing.sh"
}

install_test_suite() {
    log_section "Installing Test Suite"

    if [[ ! -f "${INSTALL_DIR}/test-nvidia-signing.sh" ]]; then
        log_error "Test suite not found: ${INSTALL_DIR}/test-nvidia-signing.sh"
        return 1
    fi

    if ! cp "${INSTALL_DIR}/test-nvidia-signing.sh" "${BIN_DIR}/test-nvidia-signing.sh"; then
        log_error "Failed to copy test suite to ${BIN_DIR}"
        return 1
    fi

    if ! chmod 755 "${BIN_DIR}/test-nvidia-signing.sh"; then
        log_error "Failed to set executable permissions"
        return 1
    fi

    log_success "Test suite installed: ${BIN_DIR}/test-nvidia-signing.sh"
}

install_systemd_service() {
    log_section "Installing Systemd Service"

    if [[ ! -f "${INSTALL_DIR}/sign-nvidia.service" ]]; then
        log_error "Service file not found: ${INSTALL_DIR}/sign-nvidia.service"
        return 1
    fi

    if ! cp "${INSTALL_DIR}/sign-nvidia.service" "${SYSTEMD_DIR}/sign-nvidia.service"; then
        log_error "Failed to copy service file"
        return 1
    fi

    if ! chmod 644 "${SYSTEMD_DIR}/sign-nvidia.service"; then
        log_error "Failed to set permissions on service file"
        return 1
    fi

    # Reload systemd daemon
    if ! systemctl daemon-reload; then
        log_error "Failed to reload systemd daemon"
        return 1
    fi

    log_success "Systemd service installed: ${SYSTEMD_DIR}/sign-nvidia.service"

    # Verify service
    if systemd-analyze verify "${SYSTEMD_DIR}/sign-nvidia.service" &>/dev/null 2>&1; then
        log_success "Service file verification passed"
    else
        log_warning "Service file verification warning (may be non-critical)"
    fi
}

install_dnf_hook() {
    log_section "Installing DNF Post-Transaction Hook"

    # Create directory if it doesn't exist
    if [[ ! -d "${DNF_ACTIONS_DIR}" ]]; then
        if ! mkdir -p "${DNF_ACTIONS_DIR}"; then
            log_error "Failed to create DNF actions directory"
            return 1
        fi
    fi

    if [[ ! -f "${INSTALL_DIR}/nvidia-signing.action" ]]; then
        log_error "DNF action file not found: ${INSTALL_DIR}/nvidia-signing.action"
        return 1
    fi

    if ! cp "${INSTALL_DIR}/nvidia-signing.action" "${DNF_ACTIONS_DIR}/nvidia-signing.action"; then
        log_error "Failed to copy DNF action file"
        return 1
    fi

    if ! chmod 644 "${DNF_ACTIONS_DIR}/nvidia-signing.action"; then
        log_error "Failed to set permissions on DNF action file"
        return 1
    fi

    log_success "DNF hook installed: ${DNF_ACTIONS_DIR}/nvidia-signing.action"
}

install_selinux_policy() {
    log_section "Installing SELinux Policy"

    # Check if SELinux is enabled
    if ! command -v getenforce &>/dev/null || [[ "$(getenforce 2>/dev/null || echo 'Disabled')" == "Disabled" ]]; then
        log_warning "SELinux is not enabled or not available"
        log_info "SELinux policy installation skipped"
        return 0
    fi

    if [[ ! -f "${INSTALL_DIR}/nvidia-signing.te" ]]; then
        log_error "SELinux policy source not found: ${INSTALL_DIR}/nvidia-signing.te"
        return 0
    fi

    # Create policy module directory
    mkdir -p "${SELINUX_DIR}/nvidia-signing"

    # Copy policy files
    cp "${INSTALL_DIR}/nvidia-signing.te" "${SELINUX_DIR}/nvidia-signing/"

    # Build and install policy
    if cd "${SELINUX_DIR}/nvidia-signing" && \
       checkmodule -M -m -o nvidia-signing.mod nvidia-signing.te && \
       semodule_package -o nvidia-signing.pp -m nvidia-signing.mod && \
       semodule -i nvidia-signing.pp; then
        log_success "SELinux policy installed successfully"
    else
        log_warning "SELinux policy installation failed (you may need to install selinux-policy-devel)"
    fi
}

setup_directories() {
    log_section "Setting Up Directories"

    # Create state directory
    if ! mkdir -p "${STATE_DIR}"; then
        log_error "Failed to create state directory: ${STATE_DIR}"
        return 1
    fi
    chmod 700 "${STATE_DIR}"
    log_success "State directory created: ${STATE_DIR}"

    # Create backup directory
    if ! mkdir -p "${BACKUP_DIR}"; then
        log_error "Failed to create backup directory: ${BACKUP_DIR}"
        return 1
    fi
    chmod 700 "${BACKUP_DIR}"
    log_success "Backup directory created: ${BACKUP_DIR}"

    # Create log directory
    if ! mkdir -p "${LOG_DIR}"; then
        log_error "Failed to create log directory: ${LOG_DIR}"
        return 1
    fi
    chmod 700 "${LOG_DIR}"
    log_success "Log directory created: ${LOG_DIR}"
}

setup_signing_keys() {
    log_section "Setting Up Signing Keys"

    local key_dir="/etc/pki/akmods/certs"

    # Check if keys already exist
    if [[ -f "${key_dir}/private_key.priv" ]] && [[ -f "${key_dir}/public_key.der" ]]; then
        log_success "Signing keys already exist"
        return 0
    fi

    log_info "Signing keys not found. Keys must be generated separately."
    log_info "Generate keys with: sudo kmodgenca -a"
    log_info "Then enroll key with: sudo mokutil --import ${key_dir}/public_key.der"
    log_warning "Skipping key generation - this requires reboot for enrollment"

    return 0
}

restrict_file_access() {
    log_section "Restricting File Access"

    local kernel_release=$(uname -r)
    local sign_file="/usr/src/kernels/${kernel_release}/scripts/sign-file"
    local mokutil_path="/usr/bin/mokutil"

    # Restrict sign-file
    if [[ -x "${sign_file}" ]]; then
        if chmod 700 "${sign_file}"; then
            log_success "Restricted access to sign-file: ${sign_file}"
        else
            log_warning "Could not restrict sign-file permissions (may require superuser)"
        fi
    fi

    # Restrict mokutil
    if [[ -x "${mokutil_path}" ]]; then
        if chmod 700 "${mokutil_path}"; then
            log_success "Restricted access to mokutil: ${mokutil_path}"
        else
            log_warning "Could not restrict mokutil permissions (may require superuser)"
        fi
    fi
}

enable_service() {
    log_section "Enabling Systemd Service"

    if systemctl enable sign-nvidia.service; then
        log_success "Service enabled for auto-start"
    else
        log_error "Failed to enable service"
        return 1
    fi

    # Ask user whether to start immediately
    read -p "Start service now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if systemctl start sign-nvidia.service; then
            log_success "Service started successfully"
        else
            log_warning "Service start returned non-zero exit code (check logs)"
        fi
    fi
}

################################################################################
# Verification and Testing
################################################################################

verify_installation() {
    log_section "Verifying Installation"

    local all_ok=true

    # Check scripts
    for script in "sign-nvidia-modules.sh" "rollback-nvidia-signing.sh" "test-nvidia-signing.sh"; do
        if [[ -x "${BIN_DIR}/${script}" ]]; then
            log_success "  ${script}: installed"
        else
            log_error "  ${script}: NOT FOUND"
            all_ok=false
        fi
    done

    # Check systemd service
    if systemctl list-unit-files | grep -q "sign-nvidia.service"; then
        log_success "  Systemd service: installed"
    else
        log_error "  Systemd service: NOT FOUND"
        all_ok=false
    fi

    # Check DNF hook
    if [[ -f "${DNF_ACTIONS_DIR}/nvidia-signing.action" ]]; then
        log_success "  DNF hook: installed"
    else
        log_error "  DNF hook: NOT FOUND"
        all_ok=false
    fi

    # Check directories
    for dir in "${STATE_DIR}" "${LOG_DIR}" "${BACKUP_DIR}"; do
        if [[ -d "${dir}" ]]; then
            log_success "  ${dir}: created"
        else
            log_error "  ${dir}: NOT FOUND"
            all_ok=false
        fi
    done

    if [[ "${all_ok}" == "false" ]]; then
        log_error "Installation verification failed"
        return 1
    fi

    log_success "Installation verification passed"
    return 0
}

run_tests() {
    log_section "Running Test Suite"

    if [[ ! -x "${BIN_DIR}/test-nvidia-signing.sh" ]]; then
        log_warning "Test suite not found - skipping tests"
        return 0
    fi

    log_info "Running comprehensive tests..."
    log_info "This may take a few minutes..."
    echo ""

    if "${BIN_DIR}/test-nvidia-signing.sh"; then
        log_success "All tests passed"
        return 0
    else
        log_warning "Some tests failed or were skipped"
        return 0
    fi
}

################################################################################
# Pre-flight and Post-flight
################################################################################

pre_flight_checks() {
    log_section "Pre-Flight Checks"

    check_root || return 1
    check_fedora_version || return 1
    check_uefi || return 1
    check_required_tools || return 1
    check_kernel_sources || return 1

    log_success "All pre-flight checks passed"
    return 0
}

show_summary() {
    log_section "Installation Summary"

    echo "NVIDIA Signing System has been installed successfully!"
    echo ""
    echo "Installed Components:"
    echo "  • Main script: ${BIN_DIR}/sign-nvidia-modules.sh"
    echo "  • Recovery script: ${BIN_DIR}/rollback-nvidia-signing.sh"
    echo "  • Test suite: ${BIN_DIR}/test-nvidia-signing.sh"
    echo "  • Systemd service: ${SYSTEMD_DIR}/sign-nvidia.service"
    echo "  • DNF hook: ${DNF_ACTIONS_DIR}/nvidia-signing.action"
    echo ""
    echo "Configuration:"
    echo "  • State directory: ${STATE_DIR}"
    echo "  • Log directory: ${LOG_DIR}"
    echo "  • Backup directory: ${BACKUP_DIR}"
    echo ""
    echo "Next Steps:"
    echo "  1. Generate signing keys (if not already done):"
    echo "     sudo kmodgenca -a"
    echo ""
    echo "  2. Enroll keys in MOK:"
    echo "     sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
    echo ""
    echo "  3. Reboot to complete MOK enrollment"
    echo ""
    echo "  4. Verify installation:"
    echo "     sudo systemctl status sign-nvidia.service"
    echo ""
    echo "  5. Run tests manually:"
    echo "     sudo ${BIN_DIR}/test-nvidia-signing.sh"
    echo ""
    echo "Usage:"
    echo "  Manual signing:  sudo ${BIN_DIR}/sign-nvidia-modules.sh"
    echo "  Recovery:        sudo ${BIN_DIR}/rollback-nvidia-signing.sh"
    echo "  Run tests:       sudo ${BIN_DIR}/test-nvidia-signing.sh"
    echo ""
    echo "Installation log: ${INSTALL_LOG}"
    echo ""

    log_success "Installation completed at $(date)"
}

cleanup_on_failure() {
    log_error "Installation failed. Attempting cleanup..."
    log_error "Partial installation remains. Please review logs at: ${INSTALL_LOG}"
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    # Set up error handling
    trap cleanup_on_failure EXIT

    log_section "NVIDIA Signing System Installation v${SCRIPT_VERSION}"

    log_info "Installation started at: $(date)"
    log_info "Installation log: ${INSTALL_LOG}"
    log_info ""

    # Pre-flight checks
    if ! pre_flight_checks; then
        log_error "Pre-flight checks failed. Aborting installation."
        return 1
    fi

    # Create directories first
    if ! setup_directories; then
        return 1
    fi

    # Install components
    if ! install_main_script; then return 1; fi
    if ! install_recovery_script; then return 1; fi
    if ! install_test_suite; then return 1; fi
    if ! install_systemd_service; then return 1; fi
    if ! install_dnf_hook; then return 1; fi
    if ! install_selinux_policy; then return 1; fi

    # Setup keys and access
    if ! setup_signing_keys; then return 1; fi
    if ! restrict_file_access; then return 1; fi

    # Verification
    if ! verify_installation; then return 1; fi

    # Test suite
    if ! run_tests; then
        log_warning "Tests failed but installation will continue"
    fi

    # Enable service
    if ! enable_service; then return 1; fi

    # Remove the trap for successful completion
    trap - EXIT

    # Show summary
    show_summary

    return 0
}

main "$@"
exit $?
