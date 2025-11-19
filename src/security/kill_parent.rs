/// Kill parent binary according to configured method
use std::fs;
use std::io::{Write, Seek, SeekFrom};
use std::path::PathBuf;
use std::process::exit;
use crate::config::KillMethod;

// Platform-specific imports
#[cfg(unix)]
use std::os::unix::process::parent_id;

#[cfg(windows)]
use std::os::windows::process::CommandExt;

/// Get parent process ID (cross-platform)
fn get_parent_pid() -> Option<u32> {
    #[cfg(unix)]
    {
        Some(parent_id())
    }
    
    #[cfg(windows)]
    {
        // Windows: use winapi to get parent PID
        use std::mem;
        use std::ptr;
        
        unsafe {
            let snapshot = winapi::um::tlhelp32::CreateToolhelp32Snapshot(
                winapi::um::tlhelp32::TH32CS_SNAPPROCESS,
                0,
            );
            
            if snapshot == winapi::um::handleapi::INVALID_HANDLE_VALUE {
                return None;
            }
            
            let mut entry: winapi::um::tlhelp32::PROCESSENTRY32W = mem::zeroed();
            entry.dwSize = mem::size_of::<winapi::um::tlhelp32::PROCESSENTRY32W>() as u32;
            
            let current_pid = winapi::um::processthreadsapi::GetCurrentProcessId();
            let mut parent_pid = None;
            
            if winapi::um::tlhelp32::Process32FirstW(snapshot, &mut entry) != 0 {
                loop {
                    if entry.th32ProcessID == current_pid {
                        parent_pid = Some(entry.th32ParentProcessID);
                        break;
                    }
                    if winapi::um::tlhelp32::Process32NextW(snapshot, &mut entry) == 0 {
                        break;
                    }
                }
            }
            
            winapi::um::handleapi::CloseHandle(snapshot);
            parent_pid
        }
    }
}

/// Get parent binary path from PID (cross-platform)
fn get_parent_binary_path(ppid: u32) -> Option<PathBuf> {
    #[cfg(target_os = "linux")]
    {
        fs::read_link(format!("/proc/{}/exe", ppid)).ok()
    }
    
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        let output = Command::new("ps")
            .args(&["-p", &ppid.to_string(), "-o", "comm="])
            .output()
            .ok()?;
        String::from_utf8(output.stdout)
            .ok()
            .map(|s| PathBuf::from(s.trim()))
    }
    
    #[cfg(windows)]
    {
        use std::mem;
        use std::ptr;
        
        unsafe {
            let handle = winapi::um::processthreadsapi::OpenProcess(
                winapi::um::winnt::PROCESS_QUERY_INFORMATION | winapi::um::winnt::PROCESS_VM_READ,
                0,
                ppid,
            );
            
            if handle.is_null() {
                return None;
            }
            
            let mut path_buf = vec![0u16; 4096];
            let mut size = path_buf.len() as u32;
            
            let result = winapi::um::psapi::GetModuleFileNameExW(
                handle,
                ptr::null_mut(),
                path_buf.as_mut_ptr(),
                size,
            );
            
            winapi::um::handleapi::CloseHandle(handle);
            
            if result > 0 {
                let path = String::from_utf16_lossy(&path_buf[..result as usize]);
                Some(PathBuf::from(path))
            } else {
                None
            }
        }
    }
}

/// Stop parent process (cross-platform)
fn stop_parent(ppid: u32) -> Result<(), String> {
    eprintln!("🛑 Stopping parent process PID {}...", ppid);
    
    #[cfg(unix)]
    {
        // Unix: Use signals
        unsafe {
            libc::kill(ppid as i32, libc::SIGTERM);
        }
        
        std::thread::sleep(std::time::Duration::from_millis(100));
        
        // Check if still alive
        if std::path::Path::new(&format!("/proc/{}", ppid)).exists() {
            eprintln!("⚠️  Process still alive, sending SIGKILL...");
            unsafe {
                libc::kill(ppid as i32, libc::SIGKILL);
            }
        }
    }
    
    #[cfg(windows)]
    {
        // Windows: Use TerminateProcess
        unsafe {
            let handle = winapi::um::processthreadsapi::OpenProcess(
                winapi::um::winnt::PROCESS_TERMINATE,
                0,
                ppid,
            );
            
            if handle.is_null() {
                return Err(format!("Failed to open process {}", ppid));
            }
            
            let result = winapi::um::processthreadsapi::TerminateProcess(handle, 1);
            winapi::um::handleapi::CloseHandle(handle);
            
            if result == 0 {
                return Err("Failed to terminate process".to_string());
            }
        }
    }
    
    eprintln!("✅ Parent process stopped");
    Ok(())
}

