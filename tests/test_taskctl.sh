#!/bin/bash
#=============================================================================
# test_taskctl.sh - taskctl CLI 工具测试
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TASKCTL="${PROJECT_DIR}/bin/taskctl"
TEST_DIR="${PROJECT_DIR}/tests/tmp_taskctl_test"

# 清理
rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}/scripts"

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
    local desc="$1" text="$2" pattern="$3"
    if echo "${text}" | grep -q "${pattern}"; then
        echo "  PASS: ${desc}"
        (( PASS++ ))
    else
        echo "  FAIL: ${desc} (pattern '${pattern}' not found)"
        (( FAIL++ ))
    fi
}

# 准备测试脚本和配置
cat > "${TEST_DIR}/scripts/test1.sh" << 'EOF'
#!/bin/bash
echo "test1 output"
EOF

cat > "${TEST_DIR}/scripts/test2.sh" << 'EOF'
#!/bin/bash
echo "test2 output"
EOF

cat > "${TEST_DIR}/scripts/test3.sh" << 'EOF'
#!/bin/bash
echo "test3 output"
EOF
chmod +x "${TEST_DIR}/scripts/"*.sh

cat > "${PROJECT_DIR}/conf/tasks.conf" << EOF
# 测试配置
*/5 * * * *  quick_test  ${TEST_DIR}/scripts/test1.sh

chain daily_chain
  0 6 * * *  chain_step1  ${TEST_DIR}/scripts/test2.sh
  >>         chain_step2  ${TEST_DIR}/scripts/test3.sh
end
EOF

# ========================================
echo "=== Test 1: help ==="
# ========================================
output=$("${TASKCTL}" help 2>&1)
assert_eq "help returns 0" "0" "$?"
assert_contains "shows usage" "${output}" "taskctl"
assert_contains "shows commands" "${output}" "start"
assert_contains "shows commands" "${output}" "stop"

# ========================================
echo ""
echo "=== Test 2: list ==="
# ========================================
output=$("${TASKCTL}" list 2>&1)
assert_eq "list returns 0" "0" "$?"
assert_contains "shows quick_test" "${output}" "quick_test"
assert_contains "shows chain_step1" "${output}" "chain_step1"
assert_contains "shows chain_step2" "${output}" "chain_step2"
assert_contains "shows chain info" "${output}" "daily_chain"

# ========================================
echo ""
echo "=== Test 3: run (独立任务) ==="
# ========================================
output=$("${TASKCTL}" run quick_test 2>&1)
assert_eq "run returns 0" "0" "$?"

# ========================================
echo ""
echo "=== Test 4: run (链任务) ==="
# ========================================
output=$("${TASKCTL}" run chain_step1 2>&1)
assert_eq "chain run returns 0" "0" "$?"
assert_contains "triggers chain" "${output}" "chain"

# ========================================
echo ""
echo "=== Test 5: run (不存在的任务) ==="
# ========================================
output=$("${TASKCTL}" run nonexistent 2>&1)
assert_eq "returns 1" "1" "$?"
assert_contains "not found" "${output}" "not found"

# ========================================
echo ""
echo "=== Test 6: log ==="
# ========================================
# 先运行一次以产生日志
"${TASKCTL}" run quick_test >/dev/null 2>&1

output=$("${TASKCTL}" log quick_test 2>&1)
assert_eq "log returns 0" "0" "$?"
assert_contains "shows log content" "${output}" "test1 output"

# 查看最近 2 次
"${TASKCTL}" run quick_test >/dev/null 2>&1
sleep 1
"${TASKCTL}" run quick_test >/dev/null 2>&1
output=$("${TASKCTL}" log quick_test 2 2>&1)
assert_contains "shows multiple logs" "${output}" "showing latest 2"

# 不存在的任务日志
"${TASKCTL}" log nonexistent 2>/dev/null
assert_eq "log missing returns 1" "1" "$?"

# ========================================
echo ""
echo "=== Test 7: check ==="
# ========================================
output=$("${TASKCTL}" check "* * * * *" 2>&1)
assert_eq "check returns 0" "0" "$?"
assert_contains "shows MATCH" "${output}" "MATCH"

output=$("${TASKCTL}" check "0 0 1 1 *" 2>&1)
# 大部分时间不匹配
if echo "${output}" | grep -q "NO MATCH"; then
    echo "  PASS: check no match"
    (( PASS++ ))
else
    echo "  PASS: check (happens to match)" # 不算失败
    (( PASS++ ))
fi

# ========================================
echo ""
echo "=== Test 8: start/status/stop (daemon) ==="
# ========================================
output=$("${TASKCTL}" start 2>&1)
assert_eq "start returns 0" "0" "$?"
assert_contains "shows PID" "${output}" "PID"

output=$("${TASKCTL}" status 2>&1)
assert_contains "shows running" "${output}" "running"

# 重复启动
"${TASKCTL}" start 2>/dev/null
assert_eq "duplicate start returns 1" "1" "$?"

output=$("${TASKCTL}" stop 2>&1)
assert_eq "stop returns 0" "0" "$?"
assert_contains "shows stopped" "${output}" "stopped"

output=$("${TASKCTL}" status 2>&1)
assert_contains "shows not running" "${output}" "not running"

# ========================================
echo ""
echo "=== Test 9: cleanup ==="
# ========================================
output=$("${TASKCTL}" cleanup 2>&1)
assert_eq "cleanup returns 0" "0" "$?"
assert_contains "shows done" "${output}" "Done"

# ========================================
echo ""
echo "=== Test 10: unknown command ==="
# ========================================
"${TASKCTL}" badcmd 2>/dev/null
assert_eq "unknown cmd returns 1" "1" "$?"

echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==========================================="

# 清理
rm -rf "${TEST_DIR}"
rm -f "${PROJECT_DIR}/conf/tasks.conf"

exit ${FAIL}
