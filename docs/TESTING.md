# Testing Guide - MOK System

## Overview

The MOK system includes a comprehensive test suite with 45+ test cases that validate all critical functionality, system integration, and error handling capabilities.

## Quick Test

The fastest way to validate your setup:

```bash
# Check system readiness (non-root)
./mok status

# Run full test suite (requires root)
sudo ./mok test
```

## Test Suite Details

The `test-nvidia-signing.sh` script provides comprehensive validation across multiple categories:

### Test Categories

#### 1. System Requirements (8 tests)
- Root privilege verification
- Required tool availability:
  - `mokutil` - Secure Boot management
  - `dracut` - Initramfs generation
  - `modinfo` - Module information
  - `sign-file` - Module signing utility
  - `kmod` - Kernel module tools
  - `tpm2_getcap` - TPM2 capability checking

**What it checks:** Your system has all required tools installed and accessible.

#### 2. Secure Boot Detection (3 tests)
- Checks for UEFI firmware
- Validates `mokutil` functionality
- Determines Secure Boot status

**What it checks:** Whether Secure Boot can be detected and its current state.

#### 3. TPM2 Detection (3 tests)
- Verifies TPM2 tools installation
- Checks for physical TPM2 device
- Validates TPM2 capability detection

**What it checks:** TPM2 availability and health status.

#### 4. Key Management (3 tests)
- Verifies private key existence at `/etc/pki/akmods/certs/private_key.priv`
- Checks public key at `/etc/pki/akmods/certs/public_key.der`
- Validates proper file permissions (400 for private key)

**What it checks:** Signing keys are present and properly secured.

#### 5. Module Discovery (2 tests)
- Searches for NVIDIA modules in `/usr/lib/modules/$(uname -r)/extra/`
- Validates module file integrity

**What it checks:** NVIDIA modules can be found and accessed.

#### 6. Signature Verification (2 tests)
- Tests signature detection using `modinfo`
- Validates signature checking logic

**What it checks:** Module signature detection mechanisms work correctly.

#### 7. File Permissions (2 tests)
- Validates script execution permissions (755)
- Checks directory access permissions

**What it checks:** All files have correct access controls.

#### 8. Access Control (1 test)
- Enforces root-only execution

**What it checks:** Scripts cannot be run by unprivileged users.

#### 9. Systemd Integration (1 test)
- Validates `sign-nvidia.service` configuration
- Checks service installation path

**What it checks:** Systemd service is properly configured.

#### 10. DNF Integration (2 tests)
- Verifies DNF hook file existence
- Validates post-transaction action configuration

**What it checks:** Automatic signing after package updates is configured.

#### 11. Error Handling (2 tests)
- Tests error code handling
- Validates graceful failure modes

**What it checks:** System handles errors safely without data loss.

#### 12. Idempotency (1 test)
- Verifies safe repeated execution

**What it checks:** Running the script multiple times doesn't cause problems.

#### 13. Rollback Capability (1 test)
- Tests recovery functionality

**What it checks:** Can recover from signing failures.

## Running Tests

### Full Test Suite

```bash
sudo ./mok test
```

Expected output:
- Color-coded test results (GREEN=pass, RED=fail, YELLOW=skip)
- Test summary with counts
- JSON report file location
- Detailed explanations of failures

### Specific Test Sections

You can run individual test sections by examining the test script:

```bash
# View test structure
grep "test_section" ./bin/test-nvidia-signing.sh
```

### Debug Mode

For verbose output during testing:

```bash
sudo DEBUG=1 ./mok test
```

This will show:
- All debug messages
- Command execution details
- File access patterns
- System state information

## Test Output Interpretation

### Passing Tests

```
[Test 1] Checking root privileges...
✓ PASSED: Running as root
```

Good! The test condition was met.

### Skipped Tests

```
[Test 5] Checking TPM2 availability...
SKIPPED: TPM2 tools not installed
```

Expected - your system doesn't have this optional component. The system will degrade gracefully.

### Failed Tests

```
[Test 8] Checking signing key...
✗ FAILED: Private key not found at /etc/pki/akmods/certs/private_key.priv
```

Action needed! You need to:
1. Generate signing keys: `sudo kmodgenca -a`
2. Verify key location: `ls -la /etc/pki/akmods/certs/`
3. Run tests again

## Test Results File

Each test run generates a JSON report:

```bash
/tmp/nvidia-signing-test-results-<PID>.json
```

Example contents:
```json
{
  "timestamp": "2025-11-19T10:45:30Z",
  "total_tests": 45,
  "passed": 43,
  "failed": 1,
  "skipped": 1,
  "tests": {
    "Root privilege check": "PASSED",
    "Private key verification": "PASSED",
    "TPM2 detection": "SKIPPED: Tools not installed",
    ...
  }
}
```

## Common Test Failures and Solutions

### "Private key not found"

