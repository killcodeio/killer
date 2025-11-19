/// Configuration loader
use super::schema::Config;
use std::fs;

/// Load configuration from adjacent .config file
/// Config file should be in the same directory as the executable
/// Named: <executable>.config (e.g., "myapp.config")
pub fn load_config() -> Result<Config, String> {
    let exe_path = std::env::current_exe()
        .map_err(|e| format!("Failed to get executable path: {}", e))?;

    let config_path = format!("{}.config", exe_path.display());

    // Read config file
    let config_content = fs::read_to_string(&config_path)
        .map_err(|e| format!("Failed to read config file {}: {}", config_path, e))?;

    // Parse JSON config
    let config: Config = serde_json::from_str(&config_content)
        .map_err(|e| format!("Failed to parse config: {}", e))?;

    // Validate config
    config.validate()?;

    Ok(config)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;
    
    #[test]
    fn test_load_valid_config() {
        let json = r#"{
            "license_id": "lic_test",
            "server_url": "http://localhost:8080",
            "shared_secret": "secret123",
            "execution_mode": "sync"
        }"#;
        
        let config: Config = serde_json::from_str(json).unwrap();
        assert_eq!(config.license_id, "lic_test");
    }
    
    #[test]
    fn test_invalid_json() {
        let json = r#"{ invalid json }"#;
        let result: Result<Config, _> = serde_json::from_str(json);
        assert!(result.is_err());
    }
}
