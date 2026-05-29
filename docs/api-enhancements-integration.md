# API Enhancements Integration Guide

This guide shows how to integrate the four new API enhancement modules into the main application.

## Quick Start

### 1. Update main.rs

Add the middleware layers to your router in the correct order:

```rust
use axum::middleware;
use std::sync::Arc;

// In your main() function or build_app():

let app = Router::new()
    // ... your routes ...
    .with_state((schema, broadcaster.clone(), health_checker.clone()))
    // Add middleware in this order:
    .layer(middleware::from_fn(distributed_tracing::distributed_tracing_middleware))
    .layer(middleware::from_fn(error_recovery::error_recovery_middleware))
    .layer(middleware::from_fn(request_queue::request_queue_middleware))
    .layer(middleware::from_fn(compression::compression_middleware))
    .layer(middleware::from_fn(require_json_content_type));
```

### 2. Initialize Fallback Manager

Add to your application state:

```rust
use std::sync::Arc;
use fallback::{FallbackConfig, FallbackManager};
use std::time::Duration;

// In main():
let fallback_config = FallbackConfig {
    primary_endpoint: std::env::var("PRIMARY_RPC_ENDPOINT")
        .unwrap_or_else(|_| "https://soroban-testnet.stellar.org".to_string()),
    fallback_endpoints: std::env::var("FALLBACK_RPC_ENDPOINTS")
        .unwrap_or_default()
        .split(',')
        .map(|s| s.trim().to_string())
        .collect(),
    health_check_interval: Duration::from_secs(
        std::env::var("HEALTH_CHECK_INTERVAL_SECS")
            .unwrap_or_else(|_| "30".to_string())
            .parse()
            .unwrap_or(30)
    ),
    timeout: Duration::from_secs(
        std::env::var("RPC_TIMEOUT_SECS")
            .unwrap_or_else(|_| "5".to_string())
            .parse()
            .unwrap_or(5)
    ),
};

let fallback_manager = Arc::new(FallbackManager::new(fallback_config));
```

### 3. Initialize Request Queue

Add to your application state:

```rust
use request_queue::{RequestQueue, QueueConfig};

// In main():
let queue_config = QueueConfig {
    max_queue_size: std::env::var("MAX_QUEUE_SIZE")
        .unwrap_or_else(|_| "1000".to_string())
        .parse()
        .unwrap_or(1000),
    max_concurrent_requests: std::env::var("MAX_CONCURRENT_REQUESTS")
        .unwrap_or_else(|_| "100".to_string())
        .parse()
        .unwrap_or(100),
    request_timeout: Duration::from_secs(
        std::env::var("REQUEST_TIMEOUT_SECS")
            .unwrap_or_else(|_| "30".to_string())
            .parse()
            .unwrap_or(30)
    ),
};

let request_queue = Arc::new(RequestQueue::new(queue_config));
```

### 4. Update Application State

Modify your state struct to include the new managers:

```rust
pub struct AppState {
    pub schema: graphql::AtomicIpSchema,
    pub broadcaster: Arc<websocket::EventBroadcaster>,
    pub health_checker: Arc<health::HealthChecker>,
    pub fallback_manager: Arc<FallbackManager>,
    pub request_queue: Arc<RequestQueue>,
}

// In main():
let state = AppState {
    schema,
    broadcaster: Arc::new(websocket::EventBroadcaster::new()),
    health_checker: Arc::new(health::HealthChecker::new()),
    fallback_manager,
    request_queue,
};

let app = Router::new()
    // ... routes ...
    .with_state(state)
    // ... middleware ...
```

## Environment Variables

Add these to your `.env` file:

```env
# Fallback Endpoints
PRIMARY_RPC_ENDPOINT=https://soroban-testnet.stellar.org
FALLBACK_RPC_ENDPOINTS=https://soroban-testnet-backup1.stellar.org,https://soroban-testnet-backup2.stellar.org
HEALTH_CHECK_INTERVAL_SECS=30
RPC_TIMEOUT_SECS=5

# Error Recovery
MAX_RETRIES=3
INITIAL_BACKOFF_MS=100
MAX_BACKOFF_SECS=10
BACKOFF_MULTIPLIER=2.0

# Request Queuing
MAX_QUEUE_SIZE=1000
MAX_CONCURRENT_REQUESTS=100
REQUEST_TIMEOUT_SECS=30

# Logging
RUST_LOG=info,api_server=debug
```

## Using Fallback Manager in Handlers

