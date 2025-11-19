#!/bin/bash

################################################################################
# MOK GitHub Publication Preparation Script
# Cleans up directory, validates structure, and prepares for GitHub publication
#
# Features:
#   - Remove unnecessary files
#   - Validate file permissions
#   - Check for secrets/sensitive data
#   - Optimize directory structure
#   - Generate clean commit message
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="${SCRIPT_DIR}"
readonly BACKUP_DIR="${PROJECT_ROOT}/.github-prep-backup"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Counters
declare -gi FILES_REMOVED=0
declare -gi FILES_FIXED=0
declare -gi WARNINGS_FOUND=0
declare -gi ERRORS_FOUND=0

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
# FILE CLEANUP
# ============================================================================

# Remove unnecessary files
cleanup_files() {
    log_info "Cleaning up unnecessary files"

    # Files to remove
    local -a files_to_remove=(
        ".DS_Store"
        "*.swp"
        "*.swo"
        "*~"
        "*.tmp"
        ".vscode/settings.json"
        "*.bak"
        ".github-prep-backup"
    )

    for pattern in "${files_to_remove[@]}"; do
        while IFS= read -r file; do
            if [[ -e "${file}" ]]; then
                log_warning "Removing: ${file}"
                rm -rf "${file}"
                ((FILES_REMOVED++))
            fi
        done < <(find "${PROJECT_ROOT}" -type f -name "${pattern}" 2>/dev/null || true)
    done

    # Remove empty directories
    log_info "Removing empty directories"
    find "${PROJECT_ROOT}" -type d -empty -delete 2>/dev/null || true

    log_success "Cleanup complete (${FILES_REMOVED} items removed)"
}

# ============================================================================
# PERMISSIONS VALIDATION AND FIXING
# ============================================================================

# Fix file permissions
fix_permissions() {
    log_info "Validating and fixing file permissions"

    # Make scripts executable
    local -a scripts=(
        "mok"
        "bin/sign-nvidia-modules.sh"
        "bin/test-nvidia-signing.sh"
        "bin/install-nvidia-signing.sh"
        "bin/rollback-nvidia-signing.sh"
        "tests/framework.sh"
        "tests/test_variables.sh"
        "tests/test_paths.sh"
        "tests/run_all_tests.sh"
        "prepare_github.sh"
    )

    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        if [[ -f "${full_path}" ]]; then
            if [[ ! -x "${full_path}" ]]; then
                chmod +x "${full_path}"
                log_success "Made executable: ${script}"
                ((FILES_FIXED++))
            fi
        fi
    done

    # Fix documentation permissions (should be readable)
    local -a docs=(
        "README.md"
        "SECURITY.md"
        "STRUCTURE.md"
        "SYSTEMD_GUIDE.md"
        "CONTRIBUTING.md"
        "CHANGELOG.md"
    )

    for doc in "${docs[@]}"; do
        local full_path="${PROJECT_ROOT}/${doc}"
        if [[ -f "${full_path}" ]]; then
            chmod 644 "${full_path}"
        fi
    done

    # Fix directory permissions
    find "${PROJECT_ROOT}" -type d ! -path "./.git*" -exec chmod 755 {} \;

    log_success "Permissions fixed (${FILES_FIXED} items updated)"
}

# ============================================================================
# SECRETS AND SENSITIVE DATA DETECTION
# ============================================================================

# Scan for secrets
scan_for_secrets() {
    log_info "Scanning for secrets and sensitive data"

    local -a patterns=(
        "aws_access_key_id"
        "aws_secret_access_key"
        "private_key"
        "api_key"
        "password"
        "token"
        "secret"
    )

    local found=0
    for pattern in "${patterns[@]}"; do
        if grep -r -i "${pattern}" "${PROJECT_ROOT}" 2>/dev/null | grep -v "Binary file" | grep -v ".git/"; then
            log_warning "Potential secret found matching: ${pattern}"
            ((found++))
        fi
    done

    if [[ ${found} -gt 0 ]]; then
        log_error "Found ${found} potential secret(s) - please review and remove"
        ((WARNINGS_FOUND++))
        return 1
    else
        log_success "No obvious secrets detected"
        return 0
    fi
}

# Check for private keys
check_private_keys() {
    log_info "Checking for private keys"

    local found=0
    while IFS= read -r file; do
        if [[ -f "${file}" ]]; then
            log_error "Found private key file: ${file}"
            log_error "REMOVE THIS FILE BEFORE PUBLISHING"
            ((found++))
            ((ERRORS_FOUND++))
        fi
    done < <(find "${PROJECT_ROOT}" -type f \( -name "*.key" -o -name "*private*" -o -name "*.pem" \) 2>/dev/null || true)

    if [[ ${found} -eq 0 ]]; then
        log_success "No private key files found"
    fi
}

# ============================================================================
# .GITIGNORE VALIDATION
# ============================================================================

# Validate gitignore
validate_gitignore() {
    log_info "Validating .gitignore"

    local gitignore="${PROJECT_ROOT}/.gitignore"

    if [[ ! -f "${gitignore}" ]]; then
        log_warning ".gitignore not found, creating basic version"
        cat > "${gitignore}" << 'EOF'
# Build artifacts
*.o
*.a
*.so
*.out

# Temporary files
*.tmp
*.log
*.swp
*.swo
*~
.DS_Store

# IDE configuration
.vscode/settings.json
.idea/
*.iml

# Test artifacts
tests/output/
.github-prep-backup/

# OS-specific
Thumbs.db
.DS_Store

# Private keys and secrets
*.key
*.pem
*.priv
*_private*
.env
.env.local

# Temporary test directories
/tmp/
/var/tmp/
EOF
        log_success "Created .gitignore"
        ((FILES_FIXED++))
    else
        log_success ".gitignore exists"
    fi
}

