# Pedersen Commitment Scheme

## Overview

AtomicIP uses a Pedersen commitment scheme to allow inventors to prove they held an idea at a specific time without revealing the idea itself. This document explains how to construct valid commitment hashes and secrets.

## How It Works

The commitment scheme uses SHA-256 hashing with a blinding factor to create a cryptographic commitment:

```
commitment_hash = sha256(secret || blinding_factor)
```

Where:
- `secret` - A 32-byte value representing your IP (e.g., a hash of your design document)
- `blinding_factor` - A 32-byte random value that hides the secret
- `||` - Concatenation operator
- `sha256` - The SHA-256 cryptographic hash function

## Secret Format

### What Constitutes a Valid Secret

A valid secret must be:

1. **Exactly 32 bytes** - The secret must be a `BytesN<32>` type
2. **Cryptographically random** - Use a secure random number generator
3. **Kept secret** - Only you should know the secret until you choose to reveal it
4. **Unique per commitment** - Each IP should have a different secret

### Recommended Secret Construction

For maximum security, construct your secret from your actual IP:

```rust
// Example: Creating a secret from a design document
use soroban_sdk::{BytesN, Env};

fn create_secret(env: &Env, design_document: &[u8]) -> BytesN<32> {
    // Hash the design document to create a 32-byte secret
    let secret: BytesN<32> = env.crypto().sha256(design_document).into();
    secret
}
```

### Alternative Secret Sources

You can use any 32-byte value as a secret:

- Hash of a PDF document
- Hash of source code
- Hash of a design schematic
- Randomly generated value (if you can remember it)

## Blinding Factor

The blinding factor is a random value that prevents attackers from guessing your secret through brute force.

### Generating a Secure Blinding Factor

```rust
use soroban_sdk::{BytesN, Env};

fn generate_blinding_factor(env: &Env) -> BytesN<32> {
    // Generate 32 random bytes
    let mut random_bytes = [0u8; 32];
    env.crypto().random_bytes(&mut random_bytes);
    BytesN::from_array(env, &random_bytes)
}
```

### Important Properties

- **Must be random** - Use cryptographically secure random generation
- **Must be kept secret** - Like the secret, the blinding factor must remain private
- **Must be unique** - Use a different blinding factor for each commitment

## Creating a Commitment Hash

### Complete Example

Here's a complete example showing how to create a commitment hash:

```rust
use soroban_sdk::{BytesN, Env};

/// Creates a Pedersen commitment hash from a secret and blinding factor.
///
/// # Arguments
///
/// * `env` - The Soroban environment
/// * `secret` - The 32-byte secret representing your IP
/// * `blinding_factor` - The 32-byte random blinding factor
///
/// # Returns
///
/// The 32-byte commitment hash to register on-chain
///
/// # Example
///
/// ```ignore
/// let env = Env::default();
/// let secret = create_secret(&env, b"My invention design");
/// let blinding_factor = generate_blinding_factor(&env);
/// let commitment_hash = create_commitment_hash(&env, &secret, &blinding_factor);
/// ```
fn create_commitment_hash(
    env: &Env,
    secret: &BytesN<32>,
    blinding_factor: &BytesN<32>,
) -> BytesN<32> {
    // Concatenate secret || blinding_factor
    let mut preimage = soroban_sdk::Bytes::new(env);
    preimage.append(&secret.clone().into());
    preimage.append(&blinding_factor.clone().into());
    
    // Hash the preimage
    let commitment_hash: BytesN<32> = env.crypto().sha256(&preimage).into();
    
    commitment_hash
}
```

### Step-by-Step Process

1. **Prepare your secret** - Hash your IP document or generate a random 32-byte value
2. **Generate blinding factor** - Create a random 32-byte value
3. **Concatenate** - Combine secret and blinding factor: `secret || blinding_factor`
4. **Hash** - Compute SHA-256 of the concatenated value
5. **Register** - Submit the commitment hash to the IP registry contract

## Verifying a Commitment

To verify a commitment, you need the original secret and blinding factor:

```rust
use soroban_sdk::BytesN;

