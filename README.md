# Task Scheduler - 任务调度系统

一个轻量级的定时任务调度系统，用于在 OpenClaw 终端上定时执行数据库功能测试和性能测试脚本。

## 特性

- **Cron 定时调度** — 兼容 crontab 表达式语法，自主实现调度（不依赖系统 crontab）
- **手动触发** — 随时手动执行任意任务
- **任务链** — 支持线性任务链（A → B → C），可选失败终止或失败继续
- **执行日志** — 每次执行生成独立日志文件，自动清理 1 个月前的历史日志
- **超时控制** — 支持任务级别超时设置
- **后台 Daemon** — 以守护进程运行，支持优雅停止
- **配置热更新** — 修改配置文件后无需重启，下次调度自动生效
- **易于迁移** — 修改 `env.conf` 即可适配不同环境

## 环境要求

| 依赖 | 版本要求 |
|------|----------|
| GNU Bash | 4.0+（推荐 5.x） |
| Python 3 | 3.6+ |
| 标准工具 | date, sleep, find, kill, ps |

## 快速开始

### 1. 部署

```bash
# 方式一：在当前目录部署
cd /path/to/task-scheduler
bash install.sh

# 方式二：部署到指定目录
bash install.sh /opt/task-scheduler
```

### 2. 配置环境（可选）

编辑 `env.conf` 修改路径和参数：

```bash
vi env.conf
```

主要配置项：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `TASK_CONFIG` | `conf/tasks.conf` | 任务配置文件路径 |
| `TASK_LOG_DIR` | `logs` | 日志目录 |
| `TASK_LOG_RETAIN_DAYS` | `31` | 日志保留天数 |
| `TASK_DEFAULT_TIMEOUT` | `0` | 默认超时（秒），0=不限制 |
| `TASK_LOG_LEVEL` | `1` | 日志级别（0=DEBUG 1=INFO 2=WARN 3=ERROR） |
| `TASK_PYTHON3` | `python3` | Python3 路径 |

### 3. 编写任务配置

```bash
vi conf/tasks.conf
```

配置格式（类似 crontab）：

```
# 分钟 小时 日 月 星期  任务名  脚本路径

# 每天凌晨 2:30 执行备份测试
30 2 * * *  backup_test  /opt/scripts/backup_test.sh

# 每周一早上 8 点执行性能测试
0  8 * * 1  perf_test    /opt/scripts/perf_test.py

# 每隔 5 分钟执行
*/5 * * * *  quick_check  /opt/scripts/quick_check.sh
```

Cron 字段支持：

| 符号 | 说明 | 示例 |
|------|------|------|
| `*` | 任意值 | `* * * * *` 每分钟 |
| `*/N` | 每隔 N | `*/5 * * * *` 每 5 分钟 |
| `N` | 固定值 | `30 2 * * *` 2 点 30 分 |
| `N,M` | 多个值 | `0,30 * * * *` 整点和半点 |
| `N-M` | 范围 | `0 8 * * 1-5` 工作日 8 点 |

星期字段：0=周日, 1=周一, ..., 6=周六, 7=周日

### 4. 任务链配置

将多个任务串联执行，上一个成功后才执行下一个：

```
# 默认：失败终止（后续任务不执行）
chain daily_func_check
  0 6 * * *  func_test_basic    /opt/scripts/func_test_basic.sh
  >>         func_test_crud     /opt/scripts/func_test_crud.sh
  >>         func_test_txn      /opt/scripts/func_test_txn.py
end

# 失败继续（所有任务都会执行，互不影响）
chain nightly_independent continue_on_failure
  0 22 * * *  test_readonly   /opt/scripts/test_readonly.sh
  >>          test_backup     /opt/scripts/test_backup.sh
  >>          test_restore    /opt/scripts/test_restore.sh
end
```

| 策略 | 语法 | 行为 |
|------|------|------|
| 失败终止 | `chain name` 或 `chain name stop_on_failure` | 任一任务失败则跳过后续（默认） |
| 失败继续 | `chain name continue_on_failure` | 即使失败也继续执行后续任务 |

### 5. 启动调度器

```bash
# 后台启动（推荐）
bin/taskctl start

# 指定配置文件启动
bin/taskctl start -c /path/to/custom.conf

# 前台运行（调试用，Ctrl+C 停止）
bin/taskctl start -f
```

## CLI 命令参考

```
taskctl start [-c config] [-f]    启动调度器（-c 指定配置，-f 前台）
taskctl stop                      停止调度器
taskctl status                    查看运行状态（含当前运行任务）
taskctl running                   查看当前正在运行的任务
taskctl run <task_name>           手动执行任务
taskctl list                      列出所有配置的任务
taskctl log <task_name> [N]       查看最近 N 次执行日志（默认 1）
taskctl cleanup                   手动清理过期日志
taskctl check "<cron_expr>"       测试 cron 表达式是否匹配当前时间
taskctl version                   显示版本和路径信息
taskctl help                      显示帮助
```

