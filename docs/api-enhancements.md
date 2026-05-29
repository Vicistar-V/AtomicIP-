# API Enhancements Documentation

This document describes the four major API enhancements implemented in issues #533-#536.

## Overview

The Atomic Patent API has been enhanced with four critical features to improve reliability, security, and backward compatibility:

1. **API Compression Support** (#533) - Reduce bandwidth usage
2. **API Versioning Strategy** (#534) - Support multiple API versions
3. **Request Signing Verification** (#535) - Secure request authentication
4. **Circuit Breaker** (#536) - Handle RPC failures gracefully

## 1. API Compression Support (#533)

### Purpose
Compress API responses using gzip and brotli to reduce bandwidth usage and improve performance.

### Implementation

#### Compression Middleware
The compression middleware automatically detects the `Accept-Encoding` header and applies the appropriate compression:

```rust
pub async fn compression_middleware(
    headers: HeaderMap,
    req: Request,
    next: Next,
) -> Response
```

#### Supported Encodings
- **gzip** - Standard compression, widely supported
- **brotli** - Modern compression with better compression ratios
- **deflate** - Legacy compression support

#### Configuration
```rust
pub struct CompressionConfig {
    pub gzip_enabled: bool,
    pub brotli_enabled: bool,
    pub min_size_bytes: usize,  // Default: 1024
}
```

#### Usage Example
```bash
# Request with gzip compression
curl -H "Accept-Encoding: gzip" http://localhost:8080/v1/ip/1

# Response headers
Content-Encoding: gzip
Vary: Accept-Encoding
```

#### Dependencies
- `flate2` - For gzip compression
- `brotli` - For brotli compression

### Testing
```bash
cargo test compression
```

---

## 2. API Versioning Strategy (#534)

### Purpose
Support multiple API versions for backward compatibility while allowing the API to evolve.

### Implementation

#### Supported Versions
- `1.0.0` - Initial release
- `1.1.0` - Future enhancements

#### Version Negotiation Middleware
```rust
pub async fn version_negotiation(
    headers: HeaderMap,
    mut req: Request,
    next: Next,
) -> Result<Response, StatusCode>
```

#### Version Header
Clients specify the desired API version using the `Accept-Version` header:

```bash
curl -H "Accept-Version: 1.0.0" http://localhost:8080/v1/ip/commit
```

#### Response Headers
```
API-Version: 1.0.0
Deprecation: false
```

For deprecated versions:
```
API-Version: 1.0.0
Deprecation: true
Sunset: Sun, 31 Dec 2027 23:59:59 GMT
```

#### Version Information Endpoint
```bash
GET /version
```

Response:
```json
{
  "version": "1.0.0",
  "status": "stable",
  "supported_versions": ["1.0.0", "1.1.0"],
  "deprecation_date": null,
  "features": [
    "api-versioning",
    "compression",
    "request-signing",
    "circuit-breaker"
  ]
}
```

#### Behavior
- If no `Accept-Version` header is provided, the current version (1.0.0) is used
- If an unsupported version is requested, the API returns `406 Not Acceptable`
- Version information is stored in request extensions for handler access

### Testing
```bash
cargo test versioning
```

---

## 3. Request Signing Verification (#535)

### Purpose
Verify that API requests are signed by valid Stellar keypairs to prevent unauthorized access.

### Implementation

#### Stellar Keypair Validation
Validates that public keys follow Stellar format:
- Start with 'G'
- Exactly 56 characters
- Alphanumeric characters only

```rust
pub fn is_valid_stellar_public_key(key: &str) -> bool {
    key.starts_with('G') && key.len() == 56 && key.chars().all(|c| c.is_alphanumeric())
}
```

#### Signature Generation
Signatures are computed as SHA256 hash of concatenated request components:

```
signature = SHA256(method || path || timestamp || body_hash)
```

#### Request Headers Required
```
X-Signature: <signature>
X-Timestamp: <unix_timestamp>
X-Public-Key: <stellar_public_key>
```

#### Verification Process
1. Extract signature, timestamp, and public key from headers
2. Validate Stellar public key format
3. Check timestamp is within 5 minutes (replay attack prevention)
4. Hash request body using SHA256
5. Recompute signature and compare

#### Example Request
```bash
curl -X POST http://localhost:8080/v1/ip/commit \
  -H "Content-Type: application/json" \
  -H "X-Signature: abc123def456..." \
  -H "X-Timestamp: 1234567890" \
  -H "X-Public-Key: GBRPYHIL2CI3WHZDTOOQFC6EB4KJJGUJJBBQ5ECVVF7C3XVQCRWGSGA" \
  -d '{"owner":"G123","commitment_hash":"abc"}'
```

#### Security Features
- **Replay Attack Prevention**: 5-minute timestamp window
- **Body Integrity**: SHA256 hash of request body
- **Method Verification**: HTTP method included in signature
- **Path Verification**: Request path included in signature

### Testing
```bash
cargo test request_signing
```

---

## 4. Circuit Breaker (#536)

### Purpose
Implement the circuit breaker pattern to handle RPC failures gracefully and prevent cascading failures.

### Implementation

#### Circuit Breaker States

**Closed** (Normal Operation)
- Requests pass through normally
- Failures are counted
- When failure count reaches threshold, transitions to Open

**Open** (Failure Mode)
- Requests are rejected immediately
- No calls to the failing service
- After timeout period, transitions to HalfOpen

**HalfOpen** (Recovery Testing)
- Limited number of requests allowed (default: 3)
- If requests succeed, transitions to Closed
- If requests fail, transitions back to Open

#### Configuration
```rust
pub struct CircuitBreakerConfig {
    pub failure_threshold: usize,      // Default: 5
    pub success_threshold: usize,      // Default: 2
    pub timeout_secs: u64,             // Default: 60
    pub half_open_max_calls: usize,    // Default: 3
}
```

#### API
```rust
pub fn can_execute(&self) -> bool
pub fn record_success(&self)
pub fn record_failure(&self)
pub fn get_state(&self) -> CircuitState
pub fn reset(&self)
```

#### State Transitions
```
Closed --[failures >= threshold]--> Open
Open --[timeout elapsed]--> HalfOpen
HalfOpen --[successes >= threshold]--> Closed
HalfOpen --[failure]--> Open
```

#### Usage Example
```rust
let cb = CircuitBreaker::new(CircuitBreakerConfig::default());

if cb.can_execute() {
    match rpc_call() {
        Ok(result) => {
            cb.record_success();
            // Process result
        }
        Err(e) => {
            cb.record_failure();
            // Handle error
        }
    }
} else {
    // Circuit is open, return cached response or error
    return Err("Service temporarily unavailable");
}
```

#### Atomic Operations
- Uses `AtomicUsize` and `AtomicU64` for thread-safe counters
- No locks required for state transitions
- Safe for concurrent access

### Testing
```bash
cargo test circuit_breaker
```

---

## Integration

All features are integrated into the main application via middleware layers:

```rust
fn build_app() -> Router {
    Router::new()
        // ... routes ...
        .layer(middleware::from_fn(tracing_middleware::trace_requests))
        .layer(middleware::from_fn(versioning::version_negotiation))
        .layer(middleware::from_fn(compression::compression_middleware))
        .layer(middleware::from_fn(require_json_content_type))
}
```

### Middleware Order
1. **Tracing** - Log all requests
2. **Version Negotiation** - Handle API versioning
3. **Compression** - Apply response compression
4. **Content-Type Validation** - Ensure JSON for POST/PUT/PATCH

---

## Testing

Run all tests:
```bash
cargo test
```

Run specific feature tests:
```bash
cargo test compression
cargo test versioning
cargo test request_signing
cargo test circuit_breaker
```

---

## Performance Considerations

### Compression
- Gzip: Good compression ratio, widely supported
- Brotli: Better compression ratio, slightly slower
- Minimum size threshold prevents compression overhead for small responses

### Versioning
- Minimal overhead (header parsing)
- Version info stored in request extensions
- No database lookups required

### Request Signing
- SHA256 hashing for all requests
- Stellar keypair validation
- Timestamp validation (5-minute window)

### Circuit Breaker
- Atomic operations for lock-free concurrency
- Minimal memory overhead
- Configurable thresholds for different use cases

---

## Migration Guide

### For API Clients

#### 1. Add Compression Support
```bash
# Before
curl http://localhost:8080/v1/ip/1

# After (with compression)
curl -H "Accept-Encoding: gzip" http://localhost:8080/v1/ip/1
```

#### 2. Specify API Version
```bash
# Before (uses default version)
curl http://localhost:8080/v1/ip/1

# After (explicit version)
curl -H "Accept-Version: 1.0.0" http://localhost:8080/v1/ip/1
```

#### 3. Sign Requests
```bash
# Generate signature
timestamp=$(date +%s)
body='{"owner":"G123","commitment_hash":"abc"}'
body_hash=$(echo -n "$body" | sha256sum | cut -d' ' -f1)
signature=$(echo -n "POST||/v1/ip/commit||$timestamp||$body_hash" | sha256sum | cut -d' ' -f1)

# Send signed request
curl -X POST http://localhost:8080/v1/ip/commit \
  -H "Content-Type: application/json" \
  -H "X-Signature: $signature" \
  -H "X-Timestamp: $timestamp" \
  -H "X-Public-Key: GBRPYHIL2CI3WHZDTOOQFC6EB4KJJGUJJBBQ5ECVVF7C3XVQCRWGSGA" \
  -d "$body"
```

---

## Troubleshooting

### Compression Issues
- Ensure `Accept-Encoding` header is set correctly
- Check `Content-Encoding` in response headers
- Verify minimum size threshold is not preventing compression

### Versioning Issues
- Use `Accept-Version` header for explicit version selection
- Check `/version` endpoint for supported versions
- Look for `Deprecation` header for version warnings

### Signing Issues
- Validate Stellar public key format (G-prefix, 56 chars)
- Ensure timestamp is within 5 minutes
- Verify body hash matches request body
- Check signature computation order: method || path || timestamp || body_hash

### Circuit Breaker Issues
- Monitor circuit breaker state via metrics
- Adjust failure/success thresholds for your use case
- Use reset() for manual recovery
- Check timeout configuration

---

## Future Enhancements

- [ ] Rate limiting per API version
- [ ] Compression level configuration
- [ ] Circuit breaker metrics export
- [ ] Request signing with Ed25519 keys
- [ ] API versioning with feature flags
- [ ] Automatic compression based on response size
