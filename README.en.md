# Task Scheduler

**English** | [中文](README.md)

A lightweight scheduled-task scheduler for running database functional and performance test scripts on a schedule from an OpenClaw terminal.

## Features

- **Cron scheduling** — Compatible with crontab expression syntax; scheduling is implemented in-house (does not depend on the system crontab)
- **Manual trigger** — Run any task on demand at any time
- **Task chains** — Linear task chains (A → B → C), with an optional stop-on-failure or continue-on-failure policy
- **Execution logs** — Each run produces its own log file; logs older than one month are cleaned up automatically
- **Timeout control** — Per-task timeout settings
- **Background daemon** — Runs as a daemon with graceful shutdown
- **Hot config reload** — Edit the config file without restarting; the next scheduling cycle picks it up automatically
- **Easy to migrate** — Adapt to a different environment by editing `env.conf`

## Requirements

| Dependency | Version |
|------|----------|
| GNU Bash | 4.0+ (5.x recommended) |
| Python 3 | 3.6+ |
| Standard tools | date, sleep, find, kill, ps |

## Quick Start

### 1. Deploy

```bash
# Option 1: deploy in the current directory
cd /path/to/task-scheduler
bash install.sh

# Option 2: deploy to a specific directory
bash install.sh /opt/task-scheduler
```

### 2. Configure the environment (optional)

Edit `env.conf` to change paths and parameters:

```bash
vi env.conf
```

Main settings:

| Parameter | Default | Description |
|------|--------|------|
| `TASK_CONFIG` | `conf/tasks.conf` | Path to the task config file |
| `TASK_LOG_DIR` | `logs` | Log directory |
| `TASK_LOG_RETAIN_DAYS` | `31` | Days to retain logs |
| `TASK_DEFAULT_TIMEOUT` | `0` | Default timeout (seconds), 0 = unlimited |
| `TASK_LOG_LEVEL` | `1` | Log level (0=DEBUG 1=INFO 2=WARN 3=ERROR) |
| `TASK_PYTHON3` | `python3` | Path to Python 3 |

### 3. Write the task config

```bash
vi conf/tasks.conf
```

Config format (similar to crontab):

```
# minute hour day month weekday  task_name  script_path

# Run a backup test every day at 2:30 AM
30 2 * * *  backup_test  /opt/scripts/backup_test.sh

# Run a performance test every Monday at 8 AM
0  8 * * 1  perf_test    /opt/scripts/perf_test.py

# Run every 5 minutes
*/5 * * * *  quick_check  /opt/scripts/quick_check.sh
```

Supported cron fields:

| Symbol | Meaning | Example |
|------|------|------|
| `*` | Any value | `* * * * *` every minute |
| `*/N` | Every N | `*/5 * * * *` every 5 minutes |
| `N` | Fixed value | `30 2 * * *` at 2:30 |
| `N,M` | Multiple values | `0,30 * * * *` on the hour and half-hour |
| `N-M` | Range | `0 8 * * 1-5` at 8 AM on weekdays |

Weekday field: 0=Sunday, 1=Monday, ..., 6=Saturday, 7=Sunday

### 4. Task chain config

Run multiple tasks in sequence; the next task runs only after the previous one succeeds:

```
# Default: stop on failure (subsequent tasks are skipped)
chain daily_func_check
  0 6 * * *  func_test_basic    /opt/scripts/func_test_basic.sh
  >>         func_test_crud     /opt/scripts/func_test_crud.sh
  >>         func_test_txn      /opt/scripts/func_test_txn.py
end

# Continue on failure (all tasks run, independently of each other)
chain nightly_independent continue_on_failure
  0 22 * * *  test_readonly   /opt/scripts/test_readonly.sh
  >>          test_backup     /opt/scripts/test_backup.sh
  >>          test_restore    /opt/scripts/test_restore.sh
end
```

| Policy | Syntax | Behavior |
|------|------|------|
| Stop on failure | `chain name` or `chain name stop_on_failure` | If any task fails, the rest are skipped (default) |
| Continue on failure | `chain name continue_on_failure` | Continue running subsequent tasks even after a failure |

### 5. Start the scheduler

```bash
# Start in the background (recommended)
bin/taskctl start

# Start with a specific config file
bin/taskctl start -c /path/to/custom.conf

# Run in the foreground (for debugging; Ctrl+C to stop)
bin/taskctl start -f
```

## CLI Reference

