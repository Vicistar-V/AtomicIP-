#!/usr/bin/env bash
# scripts/test-disaster-recovery.sh
# Automated disaster-recovery drill (#558).
#
# Exercises the full backup → verify → restore recovery chain end-to-end in a
# hermetic sandbox. External dependencies (Stellar RPC, AWS S3, the live API,
# Postgres) are replaced by mocks, so the drill runs anywhere — locally or in
# CI — without touching production infrastructure.
#
# Scenarios covered:
#   1. A backup can be produced from contract state.
#   2. The produced backup passes integrity verification.
#   3. The backup can be restored (non-interactive confirmation).
#   4. All services report healthy after recovery.
#   5. A truncated/corrupt backup is rejected before any restore is attempted.
#   6. A backup missing required state is rejected.
#
# Exit code is non-zero if any scenario fails, so CI can gate on it.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/tests/lib.sh"

echo "=== Disaster Recovery Drill (#558) ==="

setup_sandbox
trap teardown_sandbox EXIT

# ── Mock external services ────────────────────────────────────────────────────
# stellar-cli is used by backup-contract-state.sh (state export + ledger query)
# and verify-all-services.sh (contract reachability).
mock_command stellar-cli '
case "$*" in
  *"network status"*) echo "{\"ledger\": 12345}" ;;
  *"contract invoke"*get_ip_count*)   echo "0" ;;
  *"contract invoke"*get_swap_count*) echo "0" ;;
  *"contract invoke"*list_all_ips*)   echo "[{\"ip_id\":1,\"owner\":\"GTEST\"}]" ;;
  *"contract invoke"*list_all_swaps*) echo "[{\"swap_id\":1,\"ip_id\":1}]" ;;
  *) echo "[]" ;;
esac
'
# verify-all-services.sh probes the API and DB; make them all healthy.
mock_command curl 'exit 0'
mock_command pg_isready 'exit 0'
mock_command aws 'echo "mock-aws $*"; exit 0'

export BACKUP_DIR="$SANDBOX/backups"
export NETWORK="testnet"
export IP_REGISTRY_CONTRACT_ID="CIPREGISTRY000000000000000000000000000000000000000000000"
export ATOMIC_SWAP_CONTRACT_ID="CATOMICSWAP0000000000000000000000000000000000000000000000"

# ── Scenario 1: produce a backup ──────────────────────────────────────────────
echo ""
echo "Scenario 1: Back up contract state"
run_case "backup-contract-state.sh succeeds" 0 \
    bash "$SCRIPTS_DIR/backup-contract-state.sh"
assert_contains "backup reports completion" "Backup completed"

BACKUP_FILE="$(find "$BACKUP_DIR" -name 'backup_*.tar.gz' 2>/dev/null | head -1)"
assert_file_exists "backup archive was created" "$BACKUP_FILE"

# ── Scenario 2: verify the backup ─────────────────────────────────────────────
echo ""
echo "Scenario 2: Verify backup integrity"
run_case "verify-backup-integrity.sh passes on fresh backup" 0 \
    bash "$SCRIPTS_DIR/verify-backup-integrity.sh" "$BACKUP_FILE"
assert_contains "verification passes" "Backup verification passed"

# ── Scenario 3: restore the backup (non-interactive) ──────────────────────────
echo ""
echo "Scenario 3: Restore from backup"
restore_with_yes() { echo "yes" | bash "$SCRIPTS_DIR/restore-contract-state.sh" "$BACKUP_FILE"; }
run_case "restore-contract-state.sh completes" 0 restore_with_yes
assert_contains "restore reaches completion" "Restoration completed"

# ── Scenario 4: services healthy after recovery ───────────────────────────────
echo ""
echo "Scenario 4: Post-recovery service verification"
run_case "verify-all-services.sh reports healthy" 0 \
    bash "$SCRIPTS_DIR/verify-all-services.sh"
assert_contains "all services verified" "All Services Verified"

# ── Scenario 5: corrupt backup is rejected ────────────────────────────────────
echo ""
echo "Scenario 5: Corrupt backup must be rejected"
CORRUPT="$SANDBOX/corrupt.tar.gz"
head -c 256 /dev/urandom > "$CORRUPT"
run_case "verify rejects corrupt archive" 1 \
    bash "$SCRIPTS_DIR/verify-backup-integrity.sh" "$CORRUPT"

# ── Scenario 6: incomplete backup is rejected ─────────────────────────────────
echo ""
echo "Scenario 6: Incomplete backup must be rejected"
INCOMPLETE_STAGE="$SANDBOX/incomplete/20260101_000000"
mkdir -p "$INCOMPLETE_STAGE"
echo '{"timestamp":"x","network":"testnet"}' > "$INCOMPLETE_STAGE/metadata.json"
# ip_registry_state.json and atomic_swap_state.json deliberately omitted.
INCOMPLETE="$SANDBOX/incomplete.tar.gz"
tar -czf "$INCOMPLETE" -C "$SANDBOX/incomplete" "20260101_000000"
run_case "verify rejects incomplete backup" 1 \
    bash "$SCRIPTS_DIR/verify-backup-integrity.sh" "$INCOMPLETE"
assert_contains "missing-file failure reported" "verification failed"

finish_suite
