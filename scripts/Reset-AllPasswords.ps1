#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory

# -----------------------------------------------------------------------------
# Reset-AllPasswords.ps1
# Resets all lab user passwords to p@ssw0rd on the existing corp.local domain.
# Run this on the Domain Controller as Administrator.
# -----------------------------------------------------------------------------

$NewPassword = ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force

$LabUsers = @(
    "john.carter", "lisa.morgan", "mark.hayes",
    "sarah.hill", "tom.baker", "emily.grant",
    "david.king", "nancy.cole", "peter.walsh",
    "james.ford", "rachel.burns",
    "svc_sql", "svc_iis", "svc_backup",
    "old.admin", "temp.contractor", "jane.doe",
    "attacker.01"
)

Write-Host "`n[*] Resetting passwords to p@ssw0rd for all lab accounts...`n" -ForegroundColor Cyan

foreach ($user in $LabUsers) {
    try {
        Set-ADAccountPassword -Identity $user -NewPassword $NewPassword -Reset
        Write-Host "  [+] $user" -ForegroundColor Green
    } catch {
        Write-Host "  [!] $user - $_" -ForegroundColor Red
    }
}

Write-Host "`n[*] Done. All lab accounts now use: p@ssw0rd`n" -ForegroundColor Cyan