**Problem:** Signing keys haven't been generated

**Solution:**
```bash
# Check if keys exist
ls -la /etc/pki/akmods/certs/

# Generate if missing
sudo kmodgenca -a

# Verify generation
ls -la /etc/pki/akmods/certs/
```

### "mokutil not found"

**Problem:** System utilities missing

**Solution:**
```bash
# Install required tools
sudo dnf install mokutil kmod kernel-devel dracut
```

### "Not running as root"

**Problem:** Test script needs root privileges

**Solution:**
```bash
# Run with sudo
sudo ./mok test
```

### "Permission denied" on directories

**Problem:** Directory access control issue

**Solution:**
```bash
# Verify directory permissions
ls -ld /var/lib/nvidia-signing
ls -ld /var/log/nvidia-signing

# Fix if needed (after installation)
sudo chmod 700 /var/lib/nvidia-signing
sudo chmod 700 /var/log/nvidia-signing
```

## Pre-Installation Testing

Before installing the system:

```bash
# 1. Verify basic system compatibility
./mok status

# 2. Run test suite (will show what's missing)
sudo ./mok test

# 3. Review failures/skips carefully
# 4. Install missing components
sudo dnf install mokutil kmod kernel-devel dracut
```

## Post-Installation Testing

After installation:

```bash
# 1. Verify installation
./mok status

# 2. Run full test suite
sudo ./mok test

# 3. Check systemd service
sudo systemctl status sign-nvidia.service

# 4. Check logs
./mok logs

# 5. Manual signing (optional test)
sudo ./mok sign --debug
```

## Continuous Testing

For ongoing validation:

```bash
# Create a cron job for periodic testing
echo "0 3 * * 0 /var/home/sanya/MOK/mok test >> /tmp/mok-test.log 2>&1" | sudo crontab -

# View results
tail -f /tmp/mok-test.log
```

Or use a systemd timer:

```bash
sudo systemctl timer list-timers nvidia-signing*
```

## Test Metrics

Typical successful test run:

- **Total Tests:** 45
- **Passed:** 40-44 (depends on optional features)
- **Failed:** 0 (critical failures)
- **Skipped:** 1-5 (optional features not installed)

Acceptable skip scenarios:
- TPM2 tools (system doesn't have TPM2)
- Some kernel modules (custom NVIDIA driver installation)

Unacceptable failures:
- Signing keys missing (must be generated)
- Script permissions (must be 755)
- Root privilege requirement (must run as root)

## Test Development

To add new tests to the suite:

1. Edit `bin/test-nvidia-signing.sh`
2. Add test function following existing patterns
3. Use `begin_test`, `pass_test`, `fail_test`, or `skip_test` functions
4. Run `sudo ./mok test` to verify
5. Check JSON output for completeness

Example test pattern:
```bash
begin_test "Your test name"
if [[ -f "/path/to/check" ]]; then
    pass_test "File exists"
else
    fail_test "File not found at /path/to/check"
fi
```

## Performance Metrics

Typical test execution time:
- Quick status check: ~5 seconds
- Full test suite: ~30-60 seconds (depending on system)
- Individual test: ~1-2 seconds

## Troubleshooting Test Issues

### Test hangs or freezes

```bash
# Use timeout if available
timeout 60 sudo ./mok test

# Or kill the process
ps aux | grep test-nvidia
sudo kill <PID>
```

### Test produces corrupted output

```bash
# Run with explicit output
sudo ./mok test > /tmp/test.log 2>&1
cat /tmp/test.log
```

### JSON report won't parse

```bash
# Check JSON validity
python3 -m json.tool /tmp/nvidia-signing-test-results-*.json

# Or use jq if available
jq . /tmp/nvidia-signing-test-results-*.json
```

## Testing Best Practices

1. **Run tests on clean system:** Helps identify missing components
2. **Check all output:** Don't ignore warnings or skipped tests
3. **Document failures:** Keep records of test failures and fixes
4. **Test after updates:** Run tests after kernel or driver updates
5. **Keep logs:** Archive test results for audit trail
6. **Test recovery:** Periodically test rollback functionality

## Integration with CI/CD

For automated testing pipelines:

```bash
#!/bin/bash
set -euo pipefail

# Run tests and capture JSON output
TEST_OUTPUT=$(sudo /var/home/sanya/MOK/mok test 2>&1)

# Parse results
if grep -q "FAILED" <<< "$TEST_OUTPUT"; then
    echo "Tests FAILED"
    exit 1
fi

echo "Tests PASSED"
exit 0
```

## Getting Help

If tests fail with unclear error messages:

```bash
# Get verbose output
sudo DEBUG=1 ./mok test 2>&1 | tee /tmp/test-debug.log

# Check documentation
./mok docs README

# View full test script
cat ./bin/test-nvidia-signing.sh

# Check system logs
journalctl -u sign-nvidia.service -n 50
```
