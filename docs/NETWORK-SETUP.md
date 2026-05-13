# Network Setup Guide

## Overview

The lab uses two VirtualBox network adapters per VM:

| Adapter   | Type      | Subnet            | Purpose                  |
|-----------|-----------|-------------------|--------------------------|
| Adapter 1 | Host-Only | 192.168.56.0/24   | Lab traffic (static IPs) |
| Adapter 2 | NAT       | 10.0.x.x (DHCP)   | Internet access          |

---

## Step 1: Create Host-Only Network in VirtualBox

### Via GUI

1. Open VirtualBox
2. Go to **File > Host Network Manager** (or Tools > Network)
3. Click **Create**
4. Set:
   - IPv4 Address: `192.168.56.1`
   - IPv4 Network Mask: `255.255.255.0`
   - DHCP Server: **Disabled**
5. Click **Apply**

### Via CLI

```bash
VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
VBoxManage dhcpserver remove --netname HostInterfaceNetworking-vboxnet0 2>/dev/null || true
```

---

## Step 2: Configure VM Network Adapters

For each VM:

1. Right-click VM > **Settings > Network**
2. **Adapter 1**: Host-only Adapter > `vboxnet0`
3. **Adapter 2**: NAT

---

## Step 3: Set Static IPs Inside Windows VMs

### DC-01 (corp.local) — 192.168.56.10

Run in PowerShell as Administrator:

```powershell
$nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress 192.168.56.10 -PrefixLength 24 -DefaultGateway 192.168.56.1
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses "192.168.56.10","127.0.0.1"
```

### DC-02 (dev.corp.local) — 192.168.56.20

**Important:** DNS must point to DC-01 before domain join.

```powershell
# Find host-only adapter (NOT the NAT one)
Get-NetAdapter | Select-Object Name, InterfaceDescription, Status

# Set static IP on Host-Only adapter
$nic = "Ethernet"   # adjust name as shown above
New-NetIPAddress -InterfaceAlias $nic -IPAddress 192.168.56.20 -PrefixLength 24 -DefaultGateway 192.168.56.1
Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses "192.168.56.10"

# Disable IPv6 on both adapters to avoid promotion warnings
Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6
Disable-NetAdapterBinding -Name "Ethernet 2" -ComponentID ms_tcpip6

# Set static IP on NAT adapter to avoid DHCP warning during promotion
netsh interface ipv4 set address name="Ethernet 2" static 10.0.3.15 255.255.255.0 10.0.3.2
```

### WS-01 (Attacker) — 192.168.56.30

```powershell
$nic = "Ethernet"
New-NetIPAddress -InterfaceAlias $nic -IPAddress 192.168.56.30 -PrefixLength 24 -DefaultGateway 192.168.56.1
Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses "192.168.56.10"
```

---

## Step 4: Verify Connectivity

From DC-02 or WS-01:

```powershell
# Ping DC-01
Test-Connection -ComputerName 192.168.56.10 -Count 2

# DNS resolution
Resolve-DnsName corp.local -Server 192.168.56.10

# From WS-01 after domain join
nltest /sc_verify:corp.local
```

---

## Troubleshooting

**DC-02 cannot reach DC-01**
- Verify DNS is set to 192.168.56.10, not the NAT IP (10.0.x.x)
- Verify Windows Firewall allows ICMP (or disable for testing)
- Verify both VMs have Host-Only adapter on vboxnet0

**Static IP lost after reboot**
- Use `New-NetIPAddress` instead of `netsh` for persistence
- Verify IP with `ipconfig /all`

**Cannot resolve corp.local**
- `nslookup corp.local 192.168.56.10` — if this works, DNS is fine
- Check DC-01 DNS service: `Get-Service DNS`
