#!/usr/bin/env bash
# scripts/tests/lib.sh
# Shared helpers for the operational shell-script test suites
# (#558 disaster recovery, #559 backup integrity, #560 canary deployment).
#
# These helpers let the ops scripts be exercised hermetically — no AWS, no
# Stellar RPC, no live API. External commands are replaced by mocks placed on
# a throwaway PATH so the control flow of each script can be asserted offline.

# ── Counters ────────────────────────────────────────────────────────────────
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

# Root directory of the repository (two levels up from this file).
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# ── Sandbox management ────────────────────────────────────────────────────────

# Create an isolated working directory and a mock-binary directory, and prepend
# the mock dir to PATH. Returns the sandbox path via the SANDBOX global.
setup_sandbox() {
    SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/atomicip_optest.XXXXXX")"
    MOCK_BIN="$SANDBOX/mock-bin"
    mkdir -p "$MOCK_BIN"
    ORIGINAL_PATH="$PATH"
    export PATH="$MOCK_BIN:$PATH"
}

teardown_sandbox() {
    export PATH="$ORIGINAL_PATH"
    [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
    SANDBOX=""
}

# Write an executable mock command onto the sandbox PATH.
#   mock_command <name> <body>
# The body is a bash snippet; "$@" holds the args the script passed.
mock_command() {
    local name="$1"
    local body="$2"
    cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$MOCK_BIN/$name"
}

# ── Assertions ────────────────────────────────────────────────────────────────

# run_case <name> <expected_exit> <command...>
# Runs the command, captures combined output into LAST_OUTPUT, and asserts the
# exit code matches the expectation.
run_case() {
    local name="$1"
    local expected="$2"
    shift 2

    TESTS_RUN=$((TESTS_RUN + 1))
    local actual=0
    LAST_OUTPUT="$("$@" 2>&1)" || actual=$?

    if [ "$actual" -eq "$expected" ]; then
        echo "  ✓ $name (exit $actual)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "  ✗ $name — expected exit $expected, got $actual"
        echo "    ── output ──"
        echo "$LAST_OUTPUT" | sed 's/^/    /'
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES+=("$name")
        return 1
    fi
}

# assert_contains <name> <needle>  — checks LAST_OUTPUT from the previous run_case.
assert_contains() {
    local name="$1"
    local needle="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$LAST_OUTPUT" | grep -qF -- "$needle"; then
        echo "  ✓ $name (found \"$needle\")"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  ✗ $name — expected output to contain \"$needle\""
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES+=("$name")
    fi
}

# assert_file_exists <name> <path>
assert_file_exists() {
    local name="$1"
    local path="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$path" ]; then
        echo "  ✓ $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  ✗ $name — expected file: $path"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES+=("$name")
    fi
}

# Print a summary and return non-zero if anything failed.
finish_suite() {
    echo ""
    echo "──────────────────────────────────────────"
    echo "  $TESTS_PASSED/$TESTS_RUN checks passed"
    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo "  Failed: ${FAILED_NAMES[*]}"
        echo "──────────────────────────────────────────"
        return 1
    fi
    echo "──────────────────────────────────────────"
    return 0
}

# ── Fixtures ──────────────────────────────────────────────────────────────────

# build_valid_backup <dest_tarball>
# Produces a well-formed backup archive identical in shape to what
# backup-contract-state.sh emits: a timestamped directory containing
# metadata.json, ip_registry_state.json and atomic_swap_state.json.
build_valid_backup() {
    local dest="$1"
    local stamp="${2:-20260101_000000}"
    local stage="$SANDBOX/stage_$stamp"
    mkdir -p "$stage/$stamp"
    cat > "$stage/$stamp/metadata.json" <<EOF
{
  "timestamp": "$stamp",
  "network": "testnet",
  "ip_registry_contract": "CIPREGISTRY000000000000000000000000000000000000000000000",
  "atomic_swap_contract": "CATOMICSWAP0000000000000000000000000000000000000000000000",
  "ledger_sequence": 12345
}
EOF
    echo '[{"ip_id":1,"owner":"GTEST","commitment_hash":"01"}]' \
        > "$stage/$stamp/ip_registry_state.json"
    echo '[{"swap_id":1,"ip_id":1,"price":1000}]' \
        > "$stage/$stamp/atomic_swap_state.json"
    tar -czf "$dest" -C "$stage" "$stamp"
    rm -rf "$stage"
}
