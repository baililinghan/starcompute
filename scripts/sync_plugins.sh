#!/bin/bash
# ============================================================
# StarCompute — 同步插件到所有用户
# ============================================================
# 将插件目录同步到所有已创建用户的 dsh 配置中。
# 用法: ./sync_plugins.sh [plugin_name]
#   不带参数 — 同步所有插件
#   带参数   — 只同步指定插件
# ============================================================

set -euo pipefail

# 配置
STARCOMPUTE_DIR="/opt/starcompute"
PLUGINS_DIR="${STARCOMPUTE_DIR}/plugins"
AUTH_SERVICE_DIR="${STARCOMPUTE_DIR}/auth-service"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[+]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 sudo 运行此脚本"
    exit 1
fi

# 获取所有用户列表（从系统用户中筛选有 dsh 配置的）
get_dsh_users() {
    for home in /home/*/; do
        username=$(basename "$home")
        if [ -d "${home}/.dsh" ] && id "$username" &>/dev/null; then
            echo "$username"
        fi
    done
}

# 同步插件到单个用户
sync_to_user() {
    local username="$1"
    local user_dsh="/home/${username}/.dsh"

    if [ ! -d "$user_dsh" ]; then
        log_warn "跳过 $username: .dsh 目录不存在"
        return
    fi

    # 创建插件目录
    mkdir -p "${user_dsh}/plugins"

    if [ -n "${PLUGIN_NAME:-}" ]; then
        # 同步指定插件
        local plugin_dir="${PLUGINS_DIR}/${PLUGIN_NAME}"
        if [ -d "$plugin_dir" ]; then
            cp -r "$plugin_dir" "${user_dsh}/plugins/"
            log_info "  ${PLUGIN_NAME} 已同步"
        else
            log_error "  插件目录不存在: $plugin_dir"
            return 1
        fi
    else
        # 同步所有插件
        if [ -d "$PLUGINS_DIR" ]; then
            for plugin in "${PLUGINS_DIR}"/*/; do
                if [ -d "$plugin" ]; then
                    plugin_name=$(basename "$plugin")
                    cp -r "$plugin" "${user_dsh}/plugins/"
                    log_info "  ${plugin_name} 已同步"
                fi
            done
        else
            log_warn "  插件目录不存在: $PLUGINS_DIR"
        fi
    fi

    # 设置权限
    chown -R "${username}:${username}" "${user_dsh}/plugins"
    chmod -R 755 "${user_dsh}/plugins"
}

# 主逻辑
PLUGIN_NAME="${1:-}"

echo "=========================================="
echo "  StarCompute 插件同步工具"
echo "=========================================="
echo ""

if [ -n "$PLUGIN_NAME" ]; then
    log_info "同步插件: $PLUGIN_NAME"
else
    log_info "同步所有插件"
fi
echo ""

USERS=$(get_dsh_users)
USER_COUNT=$(echo "$USERS" | wc -w)

if [ "$USER_COUNT" -eq 0 ]; then
    log_warn "未找到任何 dsh 用户"
    exit 0
fi

log_info "找到 $USER_COUNT 个用户"
echo ""

SYNCED=0
FAILED=0

for username in $USERS; do
    log_info "处理用户: $username"
    if sync_to_user "$username"; then
        ((SYNCED++))
    else
        ((FAILED++))
    fi
    echo ""
done

# 总结
echo "=========================================="
log_info "同步完成"
echo "  成功: $SYNCED"
echo "  失败: $FAILED"
echo "=========================================="
