# Contributing to MOK

Thank you for your interest in contributing to the MOK project! This document provides guidelines and instructions for contributing.

## Code of Conduct

Be respectful, inclusive, and constructive in all interactions. We're committed to providing a welcoming environment for all contributors.

## How to Contribute

### Reporting Bugs

Found a bug? Please create an issue with:

1. **Clear title** - What's broken?
2. **Description** - What did you expect vs what happened?
3. **Steps to reproduce** - How can we recreate it?
4. **System info** - Fedora version, kernel version, hardware details
5. **Test output** - Run `sudo ./mok test` and share results

Example:
```
Title: Modules not signing after kernel update

Description:
After updating the kernel, modules are still unsigned

Steps to reproduce:
1. sudo dnf update kernel
2. sudo ./mok sign
3. modinfo /path/to/nvidia.ko (shows unsigned)

System:
- Fedora 43 on ASUS laptop
- Kernel 6.17.8
- NVIDIA RTX 3060

Test output:
[Paste test results here]
```

### Suggesting Enhancements

Have an idea? Create an issue with:

1. **Clear title** - What's the feature?
2. **Description** - Why would this be useful?
3. **Example usage** - How would users interact with it?
4. **Alternatives** - Other ways to solve this?

### Submitting Changes

#### Before You Start

1. Check existing issues/PRs to avoid duplicates
2. Fork the repository
3. Create a feature branch: `git checkout -b feature/my-feature`
4. Keep changes focused and atomic

#### Making Changes

1. **Follow the code style:**
   - Use consistent indentation (4 spaces)
   - Add comments for complex logic
   - Use meaningful variable names
   - Keep functions focused (single responsibility)

2. **Test thoroughly:**
   ```bash
   # Run the full test suite
   sudo ./mok test

   # Test with debug output
   sudo DEBUG=1 ./mok test
   ```

3. **Update documentation:**
   - Update README if changing user-facing behavior
   - Update relevant docs in `docs/` directory
   - Add inline code comments if needed

4. **Commit clearly:**
   ```bash
   # Good commit messages
   git commit -m "Add TPM2 verification to health check

   - Detect TPM2 presence during status check
   - Report TPM2 availability in status output
   - Add corresponding test case"
   ```

#### Submitting a Pull Request

1. **Test locally:**
   ```bash
   ./mok status          # Check system
   sudo ./mok test       # Full validation
   ```

2. **Push and create PR:**
   ```bash
   git push origin feature/my-feature
   ```

3. **PR Description:**
   ```markdown
   ## Summary
   Brief description of changes

   ## Changes
   - What was changed
   - How it works
   - Why this approach

   ## Testing
   - How to verify the changes
   - Test results

   ## Checklist
   - [ ] Tested locally with `sudo ./mok test`
   - [ ] Updated documentation
   - [ ] Added comments for complex code
   - [ ] No breaking changes
   ```

## Development Setup

### Prerequisites

```bash
# Install required tools
sudo dnf install bash git shellcheck

# Optional: for testing
sudo dnf install mokutil kernel-devel dracut
```

### Developing Locally

```bash
# Clone the repository
git clone https://github.com/username/mok
cd mok

# Create feature branch
git checkout -b feature/my-feature

# Make changes
# Edit bin/sign-nvidia-modules.sh or other scripts

# Test changes
./mok status
sudo ./mok test

# Commit and push
git add .
git commit -m "Your message"
git push origin feature/my-feature
```

### Code Guidelines

#### Bash Best Practices

```bash
#!/bin/bash
set -euo pipefail  # Always use this

# Use function definitions for organization
my_function() {
    local local_var="$1"  # Use local variables

    if [[ -f "${var}" ]]; then  # Quote variables
        do_something
    fi
}

# Always use meaningful names
local module_path="${MODULES_EXTRA_PATH}"
local is_signed=true

# Error handling
if ! command_that_might_fail; then
    log_error "Something went wrong"
    return 1
fi
```

#### Documentation

```bash
# Add comments for non-obvious logic
# Explain the 'why', not the 'what'
if [[ "${file_age}" -lt 60 ]]; then
    # Verify the initramfs was actually regenerated (not cached)
    log_success "Initramfs timestamp verification passed"
fi
```

#### Testing Code

