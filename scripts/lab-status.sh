#!/usr/bin/env bash
# Show status of all AD Lab VMs

DC01="AD-Lab-DC01"
DC02="AD-Lab-DC02"
WS01="AD-Lab-WS01"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

vm_status() {
    local name="$1"
    local ip="$2"
    local role="$3"
    local state

    state=$(VBoxManage showvminfo "$name" --machinereadable 2>/dev/null | grep "^VMState=" | cut -d'"' -f2 || echo "not-found")

    local color="$RED"
    local symbol="[-]"
    if [[ "$state" == "running" ]]; then
        color="$GREEN"
        symbol="[+]"
    elif [[ "$state" == "saved" || "$state" == "paused" ]]; then
        color="$YELLOW"
        symbol="[~]"
    fi

    printf "  ${color}${symbol}${NC}  %-18s  %-18s  %-12s  %s\n" "$name" "$ip" "$state" "$role"
}

echo ""
echo "=============================="
echo "  AD Lab — VM Status"
echo "=============================="
echo ""
printf "  %-4s  %-18s  %-18s  %-12s  %s\n" "" "VM NAME" "IP" "STATE" "ROLE"
printf "  %s\n" "-----------------------------------------------------------------------"
vm_status "$DC01" "192.168.56.10" "corp.local DC + CA"
vm_status "$DC02" "192.168.56.20" "dev.corp.local DC"
vm_status "$WS01" "192.168.56.30" "Attacker WS"
echo ""

# Ping check
echo "  Connectivity check:"
for ip in 192.168.56.10 192.168.56.20 192.168.56.30; do
    if ping -c 1 -W 1 "$ip" &>/dev/null 2>&1; then
        echo -e "  ${GREEN}[+]${NC}  $ip  reachable"
    else
        echo -e "  ${RED}[-]${NC}  $ip  unreachable"
    fi
done
echo ""
