#!/usr/bin/env bash
# scripts/test-backup-integrity.sh
# Tests for backup integrity verification (#559).
#
# Exercises scripts/verify-backup-integrity.sh against a matrix of healthy and
# damaged backups to prove the verifier accepts good archives and rejects every
# class of corruption: bad archive, missing state, malformed JSON, and a
# checksum that does not match its sidecar.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/tests/lib.sh"

VERIFY="$SCRIPTS_DIR/verify-backup-integrity.sh"

echo "=== Backup Integrity Verification (#559) ==="

setup_sandbox
trap teardown_sandbox EXIT

# ── Case 1: a well-formed backup passes ───────────────────────────────────────
echo ""
echo "Case 1: Valid backup"
GOOD="$SANDBOX/good.tar.gz"
build_valid_backup "$GOOD"
run_case "valid backup passes" 0 bash "$VERIFY" "$GOOD"
assert_contains "reports success" "Backup verification passed"

# ── Case 2: matching checksum sidecar passes ──────────────────────────────────
echo ""
echo "Case 2: Valid backup with matching checksum sidecar"
sha256sum "$GOOD" > "$GOOD.sha256"
run_case "matching checksum passes" 0 bash "$VERIFY" "$GOOD"
assert_contains "checksum verified" "Checksum matches"

# ── Case 3: tampered archive with stale checksum fails ────────────────────────
echo ""
echo "Case 3: Checksum mismatch (archive changed after checksum written)"
TAMPERED="$SANDBOX/tampered.tar.gz"
build_valid_backup "$TAMPERED" "20260202_000000"
sha256sum "$GOOD" > "$TAMPERED.sha256"   # sidecar belongs to a different archive
run_case "checksum mismatch fails" 1 bash "$VERIFY" "$TAMPERED"
assert_contains "mismatch reported" "Checksum mismatch"

# ── Case 4: corrupt archive fails ─────────────────────────────────────────────
echo ""
echo "Case 4: Corrupt archive"
CORRUPT="$SANDBOX/corrupt.tar.gz"
head -c 512 /dev/urandom > "$CORRUPT"
run_case "corrupt archive fails" 1 bash "$VERIFY" "$CORRUPT"
assert_contains "corruption reported" "corrupted"

# ── Case 5: missing required state file fails ─────────────────────────────────
echo ""
echo "Case 5: Missing required state file"
MISSING_STAGE="$SANDBOX/missing/20260303_000000"
mkdir -p "$MISSING_STAGE"
echo '{"timestamp":"x"}' > "$MISSING_STAGE/metadata.json"
echo '[]' > "$MISSING_STAGE/ip_registry_state.json"
# atomic_swap_state.json intentionally omitted
MISSING="$SANDBOX/missing.tar.gz"
tar -czf "$MISSING" -C "$SANDBOX/missing" "20260303_000000"
run_case "missing state file fails" 1 bash "$VERIFY" "$MISSING"
assert_contains "missing file reported" "(missing)"

# ── Case 6: malformed JSON fails ──────────────────────────────────────────────
echo ""
echo "Case 6: Malformed JSON in state file"
BADJSON_STAGE="$SANDBOX/badjson/20260404_000000"
mkdir -p "$BADJSON_STAGE"
echo '{"timestamp":"x"}' > "$BADJSON_STAGE/metadata.json"
echo 'not valid json {' > "$BADJSON_STAGE/ip_registry_state.json"
echo '[]' > "$BADJSON_STAGE/atomic_swap_state.json"
BADJSON="$SANDBOX/badjson.tar.gz"
tar -czf "$BADJSON" -C "$SANDBOX/badjson" "20260404_000000"
run_case "malformed JSON fails" 1 bash "$VERIFY" "$BADJSON"
assert_contains "invalid JSON reported" "invalid JSON"

# ── Case 7: missing file argument fails with usage ────────────────────────────
echo ""
echo "Case 7: No argument"
run_case "missing argument fails" 1 bash "$VERIFY"
assert_contains "prints usage" "Usage:"

# ── Case 8: nonexistent file fails ────────────────────────────────────────────
echo ""
echo "Case 8: Nonexistent file"
run_case "nonexistent file fails" 1 bash "$VERIFY" "$SANDBOX/does-not-exist.tar.gz"
assert_contains "not-found reported" "not found"

finish_suite
