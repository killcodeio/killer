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
#   - macos-x86_64    : macOS Intel (requires OSXCross)
#   - macos-arm64     : macOS Apple Silicon (requires OSXCross)
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
    echo "  windows-x86_64  - Windows 64-bit (x86_64-pc-windows-gnullvm)"
    echo "  windows-x86     - Windows 32-bit (i686-pc-windows-gnullvm)"
    echo "  macos-x86_64    - macOS Intel (x86_64-apple-darwin)"
    echo "  macos-arm64     - macOS Apple Silicon (aarch64-apple-darwin)"
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
        HOST_OS=$(uname -s)
        if [[ "$HOST_OS" == "Linux" ]]; then
            # Cross-compiling from Linux: Use LLVM-MinGW with static linking
            TARGET="x86_64-pc-windows-gnullvm"
            LINKER="x86_64-w64-mingw32-clang"
            export RUSTFLAGS="-C target-feature=+crt-static"
            NAME="Windows x86-64 (LLVM Cross-Compile)"
        else
            # Native Windows build: Use MSVC
            TARGET="x86_64-pc-windows-msvc"
            # No specific linker needed for MSVC, cargo handles it
            LINKER="" 
            NAME="Windows x86-64 (MSVC Native)"
        fi
        ;;
    windows-x86)
        HOST_OS=$(uname -s)
        if [[ "$HOST_OS" == "Linux" ]]; then
            # Cross-compiling from Linux: Use LLVM-MinGW with static linking
            TARGET="i686-pc-windows-gnullvm"
            LINKER="i686-w64-mingw32-clang"
            export RUSTFLAGS="-C target-feature=+crt-static"
            NAME="Windows x86 (LLVM Cross-Compile)"
        else
            # Native Windows build: Use MSVC
            TARGET="i686-pc-windows-msvc"
            # No specific linker needed for MSVC, cargo handles it
            LINKER=""
            NAME="Windows x86 (MSVC Native)"
        fi
        ;;
    macos-x86_64)
        TARGET="x86_64-apple-darwin"
        # Use clang as the linker driver
        LINKER="x86_64-apple-darwin25.1-clang"
        
        # Set environment variables for C/C++ compilation (needed by ring, etc.)
        export CC_x86_64_apple_darwin="x86_64-apple-darwin25.1-clang"
        export CXX_x86_64_apple_darwin="x86_64-apple-darwin25.1-clang++"
        export AR_x86_64_apple_darwin="x86_64-apple-darwin25.1-ar"
        
        NAME="macOS Intel (x86_64)"
        ;;
    macos-arm64)
        TARGET="aarch64-apple-darwin"
        # Use clang as the linker driver
        LINKER="aarch64-apple-darwin25.1-clang"
        
        # Set environment variables for C/C++ compilation (needed by ring, etc.)
        export CC_aarch64_apple_darwin="aarch64-apple-darwin25.1-clang"
        export CXX_aarch64_apple_darwin="aarch64-apple-darwin25.1-clang++"
        export AR_aarch64_apple_darwin="aarch64-apple-darwin25.1-ar"
        
        NAME="macOS Apple Silicon (arm64)"
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
    OUTPUT_DIR="builds/$VERSION/$PLATFORM"
    mkdir -p "$OUTPUT_DIR"

    if [ -f "target/$TARGET/release/kc-killer.exe" ]; then
        cp "target/$TARGET/release/kc-killer.exe" "$OUTPUT_DIR/overload.exe"
        SIZE=$(stat -c%s "$OUTPUT_DIR/overload.exe" | numfmt --to=iec-i --suffix=B)
        echo "✅ Build successful! - $SIZE"
        echo ""
        echo "📁 Binary location:"
        echo "   $OUTPUT_DIR/overload.exe"
        ls -lh "$OUTPUT_DIR/overload.exe"
    elif [ -f "target/$TARGET/release/kc-killer" ]; then
        cp "target/$TARGET/release/kc-killer" "$OUTPUT_DIR/overload"
        chmod +x "$OUTPUT_DIR/overload"
        SIZE=$(stat -c%s "$OUTPUT_DIR/overload" | numfmt --to=iec-i --suffix=B)
        echo "✅ Build successful! - $SIZE"
        echo ""
        echo "📁 Binary location:"
        echo "   $OUTPUT_DIR/overload"
        ls -lh "$OUTPUT_DIR/overload"
    else
        echo "❌ Build failed - Binary not found"
        exit 1
    fi
else
    echo ""
    echo "❌ Build failed"
    exit 1
fi
