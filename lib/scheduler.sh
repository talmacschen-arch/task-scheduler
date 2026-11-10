#!/bin/bash
#=============================================================================
# scheduler.sh - 调度守护进程模块
#
# 功能：
#   1. 后台 daemon 运行
#   2. 每分钟检查 cron 表达式，触发匹配的任务
#   3. 同一时刻只运行一个任务（串行执行）
#   4. 定期清理过期日志
#   5. 支持优雅停止（SIGTERM）
#
# 依赖：
#   lib/logger.sh
#   lib/config.sh
#   lib/executor.sh
#   lib/chain.sh
#   lib/cron_match.py
#
# 用法：
#   source lib/scheduler.sh
#   scheduler_start   # 启动 daemon
#   scheduler_stop    # 停止 daemon
#   scheduler_status  # 查看状态
#=============================================================================

# scheduler 运行目录（由外部设置）
SCHEDULER_BASE_DIR=""

# PID 文件路径
SCHEDULER_PID_FILE=""

# 日志清理间隔（每 6 小时清理一次）
LOG_CLEANUP_INTERVAL=21600

# 主循环检查间隔（秒）—— 对齐到每分钟的开头
SCHEDULER_POLL_INTERVAL=60

# 运行标志（用于优雅退出）
_SCHEDULER_RUNNING=0

#-----------------------------------------------------------------------------
# scheduler_init - 初始化调度器
#
# 参数：
#   $1 - 项目根目录
#
# 返回：
#   0 - 成功
#   1 - 失败
#-----------------------------------------------------------------------------
scheduler_init() {
    local base_dir="$1"

    if [[ -z "${base_dir}" ]]; then
        echo "[ERROR] scheduler_init: base directory is required" >&2
        return 1
    fi

    SCHEDULER_BASE_DIR="${base_dir}"
    SCHEDULER_PID_FILE="${base_dir}/run/scheduler.pid"

    mkdir -p "${base_dir}/run" || {
        echo "[ERROR] scheduler_init: failed to create run directory" >&2
        return 1
    }

    # 加载所有依赖模块
    source "${base_dir}/lib/logger.sh"
    source "${base_dir}/lib/config.sh"
    source "${base_dir}/lib/executor.sh"
    source "${base_dir}/lib/chain.sh"

    # 初始化日志
    logger_init "${base_dir}/logs"

    return 0
}

#-----------------------------------------------------------------------------
# scheduler_start - 启动调度守护进程
#
# 参数：
#   $1 - 配置文件路径
#   $2 - 是否前台运行（"foreground" 则前台，默认后台 daemon）
#
# 返回：
#   0 - 启动成功
#   1 - 启动失败
#-----------------------------------------------------------------------------
scheduler_start() {
    local config_file="$1"
    local mode="${2:-daemon}"

    # 检查是否已经在运行
    if scheduler_is_running; then
        local pid
        pid=$(cat "${SCHEDULER_PID_FILE}" 2>/dev/null)
        echo "Scheduler is already running (PID: ${pid})" >&2
        return 1
    fi

    # 加载配置
    if ! config_load "${config_file}"; then
        echo "Failed to load config: ${config_file}" >&2
        return 1
    fi

    if [[ "${mode}" == "foreground" ]]; then
        # 前台运行
        _scheduler_main_loop "${config_file}"
    else
        # 后台 daemon（重定向 stdout/stderr 到日志，避免阻塞调用方）
        _scheduler_main_loop "${config_file}" </dev/null >>"${LOG_DIR}/scheduler.log" 2>&1 &
        local daemon_pid=$!

        # 写入 PID 文件
        echo "${daemon_pid}" > "${SCHEDULER_PID_FILE}"

        # 等一下确认进程真的启动了
        sleep 1
        if kill -0 "${daemon_pid}" 2>/dev/null; then
            echo "Scheduler started (PID: ${daemon_pid})"
            return 0
        else
            echo "Scheduler failed to start" >&2
            rm -f "${SCHEDULER_PID_FILE}"
            return 1
        fi
    fi
}

