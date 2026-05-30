# Accessibility Testing

Accessibility testing verifies that the Atomic Patent API is usable by different types of clients — clients with different Accept headers, API version preferences, authentication states, and payload shapes.

## What Is Tested

| Area | Requirement |
|---|---|
| Accept headers | `application/json` and `*/*` must be accepted |
| Response Content-Type | Must always be `application/json` |
| API versioning | v1.x must be supported; unsupported versions return 406 |
| Missing version header | Defaults to current version (no error) |
| Public endpoints | `/health`, `/docs`, `/openapi.json`, `/version` require no auth |
| Minimal payloads | Required-only requests must be valid (no hidden required fields) |
| Optional fields | `referrer`, `idempotency_key`, etc. must truly be optional |
| Error responses | Must be valid JSON, never HTML |
| Pagination | List endpoints work without pagination params (use defaults) |
| Paginated responses | Must include `has_more` field |

## How to Run

```bash
# From the project root
cargo test --test accessibility_tests

# Or run all tests
cargo test
```

## Adding New Client Types

Add a `#[test]` function in `api-server/tests/accessibility_tests.rs`:

```rust
#[test]
fn test_my_client_scenario() {
    // Describe the client's request shape or header
    // Assert the API handles it correctly
}
```

Tests should cover:
- New Accept header variants your clients might send
- New optional fields added to request schemas
- New public endpoints that should not require auth
- New error scenarios that must return JSON (not HTML or plain text)
