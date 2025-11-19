# MOK Systemd Integration Guide

Complete guide to the systemd-based automation and unit files.

## Quick Start

### Enable All Services

```bash
# Install all systemd units
sudo systemctl daemon-reload
sudo systemctl enable sign-nvidia-modules.service
sudo systemctl enable sign-nvidia-modules.timer
sudo systemctl enable sign-nvidia-modules.socket
sudo systemctl enable sign-nvidia-modules.path

# Start services
sudo systemctl start sign-nvidia-modules.timer
sudo systemctl start sign-nvidia-modules.socket
sudo systemctl start sign-nvidia-modules.path
```

### Test Services

```bash
# Check service status
sudo systemctl status sign-nvidia-modules.service

# Check timer next run
sudo systemctl status sign-nvidia-modules.timer
sudo systemctl list-timers sign-nvidia-modules.timer

# View logs
sudo journalctl -u sign-nvidia-modules.service -f
```

## Systemd Units Overview

### 1. Service Unit: `sign-nvidia-modules.service`

**Purpose**: Core signing operation

**Key Settings**:
- **Type**: `oneshot` - Runs once to completion
- **After**: `dracut-pre-build.service`, `network-online.target`
- **Condition**: Module files must exist
- **Restart**: `on-failure` with 30s interval, max 3 attempts
- **Timeout**: 5 minutes

**Execution Flow**:
1. Pre-check script: Validates system state, rate limiting, disk space
2. Main signing: `/usr/local/bin/sign-nvidia-modules.sh`
3. Post-verification: Verifies signatures, updates state
4. Environment: Sets `NVIDIA_SIGNING_STATE=success` on completion

**Sandboxing**:
- `ProtectSystem=strict` - Read-only filesystem except specified paths
- `ProtectHome=yes` - No home directory access
- `NoNewPrivileges=false` - Required for module signing
- `CapabilityBoundingSet=CAP_SYS_MODULE CAP_DAC_OVERRIDE ...`
- `MemoryDenyWriteExecute=yes`
- `RestrictNamespaces=yes`

**Logging**:
- `StandardOutput=journal`
- `StandardError=journal`
- `SyslogIdentifier=nvidia-signing`

### 2. Timer Unit: `sign-nvidia-modules.timer`

**Purpose**: Periodic re-signing verification every 6 hours

**Schedule**:
```
OnBootSec=5min           # First run: 5 minutes after boot
OnUnitActiveSec=6h       # Repeat: Every 6 hours
RandomizedDelaySec=15min # Jitter: ±15 minutes
```

**Features**:
- `Persistent=yes` - Runs missed windows if system offline
- `AccuracySec=1min` - Within 1 minute of scheduled time
- No user intervention needed - fully automatic

**Enable**:
```bash
sudo systemctl enable --now sign-nvidia-modules.timer
```

**Monitor**:
```bash
# List active timers
systemctl list-timers --all

# Check next execution
systemctl list-timers sign-nvidia-modules.timer

# View timer details
systemctl show sign-nvidia-modules.timer
```

### 3. Socket Unit: `sign-nvidia-modules.socket`

**Purpose**: On-demand activation for manual triggering

**Configuration**:
- Abstract socket: `@nvidia-signing`
- Max connections: 10
- Activates: `sign-nvidia-modules.service`

**Manual Trigger**:
```bash
# Method 1: Via systemd
sudo systemctl start sign-nvidia-modules.service

# Method 2: Direct socket connection (advanced)
echo "sign" | socat - ABSTRACT-CONNECT:nvidia-signing

# Method 3: Via launcher
sudo ./mok sign
```

**Enable**:
```bash
sudo systemctl enable --now sign-nvidia-modules.socket
```

### 4. Path Unit: `sign-nvidia-modules.path`

**Purpose**: Filesystem monitoring for module changes

**Watched Directories**:
- `/usr/lib/modules/%v/extra` - Main monitoring
- Specific files: `nvidia.ko`, `nvidia-drm.ko`, `nvidia-uvm.ko`

**Triggers On**:
- File creation
- File modification
- File removal

**Use Case**: Catches manual driver installations outside DNF

**Enable**:
```bash
sudo systemctl enable --now sign-nvidia-modules.path
```

**Monitor**:
```bash
# Check path state
systemctl status sign-nvidia-modules.path

# View triggered service
journalctl -u sign-nvidia-modules.path -f
```

