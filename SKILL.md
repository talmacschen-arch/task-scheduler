---
name: task-scheduler
description: Cron-based task scheduling system. Schedule and execute shell/python scripts for database functional and performance testing. Use when user needs to set up timed tasks, manage task chains, manually trigger tests, view currently running tasks, or view execution logs.
metadata: { "openclaw": { "emoji": "⏰", "requires": { "bins": ["bash", "python3", "date", "find", "kill"], "config": ["TASK_SCHEDULER_HOME"] }, "execution": { "timeout_seconds": 30, "concurrent": false, "resource_level": "medium" } } }
---

# Task Scheduler Skill

Schedule and execute shell/python test scripts on cron-based timing, with task chain support.

## Quick Reference

| Action | Purpose | Common Parameters |
|--------|---------|-------------------|
| `start` | Start scheduler daemon | `config`, `foreground` |
| `stop` | Stop scheduler daemon | - |
| `status` | Check scheduler status | - |
| `running` | View currently running task | - |
| `run` | Manually trigger task | `task_name` **(required)** |
| `list` | List all tasks | `config` |
| `log` | View execution logs | `task_name` **(required)**, `count` |
| `cleanup` | Clean expired logs | - |
| `check` | Test cron expression | `cron_expr` **(required)** |
| `add_task` | Add new task/chain | See detailed parameters below |

## When to Use

✅ **USE this skill when:**

- "Set up a scheduled test task"
- "Run database test every day at 2am"
- "Create a task chain for regression testing"
- "Manually trigger a test task"
- "Check task execution logs"
- "View currently running task"
- "Start/stop the task scheduler"
- "List all scheduled tasks"
- "Add a new cron task"
- "View test execution history"

## When NOT to Use

❌ **DON'T use this skill when:**

- Parallel/distributed task execution → use distributed job schedulers (Airflow, etc.)
- Complex DAG workflows → this only supports linear chains
- Alert/notification on failure → not supported, use monitoring tools
- Web UI for task management → CLI only
- Sub-second scheduling precision → minimum granularity is 1 minute

## Configuration

### Environment

Set `TASK_SCHEDULER_HOME` to the installation root:

```bash
export TASK_SCHEDULER_HOME="/opt/task-scheduler"
export PATH="${TASK_SCHEDULER_HOME}/bin:${PATH}"
```

### Environment Config (`env.conf`)

```yaml
TASK_CONFIG: "conf/tasks.conf"        # Task config file path
TASK_LOG_DIR: "logs"                  # Log directory
TASK_RUN_DIR: "run"                   # PID file directory
TASK_LOG_RETAIN_DAYS: 31              # Log retention days
TASK_DEFAULT_TIMEOUT: 0               # Default timeout (0=unlimited)
TASK_LOG_LEVEL: 1                     # 0=DEBUG 1=INFO 2=WARN 3=ERROR
TASK_PYTHON3: "python3"               # Python3 interpreter path
TASK_POLL_INTERVAL: 60                # Scheduler check interval (seconds)
TASK_LOG_CLEANUP_INTERVAL: 21600      # Log cleanup interval (seconds)
```

### Task Config Format (`conf/tasks.conf`)

Standalone task:
```
# min hour day month weekday  task_name  script_path
30 2 * * *  backup_test  /opt/scripts/backup_test.sh
0  8 * * 1  perf_test    /opt/scripts/perf_test.py
```

Task chain:
```
chain <chain_name> [stop_on_failure|continue_on_failure]
  <cron_fields>  <task_name>  <script_path>
  >>             <task_name>  <script_path>
end
```

Cron field syntax: `*` any, `*/N` step, `N` fixed, `N,M` list, `N-M` range. Weekday: 0,7=Sun, 1=Mon, 6=Sat.

## Tool Call Specification

All tool calls must follow this format:

```json
{
  "action": "<action_name>",
  "parameters": {
    // action-specific parameters
  }
}
```

### Parameter Conventions
- **Required parameters**: Marked as `(required)`
- **Optional parameters**: Marked as `(optional, default: value)`
- **Types**: Explicitly specified as string/number/boolean/array/object

