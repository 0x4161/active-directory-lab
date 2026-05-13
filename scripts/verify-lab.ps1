#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

# Verify that the lab is correctly configured.
# Run on DC-01 after Setup-CorpLocal.ps1 completes.

$Pass = 0
$Fail = 0

function Test-Item {
    param([string]$Name, [scriptblock]$Check)
    try {
        $result = & $Check
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:Pass++
        } else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            $script:Fail++
        }
    } catch {
        Write-Host "  [ERROR] $Name - $_" -ForegroundColor Yellow
        $script:Fail++
    }
}

Write-Host "`n=== AD Lab Verification ===" -ForegroundColor Cyan

Write-Host "`n[*] Checking OUs..." -ForegroundColor Cyan
foreach ($ou in @("IT","HR","Finance","Dev","Management","Staging","Servers","Workstations","Service Accounts","Disabled Users")) {
    Test-Item "OU: $ou" { [bool](Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue) }
}

Write-Host "`n[*] Checking key users..." -ForegroundColor Cyan
foreach ($user in @("attacker.01","ahmad.ali","walid.saeed","svc_sql","svc_backup","lina.script","contractor.mutaeb")) {
    Test-Item "User: $user" { [bool](Get-ADUser -Identity $user -ErrorAction SilentlyContinue) }
}

Write-Host "`n[*] Checking Kerberoastable accounts (SPNs)..." -ForegroundColor Cyan
$kerberoastable = @("svc_sql","svc_iis","svc_mssql","svc_exchange","svc_web","svc_backup")
foreach ($user in $kerberoastable) {
    Test-Item "SPN: $user" {
        $u = Get-ADUser -Identity $user -Properties ServicePrincipalName -ErrorAction SilentlyContinue
        $u -and $u.ServicePrincipalName.Count -gt 0
    }
}

Write-Host "`n[*] Checking AS-REP Roastable accounts..." -ForegroundColor Cyan
foreach ($user in @("walid.saeed","lina.script","contractor.mutaeb")) {
    Test-Item "AS-REP: $user" {
        $u = Get-ADUser -Identity $user -Properties DoesNotRequirePreAuth -ErrorAction SilentlyContinue
        $u -and $u.DoesNotRequirePreAuth -eq $true
    }
}

Write-Host "`n[*] Checking ADCS..." -ForegroundColor Cyan
Test-Item "ADCS service running" { (Get-Service -Name CertSvc -ErrorAction SilentlyContinue).Status -eq "Running" }

$templates = @("ESC1-LabAltName","ESC2-AnyPurpose","ESC3-EnrollAgent","ESC4-Writable")
foreach ($t in $templates) {
    Test-Item "Certificate template: $t" {
        $base = "LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=corp,DC=local"
        $searcher = [adsisearcher]"(&(objectClass=pKICertificateTemplate)(cn=$t))"
        $searcher.SearchRoot = [adsi]$base
        $null -ne $searcher.FindOne()
    }
}

Write-Host "`n[*] Checking DSRM registry setting..." -ForegroundColor Cyan
Test-Item "DSRM DsrmAdminLogonBehavior = 2" {
    (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Lsa" -Name DsrmAdminLogonBehavior -ErrorAction SilentlyContinue).DsrmAdminLogonBehavior -eq 2
}

Write-Host "`n[*] Checking GPP SYSVOL file..." -ForegroundColor Cyan
Test-Item "GPP Groups.xml in SYSVOL" {
    $path = "C:\Windows\SYSVOL\sysvol\corp.local\Policies"
    Test-Path (Join-Path $path "*\Machine\Preferences\Groups\Groups.xml") -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "  Results: $Pass passed, $Fail failed" -ForegroundColor $(if ($Fail -eq 0) { "Green" } else { "Yellow" })
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
