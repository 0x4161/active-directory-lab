#Requires -RunAsAdministrator

# Join WS-01 to the corp.local domain as attacker workstation.
# Prerequisites:
#   - Static IP set to 192.168.56.30
#   - DNS pointing to 192.168.56.10 (DC-01)
#   - corp.local domain must be accessible

param(
    [string]$DomainName    = "corp.local",
    [string]$AdminUser     = "corp\Administrator",
    [string]$AdminPassword = "p@ssw0rd"
)

Write-Host "[*] Verifying connectivity to DC-01..." -ForegroundColor Cyan
if (-not (Test-Connection -ComputerName 192.168.56.10 -Count 2 -Quiet)) {
    Write-Error "Cannot reach DC-01 (192.168.56.10). Check DNS and network settings."
    exit 1
}

Write-Host "[*] Verifying DNS resolution for $DomainName..." -ForegroundColor Cyan
try {
    Resolve-DnsName $DomainName -Server 192.168.56.10 -ErrorAction Stop | Out-Null
} catch {
    Write-Error "DNS resolution for $DomainName failed. Ensure DNS points to 192.168.56.10."
    exit 1
}

$SecurePass = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($AdminUser, $SecurePass)

Write-Host "[*] Joining $DomainName as WS-01..." -ForegroundColor Cyan
Add-Computer -DomainName $DomainName -Credential $Credential -OUPath "OU=Workstations,DC=corp,DC=local" -Restart

# VM will reboot automatically.
# After reboot, log in as: corp\attacker.01 / p@ssw0rd
