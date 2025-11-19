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

# Enable BuildKit for better caching
export DOCKER_BUILDKIT=1

# Build the Docker image with BuildKit optimizations
echo "📦 Building Docker image with BuildKit..."
docker build -f Dockerfile.build \
    --build-arg KILLER_SERVER_URL="$KILLER_SERVER_URL" \
    -t overload-builder .

echo ""
echo "🔨 Running build in Docker container..."
docker run --rm \
    -e VERSION="$VERSION" \
    -e KILLER_SERVER_URL="$KILLER_SERVER_URL" \
    -v "$(pwd)/builds:/build/builds" \
    -v "sccache-killer:/sccache" \
    -v "cargo-registry:/usr/local/cargo/registry" \
    -v "cargo-git:/usr/local/cargo/git" \
    overload-builder \
    bash -c "sccache --show-stats && ./scripts/build/docker/internal-docker-build.sh && sccache --show-stats"

echo ""
echo "✅ Build complete! Binaries are in ./builds/$VERSION/"
echo ""
echo "📁 Built binaries:"
find "builds/$VERSION" -name "overload*" -type f -exec ls -lh {} \;
