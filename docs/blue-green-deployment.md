# Blue-Green Deployment

Blue-green deployment keeps two identical contract slots — **blue** and **green** — so you can deploy to the idle slot, verify it, then switch traffic instantly. If anything goes wrong, the previous slot remains active.

## How It Works

```
blue slot  (.env.testnet.blue)   ← currently active
green slot (.env.testnet.green)  ← deploy new version here

After smoke check passes:
.env.testnet.active → .env.testnet.green  (symlink updated)
```

## Usage

### Script

```bash
# Deploy new version to the green slot on testnet
./scripts/blue_green_deploy.sh --network testnet --slot green

# Dry-run to preview steps
./scripts/blue_green_deploy.sh --network testnet --slot green --dry-run
```

The script:
1. Deploys `ip_registry` and `atomic_swap` contracts to the specified slot
2. Writes contract IDs to `.env.{network}.{slot}`
3. Runs a smoke check (calls `list_ip_by_owner` on the new contracts)
4. On success, updates `.env.{network}.active` symlink to the new slot
5. On smoke check failure, exits without touching the active symlink

### GitHub Actions

Trigger the **Blue-Green Deploy** workflow from the Actions tab:
- **network**: `testnet` or `mainnet`
- **slot**: `blue` or `green`

## Rollback

To revert to the previous slot, re-run the workflow with the old slot, or manually update the symlink:

```bash
# Revert to blue
ln -sf .env.testnet.blue .env.testnet.active
source .env.testnet.active
```

## Verifying the Active Slot

```bash
source .env.testnet.active
echo "Active slot: $DEPLOYMENT_SLOT"
echo "IP Registry: $CONTRACT_IP_REGISTRY"
echo "Atomic Swap: $CONTRACT_ATOMIC_SWAP"
```
