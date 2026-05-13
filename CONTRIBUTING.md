# Contributing

Contributions are welcome. This lab is for educational purposes — all additions should serve that goal.

## What We Accept

- New attack scenarios with working PoC commands
- Improvements to setup scripts (idempotency, error handling)
- Additional BloodHound queries or PowerView one-liners
- Fixes for real bugs or broken configurations
- Documentation improvements

## What We Don't Accept

- Real malware samples
- Techniques targeting production environments without authorization
- Credentials, keys, or secrets

## How to Contribute

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/add-esc9`
3. Make your changes
4. Test against a fresh lab deployment
5. Submit a pull request with a clear description

## Attack Scenario Format

When adding a new attack, follow the pattern in `attacks/02-kerberoasting.md`:

```markdown
# Attack Name

## Overview
## Prerequisites
## Step-by-Step
## Detection
## Remediation
```

## Script Standards

- All PowerShell scripts must be idempotent (safe to run multiple times)
- Use `#Requires -RunAsAdministrator` where needed
- Test on Windows Server 2019
- No hardcoded paths outside the lab network range (192.168.56.0/24)
