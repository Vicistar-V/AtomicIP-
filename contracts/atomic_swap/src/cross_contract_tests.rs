/// Unit tests for cross-contract failure attribution.
///
/// Covers:
/// 1. Successful cross-contract execution — no failure, result is `Ok`.
/// 2. Single contract failure — `FailureAttribution` names the failing contract
///    and the call chain is empty.
/// 3. Nested call chain failure — an inner contract failure propagated through
///    an outer contract carries the full call chain in outermost→innermost order.
#[cfg(test)]
mod cross_contract_tests {
    use soroban_sdk::{testutils::Address as _, Address, BytesN, Env, String};

    use crate::cross_contract::{
        attribute_failure, propagate_failure, CrossContractResult, FailureAttribution,
    };

    // ── helpers ───────────────────────────────────────────────────────────────

    fn make_attribution(env: &Env, contract: &Address, reason: &str) -> FailureAttribution {
        attribute_failure(env, contract.clone(), reason)
    }

    // ── 1. Successful execution flow ─────────────────────────────────────────

    /// When a cross-contract call succeeds no `FailureAttribution` is produced.
    #[test]
    fn test_cross_contract_success_returns_ok() {
        let env = Env::default();
        let value: u64 = 42;
        let result: CrossContractResult<u64> = CrossContractResult::Ok(value);
        match result {
            CrossContractResult::Ok(v) => assert_eq!(v, 42),
            CrossContractResult::Err(_) => panic!("expected Ok"),
        }
    }

    /// A successful result carries the correct value through.
    #[test]
    fn test_cross_contract_ok_preserves_value() {
        let env = Env::default();
        let addr = Address::generate(&env);
        let result: CrossContractResult<Address> = CrossContractResult::Ok(addr.clone());
        if let CrossContractResult::Ok(got) = result {
            assert_eq!(got, addr);
        } else {
            panic!("expected Ok");
        }
    }

    // ── 2. Single contract failure ────────────────────────────────────────────

    /// `attribute_failure` produces attribution naming the failing contract,
    /// an empty call chain, and the provided reason string.
    #[test]
    fn test_single_failure_attribution_names_contract() {
        let env = Env::default();
        let failing_contract = Address::generate(&env);
        let attr = make_attribution(&env, &failing_contract, "ip_not_found");

        assert_eq!(attr.contract, failing_contract);
        assert_eq!(attr.reason, String::from_str(&env, "ip_not_found"));
        assert!(attr.call_chain.is_empty());
    }

    /// A single failure is correctly wrapped in `CrossContractResult::Err`.
    #[test]
    fn test_single_failure_wrapped_in_err() {
        let env = Env::default();
        let failing = Address::generate(&env);
        let attr = make_attribution(&env, &failing, "not_owner");
        let result: CrossContractResult<u64> = CrossContractResult::Err(attr.clone());

        match result {
            CrossContractResult::Ok(_) => panic!("expected Err"),
            CrossContractResult::Err(a) => {
                assert_eq!(a.contract, failing);
                assert!(a.call_chain.is_empty());
            }
        }
    }

    /// `attribute_failure` with different reasons are distinct.
    #[test]
    fn test_failure_attribution_reason_distinct() {
        let env = Env::default();
        let c = Address::generate(&env);
        let a1 = attribute_failure(&env, c.clone(), "reason_a");
        let a2 = attribute_failure(&env, c.clone(), "reason_b");
        assert_ne!(a1.reason, a2.reason);
    }

    // ── 3. Nested failure propagation ─────────────────────────────────────────

    /// When contract B calls contract C and C fails, B propagates the failure
    /// by prepending its own address to the call chain.
    ///
    /// Before propagation: `{ contract: C, call_chain: [] }`
    /// After propagation:  `{ contract: C, call_chain: [B] }`
    #[test]
    fn test_nested_failure_one_level_propagation() {
        let env = Env::default();
        let contract_b = Address::generate(&env);
        let contract_c = Address::generate(&env);

        // C fails; B propagates the failure outward.
        let inner_attr = make_attribution(&env, &contract_c, "registry_error");
        let propagated = propagate_failure(&env, contract_b.clone(), inner_attr);

        // The failing contract is still C.
        assert_eq!(propagated.contract, contract_c);
        // The call chain records B as the intermediate caller.
        assert_eq!(propagated.call_chain.len(), 1);
        assert_eq!(propagated.call_chain.get(0).unwrap(), contract_b);
    }

