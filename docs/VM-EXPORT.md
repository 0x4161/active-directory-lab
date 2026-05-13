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
VBoxManage controlvm "AD-Lab-WS01" poweroff

# Wait for shutdown
sleep 5

# Export
VBoxManage export "AD-Lab-DC01" -o DC-01.ova --ovf20
VBoxManage export "AD-Lab-DC02" -o DC-02.ova --ovf20
VBoxManage export "AD-Lab-WS01" -o WS-01.ova --ovf20
```

Expected file sizes:
- DC-01.ova: ~10-15 GB
- DC-02.ova: ~8-12 GB
- WS-01.ova: ~8-12 GB

---

## Hosting on GitHub Releases

GitHub has a 2 GB file limit. OVA files are much larger.

### Recommended approach: Split + Release

```bash
# Split DC-01.ova into 1.9 GB parts
split -b 1900m DC-01.ova DC-01.ova.part-
# Creates: DC-01.ova.part-aa, DC-01.ova.part-ab, ...

# Create a GitHub Release and upload all parts
gh release create v1.0.0 \
  DC-01.ova.part-* \
  DC-02.ova.part-* \
  WS-01.ova.part-* \
  --title "Lab v1.0.0" \
  --notes "Pre-built VMs for AD Lab"
```

### Downloading and Reassembling

```bash
# Download all parts for DC-01
gh release download v1.0.0 --pattern "DC-01.ova.part-*"

# Reassemble
cat DC-01.ova.part-* > DC-01.ova

# Verify integrity (if you provide a checksum)
sha256sum DC-01.ova
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
