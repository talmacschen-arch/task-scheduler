#!/bin/bash
#=============================================================================
# test_scheduler.sh - scheduler 模块集成测试
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TEST_DIR="${PROJECT_DIR}/tests/tmp_scheduler_test"

# 清理
rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}/scripts" "${TEST_DIR}/logs" "${TEST_DIR}/run" "${TEST_DIR}/lib"

# 复制所有 lib 文件到测试目录
cp "${PROJECT_DIR}/lib/"* "${TEST_DIR}/lib/"

# 加载 scheduler 模块
source "${TEST_DIR}/lib/scheduler.sh"

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

# ========================================
# 准备测试脚本
# ========================================
cat > "${TEST_DIR}/scripts/hello.sh" << 'EOF'
#!/bin/bash
echo "hello from scheduler test"
echo "time: $(date '+%Y-%m-%d %H:%M:%S')"
EOF
chmod +x "${TEST_DIR}/scripts/hello.sh"

cat > "${TEST_DIR}/scripts/step1.sh" << 'EOF'
#!/bin/bash
echo "chain step1"
EOF

cat > "${TEST_DIR}/scripts/step2.sh" << 'EOF'
#!/bin/bash
echo "chain step2"
EOF
chmod +x "${TEST_DIR}/scripts/"*.sh

# ========================================
echo "=== Test 1: scheduler_init ==="
# ========================================
scheduler_init "${TEST_DIR}"
assert_eq "init returns 0" "0" "$?"

if [[ -d "${TEST_DIR}/run" ]]; then
    echo "  PASS: run directory exists"
    (( PASS++ ))
else
    echo "  FAIL: run directory not created"
    (( FAIL++ ))
fi

# ========================================
echo ""
echo "=== Test 2: scheduler_run_task (手动触发独立任务) ==="
# ========================================
cat > "${TEST_DIR}/test.conf" << EOF
* * * * *  hello  ${TEST_DIR}/scripts/hello.sh

chain mychain
  * * * * *  step1  ${TEST_DIR}/scripts/step1.sh
  >>         step2  ${TEST_DIR}/scripts/step2.sh
end
EOF

config_load "${TEST_DIR}/test.conf"

scheduler_run_task "hello"
assert_eq "manual run returns 0" "0" "$?"
assert_eq "exit code 0" "0" "${EXECUTOR_LAST_EXIT_CODE}"

# 检查日志文件是否生成
if [[ -f "${EXECUTOR_LAST_LOG_FILE}" ]]; then
    echo "  PASS: task log created"
    (( PASS++ ))
else
    echo "  FAIL: task log not created"
    (( FAIL++ ))
fi

# ========================================
echo ""
echo "=== Test 3: scheduler_run_task (手动触发链任务) ==="
# ========================================
scheduler_run_task "step1"
assert_eq "chain trigger returns 0" "0" "$?"
assert_eq "chain completed" "SUCCESS" "${CHAIN_LAST_STATUS}"
assert_eq "chain completed 2/2" "2" "${CHAIN_LAST_COMPLETED}"

# ========================================
echo ""
echo "=== Test 4: scheduler_run_task (任务不存在) ==="
# ========================================
result=$(scheduler_run_task "nonexistent" 2>&1)
assert_eq "returns 1" "1" "$?"
assert_contains "error msg" "${result}" "not found"

# ========================================
echo ""
echo "=== Test 5: daemon 启动/状态/停止 ==="
# ========================================

# 配置一个不会立即触发的任务（避免测试中执行脚本）
cat > "${TEST_DIR}/daemon_test.conf" << EOF
0 0 1 1 *  rare_task  ${TEST_DIR}/scripts/hello.sh
EOF

config_load "${TEST_DIR}/daemon_test.conf"

# 启动 daemon
scheduler_start "${TEST_DIR}/daemon_test.conf" "daemon"
assert_eq "start returns 0" "0" "$?"

# 检查 PID 文件
if [[ -f "${SCHEDULER_PID_FILE}" ]]; then
    echo "  PASS: PID file created"
    (( PASS++ ))
else
    echo "  FAIL: PID file not created"
    (( FAIL++ ))
fi

# 检查状态
scheduler_is_running
assert_eq "is_running returns 0" "0" "$?"

status_output=$(scheduler_status)
assert_contains "status shows running" "${status_output}" "running"

# 重复启动应失败
scheduler_start "${TEST_DIR}/daemon_test.conf" "daemon" 2>/dev/null
assert_eq "duplicate start returns 1" "1" "$?"

# 停止 daemon
scheduler_stop
assert_eq "stop returns 0" "0" "$?"

# 确认已停止
scheduler_is_running
assert_eq "is_running returns 1 after stop" "1" "$?"

# PID 文件应被清理
if [[ ! -f "${SCHEDULER_PID_FILE}" ]]; then
    echo "  PASS: PID file cleaned up"
    (( PASS++ ))
else
    echo "  FAIL: PID file still exists"
    (( FAIL++ ))
fi

# ========================================
echo ""
echo "=== Test 6: 停止未运行的 scheduler ==="
# ========================================
scheduler_stop 2>/dev/null
assert_eq "stop not-running returns 1" "1" "$?"

echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==========================================="

# 清理
rm -rf "${TEST_DIR}"

exit ${FAIL}
