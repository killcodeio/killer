/// KillCode Overload Binary - License Verification & Self-Destruct
/// 
/// This binary is embedded into protected executables and performs:
/// 1. License verification via HMAC-authenticated API calls
/// 2. Machine fingerprinting
/// 3. Secure self-deletion on unauthorized access
/// 4. Sync/Async execution modes

// Module declarations
mod config;
mod verification;
mod execution;
mod security;
mod utils;

use std::process::exit;
use config::{load_config, ExecutionMode};
use security::secure_delete_self;

fn main() {
    // Load configuration
    let config = match load_config() {
        Ok(cfg) => cfg,
        Err(e) => {
            eprintln!("❌ Failed to load configuration: {}", e);
            if std::env::var("OVERLOAD_NO_DESTRUCT").is_err() {
                secure_delete_self();
            } else {
                exit(1);
            }
        }
    };

    // Execute based on mode
    match config.execution_mode {
        ExecutionMode::Sync => {
            execution::execute_sync(&config);
        }
        ExecutionMode::Async => {
            execution::execute_async(&config);
        }
    }
}
