#!/bin/bash
#=============================================================================
# chain.sh - 线性任务链执行模块
#
# 功能：
#   1. 按顺序执行任务链中的每个任务
#   2. 支持两种失败策略：
#      - stop（默认）：任一任务失败则终止整条链
#      - continue：任务失败后继续执行后续任务
#   3. 记录链的整体执行状态
#
# 依赖：
#   lib/logger.sh
#   lib/config.sh
#   lib/executor.sh
#
# 用法：
#   source lib/logger.sh
#   source lib/config.sh
#   source lib/executor.sh
#   source lib/chain.sh
#   chain_run "chain_name"
#=============================================================================

# 上一次链执行的结果
CHAIN_LAST_STATUS=""         # SUCCESS / FAILED
CHAIN_LAST_FAILED_TASKS=""   # 失败的任务名列表（逗号分隔）
CHAIN_LAST_TOTAL=0           # 链中任务总数
CHAIN_LAST_COMPLETED=0       # 成功完成的任务数
CHAIN_LAST_SKIPPED=0         # 跳过的任务数（仅 stop 模式）

#-----------------------------------------------------------------------------
# chain_run - 执行一条任务链
#
# 参数：
#   $1 - 链名称
#   $2 - 超时秒数（可选，应用于链中每个任务）
#
# 返回：
#   0 - 整条链执行成功（所有任务均成功）
#   1 - 链执行失败（存在任务失败或链不存在）
#-----------------------------------------------------------------------------
chain_run() {
    local chain_name="$1"
    local timeout="${2:-0}"

    # 重置状态
    CHAIN_LAST_STATUS=""
    CHAIN_LAST_FAILED_TASKS=""
    CHAIN_LAST_TOTAL=0
    CHAIN_LAST_COMPLETED=0
    CHAIN_LAST_SKIPPED=0

    # 获取链信息
    local chain_info
    chain_info=$(config_get_chain "${chain_name}")
    if [[ $? -ne 0 ]]; then
        log_error "chain_run: chain not found: ${chain_name}"
        CHAIN_LAST_STATUS="FAILED"
        return 1
    fi

    # 解析: chain_name|task1,task2,task3|on_failure
    local task_list on_failure
    task_list=$(echo "${chain_info}" | cut -d'|' -f2)
    on_failure=$(echo "${chain_info}" | cut -d'|' -f3)
    on_failure="${on_failure:-stop}"

    # 转为数组
    IFS=',' read -ra task_names <<< "${task_list}"
    CHAIN_LAST_TOTAL=${#task_names[@]}

    log_info "chain_run: starting chain '${chain_name}' [${on_failure}_on_failure] with ${CHAIN_LAST_TOTAL} task(s)"

    local chain_start_ts
    chain_start_ts=$(date '+%s')

    local has_failure=0
    local i=0
    for task_name in "${task_names[@]}"; do
        (( i++ ))

        # 获取任务信息
        local task_info
        task_info=$(config_get_task "${task_name}")
        if [[ $? -ne 0 ]]; then
            log_error "chain_run: task not found in config: ${task_name}"
            has_failure=1
            _chain_append_failed "${task_name}"
            if [[ "${on_failure}" == "stop" ]]; then
                CHAIN_LAST_SKIPPED=$(( CHAIN_LAST_TOTAL - i ))
                CHAIN_LAST_STATUS="FAILED"
                _chain_log_summary "${chain_name}" "${chain_start_ts}" "${on_failure}"
                return 1
            fi
            continue
        fi

        # 解析脚本路径: name|cron|script|chain_name
        local script_path
        script_path=$(echo "${task_info}" | cut -d'|' -f3)

        log_info "chain_run: [${i}/${CHAIN_LAST_TOTAL}] executing '${task_name}'"

        # 执行任务
        executor_run "${task_name}" "${script_path}" "${timeout}"
        local exit_code=$?

        if [[ ${exit_code} -ne 0 ]]; then
            has_failure=1
            _chain_append_failed "${task_name}"

            if [[ "${on_failure}" == "stop" ]]; then
                log_error "chain_run: task '${task_name}' failed (exit code: ${exit_code}), chain '${chain_name}' terminated"
                CHAIN_LAST_SKIPPED=$(( CHAIN_LAST_TOTAL - i ))
                CHAIN_LAST_STATUS="FAILED"
                _chain_log_summary "${chain_name}" "${chain_start_ts}" "${on_failure}"
                return 1
            else
                log_warn "chain_run: task '${task_name}' failed (exit code: ${exit_code}), continuing chain '${chain_name}'"
            fi
        else
            (( CHAIN_LAST_COMPLETED++ ))
            log_info "chain_run: [${i}/${CHAIN_LAST_TOTAL}] '${task_name}' completed"
        fi
    done

    if [[ ${has_failure} -eq 1 ]]; then
        CHAIN_LAST_STATUS="FAILED"
        log_warn "chain_run: chain '${chain_name}' finished with failures"
    else
        CHAIN_LAST_STATUS="SUCCESS"
        log_info "chain_run: chain '${chain_name}' completed successfully"
    fi

    _chain_log_summary "${chain_name}" "${chain_start_ts}" "${on_failure}"

    if [[ ${has_failure} -eq 1 ]]; then
        return 1
    fi
    return 0
}

#-----------------------------------------------------------------------------
# _chain_append_failed - 追加失败任务名到列表
#-----------------------------------------------------------------------------
_chain_append_failed() {
    local task_name="$1"
    if [[ -z "${CHAIN_LAST_FAILED_TASKS}" ]]; then
        CHAIN_LAST_FAILED_TASKS="${task_name}"
    else
        CHAIN_LAST_FAILED_TASKS="${CHAIN_LAST_FAILED_TASKS},${task_name}"
    fi
}

#-----------------------------------------------------------------------------
# _chain_log_summary - 输出链执行摘要到日志
#
# 参数：
#   $1 - 链名称
#   $2 - 开始时间戳
#   $3 - 失败策略
#-----------------------------------------------------------------------------
_chain_log_summary() {
    local chain_name="$1"
    local start_ts="$2"
    local on_failure="$3"
    local end_ts
    end_ts=$(date '+%s')
    local duration=$(( end_ts - start_ts ))

    local failed_count=0
    if [[ -n "${CHAIN_LAST_FAILED_TASKS}" ]]; then
        IFS=',' read -ra _arr <<< "${CHAIN_LAST_FAILED_TASKS}"
        failed_count=${#_arr[@]}
    fi

    log_info "chain_run: --- chain summary ---"
    log_info "chain_run:   chain:      ${chain_name}"
    log_info "chain_run:   policy:     ${on_failure}_on_failure"
    log_info "chain_run:   status:     ${CHAIN_LAST_STATUS}"
    log_info "chain_run:   succeeded:  ${CHAIN_LAST_COMPLETED}/${CHAIN_LAST_TOTAL}"
    if [[ ${failed_count} -gt 0 ]]; then
        log_info "chain_run:   failed(${failed_count}): ${CHAIN_LAST_FAILED_TASKS}"
    fi
    if [[ ${CHAIN_LAST_SKIPPED} -gt 0 ]]; then
        log_info "chain_run:   skipped:    ${CHAIN_LAST_SKIPPED}"
    fi
    log_info "chain_run:   duration:   ${duration}s"
    log_info "chain_run: --- end summary ---"
}

#-----------------------------------------------------------------------------
# chain_get_status - 获取上一次链执行的状态摘要
#
# 输出（stdout）：
#   status|completed|total|failed_tasks|skipped
#-----------------------------------------------------------------------------
chain_get_status() {
    echo "${CHAIN_LAST_STATUS}|${CHAIN_LAST_COMPLETED}|${CHAIN_LAST_TOTAL}|${CHAIN_LAST_FAILED_TASKS}|${CHAIN_LAST_SKIPPED}"
}