/// Verifies that a secret and blinding factor match a commitment hash.
///
/// # Arguments
///
/// * `env` - The Soroban environment
/// * `commitment_hash` - The stored commitment hash to verify against
/// * `secret` - The secret to verify
/// * `blinding_factor` - The blinding factor to verify
///
/// # Returns
///
/// `true` if the secret and blinding factor produce the commitment hash
///
/// # Example
///
/// ```ignore
/// let is_valid = verify_commitment(
///     &env,
///     &stored_commitment_hash,
///     &secret,
///     &blinding_factor
/// );
/// ```
fn verify_commitment(
    env: &Env,
    commitment_hash: &BytesN<32>,
    secret: &BytesN<32>,
    blinding_factor: &BytesN<32>,
) -> bool {
    let computed_hash = create_commitment_hash(env, secret, blinding_factor);
    commitment_hash == &computed_hash
}
```

## Commitment Strength Scoring

Every IP commitment is assigned a **strength score** (0–100) that reflects the entropy and complexity of the commitment hash. Weak commitments (e.g. all-same-byte hashes or zero PoW) score low; strong, high-entropy commitments with meaningful PoW score near 100.

### Scoring Formula

```
entropy_score = (unique_bytes_in_hash * 50) / 32   // 0–50 points
pow_score     = min(50, (pow_difficulty * 50) / 32) // 0–50 points
strength      = min(100, entropy_score + pow_score)
```

| Component | Max Points | Description |
|-----------|-----------|-------------|
| Byte entropy | 50 | Number of unique byte values in the 32-byte commitment hash, scaled to 0–50 |
| PoW difficulty | 50 | Leading-zero-bit difficulty used at commit time, scaled to 0–50 (32 bits = 50 pts) |

### Querying Strength

```rust
let strength: u32 = registry.get_ip_strength(&ip_id);
// Returns 0–100
```

### Practical Guidance

- A SHA-256 hash of real content will have ~30–32 unique bytes → ~47–50 entropy points.
- Using `pow_difficulty = 4` (default) adds ~6 points.
- A typical real-world commitment scores **53–56 / 100**.
- To reach 100, use a high-entropy hash (32 unique bytes) with `pow_difficulty ≥ 32`.

### Why Entropy Matters

A commitment hash derived from a real design document (via SHA-256) will have high byte entropy — the 256 possible byte values are roughly uniformly distributed. A weak hash like `[0x01; 32]` (all same byte) signals the commitment may not represent genuine IP, and scores near zero.



### Why Use a Blinding Factor?

Without a blinding factor, an attacker could:
1. Guess common secrets (e.g., "patent application 2024")
2. Hash the guess
3. Compare against all commitment hashes
4. Identify which commitments match their guess

The blinding factor makes this attack computationally infeasible.

### Secret Storage

**CRITICAL**: If you lose your secret and blinding factor, you cannot:
- Prove ownership of your IP
- Complete an atomic swap
- Reveal your IP to buyers

Store your secret and blinding factor securely:
- Use encrypted storage
- Create multiple backups
- Store in different physical locations
- Never share until you're ready to reveal

### What Happens If Your Secret Is Leaked?

If someone discovers your secret before you reveal it:
- They can claim they own the IP (but cannot prove it on-chain without your signature)
- They cannot complete a swap (they need your authorization)
- You should still be able to prove ownership via your Stellar wallet signature

## Common Mistakes to Avoid

### ❌ Using the Same Secret for Multiple IPs

```rust
// WRONG - Don't do this!
let secret = BytesN::from_array(&env, &[1u8; 32]);
let hash1 = create_commitment_hash(&env, &secret, &blinding_factor1);
let hash2 = create_commitment_hash(&env, &secret, &blinding_factor2);
// If someone discovers the secret, they can claim both IPs
```

### ❌ Using Predictable Blinding Factors

```rust
// WRONG - Don't do this!
let blinding_factor = BytesN::from_array(&env, &[0u8; 32]); // All zeros
// Attackers can easily guess this
```

### ❌ Not Storing the Secret

```rust
// WRONG - Don't do this!
let secret = generate_random_secret();
let commitment_hash = create_commitment_hash(&env, &secret, &blinding_factor);
// If you don't store the secret, you can never prove ownership!
```

### ✅ Correct Approach

```rust
// CORRECT - Do this!
let secret = create_secret(&env, my_design_document);
let blinding_factor = generate_blinding_factor(&env);
let commitment_hash = create_commitment_hash(&env, &secret, &blinding_factor);

