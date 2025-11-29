/// Embedded configuration - reads from binary's .license section
use super::schema::Config;

/// Read configuration from embedded .license section
/// The license data is injected into the binary by the server
/// at a fixed offset in the .license section
pub fn load_embedded_config() -> Result<Config, String> {
    // The .license section is embedded in the binary at compile time
    // The server patches it with actual license data
    // 
    // #[used] ensures this static is kept in the output even if unused
    // #[link_section] places it in a named .license section
    #[used]
    #[unsafe(link_section = ".license")]
    static LICENSE_DATA: [u8; 4096] = [0; 4096];
    
    // Try to read from the static first (works when binary runs directly)
    let config_bytes = &LICENSE_DATA;
    let config_len = config_bytes.iter()
        .position(|&b| b == 0)
        .unwrap_or(config_bytes.len());
    
    // If static has data, use it
    if config_len > 0 {
        let config_str = std::str::from_utf8(&config_bytes[..config_len])
            .map_err(|e| format!("Invalid UTF-8 in embedded license data: {}", e))?;
        
        let config: Config = serde_json::from_str(config_str)
            .map_err(|e| format!("Failed to parse embedded config: {}", e))?;
        
        config.validate()?;
        return Ok(config);
    }
    
    // If static is empty, try reading from our own executable file
    // This handles the case where we're running from memfd after extraction
    // Read from current executable path (cross-platform)
    let current_exe = std::env::current_exe()
        .map_err(|e| format!("Failed to get current executable path: {}", e))?;
        
    let exe_data = std::fs::read(&current_exe)
        .map_err(|e| format!("Failed to read executable from {}: {}", current_exe.display(), e))?;
    
    // Search for .license section in ELF
    // Simple search: find 4KB block with JSON data
    const LICENSE_SIZE: usize = 4096;
    for offset in (0..exe_data.len().saturating_sub(LICENSE_SIZE)).step_by(4) {
        let slice = &exe_data[offset..offset + LICENSE_SIZE];
        
        // Check if this looks like our license section (starts with '{')
        if slice[0] == b'{' {
            let json_len = slice.iter().position(|&b| b == 0).unwrap_or(LICENSE_SIZE);
            if json_len > 10 {  // Minimum viable JSON
                if let Ok(config_str) = std::str::from_utf8(&slice[..json_len]) {
                    if let Ok(config) = serde_json::from_str::<Config>(config_str) {
                        if config.validate().is_ok() {
                            eprintln!("✅ Found license at offset 0x{:x} in executable", offset);
                            return Ok(config);
                        }
                    }
                }
            }
        }
    }
    
    Err("No license data embedded in binary. This binary has not been patched by the server.".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_embedded_config_format() {
        // Test that we can parse a valid JSON config
        let json = r#"{
            "license_id": "lic_test",
            "server_url": "http://localhost:8080/api/v1/verify",
            "shared_secret": "secret123",
            "check_interval_ms": 5000,
            "self_destruct": true,
            "log_level": "info"
        }"#;
        
        let config: Config = serde_json::from_str(json).unwrap();
        assert_eq!(config.license_id, "lic_test");
        assert_eq!(config.check_interval_ms, 5000);
    }
}
