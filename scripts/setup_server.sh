#!/bin/bash
# ============================================================
# StarCompute — 一键服务器初始化脚本
# ============================================================
# 在全新的 Ubuntu/Debian 服务器上运行此脚本，自动完成：
#   1. 系统依赖安装（Python、Node.js、Nginx）
#   2. 项目文件部署
#   3. Python 虚拟环境创建
#   4. systemd 服务安装
#   5. Nginx 配置
#   6. 防火墙规则
#
# 用法:
#   sudo ./setup_server.sh
#
# 前置条件：
#   - Ubuntu 20.04+ / Debian 11+
#   - root 权限
#   - 可访问互联网（apt 源）
# ============================================================

set -euo pipefail

# ============================================================
# 配置 — 部署前请修改以下变量
# ============================================================
STARCOMPUTE_DIR="/opt/starcompute"
AUTH_SERVICE_DIR="${STARCOMPUTE_DIR}/auth-service"
DOMAIN="your-domain.com"                    # 替换为实际域名
SERVER_IP="your-server-ip"                  # 替换为实际 IP
DSH_BASE_PORT=8080                          # dsh 端口起始值
AUTH_SECRET_KEY="$(openssl rand -hex 32)"   # 自动生成随机密钥

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[+]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }
log_step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# ============================================================
# 检查前置条件
# ============================================================
log_step "检查前置条件"

if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 sudo 运行此脚本"
    exit 1
fi

# 检测操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    log_info "操作系统: $PRETTY_NAME"
else
    log_error "无法检测操作系统"
    exit 1
fi

# ============================================================
# 1. 系统更新和依赖安装
# ============================================================
log_step "安装系统依赖"

apt-get update -qq
apt-get install -y -qq \
    python3 python3-pip python3-venv \
    nginx \
    certbot python3-certbot-nginx \
    curl wget git \
    sqlite3 \
    > /dev/null 2>&1

log_info "系统依赖已安装"

# ============================================================
# 2. 部署项目文件
# ============================================================
log_step "部署项目文件"

# 如果是本地运行（非从 repo clone），复制当前目录
if [ -d "$(dirname "$0")/../auth-service" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    log_info "从本地目录复制: $SCRIPT_DIR"

    mkdir -p "$STARCOMPUTE_DIR"
    cp -r "${SCRIPT_DIR}/auth-service" "$STARCOMPUTE_DIR/"
    cp -r "${SCRIPT_DIR}/templates" "$STARCOMPUTE_DIR/"
    cp -r "${SCRIPT_DIR}/scripts" "$STARCOMPUTE_DIR/"
    cp -r "${SCRIPT_DIR}/plugins" "$STARCOMPUTE_DIR/"
else
    log_error "未找到项目文件，请在项目根目录运行此脚本"
    exit 1
fi

# 设置脚本可执行权限
chmod +x "${STARCOMPUTE_DIR}/scripts/"*.sh

log_info "项目文件已部署到 $STARCOMPUTE_DIR"

# ============================================================
# 3. 创建 Python 虚拟环境
# ============================================================
log_step "创建 Python 虚拟环境"

python3 -m venv "${AUTH_SERVICE_DIR}/venv"
source "${AUTH_SERVICE_DIR}/venv/bin/activate"
pip install --quiet -r "${AUTH_SERVICE_DIR}/requirements.txt"

log_info "Python 虚拟环境已创建并安装依赖"

# ============================================================
# 4. 生成环境配置文件
# ============================================================
log_step "生成环境配置"

cat > "${AUTH_SERVICE_DIR}/.env" << EOF
# StarCompute Auth Service 环境配置
# 生成时间: $(date)

AUTH_HOST=0.0.0.0
AUTH_PORT=8000
AUTH_DB_PATH=${AUTH_SERVICE_DIR}/users.db
AUTH_SECRET_KEY=${AUTH_SECRET_KEY}
DSH_SERVER_IP=127.0.0.1
DSH_BASE_PORT=${DSH_BASE_PORT}
SESSION_MAX_AGE=86400
EOF

chmod 600 "${AUTH_SERVICE_DIR}/.env"
log_info "环境配置已生成（密钥已自动创建）"

# ============================================================
# 5. 初始化数据库
# ============================================================
log_step "初始化数据库"

cd "$AUTH_SERVICE_DIR"
source venv/bin/activate
python3 -c "
import asyncio
import sys
sys.path.insert(0, '.')
from database import init_db

asyncio.run(init_db())
print('数据库已初始化')
"

log_info "数据库已初始化"

# ============================================================
# 6. 安装 systemd 服务
# ============================================================
log_step "安装 systemd 服务"

# 复制服务文件
cp "${STARCOMPUTE_DIR}/templates/starcompute-auth.service" /etc/systemd/system/
cp "${STARCOMPUTE_DIR}/templates/dsh-user.service" /etc/systemd/system/

# 更新认证服务的环境文件路径
sed -i "s|EnvironmentFile=.*|EnvironmentFile=${AUTH_SERVICE_DIR}/.env|g" \
    /etc/systemd/system/starcompute-auth.service

systemctl daemon-reload
systemctl enable starcompute-auth.service
systemctl start starcompute-auth.service

log_info "systemd 服务已安装并启动"

# ============================================================
# 7. 配置 Nginx
# ============================================================
log_step "配置 Nginx"

# 复制并修改 Nginx 配置
cp "${STARCOMPUTE_DIR}/templates/nginx.conf" /etc/nginx/sites-available/starcompute
sed -i "s/your-domain.com/${DOMAIN}/g" /etc/nginx/sites-available/starcompute

# 如果没有 SSL 证书，先用 HTTP 配置
if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
    log_warn "未找到 SSL 证书，使用 HTTP 配置"
    cat > /etc/nginx/sites-available/starcompute << 'NGINX_CONF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
    }
}
NGINX_CONF
    sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" /etc/nginx/sites-available/starcompute
fi

# 启用站点
ln -sf /etc/nginx/sites-available/starcompute /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

log_info "Nginx 配置完成"

# ============================================================
# 8. 配置防火墙
# ============================================================
log_step "配置防火墙"

if command -v ufw &>/dev/null; then
    ufw allow 22/tcp   # SSH
    ufw allow 80/tcp   # HTTP
    ufw allow 443/tcp  # HTTPS
    ufw --force enable
    log_info "防火墙已配置"
else
    log_warn "未找到 ufw，请手动配置防火墙"
fi

# ============================================================
# 完成
# ============================================================
log_step "安装完成"

echo ""
echo "=========================================="
echo "  StarCompute 服务器初始化完成"
echo "=========================================="
echo ""
echo "  访问地址: http://${DOMAIN}"
echo "  服务状态: systemctl status starcompute-auth"
echo "  配置文件: ${AUTH_SERVICE_DIR}/.env"
echo "  数据库:   ${AUTH_SERVICE_DIR}/users.db"
echo ""
echo "下一步："
echo "  1. 编辑 ${AUTH_SERVICE_DIR}/.env 修改配置"
echo "  2. 创建用户: ${STARCOMPUTE_DIR}/scripts/create_single_user.sh"
echo "  3. 配置 SSL: certbot --nginx -d ${DOMAIN}"
echo "  4. 安装 dsh 到各用户目录"
echo ""
