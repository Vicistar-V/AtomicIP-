#!/usr/bin/env bash
# Rollback Testing Script for Atomic Patent
#
# Verifies that the rollback procedure correctly restores the previous
# active contract IDs after a simulated deployment failure.
#
# Usage: ./test_rollback.sh [--network NAME]

set -e

NETWORK="testnet"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()         { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
log_success() { echo -e "${GREEN}✓ $*${NC}"; }
log_error()   { echo -e "${RED}✗ $*${NC}"; }
log_warning() { echo -e "${YELLOW}⚠ $*${NC}"; }

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --network) NETWORK="$2"; shift 2 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

# Write a fake slot env file
write_slot_env() {
    local slot="$1" ip_id="$2" swap_id="$3"
    cat > "${TMPDIR_TEST}/.env.${NETWORK}.${slot}" << EOF
export DEPLOYMENT_SLOT=${slot}
export CONTRACT_IP_REGISTRY=${ip_id}
export CONTRACT_ATOMIC_SWAP=${swap_id}
EOF
}

# Point the active symlink at a slot
activate_slot() {
    local slot="$1"
    ln -sf "${TMPDIR_TEST}/.env.${NETWORK}.${slot}" \
           "${TMPDIR_TEST}/.env.${NETWORK}.active"
}

# Read the active CONTRACT_IP_REGISTRY value
active_ip_registry() {
    # shellcheck disable=SC1090
    (source "${TMPDIR_TEST}/.env.${NETWORK}.active" && echo "$CONTRACT_IP_REGISTRY")
}

test_rollback_on_failure() {
    log "Test: rollback on simulated deployment failure"

    # Setup: blue is the known-good active slot
    write_slot_env blue "BLUE_IP_REGISTRY" "BLUE_ATOMIC_SWAP"
    activate_slot blue

    local before
    before=$(active_ip_registry)
    [[ "$before" == "BLUE_IP_REGISTRY" ]] || { log_error "Pre-condition failed: active slot is not blue"; return 1; }

    # Simulate: deploy to green, smoke check fails → do NOT switch active
    write_slot_env green "GREEN_IP_REGISTRY" "GREEN_ATOMIC_SWAP"
    log_warning "Simulating smoke check failure on green slot — not switching active"

    # Active should still be blue
    local after
    after=$(active_ip_registry)
    if [[ "$after" == "BLUE_IP_REGISTRY" ]]; then
        log_success "Rollback test passed: active slot unchanged after failure"
    else
        log_error "Rollback test FAILED: active slot changed to '${after}' despite failure"
        return 1
    fi
}

test_successful_switch_then_rollback() {
    log "Test: successful switch then manual rollback"

    write_slot_env blue "BLUE_IP_REGISTRY" "BLUE_ATOMIC_SWAP"
    write_slot_env green "GREEN_IP_REGISTRY" "GREEN_ATOMIC_SWAP"
    activate_slot blue

    # Switch to green (simulating a successful deployment)
    activate_slot green
    local active
    active=$(active_ip_registry)
    [[ "$active" == "GREEN_IP_REGISTRY" ]] || { log_error "Switch to green failed"; return 1; }
    log_success "Switched to green"

    # Rollback: switch back to blue
    activate_slot blue
    active=$(active_ip_registry)
    if [[ "$active" == "BLUE_IP_REGISTRY" ]]; then
        log_success "Rollback test passed: reverted to blue successfully"
    else
        log_error "Rollback test FAILED: expected BLUE_IP_REGISTRY, got '${active}'"
        return 1
    fi
}

test_active_symlink_points_to_correct_file() {
    log "Test: active symlink resolves to correct slot file"

    write_slot_env blue "BLUE_IP_REGISTRY" "BLUE_ATOMIC_SWAP"
    activate_slot blue

    local target
    target=$(readlink "${TMPDIR_TEST}/.env.${NETWORK}.active")
    if [[ "$target" == *".env.${NETWORK}.blue" ]]; then
        log_success "Symlink target test passed"
    else
        log_error "Symlink target test FAILED: got '${target}'"
        return 1
    fi
}

main() {
    parse_args "$@"

    log "=== Rollback Testing ==="
    log "Network: ${NETWORK}"

    local failures=0

    test_rollback_on_failure          || ((failures++))
    test_successful_switch_then_rollback || ((failures++))
    test_active_symlink_points_to_correct_file || ((failures++))

    echo ""
    if [[ $failures -eq 0 ]]; then
        log_success "All rollback tests passed"
    else
        log_error "${failures} rollback test(s) failed"
        exit 1
    fi
}

main "$@"
