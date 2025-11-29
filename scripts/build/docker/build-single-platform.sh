#!/bin/bash
################################################################################
# build-single-platform.sh - Build overload binary for one specific platform
#
# DESCRIPTION:
#   Builds overload for ONE platform at a time. Useful for:
#   - Testing individual platform builds
#   - Debugging compilation errors
#   - Incremental development
#
# USAGE:
#   ./build-single-platform.sh <platform>
#
# EXAMPLES:
#   ./build-single-platform.sh linux-x86_64     # Build for Linux 64-bit
#   ./build-single-platform.sh windows-x86_64   # Build for Windows 64-bit
#   ./build-single-platform.sh linux-arm64      # Build for Linux ARM64
#
# AVAILABLE PLATFORMS:
#   Linux:
#     - linux-x86_64    : Linux 64-bit Intel/AMD
#     - linux-x86       : Linux 32-bit Intel/AMD
#     - linux-arm64     : Linux ARM 64-bit (Raspberry Pi 4, AWS Graviton)
#     - linux-armv7     : Linux ARM 32-bit (Raspberry Pi 3)
#   
#   Windows:
#     - windows-x86_64  : Windows 64-bit
#     - windows-x86     : Windows 32-bit
#   
#   macOS (NOT SUPPORTED YET):
#     - macos-x86_64    : macOS Intel (requires OSXCross)
#     - macos-arm64     : macOS Apple Silicon (requires OSXCross)
#
# OUTPUT:
#   Built binary will be in versioned directory:
#   builds/<version>/<platform>/overload[.exe]
#
# VERSION DETECTION:
#   - Automatically extracts version from Cargo.toml
#   - Skips build if version/platform already exists
#   - Force rebuild with: rm -rf builds/<version>/<platform>
#
# REQUIREMENTS:
#   - Docker with BuildKit support
#   - Dockerfile.build
#
# NOTES:
#   - Faster than building all platforms (1-2 minutes per platform)
#   - Good for testing fixes before full build
#   - macOS builds will fail without OSXCross SDK
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

PLATFORM=$1

if [ -z "$PLATFORM" ]; then
    echo "Usage: ./build-single-platform.sh <platform>"
    echo ""
    echo "Available platforms:"
    echo "  linux-x86_64    - Linux 64-bit (x86_64-unknown-linux-gnu)"
    echo "  linux-x86       - Linux 32-bit (i686-unknown-linux-gnu)"
    echo "  linux-arm64     - Linux ARM 64-bit (aarch64-unknown-linux-gnu)"
    echo "  linux-armv7     - Linux ARMv7 (armv7-unknown-linux-gnueabihf)"
    echo "  windows-x86_64  - Windows 64-bit (x86_64-pc-windows-gnullvm)"
    echo "  windows-x86     - Windows 32-bit (i686-pc-windows-gnullvm)"
    echo "  macos-x86_64    - macOS Intel (x86_64-apple-darwin)"
    echo "  macos-arm64     - macOS Apple Silicon (aarch64-apple-darwin)"
    exit 1
fi

# Extract version from Cargo.toml
VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')

if [ -z "$VERSION" ]; then
    echo "❌ Error: Could not extract version from Cargo.toml"
    exit 1
fi

# Map platform to target triple and linker
case "$PLATFORM" in
    linux-x86_64)
        TARGET="x86_64-unknown-linux-gnu"
        LINKER="x86_64-linux-gnu-gcc"
        NAME="Linux x86-64"
        ;;
    linux-x86)
        TARGET="i686-unknown-linux-gnu"
        LINKER="i686-linux-gnu-gcc"
        NAME="Linux x86 (32-bit)"
        ;;
    linux-arm64)
        TARGET="aarch64-unknown-linux-gnu"
        LINKER="aarch64-linux-gnu-gcc"
        NAME="Linux ARM64"
        ;;
    linux-armv7)
        TARGET="armv7-unknown-linux-gnueabihf"
        LINKER="arm-linux-gnueabihf-gcc"
        NAME="Linux ARMv7"
        ;;
    windows-x86_64)
        TARGET="x86_64-pc-windows-gnullvm"
        LINKER="x86_64-w64-mingw32-clang"
        NAME="Windows x86-64 (LLVM)"
        ;;
    windows-x86)
        TARGET="i686-pc-windows-gnullvm"
        LINKER="i686-w64-mingw32-clang"
        NAME="Windows x86 (32-bit) (LLVM)"
        ;;
    macos-x86_64)
        TARGET="x86_64-apple-darwin"
        LINKER="x86_64-apple-darwin-gcc"
        NAME="macOS Intel"
        ;;
    macos-arm64)
        TARGET="aarch64-apple-darwin"
        LINKER="aarch64-apple-darwin-gcc"
        NAME="macOS Apple Silicon"
        ;;
    *)
        echo "❌ Unknown platform: $PLATFORM"
        exit 1
        ;;