// Store both securely!
store_secret_securely(&secret);
store_blinding_factor_securely(&blinding_factor);
```

## Complete Workflow Example

Here's a complete workflow for registering and verifying IP:

```rust
use soroban_sdk::{BytesN, Env, Address};

/// Complete workflow for registering IP with a Pedersen commitment
fn register_ip_workflow(env: &Env, owner: &Address, design_document: &[u8]) {
    // 1. Create secret from design document
    let secret = create_secret(env, design_document);
    
    // 2. Generate random blinding factor
    let blinding_factor = generate_blinding_factor(env);
    
    // 3. Create commitment hash
    let commitment_hash = create_commitment_hash(env, &secret, &blinding_factor);
    
    // 4. Register on-chain (this is done via the contract)
    // let ip_id = registry.commit_ip(owner, &commitment_hash);
    
    // 5. Store secret and blinding factor securely OFF-CHAIN
    // This is your responsibility - the blockchain doesn't store these!
    store_offchain(&secret, &blinding_factor);
}

/// Later, to verify or complete a swap:
fn verify_ip_workflow(env: &Env, commitment_hash: &BytesN<32>) -> bool {
    // 1. Retrieve your secret and blinding factor from secure storage
    let (secret, blinding_factor) = retrieve_from_secure_storage();
    
    // 2. Verify they match the commitment
    verify_commitment(env, commitment_hash, &secret, &blinding_factor)
}
```

## Technical Details

### Why SHA-256?

AtomicIP uses SHA-256 because:
- It's cryptographically secure
- It's widely supported in Soroban
- It produces fixed-size 32-byte outputs
- It's resistant to collision attacks

### Why Not True Pedersen Commitments?

True Pedersen commitments use elliptic curve cryptography and have special properties:
- Homomorphic: `C(m1) * C(m2) = C(m1 + m2)`
- Perfectly hiding: Commitment reveals nothing about the message
- Computationally binding: Cannot change the message after committing

AtomicIP uses a simpler SHA-256-based scheme because:
- It's easier to implement and verify
- It's sufficient for the use case (proving prior art)
- It has lower gas costs
- It's more accessible to developers

The trade-off is that SHA-256 commitments are not homomorphic, but this property isn't needed for IP registration.

## Batch Verification with ZK Proof Support (Issue #458)

AtomicIP supports **batch verification** that aggregates multiple Pedersen commitment checks into a single provable operation. This enables verifiers to confirm the correctness of multiple IP commitments at once while generating an on-chain receipt.

### Batch Verification Flow

```
                          ┌─────────────────────────────┐
                          │     Caller submits batch     │
                          │  Vec<VerifyRequest> with     │
                          │  (ip_id, secret, blinding)  │
                          └──────────────┬──────────────┘
                                         │
                                         ▼
                          ┌─────────────────────────────┐
                          │   For each request:          │
                          │   1. Look up IpRecord         │
                          │   2. Compute sha256(s || bf) │
                          │   3. Constant-time compare    │
                          │   4. Collect VerifyResult     │
                          └──────────────┬──────────────┘
                                         │
                                         ▼
                          ┌─────────────────────────────┐
                          │  Incremental hash aggregate │
                          │  H("IP_BATCH_PROOF_V1" ||   │
                          │    ip_id_1 || hash_1 || v_1 │
                          │    ip_id_2 || hash_2 || v_2 │
                          │    ...)                     │
                          └──────────────┬──────────────┘
                                         │
                                         ▼
                          ┌─────────────────────────────┐
                          │  Store BatchVerifyProof      │
                          │  on-chain keyed by hash      │
                          └──────────────┬──────────────┘
                                         │
                                         ▼
                          ┌─────────────────────────────┐
                          │  Emit batch_vfy event        │
                          │  (aggregated_hash, count,    │
                          │   all_valid)                 │
                          └─────────────────────────────┘