/// Delete parent binary file (cross-platform)
fn delete_parent(ppid: u32, path: &PathBuf) -> Result<(), String> {
    // First stop the process
    stop_parent(ppid)?;
    
    // Wait for process to fully terminate
    std::thread::sleep(std::time::Duration::from_millis(200));
    
    // Delete the file
    eprintln!("🗑️  Deleting parent binary: {}", path.display());
    fs::remove_file(path)
        .map_err(|e| format!("Failed to delete parent binary: {}", e))?;
    
    eprintln!("✅ Parent binary deleted");
    Ok(())
}

/// Shred parent binary (3-pass overwrite + delete, cross-platform)
fn shred_parent(ppid: u32, path: &PathBuf) -> Result<(), String> {
    // First stop the process
    stop_parent(ppid)?;
    
    // Wait for process to fully terminate
    std::thread::sleep(std::time::Duration::from_millis(200));
    
    eprintln!("🔥 Shredding parent binary: {}", path.display());
    
    // Open file for overwriting
    let mut file = fs::OpenOptions::new()
        .write(true)
        .open(path)
        .map_err(|e| format!("Failed to open parent binary for shredding: {}", e))?;
    
    // Get file size
    let metadata = file.metadata()
        .map_err(|e| format!("Failed to get file metadata: {}", e))?;
    let file_size = metadata.len() as usize;
    
    eprintln!("📏 File size: {} bytes, starting 3-pass overwrite...", file_size);
    
    // 3-pass overwrite
    let patterns: [u8; 3] = [0x00, 0xFF, 0xAA];
    
    for (pass, pattern) in patterns.iter().enumerate() {
        eprintln!("🔄 Pass {}/3: Writing 0x{:02X}...", pass + 1, pattern);
        
        file.seek(SeekFrom::Start(0))
            .map_err(|e| format!("Failed to seek: {}", e))?;
        
        let buffer = vec![*pattern; 8192];
        let mut remaining = file_size;
        
        while remaining > 0 {
            let write_size = remaining.min(buffer.len());
            file.write_all(&buffer[..write_size])
                .map_err(|e| format!("Failed to write during shred: {}", e))?;
            remaining -= write_size;
        }
        
        file.sync_all()
            .map_err(|e| format!("Failed to sync: {}", e))?;
    }
    
    drop(file);
    
    // Finally delete the file
    eprintln!("🗑️  Deleting shredded file...");
    fs::remove_file(path)
        .map_err(|e| format!("Failed to delete shredded file: {}", e))?;
    
    eprintln!("✅ Parent binary securely shredded and deleted");
    Ok(())
}

/// Execute kill method based on config
pub fn execute_kill(kill_method: &KillMethod) {
    eprintln!("🚨 Executing kill method: {:?}", kill_method);
    
    // Get parent PID
    let ppid = match get_parent_pid() {
        Some(pid) => pid,
        None => {
            eprintln!("❌ Failed to get parent PID");
            exit(1);
        }
    };
    
    eprintln!("📍 Parent PID: {}", ppid);
    
    // Get parent binary path
    let path = match get_parent_binary_path(ppid) {
        Some(p) => p,
        None => {
            eprintln!("❌ Failed to get parent binary path");
            // Still try to stop the process
            if let Err(e) = stop_parent(ppid) {
                eprintln!("❌ Failed to stop parent: {}", e);
            }
            exit(1);
        }
    };
    
    eprintln!("📂 Parent binary: {}", path.display());
    
    // Execute kill method
    let result = match kill_method {
        KillMethod::Stop => stop_parent(ppid),
        KillMethod::Delete => delete_parent(ppid, &path),
        KillMethod::Shred => shred_parent(ppid, &path),
    };
    
    if let Err(e) = result {
        eprintln!("❌ Kill execution failed: {}", e);
        exit(1);
    }
    
    eprintln!("✅ Kill method executed successfully");
}
