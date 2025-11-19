# NVIDIA Module Signing System - Deployment Checklist

## Pre-Deployment Phase

### System Requirements Verification

- [ ] OS: Confirm Fedora 43 installed
  ```bash
  cat /etc/os-release | grep -E "NAME|VERSION_ID"
  ```

- [ ] Firmware: Verify UEFI is present
  ```bash
  [ -d /sys/firmware/efi ] && echo "UEFI OK" || echo "UEFI Missing"
  ```

- [ ] Secure Boot: Check capability (may be disabled, but must be supported)
  ```bash
  mokutil --sb-state 2>/dev/null || echo "mokutil check failed"
  ```

- [ ] Kernel: Verify kernel-devel is appropriate version
  ```bash
  uname -r
  dnf list kernel-devel
  ```

### Package Requirements Verification

- [ ] Required packages installed
  ```bash
  dnf list installed kernel-devel dracut mokutil kmod | grep -E "kernel-devel|dracut|mokutil|kmod"
  ```

- [ ] Kernel sources available
  ```bash
  ls /usr/src/kernels/$(uname -r)/scripts/sign-file
  ```

- [ ] Optional packages (if SELinux enabled)
  ```bash
  [ "$(getenforce 2>/dev/null || echo 'Disabled')" != "Disabled" ] && \
  dnf list selinux-policy-devel | grep selinux-policy-devel
  ```

### System State Verification

- [ ] No security policies blocking script execution
  ```bash
  getenforce  # Should be Permissive, Enforcing, or Disabled
  ```

- [ ] Sufficient disk space in `/var` (minimum 5GB recommended)
  ```bash
  df -h /var | tail -1
  ```

- [ ] Sufficient disk space in `/boot` for initramfs regeneration
  ```bash
  df -h /boot | tail -1
  ```

- [ ] No pending system updates
  ```bash
  dnf check-update | wc -l
  ```

---

## Pre-Installation Phase

### File Verification

- [ ] All required files present
  ```bash
  cd /var/home/sanya/MOK
  for f in sign-nvidia-modules.sh rollback-nvidia-signing.sh test-nvidia-signing.sh \
           install-nvidia-signing.sh sign-nvidia.service nvidia-signing.action \
           nvidia-signing.te README.md QUICKSTART.md; do
    [ -f "$f" ] && echo "✓ $f" || echo "✗ $f MISSING"
  done
  ```

- [ ] Scripts have read permissions
  ```bash
  ls -la /var/home/sanya/MOK/*.sh
  ```

- [ ] No corrupted files
  ```bash
  file /var/home/sanya/MOK/*.sh | grep "Bourne-Again shell script"
  ```

### Permissions Verification

- [ ] Current user can execute scripts (will escalate to root)
  ```bash
  whoami
  [ "$EUID" -eq 0 ] && echo "Running as root (OK)" || echo "Not root (OK, will use sudo)"
  ```

### Backup and Restore Planning

- [ ] Plan for rollback location
  - [ ] At least 5GB available in `/var/lib` for backups
  - [ ] Backup strategy documented
  - [ ] Recovery procedure understood

---

## Installation Phase

### Pre-Installation Backup

- [ ] Create system snapshot (if using LVM/Btrfs)
  ```bash
  # For Btrfs:
  sudo btrfs subvolume snapshot / /mnt/snapshot-pre-nvidia-signing-$(date +%s)

  # For LVM:
  sudo lvcreate -L5G -s -n backup /dev/vg0/root
  ```

- [ ] Backup current kernel modules
  ```bash
  sudo tar czf /tmp/modules-backup-$(date +%Y%m%d).tar.gz \
    /usr/lib/modules/$(uname -r)/extra/nvidia* 2>/dev/null || true
  ```

### Installation Execution

- [ ] Run installation script
  ```bash
  sudo /var/home/sanya/MOK/install-nvidia-signing.sh
  ```

- [ ] Monitor installation progress
  ```bash
  # In another terminal:
  tail -f /tmp/nvidia-signing-install-*.log
  ```

- [ ] Verify installation completed successfully
  ```bash
  echo $?  # Should be 0
  ```

### Installation Verification

- [ ] Check all components installed
  ```bash
  ls -la /usr/local/bin/sign-nvidia*
  ls -la /etc/systemd/system/sign-nvidia.service
  ls -la /etc/dnf/plugins/post-transaction-actions.d/nvidia-signing.action
  ```

- [ ] Verify service is loaded
  ```bash
  systemctl list-unit-files | grep sign-nvidia
  ```

- [ ] Check script permissions (must be executable by root)
  ```bash
  stat -c "%a %U %G %n" /usr/local/bin/sign-nvidia-modules.sh
  # Should show: 755 root root
  ```

---

## Key Generation and Enrollment Phase

### Key Generation

- [ ] Check if keys already exist
  ```bash
  ls -la /etc/pki/akmods/certs/
  ```

- [ ] If keys don't exist, generate them
  ```bash
  sudo kmodgenca -a
  ```

