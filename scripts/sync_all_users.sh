#!/bin/bash
# 从cuimohan同步配置到所有用户
# 用法: bash sync_all_users.sh

TEMPLATE="cuimohan"
USERS=$(systemctl list-units --type=service --no-legend | grep 'dsh-' | sed 's/dsh-//;s/\.service.*//' | grep -v "^root$")

echo "=== 从 $TEMPLATE 同步配置到所有用户 ==="
echo "用户列表: $USERS"
echo ""

for USER in $USERS; do
    if [ "$USER" = "$TEMPLATE" ]; then
        echo "跳过 $USER (模板用户)"
        continue
    fi

    echo "--- 同步 $USER ---"

    # 1. 同步dsh配置
    echo "  1. 同步dsh配置..."
    cp /home/$TEMPLATE/.dsh/profiles/web/cordis.patch.yml /home/$USER/.dsh/profiles/web/
    cp /home/$TEMPLATE/.dsh/profiles/web/package.json /home/$USER/.dsh/profiles/web/

    # 2. 同步JS补丁
    echo "  2. 同步JS补丁..."
    TEMPLATE_MODULES="/home/$TEMPLATE/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai"
    USER_MODULES="/home/$USER/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai"

    # dsh-client-connection (isLoopbackHostname补丁)
    cp $TEMPLATE_MODULES/dsh-client-connection/lib/client.js $USER_MODULES/dsh-client-connection/lib/client.js
    cp $TEMPLATE_MODULES/dsh-client-connection/lib/index.js $USER_MODULES/dsh-client-connection/lib/index.js

    # dsh-client-ui-conversation (UI文案)
    cp $TEMPLATE_MODULES/dsh-client-ui-conversation/lib/client.js $USER_MODULES/dsh-client-ui-conversation/lib/client.js

    # 3. 同步插件链接
    echo "  3. 同步插件链接..."
    mkdir -p /home/$USER/.dsh/profiles/web/node_modules
    ln -sf /opt/dsh-plugins/dsh-file-upload /home/$USER/.dsh/profiles/web/node_modules/dsh-file-upload
    ln -sf /opt/dsh-plugins/dsh-file-upload /home/$USER/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/dsh-file-upload

    # 4. 设置权限
    echo "  4. 设置权限..."
    chown -R $USER:$USER /home/$USER/.dsh
    chown -R $USER:$USER /home/$USER/.local

    # 5. 重启服务
    echo "  5. 重启服务..."
    systemctl restart dsh-$USER

    echo "  完成: $USER"
    echo ""
done

sleep 5

echo "=== 验证所有用户 ==="
for USER in $USERS; do
    STATUS=$(systemctl is-active dsh-$USER)
    PORT=$(grep -o 'port [0-9]*' /etc/systemd/system/dsh-$USER.service | grep -o '[0-9]*')
    SEARCH=$(journalctl -u dsh-$USER --no-pager -n 5 | grep -c 'searxng')
    echo "$USER: $STATUS (端口: $PORT, 搜索: $SEARCH)"
done
