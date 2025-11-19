# MOK Project Structure

## Directory Organization

```
mok/
├── bin/                          # Executable scripts
│   ├── sign-nvidia-modules.sh    # Main signing automation engine
│   ├── rollback-nvidia-signing.sh # Recovery and rollback utilities
│   ├── test-nvidia-signing.sh    # Comprehensive test suite (45+ tests)
│   └── install-nvidia-signing.sh # Installation and deployment script
│
├── config/                       # Configuration files
│   ├── nvidia-signing.action     # DNF post-transaction hook
│   └── sign-nvidia.service       # Systemd service definition
│
├── selinux/                      # Security policies
│   └── nvidia-signing.te         # SELinux policy module source
│
├── docs/                         # Documentation
│   ├── README.md                 # Complete feature documentation
│   ├── QUICKSTART.md             # 5-minute setup guide
│   ├── DEPLOYMENT_CHECKLIST.md  # Deployment verification steps
│   ├── PROJECT_SUMMARY.md        # Executive summary and metrics
│   └── INDEX.md                  # Documentation navigation guide
│
├── tests/                        # Test artifacts and results
│   └── (populated during test runs)
│
├── mok                           # Unified launch script (main entry point)
├── MOK.txt                       # Original AI automation requirements
├── STRUCTURE.md                  # This file
├── .gitignore                    # Git ignore patterns
└── README.md                     # Root-level documentation link

```

## Key Files by Purpose

### Launch Script
- **mok** - Central entry point for all operations
  - Modular command structure (sign, test, install, rollback, status, logs, docs)
  - Environment validation
  - Consistent logging and color output
  - Help system with examples

### Core Functionality Scripts (bin/)

**sign-nvidia-modules.sh** (~600 lines)
- Auto-detects Secure Boot and TPM2 status
- Discovers unsigned NVIDIA kernel modules
- Signs modules with SHA256 cryptography
- Creates pre-signing backups
- Regenerates initramfs for boot compatibility
- Comprehensive logging and state tracking
- Idempotent execution (safe to run multiple times)

**test-nvidia-signing.sh** (~700 lines)
- 45+ modular test cases organized by category:
  - System requirements validation
  - Secure Boot and TPM2 detection
  - Key management and permissions
  - Module discovery and classification
  - Signature verification
  - Systemd and DNF integration
  - Error handling and rollback capability
- Color-coded output with JSON reporting
- Complete test coverage analysis

**rollback-nvidia-signing.sh** (~400 lines)
- Emergency recovery system
- Backup verification and integrity checks
- Interactive recovery menu
- Automatic restoration mode (`--auto`)
- Full audit trail of recovery operations
- Graceful failure handling

**install-nvidia-signing.sh** (~500 lines)
- Automated deployment system
- Prerequisite validation
- Component installation to system paths
- Systemd service setup
- DNF hook configuration
- SELinux policy compilation and installation
- Directory and permission setup
- Installation verification tests

### Configuration Files (config/)

**sign-nvidia.service**
- Systemd oneshot service
- Triggers on boot and after network-online
- Strict security profile with sandboxing
- Systemd journal integration
- Configurable via `systemctl edit sign-nvidia.service`

**nvidia-signing.action**
- DNF post-transaction hook
- Automatic triggering on NVIDIA driver updates
- Transparent integration with package manager
- Zero manual intervention after updates

### Security Policies (selinux/)

**nvidia-signing.te**
- Custom SELinux policy module
- Process domain isolation
- Fine-grained capability restrictions
- TPM2 and EFI system access controls
- Optional but recommended for production

### Documentation (docs/)

**README.md** (26 KB)
- Complete feature overview
- System requirements and prerequisites
- 6-step installation procedure
- Configuration options and paths
- Usage examples with real output
- Extensive troubleshooting guide (10+ solutions)
- Complete recovery procedures
- Security best practices
- Architecture diagrams
- Advanced topics and integration examples
- Quick reference appendix

**QUICKSTART.md** (3.5 KB)
- 5-minute rapid setup guide
- Prerequisites validation
- Installation in 5 steps
- Key generation and enrollment
- Verification commands
- Common operations reference
- Quick troubleshooting table

**DEPLOYMENT_CHECKLIST.md** (12 KB)
- Pre-deployment verification
- Phase-by-phase checklist (pre-install, install, test, production)
- Testing and validation procedures
- Post-deployment monitoring
- Maintenance schedule
- Sign-off procedures

**PROJECT_SUMMARY.md** (15 KB)
- Executive summary
- Complete deliverables catalog
- Feature matrix with status
- Quality metrics (code, tests, docs, security)
- Implementation approach
- File structure and installation paths
- Operational commands reference
- Future enhancement roadmap

**INDEX.md** (12 KB)
- Navigation guide for all documentation
- Quick links by user type (admin, developer, operator)
- File listing with descriptions
- Project statistics
- Common commands reference
- Learning path recommendations
- Support resources

