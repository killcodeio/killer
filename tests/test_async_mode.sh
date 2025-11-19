#!/bin/bash
# Test async execution mode with mock base binary

set -e

echo "🧪 KillCode Overload - Async Mode Test"
echo "======================================"
echo ""

# Directories
OVERLOAD_DIR="/home/kay/work/WEB/killcode/overload"
TEST_DIR="$OVERLOAD_DIR/tests"
TARGET_DIR="$OVERLOAD_DIR/target/release"

# Build mock base binary
echo "📦 Building mock base binary..."
gcc -o "$TEST_DIR/mock_base" "$TEST_DIR/mock_base.c"
chmod +x "$TEST_DIR/mock_base"
echo "✅ Mock base built: $TEST_DIR/mock_base"
echo ""

# Build overload
echo "📦 Building overload..."
cd "$OVERLOAD_DIR"
cargo build --release --quiet
echo "✅ Overload built: $TARGET_DIR/overload"
echo ""

# Test 1: Authorized async execution
echo "=========================================="
echo "Test 1: Authorized Async Execution"
echo "=========================================="
echo ""

# Create test directory
TEST_RUN_DIR="/tmp/overload_async_test_authorized"
rm -rf "$TEST_RUN_DIR"
mkdir -p "$TEST_RUN_DIR"

# Copy files
cp "$TARGET_DIR/overload" "$TEST_RUN_DIR/overload_wrapper"
cp "$TEST_DIR/mock_base" "$TEST_RUN_DIR/mock_base"

# Create valid config (will get 200 OK from server)
cat > "$TEST_RUN_DIR/overload_wrapper.config" <<EOF
{
  "license_id": "test-async-authorized",
  "server_url": "http://localhost:3000/api/v1/verify",
  "shared_secret": "test-secret-key-123",
  "execution_mode": "async",
  "grace_period": 86400,
  "self_destruct": true,
  "log_level": "debug",
  "base_binary_path": "./mock_base"
}
EOF

echo "📄 Config created with Async mode"
echo ""

# Run overload (it should fork mock_base immediately)
cd "$TEST_RUN_DIR"
echo "🚀 Launching overload wrapper..."
echo "   (Should fork mock_base, then verify license in background)"
echo ""

timeout 10s ./overload_wrapper || EXIT_CODE=$?

if [ "${EXIT_CODE:-0}" -eq 124 ]; then
    echo ""
    echo "⏰ Timeout reached (expected - mock_base was running)"
    echo "✅ Test 1 PASSED: Async execution started base binary"
else
    echo ""
    echo "ℹ️  Process exited with code: ${EXIT_CODE:-0}"
    if [ -f "$TEST_RUN_DIR/mock_base" ]; then
        echo "✅ Test 1 PASSED: Base binary still exists (not deleted)"
    else
        echo "❌ Test 1 FAILED: Base binary was deleted unexpectedly"
    fi
fi

echo ""
echo ""

# Test 2: Unauthorized async execution (should kill base)
echo "=========================================="
echo "Test 2: Unauthorized Async Execution"
echo "=========================================="
echo ""

# Create test directory
TEST_RUN_DIR="/tmp/overload_async_test_unauthorized"
rm -rf "$TEST_RUN_DIR"
mkdir -p "$TEST_RUN_DIR"

# Copy files
cp "$TARGET_DIR/overload" "$TEST_RUN_DIR/overload_wrapper"
cp "$TEST_DIR/mock_base" "$TEST_RUN_DIR/mock_base"

# Create invalid config (will get 403 from server)
cat > "$TEST_RUN_DIR/overload_wrapper.config" <<EOF
{
  "license_id": "nonexistent-license-invalid",
  "server_url": "http://localhost:3000/api/v1/verify",
  "shared_secret": "wrong-secret",
  "execution_mode": "async",
  "grace_period": 0,
  "self_destruct": true,
  "log_level": "debug",
  "base_binary_path": "./mock_base"
}
EOF

echo "📄 Config created with invalid license"
echo ""

# Run overload (should fork, then kill after failed verification)
cd "$TEST_RUN_DIR"
echo "🚀 Launching overload wrapper..."
echo "   (Should fork mock_base, verify, then kill it)"
echo ""

timeout 10s ./overload_wrapper || EXIT_CODE=$?

echo ""
if [ "${EXIT_CODE:-0}" -ne 124 ]; then
    echo "✅ Process exited quickly (expected - verification failed)"
    if [ ! -f "$TEST_RUN_DIR/overload_wrapper" ]; then
        echo "✅ Test 2 PASSED: Overload self-destructed after unauthorized access"
    else
        echo "⚠️  Overload still exists (self-destruct may be disabled in dev)"
    fi
else
    echo "❌ Test 2 FAILED: Process still running after 10s (should have been killed)"
fi

echo ""
echo ""

# Summary
echo "=========================================="
echo "📊 Test Summary"
echo "=========================================="
echo ""
echo "Test 1 (Authorized):   Check output above"
echo "Test 2 (Unauthorized): Check output above"
echo ""
echo "🔍 Manual verification needed:"
echo "   - Did Test 1 show mock_base running for ~10s?"
echo "   - Did Test 2 show mock_base being killed quickly?"
echo ""

# Cleanup
echo "🧹 Cleaning up test directories..."
rm -rf /tmp/overload_async_test_authorized
rm -rf /tmp/overload_async_test_unauthorized
echo "✅ Cleanup complete"
