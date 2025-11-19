#!/bin/bash
################################################################################
# build-all-platforms.sh - Build overload for all platforms on host machine
#
# DESCRIPTION:
#   Builds overload directly on the host using cargo (no Docker).
#   Requires all cross-compilation toolchains installed on host.
#
# USAGE:
#   ./build-all-platforms.sh
#
# OUTPUT:
#   Binaries are built in standard cargo location:
#   target/<triple>/release/overload[.exe]
#   
#   For example:
#   - target/x86_64-unknown-linux-gnu/release/overload
#   - target/x86_64-pc-windows-gnu/release/overload.exe
#
# REQUIREMENTS:
#   Run ./check-dependencies.sh first to verify all tools are installed!
#
# NOTES:
#   - Faster than Docker (no container overhead)
#   - Uses native cargo build
#   - Requires manual dependency installation
#   - Good for development and testing
#
################################################################################

set -e

# Change to project root
cd "$(dirname "$0")/../../.."

# Load environment variables from .env if it exists
if [ -f ".env" ]; then
    echo "📝 Loading environment from .env..."
    set -a  # automatically export all variables
    source ".env"
    set +a
    if [ -n "$KILLER_SERVER_URL" ]; then
        echo "   KILLER_SERVER_URL: $KILLER_SERVER_URL"
    fi
    echo ""
fi

echo "🔨 Building Overload - All Platforms (Host Build)"
echo "========================================================="
echo ""

# Enable sccache for faster compilation if available
if command -v sccache &> /dev/null; then
    export RUSTC_WRAPPER=sccache
    echo "🚀 sccache enabled for faster compilation"
    echo ""
fi

# Check dependencies first
echo "🔍 Checking dependencies..."
if ! ./scripts/build/host/check-deps.sh > /dev/null 2>&1; then
    echo ""
    echo "⚠️  Dependencies check failed!"
    echo "   Run: ./scripts/build/host/check-deps.sh"
    echo "   to see what's missing and how to install it."
    echo ""
    exit 1
fi

echo "✅ All dependencies satisfied"
echo ""

# Extract version
VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
echo "📦 Version: $VERSION"
echo ""

# Track results
SUCCESS_COUNT=0
FAIL_COUNT=0
declare -a FAILED_PLATFORMS

# Build function
build_platform() {
    local target=$1
    local display_name=$2
    local linker=$3
    
    echo "📦 Building: $display_name ($target)"
    
    # Set linker if specified
    if [ -n "$linker" ]; then
        local linker_var="CARGO_TARGET_$(echo $target | tr '[:lower:]' '[:upper:]' | tr '-' '_')_LINKER"
        export $linker_var=$linker
    fi
    
    # Build
    if cargo build --release --target "$target" 2>&1 | tail -5; then
        if [ -f "target/$target/release/kc-killer.exe" ]; then
            SIZE=$(stat -c%s "target/$target/release/kc-killer.exe" | numfmt --to=iec-i --suffix=B)
            echo "   ✅ Success - $SIZE"
            ((SUCCESS_COUNT++))
        elif [ -f "target/$target/release/kc-killer" ]; then
            SIZE=$(stat -c%s "target/$target/release/kc-killer" | numfmt --to=iec-i --suffix=B)
            echo "   ✅ Success - $SIZE"
            ((SUCCESS_COUNT++))
        else
            echo "   ❌ Failed - Binary not found"
            FAILED_PLATFORMS+=("$display_name")
            ((FAIL_COUNT++))
        fi
    else
        echo "   ❌ Failed - Build error"
        FAILED_PLATFORMS+=("$display_name")
        ((FAIL_COUNT++))
    fi
    
    echo ""
}

# Build all platforms
build_platform "x86_64-unknown-linux-gnu" "Linux x86-64" "x86_64-linux-gnu-gcc"
build_platform "i686-unknown-linux-gnu" "Linux x86 (32-bit)" "i686-linux-gnu-gcc"
build_platform "aarch64-unknown-linux-gnu" "Linux ARM64" "aarch64-linux-gnu-gcc"
build_platform "armv7-unknown-linux-gnueabihf" "Linux ARMv7" "arm-linux-gnueabihf-gcc"
build_platform "x86_64-pc-windows-gnu" "Windows x86-64" "x86_64-w64-mingw32-gcc"
build_platform "i686-pc-windows-gnu" "Windows x86 (32-bit)" "i686-w64-mingw32-gcc"

echo "========================================================="
echo "📊 Build Summary"
echo "========================================================="
echo "✅ Success: $SUCCESS_COUNT"
echo "❌ Failed:  $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo "Failed platforms:"
    for platform in "${FAILED_PLATFORMS[@]}"; do
        echo "  - $platform"
    done
    echo ""
fi

echo "📁 Built binaries are in target/<triple>/release/"
echo ""
echo "Examples:"
echo "  target/x86_64-unknown-linux-gnu/release/overload"
echo "  target/x86_64-pc-windows-gnu/release/overload.exe"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo "⚠️  Some builds failed"
    exit 1
fi

echo "✅ All builds completed successfully!"
