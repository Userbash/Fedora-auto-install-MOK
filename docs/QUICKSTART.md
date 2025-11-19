# Quick Start Guide - NVIDIA Module Signing System

## 5-Minute Installation

### Prerequisites Check (1 min)

```bash
# Verify you're on Fedora with Secure Boot
cat /etc/os-release | grep VERSION_ID
mokutil --sb-state
```

### Installation (2 min)

```bash
# Make scripts executable
chmod +x /var/home/sanya/MOK/*.sh

# Run installer as root
sudo /var/home/sanya/MOK/install-nvidia-signing.sh
```

### Key Setup (1 min)

```bash
# Generate signing keys (if not already done)
sudo kmodgenca -a

# Enroll in MOK
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
# Follow prompts and set a temporary password

# Reboot
sudo reboot
```

When rebooted, you'll see MOK Manager. Select "Enroll MOK" and enter your password.

### Verification (1 min)

```bash
# After reboot, verify installation
sudo systemctl status sign-nvidia.service
sudo /usr/local/bin/test-nvidia-signing.sh
```

---

## Common Operations

### Check Module Status

```bash
# See if modules are signed
modinfo /usr/lib/modules/$(uname -r)/extra/nvidia.ko | grep signer
```

**Expected output:** Either shows a signer name (signed) or nothing (unsigned)

### Sign Modules Manually

```bash
sudo /usr/local/bin/sign-nvidia-modules.sh
```

Automatically:
- Detects Secure Boot status
- Finds unsigned NVIDIA modules
- Signs them with enrolled keys
- Updates initramfs

### View Logs

```bash
# Recent activity
sudo journalctl -u sign-nvidia.service -n 20

# Detailed logs
sudo tail -f /var/log/nvidia-signing/*.log

# All recent operations
sudo cat /var/lib/nvidia-signing/state.json | jq .
```

### If Something Goes Wrong

**Automatic recovery:**
```bash
sudo /usr/local/bin/rollback-nvidia-signing.sh --auto
```

**Interactive recovery:**
```bash
sudo /usr/local/bin/rollback-nvidia-signing.sh
```

---

## What Happens Automatically

### On Boot
✓ System detects NVIDIA modules
✓ Checks if they're signed
✓ Signs any unsigned ones
✓ Updates boot image

### After Driver Updates
✓ System automatically runs after `dnf update`
✓ Signs new or updated modules
✓ No manual action needed

### On Demand
```bash
sudo sign-nvidia-modules.sh
```

---

## Troubleshooting Quick Reference

| Issue | Check | Fix |
|-------|-------|-----|
| Service won't start | `systemctl status sign-nvidia.service` | Generate and enroll keys |
| Modules still unsigned | `modinfo` output | Reboot to complete MOK enrollment |
| High CPU on boot | `top` command | Normal - initramfs regeneration |
| Keys not working | `mokutil --list-enrolled` | Re-enroll keys via `mokutil` |

---

## Key Files

```
/usr/local/bin/
  ├── sign-nvidia-modules.sh      ← Main script
  ├── rollback-nvidia-signing.sh  ← Recovery
  └── test-nvidia-signing.sh      ← Tests

/var/log/nvidia-signing/          ← Application logs
/var/lib/nvidia-signing/          ← Backups and state
```

---

## Next Steps

1. **Run tests to verify everything works:**
   ```bash
   sudo /usr/local/bin/test-nvidia-signing.sh
   ```

2. **Monitor automatic operation:**
   ```bash
   sudo journalctl -u sign-nvidia.service -f
   ```

3. **Keep system updated:**
   ```bash
   sudo dnf update -y
   ```

---

## Support

- **Full documentation:** See `README.md`
- **View logs:** `sudo journalctl -u sign-nvidia.service`
- **Report issues:** Attach output from `test-nvidia-signing.sh`

---

**Version:** 1.0.0
**Estimated setup time:** 10 minutes (including reboot)
**Required reboots:** 1 (for MOK enrollment)
