# Installation Guide

> **Legal Notice:** This lab is for authorized educational use only.
> All misconfigurations are intentional and exist solely for learning.
> Never expose this environment to production networks.

---

## Requirements

- Host machine with **16 GB RAM** (12 GB minimum)
- **100 GB** free disk space (60 GB per VM x 3)
- **VirtualBox 7.x** installed
- Windows Server 2019 ISO (for building from scratch)
- Windows 10 or 11 ISO (for WS-01)

---

## Option A — Import Pre-built VMs (Fastest)

### Step 1: Download Split Parts from GitHub Releases

Go to [Releases](https://github.com/0x4161/active-directory-lab/releases) and download all parts:

```
DC01.ova.part00 ~ part03      (~6.7 GB total)   Forest Root DC + CA
DC02.ova.part00 ~ part03      (~6.3 GB total)   Child Domain DC
attacker.ova.part00 ~ part04  (~8.8 GB total)   Attacker Workstation
```

### Step 2: Reassemble OVA Files

**Windows (PowerShell):**
```powershell
# Run in the folder where you downloaded the parts
$files = @("DC01","DC02","attacker")
foreach ($f in $files) {
    $parts = Get-ChildItem "$f.ova.part*" | Sort-Object Name
    $out = [System.IO.File]::OpenWrite("$f.ova")
    foreach ($p in $parts) {
        $bytes = [System.IO.File]::ReadAllBytes($p.FullName)
        $out.Write($bytes, 0, $bytes.Length)
    }
    $out.Close()
    Write-Host "[+] $f.ova ready"
}
```

**macOS / Linux:**
```bash
cat DC01.ova.part* > DC01.ova
cat DC02.ova.part* > DC02.ova
cat attacker.ova.part* > attacker.ova
```

### Step 3: Create Host-Only Network

Open VirtualBox > File > Host Network Manager > Create

```
Name    : vboxnet0
IP      : 192.168.56.1
Mask    : 255.255.255.0
DHCP    : Disabled
```

### Step 4: Import VMs

```bash
VBoxManage import DC01.ova --vsys 0 --vmname "AD-Lab-DC01"
VBoxManage import DC02.ova --vsys 0 --vmname "AD-Lab-DC02"
VBoxManage import attacker.ova --vsys 0 --vmname "AD-Lab-Attacker"
```

Or via GUI: File > Import Appliance > select each OVA.

### Step 5: Start the Lab

```bash
./scripts/lab-start.sh
```

### Step 6: Verify

```bash
./scripts/lab-status.sh
```

Log in as `corp\attacker.01` / `p@ssw0rd` and begin.

---

## Option B — Build From Scratch

See [docs/LAB-SETUP.md](docs/LAB-SETUP.md) for the full manual setup guide.

### Summary of steps:

1. Create 3 VMs in VirtualBox (specs in README)
2. Install Windows Server 2019 on DC-01 and DC-02
3. Install Windows 10/11 on WS-01
4. Configure static IPs and Host-Only networking
5. Run `setup/promote-dc01.ps1` on DC-01
6. Run `scripts/Setup-CorpLocal.ps1` on DC-01
7. Configure DC-02 DNS to point at DC-01 (192.168.56.10)
8. Run `setup/promote-dc02.ps1` on DC-02
9. Run `scripts/Setup-DevCorpLocal.ps1` on DC-02
10. Run `setup/join-ws01.ps1` on WS-01

---

## Default Credentials

| Account       | Domain         | Password  |
|---------------|----------------|-----------|
| Administrator | corp.local     | p@ssw0rd  |
| attacker.01   | corp.local     | p@ssw0rd  |
| Administrator | dev.corp.local | p@ssw0rd  |
| attacker.dev  | dev.corp.local | p@ssw0rd  |

Full credentials: [docs/ATTACK-PATHS.md](docs/ATTACK-PATHS.md)

---

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
