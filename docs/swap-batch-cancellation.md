# Swap Batch Cancellation

## Overview
`cancelBatchSwaps(swaps, cancellations?, options?)` cancels multiple swaps in a
single call. Non-cancellable swaps are captured as errors without aborting the batch.

## Cancellable States
Only `PENDING` and `ACTIVE` swaps can be cancelled. All other states result in a
per-item error.

## Refund Policies
| Policy   | Refund Amount                        |
|----------|--------------------------------------|
| FULL     | Full `amount` returned to initiator  |
| PARTIAL  | `amount - feePaid`                   |
| NONE     | 0 (penalty cancellation)             |

Default policy when `cancellations` is `null`: **FULL**.

## Usage
```js
const { cancelBatchSwaps, REFUND_POLICIES } = require('./src/batch/batchCanceller');

// Cancel all with default (FULL) refund policy
const result = cancelBatchSwaps(swaps);

// Cancel with per-swap policies
const result = cancelBatchSwaps(swaps, [
  { reason: 'User requested',  refundPolicy: REFUND_POLICIES.FULL },
  { reason: 'Penalty cancel',  refundPolicy: REFUND_POLICIES.NONE },
  { reason: 'Partial settle',  refundPolicy: REFUND_POLICIES.PARTIAL, feePaid: 25 },
]);

console.log(result.cancelledCount); // successfully cancelled
console.log(result.totalRefunded);  // total refund amount
console.log(result.errors);         // per-item failures
```

## Constraints
- Batch size: 1–100 swaps
- Reason max length: 256 characters
