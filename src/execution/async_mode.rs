/// Asynchronous execution mode  
/// Return immediately to loader, verify license in background thread
/// Kill parent process tree if verification fails

use std::process::exit;
use std::thread;
use std::time::Duration;
use crate::verification;
use crate::config::Config;

pub fn execute_async(config: &Config) -> ! {
    eprintln!("⚡ Running in ASYNC mode: Returning to loader immediately, verifying in background...");
    
    // Get parent PID (the merged binary loader) before we exit
    let parent_pid = std::os::unix::process::parent_id();
    
    eprintln!("📍 Parent loader PID: {} (will be killed if verification fails)", parent_pid);
    
    // Clone config values for background thread
    let license_id = config.license_id.clone();
    let server_url = config.get_server_url();
    let shared_secret = config.shared_secret.clone();
    let grace_period = 0u32; // grace_period removed from config
    let kill_method = config.kill_method.clone();
    
    // Spawn daemon thread that will outlive this process
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(100));
        
        eprintln!("🔍 [Background] Starting license verification...");
        
        let verification_result = verification::verify_license(
            &license_id,
            &server_url,
            &shared_secret,
            grace_period,
            true, // first_check - async mode always treats as first check
        );
        
        match verification_result {
            Ok(response) if response.authorized => {
                eprintln!("✅ [Background] License verified. Parent and base continue running.");
                return;
            }
            Ok(_response) => {
                eprintln!("❌ [Background] License verification FAILED!");
            }
            Err(e) => {
                eprintln!("❌ [Background] Verification error: {}", e);
            }
        }
        
        eprintln!("💀 [Background] Killing parent process tree (PID: {})...", parent_pid);
        kill_process_tree(parent_pid as i32);
        
        use crate::config::KillMethod;
        match kill_method {
            KillMethod::Stop => {
                eprintln!("🛑 [Background] Stopped unauthorized process");
            }
            KillMethod::Delete | KillMethod::Shred => {
                eprintln!("🗑️  [Background] Unauthorized process killed");
            }
        }
    });
    
    eprintln!("✅ Returning control to loader → Base binary will execute (verification in background)");
    exit(0);
}

#[cfg(unix)]
fn kill_process_tree(pid: i32) {
    use nix::sys::signal::{kill, Signal};
    use nix::unistd::Pid;
    
    let target_pid = Pid::from_raw(pid);
    let pgid = Pid::from_raw(-pid);
    let _ = kill(pgid, Signal::SIGTERM);
    thread::sleep(Duration::from_secs(1));
    let _ = kill(pgid, Signal::SIGKILL);
    let _ = kill(target_pid, Signal::SIGKILL);
    
    eprintln!("💀 [Background] Process tree killed");
}
