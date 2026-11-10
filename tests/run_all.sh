#!/bin/bash
#=============================================================================
# run_all.sh - 运行所有模块测试
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_MODULES=""

run_test() {
    local name="$1"
    local script="$2"

    echo "=== ${name} ==="
    local output
    output=$(bash "${script}" 2>/dev/null)
    local rc=$?

    # 提取通过/失败数
    local pass fail
    pass=$(echo "${output}" | grep "^Results:" | grep -o '[0-9]* passed' | grep -o '[0-9]*')
    fail=$(echo "${output}" | grep "^Results:" | grep -o '[0-9]* failed' | grep -o '[0-9]*')
    pass=${pass:-0}
    fail=${fail:-0}

    TOTAL_PASS=$(( TOTAL_PASS + pass ))
    TOTAL_FAIL=$(( TOTAL_FAIL + fail ))

    if [[ ${rc} -eq 0 ]]; then
        echo "  PASSED (${pass} tests)"
    else
        echo "  FAILED (${pass} passed, ${fail} failed)"
        FAILED_MODULES="${FAILED_MODULES} ${name}"
    fi
    echo ""
}

echo ""
echo "========================================"
echo " Task Scheduler - Test Suite"
echo "========================================"
echo ""

run_test "logger"     "${SCRIPT_DIR}/test_logger.sh"
run_test "config"     "${SCRIPT_DIR}/test_config.sh"
run_test "executor"   "${SCRIPT_DIR}/test_executor.sh"
run_test "chain"      "${SCRIPT_DIR}/test_chain.sh"
run_test "cron_match" "${SCRIPT_DIR}/test_cron_match.sh"
run_test "scheduler"  "${SCRIPT_DIR}/test_scheduler.sh"
run_test "taskctl"    "${SCRIPT_DIR}/test_taskctl.sh"

echo "========================================"
echo " Total: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
echo "========================================"

if [[ ${TOTAL_FAIL} -gt 0 ]]; then
    echo " Failed modules:${FAILED_MODULES}"
    exit 1
else
    echo " All tests passed!"
    exit 0
fi
