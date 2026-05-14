<div align="center">

# Active Directory Enumeration & Attacks Lab

**A fully automated, self-contained Active Directory lab for practicing real-world attack techniques**

![Windows Server](https://img.shields.io/badge/Windows_Server-2019-blue?style=flat-square&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?style=flat-square&logo=powershell)
![VirtualBox](https://img.shields.io/badge/VirtualBox-7.x-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Lab Type](https://img.shields.io/badge/Lab-Active%20Directory-red?style=flat-square)

</div>

---

> **Legal Disclaimer**
> This environment is for **educational and authorized lab usage only**.
> All misconfigurations are **intentional** and exist solely for learning purposes.
> Never deploy this lab on production networks or expose it to the internet.
> The author is not responsible for any misuse of this material.

---

## Overview

This lab simulates a realistic enterprise Active Directory environment with intentional
misconfigurations covering a wide range of AD attack techniques — from basic enumeration
to advanced persistence and cross-domain escalation.

**One-command setup. Import VM. Start hacking.**

```bash
# After importing the OVA files:
./scripts/lab-start.sh
```

---

## Lab Topology

```
                    FOREST: corp.local
    ┌─────────────────────────────────────────────────────┐
    │                                                     │
    │   DC-01 (corp.local)         DC-02 (dev.corp.local) │
    │   ┌───────────────┐          ┌───────────────────┐  │
    │   │ Windows Srv   │◄────────►│ Windows Srv       │  │
    │   │ Domain Ctrl   │  Child   │ Child Domain DC   │  │
    │   │ + CA Server   │  Trust   │                   │  │
    │   │ 192.168.56.10 │          │ 192.168.56.20     │  │
    │   └───────────────┘          └───────────────────┘  │
    │                                                     │
    │   WS-01 (Attacker)                                  │
    │   ┌───────────────┐                                 │
    │   │ Windows 10/11 │                                 │
    │   │ corp\attacker │                                 │
    │   │ 192.168.56.30 │                                 │
    │   └───────────────┘                                 │
    └─────────────────────────────────────────────────────┘

    Network : Host-Only (192.168.56.0/24)
    Internet: NAT (separate adapter)
```

---

## VM Specifications

| VM    | Role                  | OS                      | RAM  | CPU | Disk  | IP             |
|-------|-----------------------|-------------------------|------|-----|-------|----------------|
| DC-01 | Forest Root DC + CA   | Windows Server 2019     | 4 GB | 2   | 60 GB | 192.168.56.10  |
| DC-02 | Child Domain DC       | Windows Server 2019     | 4 GB | 2   | 60 GB | 192.168.56.20  |
| WS-01 | Attacker Workstation  | Windows 10/11           | 4 GB | 2   | 60 GB | 192.168.56.30  |

**Total RAM required: 12 GB minimum (16 GB recommended)**

---

## Quick Start

### Option A — Import Pre-built VMs (Recommended)

> Download split parts from [GitHub Releases](https://github.com/0x4161/active-directory-lab/releases), reassemble, then import.

**Windows (PowerShell):**
```powershell
# Reassemble OVA files from split parts
$files = @("DC01","DC02","attacker")
foreach ($f in $files) {
    $parts = Get-ChildItem "$f.ova.part*" | Sort-Object Name
    $out = [System.IO.File]::OpenWrite("$f.ova")
    foreach ($p in $parts) { $bytes = [System.IO.File]::ReadAllBytes($p); $out.Write($bytes,0,$bytes.Length) }
    $out.Close(); Write-Host "[+] $f.ova reassembled"
}

# Import into VirtualBox
VBoxManage import DC01.ova --vsys 0 --vmname "AD-Lab-DC01"
VBoxManage import DC02.ova --vsys 0 --vmname "AD-Lab-DC02"
VBoxManage import attacker.ova --vsys 0 --vmname "AD-Lab-Attacker"
```

**macOS / Linux:**
```bash
# Reassemble
cat DC01.ova.part* > DC01.ova
cat DC02.ova.part* > DC02.ova
cat attacker.ova.part* > attacker.ova

# Import
VBoxManage import DC01.ova --vsys 0 --vmname "AD-Lab-DC01"
VBoxManage import DC02.ova --vsys 0 --vmname "AD-Lab-DC02"
VBoxManage import attacker.ova --vsys 0 --vmname "AD-Lab-Attacker"
```

```bash
# Start the lab
./scripts/lab-start.sh

# Verify everything is working
./scripts/lab-status.sh
```

### Option B — Build From Scratch

```bash
# 1. Clone the repository
git clone https://github.com/0x4161/active-directory-lab.git
cd active-directory-lab
```

1. Create Host-Only network `vboxnet0` (`192.168.56.1`) in VirtualBox — DHCP disabled
2. Create 3 VMs: each with **Adapter 1: Host-Only** + **Adapter 2: NAT**
3. Install Windows Server 2019 on DC-01 and DC-02, Windows 10/11 on WS-01
4. **DC-01** → static IP `192.168.56.10` → run `setup/promote-dc01.ps1` → run `scripts/Setup-CorpLocal.ps1`
5. **DC-02** → static IP `192.168.56.20`, DNS `192.168.56.10` → run `setup/promote-dc02.ps1` → run `scripts/Setup-DevCorpLocal.ps1`
6. **WS-01** → static IP `192.168.56.30`, DNS `192.168.56.10` → run `setup/join-ws01.ps1`

> Full guide: [docs/LAB-SETUP.md](docs/LAB-SETUP.md) — Network config: [docs/NETWORK-SETUP.md](docs/NETWORK-SETUP.md)

---

## Default Credentials

| Account           | Domain          | Password   | Role                                  |
|-------------------|-----------------|------------|---------------------------------------|
| Administrator     | corp.local      | p@ssw0rd   | Domain Admin                          |
| admin1            | corp.local      | p@ssw0rd   | Domain Admin                          |
| **attacker.01**   | corp.local      | p@ssw0rd   | **Your starting point (low priv)**    |
| ahmad.ali         | corp.local      | p@ssw0rd   | IT Admin                              |
| fahad.salem       | corp.local      | p@ssw0rd   | Helpdesk Lead                         |
| sara.khalid       | corp.local      | p@ssw0rd   | HR Manager                            |
| faisal.omar       | corp.local      | p@ssw0rd   | Finance Director                      |
| walid.saeed       | corp.local      | p@ssw0rd   | Finance Analyst [AS-REP Roastable]    |
| svc_sql           | corp.local      | p@ssw0rd   | Service Account [Kerberoastable]      |
| svc_backup        | corp.local      | p@ssw0rd   | Service Account [DCSync Rights]       |
| faris.admin       | dev.corp.local  | p@ssw0rd   | Child Domain Admin                    |
| **attacker.dev**  | dev.corp.local  | p@ssw0rd   | Child domain starting point           |

> Full credentials list: [docs/ATTACK-PATHS.md](docs/ATTACK-PATHS.md)

---

## Attack Scenarios Included

| # | Attack                              | Difficulty | Path                          |
|---|-------------------------------------|------------|-------------------------------|
| 1 | Domain Enumeration                  | Easy       | BloodHound / PowerView        |
| 2 | Kerberoasting                       | Easy       | 6 service accounts            |
| 3 | AS-REP Roasting                     | Easy       | 3 users                       |
| 4 | Password Spray                      | Easy       | Weak passwords                |
| 5 | Credentials in AD Attributes        | Easy       | LDAP enumeration              |
| 6 | GPP / SYSVOL Password               | Easy       | Groups.xml                    |
| 7 | ACL — GenericAll                    | Medium     | noura.ahmed -> faisal.omar    |
| 8 | ACL — WriteDACL                     | Medium     | ahmad.ali -> Finance Users    |
| 9 | ACL — ForceChangePassword           | Medium     | fahad.salem -> faisal.omar    |
| 10| ACL — DCSync Rights                 | Medium     | svc_backup -> domain          |
| 11| ACL — WriteOwner                    | Medium     | Helpdesk -> IT Admins         |
| 12| Shadow Credentials                  | Medium     | omar.coder -> WEB-SRV-01      |
| 13| Unconstrained Delegation            | Medium     | WEB-SRV-01 / svc_web          |
| 14| Constrained Delegation (KCD)        | Hard       | svc_iis -> CIFS/DC-01         |
| 15| Resource-Based Constrained (RBCD)   | Hard       | tariq.dev -> WEB-SRV-02       |
| 16| AdminSDHolder Persistence           | Hard       | svc_backup -> all DAs         |
| 17| DSRM Abuse                          | Hard       | Local admin on DC             |
| 18| ADCS ESC1                           | Hard       | Forge admin certificate       |
| 19| ADCS ESC4                           | Hard       | Modify writable template      |
| 20| ADCS ESC6                           | Hard       | SAN in any template           |
| 21| ADCS ESC7                           | Hard       | CA Manager abuse              |
| 22| ADCS ESC8                           | Hard       | NTLM relay to ADCS            |
| 23| Golden Ticket                       | Expert     | After krbtgt dump             |
| 24| Child-to-Parent (ExtraSids)         | Expert     | dev -> corp.local EA          |
| 25| Trust Ticket                        | Expert     | Inter-realm TGT forgery       |
| 26| SID History Abuse                   | Expert     | dev.backdoor -> EA rights     |

---

## Network Configuration

```
VirtualBox Network Setup:

Adapter 1 (Host-Only): vboxnet0 — 192.168.56.0/24
  Purpose : VM-to-VM communication + host access
  DC-01   : 192.168.56.10 (static)
  DC-02   : 192.168.56.20 (static)
  WS-01   : 192.168.56.30 (static or DHCP)

Adapter 2 (NAT):
  Purpose : Internet access for downloading tools
  All VMs : DHCP (10.0.x.x)
```

---

## Supported Hypervisors

| Hypervisor      | Status    | Format     | Notes                        |
|-----------------|-----------|------------|------------------------------|
| VirtualBox 7.x  | Tested    | OVA / OVF  | Recommended                  |
| VMware Workstation 17 | Compatible | OVF   | Minor network reconfiguration|
| VMware ESXi     | Compatible | OVF        | Enterprise use               |
| Hyper-V         | Partial   | VHDX       | Manual conversion needed     |

---

## Screenshots

> Add screenshots to `/screenshots/` folder after setup.

```
screenshots/
├── 01-lab-topology.png
├── 02-bloodhound-graph.png
├── 03-kerberoast.png
├── 04-adcs-esc1.png
└── 05-golden-ticket.png
```

---

## Repository Structure

```
ad-lab/
├── README.md                  # This file
├── LICENSE                    # MIT License
├── .gitignore
├── INSTALL.md                 # Quick installation guide
├── docs/
│   ├── LAB-SETUP.md           # Detailed setup from scratch
│   ├── ATTACK-PATHS.md        # All attack paths with commands
│   ├── TROUBLESHOOTING.md     # Common issues and fixes
│   ├── REQUIREMENTS.md        # Hardware and software requirements
│   ├── VM-EXPORT.md           # How to export/import VMs
│   └── NETWORK-SETUP.md       # Network configuration guide
├── scripts/
│   ├── Setup-CorpLocal.ps1    # corp.local full setup
│   ├── Setup-DevCorpLocal.ps1 # dev.corp.local setup
│   ├── Reset-AllPasswords.ps1 # Reset all lab passwords
│   ├── lab-start.sh           # Start all VMs
│   ├── lab-stop.sh            # Stop all VMs
│   ├── lab-reset.sh           # Reset snapshots
│   ├── lab-status.sh          # Check VM status
│   └── verify-lab.ps1         # Verify AD services
├── setup/
│   ├── promote-dc01.ps1       # Promote DC-01 to forest root
│   ├── promote-dc02.ps1       # Promote DC-02 to child domain
│   └── join-ws01.ps1          # Join WS-01 to domain
├── attacks/
│   ├── 01-enumeration.md
│   ├── 02-kerberoasting.md
│   ├── 03-asrep-roasting.md
│   ├── 04-delegation.md
│   ├── 05-acl-attacks.md
│   ├── 06-adcs.md
│   ├── 07-persistence.md
│   └── 08-cross-domain.md
├── enumeration/
│   ├── bloodhound-queries.md
│   ├── powerview-cheatsheet.md
│   └── ldap-enum.md
├── vm-export/
│   └── README.md
├── screenshots/
│   └── .gitkeep
├── wordlists/
│   ├── lab-users.txt
│   ├── lab-passwords.txt
│   └── README.md
└── tools/
    └── README.md
```

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT License — see [LICENSE](LICENSE)

---

<div align="center">
Built for security education. Use responsibly.
</div>
