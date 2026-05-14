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

# ── OUs ──────────────────────────────────────────────────────────────────────
Write-Host "`n[*] Checking OUs..." -ForegroundColor Cyan
foreach ($ou in @("IT","HR","Finance","Dev","Management","Staging","Servers","Workstations","Service Accounts","Disabled Users")) {
    Test-Item "OU: $ou" { [bool](Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue) }
}

# ── Users ─────────────────────────────────────────────────────────────────────
Write-Host "`n[*] Checking all users exist..." -ForegroundColor Cyan
$allUsers = @(
    "attacker.01","ahmad.ali","fahad.salem","khalid.nasser","noura.ahmed",
    "sara.khalid","maryam.hassan","reem.sultan","hessa.jaber",
    "faisal.omar","dana.rashid","walid.saeed","nada.mubarak",
    "tariq.dev","omar.coder","lina.script","nasser.web",
    "hamad.ceo","abdulaziz.cfo","contractor.mutaeb",
    "svc_sql","svc_iis","svc_mssql","svc_exchange","svc_web","svc_backup"
)
foreach ($user in $allUsers) {
    Test-Item "User: $user" { [bool](Get-ADUser -Identity $user -ErrorAction SilentlyContinue) }
}

# ── Kerberoastable ────────────────────────────────────────────────────────────
Write-Host "`n[*] Checking Kerberoastable accounts (SPNs)..." -ForegroundColor Cyan
foreach ($user in @("svc_sql","svc_iis","svc_mssql","svc_exchange","svc_web","svc_backup")) {
    Test-Item "SPN: $user" {
        $u = Get-ADUser -Identity $user -Properties ServicePrincipalName -ErrorAction SilentlyContinue
        $u -and $u.ServicePrincipalName.Count -gt 0
    }
}

# ── AS-REP Roastable ──────────────────────────────────────────────────────────
Write-Host "`n[*] Checking AS-REP Roastable accounts..." -ForegroundColor Cyan
foreach ($user in @("walid.saeed","lina.script","contractor.mutaeb")) {
    Test-Item "AS-REP: $user" {
        $u = Get-ADUser -Identity $user -Properties DoesNotRequirePreAuth -ErrorAction SilentlyContinue
        $u -and $u.DoesNotRequirePreAuth -eq $true
    }
}

# ── Delegation ────────────────────────────────────────────────────────────────
Write-Host "`n[*] Checking Delegation misconfigs..." -ForegroundColor Cyan

Test-Item "Unconstrained delegation: svc_web" {
    $u = Get-ADUser -Identity "svc_web" -Properties TrustedForDelegation -ErrorAction SilentlyContinue
    $u -and $u.TrustedForDelegation -eq $true
}

Test-Item "Constrained delegation (KCD): svc_iis" {
    $u = Get-ADUser -Identity "svc_iis" -Properties "msDS-AllowedToDelegateTo" -ErrorAction SilentlyContinue
    $u -and $u."msDS-AllowedToDelegateTo".Count -gt 0
}

# ── ACL Attacks ───────────────────────────────────────────────────────────────
Write-Host "`n[*] Checking ACL misconfigurations..." -ForegroundColor Cyan

Test-Item "DCSync rights: svc_backup" {
    $domainDN = (Get-ADDomain).DistinguishedName
    $acl = (Get-Acl "AD:\$domainDN").Access
    $dcsyncGuid = [guid]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2"
    $svcSid = (Get-ADUser "svc_backup").SID
    $found = $acl | Where-Object {
        $_.IdentityReference -like "*svc_backup*" -and
        $_.ObjectType -eq $dcsyncGuid
    }
    [bool]$found
}

Test-Item "GenericAll: noura.ahmed -> faisal.omar" {
    $acl = (Get-Acl "AD:\$(Get-ADUser faisal.omar)").Access
    [bool]($acl | Where-Object {
        $_.IdentityReference -like "*noura.ahmed*" -and
        $_.ActiveDirectoryRights -match "GenericAll"
    })
}

Test-Item "ForceChangePassword: fahad.salem -> faisal.omar" {
    $acl = (Get-Acl "AD:\$(Get-ADUser faisal.omar)").Access
    $resetGuid = [guid]"00299570-246d-11d0-a768-00aa006e0529"
    [bool]($acl | Where-Object {
        $_.IdentityReference -like "*fahad.salem*" -and
        $_.ObjectType -eq $resetGuid
    })
}

# ── Group Memberships ─────────────────────────────────────────────────────────
Write-Host "`n[*] Checking group memberships..." -ForegroundColor Cyan

Test-Item "ahmad.ali in IT Admins" {
    [bool](Get-ADGroupMember "IT Admins" -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq "ahmad.ali" })
}

Test-Item "fahad.salem in Helpdesk" {
    [bool](Get-ADGroupMember "Helpdesk" -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq "fahad.salem" })
}

Test-Item "svc_backup in Server Operators" {
    [bool](Get-ADGroupMember "Server Operators" -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq "svc_backup" })
}

# ── ADCS ──────────────────────────────────────────────────────────────────────
Write-Host "`n[*] Checking ADCS..." -ForegroundColor Cyan
Test-Item "ADCS service running" {
    (Get-Service -Name CertSvc -ErrorAction SilentlyContinue).Status -eq "Running"
}

$configDN = (Get-ADRootDSE).configurationNamingContext
foreach ($t in @("ESC1-LabAltName","ESC2-AnyPurpose","ESC3-EnrollAgent","ESC4-Writable")) {
    Test-Item "Certificate template: $t" {
        $base = "LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,$configDN"
        $searcher = [adsisearcher]"(&(objectClass=pKICertificateTemplate)(cn=$t))"
        $searcher.SearchRoot = [adsi]$base
        $null -ne $searcher.FindOne()
    }
}

# ── Persistence Misconfigs ───────────────────────────────────────────────────
Write-Host "`n[*] Checking persistence misconfigurations..." -ForegroundColor Cyan

Test-Item "DSRM: DsrmAdminLogonBehavior = 2" {
    (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Lsa" -Name DsrmAdminLogonBehavior -ErrorAction SilentlyContinue).DsrmAdminLogonBehavior -eq 2
}

Test-Item "GPP Groups.xml exists in SYSVOL" {
    $path = "C:\Windows\SYSVOL\sysvol\corp.local\Policies"
    [bool](Get-ChildItem -Path $path -Recurse -Filter "Groups.xml" -ErrorAction SilentlyContinue | Select-Object -First 1)
}

Test-Item "AdminSDHolder: svc_backup has ACE" {
    $acl = (Get-Acl "AD:\CN=AdminSDHolder,CN=System,$(Get-ADDomain -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DistinguishedName)").Access
    [bool]($acl | Where-Object { $_.IdentityReference -like "*svc_backup*" })
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "  Results: $Pass passed, $Fail failed" -ForegroundColor $(if ($Fail -eq 0) { "Green" } else { "Yellow" })
Write-Host "================================" -ForegroundColor Cyan

if ($Fail -gt 0) {
    Write-Host "`n  Re-run Setup-CorpLocal.ps1 to fix failed items.`n" -ForegroundColor Yellow
} else {
    Write-Host "`n  Lab is fully configured. Happy hacking!`n" -ForegroundColor Green
}
