# macOS Cross-Compilation Guide

This document details the intricacies of cross-compiling for macOS from a Linux host, specifically focusing on the toolchain setup using OSXCross.

## 🧠 Concepts: Apple's Toolchain

Understanding the underlying tools is crucial for successful cross-compilation.

- **Clang**: The compiler frontend used by Apple. Unlike GCC, Clang acts as a "Driver" that manages the entire pipeline (compiling, linking, etc.).
- **Mach-O**: The binary format used by macOS (similar to ELF on Linux or PE on Windows).
- **OSXCross**: A tool that creates a cross-compiler toolchain on Linux using Clang and a packaged version of the macOS SDK.

---

## 🛠️ The Solution: OSXCross

To compile for macOS on Linux, we use **OSXCross**. This toolchain allows us to target both Intel (`x86_64`) and Apple Silicon (`arm64`) Macs.

### 1. Obtain the macOS SDK

This is the most critical step. You need a macOS SDK (e.g., `MacOSX13.3.sdk.tar.xz`).

**Official Method (Requires a Mac):**

1.  Install Xcode on a Mac.
2.  Locate the SDK directory: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/`.
3.  Compress the SDK. Note that you must compress it **outside** the SDK directory (as it is read-only) and use `--dereference` to handle symlinks correctly.

```bash
# Example for MacOSX 13.3 SDK
sudo tar -cvJf ~/MacOSX13.3.sdk.tar.xz --dereference /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX13.3.sdk
```

**Unofficial Method:**
Many developers mirror these SDKs in GitHub repositories. You can search for "MacOSX SDK GitHub" to find them. This approach is mentioned only for informational purposes — it is not recommended or endorsed.

> [!IMPORTANT]
> For Apple Silicon (`arm64`) support, you **must** use an SDK version **11.0 or higher**.

### 2. Build the Toolchain

1.  Clone the OSXCross repository:
    ```bash
    git clone https://github.com/tpoechtrager/osxcross
    cd osxcross
    ```

2.  Copy your SDK file (e.g., `MacOSX13.3.sdk.tar.xz`) into the `tarballs/` directory:
    ```bash
    cp ~/MacOSX13.3.sdk.tar.xz tarballs/
    ```

3.  Run the build script:
    ```bash
    ./build.sh
    ```

    When prompted:
    > Use lipo from cctools instead of llvm-lipo to improve compatibility?

    Answer **Yes** (`Y`) to ensure better stability.

### 3. Configure PATH

After the build finishes, add the `target/bin` directory to your PATH.

**Temporary (Current Session):**
```bash
export PATH="/path/to/osxcross/target/bin:$PATH"
```

**Permanent (Bash/Zsh):**
Add this to your shell configuration (e.g., `~/.bashrc` or `~/.zshrc`):

```bash
export PATH="/path/to/osxcross/target/bin:$PATH"
```

---

## ⚠️ Critical Warning: Environment Variables

> [!WARNING]
> Simply adding OSXCross to your PATH is **NOT** enough for Cargo to work.

Cargo (and specifically crates like `ring` that contain C code) needs to know exactly which compiler and linker to use. If you just run `cargo build --target aarch64-apple-darwin`, it will default to your system's `cc` (Linux GCC) and fail with errors like:

```text
cc: error: unrecognized command-line option '-mmacosx-version-min=11.0'
```

### The Fix: Explicit Environment Variables

You must set specific environment variables to point Cargo to the OSXCross tools. Our build script (`scripts/build/host/build-single-platform.sh`) handles this automatically, but here is what it does under the hood:

```bash
# Example for Apple Silicon (arm64)
export CC_aarch64_apple_darwin="aarch64-apple-darwin22-clang"
export CXX_aarch64_apple_darwin="aarch64-apple-darwin22-clang++"
export AR_aarch64_apple_darwin="aarch64-apple-darwin22-ar"
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="aarch64-apple-darwin22-clang"
```

**Why use `clang` as the linker?**
On macOS, it is strongly recommended to link via the compiler driver (`clang`) rather than calling the linker (`ld`) directly. Clang automatically handles the complex system paths, library paths, and framework flags required for macOS binaries.

---

## 🚀 Building with the Script

We strongly recommend using the provided build script, which sets up all the necessary environment variables for you.

```bash
./scripts/build/host/build-single-platform.sh macos-arm64
# OR
./scripts/build/host/build-single-platform.sh macos-x86_64
```

This script will:
1.  Set the correct `CC`, `CXX`, `AR`, and `LINKER` variables.
2.  Build the binary for the specified architecture.