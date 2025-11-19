# NVIDIA Kernel Module Auto-Signing System
## Fedora 43 with Secure Boot and TPM2 Support

**Version:** 1.0.0
**Author:** Automated Signing System
**Purpose:** Fully automated detection and signing of NVIDIA kernel modules to maintain Secure Boot compliance

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Requirements](#requirements)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Usage](#usage)
7. [Testing](#testing)
8. [Troubleshooting](#troubleshooting)
9. [Recovery](#recovery)
10. [Security](#security)
11. [Architecture](#architecture)
12. [Advanced Topics](#advanced-topics)

---

## Overview

This system provides complete automation of NVIDIA kernel module signing on Fedora 43 systems with Secure Boot enabled. It ensures that unsigned NVIDIA drivers are automatically detected and signed using enrolled Machine Owner Keys (MOK), maintaining system security while allowing proprietary driver use.

### Key Objectives

- **Zero Manual Intervention:** Completely automated workflow
- **Secure Boot Compliance:** Maintains Secure Boot integrity
- **Error Recovery:** Comprehensive rollback mechanisms
- **Full Audit Trail:** Detailed logging of all operations
- **Idempotent Execution:** Safe to run multiple times
- **TPM2 Integration:** Optional TPM2 support for enhanced security

---

## Features

### Core Features

✓ **Automatic Module Detection**
- Discovers all NVIDIA kernel modules in `/usr/lib/modules/$(uname -r)/extra/`
- Classifies modules as signed or unsigned

✓ **Secure Boot Detection**
- Detects system Secure Boot status via `mokutil`
- Adapts behavior based on Secure Boot state

✓ **TPM2 Support**
- Detects TPM2 chip availability
- Optional TPM2 integration for additional security

✓ **Intelligent Signing**
- Signs only unsigned modules
- Uses system kernel signing keys
- Verifies signatures after signing
- Creates backups before modifications

✓ **Automated Initramfs Regeneration**
- Automatically rebuilds initramfs when modules are signed
- Ensures boot image consistency

✓ **Systemd Integration**
- Runs automatically on system boot
- Can be triggered manually via systemctl
- Proper ordering with other systemd services

✓ **DNF Integration**
- Automatically runs after kernel or NVIDIA driver updates
- Integrated into DNF post-transaction actions
- Transparent to user operations

✓ **Access Control**
- Restricts signing tool access to root only
- Optional SELinux policy for enhanced restriction
- File permission management

✓ **Comprehensive Logging**
- Detailed operation logs with timestamps
- Structured JSON state files
- Complete audit trail for compliance

✓ **Error Handling**
- Full error checking and validation
- Graceful failure modes
- Detailed error messages

✓ **Recovery System**
- Automatic backup of modules before signing
- Rollback mechanism for failed operations
- Interactive and automatic recovery modes

✓ **Testing Framework**
- Comprehensive test suite
- Modular test architecture
- Detailed test reporting

---

## Requirements

### System Requirements

- **OS:** Fedora 43 (or compatible)
- **Firmware:** UEFI with Secure Boot support
- **Kernel:** Recent Linux kernel with module signing support
- **Architecture:** x86_64

### Required Packages

```bash
# Core requirements
dnf install kernel-devel dracut mokutil

# Optional but recommended
dnf install tpm2-tools
dnf install selinux-policy-devel  # For SELinux policy compilation

# For NVIDIA drivers
dnf install akmod-nvidia           # or xorg-x11-drv-nvidia
```

### Required Tools

- `kmodgenca` - For generating signing keys (from kernel-devel)
- `mokutil` - For MOK management
- `modinfo` - For module information (from kmod)
- `dracut` - For initramfs generation
- `sign-file` - Located in kernel source tree
- `systemd` - For service management

### Permissions

- Must run as root for installation and operation
- Signing keys must be in `/etc/pki/akmods/certs/`

---

## Installation

### Step 1: Pre-Installation Checks

Verify your system meets all requirements:

```bash
# Check Fedora version
cat /etc/os-release | grep VERSION_ID

# Verify UEFI
[ -d /sys/firmware/efi ] && echo "UEFI detected" || echo "No UEFI"

# Check Secure Boot status
mokutil --sb-state

# Verify required tools
which dracut modinfo mokutil
```

### Step 2: Download Installation Files

Ensure all required files are in the installation directory:

```bash
ls -la /path/to/mok/
# Expected files:
# - sign-nvidia-modules.sh
# - rollback-nvidia-signing.sh
# - test-nvidia-signing.sh
# - install-nvidia-signing.sh
# - sign-nvidia.service
# - nvidia-signing.action
# - nvidia-signing.te
```

### Step 3: Run Installation Script

```bash
sudo bash /path/to/mok/install-nvidia-signing.sh
```

The installer will:
1. Check all prerequisites
2. Install scripts to `/usr/local/bin/`
3. Install systemd service
4. Configure DNF hooks
5. Compile and install SELinux policy
6. Create required directories
7. Set up access restrictions
8. Run verification tests
9. Enable the service

### Step 4: Generate and Enroll Signing Keys

If keys don't already exist:

```bash
# Generate keys
sudo kmodgenca -a

# Verify keys were created
ls -la /etc/pki/akmods/certs/

# Enroll public key in MOK
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

You'll be prompted to set a temporary password for MOK enrollment.

### Step 5: Reboot for MOK Enrollment

```bash
sudo reboot
```

During boot, you'll see the MOK Manager screen. Select "Enroll MOK" and enter the password you set.

### Step 6: Verify Installation

After reboot:

```bash
# Check service status
sudo systemctl status sign-nvidia.service

# Review service logs
sudo journalctl -u sign-nvidia.service -n 50

# Check NVIDIA module signatures
modinfo /usr/lib/modules/$(uname -r)/extra/nvidia.ko | grep -i signer

# Run full test suite
sudo /usr/local/bin/test-nvidia-signing.sh
```

---

## Configuration

### Main Configuration File

The main script uses hardcoded paths suitable for Fedora 43:

```bash
# In sign-nvidia-modules.sh
KEY_DIR="/etc/pki/akmods/certs"
MODULES_EXTRA_PATH="/usr/lib/modules/$(uname -r)/extra"
KERNEL_DIR="/usr/src/kernels/$(uname -r)"
LOG_DIR="/var/log/nvidia-signing"
STATE_DIR="/var/lib/nvidia-signing"
BACKUP_DIR="/var/lib/nvidia-signing/backups"
```

### Systemd Service Configuration

Edit `/etc/systemd/system/sign-nvidia.service` to customize:

```ini
# Execution order
After=dracut-pre-build.service

# Timing
WantedBy=multi-user.target

# Security settings (modify if needed)
ProtectSystem=strict
ProtectHome=yes
```

After changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart sign-nvidia.service
```

### DNF Hook Configuration

Located at `/etc/dnf/plugins/post-transaction-actions.d/nvidia-signing.action`

Triggers on:
- `akmod-nvidia*` - NVIDIA AKMOD driver updates
- `xorg-x11-drv-nvidia*` - NVIDIA Xorg driver updates
- `kernel*` - Kernel updates

---

## Usage

### Manual Execution

Sign modules manually:

```bash
sudo /usr/local/bin/sign-nvidia-modules.sh
```

### View Output

With verbose logging:

```bash
DEBUG=1 sudo /usr/local/bin/sign-nvidia-modules.sh
```

### Systemd Service Commands

```bash
# Check service status
sudo systemctl status sign-nvidia.service

# Start service immediately
sudo systemctl start sign-nvidia.service

# View recent logs
sudo journalctl -u sign-nvidia.service -n 100 --no-pager

# View logs in real-time
sudo journalctl -u sign-nvidia.service -f

# View logs for specific date
sudo journalctl -u sign-nvidia.service --since "2024-01-15" --until "2024-01-16"
```

### Check Module Signatures

```bash
# Check specific module
modinfo /usr/lib/modules/$(uname -r)/extra/nvidia.ko | grep signer

# Check all NVIDIA modules
for mod in /usr/lib/modules/$(uname -r)/extra/nvidia*.ko; do
    echo "$(basename $mod):"
    modinfo "$mod" | grep -i signer || echo "  unsigned"
done

# Check tainted status
cat /sys/module/nvidia/tainted 2>/dev/null || echo "Module not loaded"
```

---

## Testing

### Run Full Test Suite

```bash
sudo /usr/local/bin/test-nvidia-signing.sh
```

The test suite validates:

- Root privileges
- Required tools availability
- Secure Boot detection
- TPM2 detection
- Key existence and permissions
- Module detection
- Signature verification
- File system permissions
- Access restrictions
- Systemd service configuration
- DNF hook integration
- Error handling
- Idempotency
- Rollback capability

### Run Specific Test Groups

The test suite is modular. Modify and run specific test functions:

```bash
# Test only Secure Boot detection
# (Edit test-nvidia-signing.sh and run specific functions)
```

### Interpret Test Results

```json
{
  "overall_status": "PASSED",
  "summary": {
    "total": 45,
    "passed": 43,
    "failed": 0,
    "skipped": 2
  }
}
```

- **PASSED:** Test succeeded
- **SKIPPED:** Test was not applicable to this system
- **FAILED:** Test failed, review logs for details

### Test Failure Troubleshooting

If tests fail, check the generated report:

```bash
cat /tmp/nvidia-signing-test-results-*.json | jq .

# View detailed test logs
tail -f /var/log/nvidia-signing/nvidia-signing-*.log
```

---

## Troubleshooting

### Issue: Service Fails to Start

**Symptoms:**
```
● sign-nvidia.service - Auto Sign Nvidia Kernel Modules
     Loaded: loaded (/etc/systemd/system/sign-nvidia.service; enabled)
     Active: failed
```

**Diagnosis:**
```bash
sudo journalctl -u sign-nvidia.service -n 50 --no-pager
```

**Solutions:**

1. **Missing keys:**
   ```bash
   sudo kmodgenca -a
   sudo mokutil --import /etc/pki/akmods/certs/public_key.der
   sudo reboot
   ```

2. **Missing kernel sources:**
   ```bash
   sudo dnf install kernel-devel-$(uname -r)
   ```

3. **Permission issues:**
   ```bash
   sudo chown root:root /usr/local/bin/sign-nvidia-modules.sh
   sudo chmod 755 /usr/local/bin/sign-nvidia-modules.sh
   ```

### Issue: Modules Still Unsigned

**Diagnosis:**
```bash
# Check if modules were signed
modinfo /usr/lib/modules/$(uname -r)/extra/nvidia.ko | grep signer

# Check service logs
sudo journalctl -u sign-nvidia.service -n 100

# Check log files
sudo tail -f /var/log/nvidia-signing/*.log
```

**Solutions:**

1. **Verify keys are enrolled:**
   ```bash
   mokutil --list-enrolled
   ```

2. **Run signing manually:**
   ```bash
   sudo /usr/local/bin/sign-nvidia-modules.sh
   ```

3. **Check kernel sources:**
   ```bash
   ls /usr/src/kernels/$(uname -r)/scripts/sign-file
   ```

### Issue: High CPU Usage After Signing

**Solution:**
The system is regenerating initramfs, which is normal and temporary.

### Issue: Secure Boot Shows as Disabled

**Diagnosis:**
```bash
mokutil --sb-state
```

**Solutions:**

1. **Enable in BIOS:** Reboot and enter BIOS to enable Secure Boot
2. **Check UEFI:** Verify system has UEFI firmware
3. **Reset Secure Boot:** Clear NVRAM and re-enroll keys

---

## Recovery

### Automatic Recovery

If the system enters an error state:

```bash
sudo /usr/local/bin/rollback-nvidia-signing.sh --auto
```

This will:
1. Restore all modules from latest backups
2. Regenerate initramfs
3. Clear corrupted state files

### Interactive Recovery

For step-by-step recovery:

```bash
sudo /usr/local/bin/rollback-nvidia-signing.sh
```

Menu options:
1. Restore all modules from latest backups
2. Restore specific module
3. List available backups
4. Clear corrupted state only
5. Show system status
6. Exit

### Manual Module Restore

To restore a specific module:

```bash
# Find backup
ls -la /var/lib/nvidia-signing/backups/ | grep nvidia.ko

# Restore
sudo cp /var/lib/nvidia-signing/backups/TIMESTAMP_nvidia.ko \
        /usr/lib/modules/$(uname -r)/extra/nvidia.ko

# Verify
modinfo /usr/lib/modules/$(uname -r)/extra/nvidia.ko | grep signer

# Regenerate initramfs
sudo dracut --force

# Reboot
sudo reboot
```

### View Backup History

```bash
# List all backups
sudo ls -lah /var/lib/nvidia-signing/backups/

# Find backups for specific module
sudo ls -lah /var/lib/nvidia-signing/backups/ | grep nvidia

# Check backup validity
sudo file /var/lib/nvidia-signing/backups/*
```

---

## Security

### Security Considerations

#### Key Management

- Signing keys stored in `/etc/pki/akmods/certs/` with root-only access
- Private key permissions: `400` (read-only by owner)
- Public key permissions: `444` (readable by all)

```bash
# Verify key permissions
ls -la /etc/pki/akmods/certs/
# Output should show:
# -r--------  root root  private_key.priv
# -r--r--r--  root root  public_key.der
```

#### Access Control

Only root can execute:
- `/usr/local/bin/sign-nvidia-modules.sh`
- `/usr/src/kernels/*/scripts/sign-file`
- `/usr/bin/mokutil`

```bash
# Verify permissions
ls -la /usr/local/bin/sign-nvidia-modules.sh
ls -la /usr/src/kernels/$(uname -r)/scripts/sign-file
ls -la /usr/bin/mokutil
```

#### SELinux Policies

The included SELinux module (`nvidia-signing.te`) provides:

- Domain isolation: `nvidia_signing_t`
- Restricted file access: `nvidia_signing_var_lib_t`, `nvidia_signing_var_log_t`
- Device access control: TPM2, EFI
- Network restrictions: Loopback only

Verify SELinux policy installation:

```bash
sudo semodule -l | grep nvidia_signing
sudo getsebool -a | grep nvidia
```

#### Audit Logging

All operations are logged to:
- System journal: `/var/log/journal/`
- Application logs: `/var/log/nvidia-signing/`
- State files: `/var/lib/nvidia-signing/state.json`

Access logs:

```bash
# View audit logs
sudo journalctl -u sign-nvidia.service

# View application logs
sudo tail -f /var/log/nvidia-signing/*.log

# View state
sudo cat /var/lib/nvidia-signing/state.json | jq .
```

#### Secure Boot Compliance

- Modules signed with system-enrolled keys
- Signatures verified on each execution
- Unsigned modules detected and signed automatically
- Initramfs includes signed modules

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    NVIDIA Signing System                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  sign-nvidia-modules.sh (Main Automation Script)      │   │
│  ├──────────────────────────────────────────────────────┤   │
│  │ • Detects Secure Boot status                         │   │
│  │ • Detects TPM2 availability                          │   │
│  │ • Discovers NVIDIA modules                           │   │
│  │ • Checks signatures                                  │   │
│  │ • Signs unsigned modules                             │   │
│  │ • Regenerates initramfs                              │   │
│  │ • Maintains audit trail                              │   │
│  └──────────────────────────────────────────────────────┘   │
│                            ▲                                  │
│                            │                                  │
│  ┌──────────────────────────┴──────────────────────────┐   │
│  │                                                      │   │
│  ▼                                                      ▼   │
│ ┌──────────────────────┐  ┌──────────────────────┐   │
│ │  sign-nvidia.service  │  │ nvidia-signing.action │   │
│ │  (Systemd Service)    │  │ (DNF Post-Action)     │   │
│ │                       │  │                       │   │
│ │ • Runs on boot        │  │ • Triggers after      │   │
│ │ • Manual start        │  │   dnf transactions    │   │
│ │ • Ordered execution   │  │                       │   │
│ └──────────────────────┘  └──────────────────────┘   │
│                                                       │
│  ┌─────────────────────────────────────────────┐   │
│  │  rollback-nvidia-signing.sh (Recovery)       │   │
│  ├─────────────────────────────────────────────┤   │
│  │ • Restore from backups                      │   │
│  │ • Interactive/Automatic modes               │   │
│  │ • State cleanup                             │   │
│  └─────────────────────────────────────────────┘   │
│                                                       │
│  ┌─────────────────────────────────────────────┐   │
│  │  test-nvidia-signing.sh (Test Suite)         │   │
│  ├─────────────────────────────────────────────┤   │
│  │ • Modular test framework                    │   │
│  │ • Comprehensive validation                  │   │
│  │ • JSON reporting                            │   │
│  └─────────────────────────────────────────────┘   │
│                                                       │
└─────────────────────────────────────────────────────────────┘

Data Flow:

┌─────────────┐
│   Trigger   │
├─────────────┤
│ • Boot      │
│ • DNF event │
│ • Manual    │
└──────┬──────┘
       │
       ▼
┌──────────────────────────┐
│  System Checks           │
├──────────────────────────┤
│ • Root privileges        │
│ • Secure Boot status     │
│ • TPM2 availability      │
│ • Keys existence         │
│ • Tools availability     │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│  Module Discovery        │
├──────────────────────────┤
│ • Find /usr/lib/modules  │
│ • List nvidia*.ko        │
│ • Classify signatures    │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│  Signing Process         │
├──────────────────────────┤
│ • Backup module          │
│ • Sign with keys         │
│ • Verify signature       │
│ • Log result             │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│  Finalization            │
├──────────────────────────┤
│ • Regenerate initramfs   │
│ • Save state             │
│ • Audit logging          │
└──────────────────────────┘
```

### Execution Flow

**On Boot:**
1. Systemd detects `sign-nvidia.service` in `WantedBy=multi-user.target`
2. Service starts after `dracut-pre-build.service`
3. Runs `sign-nvidia-modules.sh`
4. Checks and signs any unsigned modules
5. Regenerates initramfs if needed

**On Package Update (via DNF):**
1. DNF detects transaction matching `nvidia-signing.action` rule
2. Post-transaction hook executes `sign-nvidia-modules.sh`
3. Automatically signs any newly installed modules

**Manual Execution:**
1. User runs `sudo sign-nvidia-modules.sh`
2. Script processes normally
3. Returns exit code 0 on success, 1 on failure

### File Structure

```
/usr/local/bin/
├── sign-nvidia-modules.sh      # Main automation script
├── rollback-nvidia-signing.sh  # Recovery script
└── test-nvidia-signing.sh      # Test suite

/etc/systemd/system/
└── sign-nvidia.service         # Systemd service

/etc/dnf/plugins/post-transaction-actions.d/
└── nvidia-signing.action       # DNF hook

/etc/pki/akmods/certs/
├── private_key.priv            # Signing key (root only)
└── public_key.der              # Public key

/var/lib/nvidia-signing/
├── state.json                  # Execution state
└── backups/                    # Module backups
    └── TIMESTAMP_modulename.ko # Backup copies

/var/log/nvidia-signing/
└── nvidia-signing-*.log        # Execution logs

/usr/share/selinux/packages/nvidia-signing/
├── nvidia-signing.te           # Policy source
├── nvidia-signing.mod          # Compiled module
└── nvidia-signing.pp           # Package file
```

---

## Advanced Topics

### Custom Key Generation

If you need to use custom keys instead of system-generated ones:

```bash
# Generate custom keys
openssl genrsa -out custom_key.priv 2048
openssl x509 -new -key custom_key.priv -out custom_key.der

# Copy to system location
sudo cp custom_key.priv /etc/pki/akmods/certs/
sudo cp custom_key.der /etc/pki/akmods/certs/

# Enroll in MOK
sudo mokutil --import /etc/pki/akmods/certs/custom_key.der
```

### Debugging Issues

Enable debug mode:

```bash
DEBUG=1 sudo /usr/local/bin/sign-nvidia-modules.sh
```

Debug output will show:
- System checks
- Module discovery
- Signing operations
- State management

### Integrating with Configuration Management

For Ansible/Puppet/Salt:

```yaml
# Example Ansible role
- name: Install NVIDIA signing system
  hosts: fedora_systems
  become: yes
  tasks:
    - name: Copy signing scripts
      copy:
        src: /path/to/mok/
        dest: /opt/nvidia-signing/

    - name: Run installer
      command: /opt/nvidia-signing/install-nvidia-signing.sh
      register: install_result

    - name: Verify installation
      command: /usr/local/bin/test-nvidia-signing.sh
      register: test_result
```

### Performance Tuning

#### Optimize Signing Speed

The signing process can be optimized by:

1. **Parallel signing** (if multiple modules):
   - Modify script to use GNU parallel

2. **Caching module list**:
   - Store module list between runs

3. **Conditional initramfs rebuild**:
   - Skip if no modules were signed

Example modification:

```bash
# In sign-nvidia-modules.sh, replace regenerate_initramfs call with:
if [[ ${MODULES_SIGNED_COUNT} -gt 0 ]]; then
    regenerate_initramfs
fi
```

#### Monitor Performance

```bash
# Time the signing process
time sudo /usr/local/bin/sign-nvidia-modules.sh

# Monitor system resources
watch -n 1 'top -bn1 | head -20'

# Check initramfs regeneration time
time sudo dracut --force
```

### Integration with Other Tools

#### With NVIDIA Container Toolkit

Ensure container host system has signed modules:

```bash
# Verify before using nvidia-docker
sudo /usr/local/bin/test-nvidia-signing.sh
```

#### With GPU Pass-through

Signed modules required for:
- vGPU
- SR-IOV
- Direct GPU pass-through

### Uninstallation

To completely remove the signing system:

```bash
#!/bin/bash
# Remove service
sudo systemctl disable --now sign-nvidia.service
sudo rm /etc/systemd/system/sign-nvidia.service
sudo systemctl daemon-reload

# Remove scripts
sudo rm /usr/local/bin/sign-nvidia-modules.sh
sudo rm /usr/local/bin/rollback-nvidia-signing.sh
sudo rm /usr/local/bin/test-nvidia-signing.sh

# Remove DNF hook
sudo rm /etc/dnf/plugins/post-transaction-actions.d/nvidia-signing.action

# Remove SELinux policy
sudo semodule -r nvidia_signing

# Keep state and logs for reference
# sudo rm -rf /var/lib/nvidia-signing
# sudo rm -rf /var/log/nvidia-signing
```

---

## Support and Reporting

### Getting Help

1. **Check logs:**
   ```bash
   sudo tail -f /var/log/nvidia-signing/*.log
   sudo journalctl -u sign-nvidia.service
   ```

2. **Run tests:**
   ```bash
   sudo /usr/local/bin/test-nvidia-signing.sh
   ```

3. **Check status:**
   ```bash
   sudo systemctl status sign-nvidia.service
   ```

### Reporting Issues

When reporting issues, include:

1. System information:
   ```bash
   cat /etc/os-release
   uname -a
   ```

2. Signing system logs:
   ```bash
   sudo tar czf nvidia-signing-logs.tar.gz /var/log/nvidia-signing/
   ```

3. System journal:
   ```bash
   sudo journalctl -u sign-nvidia.service > journal.log
   ```

4. Test results:
   ```bash
   sudo /usr/local/bin/test-nvidia-signing.sh > test-results.txt 2>&1
   ```

---

## License and Maintenance

This automated signing system is designed for Fedora 43 with Secure Boot and TPM2 support. Regular updates may be needed to maintain compatibility with:

- Kernel updates
- Fedora releases
- NVIDIA driver updates
- Security policy changes

---

## Appendix

### Quick Reference Commands

```bash
# Check module signatures
modinfo /usr/lib/modules/$(uname -r)/extra/nvidia.ko | grep signer

# Manual signing
sudo /usr/local/bin/sign-nvidia-modules.sh

# View service logs
sudo journalctl -u sign-nvidia.service -n 50

# Recovery
sudo /usr/local/bin/rollback-nvidia-signing.sh --auto

# Run tests
sudo /usr/local/bin/test-nvidia-signing.sh

# Check Secure Boot
mokutil --sb-state

# List enrolled keys
mokutil --list-enrolled

# View available backups
sudo ls /var/lib/nvidia-signing/backups/

# Regenerate initramfs
sudo dracut --force

# Reboot system
sudo systemctl reboot
```

---

**Documentation Version:** 1.0.0
**Last Updated:** November 2024
**Compatibility:** Fedora 43+
**Maintainer:** Automated Signing System
