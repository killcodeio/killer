/// Security module - Secure deletion and anti-tampering
pub mod destruct;
pub mod kill_parent;

pub use destruct::{secure_delete_self, secure_delete_file};