```rust
use axum::extract::State;

async fn my_handler(
    State(state): State<AppState>,
) -> Result<Json<Response>, StatusCode> {
    // Get active endpoint
    let endpoint = state.fallback_manager.get_active_endpoint();
    
    // Make RPC call
    match make_rpc_call(&endpoint).await {
        Ok(result) => {
            state.fallback_manager.mark_healthy(&endpoint);
            Ok(Json(result))
        }
        Err(e) => {
            state.fallback_manager.mark_failed(&endpoint);
            Err(StatusCode::SERVICE_UNAVAILABLE)
        }
    }
}
```

## Using Request Queue in Handlers

```rust
use axum::extract::State;
use uuid::Uuid;

async fn my_handler(
    State(state): State<AppState>,
) -> Result<Json<Response>, StatusCode> {
    let request_id = Uuid::new_v4().to_string();
    
    // Acquire queue slot
    let _guard = state.request_queue.acquire(request_id).await?;
    
    // Process request (guard ensures cleanup)
    let result = process_request().await?;
    
    Ok(Json(result))
}
```

## Using Trace Context in Handlers

```rust
use axum::extract::Request;
use distributed_tracing::get_trace_context;

async fn my_handler(req: Request) -> Result<Json<Response>, StatusCode> {
    let trace_context = get_trace_context(req.headers());
    
    tracing::info!(
        trace_id = %trace_context.trace_id,
        span_id = %trace_context.span_id,
        "Processing request"
    );
    
    // Your handler logic
    Ok(Json(response))
}
```

## Monitoring Integration

### Prometheus Metrics

Add these metric collectors:

```rust
use metrics::{counter, histogram, gauge};

// In handlers:
counter!("api_requests_total", "endpoint" => endpoint).increment(1);
histogram!("api_request_duration_seconds").record(duration.as_secs_f64());
gauge!("api_queue_size").set(queue_size as f64);
```

### Structured Logging

All modules use structured logging with trace context:

```rust
tracing::info!(
    trace_id = %trace_context.trace_id,
    span_id = %trace_context.span_id,
    endpoint = endpoint,
    "Endpoint health check"
);
```

## Testing Integration

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_fallback_integration() {
        let config = FallbackConfig::default();
        let manager = FallbackManager::new(config);
        
        let endpoint = manager.get_active_endpoint();
        assert!(!endpoint.is_empty());
    }

    #[tokio::test]
    async fn test_queue_integration() {
        let config = QueueConfig::default();
        let queue = RequestQueue::new(config);
        
        let guard = queue.acquire("test-req".to_string()).await;
        assert!(guard.is_ok());
    }
}
```

### Integration Tests

```rust
#[tokio::test]
async fn test_full_request_flow() {
    let app = build_app();
    
    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/ip/commit")
                .header("content-type", "application/json")
                .header("X-Trace-ID", "test-trace-123")
                .body(Body::from(r#"{"owner":"G123","commitment_hash":"abc"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    
    assert_eq!(response.status(), StatusCode::OK);
    assert!(response.headers().contains_key("X-Trace-ID"));
}
```

## Performance Tuning

### Fallback Endpoints
- Increase `HEALTH_CHECK_INTERVAL_SECS` for less frequent checks
- Decrease `RPC_TIMEOUT_SECS` for faster failover
- Add more fallback endpoints for higher availability

### Request Queuing
- Increase `MAX_CONCURRENT_REQUESTS` for higher throughput
- Decrease `REQUEST_TIMEOUT_SECS` for faster timeout
- Monitor `api_queue_size` metric to tune `MAX_QUEUE_SIZE`

### Error Recovery
- Increase `MAX_RETRIES` for more resilience
- Adjust `BACKOFF_MULTIPLIER` for different retry patterns
- Monitor `api_circuit_breaker_state` for circuit breaker health

## Troubleshooting

### Queue Always Full
- Increase `MAX_QUEUE_SIZE`
- Increase `MAX_CONCURRENT_REQUESTS`
- Optimize handler performance

### High Latency
- Check `api_queue_wait_time_seconds` metric
- Verify `MAX_CONCURRENT_REQUESTS` is appropriate
- Check downstream service performance

### Circuit Breaker Stuck Open
- Check logs for error patterns
- Verify downstream service is healthy
- Manually reset if needed

## Deployment Checklist

- [ ] Add all environment variables to deployment config
- [ ] Update Prometheus scrape config for new metrics
- [ ] Configure log aggregation for structured logs
- [ ] Set up alerts for queue depth and circuit breaker state
- [ ] Test failover with fallback endpoints
- [ ] Load test with request queuing enabled
- [ ] Monitor metrics during initial deployment
- [ ] Document runbook for common issues

## References

- [Axum Middleware Documentation](https://docs.rs/axum/latest/axum/middleware/)
- [Tokio Async Runtime](https://tokio.rs/)
- [Tracing Crate](https://docs.rs/tracing/)
- [Metrics Crate](https://docs.rs/metrics/)
