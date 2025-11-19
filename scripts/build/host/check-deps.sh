#!/bin/bash
################################################################################
# check-deps.sh - Check build dependencies for host compilation
#
# DESCRIPTION:
#   Verifies that all required tools and libraries are installed for
#   cross-compiling overload binaries directly on the host machine.
#   Supports multiple Linux distributions with distro-specific package names.
#
# USAGE:
#   ./check-deps.sh [platform]
#
# ARGUMENTS:
#   platform - Optional. Check deps for specific platform only.
#              If omitted, checks all platforms.
#
# EXAMPLES:
#   ./check-deps.sh              # Check all dependencies
#   ./check-deps.sh linux-x86_64 # Check specific platform
#
# SUPPORTED DISTROS:
#   - Ubuntu/Debian (apt)
#   - Arch Linux (pacman)
#   - Fedora/RHEL (dnf/yum)
#
# WHAT IT CHECKS:
#   1. System packages (gcc, mingw, etc.)
#   2. Rust toolchains (rustup targets)
#   3. Required libraries (openssl, pkg-config, etc.)
#
# OUTPUT:
#   - Lists missing dependencies
#   - Provides exact commands to install them (distro-specific)
#   - Does NOT install automatically (user must run commands)
#
# EXIT CODES:
#   0 - All dependencies satisfied
#   1 - Missing dependencies found
#
################################################################################

set -e

PLATFORM=${1:-"all"}
MISSING_DEPS=0

echo "🔍 Checking Build Dependencies for Host Compilation"
echo "========================================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_NAME=$NAME
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
        DISTRO_NAME="Arch Linux"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
        DISTRO_NAME="Debian"
    else
        DISTRO="unknown"
        DISTRO_NAME="Unknown"
    fi
}

detect_distro
echo -e "${BLUE}📋 Detected Distribution: $DISTRO_NAME${NC}"
echo ""

# Track what's missing
MISSING_PACKAGES=()
MISSING_TARGETS=()

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if package is installed
package_installed() {
    local pkg=$1
    case $DISTRO in
        ubuntu|debian|pop|linuxmint)
            dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
            ;;
        arch|manjaro|endeavouros)
            pacman -Q "$pkg" >/dev/null 2>&1
            ;;
        fedora|rhel|centos|rocky|almalinux)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to check if Rust target is installed
rust_target_installed() {
    rustup target list | grep -q "^$1 (installed)"
}

