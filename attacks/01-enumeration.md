# 01 — Domain Enumeration

## Overview

Before attacking, map out the entire domain: users, groups, computers, trusts, ACLs, and delegation settings.

## Tools

- **BloodHound + SharpHound** — graph-based AD analysis
- **PowerView** — PowerShell enumeration (PowerSploit)
- **ldapsearch / ADExplorer** — raw LDAP queries

---

## BloodHound Collection

```powershell
# On WS-01 as attacker.01
. .\SharpHound.ps1
Invoke-BloodHound -CollectionMethod All -Domain corp.local -OutputDirectory C:\loot\
```

Upload the resulting ZIP to the BloodHound GUI.

### Key BloodHound Queries

```cypher
-- Find shortest path from attacker.01 to Domain Admins
MATCH (u:User {name:"ATTACKER.01@CORP.LOCAL"}),(g:Group {name:"DOMAIN ADMINS@CORP.LOCAL"}),
      p=shortestPath((u)-[*1..]->(g))
RETURN p

-- All Kerberoastable users
MATCH (u:User {hasspn:true}) WHERE NOT u.name STARTS WITH "krbtgt" RETURN u.name, u.serviceprincipalnames

-- All AS-REP Roastable users
MATCH (u:User {dontreqpreauth:true}) RETURN u.name

-- Computers with unconstrained delegation
MATCH (c:Computer {unconstraineddelegation:true}) RETURN c.name

-- Find DCSync rights
MATCH p=(n)-[:GetChanges|GetChangesAll*1..]->(d:Domain) RETURN p

-- Find all paths to Enterprise Admins
MATCH (n),(m:Group {name:"ENTERPRISE ADMINS@CORP.LOCAL"}),
      p=shortestPath((n)-[*1..]->(m))
WHERE NOT n=m RETURN p LIMIT 25
```

---

## PowerView Enumeration

```powershell
Import-Module .\PowerView.ps1

# Domain info
Get-Domain
Get-DomainController
Get-DomainTrust

# Users
Get-DomainUser | Select-Object SamAccountName, Description, MemberOf
Get-DomainUser -SPN | Select-Object SamAccountName, ServicePrincipalName    # Kerberoastable
Get-DomainUser -PreauthNotRequired | Select-Object SamAccountName           # AS-REP

# Groups
Get-DomainGroup | Select-Object SamAccountName, Description
Get-DomainGroupMember "Domain Admins"

# Computers
Get-DomainComputer | Select-Object Name, OperatingSystem, DNSHostName
Get-DomainComputer -Unconstrained                    # Unconstrained delegation
Get-DomainComputer -TrustedToAuth                    # Constrained delegation

# ACLs
Find-InterestingDomainAcl -ResolveGUIDs | Where-Object {
    $_.IdentityReferenceName -notmatch "^(DnsAdmins|SELF|System|Domain Admins|Enterprise Admins|Domain Controllers|Everyone|Administrators|Creator Owner)$"
}

# Credentials in attributes
Get-DomainUser | Where-Object { $_.Description -match "pass" }
```

---

## LDAP Enumeration (Linux / Impacket)

```bash
# Enumerate all users
ldapsearch -x -H ldap://192.168.56.10 -D "corp\attacker.01" -w 'p@ssw0rd' \
  -b "DC=corp,DC=local" "(objectClass=user)" sAMAccountName description

# Find accounts with SPN set
ldapsearch -x -H ldap://192.168.56.10 -D "corp\attacker.01" -w 'p@ssw0rd' \
  -b "DC=corp,DC=local" "(servicePrincipalName=*)" sAMAccountName servicePrincipalName

# Enum via Impacket
GetADUsers.py -all corp.local/attacker.01:p@ssw0rd -dc-ip 192.168.56.10
```

---

## What to Look For

| Finding                        | Next Attack                    |
|--------------------------------|--------------------------------|
| Users with SPNs                | Kerberoasting (02)             |
| Users with DoesNotRequirePreAuth | AS-REP Roasting (03)         |
| Computers with unconstrained delegation | Delegation attacks (04) |
| Interesting ACLs (WriteDACL, GenericAll) | ACL attacks (05)   |
| Weak passwords in Description  | Password spray                 |
| Cross-domain trusts            | Cross-domain attacks (08)      |