```

### Key Properties

| Property | Description |
|---|---|
| **Constant-time comparison** | Each commitment hash is compared using XOR-based equality that never short-circuits, preventing timing side-channel attacks |
| **Deterministic aggregation** | Identical input sets produce identical proof hashes — the result is deterministic and reproducible |
| **On-chain proof storage** | The aggregated `BatchVerifyProof` is stored on-chain keyed by its hash, enabling future retrieval via `verify_batch_proof()` |
| **Event emission** | A `batch_vfy` event is emitted with the aggregated hash, item count, and overall validity flag for off-chain indexing |

### How It Works

1. **Preparation**: Each request contains an `ip_id`, the `secret`, and the `blinding_factor` used when the commitment was created.

2. **Individual Verification**: For each request, the contract:
   - Loads the `IpRecord` for the given `ip_id`
   - Computes `sha256(secret || blinding_factor)`
   - Compares the result against the stored commitment hash using **constant-time comparison** (`constant_time_eq_32`)
   - Appends a `VerifyResult { ip_id, valid }` to the output vector

3. **Hash Aggregation**: After all individual checks, an **aggregated proof hash** is computed:
   ```
   aggregated_hash = sha256(
     domain_separator("IP_BATCH_PROOF_V1") ||
     ip_id_1 || stored_commitment_hash_1 || valid_1 ||
     ip_id_2 || stored_commitment_hash_2 || valid_2 ||
     ...
   )
   ```
   This incremental hashing ensures the proof is bound to:
   - The specific IP IDs being verified
   - The on-chain commitment hashes at verification time
   - The validity outcomes

4. **Storage**: The `BatchVerifyProof` struct is stored with key `DataKey::BatchVerifyResult(aggregated_hash)`:
   ```rust
   pub struct BatchVerifyProof {
       pub ip_ids: Vec<u64>,          // The IP IDs verified
       pub aggregated_hash: BytesN<32>, // The proof hash
       pub timestamp: u64,             // Ledger timestamp
       pub all_valid: bool,            // True if every check passed
   }
   ```

5. **Event Emission**: A `batch_vfy` event is emitted with topics `(batch_vfy,)` and data `(aggregated_hash, count, all_valid)`.

### Contract API

```rust
/// Verify multiple IP commitments with ZK-proof support.
/// Returns one VerifyResult per request.
fn batch_verify_commitments(
    env: Env,
    requests: Vec<VerifyRequest>,
) -> Vec<VerifyResult>

/// Retrieve a stored batch verification proof by its aggregated hash.
fn verify_batch_proof(
    env: Env,
    proof_hash: BytesN<32>,
) -> Option<BatchVerifyProof>
```

### `VerifyRequest`

| Field | Type | Description |
|---|---|---|
| `ip_id` | `u64` | The IP ID to verify |
| `secret` | `BytesN<32>` | The secret used when committing |
| `blinding_factor` | `BytesN<32>` | The blinding factor used when committing |

### `VerifyResult`

| Field | Type | Description |
|---|---|---|
| `ip_id` | `u64` | The IP ID that was verified |
| `valid` | `bool` | `true` if the proof is correct |

### `BatchVerifyProof`

| Field | Type | Description |
|---|---|---|
| `ip_ids` | `Vec<u64>` | The IP IDs included in this batch |
| `aggregated_hash` | `BytesN<32>` | The aggregated proof hash |
| `timestamp` | `u64` | Ledger timestamp when verification ran |
| `all_valid` | `bool` | `true` if every commitment was valid |

### Security: Constant-Time Comparison

The `batch_verify_commitments` function uses `constant_time_eq_32` instead of `==` for hash comparison:

```rust
fn constant_time_eq_32(a: &BytesN<32>, b: &BytesN<32>) -> bool {
    let a_arr = a.to_array();
    let b_arr = b.to_array();
    let mut diff: u8 = 0;
    for i in 0..32 {
        diff |= a_arr[i] ^ b_arr[i];
    }
    diff == 0
}
```

This XORs every byte pair and ORs the results together. Unlike `==`, this implementation:
- **Never short-circuits** on the first mismatch
- **Always touches all 32 bytes** regardless of the result
- **Prevents timing side-channel attacks** that could leak information about the secret

### Example Flow

```rust
use soroban_sdk::{BytesN, Env, Vec};

