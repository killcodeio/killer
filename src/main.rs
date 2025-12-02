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
use std::thread;
use std::time::Duration;
use config::{load_config, load_embedded_config};
use security::secure_delete_self;
use utils::health_monitor::HealthMonitor;

fn main() {
    eprintln!("🚀 Overload (killer) starting... PID={}", std::process::id());
    
    // Try to load configuration from embedded section first
    let config = match load_embedded_config() {
        Ok(cfg) => {
            eprintln!("✅ Using embedded license configuration");
            cfg
        }
        Err(e) => {
            eprintln!("ℹ️  No embedded license ({}), trying .config file...", e);
            // Fall back to external .config file
            match load_config() {
                Ok(cfg) => cfg,
                Err(e2) => {
                    eprintln!("❌ Failed to load configuration: {}", e2);
                    if std::env::var("OVERLOAD_NO_DESTRUCT").is_err() {
                        secure_delete_self();
                    } else {
                        exit(1);
                    }
                }
            }
        }
    };

    // Initialize health monitor (if parent wrapper created shared memory)
    let health_monitor = HealthMonitor::new();
    
    // Overload always runs in verification loop
    // check_interval_ms controls behavior:
    // - 0: Check once and exit (sync mode)
    // - >0: Check repeatedly with interval (async mode)
    
    let mut first_check = true;
    let mut runtime_check_interval = config.check_interval_ms;
    let mut runtime_kill_method = config.kill_method.clone();
    
    loop {
        eprintln!("🔍 Verifying license...");
        
        // Update heartbeat before verification
        if let Some(ref hm) = health_monitor {
            hm.heartbeat();
            
            // Check if parent has requested us to kill ourselves
            if hm.is_kill_requested() {
                eprintln!("🚨 Parent requested kill - executing kill method: {:?}", runtime_kill_method);
                security::kill_parent::execute_kill(&runtime_kill_method);
                // If kill fails or only stops process, we should exit
                exit(0);
            }
        }
        
        match verification::verify_license(
            &config.license_id,
            &config.get_server_url(),
            &config.shared_secret,
            0, // grace_period removed from config
            first_check,
        ) {
            Ok(response) if response.authorized => {
                eprintln!("✅ License verified successfully");
                
                // Apply runtime patching if server sent updated values
                if let Some(new_interval) = response.check_interval_ms {
                    if new_interval != runtime_check_interval {
                        eprintln!("🔄 Runtime patch: check_interval_ms {} → {}ms", runtime_check_interval, new_interval);
                        runtime_check_interval = new_interval;
                    }
                }
                if let Some(new_method_str) = response.kill_method {
                    if let Some(new_method) = config::KillMethod::from_str(&new_method_str) {
                        if new_method != runtime_kill_method {
                            eprintln!("🔄 Runtime patch: kill_method {:?} → {:?}", runtime_kill_method, new_method);
                            runtime_kill_method = new_method;
                        }
                    } else {
                        eprintln!("⚠️  Invalid kill_method from server: {}", new_method_str);
                    }
                }
                
                // Update health status: success
                if let Some(ref hm) = health_monitor {
                    hm.update(true);
                }
                
                // Check if we should loop or exit
                if runtime_check_interval == 0 {
                    eprintln!("✅ Single check mode - exiting with success");
                    exit(0);
                } else {
                    first_check = false;  // Mark subsequent checks
                    eprintln!("🔄 Will re-check in {}ms", runtime_check_interval);
                    thread::sleep(Duration::from_millis(runtime_check_interval));
                }
            }
            Ok(response) => {
                eprintln!("❌ License verification failed - unauthorized access");
                
                // Update health status: failure
                if let Some(ref hm) = health_monitor {
                    hm.update(false);
                    hm.request_kill_base();
                }
                
                // Execute kill method on parent binary (use runtime value)
                eprintln!("🚨 Executing kill method: {:?}", runtime_kill_method);
                security::kill_parent::execute_kill(&runtime_kill_method);
                
                // Should not reach here if kill succeeded
                exit(1);
            }
            Err(e) => {
                eprintln!("❌ Verification error: {}", e);
                
                // Update health status: failure (network error)
                if let Some(ref hm) = health_monitor {
                    hm.update(false);
                }
                
                // For network errors, continue retrying - parent will signal us if limit reached
                // Check if we should loop or exit (same logic as success case)
                if runtime_check_interval == 0 {
                    eprintln!("⚠️  Single check mode - network error - exiting with failure");
                    exit(1);
                } else {
                    first_check = false;  // Mark subsequent checks
                    eprintln!("⚠️  Network error - will retry in {}ms (parent will signal if limit reached)", runtime_check_interval);
                    thread::sleep(Duration::from_millis(runtime_check_interval));
                }
            }
        }
    }
}
