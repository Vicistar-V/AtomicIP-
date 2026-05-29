# API Request Deduplication (#531)

## Overview

The API implements request deduplication to prevent duplicate processing of identical concurrent requests. This is achieved through idempotency keys and concurrent request deduplication.

## Idempotency Keys

### Purpose

Idempotency keys ensure that if a request is sent multiple times (due to network issues, retries, etc.), it will only be processed once.

### Usage

Include the `x-idempotency-key` header in POST, PUT, or PATCH requests:

```bash
curl -X POST http://localhost:8080/ip/commit \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: unique-key-12345" \
  -d '{
    "owner": "GABC123",
    "commitment_hash": "abc123def456"
  }'
```

### Key Requirements

- **Uniqueness**: Each key must be unique per operation
- **Format**: Any string (UUID recommended)
- **Persistence**: Store the key with the request for retries
- **TTL**: Keys are cached for 1 hour

### Response Headers

When a request is replayed from cache:

```
x-idempotency-replayed: true
```

This header indicates the response came from cache, not from processing the request again.

## Concurrent Request Deduplication

### Purpose

Prevents duplicate concurrent requests from hitting the backend multiple times. If two identical requests arrive simultaneously, only one is processed and both receive the same result.

### How It Works

1. First request acquires a lock and proceeds to processing
2. Concurrent identical requests wait for the first to complete
3. All requests receive the same result
4. Lock is released after processing

### Implementation

The `ConcurrentDeduplicator` manages this:

```rust
let dedup = ConcurrentDeduplicator::new();

// First request
if dedup.acquire_or_wait("request-key").await {
    // Process request
    dedup.release("request-key");
} else {
    // Wait for first request to complete
    // Result is already cached
}
```

## Request Deduplication Scenarios

### Scenario 1: Network Retry

```
Client sends request with x-idempotency-key: "key-1"
  ↓
Server processes and caches result
  ↓
Network timeout, client retries with same key
  ↓
Server returns cached result (x-idempotency-replayed: true)
```

### Scenario 2: Concurrent Identical Requests

```
Request 1 arrives with x-idempotency-key: "key-2"
  ↓ (acquires lock)
Request 2 arrives with same key
  ↓ (waits for Request 1)
Request 1 completes, result cached
  ↓
Request 2 receives cached result
```

### Scenario 3: Different Keys

```
Request 1 with x-idempotency-key: "key-3"
Request 2 with x-idempotency-key: "key-4"
  ↓
Both processed independently (different keys)
```

## API Examples

### JavaScript/TypeScript

```typescript
import { v4 as uuidv4 } from 'uuid';

const idempotencyKey = uuidv4();

const response = await fetch('http://localhost:8080/ip/commit', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'x-idempotency-key': idempotencyKey
  },
  body: JSON.stringify({
    owner: 'GABC123',
    commitment_hash: 'abc123def456'
  })
});

const data = await response.json();
const isReplayed = response.headers.get('x-idempotency-replayed') === 'true';

if (isReplayed) {
  console.log('Response from cache');
} else {
  console.log('Fresh response');
}
```

### Python

```python
import requests
import uuid

idempotency_key = str(uuid.uuid4())

response = requests.post(
    'http://localhost:8080/ip/commit',
    headers={
        'x-idempotency-key': idempotency_key
    },
    json={
        'owner': 'GABC123',
        'commitment_hash': 'abc123def456'
    }
)

is_replayed = response.headers.get('x-idempotency-replayed') == 'true'
print(f"Replayed: {is_replayed}")
```

### cURL

```bash
# First request
curl -X POST http://localhost:8080/ip/commit \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: my-unique-key-123" \
  -d '{
    "owner": "GABC123",
    "commitment_hash": "abc123def456"
  }' \
  -i

# Retry with same key (will return cached result)
curl -X POST http://localhost:8080/ip/commit \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: my-unique-key-123" \
  -d '{
    "owner": "GABC123",
    "commitment_hash": "abc123def456"
  }' \
  -i
```

## Cache Duration

- **Idempotency Key TTL**: 1 hour (3600 seconds)
- **Concurrent Lock Timeout**: Request processing time + 5 seconds
- **Automatic Cleanup**: Expired entries are removed on access

## Error Handling

### Missing Idempotency Key

```
POST /ip/commit
(no x-idempotency-key header)

Response: 400 Bad Request
{
  "error": "x-idempotency-key header is required"
}
```

### Duplicate Request IDs in Batch

```
POST /batch
{
  "requests": [
    {"id": "req1", ...},
    {"id": "req1", ...}  // Duplicate ID
  ]
}

Response: 400 Bad Request
{
  "error": "Duplicate request ID: req1"
}
```

## Best Practices

1. **Always Use Idempotency Keys**: For all write operations
2. **Generate Unique Keys**: Use UUID v4 or similar
3. **Store Keys**: Keep keys with request records for auditing
4. **Retry Logic**: Implement exponential backoff with same key
5. **Monitor Replays**: Track x-idempotency-replayed header
6. **Timeout Handling**: Retry after timeout with same key

## Performance Impact

- **Reduced Backend Load**: Duplicate requests don't hit backend
- **Faster Responses**: Cached responses are instant
- **Lower Latency**: No processing overhead for replayed requests
- **Improved Reliability**: Automatic retry handling

## Limitations

- Idempotency keys are per-server (not distributed)
- Keys expire after 1 hour
- Only applies to write operations (POST, PUT, PATCH)
- GET requests are not deduplicated (use HTTP caching instead)

## Future Enhancements

- Distributed idempotency key store (Redis)
- Configurable TTL per operation
- Metrics for deduplication effectiveness
- Audit logging for replayed requests
