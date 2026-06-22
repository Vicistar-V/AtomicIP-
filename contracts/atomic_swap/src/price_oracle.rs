//! Price Oracle Integration for Atomic Swap
//!
//! Provides dynamic pricing by querying an on-chain price oracle contract.
//! The oracle contract must implement the `get_price(token: Address) -> i128`
//! interface (returns price in the same unit as swap prices, i.e. stroops).
//!
//! # Design
//! - Admin sets the oracle contract address via `set_oracle`.
//! - `initiate_swap_with_oracle_price` fetches the current price from the oracle
//!   and validates it falls within an optional `[min_price, max_price]` band
//!   before creating the swap.
//! - The oracle address is stored under `DataKey::OracleConfig`.
//! - Price freshness is validated (< 5 min staleness threshold).
//! - Stale prices fallback to cached prices if available.

use soroban_sdk::{contracttype, symbol_short, Address, Env, IntoVal, Val};

use crate::{ContractError, DataKey, LEDGER_BUMP};

// ── Oracle Constants ──────────────────────────────────────────────────────────

/// Maximum allowed staleness for oracle prices (300 seconds = 5 minutes).
pub const ORACLE_STALENESS_THRESHOLD_SECS: u64 = 300;

// ── Oracle Config ─────────────────────────────────────────────────────────────

/// Configuration for the price oracle.
#[contracttype]
#[derive(Clone, Debug, PartialEq)]
pub struct OracleConfig {
    /// Address of the oracle contract.
    pub oracle_address: Address,
    /// Whether oracle-based pricing is enabled.
    pub enabled: bool,
    /// Timestamp of the last successful price fetch (ledger timestamp).
    pub last_update_timestamp: u64,
    /// The last successfully fetched price (used as fallback for stale data).
    pub cached_price: i128,
}

// ── Oracle Event ──────────────────────────────────────────────────────────────

/// Emitted when the oracle config is updated by admin.
#[contracttype]
#[derive(Clone, Debug, PartialEq)]
pub struct OracleConfigSetEvent {
    pub oracle_address: Address,
    pub enabled: bool,
}

/// Emitted when a swap is initiated using an oracle-derived price.
#[contracttype]
#[derive(Clone, Debug, PartialEq)]
pub struct OraclePriceUsedEvent {
    pub swap_id: u64,
    pub oracle_price: i128,
}

/// Emitted when an oracle price is considered stale and fallback is used.
#[contracttype]
#[derive(Clone, Debug, PartialEq)]
pub struct OracleStalePriceEvent {
    pub token: Address,
    pub stale_price: i128,
    pub fallback_price: i128,
    pub staleness_secs: u64,
}

// ── Storage helpers ───────────────────────────────────────────────────────────

pub fn store_oracle_config(env: &Env, config: &OracleConfig) {
    env.storage()
        .persistent()
        .set(&DataKey::OracleConfig, config);
    env.storage()
        .persistent()
        .extend_ttl(&DataKey::OracleConfig, LEDGER_BUMP, LEDGER_BUMP);
}

pub fn load_oracle_config(env: &Env) -> Option<OracleConfig> {
    env.storage().persistent().get(&DataKey::OracleConfig)
}

// ── Oracle client ─────────────────────────────────────────────────────────────

/// Calls `get_price(token)` on the configured oracle contract.
/// Returns the price in stroops (i128).
///
/// # Errors
/// Panics with `OracleNotConfigured` if no oracle is set or it is disabled.
/// Panics with `OraclePriceInvalid` if the returned price is ≤ 0.
pub fn fetch_oracle_price(env: &Env, token: &Address) -> i128 {
    let config = load_oracle_config(env).unwrap_or_else(|| {
        env.panic_with_error(soroban_sdk::Error::from_contract_error(
            ContractError::OracleNotConfigured as u32,
        ))
    });

    if !config.enabled {
        env.panic_with_error(soroban_sdk::Error::from_contract_error(
            ContractError::OracleNotConfigured as u32,
        ));
    }

    // Cross-contract call: oracle must expose `get_price(token: Address) -> i128`
    let mut args: soroban_sdk::Vec<Val> = soroban_sdk::Vec::new(env);
    args.push_back(token.into_val(env));
    let price: i128 =
        env.invoke_contract(&config.oracle_address, &symbol_short!("get_price"), args);

    if price <= 0 {
        env.panic_with_error(soroban_sdk::Error::from_contract_error(
            ContractError::OraclePriceInvalid as u32,
        ));
    }

    price
}

/// Fetches the oracle price with staleness validation.
/// If the price is stale (> 5 minutes since last update), falls back to cached price.
///
/// # Returns
/// The fresh oracle price or the cached price if oracle is stale.
///
/// # Errors
/// Panics with `OracleNotConfigured` if no oracle is set or it is disabled.
/// Panics with `OraclePriceInvalid` if the returned price is ≤ 0.
pub fn fetch_oracle_price_with_staleness_check(env: &Env, token: &Address) -> i128 {
    let config = load_oracle_config(env).unwrap_or_else(|| {
        env.panic_with_error(soroban_sdk::Error::from_contract_error(
            ContractError::OracleNotConfigured as u32,
        ))
    });

    if !config.enabled {
        env.panic_with_error(soroban_sdk::Error::from_contract_error(
            ContractError::OracleNotConfigured as u32,
        ));
    }

    let current_timestamp = env.ledger().timestamp();
    let staleness_secs = current_timestamp.saturating_sub(config.last_update_timestamp);

    // Check if price is fresh
    if staleness_secs <= ORACLE_STALENESS_THRESHOLD_SECS {
        // Price is fresh, fetch new price from oracle
        let mut args: soroban_sdk::Vec<Val> = soroban_sdk::Vec::new(env);
        args.push_back(token.into_val(env));
        let price: i128 =
            env.invoke_contract(&config.oracle_address, &symbol_short!("get_price"), args);

        if price <= 0 {
            env.panic_with_error(soroban_sdk::Error::from_contract_error(
                ContractError::OraclePriceInvalid as u32,
            ));
        }

        // Update cache with new price and timestamp
        let updated_config = OracleConfig {
            oracle_address: config.oracle_address.clone(),
            enabled: config.enabled,
            last_update_timestamp: current_timestamp,
            cached_price: price,
        };
        store_oracle_config(env, &updated_config);

        price
    } else {
        // Price is stale, use cached price and emit event
        env.events().publish(
            (symbol_short!("stale"),),
            OracleStalePriceEvent {
                token: token.clone(),
                stale_price: config.cached_price,
                fallback_price: config.cached_price,
                staleness_secs,
            },
        );

        if config.cached_price <= 0 {
            env.panic_with_error(soroban_sdk::Error::from_contract_error(
                ContractError::OraclePriceInvalid as u32,
            ));
        }

        config.cached_price
    }
}

/// Validates that `price` falls within `[min_price, max_price]` if bounds are set.
/// A value of `0` for either bound means "no bound".
pub fn validate_price_bounds(env: &Env, price: i128, min_price: i128, max_price: i128) {
    if min_price > 0 && price < min_price {
        env.panic_with_error(soroban_sdk::Error::from_contract_error(
            ContractError::OraclePriceBelowMin as u32,
        ));
    }
    if max_price > 0 && price > max_price {
        env.panic_with_error(soroban_sdk::Error::from_contract_error(
            ContractError::OraclePriceAboveMax as u32,
        ));
    }
}
