#!/bin/bash
#=============================================================================
# install.sh - 任务调度系统一键部署脚本
#
# 用法：
#   bash install.sh                    # 部署到当前目录
#   bash install.sh /opt/task-scheduler # 部署到指定目录
#=============================================================================

set -e

INSTALL_DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " Task Scheduler - Install"
echo "========================================"
echo ""
echo "Install directory: ${INSTALL_DIR}"
echo ""

# 1. 如果目标目录不是源目录，复制文件
if [[ "${INSTALL_DIR}" != "${SOURCE_DIR}" ]]; then
    echo "[1/5] Copying files to ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"
    cp -r "${SOURCE_DIR}/bin"  "${INSTALL_DIR}/"
    cp -r "${SOURCE_DIR}/lib"  "${INSTALL_DIR}/"
    cp -r "${SOURCE_DIR}/conf" "${INSTALL_DIR}/"
    cp -r "${SOURCE_DIR}/tests" "${INSTALL_DIR}/"
    cp "${SOURCE_DIR}/env.conf" "${INSTALL_DIR}/"
    cp "${SOURCE_DIR}/README.md" "${INSTALL_DIR}/" 2>/dev/null || true
else
    echo "[1/5] Installing in source directory, skip copy."
fi

# 2. 创建运行时目录
echo "[2/5] Creating runtime directories..."
mkdir -p "${INSTALL_DIR}/logs/tasks"
mkdir -p "${INSTALL_DIR}/run"

# 3. 设置权限
echo "[3/5] Setting permissions..."
chmod +x "${INSTALL_DIR}/bin/taskctl"
chmod +x "${INSTALL_DIR}/lib/cron_match.py"
chmod +x "${INSTALL_DIR}/tests/"*.sh 2>/dev/null || true
chmod +x "${INSTALL_DIR}/install.sh" 2>/dev/null || true

# 4. 创建默认配置
if [[ ! -f "${INSTALL_DIR}/conf/tasks.conf" ]]; then
    echo "[4/5] Creating default config from example..."
    cp "${INSTALL_DIR}/conf/tasks.conf.example" "${INSTALL_DIR}/conf/tasks.conf"
else
    echo "[4/5] Config file already exists, skip."
fi

# 5. 环境检查
echo "[5/5] Checking environment..."

# 检查 bash 版本
bash_version=$(bash --version | head -1)
echo "  Bash: ${bash_version}"

# 检查 python3
if command -v python3 &>/dev/null; then
    py_version=$(python3 --version)
    echo "  Python: ${py_version}"
else
    echo "  WARNING: python3 not found. Please install Python 3.6+" >&2
fi

echo ""
echo "========================================"
echo " Installation complete!"
echo "========================================"
echo ""
echo "Quick start:"
echo "  1. Edit config:   vi ${INSTALL_DIR}/conf/tasks.conf"
echo "  2. Start daemon:  ${INSTALL_DIR}/bin/taskctl start"
echo "  3. Check status:  ${INSTALL_DIR}/bin/taskctl status"
echo "  4. View help:     ${INSTALL_DIR}/bin/taskctl help"
echo ""
echo "Optional: Add to PATH for convenience:"
echo "  export TASK_SCHEDULER_HOME=\"${INSTALL_DIR}\""
echo "  export PATH=\"\${TASK_SCHEDULER_HOME}/bin:\${PATH}\""
echo ""
echo "Run tests:"
echo "  bash ${INSTALL_DIR}/tests/run_all.sh"