#-----------------------------------------------------------------------------
# _scheduler_main_loop - 调度主循环
#
# 参数：
#   $1 - 配置文件路径
#-----------------------------------------------------------------------------
_scheduler_main_loop() {
    local config_file="$1"

    _SCHEDULER_RUNNING=1

    # 写入 PID 文件（BASHPID 获取真实子进程 PID）
    echo "${BASHPID}" > "${SCHEDULER_PID_FILE}"

    # 注册信号处理
    trap '_scheduler_shutdown' SIGTERM SIGINT

    log_info "scheduler: daemon started (PID: ${BASHPID})"
    log_info "scheduler: config file: ${config_file}"

    local task_count
    task_count=$(config_get_schedulable | wc -l)
    log_info "scheduler: loaded ${task_count} schedulable task(s)"

    local last_cleanup_ts=0

    while [[ ${_SCHEDULER_RUNNING} -eq 1 ]]; do
        # 等待到下一分钟的开头
        _wait_next_minute

        # 检查是否被信号中断
        [[ ${_SCHEDULER_RUNNING} -eq 0 ]] && break

        local now
        now=$(date '+%Y-%m-%d %H:%M')
        log_debug "scheduler: checking tasks at ${now}"

        # 重新加载配置（支持热更新）
        if ! config_load "${config_file}" 2>/dev/null; then
            log_error "scheduler: failed to reload config, using previous"
        fi

        # 遍历所有可调度任务
        while IFS= read -r task_entry; do
            [[ ${_SCHEDULER_RUNNING} -eq 0 ]] && break

            local task_name cron_expr script_path chain_name
            task_name=$(echo "${task_entry}" | cut -d'|' -f1)
            cron_expr=$(echo "${task_entry}" | cut -d'|' -f2)
            script_path=$(echo "${task_entry}" | cut -d'|' -f3)
            chain_name=$(echo "${task_entry}" | cut -d'|' -f4)

            # 检查 cron 匹配
            if ${TASK_PYTHON3:-python3} "${SCHEDULER_BASE_DIR}/lib/cron_match.py" "${cron_expr}" "${now}"; then
                log_info "scheduler: cron matched for '${task_name}' at ${now}"

                if [[ -n "${chain_name}" ]]; then
                    # 任务属于链，执行整条链
                    log_info "scheduler: triggering chain '${chain_name}'"
                    chain_run "${chain_name}"
                else
                    # 独立任务
                    log_info "scheduler: triggering task '${task_name}'"
                    executor_run "${task_name}" "${script_path}"
                fi
            fi
        done <<< "$(config_get_schedulable)"

        # 定期清理日志
        local current_ts
        current_ts=$(date '+%s')
        if (( current_ts - last_cleanup_ts >= LOG_CLEANUP_INTERVAL )); then
            task_log_cleanup
            last_cleanup_ts=${current_ts}
        fi
    done

    log_info "scheduler: daemon stopped"
    rm -f "${SCHEDULER_PID_FILE}"
}

#-----------------------------------------------------------------------------
# _wait_next_minute - 等待到下一分钟的开头（第 0 秒）
#-----------------------------------------------------------------------------
_wait_next_minute() {
    local current_sec
    current_sec=$(date '+%S' | sed 's/^0//')
    current_sec=${current_sec:-0}
    local wait_sec=$(( SCHEDULER_POLL_INTERVAL - current_sec ))

    if [[ ${wait_sec} -le 0 ]]; then
        wait_sec=${SCHEDULER_POLL_INTERVAL}
    fi

    # 用短循环实现可中断的 sleep
    local i=0
    while [[ ${i} -lt ${wait_sec} && ${_SCHEDULER_RUNNING} -eq 1 ]]; do
        sleep 1
        (( i++ ))
    done
}

#-----------------------------------------------------------------------------
# _scheduler_shutdown - 优雅停止处理
#-----------------------------------------------------------------------------
_scheduler_shutdown() {
    log_info "scheduler: received shutdown signal"
    _SCHEDULER_RUNNING=0

    # 如果有任务正在执行，停止它
    if executor_is_running; then
        log_info "scheduler: stopping running task..."
        executor_stop
    fi
}