### Error Response Format
All errors are returned via standard tool error mechanism:

```json
{
  "error": {
    "code": "<ERROR_CODE>",
    "message": "<Human readable error message>",
    "details": {
      // Additional context (optional)
    }
  }
}
```

Common error codes:
- `CONFIG_NOT_FOUND`: Configuration file missing
- `SCHEDULER_RUNNING`: Scheduler already running  
- `SCHEDULER_NOT_RUNNING`: Scheduler not running
- `TASK_NOT_FOUND`: Specified task doesn't exist
- `SCRIPT_NOT_FOUND`: Script path invalid
- `INVALID_CRON`: Cron expression syntax error
- `CHAIN_NOT_CLOSED`: Missing 'end' in chain definition
- `PERMISSION_DENIED`: Insufficient file permissions

## Actions

### `start` - Start Scheduler Daemon

Start the background scheduling daemon.

**Parameters:**
- `config` (optional, default: `${TASK_SCHEDULER_HOME}/conf/tasks.conf`): Path to custom config file
- `foreground` (optional, default: `false`): Run in foreground mode for debugging

**Tool Call:**
```json
{
  "action": "start",
  "parameters": {}
}
```

**With custom config:**
```json
{
  "action": "start",
  "parameters": {
    "config": "/path/to/custom.conf",
    "foreground": true
  }
}
```

### `stop` - Stop Scheduler Daemon

Gracefully stop the running daemon. Waits for current task to finish.

**Parameters:** None

**Tool Call:**
```json
{
  "action": "stop",
  "parameters": {}
}
```

### `status` - Check Scheduler Status

Show whether the daemon is running, list loaded tasks, and display the currently running task (if any).

**Parameters:** None

**Tool Call:**
```json
{
  "action": "status",
  "parameters": {}
}
```

### `running` - View Currently Running Task

Show detailed information about the task that is currently being executed.

**Parameters:** None

**Tool Call:**
```json
{
  "action": "running",
  "parameters": {}
}
```

### `run` - Manually Trigger a Task

Execute a task immediately, regardless of its cron schedule.

**Parameters:**
- `task_name` (required, string): Name of the task to run

**Tool Call:**
```json
{
  "action": "run",
  "parameters": {
    "task_name": "backup_test"
  }
}
```

### `list` - List All Tasks

Show all configured tasks and chains.

**Parameters:**
- `config` (optional): Path to config file to list from

**Tool Call:**
```json
{
  "action": "list",
  "parameters": {}
}
```

### `log` - View Task Execution Logs

View recent execution logs for a specific task.

**Parameters:**
- `task_name` (required, string): Name of the task
- `count` (optional, default: 1, number): Number of recent logs to show

**Tool Call:**
```json
{
  "action": "log",
  "parameters": {
    "task_name": "backup_test",
    "count": 5
  }
}
```

### `cleanup` - Clean Up Expired Logs

Delete log files older than retention period (default 31 days).

**Parameters:** None

**Tool Call:**
```json
{
  "action": "cleanup",
  "parameters": {}
}
```

### `check` - Test Cron Expression

Verify if a cron expression matches the current time.

**Parameters:**
- `cron_expr` (required, string): Cron expression to test

**Tool Call:**
```json
{
  "action": "check",
  "parameters": {
    "cron_expr": "*/5 * * * *"
  }
}
```

### `add_task` - Add a New Task

Add a task entry to the config file.

**Parameters for standalone task:**
- `cron` (required, string): Cron schedule expression
- `task_name` (required, string): Unique task name
- `script` (required, string): Path to executable script

**Parameters for task chain:**
- `chain_name` (required, string): Unique chain name
- `on_failure` (optional, default: "stop", string): "stop" or "continue"
- `tasks` (required, array): Array of task objects

**Standalone task example:**
```json
{
  "action": "add_task",
  "parameters": {
    "cron": "0 3 * * *",
    "task_name": "new_test",
    "script": "/opt/scripts/new_test.sh"
  }
}
```