- [ ] Verify keys were created
  ```bash
  ls -la /etc/pki/akmods/certs/private_key.priv
  ls -la /etc/pki/akmods/certs/public_key.der
  ```

- [ ] Check key permissions
  ```bash
  stat -c "%a %U %G %n" /etc/pki/akmods/certs/*
  # Private key should be 400, public key 444
  ```

### MOK Enrollment

- [ ] Enroll public key in MOK
  ```bash
  sudo mokutil --import /etc/pki/akmods/certs/public_key.der
  ```

- [ ] Set MOK enrollment password (temporary, for this boot only)

- [ ] Verify enrollment pending
  ```bash
  mokutil --list-new
  ```

- [ ] Reboot to complete enrollment
  ```bash
  sudo reboot
  ```

- [ ] At boot, enter MOK Manager:
  - Select "Enroll MOK"
  - Enter the password you set
  - Confirm enrollment

- [ ] After reboot, verify enrollment successful
  ```bash
  mokutil --list-enrolled | grep -A1 "NVIDIA"
  ```

---

## Testing and Validation Phase

### Basic Functionality Tests

- [ ] Run test suite
  ```bash
  sudo /usr/local/bin/test-nvidia-signing.sh
  ```

- [ ] Review test results
  ```bash
  cat /tmp/nvidia-signing-test-results-*.json | jq .
  ```

- [ ] All tests passed or appropriately skipped
  - [ ] No critical failures
  - [ ] Skipped tests documented in test output

### Module Signing Tests

- [ ] Check if NVIDIA modules exist
  ```bash
  find /usr/lib/modules/$(uname -r)/extra -name "*nvidia*.ko" -ls
  ```

- [ ] Check current signature status
  ```bash
  for mod in /usr/lib/modules/$(uname -r)/extra/nvidia*.ko; do
    echo "$(basename $mod): $(modinfo -F signer "$mod" 2>/dev/null || echo 'unsigned')"
  done
  ```

- [ ] Run signing manually
  ```bash
  sudo /usr/local/bin/sign-nvidia-modules.sh
  ```

- [ ] Verify signatures were applied
  ```bash
  for mod in /usr/lib/modules/$(uname -r)/extra/nvidia*.ko; do
    echo "$(basename $mod): $(modinfo -F signer "$mod" 2>/dev/null || echo 'unsigned')"
  done
  ```

### Systemd Service Tests

- [ ] Check service status
  ```bash
  sudo systemctl status sign-nvidia.service
  ```

- [ ] Verify service is enabled
  ```bash
  systemctl is-enabled sign-nvidia.service
  # Should return: enabled
  ```

- [ ] View recent service logs
  ```bash
  sudo journalctl -u sign-nvidia.service -n 50 --no-pager
  ```

- [ ] Manually start service
  ```bash
  sudo systemctl restart sign-nvidia.service
  ```

- [ ] Verify service completed
  ```bash
  sudo systemctl status sign-nvidia.service
  # Should show: Active: active (exited)
  ```

### DNF Integration Tests

- [ ] Verify DNF hook is installed
  ```bash
  cat /etc/dnf/plugins/post-transaction-actions.d/nvidia-signing.action
  ```

- [ ] Test with dummy update (if safe)
  ```bash
  # Skip this in production unless comfortable with test package update
  ```

- [ ] Check DNF logs for hook execution
  ```bash
  sudo journalctl -u dnf -n 20
  ```

### Secure Boot Verification

- [ ] Confirm Secure Boot status
  ```bash
  mokutil --sb-state
  ```

- [ ] List enrolled keys
  ```bash
  mokutil --list-enrolled
  ```

- [ ] Verify module signatures match enrolled key
  ```bash
  modinfo /usr/lib/modules/$(uname -r)/extra/nvidia.ko | grep signer
  ```

### Recovery System Tests

- [ ] Check backup directory
  ```bash
  sudo ls -la /var/lib/nvidia-signing/backups/
  ```

- [ ] Verify backups are valid
  ```bash
  sudo file /var/lib/nvidia-signing/backups/*
  ```

- [ ] Test recovery in safe environment (optional for production)
  ```bash
  # Do NOT do this in production without planning
  # sudo /usr/local/bin/rollback-nvidia-signing.sh --list
  ```

---

## Documentation and Training Phase

### Documentation Review

- [ ] README.md reviewed and understood
- [ ] QUICKSTART.md available to administrators
- [ ] DEPLOYMENT_CHECKLIST.md saved for reference
- [ ] Local documentation created (internal wiki/docs)

### Team Training

- [ ] Operations team trained on:
  - [ ] Service status checks
  - [ ] Log interpretation
  - [ ] Recovery procedures
  - [ ] Escalation procedures

- [ ] Create runbook for:
  - [ ] Daily monitoring
  - [ ] Troubleshooting common issues
  - [ ] Emergency recovery
  - [ ] Key rotation procedures

### Monitoring and Alerting Setup

