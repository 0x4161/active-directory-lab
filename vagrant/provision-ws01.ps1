#Requires -RunAsAdministrator
# Vagrant provisioner for WS-01 (Attacker Workstation)
# Sets DNS to DC-01 and joins corp.local domain
# Vagrant handles the reboot via 'vagrant-reload' after this script.

Set-ExecutionPolicy Bypass -Scope Process -Force

# ── Step 1: Set DNS to DC-01 ─────────────────────────────────────────────────
Write-Host "[*] Configuring DNS to point at DC-01 (192.168.56.10)..." -ForegroundColor Cyan

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($a in $adapters) {
    $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($ip -like "192.168.56.*") {
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses "192.168.56.10"
        Write-Host "[+] DNS set on adapter: $($a.Name) ($ip)" -ForegroundColor Green
    }
}

# ── Step 2: Wait for corp.local DNS resolution ───────────────────────────────
Write-Host "[*] Waiting for corp.local to be resolvable..." -ForegroundColor Cyan
$retry = 0
while ($retry -lt 12) {
    try {
        Resolve-DnsName "corp.local" -Server 192.168.56.10 -ErrorAction Stop | Out-Null
        Write-Host "[+] corp.local resolved successfully." -ForegroundColor Green
        break
    } catch {
        $retry++
        Write-Host "[-] Attempt $retry/12 — waiting 15s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
    }
}

if ($retry -eq 12) {
    Write-Error "corp.local not resolvable. Ensure dc01 is running: vagrant up dc01"
    exit 1
}

# ── Step 3: Join corp.local (with retry) ─────────────────────────────────────
$AdminPass = ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force
$Cred      = New-Object System.Management.Automation.PSCredential("corp\Administrator", $AdminPass)

Write-Host "[*] Joining corp.local domain..." -ForegroundColor Cyan

$joined = $false
$retry  = 0
while (-not $joined -and $retry -lt 5) {
    try {
        Add-Computer `
            -DomainName "corp.local" `
            -Credential $Cred `
            -OUPath     "OU=Workstations,DC=corp,DC=local" `
            -Force `
            -ErrorAction Stop
        $joined = $true
    } catch {
        $retry++
        Write-Host "[-] Join attempt $retry/5 failed: $_ — waiting 20s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 20
    }
}

if (-not $joined) {
    Write-Error "Failed to join corp.local after 5 attempts."
    exit 1
}

Write-Host "[+] WS-01 joined corp.local. Vagrant will now reboot..." -ForegroundColor Green
Write-Host "[*] After reboot, log in as: corp\attacker.01 / p@ssw0rd" -ForegroundColor Cyan