esac

echo "🐳 Building Overload for $NAME"
echo "==========================================="
echo "📦 Version: $VERSION"
echo ""

# Check if this version/platform already exists
if [ -f "builds/$VERSION/$PLATFORM/overload" ] || [ -f "builds/$VERSION/$PLATFORM/overload.exe" ]; then
    echo "⚠️  Version $VERSION for $PLATFORM already exists"
    echo "   To rebuild, run: rm -rf builds/$VERSION/$PLATFORM"
    echo ""
    echo "📁 Existing binary:"
    ls -lh "builds/$VERSION/$PLATFORM/"overload* 2>/dev/null
    exit 0
fi

# Build Docker image
export DOCKER_BUILDKIT=1
echo "📦 Building Docker image with BuildKit..."
docker build -f Dockerfile.build \
    --build-arg KILLER_SERVER_URL="$KILLER_SERVER_URL" \
    -t overload-builder . || exit 1

echo ""
echo "🔨 Building target: $TARGET"
echo ""

# Create a temporary build script for single target
cat > /tmp/build_single_target.sh << 'EOFSCRIPT'
#!/bin/bash

TARGET="$1"
PLATFORM="$2"
NAME="$3"
LINKER="$4"
VERSION="$5"

OUTPUT_DIR="/build/builds/$VERSION"

echo "📦 Building: $NAME ($TARGET)"

# Set up cross-compilation linker
LINKER_VAR="CARGO_TARGET_$(echo $TARGET | tr '[:lower:]' '[:upper:]' | tr '-' '_')_LINKER"
export $LINKER_VAR=$LINKER

# Enable static linking for Windows to avoid missing DLLs (libunwind, etc.)
if [[ "$TARGET" == *"windows"* ]]; then
    export RUSTFLAGS="-C target-feature=+crt-static"
fi

# Build and capture exit code
cargo build --release --target "$TARGET" 2>&1 || true
BUILD_EXIT=${PIPESTATUS[0]}

if [ $BUILD_EXIT -eq 0 ]; then
    mkdir -p "$OUTPUT_DIR/$PLATFORM"
    
    # Copy binary (handle .exe for Windows)
    if [[ "$TARGET" == *"windows"* ]]; then
        if [ -f "target/$TARGET/release/kc-killer.exe" ]; then
            cp "target/$TARGET/release/kc-killer.exe" "$OUTPUT_DIR/$PLATFORM/overload.exe"
            SIZE=$(stat -c%s "$OUTPUT_DIR/$PLATFORM/overload.exe" | numfmt --to=iec-i --suffix=B)
            echo ""
            echo "✅ Success - $SIZE"
            exit 0
        else
            echo ""
            echo "❌ Failed - Binary not found"
            exit 1
        fi
    else
        if [ -f "target/$TARGET/release/kc-killer" ]; then
            cp "target/$TARGET/release/kc-killer" "$OUTPUT_DIR/$PLATFORM/overload"
            chmod +x "$OUTPUT_DIR/$PLATFORM/overload"
            SIZE=$(stat -c%s "$OUTPUT_DIR/$PLATFORM/overload" | numfmt --to=iec-i --suffix=B)
            echo ""
            echo "✅ Success - $SIZE"
            exit 0
        else
            echo ""
            echo "❌ Failed - Binary not found"
            exit 1
        fi
    fi
else
    echo ""
    echo "❌ Failed - Build error (exit code: $BUILD_EXIT)"
    exit 1
fi
EOFSCRIPT

chmod +x /tmp/build_single_target.sh

# Run build in Docker
# Run build in Docker
docker run --rm \
    -e KILLER_SERVER_URL="$KILLER_SERVER_URL" \
    -v "$(pwd)/builds:/build/builds" \
    -v "/tmp/build_single_target.sh:/build/build_single_target.sh" \
    -v "sccache-killer:/sccache" \
    -v "cargo-registry:/usr/local/cargo/registry" \
    -v "cargo-git:/usr/local/cargo/git" \
    overload-builder \
    bash -c "bash /build/build_single_target.sh '$TARGET' '$PLATFORM' '$NAME' '$LINKER' '$VERSION'"

BUILD_RESULT=$?

echo ""
echo "==========================================="
if [ $BUILD_RESULT -eq 0 ]; then
    echo "✅ Build complete! Binary is in ./builds/$VERSION/$PLATFORM/"
    ls -lh "./builds/$VERSION/$PLATFORM/"
else
    echo "❌ Build failed for $PLATFORM"
fi

exit $BUILD_RESULT
