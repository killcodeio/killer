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

# List of platforms to build
PLATFORMS=(
    "linux-x86_64"
    "linux-x86"
    "linux-arm64"
    "linux-armv7"
    "windows-x86_64"
    "windows-x86"
    "macos-x86_64"
    "macos-arm64"
)

# Build loop
for platform in "${PLATFORMS[@]}"; do
    echo "---------------------------------------------------------"
    echo "🚀 Starting build for: $platform"
    echo "---------------------------------------------------------"
    
    if ./scripts/build/host/build-single-platform.sh "$platform"; then
        ((SUCCESS_COUNT++)) || true
    else
        echo "❌ Build failed for $platform"
        ((FAIL_COUNT++)) || true
        FAILED_PLATFORMS+=("$platform")
    fi
    echo ""
done

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

if [ $FAIL_COUNT -gt 0 ]; then
    echo "⚠️  Some builds failed"
    exit 1
fi

echo "✅ All builds completed successfully!"
