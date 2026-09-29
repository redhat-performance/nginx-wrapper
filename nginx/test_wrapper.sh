#!/bin/bash
#
# Smoke test for nginx wrapper reexec and temp file handling
# Verifies fixes for issue #3 (argument preservation, mktemp usage, cleanup)
#

set -euo pipefail

# Resolve script directory before changing directories
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

TEST_DIR=$(mktemp -d /tmp/nginx_test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "  ✓ $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "  ✗ $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "=== Nginx Wrapper Smoke Tests ==="
echo

# Test 1: Arguments with spaces are preserved
echo "Test 1: Arguments with spaces preserved"
# Create minimal test wrapper mimicking the pattern
cat > "$TEST_DIR/test_wrapper.sh" << 'EOF'
#!/bin/bash
if [ "${NGINX_WRAPPER_REEXEC:-0}" != "1" ]; then
    log_file=$(mktemp /tmp/nginx.XXXXXX.out) || exit 1
    trap 'rm -f "$log_file"' EXIT
    NGINX_WRAPPER_REEXEC=1 "$0" "$@" &> "$log_file"
    rtc=$?
    cat "$log_file"
    exit $rtc
fi
echo "ARGS: $#"
for arg in "$@"; do echo "[$arg]"; done
EOF
chmod +x "$TEST_DIR/test_wrapper.sh"

output=$("$TEST_DIR/test_wrapper.sh" --opt "value with spaces" --flag "more spaces")
if echo "$output" | grep -q "\[value with spaces\]" && echo "$output" | grep -q "\[more spaces\]"; then
    pass "Arguments with spaces preserved correctly"
else
    fail "Arguments with spaces not preserved"
fi

# Test 2: Glob characters not expanded
echo "Test 2: Glob characters not expanded"
cd "$TEST_DIR"
touch file1.txt file2.txt
output=$("$TEST_DIR/test_wrapper.sh" --pattern "*.txt")
if echo "$output" | grep -q "\[\*\.txt\]"; then
    pass "Glob characters preserved (not expanded)"
else
    fail "Glob characters were expanded"
fi

# Test 3: Stale /tmp/nginx.out doesn't affect behavior
echo "Test 3: Stale temp files don't affect wrapper"
echo "stale content" > /tmp/nginx.out
output=$("$TEST_DIR/test_wrapper.sh" --test "new run")
if echo "$output" | grep -q "ARGS:"; then
    pass "Wrapper executes despite stale /tmp/nginx.out"
else
    fail "Wrapper affected by stale file"
fi
rm -f /tmp/nginx.out

# Test 4: Temp files cleaned up after normal exit
echo "Test 4: Temp file cleanup on normal exit"
temp_count_before=$(shopt -s nullglob; files=(/tmp/nginx.*.out); echo ${#files[@]})
"$TEST_DIR/test_wrapper.sh" --test "cleanup" > /dev/null
temp_count_after=$(shopt -s nullglob; files=(/tmp/nginx.*.out); echo ${#files[@]})
if [ "$temp_count_before" -eq "$temp_count_after" ]; then
    pass "Temp files cleaned up on normal exit"
else
    fail "Temp files not cleaned up (before: $temp_count_before, after: $temp_count_after)"
fi

# Test 5: Re-entry prevention with environment variable
echo "Test 5: Re-entry prevented by environment check"
cat > "$TEST_DIR/reentry_test.sh" << 'EOF'
#!/bin/bash
if [ "${NGINX_WRAPPER_REEXEC:-0}" != "1" ]; then
    echo "FIRST_ENTRY"
    NGINX_WRAPPER_REEXEC=1 "$0" "$@"
    exit $?
fi
echo "SECOND_ENTRY"
EOF
chmod +x "$TEST_DIR/reentry_test.sh"
output=$("$TEST_DIR/reentry_test.sh")
if echo "$output" | grep -q "FIRST_ENTRY" && echo "$output" | grep -q "SECOND_ENTRY"; then
    first_count=$(echo "$output" | grep -c "FIRST_ENTRY")
    if [ "$first_count" -eq 1 ]; then
        pass "Re-entry prevention works correctly"
    else
        fail "Re-entry happened multiple times"
    fi
else
    fail "Re-entry mechanism broken"
fi

# Test 6: Pre-set NGINX_WRAPPER_REEXEC=something doesn't skip wrapper
echo "Test 6: Pre-set environment variable handled correctly"
output=$(NGINX_WRAPPER_REEXEC=garbage "$TEST_DIR/reentry_test.sh")
if echo "$output" | grep -q "FIRST_ENTRY" && echo "$output" | grep -q "SECOND_ENTRY"; then
    pass "Non-'1' value correctly enters wrapper (doesn't skip)"
else
    fail "Pre-set non-'1' environment variable incorrectly skipped wrapper"
fi

# Test 7: mktemp failure handling
echo "Test 7: mktemp failure handling"
cat > "$TEST_DIR/test_mktemp_fail.sh" << 'EOF'
#!/bin/bash
exit_out() { echo "$1"; exit "$2"; }
if [ "${NGINX_WRAPPER_REEXEC:-0}" != "1" ]; then
    # Simulate mktemp failure by using a function that always fails
    mktemp() { return 1; }
    log_file=$(mktemp /tmp/nginx.XXXXXX.out) || exit_out "Failed to create temp log file" 1
    echo "Should not reach here"
fi
echo "SECOND_ENTRY"
EOF
chmod +x "$TEST_DIR/test_mktemp_fail.sh"
output=$("$TEST_DIR/test_mktemp_fail.sh" 2>&1 || true)
if echo "$output" | grep -q "Failed to create temp log file"; then
    pass "mktemp failure triggers error message"
else
    fail "mktemp failure not handled correctly"
fi
if ! echo "$output" | grep -q "SECOND_ENTRY"; then
    pass "Script exits on mktemp failure (doesn't continue)"
else
    fail "Script continued after mktemp failure"
fi

# Test 8: EXIT trap cleanup verification
echo "Test 8: EXIT trap cleanup verification"
cat > "$TEST_DIR/test_trap.sh" << 'EOF'
#!/bin/bash
if [ "${NGINX_WRAPPER_REEXEC:-0}" != "1" ]; then
    log_file=$(mktemp /tmp/nginx.XXXXXX.out) || exit 1
    trap 'rm -f "$log_file"; echo "CLEANUP:$log_file" >&2' EXIT
    NGINX_WRAPPER_REEXEC=1 "$0" "$@" &> "$log_file"
    rtc=$?
    cat "$log_file"
    exit $rtc
fi
echo "SUCCESS"
EOF
chmod +x "$TEST_DIR/test_trap.sh"
output=$("$TEST_DIR/test_trap.sh" 2>&1)
if echo "$output" | grep -q "CLEANUP:/tmp/nginx\."; then
    pass "EXIT trap executes on normal exit"
else
    fail "EXIT trap did not execute"
fi
# Verify the temp file was actually deleted
temp_file=$(echo "$output" | grep "CLEANUP:" | cut -d: -f2)
if [ -n "$temp_file" ] && [ ! -f "$temp_file" ]; then
    pass "EXIT trap successfully deleted temp file"
else
    fail "EXIT trap did not delete temp file"
fi

# Test 9: Actual wrapper validation
echo "Test 9: Actual wrapper validation"
WRAPPER_SCRIPT="$SCRIPT_DIR/run_nginx.sh"

# Subtest 7a: Syntax validation
if bash -n "$WRAPPER_SCRIPT" 2>/dev/null; then
    pass "bash -n passes on actual script"
else
    fail "Syntax errors in actual script"
fi

# Subtest 7b: Verify actual wrapper uses correct patterns
wrapper_content=$(cat "$WRAPPER_SCRIPT")
if echo "$wrapper_content" | grep -q 'if \[ "\${NGINX_WRAPPER_REEXEC:-0}" != "1" \]; then'; then
    pass "Wrapper uses strict re-entry check"
else
    fail "Wrapper missing strict re-entry check"
fi

if echo "$wrapper_content" | grep -q 'NGINX_WRAPPER_REEXEC=1 "\$0" "\$@"'; then
    pass "Wrapper uses quoted reexec pattern"
else
    fail "Wrapper missing quoted reexec pattern"
fi

if echo "$wrapper_content" | grep -q 'mktemp.*|| exit_out'; then
    pass "Wrapper has mktemp error handling"
else
    fail "Wrapper missing mktemp error handling"
fi

if echo "$wrapper_content" | grep -q "trap.*EXIT" && ! echo "$wrapper_content" | grep -q "trap.*INT.*TERM"; then
    pass "Wrapper uses EXIT-only trap"
else
    fail "Wrapper trap pattern incorrect"
fi

echo
echo "=== Test Summary ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo

if [ $TESTS_FAILED -eq 0 ]; then
    echo "All tests passed ✓"
    exit 0
else
    echo "Some tests failed ✗"
    exit 1
fi
