#!/bin/bash
# ============================================================
# StarCompute — 单用户创建脚本
# ============================================================
# 用法: ./create_single_user.sh <username> <password> <port> [dsh_token]
#
# 示例:
#   ./create_single_user.sh alice changeme_alice 8080 your_dsh_token
# ============================================================

set -euo pipefail

# 配置
STARCOMPUTE_DIR="/opt/starcompute"
AUTH_SERVICE_DIR="${STARCOMPUTE_DIR}/auth-service"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[+]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

# 检查参数
if [ $# -lt 3 ]; then
    echo "用法: $0 <username> <password> <port> [dsh_token]"
    exit 1
fi

USERNAME="$1"
PASSWORD="$2"
PORT="$3"
DSH_TOKEN="${4:-}"

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 sudo 运行此脚本"
    exit 1
fi

log_info "创建用户: $USERNAME (port: $PORT)"

# 1. 创建系统用户
if id "$USERNAME" &>/dev/null; then
    log_warn "系统用户 '$USERNAME' 已存在"
else
    useradd -m -s /bin/bash "$USERNAME"
    log_info "系统用户已创建"
fi

# 2. 设置密码
echo "${USERNAME}:${PASSWORD}" | chpasswd
log_info "密码已设置"

# 3. 复制 dsh 配置
USER_HOME="/home/$USERNAME"
mkdir -p "${USER_HOME}/.dsh/config"

if [ -f "${STARCOMPUTE_DIR}/templates/cordis.patch.yml" ]; then
    cp "${STARCOMPUTE_DIR}/templates/cordis.patch.yml" "${USER_HOME}/.dsh/config/"
    log_info "dsh 配置已复制"
fi

if [ -f "${STARCOMPUTE_DIR}/templates/package.json" ]; then
    cp "${STARCOMPUTE_DIR}/templates/package.json" "${USER_HOME}/.dsh/"
    log_info "package.json 已复制"
fi

# 4. 设置文件权限
chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}/.dsh"
chmod 700 "${USER_HOME}/.dsh"

# 5. 启用并启动 dsh 用户服务
systemctl enable "dsh-user@${USERNAME}" 2>/dev/null
systemctl start "dsh-user@${USERNAME}" 2>/dev/null
log_info "dsh 服务已启动"

# 6. 注册到 auth 数据库
cd "$AUTH_SERVICE_DIR"
python3 -c "
import asyncio, sys, os
sys.path.insert(0, '.')
from database import init_db, create_user, get_user_by_username
from auth import AuthService

async def register():
    await init_db()
    existing = await get_user_by_username('${USERNAME}')
    if existing:
        print('用户已存在于数据库中')
        return
    auth = AuthService()
    pw_hash = auth.hash_password('${PASSWORD}')
    dsh_token = '${DSH_TOKEN}' if '${DSH_TOKEN}' else None
    await create_user('${USERNAME}', pw_hash, ${PORT}, dsh_token)
    print('用户已注册到数据库')

asyncio.run(register())
"

log_info "用户 '$USERNAME' 创建完成"
echo ""
echo "  登录地址: https://your-domain.com"
echo "  用户名:   $USERNAME"
echo "  端口:     $PORT"
echo ""
