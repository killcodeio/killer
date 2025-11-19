/// Configuration schema for overload binary
use serde::{Deserialize, Serialize};

/// Main configuration structure
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Config {
    /// License identifier
    pub license_id: String,
    
    /// Server URL for verification
    pub server_url: String,
    
    /// HMAC shared secret
    pub shared_secret: String,
    
    /// Interval to re-check license (milliseconds)
    /// 0 = check once and exit
    /// >0 = check repeatedly in loop with this interval
    #[serde(default)]
    pub check_interval_ms: u64,
    
    /// Enable self-destruct on unauthorized access
    #[serde(default = "default_true")]
    pub self_destruct: bool,
    
    /// Kill method for unauthorized access: "stop", "delete", or "shred"
    /// - stop: Just terminate the process (SIGTERM/SIGKILL)
    /// - delete: Terminate and delete binary (rm)
    /// - shred: Terminate and securely delete (3-pass overwrite + rm)
    #[serde(default = "default_kill_method")]
    pub kill_method: KillMethod,
    
    /// Log level: "debug", "info", "error", "none"
    #[serde(default = "default_log_level")]
    pub log_level: String,
    
    /// Path to base binary (for merged binaries)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub base_binary_path: Option<String>,
}

/// Kill method for unauthorized access
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum KillMethod {
    /// Just stop the process
    Stop,
    /// Stop and delete file (rm)
    Delete,
    /// Stop and securely delete (3-pass overwrite + rm)
    Shred,
}

impl KillMethod {
    /// Parse KillMethod from string (case-insensitive)
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "stop" => Some(KillMethod::Stop),
            "delete" => Some(KillMethod::Delete),
            "shred" => Some(KillMethod::Shred),
            _ => None,
        }
    }
}

fn default_true() -> bool {
    true
}

fn default_kill_method() -> KillMethod {
    KillMethod::Shred
}

fn default_log_level() -> String {
    "info".to_string()
}

impl Config {
    /// Get the effective server URL, prioritizing compile-time default
    pub fn get_server_url(&self) -> String {
        // If KILLER_SERVER_URL was set at compile time, use it (hardcoded into binary)
        if let Some(compile_time_url) = option_env!("KILLER_SERVER_URL") {
            if !compile_time_url.is_empty() {
                return compile_time_url.to_string();
            }
        }
        
        // Otherwise use the config value
        self.server_url.clone()
    }
    
    /// Validate configuration
    pub fn validate(&self) -> Result<(), String> {
        if self.license_id.is_empty() {
            return Err("license_id cannot be empty".to_string());
        }
        
        // Get effective server URL for validation
        let effective_url = self.get_server_url();
        
        if effective_url.is_empty() {
            return Err("server_url cannot be empty".to_string());
        }
        
        if self.shared_secret.is_empty() {
            return Err("shared_secret cannot be empty".to_string());
        }
        
        if !effective_url.starts_with("http://") && !effective_url.starts_with("https://") {
            return Err("server_url must start with http:// or https://".to_string());
        }
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_config_validation() {
        let mut config = Config {
            license_id: "test_license".to_string(),
            server_url: "http://localhost:8080".to_string(),
            shared_secret: "secret123".to_string(),
            check_interval_ms: 0,
            self_destruct: true,
            log_level: "info".to_string(),
        };
        
        assert!(config.validate().is_ok());
        
        config.license_id = "".to_string();
        assert!(config.validate().is_err());
    }
    
    #[test]
    fn test_default_values() {
        let json = r#"{
            "license_id": "lic_123",
            "server_url": "http://localhost:8080",
            "shared_secret": "secret"
        }"#;
        
        let config: Config = serde_json::from_str(json).unwrap();
        assert_eq!(config.check_interval_ms, 0);
        assert_eq!(config.self_destruct, true);
        assert_eq!(config.log_level, "info");
    }
}
