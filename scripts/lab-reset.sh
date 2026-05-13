#!/usr/bin/env bash
# Reset all AD Lab VMs to the Clean-Baseline snapshot

set -euo pipefail

DC01="AD-Lab-DC01"
DC02="AD-Lab-DC02"
WS01="AD-Lab-WS01"
SNAPSHOT="Clean-Baseline"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*"; }

echo ""
echo "=============================="
echo "  AD Lab — Reset to Snapshot"
echo "=============================="
echo ""
warn "This will discard ALL changes made since the '$SNAPSHOT' snapshot."
echo ""
read -r -p "Are you sure? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

restore_vm() {
    local name="$1"
    local state
    state=$(VBoxManage showvminfo "$name" --machinereadable 2>/dev/null | grep VMState= | cut -d'"' -f2 || echo "unknown")

    if [[ "$state" == "running" ]]; then
        log "Powering off $name..."
        VBoxManage controlvm "$name" poweroff
        sleep 3
    fi

    log "Restoring $name to snapshot: $SNAPSHOT..."
    if VBoxManage snapshot "$name" restore "$SNAPSHOT"; then
        log "$name restored successfully."
    else
        err "Snapshot '$SNAPSHOT' not found on $name. Skipping."
    fi
}

restore_vm "$WS01"
restore_vm "$DC02"
restore_vm "$DC01"

echo ""
log "Reset complete. Run ./scripts/lab-start.sh to start."
echo ""
