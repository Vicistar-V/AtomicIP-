# API Caching Layer (#530)

## Overview

The API server implements a comprehensive caching layer to reduce RPC calls and improve performance. The cache uses an in-process DashMap with TTL-based expiration, providing graceful fallback when Redis is unavailable.

## Features

### Cache Configuration

The cache supports configurable TTL for different data types:

- **Default TTL**: 30 seconds
- **IP Records TTL**: 60 seconds
- **Swap Records TTL**: 30 seconds
- **Reputation Data TTL**: 300 seconds (5 minutes)

### Cache Operations

#### Basic Operations

```rust
// Set a value with default TTL
cache::set("key", &value);

// Set with custom TTL
cache::set_with_ttl("key", &value, 120);

// Get a cached value
let value: Option<MyType> = cache::get("key");

// Check if key exists
if cache::exists("key") { }

// Get remaining TTL
if let Some(ttl) = cache::ttl_remaining("key") { }
```

#### Invalidation

```rust
// Invalidate a single key
cache::invalidate("key");

// Invalidate all keys with prefix
cache::invalidate_prefix("ip:");

// Invalidate with pattern (supports * wildcards)
cache::invalidate_pattern("swap:*");

// Clear all cache
cache::clear();
```

### Cache Keys

The cache uses structured key naming for easy invalidation:

- IP Records: `ip:{ip_id}`
- IP Lists: `ip:list:{owner}:{limit}:{cursor}`
- Swap Records: `swap:{swap_id}`
- Swap by Seller: `swap:seller:{seller}:{limit}:{cursor}`
- Swap by Buyer: `swap:buyer:{buyer}:{limit}:{cursor}`
- Reputation: `reputation:{address}`
- Dispute Evidence: `evidence:{swap_id}`

### Cache-Control Headers

The API returns appropriate Cache-Control headers for HTTP caching:

```
GET /ip/{id}
Cache-Control: public, max-age=60, stale-while-revalidate=30

GET /swap/{id}
Cache-Control: public, max-age=30, stale-while-revalidate=10

POST /ip/commit
Cache-Control: no-store
```

### Contract Event Integration

The cache automatically invalidates entries when contract events occur:

```rust
cache::invalidate_on_contract_event("swap_completed", swap_id);
```

Supported events:
- `ip_committed` - Invalidates IP record
- `ip_transferred` - Invalidates IP and all IP lists
- `ip_revoked` - Invalidates IP and all IP lists
- `swap_initiated` - Invalidates swap and all swap lists
- `swap_accepted` - Invalidates swap and seller/buyer lists
- `swap_completed` - Invalidates swap, lists, and reputation
- `swap_cancelled` - Invalidates swap and lists
- `dispute_raised` - Invalidates swap and evidence
- `dispute_resolved` - Invalidates swap, evidence, and reputation
- `admin_rollback` - Invalidates all related entries

## Performance Impact

The caching layer provides significant performance improvements:

- **Reduced RPC Calls**: Frequently accessed data is cached locally
- **Lower Latency**: In-process cache has microsecond response times
- **Reduced Network Traffic**: Fewer calls to Soroban RPC
- **Graceful Degradation**: Works without Redis, no external dependencies

## Statistics

Get cache statistics:

```rust
let stats = cache::stats();
println!("Total entries: {}", stats.total_entries);
```

## Testing

The cache module includes comprehensive tests:

```bash
cargo test -p api-server cache::tests
```

## Future Enhancements

- Redis backend support for distributed caching
- Cache warming strategies
- Adaptive TTL based on access patterns
- Cache hit/miss metrics
