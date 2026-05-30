#!/usr/bin/env bash
# scripts/test-canary-deployment.sh
# Tests for canary deployment with health gating and rollback (#560).
#
# Drives scripts/canary-deploy.sh through its decision tree by injecting hook
# commands, and asserts the right terminal state (promote vs. rollback) for each:
#   1. Healthy canary           → promoted, exits 0
#   2. Unhealthy canary         → rolled back, exits 1
#   3. Deploy step fails        → rolled back, exits 1, never health-checks
#   4. Flaky-then-failing canary→ rolled back on first failed check
#   5. Promotion step fails     → rolled back, exits 1

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/tests/lib.sh"

CANARY="$SCRIPTS_DIR/canary-deploy.sh"

echo "=== Canary Deployment Testing (#560) ==="

setup_sandbox
trap teardown_sandbox EXIT

# No real sleeps between checks.
export HEALTH_INTERVAL=0
export HEALTH_RETRIES=3

# ── Case 1: healthy canary is promoted ────────────────────────────────────────
echo ""
echo "Case 1: Healthy canary → promote"
run_case "healthy canary exits 0" 0 env \
    CANARY_DEPLOY_CMD="true" \
    CANARY_HEALTH_CMD="true" \
    CANARY_PROMOTE_CMD="echo PROMOTED" \
    CANARY_ROLLBACK_CMD="echo SHOULD-NOT-ROLLBACK" \
    bash "$CANARY"
assert_contains "deployment marked successful" "CANARY DEPLOYMENT SUCCESSFUL"
assert_contains "promotion ran" "PROMOTED"

# A healthy run must never invoke rollback.
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$LAST_OUTPUT" | grep -qF "SHOULD-NOT-ROLLBACK"; then
    echo "  ✗ rollback must not run on healthy canary"
    TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_NAMES+=("no-rollback-on-healthy")
else
    echo "  ✓ rollback not invoked on healthy canary"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# ── Case 2: unhealthy canary is rolled back ───────────────────────────────────
echo ""
echo "Case 2: Unhealthy canary → rollback"
run_case "unhealthy canary exits 1" 1 env \
    CANARY_DEPLOY_CMD="true" \
    CANARY_HEALTH_CMD="false" \
    CANARY_PROMOTE_CMD="echo SHOULD-NOT-PROMOTE" \
    CANARY_ROLLBACK_CMD="echo ROLLED-BACK" \
    bash "$CANARY"
assert_contains "deployment marked failed" "CANARY DEPLOYMENT FAILED"
assert_contains "rollback ran" "ROLLED-BACK"

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$LAST_OUTPUT" | grep -qF "SHOULD-NOT-PROMOTE"; then
    echo "  ✗ promotion must not run on unhealthy canary"
    TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_NAMES+=("no-promote-on-unhealthy")
else
    echo "  ✓ promotion not invoked on unhealthy canary"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# ── Case 3: deploy failure rolls back before health checks ────────────────────
echo ""
echo "Case 3: Deploy step fails → rollback, no health checks"
run_case "deploy failure exits 1" 1 env \
    CANARY_DEPLOY_CMD="false" \
    CANARY_HEALTH_CMD="echo SHOULD-NOT-HEALTHCHECK" \
    CANARY_ROLLBACK_CMD="echo ROLLED-BACK" \
    bash "$CANARY"
assert_contains "deploy failure reported" "Canary deployment failed"

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$LAST_OUTPUT" | grep -qF "SHOULD-NOT-HEALTHCHECK"; then
    echo "  ✗ health check must not run when deploy fails"
    TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_NAMES+=("no-healthcheck-on-deploy-fail")
else
    echo "  ✓ health check skipped when deploy fails"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# ── Case 4: canary that fails partway through the gate is rolled back ──────────
echo ""
echo "Case 4: Health check fails on 2nd probe → rollback"
COUNTER="$SANDBOX/health_counter"
echo 0 > "$COUNTER"
# Passes the first probe, fails the second.
HEALTH_SCRIPT="n=\$(cat $COUNTER); n=\$((n+1)); echo \$n > $COUNTER; [ \$n -le 1 ]"
run_case "flaky canary exits 1" 1 env \
    CANARY_DEPLOY_CMD="true" \
    CANARY_HEALTH_CMD="$HEALTH_SCRIPT" \
    CANARY_PROMOTE_CMD="echo SHOULD-NOT-PROMOTE" \
    CANARY_ROLLBACK_CMD="echo ROLLED-BACK" \
    bash "$CANARY"
assert_contains "rolled back after partial failure" "ROLLED-BACK"
assert_contains "first probe passed" "Health check 1/3 passed"
assert_contains "second probe failed" "Health check 2/3 failed"

# ── Case 5: promotion failure rolls back ──────────────────────────────────────
echo ""
echo "Case 5: Promotion step fails → rollback"
run_case "promotion failure exits 1" 1 env \
    CANARY_DEPLOY_CMD="true" \
    CANARY_HEALTH_CMD="true" \
    CANARY_PROMOTE_CMD="false" \
    CANARY_ROLLBACK_CMD="echo ROLLED-BACK" \
    bash "$CANARY"
assert_contains "promotion failure reported" "Promotion failed"
assert_contains "rolled back after promotion failure" "ROLLED-BACK"

finish_suite
