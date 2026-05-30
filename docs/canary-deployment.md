# Canary Deployment Testing (#560)

## Overview

A canary deployment rolls a new version out to a small slice of
traffic/infrastructure first, health-checks it, and only promotes it to the full
fleet if it stays healthy. If the canary fails, it is rolled back automatically.
`scripts/canary-deploy.sh` implements this flow and `scripts/test-canary-deployment.sh`
verifies the decision tree (promote vs. rollback) for every branch.

```bash
# Run a canary deployment (uses real hooks / defaults)
./scripts/canary-deploy.sh

# Run the canary logic test suite
bash scripts/test-canary-deployment.sh
```

## Flow

```
deploy canary ──▶ health gate (N consecutive checks) ──┬─ healthy ─▶ promote ─▶ SUCCESS
                                                        └─ unhealthy ─▶ rollback ─▶ FAIL (exit 1)
```

1. **Deploy** the new version to the canary slot. If deploy fails → rollback, exit 1.
2. **Health gate**: require `HEALTH_RETRIES` consecutive successful checks,
   `HEALTH_INTERVAL` seconds apart. Any failed check → rollback, exit 1.
3. **Promote** the canary to the full fleet. If promotion fails → rollback, exit 1.
4. On full success, exit 0.

Exit code `0` means promoted; `1` means failed-and-rolled-back, so CI/CD can
gate the rollout on it.

## Pluggable hooks

The four side-effecting steps are command hooks, overridable via the
environment. This lets the same script run against real infrastructure in
production and against mocks in tests:

| Variable | Purpose | Default |
|----------|---------|---------|
| `CANARY_DEPLOY_CMD` | Deploy the new version to the canary slot | `stellar contract deploy --network $NETWORK` |
| `CANARY_HEALTH_CMD` | Return 0 if the canary is healthy | `curl -sf $CANARY_HEALTH_URL` |
| `CANARY_PROMOTE_CMD` | Promote canary to the full fleet | `echo Promoting canary to full fleet` |
| `CANARY_ROLLBACK_CMD` | Tear down the canary / restore previous version | `echo Rolling back canary` |

Tuning knobs:

| Variable | Purpose | Default |
|----------|---------|---------|
| `HEALTH_RETRIES` | Consecutive successful checks required | `3` |
| `HEALTH_INTERVAL` | Seconds between checks (set `0` in tests) | `5` |
| `CANARY_HEALTH_URL` | Default health endpoint | `https://canary.atomicip.io/health` |
| `NETWORK` | Target network label | `testnet` |

## Example

```bash
export NETWORK=testnet
export CANARY_DEPLOY_CMD="./scripts/deploy.sh --network testnet --canary"
export CANARY_HEALTH_CMD="./scripts/smoke-test.sh"
export CANARY_PROMOTE_CMD="./scripts/promote-canary.sh"
export CANARY_ROLLBACK_CMD="./scripts/rollback.sh"
./scripts/canary-deploy.sh
```

## Test matrix

The suite in `scripts/test-canary-deployment.sh` drives the script through every
branch by injecting hook commands:

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Healthy canary | Promoted, exit 0, rollback never runs |
| 2 | Unhealthy canary | Rolled back, exit 1, promotion never runs |
| 3 | Deploy step fails | Rolled back, exit 1, health checks skipped |
| 4 | Canary fails on the 2nd probe | Rolled back on first failed check |
| 5 | Promotion step fails | Rolled back, exit 1 |

## CI integration

`.github/workflows/ops-tests.yml` runs this suite (via
`scripts/run-ops-tests.sh`) on every change under `scripts/`.