**Task chain example:**
```json
{
  "action": "add_task",
  "parameters": {
    "chain_name": "regression_test",
    "on_failure": "stop",
    "tasks": [
      {"cron": "0 4 * * *", "name": "test_connect", "script": "/opt/scripts/test_connect.sh"},
      {"name": "test_crud", "script": "/opt/scripts/test_crud.sh"},
      {"name": "test_perf", "script": "/opt/scripts/test_perf.py"}
    ]
  }
}
```

### `version` - Show Version Info

**Parameters:** None

**Tool Call:**
```json
{
  "action": "version",
  "parameters": {}
}
```

## Response Formats

### Success Response Wrapper
All successful responses follow this pattern:

```json
{
  "success": true,
  "data": {
    // Action-specific response data
  },
  "metadata": {
    "timestamp": "2026-03-22T04:10:00Z",
    "scheduler_home": "/opt/task-scheduler"
  }
}
```

### Task Execution Result
```json
{
  "success": true,
  "data": {
    "task_name": "backup_test",
    "status": "SUCCESS",
    "exit_code": 0,
    "duration_seconds": 15,
    "log_file": "logs/tasks/backup_test/20260320_023000.log",
    "message": "Task completed successfully"
  }
}
```

### Chain Execution Result
```json
{
  "success": true,
  "data": {
    "chain_name": "daily_func_check",
    "status": "FAILED",
    "policy": "stop_on_failure",
    "total": 3,
    "succeeded": 1,
    "failed_tasks": ["func_test_crud"],
    "skipped": 1,
    "duration_seconds": 42,
    "message": "Chain terminated: func_test_crud failed with exit code 1"
  }
}
```

### Status Response
```json
{
  "success": true,
  "data": {
    "running": true,
    "pid": 12345,
    "schedulable_tasks": 5,
    "config_file": "/opt/task-scheduler/conf/tasks.conf",
    "current_task": {
      "name": "backup_test",
      "pid": 12380,
      "started": "2026-03-20 02:30:00"
    }
  }
}
```

### Running Task Response
When a task is running:
```json
{
  "success": true,
  "data": {
    "has_running_task": true,
    "task_name": "backup_test",
    "task_pid": 12380,
    "script": "/opt/scripts/backup_test.sh",
    "started": "2026-03-20 02:30:00",
    "elapsed": "3m42s"
  }
}
```

When no task is running:
```json
{
  "success": true,
  "data": {
    "has_running_task": false,
    "message": "No task is currently running."
  }
}
```

### List Response
```json
{
  "success": true,
  "data": {
    "tasks": [
      {"name": "backup_test", "cron": "30 2 * * *", "script": "/opt/scripts/backup_test.sh", "chain": null},
      {"name": "func_test_1", "cron": "0 6 * * *", "script": "/opt/scripts/func_test_1.sh", "chain": "daily_check"}
    ],
    "chains": [
      {"name": "daily_check", "policy": "stop", "tasks": ["func_test_1", "func_test_2", "func_test_3"]}
    ]
  }
}
```

### Check Response
```json
{
  "success": true,
  "data": {
    "cron_expr": "*/5 * * * *",
    "current_time": "2026-03-20 14:30",
    "match": true
  }
}
```

## Usage Examples

### Complete Workflow: Set Up Daily Test

**User request:** "每天凌晨 3 点跑一次数据库备份验证测试"

**Assistant workflow:**
1. First, create the test script:
   ```bash
   cat > /opt/scripts/backup_verify.sh << 'EOF'
   #!/bin/bash
   psql -h localhost -U gpadmin -c "SELECT count(*) FROM backup_log WHERE backup_date = current_date;"
   EOF
   chmod +x /opt/scripts/backup_verify.sh
   ```

2. Add the scheduled task:
   ```json
   {
     "action": "add_task",
     "parameters": {
       "cron": "0 3 * * *",
       "task_name": "backup_verify",
       "script": "/opt/scripts/backup_verify.sh"
     }
   }
   ```

3. Verify it works by running manually:
   ```json
   {
     "action": "run",
     "parameters": {
       "task_name": "backup_verify"
     }
   }
   ```

4. Check the logs to confirm success:
   ```json
   {
     "action": "log",
     "parameters": {
       "task_name": "backup_verify",
       "count": 1
     }
   }
   ```

