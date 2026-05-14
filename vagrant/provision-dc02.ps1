#Requires -RunAsAdministrator
# Vagrant provisioner for DC-02
# Sets DNS to DC-01 then promotes to Child Domain DC (dev.corp.local)
# Vagrant handles the reboot via 'vagrant-reload' after this script.

Set-ExecutionPolicy Bypass -Scope Process -Force

# ── Step 1: Point DNS at DC-01 ──────────────────────────────────────────────
Write-Host "[*] Configuring DNS to point at DC-01 (192.168.56.10)..." -ForegroundColor Cyan

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($a in $adapters) {
    $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($ip -like "192.168.56.*") {
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses "192.168.56.10"
        Write-Host "[+] DNS set on adapter: $($a.Name) ($ip)" -ForegroundColor Green
    }
}

# Disable IPv6 to prevent promotion warnings
Get-NetAdapter | ForEach-Object {
    Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
}

# ── Step 2: Wait for DC-01 ping ──────────────────────────────────────────────
Write-Host "[*] Waiting for DC-01 to be reachable (ping)..." -ForegroundColor Cyan
$retry = 0
while ($retry -lt 20) {
    if (Test-Connection -ComputerName 192.168.56.10 -Count 1 -Quiet) {
        Write-Host "[+] DC-01 is reachable." -ForegroundColor Green
        break
    }
    $retry++
    Write-Host "[-] Ping attempt $retry/20 — waiting 15s..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
}
if ($retry -eq 20) {
    Write-Error "DC-01 not reachable after 5 minutes. Ensure dc01 is running: vagrant up dc01"
    exit 1
}

# ── Step 2b: Wait for corp.local DNS to be fully operational ─────────────────
Write-Host "[*] Waiting for corp.local DNS to be ready..." -ForegroundColor Cyan
$retry = 0
while ($retry -lt 20) {
    try {
        Resolve-DnsName "corp.local" -Server 192.168.56.10 -ErrorAction Stop | Out-Null
        Write-Host "[+] corp.local DNS is responding." -ForegroundColor Green
        break
    } catch {
        $retry++
        Write-Host "[-] DNS attempt $retry/20 — waiting 15s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
    }
}
if ($retry -eq 20) {
    Write-Error "corp.local DNS not responding after 5 minutes."
    exit 1
}

# ── Step 3: Install AD DS ────────────────────────────────────────────────────
Write-Host "[*] Installing AD DS role..." -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services, RSAT-AD-PowerShell -IncludeManagementTools -ErrorAction Stop
Import-Module ADDSDeployment

# ── Step 4: Promote to Child Domain ─────────────────────────────────────────
$SafePass  = ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force
$AdminPass = ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force
$Cred      = New-Object System.Management.Automation.PSCredential("corp\Administrator", $AdminPass)

Write-Host "[*] Promoting to Child Domain DC: dev.corp.local" -ForegroundColor Cyan

Install-ADDSDomain `
    -NewDomainName                 "dev" `
    -ParentDomainName              "corp.local" `
    -DomainType                    ChildDomain `
    -SafeModeAdministratorPassword $SafePass `
    -Credential                    $Cred `
    -DomainMode                    WinThreshold `
    -InstallDns `
    -CreateDnsDelegation `
    -DatabasePath                  "C:\Windows\NTDS" `
    -LogPath                       "C:\Windows\NTDS" `
    -SysvolPath                    "C:\Windows\SYSVOL" `
    -NoRebootOnCompletion:$true `
    -Force

Write-Host "[+] DC-02 promotion complete. Vagrant will now reboot..." -ForegroundColor Green
