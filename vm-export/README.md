# VM Export Guide

See the full guide: [docs/VM-EXPORT.md](../docs/VM-EXPORT.md)

---

## Quick Export Commands

```bash
# Power off all VMs
VBoxManage controlvm "AD-Lab-DC01" acpipowerbutton
VBoxManage controlvm "AD-Lab-DC02" acpipowerbutton
VBoxManage controlvm "AD-Lab-WS01" acpipowerbutton
sleep 30

# Export to OVA
VBoxManage export "AD-Lab-DC01" -o DC-01.ova --ovf20
VBoxManage export "AD-Lab-DC02" -o DC-02.ova --ovf20
VBoxManage export "AD-Lab-WS01" -o WS-01.ova --ovf20
```

## Sharing via GitHub Releases

OVA files are too large for git. Use GitHub Releases:

```bash
# Split into 1.9 GB chunks
split -b 1900m DC-01.ova DC-01.ova.part-

# Upload to a GitHub Release
gh release create v1.0.0 DC-01.ova.part-* DC-02.ova.part-* WS-01.ova.part-* \
  --title "AD Lab v1.0.0 — Pre-built VMs" \
  --notes "Import with VBoxManage. See INSTALL.md for instructions."
```

## Quick Import

```bash
VBoxManage import DC-01.ova --vsys 0 --vmname "AD-Lab-DC01"
VBoxManage import DC-02.ova --vsys 0 --vmname "AD-Lab-DC02"
VBoxManage import WS-01.ova --vsys 0 --vmname "AD-Lab-WS01"
./scripts/lab-start.sh
```
