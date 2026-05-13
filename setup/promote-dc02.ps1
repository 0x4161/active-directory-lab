#Requires -RunAsAdministrator

# Promote DC-02 as Child Domain Controller for dev.corp.local
# Prerequisites:
#   - Static IP set to 192.168.56.20
#   - DNS pointing to 192.168.56.10 (DC-01)
#   - DC-01 must be running and reachable
#   - IPv6 disabled on all adapters
#   - NAT adapter has static IP (not DHCP)

param(
    [string]$ChildDomainName = "dev",
    [string]$ParentDomain    = "corp.local",
    [string]$SafeModePassword = "p@ssw0rd",
    [string]$ParentAdminUser  = "corp\Administrator",
    [string]$ParentAdminPass  = "p@ssw0rd"
)

Write-Host "[*] Verifying connectivity to DC-01..." -ForegroundColor Cyan
if (-not (Test-Connection -ComputerName 192.168.56.10 -Count 2 -Quiet)) {
    Write-Error "Cannot reach DC-01 (192.168.56.10). Check DNS and network settings."
    exit 1
}

Write-Host "[*] Installing AD DS role..." -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services, RSAT-AD-PowerShell -IncludeManagementTools -ErrorAction Stop

Import-Module ADDSDeployment

$SecurePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
$SecureAdminPass = ConvertTo-SecureString $ParentAdminPass -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($ParentAdminUser, $SecureAdminPass)

Write-Host "[*] Promoting to Child Domain DC: $ChildDomainName.$ParentDomain" -ForegroundColor Cyan

Install-ADDSDomain `
    -NewDomainName $ChildDomainName `
    -ParentDomainName $ParentDomain `
    -DomainType ChildDomain `
    -SafeModeAdministratorPassword $SecurePassword `
    -Credential $Credential `
    -DomainMode WinThreshold `
    -InstallDns `
    -CreateDnsDelegation `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force `
    -NoRebootOnCompletion:$false

# VM reboots automatically.
# After reboot, run: Setup-DevCorpLocal.ps1
