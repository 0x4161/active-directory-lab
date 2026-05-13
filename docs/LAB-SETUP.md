# Lab Setup Guide — Build From Scratch

This guide walks through building the full 3-VM lab manually.

---

## Overview

| Step | Machine | Action                              |
|------|---------|-------------------------------------|
| 1    | Host    | Create VMs in VirtualBox            |
| 2    | DC-01   | Install Windows Server 2019         |
| 3    | DC-01   | Configure static IP                 |
| 4    | DC-01   | Promote to Forest Root DC           |
| 5    | DC-01   | Run Setup-CorpLocal.ps1             |
| 6    | DC-02   | Install Windows Server 2019         |
| 7    | DC-02   | Configure static IP + DNS           |
| 8    | DC-02   | Promote to Child Domain DC          |
| 9    | DC-02   | Run Setup-DevCorpLocal.ps1          |
| 10   | WS-01   | Install Windows 10/11               |
| 11   | WS-01   | Configure static IP + DNS           |
| 12   | WS-01   | Join corp.local domain              |

---

## Step 1: Create VMs

In VirtualBox, create 3 VMs:

| VM    | OS                      | RAM  | CPU | Disk  |
|-------|-------------------------|------|-----|-------|
| DC-01 | Windows Server 2019     | 4 GB | 2   | 60 GB |
| DC-02 | Windows Server 2019     | 4 GB | 2   | 60 GB |
| WS-01 | Windows 10 or 11        | 4 GB | 2   | 60 GB |

For each VM > Settings > Network:
- Adapter 1: Host-Only > `vboxnet0`
- Adapter 2: NAT

---

## Step 2: Install Windows Server 2019 on DC-01

1. Attach Windows Server 2019 ISO
2. Install "Windows Server 2019 Standard (Desktop Experience)"
3. Set Administrator password: `p@ssw0rd`
4. Complete setup wizard

---

## Step 3: Configure DC-01 Static IP

Open PowerShell as Administrator:

```powershell
$nic = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -like "*Host-Only*" }).Name
New-NetIPAddress -InterfaceAlias $nic -IPAddress 192.168.56.10 -PrefixLength 24 -DefaultGateway 192.168.56.1
Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses "127.0.0.1"
Rename-Computer -NewName "DC-01" -Force
Restart-Computer -Force
```

---

## Step 4: Promote DC-01 to Forest Root

Copy and run `setup/promote-dc01.ps1`:

```powershell
# Or run manually:
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName "corp.local" `
    -DomainNetbiosName "CORP" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force) `
    -InstallDns `
    -Force
```

VM will reboot automatically. Wait 2-3 minutes.

---

## Step 5: Run Setup-CorpLocal.ps1 on DC-01

Copy `scripts/Setup-CorpLocal.ps1` to DC-01 and run as Domain Admin:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Setup-CorpLocal.ps1
```

This creates all users, groups, OUs, SPNs, ACLs, and ADCS misconfigurations.

Expected runtime: 3-5 minutes.

---

## Step 6: Install Windows Server 2019 on DC-02

Same as Step 2. Set Administrator password: `p@ssw0rd`.

---

## Step 7: Configure DC-02 Static IP + DNS

**Critical:** DNS must point to DC-01 (192.168.56.10) before promotion.

```powershell
# Find the host-only adapter
Get-NetAdapter | Select-Object Name, Status, InterfaceDescription

# Set static IP (adjust adapter name as shown above)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.56.20 -PrefixLength 24 -DefaultGateway 192.168.56.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "192.168.56.10"

# Disable IPv6 on all adapters
Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6
Disable-NetAdapterBinding -Name "Ethernet 2" -ComponentID ms_tcpip6

# Set static IP on NAT adapter (prevents promotion warning)
netsh interface ipv4 set address name="Ethernet 2" static 10.0.3.15 255.255.255.0 10.0.3.2

Rename-Computer -NewName "DC-02" -Force
Restart-Computer -Force
```

Verify connectivity after reboot:
```powershell
nslookup corp.local 192.168.56.10
Test-Connection -ComputerName 192.168.56.10 -Count 2
```

---

## Step 8: Promote DC-02 to Child Domain

Copy and run `setup/promote-dc02.ps1`:

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
Install-ADDSDomain `
    -NewDomainName "dev" `
    -ParentDomainName "corp.local" `
    -DomainType ChildDomain `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force) `
    -Credential (Get-Credential "corp\Administrator") `
    -InstallDns `
    -Force
```

When prompted for credentials, enter: `corp\Administrator` / `p@ssw0rd`

VM reboots automatically. Wait 3-5 minutes for full sync.

---

## Step 9: Run Setup-DevCorpLocal.ps1 on DC-02

Copy `scripts/Setup-DevCorpLocal.ps1` to DC-02:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Setup-DevCorpLocal.ps1
```

---

## Step 10: Install Windows 10/11 on WS-01

Attach ISO, install Windows, set local Administrator: `p@ssw0rd`.

---

## Step 11: Configure WS-01 Static IP + DNS

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.56.30 -PrefixLength 24 -DefaultGateway 192.168.56.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "192.168.56.10"
```

---

## Step 12: Join WS-01 to corp.local

```powershell
Add-Computer -DomainName "corp.local" -Credential (Get-Credential "corp\Administrator") -Restart
```

Enter: `corp\Administrator` / `p@ssw0rd`

After reboot, log in as: `corp\attacker.01` / `p@ssw0rd`

---

## Verification

After all steps complete, run `scripts/lab-status.sh` from the host, or from WS-01:

```powershell
# Check domain connectivity
nltest /sc_verify:corp.local

# List domain users
Get-ADUser -Filter * -SearchBase "DC=corp,DC=local" | Select-Object SamAccountName

# Check ADCS
certutil -ping
```

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
