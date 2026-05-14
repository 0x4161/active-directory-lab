# VM Export & Import Guide

## Why Export?

Exporting your configured lab as OVA files lets you:
- Share the lab without others needing to run setup scripts
- Create a clean baseline snapshot before attacking
- Host pre-built VMs on GitHub Releases

---

## Before Exporting

### 1. Take a Clean Snapshot

In VirtualBox:
1. Select the VM
2. **Machine > Take Snapshot**
3. Name: `Clean-Baseline`
4. Repeat for all 3 VMs

### 2. Run Verify Script

On DC-01:
```powershell
.\scripts\verify-lab.ps1
```
Confirm all services, users, and misconfigurations are properly configured.

### 3. Sysprep (Optional)

If you want to generalize the image (remove SIDs, machine-specific data):
```cmd
C:\Windows\System32\Sysprep\sysprep.exe /oobe /generalize /shutdown
```
> **Note:** Sysprep on a Domain Controller is not supported. Only use on WS-01 if needed.

---

## Export VMs as OVA

### Via VirtualBox GUI

1. Shut down the VM
2. **File > Export Appliance**
3. Select the VM
4. Format: **OVF 2.0**
5. File: `DC-01.ova`
6. Click **Export**

### Via CLI (Recommended for automation)

```bash
# Shut down VMs first
VBoxManage controlvm "AD-Lab-DC01" poweroff
VBoxManage controlvm "AD-Lab-DC02" poweroff
VBoxManage controlvm "AD-Lab-Attacker" poweroff

# Wait for shutdown
sleep 5

# Export
VBoxManage export "AD-Lab-DC01" -o DC01.ova --ovf20
VBoxManage export "AD-Lab-DC02" -o DC02.ova --ovf20
VBoxManage export "AD-Lab-Attacker" -o attacker.ova --ovf20
```

Expected file sizes:
- DC01.ova: ~6-8 GB
- DC02.ova: ~6-8 GB
- attacker.ova: ~8-10 GB

---

## Hosting on GitHub Releases

GitHub has a 2 GB file limit. OVA files are much larger.

### Recommended approach: Split + Release

**Windows (PowerShell):**
```powershell
function Split-OVA($file, $chunkMB = 1900) {
    $chunkSize = $chunkMB * 1MB
    $reader = [System.IO.File]::OpenRead($file)
    $buffer = New-Object byte[] $chunkSize
    $part = 0
    while (($read = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $outFile = "$file.part{0:D2}" -f $part
        $writer = [System.IO.File]::OpenWrite($outFile)
        $writer.Write($buffer, 0, $read)
        $writer.Close()
        Write-Host "[+] $outFile"
        $part++
    }
    $reader.Close()
}

Split-OVA "DC01.ova"
Split-OVA "DC02.ova"
Split-OVA "attacker.ova"

gh release create v1.0.0 `
  --title "AD Lab v1.0.0 - Pre-built VMs" `
  DC01.ova.part* DC02.ova.part* attacker.ova.part*
```

**macOS / Linux:**
```bash
split -b 1900m DC01.ova DC01.ova.part
split -b 1900m DC02.ova DC02.ova.part
split -b 1900m attacker.ova attacker.ova.part

gh release create v1.0.0 \
  DC01.ova.part* DC02.ova.part* attacker.ova.part* \
  --title "AD Lab v1.0.0 - Pre-built VMs"
```

### Downloading and Reassembling

**Windows (PowerShell):**
```powershell
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

### Alternative: Git LFS

```bash
# Install Git LFS
git lfs install

# Track large files
git lfs track "*.ova"
git lfs track "*.vmdk"
git add .gitattributes
git commit -m "Configure Git LFS for VM files"
```

> **Note:** GitHub LFS free tier is 1 GB storage / 1 GB bandwidth. Large OVA files will quickly exceed this. GitHub Releases is generally preferred.

---

## Importing VMs

```bash
# Import with custom name
VBoxManage import DC-01.ova --vsys 0 --vmname "AD-Lab-DC01"
VBoxManage import DC-02.ova --vsys 0 --vmname "AD-Lab-DC02"
VBoxManage import WS-01.ova --vsys 0 --vmname "AD-Lab-WS01"

# Start all VMs
./scripts/lab-start.sh
```

After import:
1. Verify network adapters are set to `vboxnet0` (Host-Only) + NAT
2. Adjust RAM if your host has different capacity
3. Run `./scripts/lab-status.sh` to verify

---

## VMware Compatibility

To use with VMware Workstation:

```bash
# Convert OVA to VMX (VMware format)
ovftool DC-01.ova DC-01-vmware/DC-01.vmx
```

Or import the OVA directly in VMware Workstation via File > Open.

Minor reconfiguration of network adapters may be needed after import.
