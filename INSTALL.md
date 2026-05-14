# Installation Guide

> **Legal Notice:** This lab is for authorized educational use only.
> All misconfigurations are intentional and exist solely for learning.
> Never expose this environment to production networks.

---

## Requirements

| | Vagrant (Recommended) | Manual Build |
|---|---|---|
| RAM | 16 GB (12 GB min) | 16 GB (12 GB min) |
| Disk | 80 GB free | 100 GB free |
| Software | VirtualBox + Vagrant | VirtualBox + Windows ISOs |
| Build time | ~45-60 min (automated) | 2-3 hours (manual) |
| Download | ~12 GB (base boxes) | 0 (you provide ISOs) |

---

## Option A — Vagrant (Recommended)

Vagrant automatically downloads Windows base boxes, builds all 3 VMs, and runs all setup scripts. No manual steps required.

### Step 1: Install Requirements

- [VirtualBox 7.x](https://www.virtualbox.org/wiki/Downloads)
- [Vagrant](https://developer.hashicorp.com/vagrant/downloads)

### Step 2: Clone and Start

```bash
git clone https://github.com/0x4161/active-directory-lab.git
cd active-directory-lab

# Install required Vagrant plugin
vagrant plugin install vagrant-reload

# Build the entire lab (takes ~45-60 min)
vagrant up
```

Vagrant will:
1. Download `StefanScherer/windows_2019` base box (~7 GB, cached after first use)
2. Download `gusztavvargadr/windows-10` base box (~5 GB, cached)
3. Boot DC-01 → promote to `corp.local` → run `Setup-CorpLocal.ps1`
4. Boot DC-02 → promote to `dev.corp.local` → run `Setup-DevCorpLocal.ps1`
5. Boot WS-01 → join `corp.local`

### Step 3: Start Hacking

```bash
# Check all VMs are up
vagrant status

# Open WS-01 GUI (if not already open)
vagrant up ws01 --provision=false
```

Log in as: `corp\attacker.01` / `p@ssw0rd`

### Common Vagrant Commands

```bash
vagrant up          # Start all VMs
vagrant halt        # Shutdown all VMs
vagrant destroy -f  # Delete all VMs
vagrant status      # Show VM states
vagrant snapshot save all clean-baseline   # Take snapshot before attacking
vagrant snapshot restore all clean-baseline # Reset to clean state
```

---

## Option B — Import Pre-built VMs (if provided)

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

See [docs/LAB-SETUP.md](docs/LAB-SETUP.md) for the full step-by-step guide.

> All promotion and setup scripts must be run in **Administrator PowerShell** on each VM.

### Summary of steps:

1. **VirtualBox:** Create Host-Only network `vboxnet0` at `192.168.56.1` (DHCP disabled)
2. Create 3 VMs — each with **Adapter 1: Host-Only (vboxnet0)** and **Adapter 2: NAT**
3. Install **Windows Server 2019** on DC-01 and DC-02
4. Install **Windows 10/11** on WS-01
5. **DC-01:** Set static IP `192.168.56.10`, run `setup/promote-dc01.ps1`
6. **DC-01:** Run `scripts/Setup-CorpLocal.ps1` (creates all users, groups, ACLs, ADCS)
7. **DC-02:** Set static IP `192.168.56.20`, DNS → `192.168.56.10`, run `setup/promote-dc02.ps1`
8. **DC-02:** Run `scripts/Setup-DevCorpLocal.ps1`
9. **WS-01:** Set static IP `192.168.56.30`, DNS → `192.168.56.10`, run `setup/join-ws01.ps1`
10. Log in as `corp\attacker.01` / `p@ssw0rd` and begin

> See [docs/NETWORK-SETUP.md](docs/NETWORK-SETUP.md) for static IP commands and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues.

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
