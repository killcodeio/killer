/// Synchronous execution mode
/// Verify license FIRST, then execute base binary only if authorized

use std::process::{Command, exit};
use crate::verification;
use crate::config::Config;
use crate::security::secure_delete_self;

/// Execute in synchronous mode
/// 
/// Flow:
/// 1. Verify license with server
/// 2. If authorized → exit(0) to signal loader to continue to base
/// 3. If unauthorized → exit(1) to signal loader to abort
/// 
/// NOTE: Overload runs as FIRST binary in merged executable.
/// The merged binary's loader will check our exit code:
///   - exit(0) → loader continues to execute base binary
///   - exit(1) → loader aborts, base never runs
pub fn execute_sync(config: &Config) -> ! {
    eprintln!("🔄 Running in SYNC mode: Verifying license before execution...");
    
    // Verify license (grace_period removed from config, pass 0)
    match verification::verify_license(
        &config.license_id,
        &config.get_server_url(),
        &config.shared_secret,
        0, // grace_period removed from config
        true, // first_check - sync mode always treats as first check
    ) {
        Ok(response) if response.authorized => {
            eprintln!("✅ License verified successfully");
            eprintln!("✅ Returning control to loader → Base binary will execute");
            exit(0); // Signal success to loader
        }
        Ok(_response) => {
            eprintln!("❌ License verification failed");
            eprintln!("❌ Signaling loader to abort → Base binary will NOT execute");
            if config.self_destruct {
                secure_delete_self();
            } else {
                exit(1);
            }
        }
        Err(e) => {
            eprintln!("❌ Verification error: {}", e);
            eprintln!("❌ Signaling loader to abort → Base binary will NOT execute");
            if config.self_destruct {
                secure_delete_self();
            } else {
                exit(1);
            }
        }
    }
}

/// Chain execution to base binary
/// This replaces the current process with the base binary
#[cfg(unix)]
fn chain_to_base(base_path: &str) -> ! {
    use std::os::unix::process::CommandExt;
    
    eprintln!("🚀 Executing base binary...");
    
    let error = Command::new(base_path)
        .args(std::env::args().skip(1)) // Forward arguments
        .exec(); // Replace current process
    
    // If exec returns, it failed
    eprintln!("❌ Failed to exec base binary: {}", error);
    exit(1);
}

/// Chain execution to base binary (Windows version)
/// Windows doesn't have exec(), so we spawn and exit
#[cfg(windows)]
fn chain_to_base(base_path: &str) -> ! {
    eprintln!("🚀 Executing base binary...");
    
    let status = Command::new(base_path)
        .args(std::env::args().skip(1)) // Forward arguments
        .status();
    
    match status {
        Ok(exit_status) => {
            exit(exit_status.code().unwrap_or(1));
        }
        Err(e) => {
            eprintln!("❌ Failed to execute base binary: {}", e);
            exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_chain_to_base_validation() {
        // This test just ensures the function compiles
        // Actual execution testing requires integration tests
    }
}
