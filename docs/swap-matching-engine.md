# Swap Matching Engine

## Overview
`findMatchesForBuyer(buyer, sellers, options?)` scores and ranks sellers against a
buyer's preferences using a weighted multi-factor model.

## Scoring Model (0–100 pts)

| Factor        | Weight | Criteria                                               |
|---------------|--------|--------------------------------------------------------|
| Price overlap | 30     | Buyer maxPrice ≥ seller minPrice; partial for <20% gap |
| Category      | 25     | Exact slug > parent category > no match                |
| Condition     | 20     | Seller condition ≥ buyer minCondition                  |
| Asset type    | 15     | Exact string match on assetType                        |
| Location      | 10     | Same country + haversine ≤ maxDistanceKm               |

## Usage
```js
const { findMatchesForBuyer, batchMatch } = require('./src/matching/swapMatchingEngine');

const matches = findMatchesForBuyer(buyerListing, sellerListings, {
  minScore: 50,   // discard below this score (default 40)
  maxResults: 10, // return top N (default 50)
});

const batch = batchMatch(allBuyers, allSellers);
```