### 5. Target Unit: `nvidia-signing.target`

**Purpose**: Organize all signing-related units

**Dependencies**:
- Requires: `sign-nvidia-modules.service`
- After: `sign-nvidia-modules.service`

**Usage**:
```bash
# Start all signing units together
sudo systemctl start nvidia-signing.target

# Check target status
sudo systemctl status nvidia-signing.target
```

### 6. Slice Unit: `system-nvidia-signing.slice`

**Purpose**: Resource control and limiting

**Limits**:
```
CPU:     50% maximum (prevents system slowdown)
Memory:  1GB hard limit, 1.2GB soft limit
I/O:     Weight 100 (balanced)
Tasks:   100 max concurrent
```

**Enables**:
- Prevents signing operations from consuming system resources
- Fair allocation among other services
- Monitoring and accounting

**Monitor**:
```bash
# View resource usage
systemctl status system-nvidia-signing.slice

# CPU usage
systemctl show system-nvidia-signing.slice --property=CPUUsageNSec

# Memory usage
systemctl show system-nvidia-signing.slice --property=MemoryCurrent
```

## Integration Points

### DNF Hook Integration

Still compatible with existing DNF hook:
- File: `/etc/dnf/plugins/post-transaction-actions.d/nvidia-signing.action`
- Triggers: NVIDIA driver/kernel package updates
- No changes needed for compatibility

### Boot Sequence

1. **dracut-pre-build.service** (dependency)
2. **network-online.target** (dependency)
3. **sign-nvidia-modules.service** (our service)
   - Pre-check validation
   - Module signing
   - Post-verification
4. **getty@tty1.service** (waits for completion)

### Monitoring and Alerts

**View Logs**:
```bash
# Recent entries
sudo journalctl -u sign-nvidia-modules -n 50

# Follow in real-time
sudo journalctl -u sign-nvidia-modules -f

# Since boot
sudo journalctl -u sign-nvidia-modules -b

# Specific date
sudo journalctl -u sign-nvidia-modules --since "2024-01-01"
```

**System Status**:
```bash
# All signing units
sudo systemctl list-units --all '*nvidia-signing*'

# Service details
sudo systemctl show sign-nvidia-modules.service

# Timer details
sudo systemctl show sign-nvidia-modules.timer
```

## Configuration Management

### Configuration File

Location: `/etc/nvidia-signing/nvidia-signing.conf`

Key settings:
```bash
# Enable/disable features
ENABLE_AUTO_SIGNING="yes"
ENABLE_TIMER="yes"
ENABLE_SOCKET_ACTIVATION="yes"
ENABLE_PATH_WATCHER="yes"

# Timer schedule
TIMER_INTERVAL="6h"

# Security
REQUIRE_SECURE_BOOT="no"
REQUIRE_MOK_ENROLLMENT="no"
```

### Tmpfiles Configuration

Location: `/etc/tmpfiles.d/nvidia-signing.conf`

Auto-creates runtime directories on every boot:
```
/run/nvidia-signing          (755)
/var/lib/nvidia-signing      (700)
/var/lib/nvidia-signing/backups (700)
/var/log/nvidia-signing      (700)
```

Run manually:
```bash
sudo systemd-tmpfiles --create /etc/tmpfiles.d/nvidia-signing.conf
```

## Customization

### Modify Timer Schedule

```bash
# Edit timer
sudo systemctl edit sign-nvidia-modules.timer

# Add custom settings:
[Timer]
OnBootSec=10min
OnUnitActiveSec=4h
RandomizedDelaySec=10min
```

### Modify Resource Limits

```bash
# Edit slice
sudo systemctl edit system-nvidia-signing.slice

# Increase memory limit:
[Slice]
MemoryLimit=2G
```

### Add Custom Pre/Post Hooks

```bash
# Edit service
sudo systemctl edit sign-nvidia-modules.service

# Add pre-execution
[Service]
ExecStartPre=/usr/local/lib/nvidia-signing/custom-pre-hook.sh

# Add post-execution
ExecStartPost=/usr/local/lib/nvidia-signing/custom-post-hook.sh
```

## Troubleshooting

### Service Won't Start

**Check status**:
```bash
sudo systemctl status sign-nvidia-modules.service
sudo journalctl -u sign-nvidia-modules.service -n 50
```

