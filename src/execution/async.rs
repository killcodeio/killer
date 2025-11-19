/// Asynchronous execution mode
/// Start base binary IMMEDIATELY, verify license in parallel
/// Kill base if verification fails

use std::process::{Command, Child, exit};
use std::thread;
use std::time::Duration;
use crate::verification;
use crate::config::Config;
use crate::security::secure_delete_self;

/// Execute in asynchronous mode
/// 
/// Flow:
/// 1. Fork and start base binary immediately
/// 2. Verify license in parallel
/// 3. If authorized → let base continue
/// 4. If unauthorized → kill base process + self-destruct
pub fn execute_async(config: &Config) -> ! {
    eprintln!("⚡ Running in ASYNC mode: Starting base binary while verifying...");
    
    let base_path = match &config.base_binary_path {
        Some(path) => path.clone(),
        None => {
            eprintln!("❌ ASYNC mode requires base_binary_path in config");
            exit(1);
        }
    };
    
    // Start base binary in background
    let mut base_process = match spawn_base(&base_path) {
        Ok(child) => child,
        Err(e) => {
            eprintln!("❌ Failed to spawn base binary: {}", e);
            exit(1);
        }
    };
    
    eprintln!("🚀 Base binary started (PID: {})", base_process.id());
    
    // Verify license in parallel
    let license_id = config.license_id.clone();
    let server_url = config.get_server_url();
    let shared_secret = config.shared_secret.clone();
    let grace_period = 0u32; // grace_period removed from config
    let self_destruct = config.self_destruct;
    
    let verification_handle = thread::spawn(move || {
        verification::verify_license(
            &license_id,
            &server_url,
            &shared_secret,
            grace_period,
            true, // first_check
        )
    });
    
    // Wait for verification (with timeout)
    let verification_timeout = Duration::from_secs(30);
    let start = std::time::Instant::now();
    
    loop {
        // Check if verification completed
        if verification_handle.is_finished() {
            match verification_handle.join() {
                Ok(Ok(response)) if response.authorized => {
                    eprintln!("✅ License verified. Base binary continues running.");
                    // Wait for base to complete
                    let status = base_process.wait().expect("Failed to wait for base");
                    exit(status.code().unwrap_or(0));
                }
                Ok(Ok(_response)) | Ok(Err(_)) | Err(_) => {
                    eprintln!("❌ License verification failed. Terminating base binary...");
                    kill_base(&mut base_process);
                    
                    if self_destruct {
                        secure_delete_self();
                    } else {
                        exit(1);
                    }
                }
            }
        }
        
        // Check if verification timed out
        if start.elapsed() > verification_timeout {
            eprintln!("⏱️  Verification timeout. Terminating base binary...");
            kill_base(&mut base_process);
            
            if self_destruct {
                secure_delete_self();
            } else {
                exit(1);
            }
        }
        
        // Check if base process died
        match base_process.try_wait() {
            Ok(Some(status)) => {
                eprintln!("⚠️  Base binary exited early with status: {}", status);
                exit(status.code().unwrap_or(1));
            }
            Ok(None) => {
                // Still running, continue waiting
                thread::sleep(Duration::from_millis(100));
            }
            Err(e) => {
                eprintln!("❌ Error waiting for base: {}", e);
                exit(1);
            }
        }
    }
}

/// Spawn base binary as child process
fn spawn_base(base_path: &str) -> Result<Child, std::io::Error> {
    Command::new(base_path)
        .args(std::env::args().skip(1)) // Forward arguments
        .spawn()
}

/// Kill base process and any children
fn kill_base(child: &mut Child) {
    eprintln!("🔪 Killing base process (PID: {})...", child.id());
    
    #[cfg(unix)]
    {
        use nix::sys::signal::{kill, Signal};
        use nix::unistd::Pid;
        
        let pid = Pid::from_raw(child.id() as i32);
        
        // Try SIGTERM first (graceful)
        if kill(pid, Signal::SIGTERM).is_ok() {
            thread::sleep(Duration::from_secs(2));
        }
        
        // Force kill with SIGKILL
        let _ = kill(pid, Signal::SIGKILL);
    }
    
    #[cfg(windows)]
    {
        let _ = child.kill();
    }
    
    let _ = child.wait();
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_spawn_base_error_handling() {
        let result = spawn_base("/nonexistent/binary");
        assert!(result.is_err());
    }
}
