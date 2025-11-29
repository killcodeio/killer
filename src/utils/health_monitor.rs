/// Shared memory health status communication with parent wrapper
use std::env;
use std::ffi::CString;
use std::ptr;
use std::time::{SystemTime, UNIX_EPOCH};

#[repr(C)]
struct HealthStatus {
    last_success: i64,          // Timestamp of last successful check
    consecutive_failures: i32,   // Counter of network failures
    is_alive: i32,               // Heartbeat flag (1=alive, 0=dead)
    should_kill_base: i32,       // Signal to kill base (1=kill, 0=continue)
    parent_requests_kill: i32,   // Signal from parent: kill yourself now (1=kill, 0=continue)
}

pub struct HealthMonitor {
    shm_ptr: *mut HealthStatus,
}

impl HealthMonitor {
    /// Open shared memory if KILLCODE_HEALTH_SHM env var is set
    pub fn new() -> Option<Self> {
        let shm_name = env::var("KILLCODE_HEALTH_SHM").ok()?;
        
        eprintln!("📊 Opening health monitor: {}", shm_name);
        
        #[cfg(unix)]
        unsafe {
            let name_cstr = CString::new(shm_name).ok()?;
            
            // Open existing shared memory (created by parent)
            let shm_fd = libc::shm_open(
                name_cstr.as_ptr(),
                libc::O_RDWR,
                0o600,
            );
            
            if shm_fd < 0 {
                eprintln!("⚠️  Failed to open shared memory: {}", std::io::Error::last_os_error());
                return None;
            }
            
            // Map shared memory
            let shm_ptr = libc::mmap(
                ptr::null_mut(),
                std::mem::size_of::<HealthStatus>(),
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                shm_fd,
                0,
            );
            
            libc::close(shm_fd);
            
            if shm_ptr == libc::MAP_FAILED {
                eprintln!("⚠️  Failed to map shared memory: {}", std::io::Error::last_os_error());
                return None;
            }
            
            eprintln!("✅ Health monitor initialized");
            
            Some(Self {
                shm_ptr: shm_ptr as *mut HealthStatus,
            })
        }

        #[cfg(windows)]
        unsafe {
            use winapi::um::memoryapi::{MapViewOfFile, FILE_MAP_ALL_ACCESS};
            use winapi::um::handleapi::CloseHandle;
            use winapi::um::winbase::OpenFileMappingA;

            let name_cstr = CString::new(shm_name).ok()?;
            
            let handle = OpenFileMappingA(
                FILE_MAP_ALL_ACCESS,
                0,
                name_cstr.as_ptr(),
            );

            if handle.is_null() {
                 eprintln!("⚠️  Failed to open shared memory: {}", std::io::Error::last_os_error());
                 return None;
            }

            let shm_ptr = MapViewOfFile(
                handle,
                FILE_MAP_ALL_ACCESS,
                0,
                0,
                std::mem::size_of::<HealthStatus>(),
            );

            CloseHandle(handle); // We can close the handle after mapping

            if shm_ptr.is_null() {
                 eprintln!("⚠️  Failed to map shared memory: {}", std::io::Error::last_os_error());
                 return None;
            }

            eprintln!("✅ Health monitor initialized");

            Some(Self {
                shm_ptr: shm_ptr as *mut HealthStatus,
            })
        }
    }
    
    /// Update health status after verification attempt
    pub fn update(&self, success: bool) {
        unsafe {
            if self.shm_ptr.is_null() {
                return;
            }
            
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64;
            
            if success {
                (*self.shm_ptr).consecutive_failures = 0;
                (*self.shm_ptr).last_success = now;
                eprintln!("✅ Health update: verification successful");
            } else {
                (*self.shm_ptr).consecutive_failures += 1;
                eprintln!("⚠️  Health update: verification failed (consecutive: {})", 
                         (*self.shm_ptr).consecutive_failures);
            }
            
            // Update heartbeat
            (*self.shm_ptr).is_alive = 1;
        }
    }
    
    /// Signal parent to kill base binary
    pub fn request_kill_base(&self) {
        unsafe {
            if !self.shm_ptr.is_null() {
                (*self.shm_ptr).should_kill_base = 1;
                eprintln!("🚨 Signaled parent to kill base binary");
            }
        }
    }
    
    /// Update heartbeat to show we're still alive
    pub fn heartbeat(&self) {
        unsafe {
            if !self.shm_ptr.is_null() {
                (*self.shm_ptr).is_alive = 1;
            }
        }
    }
    
    /// Check if parent has requested us to kill ourselves
    pub fn is_kill_requested(&self) -> bool {
        unsafe {
            if self.shm_ptr.is_null() {
                return false;
            }
            (*self.shm_ptr).parent_requests_kill == 1
        }
    }
}

impl Drop for HealthMonitor {
    fn drop(&mut self) {
        unsafe {
            if !self.shm_ptr.is_null() {
                #[cfg(unix)]
                libc::munmap(
                    self.shm_ptr as *mut libc::c_void,
                    std::mem::size_of::<HealthStatus>(),
                );

                #[cfg(windows)]
                winapi::um::memoryapi::UnmapViewOfFile(self.shm_ptr as *const _);
            }
        }
    }
}