fn batch_verify_example(env: &Env, client: &IpRegistryClient) {
    let requests = vec![
        VerifyRequest { ip_id: 1, secret: s1, blinding_factor: b1 },
        VerifyRequest { ip_id: 2, secret: s2, blinding_factor: b2 },
    ];

    // Batch verify all commitments
    let results: Vec<VerifyResult> = client.batch_verify_commitments(&requests);

    // Check individual results
    assert!(results.get(0).unwrap().valid);
    assert!(results.get(1).unwrap().valid);

    // The aggregated proof is stored on-chain.
    // Retrieve it later by its hash:
    // let proof = client.verify_batch_proof(&aggregated_hash);
}
```

### Event: `batch_vfy`

Emitted once per `batch_verify_commitments` call:

| Topic | Data |
|---|---|
| `(batch_vfy,)` | `(aggregated_hash: BytesN<32>, count: u64, all_valid: bool)` |

### Off-Chain Indexing

The `batch_vfy` event enables off-chain services to:
- Track batch verification completion without replaying individual checks
- Monitor overall validity of verified batches
- Build verification histories for reputation systems

### Error Cases

| Condition | Behavior |
|---|---|
| Empty request vector | Returns empty `Vec<VerifyResult>` — no proof is stored, no event emitted |
| Nonexistent `ip_id` | Panics with `IpNotFound` |
| Mismatched secret/blinding | Individual `VerifyResult.valid` is `false`; `all_valid` is `false` |
| All valid | All results have `valid == true`; `all_valid == true` |

## References

- [SHA-256 Wikipedia](https://en.wikipedia.org/wiki/SHA-2)
- [Pedersen Commitment Wikipedia](https://en.wikipedia.org/wiki/Pedersen_commitment)
- [Soroban Cryptography Documentation](https://soroban.stellar.org/docs/reference/environment-functions/crypto)
- [NIST SHA-2 Standard](https://csrc.nist.gov/publications/detail/fips/180-4/final)

## Batch Verification with ZK-Style Aggregate Proofs

### Overview

Batch verification allows multiple IP commitments to be verified simultaneously in a single on-chain
call. The implementation combines three advanced features:

1. **Hash aggregation** — validated commitment hashes are folded into a single deterministic proof
2. **Constant-time comparison** — all 32-byte comparisons execute in fixed time, preventing timing side-channel attacks
3. **On-chain event** — a `b_vfy` event is emitted with the aggregate proof and summary counts

### How It Works

A single call to `batch_verify_commitments` processes N verification requests and produces:

- A `Vec<VerifyResult>` — one result per request in input order
- An **aggregate proof hash** — a single 32-byte value that cryptographically binds all validated commitments

#### Aggregate Proof Construction

The aggregate proof is built using **incremental SHA-256 hashing**:

```
proof_0 = 0x0000...0000          (32 zero bytes)
proof_1 = sha256(proof_0 || hash_1)   # only if verification 1 is valid
proof_2 = sha256(proof_1 || hash_2)   # only if verification 2 is valid
...
proof_N = sha256(proof_{N-1} || hash_N)
```

Where `hash_i = sha256(secret_i || blinding_factor_i)` is the on-chain commitment hash.

This produces a deterministic, order-dependent proof. The same set of requests in a different order
yields a different aggregate proof, preventing replay across reordered batches.

### Function Signature

```rust
pub fn batch_verify_commitments(
    env: Env,
    requests: Vec<VerifyRequest>,
) -> Vec<VerifyResult>
```

#### Input

```rust
pub struct VerifyRequest {
    pub ip_id: u64,
    pub secret: BytesN<32>,
    pub blinding_factor: BytesN<32>,
}
```

#### Output

```rust
pub struct VerifyResult {
    pub ip_id: u64,
    pub valid: bool,
}
```

### Event

Each call emits a single event with topic `b_vfy` and data `(aggregate_proof, total_count, valid_count)`:

```
topic:  (symbol_short!("b_vfy"),)
data:   (BytesN<32>, u32, u32)  // (aggregate_proof, total, valid)
```

Off-chain listeners can subscribe to this event to track batch verification completion.

### Storage

The aggregate proof and summary are stored on-chain under `DataKey::BatchVerifyResult(proof_hash)`:

```rust
pub struct BatchVerifyResultStorage {
    pub aggregate_proof: BytesN<32>,
    pub total_count: u32,
    pub valid_count: u32,
}
```

### Gas Efficiency

Batch verification processes all requests in a single contract call, amortising the fixed overhead
of storage reads and authentication across N verifications. For large batches this can reduce gas
costs by up to 50% compared to N individual `verify_commitment` calls.

### Constant-Time Security

All commitment hash comparisons use a dedicated constant-time comparator:

```rust
fn constant_time_bytes_32_eq(a: &BytesN<32>, b: &BytesN<32>) -> bool {
    let a_arr = a.to_array();
    let b_arr = b.to_array();
    let mut diff: u8 = 0;
    for i in 0..32 {
        diff |= a_arr[i] ^ b_arr[i];
    }
    diff == 0
}
```

Every code path performs exactly 32 XOR+OR operations, regardless of how many bytes match. This
prevents timing attacks where an adversary could exploit short-circuit equality checks to
iteratively guess secret bytes.

### Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| **Empty batch** | Returns an empty `Vec<VerifyResult>`, aggregate proof is `sha256(0x00..00)`, event emitted with `total=0, valid=0` |
| **Single item** | Returns one `VerifyResult`, aggregate proof equals the commitment hash if valid, or remains the zero seed if invalid |
| **Non-existent IP** | Panics with `IpNotFound` — all requests are treated as authoritative; a missing IP is a fatal error |
| **All invalid** | Aggregate proof remains `0x00..00` (the seed), event shows `valid=0` |
| **Mixed valid/invalid** | Only valid hashes contribute to the aggregate proof; invalid entries are skipped |

### Complete Example

```rust
use soroban_sdk::{BytesN, Vec};