#-----------------------------------------------------------------------------
# scheduler_stop - 停止调度守护进程
#
# 返回：
#   0 - 已停止
#   1 - 停止失败
#-----------------------------------------------------------------------------
scheduler_stop() {
    if [[ ! -f "${SCHEDULER_PID_FILE}" ]]; then
        echo "Scheduler is not running (no PID file)" >&2
        return 1
    fi

    local pid
    pid=$(cat "${SCHEDULER_PID_FILE}" 2>/dev/null)

    if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
        echo "Scheduler is not running (stale PID file)" >&2
        rm -f "${SCHEDULER_PID_FILE}"
        return 1
    fi

    echo "Stopping scheduler (PID: ${pid})..."
    kill -TERM "${pid}" 2>/dev/null

    # 等待进程退出（最多 30 秒）
    local wait=0
    while kill -0 "${pid}" 2>/dev/null && [[ ${wait} -lt 30 ]]; do
        sleep 1
        (( wait++ ))
    done

    if kill -0 "${pid}" 2>/dev/null; then
        echo "Force killing scheduler..." >&2
        kill -9 "${pid}" 2>/dev/null
        sleep 1
    fi

    rm -f "${SCHEDULER_PID_FILE}"
    echo "Scheduler stopped"
    return 0
}

#-----------------------------------------------------------------------------
# scheduler_is_running - 检查调度器是否在运行
#
# 返回：
#   0 - 运行中
#   1 - 未运行
#-----------------------------------------------------------------------------
scheduler_is_running() {
    if [[ ! -f "${SCHEDULER_PID_FILE}" ]]; then
        return 1
    fi

    local pid
    pid=$(cat "${SCHEDULER_PID_FILE}" 2>/dev/null)

    if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
        return 1
    fi

    return 0
}

#-----------------------------------------------------------------------------
# scheduler_status - 输出调度器状态信息
#-----------------------------------------------------------------------------
scheduler_status() {
    if scheduler_is_running; then
        local pid
        pid=$(cat "${SCHEDULER_PID_FILE}" 2>/dev/null)
        echo "Scheduler is running (PID: ${pid})"

        # 显示当前正在运行的任务
        local status_file="${SCHEDULER_BASE_DIR}/run/current_task.info"
        if [[ -f "${status_file}" ]]; then
            local task_name="" task_pid="" task_start_time=""
            while IFS='=' read -r key value; do
                case "${key}" in
                    TASK_NAME)       task_name="${value}" ;;
                    TASK_PID)        task_pid="${value}" ;;
                    TASK_START_TIME) task_start_time="${value}" ;;
                esac
            done < "${status_file}"
            if [[ -n "${task_pid}" && "${task_pid}" -ne 0 ]] && kill -0 "${task_pid}" 2>/dev/null; then
                echo ""
                echo "Running task: ${task_name} (PID: ${task_pid}, started: ${task_start_time})"
            fi
        fi

        # 输出已加载的任务信息
        if [[ ${#TASKS[@]} -gt 0 ]]; then
            echo ""
            echo "Loaded tasks:"
            config_get_schedulable | while IFS= read -r entry; do
                local name cron chain
                name=$(echo "${entry}" | cut -d'|' -f1)
                cron=$(echo "${entry}" | cut -d'|' -f2)
                chain=$(echo "${entry}" | cut -d'|' -f4)
                if [[ -n "${chain}" ]]; then
                    echo "  [chain:${chain}] ${cron}  ${name}"
                else
                    echo "  ${cron}  ${name}"
                fi
            done
        fi
    else
        echo "Scheduler is not running"
    fi
}

#-----------------------------------------------------------------------------
# scheduler_run_task - 手动触发单个任务
#
# 参数：
#   $1 - 任务名称
#
# 返回：
#   0 - 成功
#   1 - 失败
#-----------------------------------------------------------------------------
scheduler_run_task() {
    local task_name="$1"

    local task_info
    task_info=$(config_get_task "${task_name}")
    if [[ $? -ne 0 ]]; then
        echo "Task not found: ${task_name}" >&2
        return 1
    fi

    local script_path chain_name
    script_path=$(echo "${task_info}" | cut -d'|' -f3)
    chain_name=$(echo "${task_info}" | cut -d'|' -f4)

    if [[ -n "${chain_name}" ]]; then
        echo "Task '${task_name}' belongs to chain '${chain_name}'"
        echo "Triggering entire chain..."
        chain_run "${chain_name}"
    else
        executor_run "${task_name}" "${script_path}"
    fi
}
