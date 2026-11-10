#!/bin/bash
#=============================================================================
# executor.sh - 任务执行器模块
#
# 功能：
#   1. 执行 shell 或 python 脚本
#   2. 捕获 stdout/stderr 到日志文件
#   3. 记录退出码和执行耗时
#   4. 支持执行超时控制
#
# 依赖：
#   lib/logger.sh
#
# 用法：
#   source lib/logger.sh
#   source lib/executor.sh
#   logger_init "/path/to/logs"
#   executor_run "task_name" "/path/to/script.sh" [timeout_seconds]
#=============================================================================

# 默认超时时间（秒），0 表示不限制
EXECUTOR_DEFAULT_TIMEOUT=0

# 上一次执行的退出码（供外部查询）
EXECUTOR_LAST_EXIT_CODE=0

# 上一次执行的日志文件路径
EXECUTOR_LAST_LOG_FILE=""

# 当前正在执行的任务 PID（用于外部中断）
EXECUTOR_CURRENT_PID=0

#-----------------------------------------------------------------------------
# executor_run - 执行一个任务脚本
#
# 参数：
#   $1 - 任务名称
#   $2 - 脚本路径
#   $3 - 超时秒数（可选，默认不限制）
#
# 返回：
#   0 - 任务执行成功（脚本退出码为 0）
#   1 - 任务执行失败（脚本退出码非 0、超时、或执行错误）
#-----------------------------------------------------------------------------
executor_run() {
    local task_name="$1"
    local script_path="$2"
    local timeout="${3:-${EXECUTOR_DEFAULT_TIMEOUT}}"

    EXECUTOR_LAST_EXIT_CODE=0
    EXECUTOR_LAST_LOG_FILE=""
    EXECUTOR_CURRENT_PID=0

    # 参数检查
    if [[ -z "${task_name}" || -z "${script_path}" ]]; then
        log_error "executor_run: task_name and script_path are required"
        EXECUTOR_LAST_EXIT_CODE=1
        return 1
    fi

    # 检查脚本是否存在
    if [[ ! -f "${script_path}" ]]; then
        log_error "executor_run: script not found: ${script_path}"
        EXECUTOR_LAST_EXIT_CODE=1
        return 1
    fi

    # 检查脚本是否有执行权限，没有则自动添加
    if [[ ! -x "${script_path}" ]]; then
        chmod +x "${script_path}" 2>/dev/null || {
            log_error "executor_run: cannot set execute permission: ${script_path}"
            EXECUTOR_LAST_EXIT_CODE=1
            return 1
        }
        log_info "executor_run: added execute permission to ${script_path}"
    fi

    # 创建任务日志文件
    local log_file
    log_file=$(task_log_create "${task_name}")
    if [[ $? -ne 0 ]]; then
        log_error "executor_run: failed to create task log"
        EXECUTOR_LAST_EXIT_CODE=1
        return 1
    fi
    EXECUTOR_LAST_LOG_FILE="${log_file}"

    log_info "executor_run: starting task '${task_name}' -> ${script_path}"

    local start_ts
    start_ts=$(date '+%s')

    # 写入运行状态文件，供外部查询
    _executor_write_status "${task_name}" "${script_path}" "${start_ts}"

    # 根据脚本类型选择执行方式
    local interpreter
    interpreter=$(_detect_interpreter "${script_path}")

    local exit_code=0

    if [[ ${timeout} -gt 0 ]]; then
        _run_with_timeout "${interpreter}" "${script_path}" "${log_file}" "${timeout}"
        exit_code=$?
    else
        _run_script "${interpreter}" "${script_path}" "${log_file}"
        exit_code=$?
    fi

    EXECUTOR_CURRENT_PID=0
    EXECUTOR_LAST_EXIT_CODE=${exit_code}

    # 清除运行状态文件
    _executor_clear_status

    # 写入日志尾部
    task_log_finish "${log_file}" "${exit_code}" "${start_ts}"

    local duration=$(( $(date '+%s') - start_ts ))

    if [[ ${exit_code} -eq 0 ]]; then
        log_info "executor_run: task '${task_name}' completed successfully (${duration}s)"
    else
        log_error "executor_run: task '${task_name}' failed with exit code ${exit_code} (${duration}s)"
    fi

    return ${exit_code}
}

#-----------------------------------------------------------------------------
# _detect_interpreter - 检测脚本类型，返回解释器
#
# 参数：
#   $1 - 脚本路径
#
# 输出（stdout）：
#   解释器命令（bash/python3/空）
#-----------------------------------------------------------------------------
_detect_interpreter() {
    local script_path="$1"

    # 先检查 shebang
    local first_line
    first_line=$(head -1 "${script_path}" 2>/dev/null)

    if [[ "${first_line}" == \#!* ]]; then
        # 有 shebang，直接执行
        echo ""
        return
    fi

    # 没有 shebang，根据扩展名判断
    case "${script_path}" in
        *.py)
            echo "python3"
            ;;
        *.sh)
            echo "bash"
            ;;
        *)
            # 默认用 bash
            echo "bash"
            ;;
    esac
}