# Function to get distro-specific package name
get_package_name() {
    local generic_name=$1
    
    case $DISTRO in
        ubuntu|debian|pop|linuxmint)
            case $generic_name in
                "gcc-x86_64") echo "gcc-x86-64-linux-gnu" ;;
                "g++-x86_64") echo "g++-x86-64-linux-gnu" ;;
                "gcc-i686") echo "gcc-i686-linux-gnu" ;;
                "g++-i686") echo "g++-i686-linux-gnu" ;;
                "gcc-aarch64") echo "gcc-aarch64-linux-gnu" ;;
                "g++-aarch64") echo "g++-aarch64-linux-gnu" ;;
                "gcc-armv7") echo "gcc-arm-linux-gnueabihf" ;;
                "g++-armv7") echo "g++-arm-linux-gnueabihf" ;;
                "mingw-w64") echo "mingw-w64" ;;
                "mingw-x86_64") echo "gcc-mingw-w64-x86-64" ;;
                "mingw-i686") echo "gcc-mingw-w64-i686" ;;
                "pkg-config") echo "pkg-config" ;;
                "openssl-dev") echo "libssl-dev" ;;
                *) echo "$generic_name" ;;
            esac
            ;;
        arch|manjaro|endeavouros)
            case $generic_name in
                "gcc-x86_64") echo "gcc" ;;  # Native gcc
                "g++-x86_64") echo "gcc" ;;
                "gcc-i686") echo "lib32-gcc-libs" ;;
                "g++-i686") echo "lib32-gcc-libs" ;;
                "gcc-aarch64") echo "aarch64-linux-gnu-gcc" ;;
                "g++-aarch64") echo "aarch64-linux-gnu-gcc" ;;
                "gcc-armv7") echo "arm-linux-gnueabihf-gcc" ;;
                "g++-armv7") echo "arm-linux-gnueabihf-gcc" ;;
                "mingw-w64") echo "mingw-w64-gcc" ;;
                "mingw-x86_64") echo "mingw-w64-gcc" ;;
                "mingw-i686") echo "mingw-w64-gcc" ;;
                "pkg-config") echo "pkgconf" ;;  # Arch uses pkgconf
                "openssl-dev") echo "openssl" ;;
                *) echo "$generic_name" ;;
            esac
            ;;
        fedora|rhel|centos|rocky|almalinux)
            case $generic_name in
                "gcc-x86_64") echo "gcc" ;;
                "g++-x86_64") echo "gcc-c++" ;;
                "gcc-i686") echo "glibc-devel.i686" ;;
                "g++-i686") echo "libstdc++-devel.i686" ;;
                "gcc-aarch64") echo "gcc-aarch64-linux-gnu" ;;
                "g++-aarch64") echo "gcc-c++-aarch64-linux-gnu" ;;
                "gcc-armv7") echo "gcc-arm-linux-gnu" ;;
                "g++-armv7") echo "gcc-c++-arm-linux-gnu" ;;
                "mingw-w64") echo "mingw64-gcc" ;;
                "mingw-x86_64") echo "mingw64-gcc" ;;
                "mingw-i686") echo "mingw32-gcc" ;;
                "pkg-config") echo "pkgconfig" ;;
                "openssl-dev") echo "openssl-devel" ;;
                *) echo "$generic_name" ;;
            esac
            ;;
        *)
            echo "$generic_name"
            ;;
    esac
}

# Function to add missing package (converts to distro-specific name)
add_missing_package() {
    local generic_name=$1
    local distro_pkg=$(get_package_name "$generic_name")
    
    # Check if not already in array
    if [[ ! " ${MISSING_PACKAGES[@]} " =~ " ${distro_pkg} " ]]; then
        MISSING_PACKAGES+=("$distro_pkg")
    fi
}

# Function to check toolchain by command
check_toolchain() {
    local display_name=$1
    local command_name=$2
    local generic_gcc=$3
    local generic_gxx=$4
    
    if command_exists "$command_name"; then
        echo -e "  ${GREEN}✅${NC} $display_name"
        return 0
    else
        echo -e "  ${RED}❌${NC} $display_name"
        add_missing_package "$generic_gcc"
        [ -n "$generic_gxx" ] && add_missing_package "$generic_gxx"
        return 1
    fi
}

echo "📦 Checking Base Dependencies..."
echo ""

# Check Rust
if command_exists rustc; then
    RUST_VERSION=$(rustc --version | awk '{print $2}')
    echo -e "${GREEN}✅${NC} Rust installed: $RUST_VERSION"
else
    echo -e "${RED}❌${NC} Rust not installed"
    echo "   Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    MISSING_DEPS=1
fi

# Check rustup
if command_exists rustup; then
    echo -e "${GREEN}✅${NC} rustup installed"
else
    echo -e "${RED}❌${NC} rustup not installed"
    MISSING_DEPS=1
fi

# Check cargo
if command_exists cargo; then
    CARGO_VERSION=$(cargo --version | awk '{print $2}')
    echo -e "${GREEN}✅${NC} cargo installed: $CARGO_VERSION"
else
    echo -e "${RED}❌${NC} cargo not installed"
    MISSING_DEPS=1
fi

echo ""
echo "📦 Checking Platform-Specific Dependencies..."
echo ""

