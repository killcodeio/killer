# Killer - License Verification Binary

Binary protection system that verifies license validity before allowing execution of protected binaries.

## Overview

Killer is a Rust-based license verification binary that can be merged with any customer binary to enforce license checking. It supports multiple execution modes and architectures.

## Features

### Multi-Architecture Support
Built for 6 platforms out of the box:
- **Linux**: x86_64, x86 (32-bit), ARM64, ARMv7
- **Windows**: x86_64, x86 (32-bit)
- **macOS**: Not yet tested (requires OSXCross/MacOs)

### Execution Modes
- **SYNC Mode**: Verify license BEFORE running base binary
- **ASYNC Mode**: Run base binary FIRST, verify in background, kill if unauthorized

### Security Features
- HMAC-authenticated API calls
- Machine fingerprinting (CPU, RAM, MAC address)
- Self-destruct on unauthorized access
- Embedded license configuration (no external config files needed)
- Anti-debugging protection

### License Configuration
- Embedded directly in binary (`.license` ELF section)
- No separate config files to distribute
- 4096-byte reserved space for JSON license data
- Server-side patching support

## Quick Start

### Building All Platforms (Docker - Recommended)

Build killer binaries for all supported architectures using Docker:

```bash
cd killer
./scripts/build/docker/build-all-platforms.sh
```

Output binaries will be in versioned directories `./builds/<version>/`:
```
builds/
└── 1.0.0/
    ├── linux-x86_64/overload
    ├── linux-x86/overload
    ├── linux-arm64/overload
    ├── linux-armv7/overload
    ├── windows-x86_64/overload.exe
    └── windows-x86/overload.exe
```

**Version Detection:**
- Version is automatically extracted from `Cargo.toml`
- If version already exists in `builds/`, build is skipped
- To rebuild: `rm -rf builds/<version>`

### Building Single Platform (Docker)

Build for a specific platform only (faster for testing):

```bash
./scripts/build/docker/build-single-platform.sh linux-x86_64
./scripts/build/docker/build-single-platform.sh windows-x86_64
./scripts/build/docker/build-single-platform.sh linux-arm64
```

### Building on Host Machine (Development)

For faster iteration during development, build directly on your machine:

```bash
# 1. Check dependencies first
./scripts/build/host/check-deps.sh

# 2. Install any missing dependencies (script will show commands)

# 3. Build single platform
./scripts/build/host/build-single-platform.sh linux-x86_64

# Or build all platforms
./scripts/build/host/build-all-platforms.sh
```

**Note:** Host builds require cross-compilation toolchains installed. See `scripts/README.md` for details.

### Development Build (Host Machine)

For quick testing on your local machine:

```bash
cargo build --release
```

## Configuration

### Embedded License (Production)

License configuration is embedded directly in the binary:

```rust
#[link_section = ".license"]
static LICENSE_DATA: [u8; 4096] = [0; 4096];
```

The server patches license JSON into this section before distribution.

### Config File (Development/Testing)

For testing, you can use a `.config` file:

```json
{
  "license_id": "test-license-123",
  "server_url": "http://localhost:3000",
  "shared_secret": "your-secret-key",
  "mode": "sync",
  "sync": true,
  "self_destruct": false,
  "grace_period": 86400,
  "base_binary_path": "/path/to/base/binary"
}
```

## Execution Modes

### SYNC Mode (Recommended)
Verifies license BEFORE executing base binary:
1. Check license with server
2. If authorized → execute base binary
3. If unauthorized → self-destruct

```bash
# Set in config
"mode": "sync"
"sync": true
```

### ASYNC Mode
Executes base binary immediately, verifies in background:
1. Launch base binary first
2. Verify license in parallel
3. If unauthorized → kill base binary
4. Self-destruct if configured

```bash
# Set in config
"mode": "async"
"sync": false
```

## Build Requirements

### Host System
- Linux (tested on Ubuntu/Debian)
- Docker with BuildKit support
- 2GB+ disk space for Docker image

### Docker Environment
All cross-compilation tools are included in Docker:
- Rust 1.91
- GCC toolchains (x86, ARM, ARM64, MinGW)
- Cross-compilation libraries
- BuildKit cache optimizations

### First Build
- Takes ~2-3 minutes (downloads dependencies)
- Subsequent builds: ~10-30 seconds (cached)

## Architecture Details

### Cross-Compilation
Uses Docker with pre-installed toolchains:
- `x86_64-linux-gnu-gcc` - Linux 64-bit
- `i686-linux-gnu-gcc` - Linux 32-bit
- `aarch64-linux-gnu-gcc` - Linux ARM64
- `arm-linux-gnueabihf-gcc` - Linux ARMv7
- `x86_64-w64-mingw32-gcc` - Windows 64-bit
- `i686-w64-mingw32-gcc` - Windows 32-bit

### Binary Sizes
Optimized with:
```toml
[profile.release]
strip = true
opt-level = "z"
lto = true
codegen-units = 1
panic = "abort"
```

Typical sizes:
- Linux x86_64: ~2.3 MB
- Linux ARM64: ~2.1 MB
- Windows x86_64: ~2.1 MB

## Testing

### Unit Tests
```bash
cargo test
```

### Integration Tests
```bash
# Build and test ASYNC mode
./tests/test_async_mode.sh
```

