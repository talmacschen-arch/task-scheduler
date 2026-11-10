#!/bin/bash
#=============================================================================
# test_executor.sh - executor 模块测试
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TEST_DIR="${PROJECT_DIR}/tests/tmp_executor_test"

# 清理
rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}/scripts" "${TEST_DIR}/logs"

# 加载模块
source "${PROJECT_DIR}/lib/logger.sh"
source "${PROJECT_DIR}/lib/executor.sh"

logger_init "${TEST_DIR}/logs"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        echo "  PASS: ${desc}"
        (( PASS++ ))
    else
        echo "  FAIL: ${desc}"
        echo "    expected: [${expected}]"
        echo "    actual:   [${actual}]"
        (( FAIL++ ))
    fi
}

assert_contains() {
    local desc="$1" file="$2" pattern="$3"
    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        echo "  PASS: ${desc}"
        (( PASS++ ))
    else
        echo "  FAIL: ${desc} (pattern '${pattern}' not in ${file})"
        (( FAIL++ ))
    fi
}

# ========================================
echo "=== Test 1: 成功执行 shell 脚本 ==="
# ========================================
cat > "${TEST_DIR}/scripts/ok.sh" << 'EOF'
#!/bin/bash
echo "hello from shell"
echo "test output line 2"
exit 0
EOF
chmod +x "${TEST_DIR}/scripts/ok.sh"

executor_run "test_ok" "${TEST_DIR}/scripts/ok.sh"
assert_eq "exit code 0" "0" "$?"
assert_eq "LAST_EXIT_CODE is 0" "0" "${EXECUTOR_LAST_EXIT_CODE}"
assert_contains "stdout captured" "${EXECUTOR_LAST_LOG_FILE}" "hello from shell"
assert_contains "log has SUCCESS" "${EXECUTOR_LAST_LOG_FILE}" "Status:   SUCCESS"

# ========================================
echo ""
echo "=== Test 2: 失败的脚本 ==="
# ========================================
cat > "${TEST_DIR}/scripts/fail.sh" << 'EOF'
#!/bin/bash
echo "about to fail"
exit 42
EOF
chmod +x "${TEST_DIR}/scripts/fail.sh"

executor_run "test_fail" "${TEST_DIR}/scripts/fail.sh"
assert_eq "exit code non-zero" "42" "$?"
assert_eq "LAST_EXIT_CODE is 42" "42" "${EXECUTOR_LAST_EXIT_CODE}"
assert_contains "stdout captured" "${EXECUTOR_LAST_LOG_FILE}" "about to fail"
assert_contains "log has FAILED" "${EXECUTOR_LAST_LOG_FILE}" "FAILED (exit code: 42)"

# ========================================
echo ""
echo "=== Test 3: python 脚本 ==="
# ========================================
cat > "${TEST_DIR}/scripts/test.py" << 'EOF'
#!/usr/bin/env python3
import sys
print("hello from python")
print("stderr output", file=sys.stderr)
sys.exit(0)
EOF
chmod +x "${TEST_DIR}/scripts/test.py"

executor_run "test_python" "${TEST_DIR}/scripts/test.py"
assert_eq "python exit code 0" "0" "$?"
assert_contains "python stdout captured" "${EXECUTOR_LAST_LOG_FILE}" "hello from python"
assert_contains "python stderr captured" "${EXECUTOR_LAST_LOG_FILE}" "stderr output"

# ========================================
echo ""
echo "=== Test 4: 无 shebang 的脚本（按扩展名判断）==="
# ========================================
cat > "${TEST_DIR}/scripts/no_shebang.sh" << 'EOF'
echo "no shebang but works"
EOF

executor_run "test_no_shebang" "${TEST_DIR}/scripts/no_shebang.sh"
assert_eq "no shebang exit code 0" "0" "$?"
assert_contains "output captured" "${EXECUTOR_LAST_LOG_FILE}" "no shebang but works"

cat > "${TEST_DIR}/scripts/no_shebang.py" << 'EOF'
print("python no shebang")
EOF

executor_run "test_py_no_shebang" "${TEST_DIR}/scripts/no_shebang.py"
assert_eq "py no shebang exit code 0" "0" "$?"
assert_contains "py output captured" "${EXECUTOR_LAST_LOG_FILE}" "python no shebang"

# ========================================
echo ""
echo "=== Test 5: 超时控制 ==="
# ========================================
cat > "${TEST_DIR}/scripts/slow.sh" << 'EOF'
#!/bin/bash
echo "starting slow task"
sleep 30
echo "should not reach here"
EOF
chmod +x "${TEST_DIR}/scripts/slow.sh"

executor_run "test_timeout" "${TEST_DIR}/scripts/slow.sh" 3
assert_eq "timeout returns 124" "124" "$?"
assert_contains "timeout message in log" "${EXECUTOR_LAST_LOG_FILE}" "TIMEOUT"

# ========================================
echo ""
echo "=== Test 6: 脚本不存在 ==="
# ========================================
executor_run "test_missing" "/nonexistent/script.sh" 2>/dev/null
assert_eq "missing script returns 1" "1" "$?"

# ========================================
echo ""
echo "=== Test 7: 参数缺失 ==="
# ========================================
executor_run "" "" 2>/dev/null
assert_eq "empty args returns 1" "1" "$?"

# ========================================
echo ""
echo "=== Test 8: 日志文件独立 ==="
# ========================================
executor_run "test_ok" "${TEST_DIR}/scripts/ok.sh"
log1="${EXECUTOR_LAST_LOG_FILE}"
sleep 1
executor_run "test_ok" "${TEST_DIR}/scripts/ok.sh"
log2="${EXECUTOR_LAST_LOG_FILE}"

if [[ "${log1}" != "${log2}" ]]; then
    echo "  PASS: each execution has independent log file"
    (( PASS++ ))
else
    echo "  FAIL: log files should be different"
    (( FAIL++ ))
fi

echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==========================================="

# 清理
rm -rf "${TEST_DIR}"

exit ${FAIL}
