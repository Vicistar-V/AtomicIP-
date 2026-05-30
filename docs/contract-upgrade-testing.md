# Contract Upgrade Testing (#557)

## Overview

Soroban contracts are upgraded in place via
`env.deployer().update_current_contract_wasm(new_wasm_hash)`. Because the same
persistent storage survives the swap, a new WASM that drops a storage key,
removes a function, or renumbers an error code can silently corrupt live data.
These tests pin down the **upgrade-safety surface** of the IP Registry contract
so an incompatible or unauthorized upgrade is rejected before it can run.

```bash
cargo test -p ip_registry upgrade_tests
```

## What is tested

The suite lives in `contracts/ip_registry/src/upgrade_tests.rs` and exercises
the two guards that protect an upgrade:

| Test | Property | Expected outcome |
|------|----------|------------------|
| `validate_upgrade_accepts_typical_hash` | A well-formed candidate WASM hash is accepted | No panic |
| `validate_upgrade_accepts_all_ones_hash` | Boundary hash (`0xff…`) is accepted | No panic |
| `validate_upgrade_accepts_single_nonzero_byte` | Smallest non-zero hash is accepted | No panic |
| `validate_upgrade_rejects_zero_hash` | The zero hash (no/garbage WASM) is rejected | Panics `#5 UnauthorizedUpgrade` |
| `validate_upgrade_is_idempotent` | The check is repeatable | No panic across repeated calls |
| `validate_upgrade_preserves_committed_state` | Compatibility validation is read-only | Committed records and ID allocation unchanged |
| `upgrade_rejected_when_no_admin_initialized` | Upgrade requires an established admin | Panics `#5 UnauthorizedUpgrade` |

## Upgrade-compatibility contract

The following must **not** change across an upgrade, or committed IP records
become unreadable:

| Category | Rule |
|----------|------|
| Storage keys | `DataKey` variants in use (e.g. `IpRecord`, `Admin`, `NextId`) must be preserved |
| Function names | Existing exported functions must remain callable |
| Error codes | `ContractError` discriminants must be stable (e.g. `UnauthorizedUpgrade = 5`) |
| Record layout | `IpRecord` fields must remain backward-compatible |

`validate_upgrade` is the on-chain gate for this contract. It currently rejects
an obviously invalid (zero) WASM hash; richer manifest comparison (enumerating
functions, storage keys and error codes) is tracked as a TODO in
`contracts/ip_registry/src/lib.rs`.

## What is intentionally *not* unit-tested

The successful `upgrade` path calls `update_current_contract_wasm`, which
requires a genuinely **installed** WASM hash. The unit-test host cannot install
a second contract WASM, so the success path is validated on testnet during a
real deploy (see `docs/deployment-guide.md`) rather than in unit tests. The
compatibility check and the admin-authorization guard that protect that call
are what these tests cover.

## Adding new upgrade tests

1. Add a `#[test]` to the `upgrade_tests` module.
2. For rejection paths, assert the specific error with
   `#[should_panic(expected = "Error(Contract, #5)")]`.
3. For state-preservation properties, commit records, run the operation under
   test, then assert records and `NextId` allocation are unchanged.
4. Document the new case in the table above.
