# Disaster Recovery Testing (#558)

## Overview

A disaster recovery plan is only credible if it is exercised. `scripts/test-disaster-recovery.sh`
runs the full recovery chain — **back up → verify → restore → re-verify
services** — automatically, in a hermetic sandbox. External dependencies
(Stellar RPC, AWS S3, the live API, Postgres) are replaced by mocks, so the
drill runs anywhere without touching production infrastructure.

It complements the human-facing runbook in `docs/disaster-recovery-plan.md`,
turning the documented procedure into something CI can gate on.

```bash
bash scripts/test-disaster-recovery.sh
```

## Recovery chain under test

```
backup-contract-state.sh ─▶ verify-backup-integrity.sh ─▶ restore-contract-state.sh ─▶ verify-all-services.sh
```

## Scenarios

| # | Scenario | Expected outcome |
|---|----------|------------------|
| 1 | Back up contract state | Backup archive + checksum sidecar produced |
| 2 | Verify the fresh backup | Integrity check passes |
| 3 | Restore from backup (non-interactive) | Restore completes |
| 4 | Verify all services post-recovery | API, contracts and DB healthy |
| 5 | Corrupt/truncated backup | Rejected before restore |
| 6 | Backup missing required state | Rejected before restore |

## How the sandbox works

The suite sources `scripts/tests/lib.sh`, which:

- creates a throwaway working directory and a `mock-bin` directory prepended to `PATH`;
- installs mock `stellar-cli`, `aws`, `curl` and `pg_isready` commands that
  return controlled output;
- provides assertion helpers (`run_case`, `assert_contains`, …) and a
  `build_valid_backup` fixture.

Because the recovery scripts only ever call the mocked binaries, no real
Stellar transaction, S3 upload or HTTP request is made.

## Recovery objectives

These are defined in `docs/disaster-recovery-plan.md` and the drill validates
that the mechanical steps behind them work:

| Objective | Target |
|-----------|--------|
| RTO (Recovery Time Objective) | 4 hours |
| RPO (Recovery Point Objective) | 1 hour |
| MTD (Maximum Tolerable Downtime) | 24 hours |

## CI integration

`.github/workflows/ops-tests.yml` runs this suite (via
`scripts/run-ops-tests.sh`) on every change under `scripts/`, so a regression
in any recovery script fails the build.

## Running a real drill

In a staging environment with real credentials, run the underlying scripts
directly instead of the test harness:

```bash
export IP_REGISTRY_CONTRACT_ID=... ATOMIC_SWAP_CONTRACT_ID=... NETWORK=testnet
./scripts/backup-contract-state.sh
./scripts/verify-backup-integrity.sh /var/backups/atomicip/backup_*.tar.gz
./scripts/activate-dr-site.sh   # full DR-site activation
```