**Common issues**:
1. Modules don't exist: Install NVIDIA driver first
2. Keys missing: Generate signing keys
3. Disk full: Free up 100MB on root, 50MB on /boot
4. Rate limited: Wait 5 minutes, check `/var/lib/nvidia-signing/last-signing-attempt`

### Timer Not Running

**Check timer**:
```bash
sudo systemctl list-timers sign-nvidia-modules.timer

# Manually trigger for testing
sudo systemctl start sign-nvidia-modules.timer
```

**Enable if disabled**:
```bash
sudo systemctl enable sign-nvidia-modules.timer
sudo systemctl start sign-nvidia-modules.timer
```

### Path Unit Not Triggering

**Check path**:
```bash
sudo systemctl status sign-nvidia-modules.path
sudo journalctl -u sign-nvidia-modules.path
```

**Test path monitoring**:
```bash
# Copy a test file (simulates driver installation)
sudo cp /usr/lib/modules/*/extra/nvidia.ko /tmp/test-nvidia.ko
sudo cp /tmp/test-nvidia.ko /usr/lib/modules/$(uname -r)/extra/test.ko

# Should trigger signing service
sudo journalctl -u sign-nvidia-modules.service -n 10
```

### View Service Resources

**CPU and Memory Usage**:
```bash
# Real-time monitoring
sudo systemd-cgtop

# Or check slice
sudo systemctl show system-nvidia-signing.slice \
  --property CPUUsageNSec,MemoryCurrent,TasksCurrent
```

## Advanced Features

### Manual Service Restart

```bash
# Restart if stuck
sudo systemctl restart sign-nvidia-modules.service

# Force daemon reload (after manual edits)
sudo systemctl daemon-reload
```

### Disable Individual Units

```bash
# Disable timer (keep service)
sudo systemctl disable sign-nvidia-modules.timer

# Disable path watcher
sudo systemctl disable sign-nvidia-modules.path

# Disable socket activation
sudo systemctl disable sign-nvidia-modules.socket
```

### Run Signing Once Manually

```bash
# Via systemd
sudo systemctl start sign-nvidia-modules.service

# Via launcher
sudo ./mok sign

# Direct script
sudo /usr/local/bin/sign-nvidia-modules.sh
```

### View Complete System State

```bash
# All service files
sudo systemctl show-environment | grep NVIDIA

# Unit relationships
systemctl show sign-nvidia-modules.service --property=Requires,After,Wants

# Dependencies visualization
systemctl graph --system | grep nvidia
```

## Security Notes

### Capabilities

The service runs with minimal capabilities:
- `CAP_SYS_MODULE` - Load/unload kernel modules (required)
- `CAP_DAC_OVERRIDE` - Access protected files (required for signing)
- `CAP_DAC_READ_SEARCH` - Read protected files

### Sandboxing

- Filesystem: Strict read-only except signing paths
- Network: No network access during signing
- Memory: No execute-after-write (MemoryDenyWriteExecute)
- Namespaces: Restricted to prevent escape

### Audit Trail

All operations logged to:
1. Systemd journal: `/var/log/journal/`
2. Application log: `/var/log/nvidia-signing/`
3. Syslog: System syslog facility

## Performance Impact

Typical impact on system:
- **CPU**: <5% during signing (with 50% limit enforced)
- **Memory**: 50-200MB (with 1GB limit enforced)
- **I/O**: Minimal, limited to 1-2 seconds per module
- **Boot time**: +10-30 seconds (5 minute delay after boot)

## Monitoring and Alerts

### Enable Email Alerts (Optional)

```bash
# Edit service
sudo systemctl edit sign-nvidia-modules.service

# Add failure notification
[Unit]
OnFailure=email-admin@example.com.service
```

### Check Health

```bash
# All units healthy
sudo systemctl is-system-running

# Timer running
sudo systemctl is-active sign-nvidia-modules.timer

# Service operational
sudo systemctl is-enabled sign-nvidia-modules.service
```

## References

- [Systemd Unit Files](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- [Systemd Service](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Systemd Timer](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [Systemd Socket](https://www.freedesktop.org/software/systemd/man/systemd.socket.html)
- [Systemd Path](https://www.freedesktop.org/software/systemd/man/systemd.path.html)
- [Systemd Slice](https://www.freedesktop.org/software/systemd/man/systemd.slice.html)
- [Systemd Resource Control](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)

