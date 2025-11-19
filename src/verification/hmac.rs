/// HMAC-SHA256 signature generation and validation
use hmac::{Hmac, Mac};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

/// Create HMAC-SHA256 signature
/// 
/// # Arguments
/// * `data` - Data to sign (typically license_id + timestamp)
/// * `secret` - Shared secret key
/// 
/// # Returns
/// Hex-encoded HMAC signature
pub fn create_signature(data: &str, secret: &str) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .expect("HMAC can take key of any size");
    mac.update(data.as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

/// Verify HMAC signature
///
/// # Arguments
/// * `data` - Original data that was signed
/// * `secret` - Shared secret key
/// * `signature` - Signature to verify (hex-encoded)
///
/// # Returns
/// true if signature is valid
pub fn verify_signature(data: &str, secret: &str, signature: &str) -> bool {
    let expected = create_signature(data, secret);
    
    // Use constant-time comparison to prevent timing attacks
    use subtle::ConstantTimeEq;
    expected.as_bytes().ct_eq(signature.as_bytes()).into()
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_create_signature() {
        let data = "lic_12345" + "1234567890";
        let secret = "my_secret_key";
        
        let sig1 = create_signature(&data, secret);
        let sig2 = create_signature(&data, secret);
        
        // Same input should produce same signature
        assert_eq!(sig1, sig2);
        
        // Signature should be hex string
        assert!(sig1.chars().all(|c| c.is_ascii_hexdigit()));
    }
    
    #[test]
    fn test_verify_signature() {
        let data = "test_data";
        let secret = "test_secret";
        
        let signature = create_signature(data, secret);
        assert!(verify_signature(data, secret, &signature));
        
        // Wrong secret should fail
        assert!(!verify_signature(data, "wrong_secret", &signature));
        
        // Wrong data should fail
        assert!(!verify_signature("wrong_data", secret, &signature));
        
        // Tampered signature should fail
        let mut tampered = signature.clone();
        tampered.push('0');
        assert!(!verify_signature(data, secret, &tampered));
    }
}
