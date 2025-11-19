/// Configuration module - Load and validate overload configuration
pub mod schema;
pub mod loader;
pub mod embedded;

pub use schema::{Config, KillMethod};
pub use loader::load_config;
pub use embedded::load_embedded_config;
