/// Network communication for license verification
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

use super::hmac::create_signature;
use super::fingerprint::get_machine_fingerprint;

/// Verification request payload
#[derive(Serialize)]
struct VerifyRequest {
    license_id: String,
    machine_fingerprint: String,
    timestamp: i64,
}

/// Verification response from server
#[derive(Deserialize)]
pub struct VerifyResponse {
    pub authorized: bool,
    pub message: String,
    pub expires_in: Option<i64>,
    pub check_interval_ms: Option<u64>,
    pub kill_method: Option<String>,
}

/// Verify license with server
/// 
/// # Arguments
/// * `license_id` - License identifier
/// * `server_url` - Server URL
/// * `shared_secret` - HMAC shared secret
/// * `grace_period` - Grace period for offline mode (seconds)
/// * `first_check` - Whether this is the first check (startup) or interval check
/// 
/// # Returns
/// Result<VerifyResponse, String> - VerifyResponse if successful, Err on failure
pub fn verify_license(
    license_id: &str,
    server_url: &str,
    shared_secret: &str,
    grace_period: u32,
    first_check: bool,
) -> Result<VerifyResponse, String> {
    // Get current timestamp
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    // Get machine fingerprint
    let machine_fingerprint = get_machine_fingerprint();

    // Create HMAC signature
    let signature_data = format!("{}{}", license_id, timestamp);
    let signature = create_signature(&signature_data, shared_secret);

    // Build request
    let payload = VerifyRequest {
        license_id: license_id.to_string(),
        machine_fingerprint: machine_fingerprint.clone(),
        timestamp,
    };

    // Append API path to base URL
    let clean_url = server_url.trim_end_matches('/');
    let url = if clean_url.ends_with("/api/v1/verify") {
        clean_url.to_string()
    } else {
        format!("{}/api/v1/verify", clean_url)
    };

    // Make HTTP request with timeout
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .danger_accept_invalid_certs(false) // Enforce SSL verification
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {}", e))?;

    eprintln!("🌐 POST {} with signature: {}", url, signature);
    
    let response = client
        .post(&url)
        .header("Content-Type", "application/json")
        .header("X-License-ID", license_id)
        .header("X-Timestamp", timestamp.to_string())
        .header("X-Signature", signature.as_str())
        .header("X-First-Check", if first_check { "true" } else { "false" })
        .json(&payload)
        .send();
    
    // Handle network errors with grace period
    let response = match response {
        Ok(resp) => resp,
        Err(e) => {
            if grace_period > 0 {
                eprintln!("⚠️  Network error: {}. Grace period: {}s. Allowing offline access.", e, grace_period);
                // TODO: Implement grace period tracking (store last successful verification time)
                return Ok(VerifyResponse {
                    authorized: true,
                    message: "Offline access granted".to_string(),
                    expires_in: None,
                    check_interval_ms: None,
                    kill_method: None,
                }); // Allow offline access during grace period
            } else {
                return Err(format!("HTTP request failed: {}", e));
            }
        }
    };

    // Check response status
    eprintln!("📡 Response status: {}", response.status());
    
    if response.status() != 200 {
        // Print error response body
        if let Ok(text) = response.text() {
            eprintln!("❌ Server response: {}", text);
        }
        return Ok(VerifyResponse {
            authorized: false,
            message: "HTTP error".to_string(),
            expires_in: None,
            check_interval_ms: None,
            kill_method: None,
        });
    }

    // Parse response
    let verify_response: VerifyResponse = response
        .json()
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    Ok(verify_response)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_verify_request_serialization() {
        let req = VerifyRequest {
            license_id: "lic_test".to_string(),
            machine_fingerprint: "fp_test".to_string(),
            timestamp: 1234567890,
        };
        
        let json = serde_json::to_string(&req).unwrap();
        assert!(json.contains("lic_test"));
        assert!(json.contains("fp_test"));
    }
}
