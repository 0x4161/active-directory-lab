# Troubleshooting

Common issues encountered when setting up and running the lab.

---

## DC Promotion Issues

### Error: "dcpromo is already running" (0x800700b7)

A previous interrupted promotion attempt left a dcpromo mutex locked.

**Fix:** Restart the VM completely.
```powershell
shutdown /r /t 0
```

---

### Error 8200 — NTDS Database Corruption

Multiple failed promotion attempts corrupted the NTDS database.

**Fix:** Clean all remnants and retry.
```powershell
# Run as Administrator
Remove-Item C:\Windows\NTDS -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item C:\Windows\SYSVOL -Recurse -Force -ErrorAction SilentlyContinue

# Remove corrupt DSA epoch key
Remove-Item "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters\DSA Database Epoch" -ErrorAction SilentlyContinue

# Reboot, then re-run promote-dc02.ps1
shutdown /r /t 0
```

---

### Error: "The server could not be contacted" when promoting DC-02

DC-02 cannot reach DC-01 — DNS misconfiguration.

**Fix:** Point DNS to DC-01 before promotion.
```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "192.168.56.10"
# Verify:
nslookup corp.local 192.168.56.10
```

---

### Warning about static IP during promotion

VirtualBox NAT adapter is still on DHCP, triggering promotion warnings that can cause failure.

**Fix:** Assign static IP to the NAT adapter.
```powershell
netsh interface ipv4 set address name="Ethernet 2" static 10.0.3.15 255.255.255.0 10.0.3.2
Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6
Disable-NetAdapterBinding -Name "Ethernet 2" -ComponentID ms_tcpip6
```

---

### VM freezes during DC promotion

Usually caused by insufficient RAM.

**Fix:** Increase VM RAM to 4 GB in VirtualBox Settings > System > Motherboard.
Shut down the VM first — RAM cannot be changed while running.

---

## Script Errors

### "ActiveDirectory module not found"

```
#Requires -Modules ActiveDirectory — module is not installed.
```

**Fix:**
```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeManagementTools
Import-Module ActiveDirectory
```

---

### PowerShell encoding errors (em dashes, box-drawing characters)

Script was saved with special Unicode characters that PowerShell on Windows cannot parse.

**Fix:** Open the file in VS Code and save as UTF-8 (without BOM), or re-download from the repository. All scripts in this repo use ASCII-safe characters only.

---

### "Restart-Computer: Privilege not held"

**Fix:** Use `shutdown` instead.
```powershell
shutdown /r /t 0
```

---

## Domain Join Issues (WS-01)

### Add-Computer fails — "The network path was not found"

- Verify WS-01 DNS points to `192.168.56.10`
- Verify connectivity: `ping 192.168.56.10`
- Verify the domain name: `nslookup corp.local`

### Add-Computer with comment embedded in command

If you copy a command that has a comment at the end and paste it incorrectly:
```powershell
# Wrong — comment embedded as parameter
Add-Computer -DomainName corp.local -Restart# some comment

# Correct
Add-Computer -DomainName corp.local -Credential (Get-Credential) -Restart
```

---

## Cross-Domain Issues

### Cannot add global group member from another domain

Global groups cannot have cross-domain members — this is by design in Active Directory.

**Fix:** Use Universal groups for cross-domain membership.
```powershell
# Change group scope to Universal
Set-ADGroup -Identity "GroupName" -GroupScope Universal
```
This limitation is non-critical for the lab since most cross-domain attacks don't require this.

---

## VirtualBox Issues

### Guest Additions UAC prompt — no admin access

On WS-01, if you can't install Guest Additions:

- Guest Additions are **optional** — the lab works without them
- Skip and proceed to domain join
- If needed later: enable the built-in Administrator account
  ```cmd
  net user Administrator /active:yes
  net user Administrator p@ssw0rd
  ```

---

## Password / Authentication Issues

### Reset all lab passwords

If any account gets locked out or passwords are changed during testing:
```powershell
# Run on DC-01 as Domain Admin
.\scripts\Reset-AllPasswords.ps1
```

### attacker.01 account locked out

```powershell
Unlock-ADAccount -Identity "attacker.01"
Set-ADAccountPassword -Identity "attacker.01" -NewPassword (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force) -Reset
```

---

## BloodHound Issues

### SharpHound collection fails — access denied

Run SharpHound from the attacker workstation (WS-01) as a domain user, not as local admin:
```powershell
runas /user:corp\attacker.01 "powershell -c '. .\SharpHound.ps1; Invoke-BloodHound -CollectionMethod All'"
```

### Neo4j won't start

Default ports: Neo4j Browser on `7474`, Bolt on `7687`.
Check if port is in use: `netstat -ano | findstr 7687`
