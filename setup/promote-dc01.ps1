#Requires -RunAsAdministrator

# Promote DC-01 as Forest Root Domain Controller for corp.local
# Run on a fresh Windows Server 2019 VM.
# Static IP must be set to 192.168.56.10 before running this.

param(
    [string]$DomainName = "corp.local",
    [string]$NetbiosName = "CORP",
    [string]$SafeModePassword = "p@ssw0rd"
)

Write-Host "[*] Installing AD DS role..." -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop

Import-Module ADDSDeployment

$SecurePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

Write-Host "[*] Promoting to Forest Root DC: $DomainName" -ForegroundColor Cyan

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -SafeModeAdministratorPassword $SecurePassword `
    -DomainMode WinThreshold `
    -ForestMode WinThreshold `
    -InstallDns `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force `
    -NoRebootOnCompletion:$false

# VM will reboot automatically after promotion completes.
# After reboot, run: Setup-CorpLocal.ps1
