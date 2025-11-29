#!/bin/bash
################################################################################
# build-all-platforms.sh - Build overload binaries for all architectures
#
# DESCRIPTION:
#   Builds overload license verification binaries for 6 platforms using Docker:
#   - Linux: x86_64, x86 (32-bit), ARM64, ARMv7
#   - Windows: x86_64, x86 (32-bit)
#
# USAGE:
#   ./build-all-platforms.sh
#
# OUTPUT:
#   Built binaries will be in versioned directory structure:
#   builds/1.0.0/linux-x86_64/overload
#   builds/1.0.0/linux-x86/overload
#   builds/1.0.0/linux-arm64/overload
#   builds/1.0.0/linux-armv7/overload
#   builds/1.0.0/windows-x86_64/overload.exe
#   builds/1.0.0/windows-x86/overload.exe
#
# VERSION DETECTION:
#   - Automatically extracts version from Cargo.toml
#   - Skips build if version already exists in builds/
#   - Force rebuild with: rm -rf builds/<version>
#
# REQUIREMENTS:
#   - Docker with BuildKit support (DOCKER_BUILDKIT=1)
#   - Dockerfile.build (cross-compilation environment)
#
# NOTES:
#   - Uses BuildKit for fast incremental builds (caches dependencies)
#   - First build takes ~2 minutes, subsequent builds ~10 seconds
#   - macOS builds not supported (requires OSXCross SDK)
#
################################################################################

set -e

# Always run from overload project root regardless of where script is called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$PROJECT_ROOT"

echo "📂 Working directory: $PROJECT_ROOT"
echo ""

# Load environment variables from .env if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "📝 Loading environment from .env..."
    set -a  # automatically export all variables
    source "$PROJECT_ROOT/.env"
    set +a
    if [ -n "$KILLER_SERVER_URL" ]; then
        echo "   KILLER_SERVER_URL: $KILLER_SERVER_URL"
    fi
    echo ""
fi

echo "🐳 Building Overload - All Platforms"
echo "========================================================="
echo ""

# Extract version from Cargo.toml
VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')

if [ -z "$VERSION" ]; then
    echo "❌ Error: Could not extract version from Cargo.toml"
    exit 1
fi

echo "📦 Version: $VERSION"
echo ""

# Check if this version already exists
if [ -d "builds/$VERSION" ]; then
    echo "⚠️  Version $VERSION already exists in builds/"
    echo "   To rebuild, run: rm -rf builds/$VERSION"
    echo ""
    echo "📁 Existing binaries:"
    find "builds/$VERSION" -name "overload*" -type f -exec ls -lh {} \;
    exit 0
fi

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
    echo "🐳 Starting Docker build for: $platform"
    echo "---------------------------------------------------------"
    
    if ./scripts/build/docker/build-single-platform.sh "$platform"; then
        ((SUCCESS_COUNT++))
    else
        echo "❌ Build failed for $platform"
        ((FAIL_COUNT++))
        FAILED_PLATFORMS+=("$platform")
    fi
    echo ""
done