- [ ] Log aggregation (if centralized logging)
  ```bash
  # Example for journalctl to rsyslog:
  # Configure /etc/systemd/journald.conf to forward to syslog
  ```

- [ ] Service monitoring alerts (Nagios/Zabbix/Prometheus)
  ```bash
  # Monitor: systemctl status sign-nvidia.service
  # Alert on: failed or inactive state
  ```

- [ ] Log monitoring alerts
  ```bash
  # Monitor: /var/log/nvidia-signing/*.log
  # Alert on: ERROR patterns
  ```

---

## Production Deployment Phase

### Pre-Production Checks

- [ ] All tests passed
- [ ] Documentation complete
- [ ] Team trained
- [ ] Monitoring configured
- [ ] Rollback plan documented

### Deployment Execution

- [ ] Deploy to first test system
  - [ ] Monitor for 24 hours
  - [ ] Verify automatic signing on boot
  - [ ] Verify automatic signing on updates

- [ ] Deploy to additional test systems
  - [ ] At least 3-5 test systems recommended
  - [ ] Various hardware configurations if possible

- [ ] Monitor test deployment phase
  - [ ] Daily logs review
  - [ ] Weekly status summary

- [ ] Deploy to production
  - [ ] Staggered rollout (if managing multiple systems)
  - [ ] Maintain change log
  - [ ] Document any issues encountered

### Post-Deployment Monitoring (First Month)

- [ ] Daily: Review service logs
  ```bash
  sudo journalctl -u sign-nvidia.service --since "24 hours ago" | grep -E "ERROR|FAILED|WARNING"
  ```

- [ ] Weekly: Full status check
  ```bash
  sudo /usr/local/bin/test-nvidia-signing.sh | tail -20
  ```

- [ ] Monthly: Comprehensive review
  - [ ] Test recovery procedures (lab environment only)
  - [ ] Review and update documentation
  - [ ] Security audit of logs

---

## Post-Deployment Phase

### Operational Handoff

- [ ] Operations team has:
  - [ ] Access to all scripts and tools
  - [ ] Copies of documentation
  - [ ] Contact information for escalation
  - [ ] Runbooks for common procedures

- [ ] Monitoring and alerting:
  - [ ] Configured and tested
  - [ ] Team trained on alerts
  - [ ] Alert thresholds documented

### Maintenance Schedule

- [ ] Monthly review:
  - [ ] [ ] Check service health
  - [ ] [ ] Review logs for errors
  - [ ] [ ] Verify backup integrity

- [ ] Quarterly review:
  - [ ] [ ] Test recovery procedures (lab only)
  - [ ] [ ] Review security logs
  - [ ] [ ] Plan any updates/improvements

- [ ] Annual review:
  - [ ] [ ] Full system audit
  - [ ] [ ] Security review
  - [ ] [ ] Capacity planning
  - [ ] [ ] Disaster recovery drill

### Documentation Updates

- [ ] Keep documentation current:
  - [ ] Script versions documented
  - [ ] Changes logged
  - [ ] Known issues maintained
  - [ ] FAQs updated based on support tickets

---

## Rollback Procedures

### If Installation Fails

- [ ] Stop service
  ```bash
  sudo systemctl stop sign-nvidia.service
  ```

- [ ] Restore from backup
  ```bash
  sudo /var/home/sanya/MOK/rollback-nvidia-signing.sh --auto
  ```

- [ ] Revert system to snapshot (if available)
  ```bash
  # For Btrfs: restore subvolume
  # For LVM: restore logical volume snapshot
  ```

### If Issues Appear After Installation

- [ ] Check logs first
  ```bash
  sudo journalctl -u sign-nvidia.service
  sudo tail -f /var/log/nvidia-signing/*.log
  ```

- [ ] Try automatic recovery
  ```bash
  sudo /usr/local/bin/rollback-nvidia-signing.sh --auto
  ```

- [ ] If needed, disable service temporarily
  ```bash
  sudo systemctl disable sign-nvidia.service
  ```

- [ ] Restore system from backup if necessary

### Success Criteria for Rollback

- [ ] Modules return to signed state
- [ ] System boots without errors
- [ ] NVIDIA drivers function
- [ ] No corruption detected

---

## Sign-Off

### Pre-Deployment Sign-Off

- [ ] System Administrator: _________________ Date: _______
- [ ] Security Officer: _________________ Date: _______
- [ ] Operations Manager: _________________ Date: _______

### Post-Deployment Sign-Off

- [ ] All tests passed: _________________ Date: _______
- [ ] No critical issues: _________________ Date: _______
- [ ] Team trained: _________________ Date: _______
- [ ] Monitoring configured: _________________ Date: _______
- [ ] Documentation complete: _________________ Date: _______

---

## Notes and Issues Log

| Date | Issue | Status | Resolution | Contact |
|------|-------|--------|------------|---------|
|      |       |        |            |         |
|      |       |        |            |         |
|      |       |        |            |         |

---

**Deployment Checklist Version:** 1.0.0
**Last Updated:** November 2024
**Maintained By:** System Administration Team
