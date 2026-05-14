#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

# -----------------------------------------------------------------------------
# Reset-AllPasswords.ps1
# Resets ALL lab user passwords to p@ssw0rd on corp.local.
# Run on DC-01 as Domain Admin when accounts get locked out or passwords change.
# -----------------------------------------------------------------------------

$NewPassword = ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force

$LabUsers = @(
    # IT Department
    "ahmad.ali", "fahad.salem", "khalid.nasser", "noura.ahmed",
    # HR Department
    "sara.khalid", "maryam.hassan", "reem.sultan", "hessa.jaber",
    # Finance Department
    "faisal.omar", "dana.rashid", "walid.saeed", "nada.mubarak",
    # Dev Department
    "tariq.dev", "omar.coder", "lina.script", "nasser.web",
    # Management
    "hamad.ceo", "abdulaziz.cfo",
    # Staging / Contractor
    "contractor.mutaeb",
    # Attacker accounts
    "attacker.01",
    # Service Accounts
    "svc_sql", "svc_iis", "svc_mssql", "svc_exchange", "svc_web", "svc_backup",
    # Disabled / Legacy (reset in case re-enabled during testing)
    "old.admin", "temp.mutaeb", "svc_old_crm",
    # Additional Domain Admin
    "admin1"
)

Write-Host "`n[*] Resetting passwords to p@ssw0rd for all lab accounts...`n" -ForegroundColor Cyan

$ok  = 0
$err = 0

foreach ($user in $LabUsers) {
    try {
        Set-ADAccountPassword -Identity $user -NewPassword $NewPassword -Reset -ErrorAction Stop
        Set-ADUser -Identity $user -PasswordNeverExpires $true -ChangePasswordAtLogon $false -ErrorAction SilentlyContinue
        Unlock-ADAccount -Identity $user -ErrorAction SilentlyContinue
        Write-Host "  [+] $user" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "  [!] $user - $_" -ForegroundColor Red
        $err++
    }
}

Write-Host "`n[*] Done. $ok reset, $err failed. Password: p@ssw0rd`n" -ForegroundColor Cyan
