# API Batch Request Support (#532)

## Overview

The batch API endpoint allows clients to send multiple requests in a single HTTP call, reducing round trips and improving performance for bulk operations.

## Endpoint

```
POST /batch
```

## Request Format

```json
{
  "requests": [
    {
      "id": "req1",
      "method": "GET",
      "path": "/ip/123",
      "body": null,
      "headers": {}
    },
    {
      "id": "req2",
      "method": "POST",
      "path": "/ip/commit",
      "body": {
        "owner": "GABC123",
        "commitment_hash": "abc123def456"
      },
      "headers": {
        "x-idempotency-key": "unique-key-123"
      }
    }
  ]
}
```

## Response Format

```json
{
  "responses": [
    {
      "id": "req1",
      "status": 200,
      "body": {
        "ip_id": 123,
        "owner": "GABC123",
        "timestamp": 1234567890
      },
      "headers": {}
    },
    {
      "id": "req2",
      "status": 200,
      "body": {
        "ip_id": 456,
        "timestamp": 1234567891
      },
      "headers": {}
    }
  ]
}
```

## Constraints

- **Batch Size**: 1-100 requests per batch
- **Request IDs**: Must be unique within a batch
- **Timeout**: Each request has standard timeout (30s)
- **Order**: Responses are returned in request order

## Supported Operations

### IP Operations

```json
{
  "id": "get-ip",
  "method": "GET",
  "path": "/ip/123"
}
```

```json
{
  "id": "commit-ip",
  "method": "POST",
  "path": "/ip/commit",
  "body": {
    "owner": "GABC123",
    "commitment_hash": "hash"
  }
}
```

### Swap Operations

```json
{
  "id": "get-swap",
  "method": "GET",
  "path": "/swap/789"
}
```

```json
{
  "id": "initiate-swap",
  "method": "POST",
  "path": "/swap/initiate",
  "body": {
    "ip_id": 123,
    "buyer": "GXYZ789",
    "price": "1000000"
  }
}
```

```json
{
  "id": "accept-swap",
  "method": "POST",
  "path": "/swap/accept",
  "body": {
    "swap_id": 789,
    "payment": "1000000"
  }
}
```

## Error Handling

### Batch-Level Errors

```json
{
  "error": "Batch size must be between 1 and 100 requests"
}
```

### Request-Level Errors

Individual request errors are returned in the response with appropriate status codes:

```json
{
  "responses": [
    {
      "id": "req1",
      "status": 404,
      "body": {
        "error": "IP not found"
      }
    }
  ]
}
```

## Performance Benefits

- **Reduced Round Trips**: Send 100 requests in 1 HTTP call
- **Lower Latency**: Fewer network round trips
- **Improved Throughput**: Batch processing is more efficient
- **Better Resource Utilization**: Fewer TCP connections

## Example Usage

### JavaScript/TypeScript

```typescript
const batch = {
  requests: [
    {
      id: "get-ip-1",
      method: "GET",
      path: "/ip/123"
    },
    {
      id: "get-ip-2",
      method: "GET",
      path: "/ip/456"
    },
    {
      id: "commit-ip",
      method: "POST",
      path: "/ip/commit",
      body: {
        owner: "GABC123",
        commitment_hash: "hash"
      }
    }
  ]
};

const response = await fetch("http://localhost:8080/batch", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(batch)
});

const results = await response.json();
results.responses.forEach(r => {
  console.log(`${r.id}: ${r.status}`);
});
```

### Python

```python
import requests

batch = {
    "requests": [
        {
            "id": "get-ip-1",
            "method": "GET",
            "path": "/ip/123"
        },
        {
            "id": "commit-ip",
            "method": "POST",
            "path": "/ip/commit",
            "body": {
                "owner": "GABC123",
                "commitment_hash": "hash"
            }
        }
    ]
}

response = requests.post(
    "http://localhost:8080/batch",
    json=batch
)

for resp in response.json()["responses"]:
    print(f"{resp['id']}: {resp['status']}")
```

## Best Practices

1. **Group Related Requests**: Batch requests that are logically related
2. **Use Unique IDs**: Make request IDs meaningful for debugging
3. **Handle Partial Failures**: Check individual response statuses
4. **Respect Rate Limits**: Batch requests still count toward rate limits
5. **Monitor Performance**: Track batch sizes and response times

## Limitations

- Requests are processed sequentially (not in parallel)
- Each request is independent (no cross-request dependencies)
- Batch timeout is sum of individual request timeouts
- Large batches may take longer to process