```bash
# Write functions that can be tested
check_module_signed() {
    local module="$1"

    # Method 1: Check using modinfo
    if modinfo -F signer "${module}" 2>/dev/null | grep -q .; then
        return 0
    fi

    # Method 2: Check tainted flag
    local module_name=$(basename "${module}" .ko)
    if [[ -f "/sys/module/${module_name}/tainted" ]]; then
        if [[ "$(cat "/sys/module/${module_name}/tainted")" == "0" ]]; then
            return 0
        fi
    fi

    return 1
}
```

## Testing Guidelines

### Running Tests

```bash
# Full test suite
sudo ./mok test

# Specific test
sudo ./mok test 2>&1 | grep "Test Name"

# Debug mode
sudo DEBUG=1 ./mok test

# Test specific script
sudo ./bin/sign-nvidia-modules.sh
```

### Adding Tests

When adding a feature, add corresponding tests:

```bash
# In bin/test-nvidia-signing.sh

# 1. Add to appropriate section
test_section "My Feature Tests"

# 2. Create test
begin_test "My new feature works correctly"
if my_new_function > /dev/null 2>&1; then
    pass_test "Feature works as expected"
else
    fail_test "Feature failed to work"
fi
```

## Project Structure

```
mok/
├── bin/                    # Core scripts (what you'll usually edit)
│   ├── sign-nvidia-modules.sh
│   ├── test-nvidia-signing.sh
│   ├── rollback-nvidia-signing.sh
│   ├── install-nvidia-signing.sh
│   └── common.sh
├── config/                 # System configuration
├── docs/                   # User documentation
├── selinux/               # Security policies
├── mok                    # Main launcher
├── README.md              # Project overview
└── CONTRIBUTING.md        # This file
```

## Making Different Types of Changes

### Adding a New Feature

1. **Design phase:**
   - Discuss in an issue first
   - Get feedback from maintainers
   - Plan the implementation

2. **Implementation:**
   - Add code to appropriate script
   - Add logging/output for users
   - Add corresponding tests
   - Update documentation

3. **Testing:**
   - Run full test suite: `sudo ./mok test`
   - Test edge cases manually
   - Verify no regressions

### Fixing a Bug

1. **Create issue** with reproduction steps
2. **Write test** that demonstrates the bug
3. **Fix the bug** (minimal change)
4. **Verify test passes** with the fix
5. **Submit PR** with clear explanation

### Improving Documentation

1. **Identify unclear sections** in docs/
2. **Clarify the explanation** with examples
3. **Verify accuracy** against actual code
4. **Get feedback** if it's major
5. **Submit PR** with improved docs

## Review Process

When you submit a PR:

1. **Automated checks** run tests and validation
2. **Maintainer reviews** code for:
   - Correctness and security
   - Alignment with project goals
   - Code quality and style
   - Documentation completeness
3. **Feedback** provided if changes needed
4. **Approval** and merge when ready

## Commit Message Guidelines

Good commit messages:
- Start with an imperative verb: "Add", "Fix", "Update", "Remove"
- First line is a short summary (50 chars)
- Leave blank line
- Add detailed explanation if needed
- Reference issues: "Fixes #123" or "Related to #456"

Examples:

```
Add TPM2 detection to status output
Fixes #42

Previously, the status command didn't show TPM2 information.
This adds detection and reporting of TPM2 availability.
```

```
Fix module signing timeout on slow systems
Related to #78

Increase timeout from 30s to 60s for systems with slow disk I/O.
Added DEBUG=1 output to track timing.
```

## Release Process

(For maintainers)

1. **Update version** in all scripts
2. **Update CHANGELOG.md** with changes
3. **Run full tests** on target systems
4. **Tag release:** `git tag v1.0.1`
5. **Push release:** `git push origin main --tags`
6. **Create release notes** on GitHub

## Communication

- **Issues** - Report bugs and suggest features
- **Discussions** - Ask questions and discuss ideas
- **PRs** - Submit changes and code reviews
- **Email** - Contact maintainers directly if needed

## License

By contributing to MOK, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors will be recognized:
- In commit history
- In release notes for major contributions
- In CONTRIBUTORS.md file (to be created)

## Questions?

- Check existing [Issues](https://github.com/mok/issues)
- Read the [Documentation](docs/)
- Create a [Discussion](https://github.com/mok/discussions)

Thank you for contributing to MOK!
