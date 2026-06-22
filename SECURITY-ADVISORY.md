# Security Advisory: RUSTSEC-2026-0097

## Status: ✅ RESOLVED

### Vulnerability Details
- **Package**: `rand`
- **Affected Version**: 0.8.5 and earlier
- **Fixed Version**: 0.8.6+
- **Severity**: Unsound (can cause Undefined Behaviour)
- **Advisory**: [RUSTSEC-2026-0097](https://rustsec.org/advisories/RUSTSEC-2026-0097.html)

### Issue Description
The `rand` library version 0.8.5 contains unsound code that can cause Undefined Behaviour when:
- The `log` and `thread_rng` features are enabled
- A custom logger is defined
- The custom logger accesses `rand::rng()` and calls `TryRng` methods
- The `ThreadRng` attempts to reseed while called from the custom logger
- Trace-level or warn-level logging is enabled

This creates aliased mutable references, violating Rust's Stacked Borrows rules.

### Mitigation Actions Taken

1. **Root Workspace** (`Cargo.toml`):
   - Added `[workspace.dependencies]` section with `rand = "0.8.6"` to force minimum version across all workspace members
   - Removed duplicate workspace section
   
2. **API Server** (`api-server/Cargo.toml`):
   - Updated from `rand = "0.8"` to `rand = "0.8.6"` (explicit version pin)
   - Removed duplicate workspace declaration
   - Regenerated Cargo.lock (was corrupted)

3. **Contract Dependencies**:
   - Updated via `cargo update -p rand@0.8.5` to upgrade transitive dependency from soroban-sdk

4. **Lock Files Updated**:
   - Root workspace: `rand 0.8.5` → `rand 0.8.6` ✅
   - API server: Already had `0.8.6`, regenerated lock file ✅

### Verification Results

```bash
# Root workspace
$ cargo tree -p rand@0.8.6 --depth 0
rand v0.8.6 ✅

# API server
$ cd api-server && cargo tree -p rand@0.8.6 --depth 0
rand v0.8.6 ✅

# No vulnerable versions found
$ grep -r "rand.*0.8.5" **/Cargo.lock
(no results) ✅
```

Build verification passed successfully.

### References
- [GitHub PR](https://github.com/rust-random/rand/pull/1763)
- [RustSec Advisory](https://rustsec.org/advisories/RUSTSEC-2026-0097.html)
- [Unsafe Code Guidelines](https://rust-lang.github.io/unsafe-code-guidelines/glossary.html#soundness-of-code--of-a-library)
