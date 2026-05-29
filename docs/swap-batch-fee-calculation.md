# Swap Batch Fee Calculation

## Overview
`calculateBatchFees(swaps, options?)` computes fees for a batch of atomic swaps
with volume-tiered rates, a per-swap base fee, an optional batch discount, and a
protocol/LP fee split.

## Fee Structure

| Component            | Value          |
|----------------------|----------------|
| Base fee per swap    | 0.001 tokens   |
| Default rate         | 30 bps (0.30%) |
| Mid-volume (≥10k)    | 25 bps         |
| High-volume (≥100k)  | 20 bps         |
| Institutional (≥1M)  | 15 bps         |
| Batch discount       | 5 bps off total|
| Protocol split       | 20% of net fee |
| LP split             | 80% of net fee |

## Usage
```js
const { calculateBatchFees } = require('./src/batch/batchFeeCalculator');

const result = calculateBatchFees([
  { id: 'swap-1', amount: 10, value: 5000 },
  { id: 'swap-2', amount: 3,  value: 1500 },
]);

console.log(result.totalNetFee);   // total fee charged
console.log(result.totalProtocolFee); // platform revenue
```

## Options
| Option               | Type    | Default | Description                          |
|----------------------|---------|---------|--------------------------------------|
| `overrideFeeBps`     | number  | —       | Override tier lookup with fixed rate |
| `applyBatchDiscount` | boolean | true    | Apply 5bps batch discount            |

## Constraints
- Batch size: 1–100 swaps
- All `amount` and `value` fields must be positive numbers
