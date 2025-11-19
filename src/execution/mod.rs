/// Execution module - Handle sync and async execution modes
pub mod sync;
pub mod async_mode;

// Re-export for convenience
pub use sync::execute_sync;
pub use async_mode::execute_async;
