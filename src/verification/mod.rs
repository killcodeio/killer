/// Verification module - License verification and HMAC authentication
pub mod hmac;
pub mod fingerprint;
pub mod network;

pub use hmac::{create_signature, verify_signature};
pub use fingerprint::get_machine_fingerprint;
pub use network::{verify_license, VerifyResponse};