# Linux x86_64
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "linux-x86_64" ]; then
    echo "🐧 Linux x86_64:"
    
    check_toolchain "gcc-x86-64-linux-gnu" "x86_64-linux-gnu-gcc" "gcc-x86_64" "g++-x86_64"
    
    if rust_target_installed "x86_64-unknown-linux-gnu"; then
        echo -e "  ${GREEN}✅${NC} Rust target: x86_64-unknown-linux-gnu"
    else
        echo -e "  ${RED}❌${NC} Rust target: x86_64-unknown-linux-gnu"
        MISSING_TARGETS+=("x86_64-unknown-linux-gnu")
    fi
    echo ""
fi

# Linux x86 (32-bit)
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "linux-x86" ]; then
    echo "🐧 Linux x86 (32-bit):"
    
    check_toolchain "gcc-i686-linux-gnu" "i686-linux-gnu-gcc" "gcc-i686" "g++-i686"
    
    if rust_target_installed "i686-unknown-linux-gnu"; then
        echo -e "  ${GREEN}✅${NC} Rust target: i686-unknown-linux-gnu"
    else
        echo -e "  ${RED}❌${NC} Rust target: i686-unknown-linux-gnu"
        MISSING_TARGETS+=("i686-unknown-linux-gnu")
    fi
    echo ""
fi

# Linux ARM64
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "linux-arm64" ]; then
    echo "🐧 Linux ARM64:"
    
    check_toolchain "gcc-aarch64-linux-gnu" "aarch64-linux-gnu-gcc" "gcc-aarch64" "g++-aarch64"
    
    if rust_target_installed "aarch64-unknown-linux-gnu"; then
        echo -e "  ${GREEN}✅${NC} Rust target: aarch64-unknown-linux-gnu"
    else
        echo -e "  ${RED}❌${NC} Rust target: aarch64-unknown-linux-gnu"
        MISSING_TARGETS+=("aarch64-unknown-linux-gnu")
    fi
    echo ""
fi

# Linux ARMv7
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "linux-armv7" ]; then
    echo "🐧 Linux ARMv7:"
    
    check_toolchain "gcc-arm-linux-gnueabihf" "arm-linux-gnueabihf-gcc" "gcc-armv7" "g++-armv7"
    
    if rust_target_installed "armv7-unknown-linux-gnueabihf"; then
        echo -e "  ${GREEN}✅${NC} Rust target: armv7-unknown-linux-gnueabihf"
    else
        echo -e "  ${RED}❌${NC} Rust target: armv7-unknown-linux-gnueabihf"
        MISSING_TARGETS+=("armv7-unknown-linux-gnueabihf")
    fi
    echo ""
fi

# Windows x86_64
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "windows-x86_64" ]; then
    echo "🪟 Windows x86_64:"
    
    if command_exists "x86_64-w64-mingw32-gcc"; then
        echo -e "  ${GREEN}✅${NC} mingw-w64 (x86_64)"
    else
        echo -e "  ${RED}❌${NC} mingw-w64 (x86_64)"
        add_missing_package "mingw-w64"
        add_missing_package "mingw-x86_64"
    fi
    
    if rust_target_installed "x86_64-pc-windows-gnu"; then
        echo -e "  ${GREEN}✅${NC} Rust target: x86_64-pc-windows-gnu"
    else
        echo -e "  ${RED}❌${NC} Rust target: x86_64-pc-windows-gnu"
        MISSING_TARGETS+=("x86_64-pc-windows-gnu")
    fi
    echo ""
fi

# Windows x86 (32-bit)
if [ "$PLATFORM" = "all" ] || [ "$PLATFORM" = "windows-x86" ]; then
    echo "🪟 Windows x86 (32-bit):"
    
    if command_exists "i686-w64-mingw32-gcc"; then
        echo -e "  ${GREEN}✅${NC} mingw-w64 (i686)"
    else
        echo -e "  ${RED}❌${NC} mingw-w64 (i686)"
        add_missing_package "mingw-w64"
        add_missing_package "mingw-i686"
    fi
    
    if rust_target_installed "i686-pc-windows-gnu"; then
        echo -e "  ${GREEN}✅${NC} Rust target: i686-pc-windows-gnu"
    else
        echo -e "  ${RED}❌${NC} Rust target: i686-pc-windows-gnu"
        MISSING_TARGETS+=("i686-pc-windows-gnu")
    fi
    echo ""