# ============================================================================
# DOCUMENTATION VALIDATION
# ============================================================================

# Check documentation quality
check_documentation() {
    log_info "Checking documentation quality"

    local required_docs=(
        "README.md"
        "SECURITY.md"
        "CONTRIBUTING.md"
    )

    for doc in "${required_docs[@]}"; do
        local full_path="${PROJECT_ROOT}/${doc}"
        if [[ -f "${full_path}" ]]; then
            local lines=$(wc -l < "${full_path}")
            if [[ ${lines} -gt 10 ]]; then
                log_success "Documentation adequate: ${doc} (${lines} lines)"
            else
                log_warning "Documentation sparse: ${doc} (${lines} lines)"
                ((WARNINGS_FOUND++))
            fi
        else
            log_error "Missing documentation: ${doc}"
            ((ERRORS_FOUND++))
        fi
    done
}

# ============================================================================
# PROJECT STRUCTURE VALIDATION
# ============================================================================

# Verify project structure
verify_structure() {
    log_info "Verifying project structure"

    local -a required_dirs=(
        "bin"
        "config"
        "docs"
        "tests"
        "selinux"
    )

    for dir in "${required_dirs[@]}"; do
        local full_path="${PROJECT_ROOT}/${dir}"
        if [[ -d "${full_path}" ]]; then
            log_success "Directory exists: ${dir}"
        else
            log_error "Missing directory: ${dir}"
            ((ERRORS_FOUND++))
        fi
    done

    # Check core files
    local -a core_files=(
        "mok"
        "README.md"
        "LICENSE"
    )

    for file in "${core_files[@]}"; do
        local full_path="${PROJECT_ROOT}/${file}"
        if [[ -f "${full_path}" ]]; then
            log_success "Core file exists: ${file}"
        else
            log_error "Missing core file: ${file}"
            ((ERRORS_FOUND++))
        fi
    done
}

# ============================================================================
# CODE QUALITY CHECKS
# ============================================================================

# Check bash syntax
check_bash_syntax() {
    log_info "Checking bash script syntax"

    local -i errors=0
    while IFS= read -r script; do
        if bash -n "${script}" 2>/dev/null; then
            log_success "Syntax OK: $(basename "${script}")"
        else
            log_error "Syntax error in: ${script}"
            ((errors++))
            ((ERRORS_FOUND++))
        fi
    done < <(find "${PROJECT_ROOT}" -type f -name "*.sh" ! -path "./.git*")

    if [[ ${errors} -eq 0 ]]; then
        log_success "All scripts have valid bash syntax"
    else
        log_error "Found ${errors} script(s) with syntax errors"
    fi
}

# ============================================================================
# GIT STATUS CHECK
# ============================================================================

# Check git status
check_git_status() {
    log_info "Checking git status"

    if ! command -v git &>/dev/null; then
        log_warning "Git not found, skipping git checks"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # Check for untracked files
    local untracked
    untracked=$(git ls-files --others --exclude-standard | wc -l)
    if [[ ${untracked} -gt 0 ]]; then
        log_warning "Found ${untracked} untracked files"
        ((WARNINGS_FOUND++))
    else
        log_success "No untracked files"
    fi

    # Check for uncommitted changes
    local uncommitted
    uncommitted=$(git status --porcelain | wc -l)
    if [[ ${uncommitted} -gt 0 ]]; then
        log_warning "Found ${uncommitted} uncommitted changes"
        ((WARNINGS_FOUND++))
    else
        log_success "All changes committed"
    fi
}

# ============================================================================
# FINAL REPORT AND SUMMARY
# ============================================================================

# Generate final report
generate_final_report() {
    echo ""
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}GITHUB PUBLICATION PREPARATION REPORT${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"

    echo ""
    echo -e "Files removed:       ${FILES_REMOVED}"
    echo -e "Files fixed:         ${FILES_FIXED}"
    echo -e "${YELLOW}Warnings found:      ${WARNINGS_FOUND}${NC}"
    echo -e "${RED}Errors found:        ${ERRORS_FOUND}${NC}"

    echo ""
    echo -e "${BLUE}Status:${NC}"

    if [[ ${ERRORS_FOUND} -eq 0 && ${WARNINGS_FOUND} -eq 0 ]]; then
        echo -e "${GREEN}✓ Project is ready for GitHub publication${NC}"
        return 0
    elif [[ ${ERRORS_FOUND} -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Project can be published, but review warnings${NC}"
        return 0
    else
        echo -e "${RED}✗ Project has errors that must be fixed before publishing${NC}"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo -e "${MAGENTA}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  MOK GitHub Publication Preparation Tool v1.0             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    log_info "Project Root: ${PROJECT_ROOT}"
    echo ""

    # Execute checks
    verify_structure
    echo ""

    cleanup_files
    echo ""

    fix_permissions
    echo ""

    validate_gitignore
    echo ""

    check_bash_syntax
    echo ""

    check_documentation
    echo ""

    check_private_keys
    echo ""

    scan_for_secrets || true
    echo ""

    check_git_status
    echo ""

    # Generate final report
    generate_final_report
    local final_result=$?

    echo ""

    if [[ ${final_result} -eq 0 ]]; then
        log_success "Ready to push to GitHub!"
        log_info "Next steps:"
        log_info "  1. Review all changes: git status"
        log_info "  2. Add files: git add ."
        log_info "  3. Commit: git commit -m 'Prepare for publication'"
        log_info "  4. Push: git push origin main"
    fi

    echo ""
    return ${final_result}
}

# Execute if running directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
