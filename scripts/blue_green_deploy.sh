#!/usr/bin/env bash
# Blue-Green Deployment Script for Atomic Patent
#
# Usage: ./blue_green_deploy.sh [OPTIONS]
# Options:
#   --network NAME   Network to deploy to (testnet, mainnet) [default: testnet]
#   --slot SLOT      Deployment slot: blue or green [required]
#   --dry-run        Simulate without executing
#   --verbose        Enable verbose output

set -e

NETWORK="testnet"
SLOT=""
DRY_RUN=false
VERBOSE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()         { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
log_success() { echo -e "${GREEN}✓ $*${NC}"; }
log_error()   { echo -e "${RED}✗ $*${NC}"; }
log_warning() { echo -e "${YELLOW}⚠ $*${NC}"; }

run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] $*"
    else
        [[ "$VERBOSE" == true ]] && log "Running: $*"
        eval "$@"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --network) NETWORK="$2"; shift 2 ;;
            --slot)    SLOT="$2";    shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "$SLOT" ]]; then
        log_error "--slot is required (blue or green)"
        exit 1
    fi

    if [[ "$SLOT" != "blue" && "$SLOT" != "green" ]]; then
        log_error "--slot must be 'blue' or 'green'"
        exit 1
    fi
}

deploy_slot() {
    local slot_env=".env.${NETWORK}.${SLOT}"
    log "Deploying contracts to slot '${SLOT}' on ${NETWORK}..."

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would deploy ip_registry and atomic_swap to slot ${SLOT}"
        IP_REGISTRY="DRY_RUN_IP_REGISTRY_${SLOT}"
        ATOMIC_SWAP="DRY_RUN_ATOMIC_SWAP_${SLOT}"
    else
        IP_REGISTRY=$(stellar contract deploy \
            --wasm target/wasm32-unknown-unknown/release/ip_registry.wasm \
            --source deployer \
            --network "$NETWORK")
        ATOMIC_SWAP=$(stellar contract deploy \
            --wasm target/wasm32-unknown-unknown/release/atomic_swap.wasm \
            --source deployer \
            --network "$NETWORK")
    fi

    cat > "$slot_env" << EOF
# Blue-Green slot: ${SLOT} — deployed $(date -u +%Y-%m-%dT%H:%M:%SZ)
export STELLAR_NETWORK=${NETWORK}
export DEPLOYMENT_SLOT=${SLOT}
export CONTRACT_IP_REGISTRY=${IP_REGISTRY}
export CONTRACT_ATOMIC_SWAP=${ATOMIC_SWAP}
EOF
    log_success "Slot '${SLOT}' env written to ${slot_env}"
}

smoke_check() {
    log "Running smoke check on slot '${SLOT}'..."

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Smoke check skipped"
        return 0
    fi

    # Verify the IP Registry contract is callable
    stellar contract invoke \
        --id "$IP_REGISTRY" \
        --source deployer \
        --network "$NETWORK" \
        -- list_ip_by_owner \
        --owner "$(stellar keys address deployer)" \
        > /dev/null 2>&1 \
        && log_success "Smoke check passed" \
        || { log_error "Smoke check failed — aborting traffic switch"; exit 1; }
}

switch_traffic() {
    local active_link=".env.${NETWORK}.active"
    local slot_env=".env.${NETWORK}.${SLOT}"

    log "Switching active traffic to slot '${SLOT}'..."
    run_cmd "ln -sf '${slot_env}' '${active_link}'"
    log_success "Active slot is now '${SLOT}' (${active_link} -> ${slot_env})"
}

main() {
    parse_args "$@"

    log "=== Blue-Green Deployment ==="
    log "Network: ${NETWORK} | Slot: ${SLOT}"

    deploy_slot
    smoke_check
    switch_traffic

    log_success "=== Blue-Green Deployment Complete ==="
    log "To activate: source .env.${NETWORK}.active"
}

main "$@"
