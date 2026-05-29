# Swap Batch Expiry Extension

## Overview
`extendBatchExpiry(swaps, extensions, options?)` extends the expiry timestamp for
multiple swaps in a single operation. Non-extendable swaps are captured as errors
without aborting the batch.

## Extendable States
Only `PENDING` and `ACTIVE` swaps can be extended. All other states (EXPIRED,
COMPLETED, CANCELLED) are recorded as errors.

## Extension Rules
| Rule                    | Value                    |
|-------------------------|--------------------------|
| Minimum extension       | 1 minute (60,000 ms)     |
| Maximum extension       | 30 days (2,592,000,000 ms) |
| Max batch size          | 100 swaps                |

## Usage
```js
const { extendBatchExpiry } = require('./src/batch/batchExpiryExtender');

const ONE_DAY = 24 * 60 * 60 * 1000;

// Same extension for all swaps
const result = extendBatchExpiry(swaps, ONE_DAY);

// Per-swap extensions
const result = extendBatchExpiry(swaps, [ONE_DAY, 2 * ONE_DAY, ONE_DAY]);

console.log(result.extendedCount);     // number successfully extended
console.log(result.failedCount);       // number that failed (non-extendable state etc.)
console.log(result.totalExtensionMs);  // total ms added across all swaps
```
