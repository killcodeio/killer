/// Build script to load environment variables from .env file
/// This allows compile-time injection of server URL

fn main() {
    // Load .env file from project root if it exists
    // This is relative to the killer directory
    if let Ok(path) = std::env::var("CARGO_MANIFEST_DIR") {
        let env_path = std::path::Path::new(&path).parent().unwrap().join(".env");
        if env_path.exists() {
            println!("cargo:rerun-if-changed={}", env_path.display());
            
            // Read .env file manually (avoid extra dependencies in build script)
            if let Ok(contents) = std::fs::read_to_string(&env_path) {
                for line in contents.lines() {
                    let line = line.trim();
                    
                    // Skip comments and empty lines
                    if line.is_empty() || line.starts_with('#') {
                        continue;
                    }
                    
                    // Parse KEY=VALUE format
                    if let Some((key, value)) = line.split_once('=') {
                        let key = key.trim();
                        let value = value.trim().trim_matches('"').trim_matches('\'');
                        
                        // Pass KILLER_SERVER_URL to rustc if present
                        if key == "KILLER_SERVER_URL" {
                            println!("cargo:rustc-env={}={}", key, value);
                            eprintln!("🔧 Building with server URL: {}", value);
                        }
                    }
                }
            }
        }
    }
}