    /// Three-level chain: A → B → C, C fails.
    ///
    /// Expected final attribution:
    ///   `{ contract: C, call_chain: [A, B] }`
    #[test]
    fn test_nested_failure_two_level_propagation() {
        let env = Env::default();
        let contract_a = Address::generate(&env);
        let contract_b = Address::generate(&env);
        let contract_c = Address::generate(&env);

        // Step 1: C fails.
        let inner_attr = make_attribution(&env, &contract_c, "commitment_mismatch");
        // Step 2: B propagates outward through A's call.
        let after_b = propagate_failure(&env, contract_b.clone(), inner_attr);
        // Step 3: A propagates outward.
        let after_a = propagate_failure(&env, contract_a.clone(), after_b);

        assert_eq!(after_a.contract, contract_c);
        assert_eq!(after_a.call_chain.len(), 2);
        // Chain is outermost → innermost: [A, B].
        assert_eq!(after_a.call_chain.get(0).unwrap(), contract_a);
        assert_eq!(after_a.call_chain.get(1).unwrap(), contract_b);
    }

    /// Propagation does not mutate the original attribution.
    #[test]
    fn test_propagation_does_not_mutate_original() {
        let env = Env::default();
        let contract_b = Address::generate(&env);
        let contract_c = Address::generate(&env);

        let original = make_attribution(&env, &contract_c, "swap_not_found");
        assert!(original.call_chain.is_empty());

        let propagated = propagate_failure(&env, contract_b, original.clone());
        // Original is unchanged.
        assert!(original.call_chain.is_empty());
        // Propagated has one entry.
        assert_eq!(propagated.call_chain.len(), 1);
    }

    /// The reason string is preserved unchanged through propagation.
    #[test]
    fn test_propagation_preserves_reason() {
        let env = Env::default();
        let intermediate = Address::generate(&env);
        let failing = Address::generate(&env);

        let attr = make_attribution(&env, &failing, "invalid_key");
        let propagated = propagate_failure(&env, intermediate, attr);

        assert_eq!(propagated.reason, String::from_str(&env, "invalid_key"));
    }

    // ── 4. scval_to_string utility ────────────────────────────────────────────

    /// `scval_to_string` converts a bool ScVal correctly.
    #[test]
    fn test_scval_to_string_bool_true() {
        use crate::utils::scval_to_string;
        use soroban_sdk::xdr::ScVal;
        let env = Env::default();
        let s = scval_to_string(&env, &ScVal::Bool(true));
        assert_eq!(s, String::from_str(&env, "true"));
    }

    #[test]
    fn test_scval_to_string_bool_false() {
        use crate::utils::scval_to_string;
        use soroban_sdk::xdr::ScVal;
        let env = Env::default();
        let s = scval_to_string(&env, &ScVal::Bool(false));
        assert_eq!(s, String::from_str(&env, "false"));
    }

    #[test]
    fn test_scval_to_string_void() {
        use crate::utils::scval_to_string;
        use soroban_sdk::xdr::ScVal;
        let env = Env::default();
        assert_eq!(
            scval_to_string(&env, &ScVal::Void),
            String::from_str(&env, "void")
        );
    }

    #[test]
    fn test_scval_to_string_address() {
        use crate::utils::scval_to_string;
        use soroban_sdk::xdr::ScVal;
        let env = Env::default();
        assert_eq!(
            scval_to_string(&env, &ScVal::Address(Default::default())),
            String::from_str(&env, "address")
        );
    }

    #[test]
    fn test_scval_to_string_vec() {
        use crate::utils::scval_to_string;
        use soroban_sdk::xdr::ScVal;
        let env = Env::default();
        assert_eq!(
            scval_to_string(&env, &ScVal::Vec(None)),
            String::from_str(&env, "vec")
        );
    }

    #[test]
    fn test_scval_to_string_bytes() {
        use crate::utils::scval_to_string;
        use soroban_sdk::xdr::ScVal;
        let env = Env::default();
        let bytes_val = ScVal::Bytes(soroban_sdk::xdr::ScBytes::default());
        assert_eq!(
            scval_to_string(&env, &bytes_val),
            String::from_str(&env, "bytes")
        );
    }
}
