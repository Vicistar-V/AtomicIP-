# Swap Royalty Tracking

## Overview
`calculateRoyalty(config, salePrice)` computes royalty distributions for IP resale swaps.
`recordRoyaltyEvent` and `processPayouts` manage a lightweight in-memory ledger.

## Royalty Config

```js
{
  assetId: "patent-42",
  rateBps: 1000,            // 10% (max 3000 = 30%)
  beneficiaries: [
    { id: "creator-1", shareBps: 7000 },  // 70% of royalty
    { id: "agent-1",   shareBps: 3000 },  // 30% of royalty
    // shareBps must sum to 10000
  ]
}
```

## Ledger Operations

| Function                | Description                                    |
|-------------------------|------------------------------------------------|
| `recordRoyaltyEvent`    | Appends PENDING entries for each beneficiary   |
| `processPayouts`        | Marks PENDING → PAID, respects maxAmount cap   |
| `getPendingRoyalties`   | Sums unpaid amounts for a beneficiary          |
| `processBatchRoyalties` | Processes many transactions, collects errors   |

## Usage
```js
const {
  calculateRoyalty,
  recordRoyaltyEvent,
  processPayouts,
  getPendingRoyalties,
} = require('./src/royalty/swapRoyaltyTracker');

const ledger = [];

const calc    = calculateRoyalty(config, 10_000);
// => { totalRoyalty: 1000, sellerProceeds: 9000, payouts: [...] }

recordRoyaltyEvent(ledger, 'swap-99', calc);
processPayouts(ledger, 'creator-1');
const { total } = getPendingRoyalties(ledger, 'agent-1');
```
