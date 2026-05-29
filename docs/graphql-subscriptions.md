# GraphQL Subscription Support (#529)

## Overview

The API now supports real-time GraphQL subscriptions for swap events, allowing clients to receive live updates without polling.

## Subscription Types

### 1. Swap Status Changed

Subscribe to status changes for a specific swap:

```graphql
subscription OnSwapStatusChanged($swapId: UInt64!) {
  swapStatusChanged(swapId: $swapId) {
    swapId
    oldStatus
    newStatus
    timestamp
  }
}
```

**Variables:**
```json
{
  "swapId": 123
}
```

**Response:**
```json
{
  "data": {
    "swapStatusChanged": {
      "swapId": 123,
      "oldStatus": "PENDING",
      "newStatus": "ACCEPTED",
      "timestamp": 1234567890
    }
  }
}
```

### 2. IP Committed

Subscribe to all IP commitment events:

```graphql
subscription OnIpCommitted {
  ipCommitted {
    ipId
    owner
    timestamp
  }
}
```

**Response:**
```json
{
  "data": {
    "ipCommitted": {
      "ipId": 456,
      "owner": "GABC123",
      "timestamp": 1234567891
    }
  }
}
```

### 3. Swap Initiated

Subscribe to all swap initiation events:

```graphql
subscription OnSwapInitiated {
  swapInitiated {
    swapId
    ipId
    seller
    buyer
    price
    timestamp
  }
}
```

**Response:**
```json
{
  "data": {
    "swapInitiated": {
      "swapId": 789,
      "ipId": 456,
      "seller": "GABC123",
      "buyer": "GXYZ789",
      "price": "1000000",
      "timestamp": 1234567892
    }
  }
}
```

### 4. Seller Swap Events

Subscribe to swap events for a specific seller:

```graphql
subscription OnSellerSwapEvents($seller: String!) {
  sellerSwapEvents(seller: $seller) {
    swapId
    oldStatus
    newStatus
    timestamp
  }
}
```

**Variables:**
```json
{
  "seller": "GABC123"
}
```

## Connection Methods

### WebSocket (Recommended)

```bash
ws://localhost:8080/graphql
```

### HTTP (Long Polling)

```bash
POST http://localhost:8080/graphql
```

## Client Examples

### JavaScript/TypeScript with Apollo Client

```typescript
import { ApolloClient, InMemoryCache, gql, useSubscription } from '@apollo/client';
import { WebSocketLink } from '@apollo/client/link/ws';

const wsLink = new WebSocketLink({
  uri: 'ws://localhost:8080/graphql',
  options: {
    reconnect: true,
  },
});

const client = new ApolloClient({
  link: wsLink,
  cache: new InMemoryCache(),
});

const SWAP_STATUS_SUBSCRIPTION = gql`
  subscription OnSwapStatusChanged($swapId: UInt64!) {
    swapStatusChanged(swapId: $swapId) {
      swapId
      oldStatus
      newStatus
      timestamp
    }
  }
`;

function SwapStatusMonitor({ swapId }) {
  const { data, loading, error } = useSubscription(SWAP_STATUS_SUBSCRIPTION, {
    variables: { swapId },
  });

  if (loading) return <p>Listening for updates...</p>;
  if (error) return <p>Error: {error.message}</p>;

  return (
    <div>
      <p>Swap {data.swapStatusChanged.swapId}</p>
      <p>Status: {data.swapStatusChanged.newStatus}</p>
      <p>Time: {new Date(data.swapStatusChanged.timestamp * 1000).toISOString()}</p>
    </div>
  );
}
```

### Python with gql

```python
from gql import Client, gql
from gql.transport.websockets import WebsocketsTransport
import asyncio

async def subscribe_to_swap_status():
    transport = WebsocketsTransport(url="ws://localhost:8080/graphql")
    
    async with Client(transport=transport) as session:
        subscription = gql("""
            subscription OnSwapStatusChanged($swapId: UInt64!) {
                swapStatusChanged(swapId: $swapId) {
                    swapId
                    oldStatus
                    newStatus
                    timestamp
                }
            }
        """)
        
        async for result in session.subscribe(
            subscription,
            variable_values={"swapId": 123}
        ):
            print(f"Swap {result['swapStatusChanged']['swapId']}")
            print(f"Status: {result['swapStatusChanged']['newStatus']}")

asyncio.run(subscribe_to_swap_status())
```

### Rust with async-graphql-client

```rust
use async_graphql_client::Client;

#[tokio::main]
async fn main() {
    let client = Client::new("ws://localhost:8080/graphql");
    
    let subscription = r#"
        subscription OnSwapStatusChanged($swapId: UInt64!) {
            swapStatusChanged(swapId: $swapId) {
                swapId
                oldStatus
                newStatus
                timestamp
            }
        }
    "#;
    
    let mut stream = client.subscribe(
        subscription,
        Some(serde_json::json!({"swapId": 123}))
    ).await.unwrap();
    
    while let Some(result) = stream.next().await {
        match result {
            Ok(data) => println!("Update: {:?}", data),
            Err(e) => eprintln!("Error: {}", e),
        }
    }
}
```

## Event Flow

### Swap Status Change Flow

```
1. Seller initiates swap
   → SwapInitiated event published
   → Subscribers receive event

2. Buyer accepts swap
   → SwapStatusChanged event (PENDING → ACCEPTED)
   → Subscribers receive event

3. Seller reveals key
   → SwapStatusChanged event (ACCEPTED → COMPLETED)
   → Subscribers receive event
```

### IP Commitment Flow

```
1. User commits IP
   → IpCommitted event published
   → Subscribers receive event
```

## Subscription Lifecycle

### Connection

```
Client connects to ws://localhost:8080/graphql
↓
Server accepts WebSocket connection
↓
Client sends subscription query
↓
Server validates and starts streaming
```

### Streaming

```
Server monitors for events
↓
Event occurs (e.g., swap status change)
↓
Server publishes event to all subscribers
↓
Client receives event in real-time
```

### Disconnection

```
Client closes connection
↓
Server stops streaming
↓
Resources cleaned up
```

## Error Handling

### Connection Errors

```json
{
  "errors": [
    {
      "message": "Connection failed",
      "extensions": {
        "code": "CONNECTION_ERROR"
      }
    }
  ]
}
```

### Subscription Errors

```json
{
  "errors": [
    {
      "message": "Invalid subscription",
      "extensions": {
        "code": "GRAPHQL_PARSE_FAILED"
      }
    }
  ]
}
```

## Performance Considerations

- **Connection Pooling**: Reuse WebSocket connections
- **Selective Subscriptions**: Only subscribe to needed events
- **Backpressure Handling**: Handle slow consumers gracefully
- **Memory Usage**: Each subscription uses minimal memory

## Best Practices

1. **Use WebSocket**: More efficient than HTTP polling
2. **Reconnection Logic**: Implement exponential backoff
3. **Error Handling**: Handle connection and subscription errors
4. **Resource Cleanup**: Unsubscribe when no longer needed
5. **Monitoring**: Track subscription count and latency

## Limitations

- Subscriptions are per-server (not distributed)
- Events are not persisted (only live subscribers receive them)
- Maximum concurrent subscriptions per connection: 1000
- Subscription timeout: 30 minutes of inactivity

## Future Enhancements

- Event persistence and replay
- Subscription filtering and aggregation
- Distributed event broadcasting
- Subscription metrics and monitoring
- Rate limiting per subscription
