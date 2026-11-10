#!/bin/bash
#=============================================================================
# logger.sh - 任务调度系统日志模块
#
# 功能：
#   1. 为每次任务执行创建独立日志文件
#   2. 记录调度系统自身运行日志
#   3. 自动清理超过1个月的历史日志
#
# 日志目录结构：
#   logs/
#   ├── scheduler.log          # 调度系统运行日志
#   └── tasks/                 # 任务执行日志
#       └── <task_name>/
#           └── 20260320_153000.log
#
# 用法：
#   source lib/logger.sh
#   logger_init "/path/to/logs"
#   log_info "message"
#   log_file=$(task_log_create "my_task")
#   task_log_cleanup
#=============================================================================

# 日志保留天数（1个月）
LOG_RETAIN_DAYS=31

# 日志根目录（由 logger_init 设置）
LOG_DIR=""

# 日志级别
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# 当前日志级别，默认 INFO
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}

#-----------------------------------------------------------------------------
# logger_init - 初始化日志模块
#
# 参数：
#   $1 - 日志根目录路径
#
# 返回：
#   0 - 成功
#   1 - 目录创建失败
#-----------------------------------------------------------------------------
logger_init() {
    local log_dir="$1"

    if [[ -z "${log_dir}" ]]; then
        echo "[ERROR] logger_init: log directory path is required" >&2
        return 1
    fi

    LOG_DIR="${log_dir}"

    # 创建日志目录
    mkdir -p "${LOG_DIR}/tasks" || {
        echo "[ERROR] logger_init: failed to create log directory: ${LOG_DIR}" >&2
        return 1
    }

    return 0
}

#-----------------------------------------------------------------------------
# _log - 内部日志写入函数
#
# 参数：
#   $1 - 日志级别标签 (INFO/WARN/ERROR/DEBUG)
#   $2 - 日志消息
#-----------------------------------------------------------------------------
_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local log_line="[${timestamp}] [${level}] ${message}"

    # 写入调度系统日志文件
    if [[ -n "${LOG_DIR}" ]]; then
        echo "${log_line}" >> "${LOG_DIR}/scheduler.log"
    fi

    # 同时输出到 stderr（便于调试）
    echo "${log_line}" >&2
}

#-----------------------------------------------------------------------------
# 四个级别的日志函数
#-----------------------------------------------------------------------------
log_debug() {
    [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_DEBUG} ]] && _log "DEBUG" "$1"
}

log_info() {
    [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_INFO} ]] && _log "INFO" "$1"
}

log_warn() {
    [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_WARN} ]] && _log "WARN" "$1"
}

log_error() {
    [[ ${CURRENT_LOG_LEVEL} -le ${LOG_LEVEL_ERROR} ]] && _log "ERROR" "$1"
}

#-----------------------------------------------------------------------------
# task_log_create - 为一次任务执行创建独立日志文件
#
# 参数：
#   $1 - 任务名称
#
# 输出（stdout）：
#   日志文件的完整路径
#
# 返回：
#   0 - 成功
#   1 - 失败
#-----------------------------------------------------------------------------
task_log_create() {
    local task_name="$1"

    if [[ -z "${task_name}" ]]; then
        log_error "task_log_create: task name is required"
        return 1
    fi

    if [[ -z "${LOG_DIR}" ]]; then
        log_error "task_log_create: logger not initialized"
        return 1
    fi

    local task_log_dir="${LOG_DIR}/tasks/${task_name}"
    mkdir -p "${task_log_dir}" || {
        log_error "task_log_create: failed to create dir: ${task_log_dir}"
        return 1
    }

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="${task_log_dir}/${timestamp}.log"

    # 写入日志头部信息
    {
        echo "=========================================="
        echo "Task: ${task_name}"
        echo "Start: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
    } > "${log_file}"

    echo "${log_file}"
    return 0
}

#-----------------------------------------------------------------------------
# task_log_finish - 在任务日志末尾追加结束信息
#
# 参数：
#   $1 - 日志文件路径
#   $2 - 退出码
#   $3 - 开始时间戳（epoch秒）
#-----------------------------------------------------------------------------
task_log_finish() {
    local log_file="$1"
    local exit_code="$2"
    local start_ts="$3"

    if [[ ! -f "${log_file}" ]]; then
        log_error "task_log_finish: log file not found: ${log_file}"
        return 1
    fi

    local end_ts
    end_ts=$(date '+%s')
    local duration=$(( end_ts - start_ts ))

    local status="SUCCESS"
    [[ ${exit_code} -ne 0 ]] && status="FAILED (exit code: ${exit_code})"

    {
        echo "=========================================="
        echo "End:      $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Duration: ${duration}s"
        echo "Status:   ${status}"
        echo "=========================================="
    } >> "${log_file}"

    return 0
}

#-----------------------------------------------------------------------------
# task_log_cleanup - 清理超过保留期限的任务日志
#
# 删除 LOG_DIR/tasks/ 下所有超过 LOG_RETAIN_DAYS 天的 .log 文件，
# 并清理产生的空目录。
#
# 返回：
#   0 - 成功
#-----------------------------------------------------------------------------
task_log_cleanup() {
    if [[ -z "${LOG_DIR}" ]]; then
        log_error "task_log_cleanup: logger not initialized"
        return 1
    fi

    local task_log_dir="${LOG_DIR}/tasks"

    if [[ ! -d "${task_log_dir}" ]]; then
        return 0
    fi

    # 删除过期日志文件
    local count=0
    while IFS= read -r -d '' file; do
        rm -f "${file}"
        (( count++ ))
    done < <(find "${task_log_dir}" -name "*.log" -type f -mtime +${LOG_RETAIN_DAYS} -print0)

    # 清理空目录
    find "${task_log_dir}" -type d -empty -delete 2>/dev/null

    if [[ ${count} -gt 0 ]]; then
        log_info "task_log_cleanup: removed ${count} expired log file(s)"
    fi

    return 0
}
