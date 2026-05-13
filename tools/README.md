# Tools

This directory is intentionally empty. Do not commit tools or binaries to the repository.

Download tools separately and place them in this folder on your attacker machine (WS-01).

---

## Required Tools

### Windows (WS-01)

| Tool          | Download                                               | Purpose                     |
|---------------|--------------------------------------------------------|-----------------------------|
| BloodHound    | https://github.com/BloodHoundAD/BloodHound/releases    | AD graph analysis            |
| SharpHound    | https://github.com/BloodHoundAD/SharpHound/releases    | BloodHound collector         |
| Rubeus        | https://github.com/GhostPack/Rubeus                    | Kerberos attacks             |
| Certify       | https://github.com/GhostPack/Certify                   | ADCS attacks                 |
| Whisker       | https://github.com/eladshamir/Whisker                  | Shadow Credentials           |
| PowerView     | https://github.com/PowerShellMafia/PowerSploit         | AD enumeration               |
| mimikatz      | https://github.com/gentilkiwi/mimikatz/releases        | Credential extraction        |
| ADCSPwn       | https://github.com/bats3c/ADCSPwn                      | ESC8 NTLM relay              |

### Linux / Kali

| Tool          | Install                              | Purpose                     |
|---------------|--------------------------------------|-----------------------------|
| Impacket      | `pip3 install impacket`              | AD attack suite              |
| CrackMapExec  | `pip3 install crackmapexec`          | Network protocol attacks     |
| Hashcat       | `apt install hashcat`                | Password cracking            |
| John the Ripper | `apt install john`                 | Password cracking            |
| ldapsearch    | `apt install ldap-utils`             | LDAP enumeration             |
| PetitPotam    | https://github.com/topotam/PetitPotam | Coerce NTLM auth            |
| ntlmrelayx    | Included in Impacket                 | NTLM relay                  |

---

## Suggested Directory Layout on WS-01

```
C:\Tools\
├── BloodHound\
│   ├── BloodHound.exe
│   └── SharpHound.exe
├── Rubeus\
│   └── Rubeus.exe
├── Certify\
│   └── Certify.exe
├── Whisker\
│   └── Whisker.exe
├── PowerSploit\
│   └── Recon\
│       └── PowerView.ps1
├── mimikatz\
│   └── x64\
│       └── mimikatz.exe
└── Scripts\
    └── (custom scripts)
```

---

## AMSI / Defender Bypass (Lab Only)

In the lab environment, you may need to disable Defender for tools to run:

```powershell
# Disable real-time protection (as admin)
Set-MpPreference -DisableRealtimeMonitoring $true

# Add exclusion for tools directory
Add-MpPreference -ExclusionPath "C:\Tools"

# AMSI bypass (in-memory, not persistent)
[Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
```

> These techniques are for the isolated lab only. Never use them in production.