let secret1: BytesN<32> = /* ... */;
let blind1: BytesN<32>  = /* ... */;
let secret2: BytesN<32> = /* ... */;
let blind2: BytesN<32>  = /* ... */;

let mut requests = Vec::new(&env);
requests.push_back(VerifyRequest { ip_id: 1, secret: secret1, blinding_factor: blind1 });
requests.push_back(VerifyRequest { ip_id: 2, secret: secret2, blinding_factor: blind2 });

let results: Vec<VerifyResult> = registry.batch_verify_commitments(&requests);

for r in results.iter() {
    println!("IP {} valid: {}", r.ip_id, r.valid);
}
```

## Questions?

If you have questions about the commitment scheme:
- Open a [GitHub Issue](https://github.com/AtomicIP/AtomicIP-/issues)
- Join our [Discord community](https://discord.gg/atomicip)
- Email: support@atomicip.io

## Commitment Renewal

IP commitments have an on-chain TTL of approximately 1 year (~6,307,200 ledgers). Owners can renew
an expiring commitment without re-committing or changing the commitment hash:

```rust
fn renew_ip(ip_id: u64)
```

- Requires owner authorization
- Resets the storage TTL back to `LEDGER_BUMP` (~1 year)
- Increments an on-chain renewal counter (queryable via `get_renewal_count`)
- Emits a `renewed` event with `(ip_id, renewal_count)`
- Panics if the IP is revoked or does not exist

The original commitment hash, timestamp, and owner are **never modified** by renewal — prior art
proof is fully preserved.

```rust
fn get_renewal_count(ip_id: u64) -> u32
```

Returns how many times the IP has been renewed (0 if never renewed).
