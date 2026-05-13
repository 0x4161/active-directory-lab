#!/usr/bin/env bash
# Gracefully shut down all AD Lab VMs

set -euo pipefail

DC01="AD-Lab-DC01"
DC02="AD-Lab-DC02"
WS01="AD-Lab-WS01"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

stop_vm() {
    local name="$1"
    local state
    state=$(VBoxManage showvminfo "$name" --machinereadable 2>/dev/null | grep VMState= | cut -d'"' -f2 || echo "unknown")

    if [[ "$state" != "running" ]]; then
        warn "$name is not running (state: $state)"
        return 0
    fi

    log "Stopping $name..."
    VBoxManage controlvm "$name" acpipowerbutton || true
}

echo ""
echo "=============================="
echo "  AD Lab — Stopping VMs"
echo "=============================="
echo ""

# Stop in reverse order
stop_vm "$WS01"
sleep 5
stop_vm "$DC02"
sleep 5
stop_vm "$DC01"

echo ""
log "Shutdown signals sent. VMs will power off in ~30 seconds."
echo ""
