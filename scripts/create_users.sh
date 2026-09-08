#!/bin/bash
# ============================================================
# StarCompute — 批量创建用户脚本
# ============================================================
# 用法: ./create_users.sh users.txt
# 用户文件格式（每行一个用户）:
#   username password port dsh_token
#
# 示例 users.txt:
#   alice changeme_alice 8080 your_dsh_token_alice
#   bob changeme_bob 8081 your_dsh_token_bob
#   charlie changeme_charlie 8082 your_dsh_token_charlie
# ============================================================

set -euo pipefail

# 配置
STARCOMPUTE_DIR="/opt/starcompute"
AUTH_SERVICE_DIR="${STARCOMPUTE_DIR}/auth-service"
DSH_USER_SERVICE="/etc/systemd/system/dsh-user@.service"
AUTH_DB="${AUTH_SERVICE_DIR}/users.db"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[+]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

# 检查参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <users_file>"
    echo ""
    echo "用户文件格式（每行）："
    echo "  username password port dsh_token"
    exit 1
fi

USERS_FILE="$1"

if [ ! -f "$USERS_FILE" ]; then
    log_error "用户文件不存在: $USERS_FILE"
    exit 1
fi

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 sudo 运行此脚本"
    exit 1
fi

# 检查 auth-service 是否安装
if [ ! -d "$AUTH_SERVICE_DIR" ]; then
    log_error "未找到 auth-service 目录: $AUTH_SERVICE_DIR"
    log_error "请先运行 setup_server.sh"
    exit 1
fi

# 读取用户文件并创建
CREATED=0
SKIPPED=0
FAILED=0

while IFS=' ' read -r username password port dsh_token; do
    # 跳过空行和注释
    [[ -z "$username" || "$username" == \#* ]] && continue

    log_info "处理用户: $username (port: $port)"

    # 检查系统用户是否已存在
    if id "$username" &>/dev/null; then
        log_warn "系统用户 '$username' 已存在，跳过系统用户创建"
    else
        # 创建系统用户
        useradd -m -s /bin/bash "$username" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_info "  系统用户已创建"
        else
            log_error "  创建系统用户失败"
            ((FAILED++))
            continue
        fi
    fi

    # 设置密码
    echo "${username}:${password}" | chpasswd
    log_info "  密码已设置"

    # 复制 dsh 配置
    USER_HOME="/home/$username"
    mkdir -p "${USER_HOME}/.dsh/config"

    if [ -f "${STARCOMPUTE_DIR}/templates/cordis.patch.yml" ]; then
        cp "${STARCOMPUTE_DIR}/templates/cordis.patch.yml" "${USER_HOME}/.dsh/config/"
        log_info "  dsh 配置已复制"
    fi

    if [ -f "${STARCOMPUTE_DIR}/templates/package.json" ]; then
        cp "${STARCOMPUTE_DIR}/templates/package.json" "${USER_HOME}/.dsh/"
        log_info "  package.json 已复制"
    fi

    # 设置文件权限
    chown -R "${username}:${username}" "${USER_HOME}/.dsh"
    chmod 700 "${USER_HOME}/.dsh"

    # 启用并启动 dsh 用户服务
    systemctl enable "dsh-user@${username}" 2>/dev/null
    systemctl start "dsh-user@${username}" 2>/dev/null
    log_info "  dsh 服务已启动"

    # 注册到 auth 数据库（使用 Python）
    cd "$AUTH_SERVICE_DIR"
    python3 -c "
import asyncio, sys, os
sys.path.insert(0, '.')
from database import init_db, create_user, get_user_by_username
from auth import AuthService

async def register():
    await init_db()
    existing = await get_user_by_username('${username}')
    if existing:
        print('  用户已存在于数据库中')
        return
    auth = AuthService()
    pw_hash = auth.hash_password('${password}')
    await create_user('${username}', pw_hash, ${port}, '${dsh_token}')
    print('  用户已注册到数据库')

asyncio.run(register())
" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_info "  数据库注册成功"
        ((CREATED++))
    else
        log_error "  数据库注册失败"
        ((FAILED++))
    fi

    echo ""

done < "$USERS_FILE"

# 总结
echo "=========================================="
log_info "批量创建完成"
echo "  成功: $CREATED"
echo "  跳过: $SKIPPED"
echo "  失败: $FAILED"
echo "=========================================="
