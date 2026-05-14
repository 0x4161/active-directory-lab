#!/usr/bin/env bash
# Start all AD Lab VMs in the correct order

set -euo pipefail

DC01="AD-Lab-DC01"
DC02="AD-Lab-DC02"
WS01="AD-Lab-Attacker"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; }

start_vm() {
    local name="$1"
    local state
    state=$(VBoxManage showvminfo "$name" --machinereadable 2>/dev/null | grep VMState= | cut -d'"' -f2 || echo "unknown")

    if [[ "$state" == "running" ]]; then
        warn "$name is already running"
        return 0
    fi

    log "Starting $name..."
    VBoxManage startvm "$name" --type headless
}

echo ""
echo "=============================="
echo "  AD Lab — Starting VMs"
echo "=============================="
echo ""

# Start DC-01 first (forest root)
start_vm "$DC01"
log "Waiting 45 seconds for DC-01 to initialize..."
sleep 45

# Then DC-02
start_vm "$DC02"
log "Waiting 30 seconds for DC-02 to initialize..."
sleep 30

# Then attacker workstation
start_vm "$WS01"

echo ""
log "All VMs started."
echo ""
echo "  DC-01  : 192.168.56.10  (corp.local)"
echo "  DC-02  : 192.168.56.20  (dev.corp.local)"
echo "  WS-01  : 192.168.56.30  (attacker)"
echo ""
echo "  Login  : corp\\attacker.01 / p@ssw0rd"
echo ""
echo "Run ./scripts/lab-status.sh to verify everything is up."
echo ""
