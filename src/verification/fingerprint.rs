/// Machine fingerprinting for license verification
use sha2::{Digest, Sha256};
use std::fs;

/// Generate machine fingerprint
/// 
/// Creates a unique identifier for the machine based on:
/// - Hostname
/// - MAC address of first network interface
/// 
/// # Returns
/// SHA256 hash of the combined identifiers
pub fn get_machine_fingerprint() -> String {
    // Get hostname
    let hostname = hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .unwrap_or_else(|| "unknown".to_string());

    // Get MAC address (simplified - in production use more robust method)
    let mac = get_mac_address().unwrap_or_else(|| "00:00:00:00:00:00".to_string());

    // Hash the combination
    let data = format!("{}-{}", hostname, mac);
    let mut hasher = Sha256::new();
    hasher.update(data.as_bytes());
    hex::encode(hasher.finalize())
}

/// Get MAC address of first network interface
/// 
/// # Returns
/// MAC address string or None if not found
fn get_mac_address() -> Option<String> {
    // Try to read from /sys/class/net (Linux)
    #[cfg(target_os = "linux")]
    {
        if let Ok(entries) = fs::read_dir("/sys/class/net") {
            for entry in entries.flatten() {
                let iface_name = entry.file_name();
                let iface_str = iface_name.to_string_lossy();
                
                // Skip loopback
                if iface_str == "lo" {
                    continue;
                }

                let addr_path = format!("/sys/class/net/{}/address", iface_str);
                if let Ok(addr) = fs::read_to_string(&addr_path) {
                    return Some(addr.trim().to_string());
                }
            }
        }
    }
    
    // Fallback for non-Linux platforms
    #[cfg(not(target_os = "linux"))]
    {
        // TODO: Add Windows and macOS support
        // For now, return None for these platforms
    }
    
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_fingerprint_format() {
        let fp = get_machine_fingerprint();
        
        // Should be a hex string
        assert!(fp.chars().all(|c| c.is_ascii_hexdigit()));
        
        // Should be 64 characters (SHA256 hex)
        assert_eq!(fp.len(), 64);
        
        // Should be consistent
        let fp2 = get_machine_fingerprint();
        assert_eq!(fp, fp2);
    }
}
