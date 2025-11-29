# Windows Cross-Compilation Guide

This document details the intricacies of cross-compiling for Windows from a Linux host, specifically focusing on the toolchain differences between MinGW-GCC and LLVM-MinGW.

## 🧠 Concepts: MinGW vs. LLVM

Understanding the underlying tools is crucial for successful cross-compilation.

- **MinGW (Minimal GNU for Windows)**: A port of the GNU Compiler Collection (GCC) and GNU Binutils (like `ld`) to Windows. It historically relies on `libgcc` for exception handling and stack unwinding.
- **LLVM (Low Level Virtual Machine)**: A modern compiler infrastructure. In this context, we refer to **LLVM-MinGW**, which uses `clang` (compiler) and `lld` (linker) but targets the MinGW runtime.
- **UCRT vs. MSVCRT**:
  - **UCRT (Universal C Runtime)**: The modern, standards-compliant runtime used by Windows 10 and newer. This is what our recommended toolchain (`llvm-mingw-w64-toolchain-ucrt-bin`) uses.
  - **MSVCRT**: The legacy, non-standard runtime from the Visual C++ 6.0 era, traditionally used by older MinGW toolchains.

---

## ⚠️ Critical Warning: Avoid `x86_64-pc-windows-gnu`

> [!WARNING] > **Do NOT use the `x86_64-pc-windows-gnu` target for this project.**

The standard `x86_64-pc-windows-gnu` target relies on the traditional GCC toolchain (GCC, `ld`, etc.). This approach uses older tooling that can result in **undefined behavior** for our specific codebase.

**Known Issues:**

- **Missing Link Sections**: Even when using `#[used]`, embedded `.link_section` attributes may be stripped or not correctly placed in the final binary.
- **Linux vs. Windows**: While this target might appear to work or compile, the resulting binary often behaves incorrectly compared to its Linux counterpart.

---

## 🛠️ The Solution: LLVM-MinGW

The recommended approach is to use the **LLVM-based toolchain**. On why this works, I think this aligns Rust's usage of LLVM with the underlying linker and runtime libraries, preventing the issues seen with the GCC approach.

### Target Specification

To compile via `llvm-mingw` for 64-bit PC, you must use the specific LLVM target:

```bash
rustup target add x86_64-pc-windows-gnullvm
```

### Tooling Requirements

Simply adding the target is not enough. You strictly require the full LLVM tooling suite:

- **Clang**: The C compiler.
- **LLD**: The LLVM linker.

> [!NOTE]
> Most Linux distributions are compiled via GCC. If your distribution is compiled via LLVM (which is possible), all the necessary tooling will already be available. In that case, only installing MinGW will be enough.

---

## 🔬 Technical Deep Dive: The `libunwind` Issue

If you attempt to compile using the GCC MinGW tooling with the LLVM target (or mix them incorrectly), you will encounter specific linker errors.

### The Error

Running `cargo build` with only GCC MinGW tooling installed results in:

```text
/usr/bin/x86_64-w64-mingw32-ld: cannot find -lunwind: No such file or directory
```

### The Explanation

1.  **`-l` Flag**: This flag tells the linker to search for a library.
2.  **`libunwind`**: This is the "Stack Unwinder." It is a low-level system library responsible for managing the program's call stack during exceptions or debugging.
3.  **GCC vs. LLVM Implementation**:
    - **GCC** uses `libgcc_s` or `libgcc_eh` for this functionality.
    - **LLVM** relies on `libunwind`.

**The Conflict**: The GCC linker (`/usr/bin/x86_64-w64-mingw32-ld`) looks for its own libraries and does not have or understand `libunwind`. Since the Rust `gnullvm` target expects `libunwind`, the build fails.

---

## 📦 Static Linking: The `libunwind.dll` Fix

Even with the correct toolchain, you may encounter a runtime error on the target Windows machine:

> "The code execution cannot proceed because libunwind.dll was not found."

### The Cause

By default, the `x86_64-pc-windows-gnullvm` target may dynamically link the C runtime. This means the binary expects `libunwind.dll` (and potentially other MinGW runtime DLLs) to be present on the system. Since standard Windows installations do not have LLVM-MinGW libraries, the binary fails to run.

### The Fix: `crt-static`

To resolve this, we must force **static linking** of the C runtime. This bundles the necessary runtime code (including `libunwind`) directly into the executable.

We achieve this by setting the `RUSTFLAGS` environment variable during the build:

```bash
export RUSTFLAGS="-C target-feature=+crt-static"
```

### When to use it?

**1. Cross-Compile (Linux Host)**

- **Toolchain**: `gnullvm`
- **Flag Needed?**: **YES**
- **Why?**: The target Windows system does not have the LLVM-MinGW runtime DLLs (`libunwind.dll`). We must bundle them.

**2. Native Build (Windows Host)**

- **Toolchain**: `msvc`
- **Flag Needed?**: **NO**
- **Why?**: The MSVC toolchain links against the standard Windows runtime (UCRT/MSVCRT), which is already present on Windows. Static linking is optional but not required for basic functionality.

> [!IMPORTANT]
> Our build scripts automatically handle this distinction. They apply `crt-static` only when cross-compiling from Linux to Windows.

---

## 🚀 Installation Guide (Arch Linux)

To set up a working environment on Arch Linux, we recommend using the pre-compiled UCRT (Universal C Runtime) toolchain.

### Recommended Package

Install the pre-compiled binary from the AUR. This avoids the long compilation time of the source package.

- **Recommended**: `aur/llvm-mingw-w64-toolchain-ucrt-bin`
- _Alternative (Slow)_: `aur/llvm-mingw` (compiles everything from source)

### Configuration

The `llvm-mingw-w64-toolchain-ucrt-bin` package installs binaries to a specific location that might not be in your standard PATH.

1.  **Locate Binaries**: `/opt/llvm-mingw/llvm-mingw-ucrt/bin`
2.  **Update PATH**: Add this directory to your system PATH.

**Temporary (Current Session):**

```bash
export PATH="/opt/llvm-mingw/llvm-mingw-ucrt/bin:$PATH"
```

**Permanent (Bash/Zsh):**
To make this change persist across reboots, add it to your shell configuration (e.g., `~/.bashrc` or `~/.zshrc`).

```bash
# For Bash
echo 'export PATH="/opt/llvm-mingw/llvm-mingw-ucrt/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# For Zsh
echo 'export PATH="/opt/llvm-mingw/llvm-mingw-ucrt/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

> [!TIP] > **Linker Verification**: If you look in `/opt/llvm-mingw/llvm-mingw-ucrt/bin`, you will see `x86_64-w64-mingw32-ld`. **Do not panic.** This is NOT the GCC linker. It is a symlink to `ld-wrapper.sh`, which `clang` uses to invoke `lld` (the LLVM linker).

Once configured, you are ready to compile this project for Windows on Linux.
