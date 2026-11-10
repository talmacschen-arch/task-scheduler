#!/bin/bash
#=============================================================================
# test_logger.sh - logger 模块测试
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TEST_LOG_DIR="${PROJECT_DIR}/logs_test"

# 清理测试环境
rm -rf "${TEST_LOG_DIR}"

# 加载 logger 模块
source "${PROJECT_DIR}/lib/logger.sh"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        echo "  PASS: ${desc}"
        (( PASS++ ))
    else
        echo "  FAIL: ${desc}"
        echo "    expected: ${expected}"
        echo "    actual:   ${actual}"
        (( FAIL++ ))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [[ -f "${file}" ]]; then
        echo "  PASS: ${desc}"
        (( PASS++ ))
    else
        echo "  FAIL: ${desc} (file not found: ${file})"
        (( FAIL++ ))
    fi
}

assert_contains() {
    local desc="$1" file="$2" pattern="$3"
    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        echo "  PASS: ${desc}"
        (( PASS++ ))
    else
        echo "  FAIL: ${desc} (pattern '${pattern}' not found in ${file})"
        (( FAIL++ ))
    fi
}

echo "=== Test 1: logger_init ==="
logger_init "${TEST_LOG_DIR}"
assert_eq "init returns 0" "0" "$?"
if [[ -d "${TEST_LOG_DIR}/tasks" ]]; then
    echo "  PASS: tasks dir created"
    (( PASS++ ))
else
    echo "  FAIL: tasks dir not created"
    (( FAIL++ ))
fi

echo ""
echo "=== Test 2: log functions ==="
log_info "test info message"
log_warn "test warn message"
log_error "test error message"
assert_file_exists "scheduler.log created" "${TEST_LOG_DIR}/scheduler.log"
assert_contains "info logged" "${TEST_LOG_DIR}/scheduler.log" "\\[INFO\\] test info message"
assert_contains "warn logged" "${TEST_LOG_DIR}/scheduler.log" "\\[WARN\\] test warn message"
assert_contains "error logged" "${TEST_LOG_DIR}/scheduler.log" "\\[ERROR\\] test error message"

echo ""
echo "=== Test 3: task_log_create ==="
log_file=$(task_log_create "db_func_test")
assert_eq "create returns 0" "0" "$?"
assert_file_exists "task log file created" "${log_file}"
assert_contains "header has task name" "${log_file}" "Task: db_func_test"

echo ""
echo "=== Test 4: task_log_finish ==="
start_ts=$(date '+%s')
sleep 1
task_log_finish "${log_file}" 0 "${start_ts}"
assert_contains "has SUCCESS status" "${log_file}" "Status:   SUCCESS"
assert_contains "has duration" "${log_file}" "Duration:"

# 测试失败状态
log_file2=$(task_log_create "db_perf_test")
start_ts2=$(date '+%s')
task_log_finish "${log_file2}" 1 "${start_ts2}"
assert_contains "has FAILED status" "${log_file2}" "Status:   FAILED (exit code: 1)"

echo ""
echo "=== Test 5: task_log_cleanup ==="
# 创建一个"过期"日志文件（修改时间设为40天前）
old_task_dir="${TEST_LOG_DIR}/tasks/old_task"
mkdir -p "${old_task_dir}"
touch -d "40 days ago" "${old_task_dir}/20260201_120000.log"
# 创建一个正常日志文件
new_task_dir="${TEST_LOG_DIR}/tasks/new_task"
mkdir -p "${new_task_dir}"
echo "recent log" > "${new_task_dir}/20260320_120000.log"

task_log_cleanup
assert_eq "cleanup returns 0" "0" "$?"

if [[ ! -f "${old_task_dir}/20260201_120000.log" ]]; then
    echo "  PASS: expired log removed"
    (( PASS++ ))
else
    echo "  FAIL: expired log still exists"
    (( FAIL++ ))
fi

assert_file_exists "recent log kept" "${new_task_dir}/20260320_120000.log"

echo ""
echo "=== Test 6: error handling ==="
# 未初始化时调用
LOG_DIR=""
result=$(task_log_create "test" 2>/dev/null)
assert_eq "create fails without init" "1" "$?"

echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==========================================="

# 清理测试环境
rm -rf "${TEST_LOG_DIR}"

exit ${FAIL}