```
taskctl start [-c config] [-f]    Start the scheduler (-c to specify config, -f for foreground)
taskctl stop                      Stop the scheduler
taskctl status                    Show runtime status (including currently running tasks)
taskctl running                   Show tasks currently running
taskctl run <task_name>           Run a task manually
taskctl list                      List all configured tasks
taskctl log <task_name> [N]       Show the last N execution logs (default 1)
taskctl cleanup                   Clean up expired logs manually
taskctl check "<cron_expr>"       Test whether a cron expression matches the current time
taskctl version                   Show version and path information
taskctl help                      Show help
```

### Common usage examples

```bash
# List all tasks
taskctl list

# Run a task manually
taskctl run backup_test

# Show the last 3 execution logs
taskctl log backup_test 3

# Test a cron expression
taskctl check "*/5 * * * *"

# Show currently running tasks
taskctl running

# Show scheduler status
taskctl status

# Stop the scheduler
taskctl stop
```

## Directory Structure

```
task-scheduler/
├── bin/
│   └── taskctl              # CLI tool (the only entry point)
├── lib/
│   ├── logger.sh            # Logging module
│   ├── config.sh            # Config parsing
│   ├── executor.sh          # Script executor
│   ├── chain.sh             # Task-chain orchestration
│   ├── scheduler.sh         # Scheduling daemon
│   └── cron_match.py        # Cron expression matching (Python)
├── conf/
│   ├── tasks.conf           # Task config (user-edited)
│   └── tasks.conf.example   # Config template
├── tests/
│   ├── run_all.sh           # Run all tests at once
│   ├── test_logger.sh
│   ├── test_config.sh
│   ├── test_executor.sh
│   ├── test_chain.sh
│   ├── test_cron_match.sh
│   ├── test_scheduler.sh
│   └── test_taskctl.sh
├── logs/                    # Runtime logs (auto-created)
│   ├── scheduler.log        # Scheduler system log
│   └── tasks/               # Per-task execution logs
│       └── <task_name>/
│           └── 20260320_153000.log
├── run/                     # Runtime files (auto-created)
│   ├── scheduler.pid        # Scheduler PID file
│   └── current_task.info    # Current-task status (auto-managed)
├── env.conf                 # Environment config (edit this when migrating)
├── install.sh               # One-shot deploy script
└── README.md
```

## Migrating to OpenClaw

### Steps

```bash
# 1. Pack up the whole directory and transfer it to OpenClaw
tar czf task-scheduler.tar.gz task-scheduler/
scp task-scheduler.tar.gz user@openclaw:/opt/

# 2. Unpack it on OpenClaw
ssh user@openclaw
cd /opt && tar xzf task-scheduler.tar.gz

# 3. Run the deploy
cd /opt/task-scheduler
bash install.sh

# 4. Adjust env.conf as needed (paths, etc.)
vi env.conf

# 5. Write the task config
vi conf/tasks.conf

# 6. Run the tests to confirm the environment is healthy
bash tests/run_all.sh

# 7. Start the scheduler
bin/taskctl start
```

### Add to PATH (optional)

```bash
# Add to ~/.bashrc:
export TASK_SCHEDULER_HOME="/opt/task-scheduler"
export PATH="${TASK_SCHEDULER_HOME}/bin:${PATH}"

source ~/.bashrc

# Then you can use it directly:
taskctl start
taskctl status
```

### Start on boot (optional)

Create a systemd service file `/etc/systemd/system/task-scheduler.service`:

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

## Logging

### Scheduler system log

Location: `logs/scheduler.log`

Records system events such as scheduler start/stop, task triggers, and config loading.

### Task execution logs

Location: `logs/tasks/<task_name>/<timestamp>.log`

Each run produces its own file, containing:
- Task name and start time
- The script's stdout and stderr output
- End time, duration, and success/failure status

Example:
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

### Log cleanup

- Automatic: the scheduler checks every 6 hours and deletes logs older than 31 days
- Manual: `taskctl cleanup`
- The retention period is adjustable via `TASK_LOG_RETAIN_DAYS` in `env.conf`

## Running Tests

```bash
# Run all tests
bash tests/run_all.sh

# Run a single module's tests
bash tests/test_logger.sh
bash tests/test_config.sh
bash tests/test_executor.sh
bash tests/test_chain.sh
bash tests/test_cron_match.sh
bash tests/test_scheduler.sh
bash tests/test_taskctl.sh
```
