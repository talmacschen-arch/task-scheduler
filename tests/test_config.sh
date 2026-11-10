#!/bin/bash
#=============================================================================
# test_config.sh - config 模块测试
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TEST_DIR="${PROJECT_DIR}/tests/tmp_config_test"

# 清理
rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}"

# 加载 config 模块
source "${PROJECT_DIR}/lib/config.sh"

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
echo "=== Test 1: 正常配置文件解析 ==="
# ========================================
cat > "${TEST_DIR}/normal.conf" << 'EOF'
# 注释行
30 2 * * *  backup_test  /opt/scripts/backup_test.sh
0  8 * * 1  perf_test    /opt/scripts/perf_test.py

chain daily_check
  0 6 * * *  func_test_1  /opt/scripts/func_test_1.sh
  >>         func_test_2  /opt/scripts/func_test_2.sh
  >>         func_test_3  /opt/scripts/func_test_3.py
end
EOF

config_load "${TEST_DIR}/normal.conf"
assert_eq "load returns 0" "0" "$?"

# 验证任务数量
task_count=$(config_get_tasks | wc -l)
assert_eq "total 5 tasks" "5" "${task_count}"

# 验证独立任务
task_info=$(config_get_task "backup_test")
assert_eq "backup_test info" "backup_test|30 2 * * *|/opt/scripts/backup_test.sh|" "${task_info}"

task_info=$(config_get_task "perf_test")
assert_eq "perf_test info" "perf_test|0 8 * * 1|/opt/scripts/perf_test.py|" "${task_info}"

# 验证链任务
task_info=$(config_get_task "func_test_1")
assert_eq "chain first task" "func_test_1|0 6 * * *|/opt/scripts/func_test_1.sh|daily_check" "${task_info}"

task_info=$(config_get_task "func_test_2")
assert_eq "chain follow task" "func_test_2|chain_follow|/opt/scripts/func_test_2.sh|daily_check" "${task_info}"

# 验证任务链
chain_info=$(config_get_chain "daily_check")
assert_eq "chain info" "daily_check|func_test_1,func_test_2,func_test_3|stop" "${chain_info}"

# ========================================
echo ""
echo "=== Test 2: config_get_schedulable ==="
# ========================================
schedulable=$(config_get_schedulable)
sched_count=$(echo "${schedulable}" | wc -l)
assert_eq "3 schedulable entries" "3" "${sched_count}"
assert_contains "has backup_test" "${schedulable}" "backup_test"
assert_contains "has perf_test" "${schedulable}" "perf_test"
assert_contains "has func_test_1 (chain head)" "${schedulable}" "func_test_1"

# 确认 chain_follow 任务不在 schedulable 里
if echo "${schedulable}" | grep -q "chain_follow"; then
    echo "  FAIL: chain_follow tasks should not be schedulable"
    (( FAIL++ ))
else
    echo "  PASS: chain_follow excluded from schedulable"
    (( PASS++ ))
fi

# ========================================
echo ""
echo "=== Test 3: config_get_task 查找不存在的任务 ==="
# ========================================
config_get_task "nonexistent" > /dev/null 2>&1
assert_eq "nonexistent returns 1" "1" "$?"

# ========================================
echo ""
echo "=== Test 4: cron字段验证 ==="
# ========================================

# 有效的 cron 字段
cat > "${TEST_DIR}/cron_valid.conf" << 'EOF'
*/5 0-23 1,15 * 0-6  test_cron  /opt/scripts/test.sh
EOF
config_load "${TEST_DIR}/cron_valid.conf"
assert_eq "valid cron fields accepted" "0" "$?"

# 无效的 cron 字段
cat > "${TEST_DIR}/cron_invalid.conf" << 'EOF'
abc 2 * * *  bad_task  /opt/scripts/test.sh
EOF
config_load "${TEST_DIR}/cron_invalid.conf" 2>/dev/null
assert_eq "invalid cron rejected" "1" "$?"

# ========================================
echo ""
echo "=== Test 5: 错误处理 ==="
# ========================================

# 文件不存在
config_load "/nonexistent/file" 2>/dev/null
assert_eq "missing file returns 1" "1" "$?"

# 未关闭的 chain
cat > "${TEST_DIR}/unclosed.conf" << 'EOF'
chain broken
  0 6 * * *  task1  /opt/scripts/task1.sh
EOF
config_load "${TEST_DIR}/unclosed.conf" 2>/dev/null
assert_eq "unclosed chain returns 1" "1" "$?"

# 不完整的任务定义
cat > "${TEST_DIR}/incomplete.conf" << 'EOF'
30 2 * * *  only_name
EOF
config_load "${TEST_DIR}/incomplete.conf" 2>/dev/null
assert_eq "incomplete task returns 1" "1" "$?"

# chain 内不完整的 >> 行
cat > "${TEST_DIR}/incomplete_chain.conf" << 'EOF'
chain test
  0 6 * * *  task1  /opt/scripts/task1.sh
  >>         task2
end
EOF
config_load "${TEST_DIR}/incomplete_chain.conf" 2>/dev/null
assert_eq "incomplete chain task returns 1" "1" "$?"

# ========================================
echo ""
echo "=== Test 6: config_dump ==="
# ========================================
config_load "${TEST_DIR}/normal.conf"
dump_output=$(config_dump)
assert_contains "dump shows tasks" "${dump_output}" "Tasks (5)"
assert_contains "dump shows chains" "${dump_output}" "Chains (1)"

echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==========================================="

# 清理
rm -rf "${TEST_DIR}"

exit ${FAIL}
