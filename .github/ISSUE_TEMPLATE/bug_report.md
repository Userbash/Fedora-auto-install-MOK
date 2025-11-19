---
name: Bug Report
about: Report a bug to help us improve
title: "[BUG] "
labels: bug
assignees: ''

---

## Description
<!-- Clear description of the bug -->

## Steps to Reproduce
<!-- How to recreate the issue -->
1.
2.
3.

## Expected Behavior
<!-- What should happen -->

## Actual Behavior
<!-- What actually happens -->

## System Information
- **OS:** Fedora 43
- **Kernel:** <!-- output of: uname -r -->
- **Hardware:** <!-- CPU/GPU info if relevant -->
- **MOK Version:** <!-- output of: ./mok version -->

## Test Results
<!-- Run these and share output: -->
```bash
./mok status
sudo ./mok test
./mok logs
```

### Status Output
```
[Paste output from: ./mok status]
```

### Test Results
```
[Paste output from: sudo ./mok test]
```

### Recent Logs
```
[Paste output from: ./mok logs]
```

## Debug Output
<!-- If applicable, run with debug and share output: -->
```bash
sudo DEBUG=1 ./mok sign
```

### Debug Output
```
[Paste debug output here]
```

## Additional Context
<!-- Any other relevant information -->

## Checklist
- [ ] I've checked existing issues for duplicates
- [ ] I've run `sudo ./mok test` and reviewed results
- [ ] I've included system information
- [ ] I've included relevant logs or debug output
