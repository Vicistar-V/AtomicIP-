#!/usr/bin/env bash
# scripts/canary-deploy.sh
# Canary deployment with automated health gating and rollback (#560).
#
# A canary release is rolled out to a small slice of traffic/infrastructure
# first, health-checked, and only promoted to the full fleet if it stays
# healthy. If the canary fails its health checks it is rolled back automatically
# and the script exits non-zero so CI/CD halts the rollout.
#
# The four side-effecting steps are pluggable command hooks so the script can be
# driven against real infrastructure in production and against mocks in tests:
#
#   CANARY_DEPLOY_CMD     deploy the new version to the canary slot
#   CANARY_HEALTH_CMD     return 0 if the canary is healthy, non-zero otherwise
#   CANARY_PROMOTE_CMD    promote the canary to the full fleet
#   CANARY_ROLLBACK_CMD   tear the canary down / restore the previous version
#
# Tuning knobs:
#   HEALTH_RETRIES   number of consecutive successful checks required (default 3)
#   HEALTH_INTERVAL  seconds to sleep between checks (default 5; set 0 in tests)
#   NETWORK          target network label, informational (default testnet)
#
# Exit codes: 0 = canary healthy and promoted; 1 = failed and rolled back.

set -uo pipefail

NETWORK="${NETWORK:-testnet}"
HEALTH_RETRIES="${HEALTH_RETRIES:-3}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-5}"
CANARY_HEALTH_URL="${CANARY_HEALTH_URL:-https://canary.atomicip.io/health}"

# Default hooks. Each may be overridden via the environment.
CANARY_DEPLOY_CMD="${CANARY_DEPLOY_CMD:-stellar contract deploy --network $NETWORK}"
CANARY_HEALTH_CMD="${CANARY_HEALTH_CMD:-curl -sf $CANARY_HEALTH_URL}"
CANARY_PROMOTE_CMD="${CANARY_PROMOTE_CMD:-echo Promoting canary to full fleet}"
CANARY_ROLLBACK_CMD="${CANARY_ROLLBACK_CMD:-echo Rolling back canary}"

echo "=== Canary Deployment ($NETWORK) ==="
echo "Health gate: $HEALTH_RETRIES consecutive checks, ${HEALTH_INTERVAL}s apart"
echo ""

rollback() {
    echo ""
    echo "CANARY: rolling back"
    if eval "$CANARY_ROLLBACK_CMD"; then
        echo "✓ Rollback complete"
    else
        echo "✗ Rollback command failed — MANUAL INTERVENTION REQUIRED"
    fi
    echo "=== CANARY DEPLOYMENT FAILED — ROLLED BACK ==="
}

# ── Step 1: deploy the canary ─────────────────────────────────────────────────
echo "Step 1: Deploying canary..."
if ! eval "$CANARY_DEPLOY_CMD"; then
    echo "✗ Canary deployment failed"
    rollback
    exit 1
fi
echo "✓ Canary deployed"

# ── Step 2: health gate ───────────────────────────────────────────────────────
echo ""
echo "Step 2: Health-checking canary..."
attempt=0
while [ "$attempt" -lt "$HEALTH_RETRIES" ]; do
    attempt=$((attempt + 1))
    if eval "$CANARY_HEALTH_CMD" > /dev/null 2>&1; then
        echo "✓ Health check $attempt/$HEALTH_RETRIES passed"
    else
        echo "✗ Health check $attempt/$HEALTH_RETRIES failed"
        rollback
        exit 1
    fi
    if [ "$attempt" -lt "$HEALTH_RETRIES" ] && [ "$HEALTH_INTERVAL" -gt 0 ]; then
        sleep "$HEALTH_INTERVAL"
    fi
done

# ── Step 3: promote ───────────────────────────────────────────────────────────
echo ""
echo "Step 3: Canary healthy — promoting to full fleet..."
if ! eval "$CANARY_PROMOTE_CMD"; then
    echo "✗ Promotion failed"
    rollback
    exit 1
fi
echo "✓ Promotion complete"
echo ""
echo "=== CANARY DEPLOYMENT SUCCESSFUL ==="
