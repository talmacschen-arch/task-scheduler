#!/bin/bash
#=============================================================================
# test_chain.sh - chain 模块测试
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TEST_DIR="${PROJECT_DIR}/tests/tmp_chain_test"

# 清理
rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}/scripts" "${TEST_DIR}/logs"

# 加载模块
source "${PROJECT_DIR}/lib/logger.sh"
source "${PROJECT_DIR}/lib/config.sh"
source "${PROJECT_DIR}/lib/executor.sh"
source "${PROJECT_DIR}/lib/chain.sh"

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

# ========================================
# 准备测试脚本
# ========================================
cat > "${TEST_DIR}/scripts/step1.sh" << 'EOF'
#!/bin/bash
echo "step1 done"
exit 0
EOF

cat > "${TEST_DIR}/scripts/step2.sh" << 'EOF'
#!/bin/bash
echo "step2 done"
exit 0
EOF

cat > "${TEST_DIR}/scripts/step3.sh" << 'EOF'
#!/bin/bash
echo "step3 done"
exit 0
EOF

cat > "${TEST_DIR}/scripts/step_fail.sh" << 'EOF'
#!/bin/bash
echo "step_fail about to fail"
exit 1
EOF

chmod +x "${TEST_DIR}/scripts/"*.sh

# ========================================
echo "=== Test 1: stop模式 - 全部成功 ==="
# ========================================
cat > "${TEST_DIR}/test.conf" << EOF
chain ok_chain stop_on_failure
  0 0 * * *  step1  ${TEST_DIR}/scripts/step1.sh
  >>         step2  ${TEST_DIR}/scripts/step2.sh
  >>         step3  ${TEST_DIR}/scripts/step3.sh
end
EOF

config_load "${TEST_DIR}/test.conf"
chain_run "ok_chain"
assert_eq "returns 0" "0" "$?"
assert_eq "status SUCCESS" "SUCCESS" "${CHAIN_LAST_STATUS}"
assert_eq "completed 3" "3" "${CHAIN_LAST_COMPLETED}"
assert_eq "no failed tasks" "" "${CHAIN_LAST_FAILED_TASKS}"
assert_eq "skipped 0" "0" "${CHAIN_LAST_SKIPPED}"

# ========================================
echo ""
echo "=== Test 2: stop模式（默认）- 中间失败终止 ==="
# ========================================
cat > "${TEST_DIR}/test.conf" << EOF
chain stop_chain
  0 0 * * *  step1      ${TEST_DIR}/scripts/step1.sh
  >>         step_fail  ${TEST_DIR}/scripts/step_fail.sh
  >>         step3      ${TEST_DIR}/scripts/step3.sh
end
EOF

config_load "${TEST_DIR}/test.conf"
chain_run "stop_chain"
assert_eq "returns 1" "1" "$?"
assert_eq "status FAILED" "FAILED" "${CHAIN_LAST_STATUS}"
assert_eq "completed 1" "1" "${CHAIN_LAST_COMPLETED}"
assert_eq "failed task" "step_fail" "${CHAIN_LAST_FAILED_TASKS}"
assert_eq "skipped 1" "1" "${CHAIN_LAST_SKIPPED}"

# ========================================
echo ""
echo "=== Test 3: continue模式 - 中间失败继续 ==="
# ========================================
cat > "${TEST_DIR}/test.conf" << EOF
chain continue_chain continue_on_failure
  0 0 * * *  step1      ${TEST_DIR}/scripts/step1.sh
  >>         step_fail  ${TEST_DIR}/scripts/step_fail.sh
  >>         step3      ${TEST_DIR}/scripts/step3.sh
end
EOF

config_load "${TEST_DIR}/test.conf"
chain_run "continue_chain"
assert_eq "returns 1 (has failure)" "1" "$?"
assert_eq "status FAILED" "FAILED" "${CHAIN_LAST_STATUS}"
assert_eq "completed 2 (step1+step3)" "2" "${CHAIN_LAST_COMPLETED}"
assert_eq "failed task" "step_fail" "${CHAIN_LAST_FAILED_TASKS}"
assert_eq "skipped 0 (all attempted)" "0" "${CHAIN_LAST_SKIPPED}"

# ========================================
echo ""
echo "=== Test 4: continue模式 - 多个失败 ==="
# ========================================
cat > "${TEST_DIR}/scripts/step_fail2.sh" << 'EOF'
#!/bin/bash
echo "step_fail2 also fails"
exit 2
EOF
chmod +x "${TEST_DIR}/scripts/step_fail2.sh"

cat > "${TEST_DIR}/test.conf" << EOF
chain multi_fail continue_on_failure
  0 0 * * *  step_fail   ${TEST_DIR}/scripts/step_fail.sh
  >>         step2       ${TEST_DIR}/scripts/step2.sh
  >>         step_fail2  ${TEST_DIR}/scripts/step_fail2.sh
end
EOF

config_load "${TEST_DIR}/test.conf"
chain_run "multi_fail"
assert_eq "returns 1" "1" "$?"
assert_eq "completed 1 (only step2)" "1" "${CHAIN_LAST_COMPLETED}"
assert_eq "two failed tasks" "step_fail,step_fail2" "${CHAIN_LAST_FAILED_TASKS}"

# ========================================
echo ""
echo "=== Test 5: continue模式 - 全部成功 ==="
# ========================================
cat > "${TEST_DIR}/test.conf" << EOF
chain all_ok continue_on_failure
  0 0 * * *  step1  ${TEST_DIR}/scripts/step1.sh
  >>         step2  ${TEST_DIR}/scripts/step2.sh
end
EOF

config_load "${TEST_DIR}/test.conf"
chain_run "all_ok"
assert_eq "returns 0" "0" "$?"
assert_eq "status SUCCESS" "SUCCESS" "${CHAIN_LAST_STATUS}"
assert_eq "completed 2" "2" "${CHAIN_LAST_COMPLETED}"

# ========================================
echo ""
echo "=== Test 6: stop模式 - 首个任务失败 ==="
# ========================================
cat > "${TEST_DIR}/test.conf" << EOF
chain first_fail stop_on_failure
  0 0 * * *  step_fail  ${TEST_DIR}/scripts/step_fail.sh
  >>         step2      ${TEST_DIR}/scripts/step2.sh
  >>         step3      ${TEST_DIR}/scripts/step3.sh
end
EOF

config_load "${TEST_DIR}/test.conf"
chain_run "first_fail"
assert_eq "returns 1" "1" "$?"
assert_eq "completed 0" "0" "${CHAIN_LAST_COMPLETED}"
assert_eq "skipped 2" "2" "${CHAIN_LAST_SKIPPED}"

# ========================================
echo ""
echo "=== Test 7: 不存在的链 ==="
# ========================================
chain_run "nonexistent" 2>/dev/null
assert_eq "returns 1" "1" "$?"
assert_eq "status FAILED" "FAILED" "${CHAIN_LAST_STATUS}"

# ========================================
echo ""
echo "=== Test 8: chain_get_status ==="
# ========================================
config_load "${TEST_DIR}/test.conf"
chain_run "first_fail"
status=$(chain_get_status)
assert_eq "get_status format" "FAILED|0|3|step_fail|2" "${status}"

echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==========================================="

# 清理
rm -rf "${TEST_DIR}"

exit ${FAIL}
