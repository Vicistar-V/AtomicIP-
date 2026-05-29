# Swap Batch Dispute Resolution

## Overview
`resolveBatchDisputes(disputes, resolutions)` resolves disputes for multiple swaps
in a single pass, returning per-swap outcomes and batch-level totals.

## Dispute States
| State     | Description                          |
|-----------|--------------------------------------|
| OPEN      | Dispute is active and resolvable     |
| RESOLVED  | Dispute resolved (refund/release/split)|
| ESCALATED | Handed off to human arbitration      |

## Resolution Types
| Type     | Outcome                                      |
|----------|----------------------------------------------|
| REFUND   | Full amount returned to initiator            |
| RELEASE  | Full amount released to counterparty         |
| SPLIT    | Amount split by `splitRatio` (default 50/50) |
| ESCALATE | Marked for human arbitration, funds frozen   |

## Usage
```js
const { resolveBatchDisputes, DISPUTE_STATES, RESOLUTION_TYPES } =
  require('./src/batch/batchDisputeResolver');

const result = resolveBatchDisputes(
  [
    { swapId: 'swap-1', state: 'OPEN', amount: 500 },
    { swapId: 'swap-2', state: 'OPEN', amount: 300 },
  ],
  [
    { type: 'REFUND' },
    { type: 'SPLIT', splitRatio: 0.6, reason: 'Partial delivery' },
  ]
);

console.log(result.resolvedCount); // 2
console.log(result.totalRefunded); // 500
```

## Constraints
- Batch size: 1–50 disputes
- Only OPEN disputes can be resolved; others are recorded as errors (non-throwing)
- `splitRatio` must be between 0.01 and 0.99
