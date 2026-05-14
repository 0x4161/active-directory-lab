#Requires -RunAsAdministrator
# Vagrant provisioner for DC-01
# Installs AD DS and promotes to Forest Root DC (corp.local)
# Vagrant handles the reboot via 'vagrant-reload' after this script.

Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "[*] Installing AD DS role..." -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop

Import-Module ADDSDeployment

$SafePass = ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force

Write-Host "[*] Promoting to Forest Root DC: corp.local" -ForegroundColor Cyan

Install-ADDSForest `
    -DomainName                    "corp.local" `
    -DomainNetbiosName             "CORP" `
    -SafeModeAdministratorPassword $SafePass `
    -DomainMode                    WinThreshold `
    -ForestMode                    WinThreshold `
    -InstallDns `
    -CreateDnsDelegation:$false `
    -DatabasePath                  "C:\Windows\NTDS" `
    -LogPath                       "C:\Windows\NTDS" `
    -SysvolPath                    "C:\Windows\SYSVOL" `
    -NoRebootOnCompletion:$true `
    -Force

Write-Host "[+] DC-01 promotion complete. Vagrant will now reboot..." -ForegroundColor Green