### Original Requirements

**MOK.txt** (4.4 KB)
- Original AI automation instruction document
- Step-by-step requirements breakdown
- Commands and logic for each phase
- Basic script template and testing suggestions
- Preserved for reference and requirements traceability

## File Organization Principles

### By Function
- **bin/** - Executable code
- **config/** - System configuration
- **docs/** - User documentation
- **selinux/** - Security policies
- **tests/** - Test artifacts

### By Concern
1. **Signing** - sign-nvidia-modules.sh
2. **Testing** - test-nvidia-signing.sh
3. **Recovery** - rollback-nvidia-signing.sh
4. **Installation** - install-nvidia-signing.sh
5. **Orchestration** - mok (launcher)

### By Deployment Path
- Development: Local files in project directory
- Installation: `/usr/local/bin/`, `/etc/systemd/system/`, etc.
- Runtime: `/var/lib/nvidia-signing/` and `/var/log/nvidia-signing/`

## Installation Directory Map

When installed system-wide (`sudo mok install`):

```
/usr/local/bin/
├── sign-nvidia-modules.sh
├── rollback-nvidia-signing.sh
├── test-nvidia-signing.sh
└── install-nvidia-signing.sh

/etc/systemd/system/
└── sign-nvidia.service

/etc/dnf/plugins/post-transaction-actions.d/
└── nvidia-signing.action

/usr/share/selinux/packages/
└── nvidia-signing/

/var/lib/nvidia-signing/
├── backups/              # Pre-signing module backups
├── state.json            # Execution state and statistics
└── ...

/var/log/nvidia-signing/
└── nvidia-signing-*.log  # Timestamped execution logs
```

## Unified Launch Script Interface

The `mok` script provides a modular interface:

```bash
mok <command> [options]
```

### Commands
- **sign** - Execute module signing process
- **test** - Run validation test suite
- **install** - Deploy system components (requires root)
- **rollback** - Recover from signing failures (requires root)
- **status** - Display system health and status
- **logs** - View recent execution logs
- **docs** - Display inline documentation
- **version** - Show version information
- **help** - Display usage help

### Example Usage
```bash
./mok help              # Show all commands
./mok status            # Check system configuration
sudo ./mok install      # Deploy to system
sudo ./mok sign         # Sign modules manually
./mok docs README       # View documentation
./mok test              # Run test suite
```

## Code Organization Highlights

### Modular Design
- Clear separation of concerns
- Each script has specific responsibility
- Shared patterns (logging, error handling)
- Standalone execution capability

### Error Handling
- Comprehensive input validation
- Atomic operations with rollback
- Detailed error messages
- Full audit trail logging

### Security
- Root-only where required
- No hardcoded secrets
- Pre-signing backups
- Cryptographic verification
- SELinux isolation optional but supported

### Maintainability
- Consistent code style
- Comprehensive comments
- Modular functions with clear purposes
- Helper functions for common tasks
- Debug logging with `DEBUG=1` flag

## Configuration and Customization

### Hard-coded Paths (in scripts)
Can be modified but should generally remain consistent:
- Key directory: `/etc/pki/akmods/certs/`
- Module directory: `/usr/lib/modules/$(uname -r)/extra/`
- State directory: `/var/lib/nvidia-signing/`
- Log directory: `/var/log/nvidia-signing/`

### Runtime Configuration
- **DEBUG=1** - Enable verbose debug output
- Environment variables passed to subscripts
- Systemd service settings editable via `systemctl edit`
- DNF hook triggers configurable in `.action` file

### System Integration Points
1. **Boot time** - Via systemd service (sign-nvidia.service)
2. **Post-update** - Via DNF hook (nvidia-signing.action)
3. **Manual** - Via `mok sign` or direct script execution
4. **Monitoring** - Via state.json and log files

## Quality Assurance

### Testing
- 45+ test cases covering all major functionality
- Prerequisite validation
- Integration testing with system components
- Error scenario testing
- Idempotency verification
- Rollback capability testing

### Documentation
- Complete user guides (README, QUICKSTART)
- Deployment procedures (DEPLOYMENT_CHECKLIST)
- Architecture documentation (PROJECT_SUMMARY)
- Navigation guide (INDEX)
- Inline code comments and help text

### Version Control Ready
- Clean directory structure
- .gitignore configured
- No generated artifacts tracked
- Original requirements preserved (MOK.txt)
- License and contribution files ready to add

## Next Steps for GitHub Publication

1. Add LICENSE file (recommend MIT or GPL-3.0)
2. Add CONTRIBUTING.md for contributor guidelines
3. Create GitHub Actions workflow for automated testing
4. Add CHANGELOG.md for version history
5. Create GitHub issue templates
6. Add security policy (SECURITY.md)
7. Include GitHub discussion settings
8. Set up project labels and milestones

See the "Prepare GitHub repository structure" section in the todo list for implementation.
