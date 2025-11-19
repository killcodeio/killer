#!/bin/bash
################################################################################
# internal-docker-build.sh - Internal Docker build script (DO NOT RUN DIRECTLY)
#
# DESCRIPTION:
#   This script runs INSIDE the Docker container and performs the actual
#   cross-compilation for all architectures. It is called automatically by
#   build-all-platforms.sh or build-single-platform.sh.
#
# USAGE:
#   DO NOT run this directly on your host machine!
#   This is executed inside the Docker container automatically.
#
# WHAT IT DOES:
#   1. Extracts version from Cargo.toml or environment variable
#   2. Sets up cross-compilation environment variables
#   3. Configures linkers for each target architecture
#   4. Runs cargo build for each platform
#   5. Copies built binaries to /build/builds/<version>/<platform>/
#   6. Reports success/failure for each platform
#
# PLATFORMS BUILT:
#   - Linux: x86_64, x86, ARM64, ARMv7
#   - Windows: x86_64, x86
#   - macOS: x86_64, ARM64 (will fail without OSXCross)
#
# OUTPUT:
#   Binaries are placed in /build/builds/<version>/<platform>/overload[.exe]
#
# NOTES:
#   - Continues building even if individual platforms fail
#   - Shows summary at the end with success/failure counts
#   - Used by both build-all-platforms.sh and build-single-platform.sh
#
################################################################################

# DON'T use set -e - we want to continue even if individual builds fail
# set -e

echo "🔧 Building Killer's Overload for All Architectures"
echo "==========================================="
echo ""

# Get version from environment or Cargo.toml
if [ -z "$VERSION" ]; then
    VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
fi

if [ -z "$VERSION" ]; then
    echo "❌ Error: VERSION not set and couldn't extract from Cargo.toml"
    exit 1
fi

echo "📦 Version: $VERSION"
echo ""

# Output directory
OUTPUT_DIR="/build/builds/$VERSION"
mkdir -p "$OUTPUT_DIR"

# Track results
SUCCESS_COUNT=0
FAIL_COUNT=0

# Build function
build_for_target() {
    local target=$1
    local output_dir=$2
    local display_name=$3
    local linker=$4
    
    echo "📦 Building: $display_name ($target)"
    
    # Set linker if specified
    if [ -n "$linker" ]; then
        export CARGO_TARGET_$(echo $target | tr '[:lower:]' '[:upper:]' | tr '-' '_')_LINKER=$linker
    fi
    
    # Build and capture exit code
    cargo build --release --target "$target" 2>&1 | tail -10
    BUILD_EXIT=${PIPESTATUS[0]}
    
    if [ $BUILD_EXIT -eq 0 ]; then
        mkdir -p "$OUTPUT_DIR/$output_dir"
        
        # Copy binary (handle .exe for Windows)
        if [[ "$target" == *"windows"* ]]; then
            if [ -f "target/$target/release/kc-killer.exe" ]; then
                cp "target/$target/release/kc-killer.exe" "$OUTPUT_DIR/$output_dir/overload.exe"
                echo "   ✅ Success - $(stat -c%s "$OUTPUT_DIR/$output_dir/overload.exe" | numfmt --to=iec-i --suffix=B)"
                ((SUCCESS_COUNT++))
            else
                echo "   ❌ Failed - Binary not found"
                ((FAIL_COUNT++))
            fi
        else
            if [ -f "target/$target/release/kc-killer" ]; then
                cp "target/$target/release/kc-killer" "$OUTPUT_DIR/$output_dir/overload"
                chmod +x "$OUTPUT_DIR/$output_dir/overload"
                echo "   ✅ Success - $(stat -c%s "$OUTPUT_DIR/$output_dir/overload" | numfmt --to=iec-i --suffix=B)"
                ((SUCCESS_COUNT++))
            else
                echo "   ❌ Failed - Binary not found"
                ((FAIL_COUNT++))
            fi
        fi
    else
        echo "   ❌ Failed - Build error (exit code: $BUILD_EXIT)"
        ((FAIL_COUNT++))
    fi
    
    echo ""
}

# Linux builds
build_for_target "x86_64-unknown-linux-gnu" "linux-x86_64" "Linux x86-64" "x86_64-linux-gnu-gcc"
build_for_target "i686-unknown-linux-gnu" "linux-x86" "Linux x86 (32-bit)" "i686-linux-gnu-gcc"
build_for_target "aarch64-unknown-linux-gnu" "linux-arm64" "Linux ARM64" "aarch64-linux-gnu-gcc"
build_for_target "armv7-unknown-linux-gnueabihf" "linux-armv7" "Linux ARMv7" "arm-linux-gnueabihf-gcc"

# Windows builds
build_for_target "x86_64-pc-windows-gnu" "windows-x86_64" "Windows x86-64" "x86_64-w64-mingw32-gcc"
build_for_target "i686-pc-windows-gnu" "windows-x86" "Windows x86 (32-bit)" "i686-w64-mingw32-gcc"

# macOS builds (may fail without macOS SDK, but try anyway)
build_for_target "x86_64-apple-darwin" "macos-x86_64" "macOS Intel" ""
build_for_target "aarch64-apple-darwin" "macos-arm64" "macOS Apple Silicon" ""

# Summary
echo "==========================================="
echo "📊 Build Summary"
echo "==========================================="
echo "✅ Success: $SUCCESS_COUNT"
echo "❌ Failed:  $FAIL_COUNT"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "📁 Built templates:"
    ls -lh "$OUTPUT_DIR"/*/ 2>/dev/null | grep -E "^-" || true
fi

echo ""
if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 All builds successful!"
    exit 0
else
    echo "⚠️  Some builds failed (this is expected for macOS without SDK)"
    exit 0  # Don't fail the build if only some targets fail
fi
