#!/bin/bash
#=============================================================================
# test_cron_match.sh - cron_match.py 测试
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
CRON_MATCH="${PROJECT_DIR}/lib/cron_match.py"

PASS=0
FAIL=0

# assert_match: 期望匹配（退出码 0）
assert_match() {
    local desc="$1" cron="$2" time="$3"
    if python3 "${CRON_MATCH}" "${cron}" "${time}"; then
        echo "  PASS: ${desc}"
        (( PASS++ ))
    else
        echo "  FAIL: ${desc} (expected match)"
        (( FAIL++ ))
    fi
}

# assert_no_match: 期望不匹配（退出码 1）
assert_no_match() {
    local desc="$1" cron="$2" time="$3"
    if python3 "${CRON_MATCH}" "${cron}" "${time}"; then
        echo "  FAIL: ${desc} (expected no match)"
        (( FAIL++ ))
    else
        echo "  PASS: ${desc}"
        (( PASS++ ))
    fi
}

# ========================================
echo "=== Test 1: 基本通配符 * ==="
# ========================================
assert_match    "all stars" "* * * * *" "2026-03-20 14:30"
assert_match    "fixed minute" "30 * * * *" "2026-03-20 14:30"
assert_no_match "wrong minute" "31 * * * *" "2026-03-20 14:30"

# ========================================
echo ""
echo "=== Test 2: 固定时间 ==="
# ========================================
assert_match    "exact match" "30 2 20 3 *" "2026-03-20 02:30"
assert_no_match "wrong hour" "30 3 20 3 *" "2026-03-20 02:30"
assert_no_match "wrong day" "30 2 21 3 *" "2026-03-20 02:30"
assert_no_match "wrong month" "30 2 20 4 *" "2026-03-20 02:30"

# ========================================
echo ""
echo "=== Test 3: 步进 */N ==="
# ========================================
assert_match    "*/5 at 0" "*/5 * * * *" "2026-03-20 14:00"
assert_match    "*/5 at 15" "*/5 * * * *" "2026-03-20 14:15"
assert_match    "*/5 at 30" "*/5 * * * *" "2026-03-20 14:30"
assert_no_match "*/5 at 31" "*/5 * * * *" "2026-03-20 14:31"
assert_match    "*/6 hour at 0" "0 */6 * * *" "2026-03-20 00:00"
assert_match    "*/6 hour at 6" "0 */6 * * *" "2026-03-20 06:00"
assert_match    "*/6 hour at 12" "0 */6 * * *" "2026-03-20 12:00"

# ========================================
echo ""
echo "=== Test 4: 列表 N,M ==="
# ========================================
assert_match    "1,15 on 1st" "0 0 1,15 * *" "2026-03-01 00:00"
assert_match    "1,15 on 15th" "0 0 1,15 * *" "2026-03-15 00:00"
assert_no_match "1,15 on 10th" "0 0 1,15 * *" "2026-03-10 00:00"

# ========================================
echo ""
echo "=== Test 5: 范围 N-M ==="
# ========================================
assert_match    "1-5 on Mon" "0 8 * * 1-5" "2026-03-16 08:00"   # Monday
assert_match    "1-5 on Fri" "0 8 * * 1-5" "2026-03-20 08:00"   # Friday
assert_no_match "1-5 on Sun" "0 8 * * 1-5" "2026-03-22 08:00"   # Sunday

# ========================================
echo ""
echo "=== Test 6: 星期天 = 0 或 7 ==="
# ========================================
# 2026-03-22 is a Sunday
assert_match "weekday 0 = Sunday" "0 0 * * 0" "2026-03-22 00:00"
assert_match "weekday 7 = Sunday" "0 0 * * 7" "2026-03-22 00:00"

# ========================================
echo ""
echo "=== Test 7: 错误处理 ==="
# ========================================
python3 "${CRON_MATCH}" "bad" 2>/dev/null
if [[ $? -eq 2 ]]; then
    echo "  PASS: invalid expr returns 2"
    (( PASS++ ))
else
    echo "  FAIL: invalid expr should return 2"
    (( FAIL++ ))
fi

python3 "${CRON_MATCH}" "* * * * *" "bad-time" 2>/dev/null
if [[ $? -eq 2 ]]; then
    echo "  PASS: invalid time returns 2"
    (( PASS++ ))
else
    echo "  FAIL: invalid time should return 2"
    (( FAIL++ ))
fi

echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==========================================="

exit ${FAIL}
