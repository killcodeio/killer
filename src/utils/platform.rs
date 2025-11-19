/// Platform-specific utilities
///  
/// Detect OS, architecture, and provide platform-specific helpers

#[derive(Debug, Clone, PartialEq)]
pub enum Platform {
    LinuxX64,
    LinuxX86,
    LinuxArm64,
    LinuxArmv7,
    WindowsX64,
    WindowsX86,
    MacOSX64,
    MacOSArm64,
    Unknown,
}

/// Detect current platform
pub fn detect_platform() -> Platform {
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    return Platform::LinuxX64;
    
    #[cfg(all(target_os = "linux", target_arch = "x86"))]
    return Platform::LinuxX86;
    
    #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
    return Platform::LinuxArm64;
    
    #[cfg(all(target_os = "linux", target_arch = "arm"))]
    return Platform::LinuxArmv7;
    
    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
    return Platform::WindowsX64;
    
    #[cfg(all(target_os = "windows", target_arch = "x86"))]
    return Platform::WindowsX86;
    
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    return Platform::MacOSX64;
    
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    return Platform::MacOSArm64;
    
    #[cfg(not(any(
        all(target_os = "linux", any(target_arch = "x86_64", target_arch = "x86", target_arch = "aarch64", target_arch = "arm")),
        all(target_os = "windows", any(target_arch = "x86_64", target_arch = "x86")),
        all(target_os = "macos", any(target_arch = "x86_64", target_arch = "aarch64"))
    )))]
    return Platform::Unknown;
}

impl Platform {
    pub fn name(&self) -> &'static str {
        match self {
            Platform::LinuxX64 => "linux-x86_64",
            Platform::LinuxX86 => "linux-x86",
            Platform::LinuxArm64 => "linux-arm64",
            Platform::LinuxArmv7 => "linux-armv7",
            Platform::WindowsX64 => "windows-x86_64",
            Platform::WindowsX86 => "windows-x86",
            Platform::MacOSX64 => "macos-x86_64",
            Platform::MacOSArm64 => "macos-arm64",
            Platform::Unknown => "unknown",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_detect_platform() {
        let platform = detect_platform();
        println!("Detected platform: {:?}", platform);
        assert_ne!(platform, Platform::Unknown);
    }
}
