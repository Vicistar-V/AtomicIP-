/// Cross-contract call utilities with failure attribution.
///
/// When a call chain spans multiple contracts, a failure in an inner contract
/// must be attributed to the specific contract that failed rather than surfacing
/// as an opaque error from the outermost caller. This module provides types and
/// helpers to capture that attribution.
use soroban_sdk::{contracttype, Address, Env, String, Vec};

// ── Types ─────────────────────────────────────────────────────────────────────

/// Identifies which contract in a cross-contract call chain caused a failure.
#[contracttype]
#[derive(Clone, Debug, PartialEq)]
pub struct FailureAttribution {
    /// Address of the contract that produced the error.
    pub contract: Address,
    /// Human-readable description of the failure reason.
    pub reason: String,
    /// Call stack above the failing contract, ordered outermost → innermost
    /// (excluding the failing contract itself).
    pub call_chain: Vec<Address>,
}

/// Result of a cross-contract invocation that may fail.
#[derive(Clone, Debug, PartialEq)]
pub enum CrossContractResult<T> {
    /// Call succeeded; carries the return value.
    Ok(T),
    /// Call failed; carries failure attribution.
    Err(FailureAttribution),
}

// ── Attribution helpers ───────────────────────────────────────────────────────

/// Builds a `FailureAttribution` for a direct (non-nested) failure.
pub fn attribute_failure(env: &Env, contract: Address, reason: &str) -> FailureAttribution {
    FailureAttribution {
        contract,
        reason: String::from_str(env, reason),
        call_chain: Vec::new(env),
    }
}

/// Builds a `FailureAttribution` for a nested failure, prepending the
/// intermediate caller's address to the existing attribution's call chain.
///
/// Example — A calls B which calls C; C fails:
/// - C produces `{ contract: C, call_chain: [] }`
/// - B calls `propagate_failure(env, B_addr, attribution)` →
///   `{ contract: C, call_chain: [B] }`
/// - A calls `propagate_failure(env, A_addr, attribution)` →
///   `{ contract: C, call_chain: [A, B] }`
pub fn propagate_failure(
    env: &Env,
    caller: Address,
    mut attribution: FailureAttribution,
) -> FailureAttribution {
    let mut new_chain: Vec<Address> = Vec::new(env);
    new_chain.push_back(caller);
    for addr in attribution.call_chain.iter() {
        new_chain.push_back(addr);
    }
    attribution.call_chain = new_chain;
    attribution
}

// ── Event processing (test / diagnostics only) ────────────────────────────────

/// Processes raw contract events to extract failure-related information.
///
/// Only non-system contract events are inspected; system events (diagnostics,
/// ledger metadata, fee events) are skipped because they are not emitted by
/// application contracts and do not carry failure attribution data.
///
/// **FIX**: The intent is to process *non*-system contract events only.
/// The previous implementation checked `== ContractEventType::System`, which
/// would process only system events — the opposite of the documented intent.
/// The condition is now `!= ContractEventType::System`.
///
/// Available in test builds only because `env.events().all()` requires
/// `soroban_sdk`'s `testutils` feature.
#[cfg(test)]
pub fn extract_non_system_event_data(env: &Env) -> Vec<String> {
    use crate::utils::scval_to_string;
    use soroban_sdk::testutils::Events as _;
    use soroban_sdk::xdr::ContractEventType;
    let mut result: Vec<String> = Vec::new(env);
    for contract_event in env.events().all().events().iter() {
        // Process only non-system (application) events.
        // FIX: intent is != System, not == System.
        if contract_event.type_ != ContractEventType::System {
            if let soroban_sdk::xdr::ContractEventBody::V0(v0) = &contract_event.body {
                for topic in v0.topics.iter() {
                    result.push_back(scval_to_string(env, topic));
                }
            }
        }
    }
    result
}