#-----------------------------------------------------------------------------
# _run_script - 执行脚本（无超时）
#
# 参数：
#   $1 - 解释器（空则直接执行）
#   $2 - 脚本路径
#   $3 - 日志文件路径
#
# 返回：
#   脚本退出码
#-----------------------------------------------------------------------------
_run_script() {
    local interpreter="$1"
    local script_path="$2"
    local log_file="$3"

    if [[ -n "${interpreter}" ]]; then
        ${interpreter} "${script_path}" >> "${log_file}" 2>&1 &
    else
        "${script_path}" >> "${log_file}" 2>&1 &
    fi

    EXECUTOR_CURRENT_PID=$!
    _executor_update_pid ${EXECUTOR_CURRENT_PID}
    wait ${EXECUTOR_CURRENT_PID}
    return $?
}

#-----------------------------------------------------------------------------
# _run_with_timeout - 执行脚本（带超时控制）
#
# 参数：
#   $1 - 解释器（空则直接执行）
#   $2 - 脚本路径
#   $3 - 日志文件路径
#   $4 - 超时秒数
#
# 返回：
#   脚本退出码，超时返回 124
#-----------------------------------------------------------------------------
_run_with_timeout() {
    local interpreter="$1"
    local script_path="$2"
    local log_file="$3"
    local timeout="$4"

    if [[ -n "${interpreter}" ]]; then
        ${interpreter} "${script_path}" >> "${log_file}" 2>&1 &
    else
        "${script_path}" >> "${log_file}" 2>&1 &
    fi

    local pid=$!
    EXECUTOR_CURRENT_PID=${pid}
    _executor_update_pid ${pid}

    # 后台监控超时
    (
        sleep "${timeout}"
        if kill -0 "${pid}" 2>/dev/null; then
            echo "[TIMEOUT] Task killed after ${timeout}s" >> "${log_file}"
            kill -TERM "${pid}" 2>/dev/null
            sleep 2
            kill -9 "${pid}" 2>/dev/null
        fi
    ) &
    local watchdog_pid=$!

    wait ${pid}
    local exit_code=$?

    # 清理 watchdog
    kill "${watchdog_pid}" 2>/dev/null
    wait "${watchdog_pid}" 2>/dev/null

    # 判断是否超时（被 SIGTERM 杀死返回 143）
    if [[ ${exit_code} -eq 143 ]]; then
        return 124
    fi

    return ${exit_code}
}

#-----------------------------------------------------------------------------
# executor_is_running - 检查是否有任务正在执行
#
# 返回：
#   0 - 有任务在执行
#   1 - 无任务在执行
#-----------------------------------------------------------------------------
executor_is_running() {
    if [[ ${EXECUTOR_CURRENT_PID} -ne 0 ]] && kill -0 "${EXECUTOR_CURRENT_PID}" 2>/dev/null; then
        return 0
    fi
    return 1
}

#-----------------------------------------------------------------------------
# executor_stop - 停止当前正在执行的任务
#
# 返回：
#   0 - 已停止或无任务
#   1 - 停止失败
#-----------------------------------------------------------------------------
executor_stop() {
    if ! executor_is_running; then
        return 0
    fi

    log_warn "executor_stop: killing task PID ${EXECUTOR_CURRENT_PID}"
    kill -TERM "${EXECUTOR_CURRENT_PID}" 2>/dev/null
    sleep 2

    if kill -0 "${EXECUTOR_CURRENT_PID}" 2>/dev/null; then
        kill -9 "${EXECUTOR_CURRENT_PID}" 2>/dev/null
        sleep 1
    fi

    if kill -0 "${EXECUTOR_CURRENT_PID}" 2>/dev/null; then
        log_error "executor_stop: failed to kill PID ${EXECUTOR_CURRENT_PID}"
        return 1
    fi

    EXECUTOR_CURRENT_PID=0
    return 0
}

#-----------------------------------------------------------------------------
# _executor_update_pid - 更新状态文件中的 PID
#
# 参数：
#   $1 - 任务进程 PID
#-----------------------------------------------------------------------------
_executor_update_pid() {
    local pid="$1"
    local status_file="${SCHEDULER_BASE_DIR}/run/current_task.info"
    if [[ -f "${status_file}" ]]; then
        sed -i "s/^TASK_PID=.*/TASK_PID=${pid}/" "${status_file}" 2>/dev/null
    fi
}

#-----------------------------------------------------------------------------
# _executor_write_status - 写入当前任务运行状态文件
#
# 参数：
#   $1 - 任务名称
#   $2 - 脚本路径
#   $3 - 开始时间戳
#-----------------------------------------------------------------------------
_executor_write_status() {
    local task_name="$1"
    local script_path="$2"
    local start_ts="$3"
    local status_file="${SCHEDULER_BASE_DIR}/run/current_task.info"

    cat > "${status_file}" 2>/dev/null << EOF
TASK_NAME=${task_name}
TASK_PID=${EXECUTOR_CURRENT_PID}
TASK_SCRIPT=${script_path}
TASK_START_TS=${start_ts}
TASK_START_TIME=$(date -d @"${start_ts}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
EOF
}

#-----------------------------------------------------------------------------
# _executor_clear_status - 清除当前任务运行状态文件
#-----------------------------------------------------------------------------
_executor_clear_status() {
    local status_file="${SCHEDULER_BASE_DIR}/run/current_task.info"
    rm -f "${status_file}" 2>/dev/null
}
