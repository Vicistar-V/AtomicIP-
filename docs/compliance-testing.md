# Compliance Testing Framework

Compliance tests verify that the Atomic Patent API meets regulatory and policy requirements: standard error formats, required audit fields, versioning enforcement, and idempotency guarantees.

## What Is Tested

| Area | Requirement |
|---|---|
| Error responses | Must include a non-empty `error` string field |
| Error responses | Must be valid JSON |
| Health endpoint | Must include `status`, `timestamp`, `uptime_seconds`, `version` |
| Health status | Must be one of: `healthy`, `degraded`, `unhealthy` |
| API versioning | Must declare `version` and non-empty `supported_versions` |
| API versioning | Current version must appear in `supported_versions` |
| IP records | Must include `owner`, `commitment_hash`, `timestamp`, `revoked` |
| Swap records | Must include `seller`, `buyer`, `price`, `status` |
| Swap status | Must be one of: `Pending`, `Accepted`, `Completed`, `Cancelled` |
| Idempotency keys | Must be non-empty strings (UUID v4 recommended) |
| Batch responses | Each response must include `id` and `status` |

## How to Run

```bash
# From the project root
cargo test --test compliance_tests

# Or run all tests including compliance
cargo test
```

## Adding New Compliance Checks

Add a new `#[test]` function in `api-server/tests/compliance_tests.rs`. Follow the pattern:

```rust
#[test]
fn test_my_compliance_requirement() {
    let data = json!({ "field": "value" });
    assert!(data["field"].is_string(), "field must be a string per spec");
}
```

Tests should:
- Validate data structure requirements, not implementation details
- Include a descriptive assertion message explaining the compliance rule
- Be self-contained (no live server or network required)
