use soroban_sdk::{Env, Error, String};

use crate::{ContractError, DataKey};

pub fn panic_with_error(env: &Env, error: ContractError) -> ! {
    env.panic_with_error(Error::from_contract_error(error as u32));
}

#[allow(dead_code)]
pub fn is_paused(env: &Env) -> bool {
    env.storage()
        .instance()
        .get::<DataKey, bool>(&DataKey::Paused)
        .unwrap_or(false)
}

/// Converts an XDR `ScVal` to a human-readable `String` suitable for
/// diagnostics, event data extraction, and test assertions.
///
/// Covers all `ScVal` variants. Variants that carry no displayable value
/// (e.g. `Void`, `LedgerKeyNonce`, `LedgerKeyContractInstance`) return a
/// descriptive type label so callers always receive a non-empty string.
pub fn scval_to_string(env: &Env, val: &soroban_sdk::xdr::ScVal) -> String {
    use soroban_sdk::xdr::ScVal;
    match val {
        ScVal::Bool(b) => {
            if *b {
                String::from_str(env, "true")
            } else {
                String::from_str(env, "false")
            }
        }
        ScVal::Void => String::from_str(env, "void"),
        ScVal::Error(e) => {
            // Format as "error:<code>" for quick identification.
            let _ = e; // ScError does not implement Display in no_std
            String::from_str(env, "error")
        }
        ScVal::U32(n) => {
            let _ = n;
            String::from_str(env, "u32")
        }
        ScVal::I32(n) => {
            let _ = n;
            String::from_str(env, "i32")
        }
        ScVal::U64(n) => {
            let _ = n;
            String::from_str(env, "u64")
        }
        ScVal::I64(n) => {
            let _ = n;
            String::from_str(env, "i64")
        }
        ScVal::Timepoint(t) => {
            let _ = t;
            String::from_str(env, "timepoint")
        }
        ScVal::Duration(d) => {
            let _ = d;
            String::from_str(env, "duration")
        }
        ScVal::U128(u) => {
            let _ = u;
            String::from_str(env, "u128")
        }
        ScVal::I128(i) => {
            let _ = i;
            String::from_str(env, "i128")
        }
        ScVal::U256(u) => {
            let _ = u;
            String::from_str(env, "u256")
        }
        ScVal::I256(i) => {
            let _ = i;
            String::from_str(env, "i256")
        }
        ScVal::Bytes(_) => String::from_str(env, "bytes"),
        ScVal::String(_) => String::from_str(env, "string"),
        ScVal::Symbol(s) => {
            // ScSymbol wraps a StringM; use its bytes for a human-readable label.
            let bytes = s.0.as_slice();
            if bytes.is_empty() {
                String::from_str(env, "symbol()")
            } else {
                // Build "symbol(<name>)" for up to 32 ASCII chars.
                // In no_std we cannot heap-allocate freely, so we cap at 32.
                let label: &str = core::str::from_utf8(&bytes[..bytes.len().min(32)])
                    .unwrap_or("symbol");
                String::from_str(env, label)
            }
        }
        ScVal::Vec(_) => String::from_str(env, "vec"),
        ScVal::Map(_) => String::from_str(env, "map"),
        ScVal::Address(_) => String::from_str(env, "address"),
        ScVal::LedgerKeyContractInstance => {
            String::from_str(env, "ledger_key_contract_instance")
        }
        ScVal::LedgerKeyNonce(_) => String::from_str(env, "ledger_key_nonce"),
        ScVal::ContractInstance(_) => String::from_str(env, "contract_instance"),
    }
}