### 常用操作示例

```bash
# 查看所有任务
taskctl list

# 手动跑一个任务
taskctl run backup_test

# 查看最近 3 次执行日志
taskctl log backup_test 3

# 测试 cron 表达式
taskctl check "*/5 * * * *"

# 查看当前运行中的任务
taskctl running

# 查看调度器状态
taskctl status

# 停止调度器
taskctl stop
```

## 目录结构

```
task-scheduler/
├── bin/
│   └── taskctl              # CLI 工具（唯一入口）
├── lib/
│   ├── logger.sh            # 日志模块
│   ├── config.sh            # 配置解析
│   ├── executor.sh          # 脚本执行器
│   ├── chain.sh             # 任务链编排
│   ├── scheduler.sh         # 调度守护进程
│   └── cron_match.py        # Cron 表达式匹配（Python）
├── conf/
│   ├── tasks.conf           # 任务配置（用户编辑）
│   └── tasks.conf.example   # 配置模板
├── tests/
│   ├── run_all.sh           # 一键运行全部测试
│   ├── test_logger.sh
│   ├── test_config.sh
│   ├── test_executor.sh
│   ├── test_chain.sh
│   ├── test_cron_match.sh
│   ├── test_scheduler.sh
│   └── test_taskctl.sh
├── logs/                    # 运行时日志（自动创建）
│   ├── scheduler.log        # 调度系统日志
│   └── tasks/               # 任务执行日志
│       └── <task_name>/
│           └── 20260320_153000.log
├── run/                     # 运行时文件（自动创建）
│   ├── scheduler.pid        # 调度器 PID 文件
│   └── current_task.info    # 当前运行任务状态（自动管理）
├── env.conf                 # 环境配置（迁移时修改此文件）
├── install.sh               # 一键部署脚本
└── README.md
```

## 迁移到 OpenClaw

### 步骤

```bash
# 1. 将整个目录打包传输到 OpenClaw
tar czf task-scheduler.tar.gz task-scheduler/
scp task-scheduler.tar.gz user@openclaw:/opt/

# 2. 在 OpenClaw 上解压
ssh user@openclaw
cd /opt && tar xzf task-scheduler.tar.gz

# 3. 运行部署
cd /opt/task-scheduler
bash install.sh

# 4. 按需修改 env.conf（调整路径等）
vi env.conf

# 5. 编写任务配置
vi conf/tasks.conf

# 6. 运行测试确认环境正常
bash tests/run_all.sh

# 7. 启动调度器
bin/taskctl start
```

### 添加到 PATH（可选）

```bash
# 在 ~/.bashrc 中添加：
export TASK_SCHEDULER_HOME="/opt/task-scheduler"
export PATH="${TASK_SCHEDULER_HOME}/bin:${PATH}"

source ~/.bashrc

# 之后可以直接使用：
taskctl start
taskctl status
```

### 开机自启（可选）

创建 systemd 服务文件 `/etc/systemd/system/task-scheduler.service`：

```ini
[Unit]
Description=Task Scheduler Daemon
After=network.target

[Service]
Type=forking
Environment=TASK_SCHEDULER_HOME=/opt/task-scheduler
ExecStart=/opt/task-scheduler/bin/taskctl start
ExecStop=/opt/task-scheduler/bin/taskctl stop
PIDFile=/opt/task-scheduler/run/scheduler.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable task-scheduler
systemctl start task-scheduler
```

## 日志说明

### 调度系统日志

位置：`logs/scheduler.log`

记录调度器启停、任务触发、配置加载等系统事件。

### 任务执行日志

位置：`logs/tasks/<task_name>/<timestamp>.log`

每次执行生成独立文件，包含：
- 任务名称和开始时间
- 脚本的 stdout 和 stderr 输出
- 结束时间、执行耗时、成功/失败状态

示例：
```
==========================================
Task: backup_test
Start: 2026-03-20 02:30:00
==========================================
Starting backup test...
Backup completed: 1024 rows verified
All checks passed
==========================================
End:      2026-03-20 02:30:15
Duration: 15s
Status:   SUCCESS
==========================================
```

### 日志清理

- 自动清理：调度器每 6 小时检查一次，删除超过 31 天的日志
- 手动清理：`taskctl cleanup`
- 保留天数可在 `env.conf` 中通过 `TASK_LOG_RETAIN_DAYS` 调整

## 运行测试

```bash
# 运行全部测试
bash tests/run_all.sh

# 运行单个模块测试
bash tests/test_logger.sh
bash tests/test_config.sh
bash tests/test_executor.sh
bash tests/test_chain.sh
bash tests/test_cron_match.sh
bash tests/test_scheduler.sh
bash tests/test_taskctl.sh
```
