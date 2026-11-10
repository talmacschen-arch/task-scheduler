#!/bin/bash
#=============================================================================
# config.sh - 任务调度系统配置解析模块
#
# 功能：
#   1. 解析 crontab 风格的任务配置文件
#   2. 支持单独任务和线性任务链（chain）
#   3. 提供任务查询接口
#
# 配置文件格式：
#   # 注释行
#   分钟 小时 日 月 星期  任务名  脚本路径
#
#   chain 链名
#     0 6 * * *  任务名1  /path/to/script1.sh
#     >>         任务名2  /path/to/script2.sh
#   end
#
# 内部数据结构（用数组模拟）：
#   TASKS[]      - 所有任务，格式: "name|cron|script|chain_name"
#   CHAINS[]     - 所有链，格式: "chain_name|task1,task2,task3|on_failure"
#                  on_failure: stop（默认）或 continue
#=============================================================================

# 任务列表
declare -a TASKS=()

# 任务链列表
declare -a CHAINS=()

# 配置文件路径
CONFIG_FILE=""

#-----------------------------------------------------------------------------
# config_load - 加载并解析配置文件
#
# 参数：
#   $1 - 配置文件路径
#
# 返回：
#   0 - 成功
#   1 - 文件不存在或解析失败
#-----------------------------------------------------------------------------
config_load() {
    local config_file="$1"

    if [[ -z "${config_file}" ]]; then
        echo "[ERROR] config_load: config file path is required" >&2
        return 1
    fi

    if [[ ! -f "${config_file}" ]]; then
        echo "[ERROR] config_load: file not found: ${config_file}" >&2
        return 1
    fi

    CONFIG_FILE="${config_file}"
    TASKS=()
    CHAINS=()

    local line_num=0
    local in_chain=0
    local chain_name=""
    local chain_tasks=""
    local chain_cron=""
    local chain_on_failure=""

    while IFS= read -r line || [[ -n "${line}" ]]; do
        (( line_num++ ))

        # 去除首尾空白
        line=$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 跳过空行和注释
        [[ -z "${line}" ]] && continue
        [[ "${line}" == \#* ]] && continue

        # 处理 chain 块
        # 格式: chain <name> [continue_on_failure]
        if [[ "${line}" =~ ^chain[[:space:]]+([^[:space:]]+)([[:space:]]+(.+))?$ ]]; then
            if [[ ${in_chain} -eq 1 ]]; then
                echo "[ERROR] line ${line_num}: nested chain not allowed" >&2
                return 1
            fi
            in_chain=1
            chain_name="${BASH_REMATCH[1]}"
            local policy="${BASH_REMATCH[3]}"
            chain_tasks=""
            chain_cron=""
            # 解析失败策略
            if [[ "${policy}" == "continue_on_failure" ]]; then
                chain_on_failure="continue"
            elif [[ -z "${policy}" || "${policy}" == "stop_on_failure" ]]; then
                chain_on_failure="stop"
            else
                echo "[ERROR] line ${line_num}: unknown chain policy: '${policy}'" >&2
                return 1
            fi
            continue
        fi

        if [[ "${line}" == "end" ]]; then
            if [[ ${in_chain} -eq 0 ]]; then
                echo "[ERROR] line ${line_num}: unexpected 'end' outside chain" >&2
                return 1
            fi
            # 去掉末尾逗号
            chain_tasks="${chain_tasks%,}"
            CHAINS+=("${chain_name}|${chain_tasks}|${chain_on_failure}")
            in_chain=0
            chain_name=""
            chain_tasks=""
            chain_cron=""
            chain_on_failure=""
            continue
        fi

        if [[ ${in_chain} -eq 1 ]]; then
            _parse_chain_line "${line}" "${line_num}" "${chain_name}" || return 1
        else
            _parse_task_line "${line}" "${line_num}" "" || return 1
        fi

    done < "${config_file}"

    if [[ ${in_chain} -eq 1 ]]; then
        echo "[ERROR] unexpected end of file: chain '${chain_name}' not closed" >&2
        return 1
    fi

    return 0
}

#-----------------------------------------------------------------------------
# _parse_task_line - 解析单独任务行
#
# 参数：
#   $1 - 行内容
#   $2 - 行号
#   $3 - 所属链名（空表示独立任务）
#-----------------------------------------------------------------------------
_parse_task_line() {
    local line="$1"
    local line_num="$2"
    local chain_name="$3"

    # 格式: min hour day month weekday task_name script_path
    local min hour day month weekday task_name script_path
    read -r min hour day month weekday task_name script_path <<< "${line}"

    if [[ -z "${script_path}" ]]; then
        echo "[ERROR] line ${line_num}: incomplete task definition" >&2
        return 1
    fi

    # 验证 cron 字段基本格式
    if ! _validate_cron_field "${min}" "0-59" "${line_num}" "minute" || \
       ! _validate_cron_field "${hour}" "0-23" "${line_num}" "hour" || \
       ! _validate_cron_field "${day}" "1-31" "${line_num}" "day" || \
       ! _validate_cron_field "${month}" "1-12" "${line_num}" "month" || \
       ! _validate_cron_field "${weekday}" "0-7" "${line_num}" "weekday"; then
        return 1
    fi

    local cron_expr="${min} ${hour} ${day} ${month} ${weekday}"
    TASKS+=("${task_name}|${cron_expr}|${script_path}|${chain_name}")

    return 0
}

#-----------------------------------------------------------------------------
# _parse_chain_line - 解析任务链内的行
#
# 参数：
#   $1 - 行内容
#   $2 - 行号
#   $3 - 链名
#-----------------------------------------------------------------------------
_parse_chain_line() {
    local line="$1"
    local line_num="$2"
    local chain_name="$3"

    # 判断是链首行（带cron）还是后续行（>> 开头）
    if [[ "${line}" == \>\>* ]]; then
        # 后续任务行: >> task_name script_path
        local rest
        rest=$(echo "${line}" | sed 's/^>>[[:space:]]*//')
        local task_name script_path
        read -r task_name script_path <<< "${rest}"

        if [[ -z "${script_path}" ]]; then
            echo "[ERROR] line ${line_num}: incomplete chain task definition" >&2
            return 1
        fi

        # 后续任务没有独立 cron，标记为 chain_follow
        TASKS+=("${task_name}|chain_follow|${script_path}|${chain_name}")

        # 追加到链的任务列表
        chain_tasks="${chain_tasks}${task_name},"
    else
        # 链首行，有 cron 时间
        _parse_task_line "${line}" "${line_num}" "${chain_name}" || return 1

        # 取刚加入的任务名
        local last_task="${TASKS[-1]}"
        local task_name
        task_name=$(echo "${last_task}" | cut -d'|' -f1)
        chain_tasks="${chain_tasks}${task_name},"
    fi

    return 0
}

#-----------------------------------------------------------------------------
# _validate_cron_field - 验证 cron 字段基本格式
#
# 支持: * */N N N,N N-N
#
# 参数：
#   $1 - 字段值
#   $2 - 有效范围（如 "0-59"）
#   $3 - 行号
#   $4 - 字段名
#-----------------------------------------------------------------------------
_validate_cron_field() {
    local value="$1"
    local range="$2"
    local line_num="$3"
    local field_name="$4"

    # 允许的格式: * */N N N,N,N N-N
    if [[ "${value}" =~ ^(\*|(\*/[0-9]+)|([0-9]+(-[0-9]+)?)(,[0-9]+(-[0-9]+)?)*)$ ]]; then
        return 0
    fi

    echo "[ERROR] line ${line_num}: invalid ${field_name} field: '${value}'" >&2
    return 1
}

#-----------------------------------------------------------------------------
# config_get_tasks - 获取所有任务列表
#
# 输出（stdout）：
#   每行一个任务：name|cron|script|chain_name
#-----------------------------------------------------------------------------
config_get_tasks() {
    local task
    for task in "${TASKS[@]}"; do
        echo "${task}"
    done
}

#-----------------------------------------------------------------------------
# config_get_task - 根据任务名获取任务信息
#
# 参数：
#   $1 - 任务名
#
# 输出（stdout）：
#   name|cron|script|chain_name
#
# 返回：
#   0 - 找到
#   1 - 未找到
#-----------------------------------------------------------------------------
config_get_task() {
    local name="$1"
    local task
    for task in "${TASKS[@]}"; do
        local task_name
        task_name=$(echo "${task}" | cut -d'|' -f1)
        if [[ "${task_name}" == "${name}" ]]; then
            echo "${task}"
            return 0
        fi
    done
    return 1
}

#-----------------------------------------------------------------------------
# config_get_chains - 获取所有任务链
#
# 输出（stdout）：
#   每行一个链：chain_name|task1,task2,task3
#-----------------------------------------------------------------------------
config_get_chains() {
    local chain
    for chain in "${CHAINS[@]}"; do
        echo "${chain}"
    done
}

#-----------------------------------------------------------------------------
# config_get_chain - 根据链名获取任务链信息
#
# 参数：
#   $1 - 链名
#
# 输出（stdout）：
#   chain_name|task1,task2,task3
#
# 返回：
#   0 - 找到
#   1 - 未找到
#-----------------------------------------------------------------------------
config_get_chain() {
    local name="$1"
    local chain
    for chain in "${CHAINS[@]}"; do
        local chain_name
        chain_name=$(echo "${chain}" | cut -d'|' -f1)
        if [[ "${chain_name}" == "${name}" ]]; then
            echo "${chain}"
            return 0
        fi
    done
    return 1
}

#-----------------------------------------------------------------------------
# config_get_schedulable - 获取所有可调度的条目（独立任务+链首任务）
#
# 只返回有 cron 表达式的任务（排除 chain_follow 类型）
#
# 输出（stdout）：
#   每行: name|cron|script|chain_name
#-----------------------------------------------------------------------------
config_get_schedulable() {
    local task
    for task in "${TASKS[@]}"; do
        local cron
        cron=$(echo "${task}" | cut -d'|' -f2)
        if [[ "${cron}" != "chain_follow" ]]; then
            echo "${task}"
        fi
    done
}

#-----------------------------------------------------------------------------
# config_dump - 输出解析后的配置摘要（调试用）
#-----------------------------------------------------------------------------
config_dump() {
    echo "=== Tasks (${#TASKS[@]}) ==="
    local i=0
    local task
    for task in "${TASKS[@]}"; do
        echo "  [${i}] ${task}"
        (( i++ ))
    done

    echo "=== Chains (${#CHAINS[@]}) ==="
    local chain
    for chain in "${CHAINS[@]}"; do
        echo "  ${chain}"
    done
}
