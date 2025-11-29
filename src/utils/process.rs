/// Process utilities

#[cfg(unix)]
use std::os::unix::process::parent_id;

/// Get parent process ID (cross-platform)
pub fn get_parent_pid() -> Option<u32> {
    #[cfg(unix)]
    {
        Some(parent_id())
    }
    
    #[cfg(windows)]
    {
        // Windows: use winapi to get parent PID
        use std::mem;
        use winapi::um::handleapi::{CloseHandle, INVALID_HANDLE_VALUE};
        use winapi::um::tlhelp32::{
            CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
        };
        use winapi::um::processthreadsapi::GetCurrentProcessId;
        
        unsafe {
            let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            
            if snapshot == INVALID_HANDLE_VALUE {
                return None;
            }
            
            let mut entry: PROCESSENTRY32W = mem::zeroed();
            entry.dwSize = mem::size_of::<PROCESSENTRY32W>() as u32;
            
            let current_pid = GetCurrentProcessId();
            let mut parent_pid = None;
            
            if Process32FirstW(snapshot, &mut entry) != 0 {
                loop {
                    if entry.th32ProcessID == current_pid {
                        parent_pid = Some(entry.th32ParentProcessID);
                        break;
                    }
                    if Process32NextW(snapshot, &mut entry) == 0 {
                        break;
                    }
                }
            }
            
            CloseHandle(snapshot);
            parent_pid
        }
    }
}
