# Requirements

## Hardware

| Component | Minimum      | Recommended  |
|-----------|-------------|--------------|
| RAM       | 12 GB       | 16 GB+       |
| CPU       | 4 cores     | 6+ cores     |
| Disk      | 100 GB free | 200 GB free  |
| Network   | Any         | Gigabit LAN  |

### Per-VM Allocation

| VM    | RAM  | CPU | Disk  |
|-------|------|-----|-------|
| DC-01 | 4 GB | 2   | 60 GB |
| DC-02 | 4 GB | 2   | 60 GB |
| WS-01 | 4 GB | 2   | 60 GB |

---

## Software

### Required

| Software               | Version   | Notes                        |
|------------------------|-----------|------------------------------|
| VirtualBox             | 7.x       | Primary supported hypervisor |
| Windows Server 2019    | Any build | For DC-01 and DC-02          |
| Windows 10 or 11       | Any build | For WS-01 (attacker)         |

### Optional (for build-from-scratch)

| Software               | Purpose                    |
|------------------------|----------------------------|
| Windows Server 2019 ISO| VM installation            |
| Windows 10/11 ISO      | WS-01 installation         |

### Attack Tools (on WS-01)

Downloaded separately — see [tools/README.md](../tools/README.md)

| Tool            | Purpose                            |
|-----------------|------------------------------------|
| BloodHound 4.x  | AD graph analysis                  |
| SharpHound      | BloodHound data collector          |
| Rubeus          | Kerberos attack tool               |
| PowerView       | AD enumeration (PowerSploit)       |
| Mimikatz        | Credential extraction              |
| Certify         | ADCS attack tool                   |
| ADCSPwn         | NTLM relay to ADCS (ESC8)         |
| Impacket        | Python AD attack suite             |
| CrackMapExec    | Network protocol attack tool       |
| Hashcat         | Password cracking                  |

---

## Operating System Compatibility

| Host OS         | Status    | Notes                              |
|-----------------|-----------|------------------------------------|
| Windows 10/11   | Tested    | Full support                       |
| macOS (Intel)   | Tested    | VirtualBox 7.x required            |
| macOS (Apple Silicon) | Partial | VirtualBox 7.x beta, limited |
| Ubuntu 22.04    | Tested    | VirtualBox from Oracle repo        |

---

## VirtualBox Network Requirements

Two virtual networks are required:

1. **Host-Only Network** (`vboxnet0`): `192.168.56.0/24`
   - Allows VM-to-VM and host-to-VM communication
   - No external internet access
   - Static IPs required for DCs

2. **NAT Adapter** (default VirtualBox NAT):
   - Provides internet access for downloading tools
   - Separate from lab traffic

See [docs/NETWORK-SETUP.md](NETWORK-SETUP.md) for configuration steps.