### Manual Testing
```bash
# Build for local machine
cargo build --release

# Create test config
cat > .config << EOF
{
  "license_id": "test-123",
  "server_url": "http://localhost:3000",
  "shared_secret": "test-secret",
  "mode": "sync",
  "sync": true,
  "self_destruct": false,
  "grace_period": 86400
}
EOF

# Run
./target/release/killer
```

## Deployment

### Docker Volume Mounting

The killer builds are automatically made available to the server via Docker volume mounting:

```yaml
# docker-compose.yml
server:
  volumes:
    - ./killer/builds:/app/overload_bins:ro  # Read-only mount
```

**Directory Structure in Server:**
```
/app/overload_bins/
└── 1.0.0/                    # Version from Cargo.toml
    ├── linux-x86_64/overload
    ├── linux-x86/overload
    ├── linux-arm64/overload
    ├── linux-armv7/overload
    ├── windows-x86_64/overload.exe
    └── windows-x86/overload.exe
```

**Server auto-detects:**
1. Uploaded binary's architecture and OS
2. Latest killer version available
3. Matching killer template for that platform
4. Falls back to closest compatible architecture if exact match not found

### Updating Killer Templates

```bash
# 1. Update version in Cargo.toml
# 2. Build new version
cd killer
./scripts/build/docker/build-all-platforms.sh

# 3. New version appears in builds/
# 4. Server automatically uses latest version
# 5. Old versions remain for backward compatibility
```

## Integration with KillCode System

### Workflow
1. **Build**: Create killer templates for all architectures
2. **Mount**: Docker mounts `killer/builds` to server as `/app/overload_bins`
3. **Upload**: User uploads binary to server
4. **Detect**: Server detects customer binary architecture (ELF/PE header analysis)
5. **Select**: Server chooses matching killer template from mounted builds
6. **Patch**: Server embeds license into killer's `.license` section
7. **Merge**: Weaver merges customer binary + patched killer
8. **Cache**: Server caches merged binary in `/uploads`
9. **Deliver**: Customer downloads single protected binary

### Server-Side License Patching
```rust
// Server writes license JSON to .license section
let license_json = serde_json::to_string(&license_config)?;
patch_license_section(&overload_binary, &license_json)?;
```

## Security Considerations

### What It Protects
✅ License validation before execution
✅ Time-based license expiration
✅ Machine fingerprinting (hardware-locked)
✅ HMAC-authenticated communication
✅ Self-destruct on tampering

### What It Doesn't Protect
❌ Runtime binary modification (use weaver merge)
❌ Memory dumping (use anti-debug features)
❌ Reverse engineering (obfuscate if needed)

### Best Practices
- Use SYNC mode for critical applications
- Enable self-destruct in production
- Keep shared secrets secure (environment variables)
- Monitor license check failures on server
- Rotate secrets periodically

## Troubleshooting

### Build Fails
```bash
# Clean Docker cache
docker system prune -a

# Rebuild from scratch
./scripts/build/docker/build-all-platforms.sh
```

### macOS Builds Fail
This is expected! macOS builds require OSXCross which needs Apple's SDK. Currently not supported. Use 6 working platforms instead.

### Binary Too Large
Already optimized. If you need smaller:
- Remove unused dependencies
- Use `upx` compression (may trigger antivirus)
- Remove debug symbols (already done)

## Development

### Adding New Features
1. Implement in `src/`
2. Test locally: `cargo test`
3. Build all platforms: `./scripts/build/docker/build-all-platforms.sh`
4. Verify templates are updated

### Modifying Build Process
- Edit `Dockerfile.build` for Docker environment
- Edit `scripts/build/docker/internal-docker-build.sh` for build logic

### Building Single Platform (Quick Testing)

When testing changes for a specific platform, use the single platform build script:

```bash
cd overload

# Build for specific platform
./scripts/build/docker/build-single-platform.sh linux-x86_64
./scripts/build/docker/build-single-platform.sh windows-x86_64
./scripts/build/docker/build-single-platform.sh linux-arm64
./scripts/build/docker/build-single-platform.sh linux-armv7
./scripts/build/docker/build-single-platform.sh windows-x86
./scripts/build/docker/build-single-platform.sh linux-x86
```

**Available platforms:**
- `linux-x86_64` - Linux 64-bit Intel/AMD
- `linux-x86` - Linux 32-bit Intel/AMD
- `linux-arm64` - Linux ARM 64-bit (Raspberry Pi 4, AWS Graviton)
- `linux-armv7` - Linux ARMv7 (Raspberry Pi 3)
- `windows-x86_64` - Windows 64-bit
- `windows-x86` - Windows 32-bit

**Benefits:**
- Faster than full build (~1-2 minutes vs 10+ minutes)
- Good for debugging platform-specific issues
- Auto-detects version from Cargo.toml
- Skips rebuild if version already exists

**Force rebuild:**
```bash
# Remove existing build for that platform
rm -rf builds/<version>/<platform>

# Then rebuild
./scripts/build/docker/build-single-platform.sh linux-x86_64
```

## License

Part of KillCode binary protection system.

## Support

- Check server logs for license verification issues
- Test with `.config` file before using embedded config
- Use single platform builds for faster iteration during development