### Debugging Failed Task

**User request:** "backup_verify 昨晚执行失败了，帮我看看日志"

**Assistant action:**
```json
{
  "action": "log",
  "parameters": {
    "task_name": "backup_verify",
    "count": 3
  }
}
```

**Expected response handling:**
- If logs show database connection error → suggest checking DB credentials
- If logs show script permission error → suggest `chmod +x` on script
- If no logs found → suggest running task manually first

## Security & Permissions

### Required Permissions
- **File system**: Read/write access to `${TASK_SCHEDULER_HOME}`
- **Process**: Ability to spawn child processes and manage PIDs
- **Network**: None (unless test scripts require it)

### Security Best Practices
- ⚠️ **Never run as root**: Scripts execute with scheduler's privileges
- ⚠️ **Secure script permissions**: Set `chmod 700` on scripts containing credentials
- ⚠️ **Restrict log access**: Execution logs may contain sensitive output
- ⚠️ **Validate script paths**: Always verify script existence before adding tasks

### Sandbox Considerations
In OpenClaw sandboxed environments:
- File system access limited to allowed directories
- Process spawning may be restricted
- Network access controlled by sandbox policy

## Performance Characteristics

| Aspect | Details |
|--------|---------|
| **Memory usage** | ~10-50MB (scales with number of tasks) |
| **CPU usage** | Minimal (<1% when idle, spikes during task execution) |
| **Disk I/O** | Moderate (log writing, cleanup operations) |
| **Startup time** | <2 seconds |
| **Task latency** | ±30 seconds (due to 60-second polling interval) |

### Scaling Limits
- **Maximum tasks**: ~1000 (practical limit due to config file size)
- **Concurrent tasks**: Limited by system resources (no built-in concurrency control)
- **Log retention**: Configurable, default 31 days (~1GB per 100 tasks/month)

## Dependencies

| Tool | Purpose | Required For | Version |
|------|---------|--------------|---------|
| `bash` | Shell runtime | All operations | 4.0+ |
| `python3` | Cron expression matching | Scheduler, `check` | 3.6+ |
| `date` | Timestamp generation | Logging, scheduling | Any |
| `find` | Log file cleanup | `cleanup`, auto-cleanup | Any |
| `kill`/`ps` | Process management | `start`, `stop`, `status` | Any |
| `sleep` | Timing control | Scheduler loop | Any |

## Related Skills

- `post-upgrade-test` - Database post-upgrade verification testing
- `healthcheck` - System health verification

## Troubleshooting Guide

### Common Issues & Solutions

| Symptom | Likely Cause | Resolution |
|---------|--------------|------------|
| `Config file not found` | tasks.conf missing | Run `bash install.sh` or copy from tasks.conf.example |
| `Scheduler is already running` | Duplicate start | Run `taskctl stop` first, or check `taskctl status` |
| `Scheduler is not running` | Stop without start | Already stopped, no action needed |
| `Task not found` | Invalid task name | Run `taskctl list` to see available tasks |
| `Script not found` | Script path incorrect | Verify script exists and path is correct in config |
| `No logs found for task` | Task never executed | Run the task first with `taskctl run <name>` |
| `Invalid cron expression` | Syntax error in cron | Use `taskctl check` to validate expression |
| `Chain not closed` | Missing `end` in config | Add `end` after last chain task in config |
| `python3 not found` | Python not installed | Install Python 3.6+ or set `TASK_PYTHON3` in env.conf |
| `Permission denied` | Script not executable | Run `chmod +x <script_path>` |

### Diagnostic Commands
```bash
# Check if scheduler is running
ps aux | grep scheduler.sh

# View scheduler logs
tail -f ${TASK_SCHEDULER_HOME}/logs/scheduler.log

# Check config syntax
bash ${TASK_SCHEDULER_HOME}/lib/config.sh --validate

# Test cron matching manually
python3 ${TASK_SCHEDULER_HOME}/lib/cron_match.py "*/5 * * * *"
```

## Related Skills

- `post-upgrade-test` - Database post-upgrade verification testing

