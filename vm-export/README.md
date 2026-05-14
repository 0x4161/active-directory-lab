# VM Export Guide

See the full guide: [docs/VM-EXPORT.md](../docs/VM-EXPORT.md)

---

## Quick Export Commands

```bash
# Power off all VMs
VBoxManage controlvm "AD-Lab-DC01" acpipowerbutton
VBoxManage controlvm "AD-Lab-DC02" acpipowerbutton
VBoxManage controlvm "AD-Lab-Attacker" acpipowerbutton
sleep 30

# Export to OVA
VBoxManage export "AD-Lab-DC01" -o DC01.ova --ovf20
VBoxManage export "AD-Lab-DC02" -o DC02.ova --ovf20
VBoxManage export "AD-Lab-Attacker" -o attacker.ova --ovf20
```

## Sharing via GitHub Releases

OVA files are too large for git. Use GitHub Releases:

**Windows (PowerShell):**
```powershell
# Split + upload (see docs/VM-EXPORT.md for full Split-OVA function)
gh release create v1.0.0 `
  DC01.ova.part* DC02.ova.part* attacker.ova.part* `
  --title "AD Lab v1.0.0 - Pre-built VMs" `
  --notes "See INSTALL.md for download and reassembly instructions."
```

**macOS / Linux:**
```bash
split -b 1900m DC01.ova DC01.ova.part
split -b 1900m DC02.ova DC02.ova.part
split -b 1900m attacker.ova attacker.ova.part

gh release create v1.0.0 DC01.ova.part* DC02.ova.part* attacker.ova.part* \
  --title "AD Lab v1.0.0 - Pre-built VMs" \
  --notes "See INSTALL.md for download and reassembly instructions."
```

## Quick Import

```bash
VBoxManage import DC01.ova --vsys 0 --vmname "AD-Lab-DC01"
VBoxManage import DC02.ova --vsys 0 --vmname "AD-Lab-DC02"
VBoxManage import attacker.ova --vsys 0 --vmname "AD-Lab-Attacker"
./scripts/lab-start.sh
```
