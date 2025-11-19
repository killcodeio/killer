#!/bin/bash
################################################################################
# build-single-platform.sh - Build overload for one platform on host machine
#
# DESCRIPTION:
#   Builds overload for ONE platform directly on host using cargo (no Docker).
#   Useful for quick testing and development.
#
# USAGE:
#   ./build-single-platform.sh <platform>
#
# EXAMPLES:
#   ./build-single-platform.sh linux-x86_64
#   ./build-single-platform.sh windows-x86_64
#   ./build-single-platform.sh linux-arm64
#
# AVAILABLE PLATFORMS:
#   - linux-x86_64    : Linux 64-bit Intel/AMD
#   - linux-x86       : Linux 32-bit Intel/AMD
#   - linux-arm64     : Linux ARM 64-bit
#   - linux-armv7     : Linux ARM 32-bit
#   - windows-x86_64  : Windows 64-bit
#   - windows-x86     : Windows 32-bit
#
# OUTPUT:
#   Binary built in: target/<triple>/release/overload[.exe]
#
# REQUIREMENTS:
#   Run ./check-deps.sh <platform> to verify dependencies!
#
# NOTES:
#   - Much faster than Docker build
#   - Good for iterative development
#   - Requires toolchains installed on host
#
################################################################################

set -e

PLATFORM=$1

if [ -z "$PLATFORM" ]; then
    echo "Usage: ./build-single-platform.sh <platform>"
    echo ""
    echo "Available platforms:"
    echo "  linux-x86_64    - Linux 64-bit (x86_64-unknown-linux-gnu)"
    echo "  linux-x86       - Linux 32-bit (i686-unknown-linux-gnu)"
    echo "  linux-arm64     - Linux ARM 64-bit (aarch64-unknown-linux-gnu)"
    echo "  linux-armv7     - Linux ARMv7 (armv7-unknown-linux-gnueabihf)"
    echo "  windows-x86_64  - Windows 64-bit (x86_64-pc-windows-gnu)"
    echo "  windows-x86     - Windows 32-bit (i686-pc-windows-gnu)"
    exit 1
fi

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

# Enable sccache for faster compilation if available
if command -v sccache &> /dev/null; then
    export RUSTC_WRAPPER=sccache
    echo "🚀 sccache enabled for faster compilation"
    echo ""
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
        TARGET="x86_64-pc-windows-gnu"
        LINKER="x86_64-w64-mingw32-gcc"
        NAME="Windows x86-64"
        ;;
    windows-x86)
        TARGET="i686-pc-windows-gnu"
        LINKER="i686-w64-mingw32-gcc"
        NAME="Windows x86 (32-bit)"
        ;;
    *)
        echo "❌ Unknown platform: $PLATFORM"
        exit 1
        ;;
esac

echo "🔨 Building Overload for $NAME (Host Build)"
echo "========================================================="
echo ""

# Check dependencies for this specific platform
echo "🔍 Checking dependencies for $PLATFORM..."
if ! ./scripts/build/host/check-deps.sh "$PLATFORM" > /dev/null 2>&1; then
    echo ""
    echo "⚠️  Dependencies check failed!"
    echo "   Run: ./scripts/build/host/check-deps.sh $PLATFORM"
    echo "   to see what's missing and how to install it."
    echo ""
    exit 1
fi

echo "✅ Dependencies satisfied"
echo ""

# Extract version
VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
echo "📦 Version: $VERSION"
echo "🎯 Target:  $TARGET"
echo ""

# Set linker
if [ -n "$LINKER" ]; then
    LINKER_VAR="CARGO_TARGET_$(echo $TARGET | tr '[:lower:]' '[:upper:]' | tr '-' '_')_LINKER"
    export $LINKER_VAR=$LINKER
    echo "🔗 Linker:  $LINKER"
    echo ""
fi

# Build
echo "⚙️  Building..."
echo ""

if cargo build --release --target "$TARGET"; then
    echo ""
    echo "========================================================="
    
    # Check for binary
    if [ -f "target/$TARGET/release/kc-killer.exe" ]; then
        SIZE=$(stat -c%s "target/$TARGET/release/kc-killer.exe" | numfmt --to=iec-i --suffix=B)
        echo "✅ Build successful! - $SIZE"
        echo ""
        echo "📁 Binary location:"
        echo "   target/$TARGET/release/kc-killer.exe"
        ls -lh "target/$TARGET/release/kc-killer.exe"
    elif [ -f "target/$TARGET/release/kc-killer" ]; then
        SIZE=$(stat -c%s "target/$TARGET/release/kc-killer" | numfmt --to=iec-i --suffix=B)
        echo "✅ Build successful! - $SIZE"
        echo ""
        echo "📁 Binary location:"
        echo "   target/$TARGET/release/kc-killer"
        ls -lh "target/$TARGET/release/kc-killer"
    else
        echo "❌ Build failed - Binary not found"
        exit 1
    fi
else
    echo ""
    echo "❌ Build failed"
    exit 1
fi
