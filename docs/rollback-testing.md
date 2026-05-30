# Rollback Testing

Rollback testing verifies that the deployment rollback procedure works correctly — after a failed or bad deployment, the system can revert to the previous known-good state without data loss or downtime.

## What Is Tested

| Test | Description |
|---|---|
| Failure isolation | Active slot is unchanged when a smoke check fails |
| Manual rollback | Switching back from a new slot to the previous slot works correctly |
| Symlink integrity | The `.env.{network}.active` symlink resolves to the correct slot file |

## How to Run

```bash
# Run all rollback tests (uses testnet by default)
./scripts/test_rollback.sh

# Run against a specific network label
./scripts/test_rollback.sh --network mainnet
```

All tests run locally using temporary files — no live network connection required.

## Expected Output

```
✓ Rollback test passed: active slot unchanged after failure
✓ Rollback test passed: reverted to blue successfully
✓ Symlink target test passed
✓ All rollback tests passed
```

Exit code `0` means all tests passed. Non-zero means at least one test failed.

## CI

The **Rollback Test** workflow runs automatically on every push to `main` and can also be triggered manually from the Actions tab.

## Performing a Real Rollback

If a live deployment needs to be rolled back:

```bash
# Revert to the blue slot
ln -sf .env.testnet.blue .env.testnet.active
source .env.testnet.active
echo "Rolled back to: $DEPLOYMENT_SLOT ($CONTRACT_IP_REGISTRY)"
```

See [Blue-Green Deployment](blue-green-deployment.md) for the full deployment flow.