fi

# Check common dependencies
echo "📚 Checking Common Libraries..."
echo ""

# Check pkg-config
PKG_CONFIG_PKG=$(get_package_name "pkg-config")
if package_installed "$PKG_CONFIG_PKG" || command_exists "pkg-config"; then
    echo -e "${GREEN}✅${NC} $PKG_CONFIG_PKG"
else
    echo -e "${RED}❌${NC} $PKG_CONFIG_PKG"
    add_missing_package "pkg-config"
fi

# Check OpenSSL
OPENSSL_PKG=$(get_package_name "openssl-dev")
case $DISTRO in
    ubuntu|debian|pop|linuxmint)
        if package_installed "libssl-dev"; then
            echo -e "${GREEN}✅${NC} libssl-dev"
        else
            echo -e "${RED}❌${NC} libssl-dev"
            add_missing_package "openssl-dev"
        fi
        ;;
    arch|manjaro|endeavouros)
        if package_installed "openssl"; then
            echo -e "${GREEN}✅${NC} openssl"
        else
            echo -e "${RED}❌${NC} openssl"
            add_missing_package "openssl-dev"
        fi
        ;;
    fedora|rhel|centos|rocky|almalinux)
        if package_installed "openssl-devel"; then
            echo -e "${GREEN}✅${NC} openssl-devel"
        else
            echo -e "${RED}❌${NC} openssl-devel"
            add_missing_package "openssl-dev"
        fi
        ;;
    *)
        echo -e "${YELLOW}⚠️${NC} OpenSSL (cannot verify on unknown distro)"
        ;;
esac

echo ""
echo "========================================================="
echo ""

# Remove duplicates
MISSING_PACKAGES=($(echo "${MISSING_PACKAGES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
MISSING_TARGETS=($(echo "${MISSING_TARGETS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# Generate install command based on distro
get_install_command() {
    case $DISTRO in
        ubuntu|debian|pop|linuxmint)
            echo "sudo apt-get update && sudo apt-get install -y"
            ;;
        arch|manjaro|endeavouros)
            echo "sudo pacman -S --needed"
            ;;
        fedora)
            echo "sudo dnf install -y"
            ;;
        rhel|centos|rocky|almalinux)
            if command_exists dnf; then
                echo "sudo dnf install -y"
            else
                echo "sudo yum install -y"
            fi
            ;;
        *)
            echo "# Install using your package manager:"
            ;;
    esac
}

# Print summary
if [ ${#MISSING_PACKAGES[@]} -eq 0 ] && [ ${#MISSING_TARGETS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All dependencies satisfied!${NC}"
    echo ""
    echo "You can now build with:"
    echo "  ./build-all-platforms.sh"
    echo "  ./build-single-platform.sh <platform>"
    exit 0
else
    echo -e "${YELLOW}⚠️  Missing Dependencies Found${NC}"
    echo ""
    
    if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
        echo -e "${RED}Missing System Packages:${NC}"
        for pkg in "${MISSING_PACKAGES[@]}"; do
            echo "  - $pkg"
        done
        echo ""
        echo -e "${YELLOW}Install with:${NC}"
        INSTALL_CMD=$(get_install_command)
        echo "  $INSTALL_CMD ${MISSING_PACKAGES[@]}"
        echo ""
    fi
    
    if [ ${#MISSING_TARGETS[@]} -gt 0 ]; then
        echo -e "${RED}Missing Rust Targets:${NC}"
        for target in "${MISSING_TARGETS[@]}"; do
            echo "  - $target"
        done
        echo ""
        echo -e "${YELLOW}Install with:${NC}"
        for target in "${MISSING_TARGETS[@]}"; do
            echo "  rustup target add $target"
        done
        echo ""
        echo "Or install all at once:"
        echo "  rustup target add ${MISSING_TARGETS[@]}"
        echo ""
    fi
    
    echo "After installing dependencies, run this script again to verify."
    exit 1
fi
