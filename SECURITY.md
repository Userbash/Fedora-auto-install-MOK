# Security Policy

## Overview

MOK (NVIDIA Module Auto-Signing System) takes security seriously. This document describes our security policies and procedures.

## Supported Versions

| Version | Supported          | EOL Date   |
|---------|------------------|------------|
| 1.0.x   | ✅ Yes            | 2026-11-19 |
| < 1.0   | ❌ No             | N/A        |

## Reporting Security Vulnerabilities

**IMPORTANT:** Do not report security vulnerabilities through public GitHub issues.

Instead, please report security vulnerabilities by emailing:
```
security@[maintainer-email-domain]
```

**Include the following information:**

1. Type of vulnerability (e.g., command injection, privilege escalation)
2. Location of the vulnerability (file, line number, or description)
3. Proof of concept or reproduction steps
4. Potential impact assessment
5. Suggested fix (if available)

**Expected Response Timeline:**

- **Acknowledgment**: Within 24 hours
- **Initial Assessment**: Within 72 hours
- **Security Patch**: Within 14 days for critical issues
- **Public Disclosure**: After fix is released or 90 days, whichever is first

## Security Features

### 1. Access Control

- ✅ Root privilege enforcement for sensitive operations
- ✅ User validation before critical actions
- ✅ Environment variable validation
- ✅ Secure temporary file handling with restricted permissions

### 2. Cryptography

- ✅ SHA256 signing algorithm (industry standard)
- ✅ Hardware-backed key storage via TPM2
- ✅ SELinux policies for process isolation
- ✅ Secure key enrollment via MOK (Machine Owner Key)

### 3. Input Validation

- ✅ No shell metacharacter injection vulnerabilities
- ✅ Proper quoting of all variable expansions
- ✅ Path validation prevents directory traversal
- ✅ Command validation before execution

### 4. Error Handling

- ✅ Comprehensive error logging
- ✅ No information disclosure in error messages
- ✅ Graceful failure with rollback capability
- ✅ Pre-operation backups prevent data loss

### 5. Audit Trail

- ✅ Timestamped logs of all operations
- ✅ Systemd journal integration for centralized logging
- ✅ JSON state files for tracking changes
- ✅ Complete module signature history

## Security Best Practices

### For Users

1. **Update Regularly**
   ```bash
   git pull origin main
   sudo ./mok install  # Re-install to get latest version
   ```

2. **Verify Installation**
   ```bash
   ./mok test        # Run test suite
   ./mok status      # Verify system health
   ```

3. **Monitor Logs**
   ```bash
   ./mok logs        # View recent execution logs
   journalctl -u sign-nvidia-modules  # View systemd logs
   ```

4. **Backup Modules**
   ```bash
   sudo cp -r /lib/modules/*/extra/nvidia* ~/nvidia-backup/
   ```

5. **Secure Boot Best Practices**
   - Keep Secure Boot enabled in BIOS
   - Don't disable Secure Boot to bypass signing
   - Keep boot firmware updated
   - Use strong BIOS/UEFI passwords

### For Developers

1. **Code Review**
   - All PRs require security review
   - Check for shellcheck warnings
   - Verify no hardcoded secrets

2. **Testing**
   - Run full test suite before commit
   - Test with SE Linux enabled and disabled
   - Test with Secure Boot enabled and disabled

3. **Dependency Management**
   - Minimize external dependencies
   - Pin versions in installation scripts
   - Regular security updates of dependencies

## Known Security Considerations

### Secure Boot

**Dependency**: MOK requires Secure Boot for full security value

- If Secure Boot is disabled, module signing provides no protection
- Attackers can still load unsigned malicious modules
- Re-enable Secure Boot in BIOS for proper security

**Mitigation**:
```bash
# Check Secure Boot status
./mok status | grep "Secure Boot"
```

### TPM2 Hardware

**Optional but Recommended**: TPM2 enhances security

- TPM2 stores keys more securely than filesystem
- Enables attestation and secure measurement
- Not required for basic module signing

**Fallback**: System works without TPM2 but with reduced security guarantees

### Root Access

**Required**: MOK signing operations require root

- Installation requires `sudo`
- Systemd timer runs as root
- System assumes root is trusted

**Trust Model**: This is standard for kernel module management

### Key Management

**Security Notes**:
- Private keys stored in `/etc/nvidia-signing/` (700 permissions)
- Only root and systemd can read keys
- Keys should be backed up securely
- Lost keys require reinstallation

## Compliance

### Standards Met

- ✅ **Secure Boot**: Follows UEFI Secure Boot specification
- ✅ **TPM2**: Uses TCG TPM2 spec for hardware acceleration
- ✅ **SELinux**: Includes mandatory access control policy
- ✅ **Linux Standard Base**: Compatible with Fedora packaging

### Security Scanning

This project:
- Uses ShellCheck for bash code quality
- Follows CII Best Practices recommendations
- Passes basic security linting

**Manual Review**: The codebase is intentionally simple (< 3000 SLOC) for auditability

## Vulnerability Disclosure Examples

### Well-Known Vulnerabilities (Examples)

Here are examples of security issues we take seriously:

1. **Command Injection**
   - Risk: Attacker can inject shell commands
   - Example: Unquoted variables in system() calls
   - Status: ✅ Not present in MOK (all vars properly quoted)

2. **Privilege Escalation**
   - Risk: Unprivileged user gains root access
   - Example: World-writable config files
   - Status: ✅ Not present (all critical files 700/600)

3. **Unauthorized Module Loading**
   - Risk: Loading of unsigned malicious modules
   - Example: Secure Boot disabled or bypassed
   - Status: ✅ Protected (Secure Boot enforcement)

4. **Key Compromise**
   - Risk: Signing key stolen or exposed
   - Example: Keys in world-readable files
   - Status: ✅ Protected (root-only access, TPM2 support)

## Incident Response

### Response Plan

1. **Report Received** → Acknowledge within 24 hours
2. **Triage** → Assess severity and impact
3. **Development** → Fix vulnerability in isolated branch
4. **Testing** → Verify fix with security tests
5. **Release** → Publish security patch release
6. **Disclosure** → Public security advisory
7. **Follow-up** → Monitor for similar issues

### Severity Levels

- **Critical**: Remote code execution, privilege escalation (CVSS 9.0+)
  - Fix timeframe: 48-72 hours

- **High**: Denial of service, information disclosure (CVSS 7.0-8.9)
  - Fix timeframe: 1 week

- **Medium**: Partial functionality loss, minor data exposure (CVSS 4.0-6.9)
  - Fix timeframe: 2-4 weeks

- **Low**: Minor issues, hardening improvements (CVSS < 4.0)
  - Fix timeframe: Next regular release

## Security Resources

### For More Information

- [OWASP Top 10](https://owasp.org/www-project-top-ten/) - Web security
- [CII Best Practices](https://bestpractices.coreinfrastructure.org/) - Open source security
- [Linux Kernel Security](https://www.kernel.org/security/) - Kernel security
- [Secure Boot Documentation](https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/uefi.rst)

### Related Tools

- **ShellCheck** - Bash code quality analysis
- **mokutil** - MOK/Secure Boot administration
- **tpm2-tools** - TPM2 hardware interaction
- **SELinux tools** - Mandatory access control

## Thank You

Thank you for helping keep MOK secure. We appreciate responsible vulnerability disclosure.

---

**Document Version**: 1.0
**Last Updated**: November 19, 2025
**Maintained By**: MOK Project Maintainers
**License**: MIT (same as MOK project)
