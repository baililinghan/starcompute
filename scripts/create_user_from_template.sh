#!/bin/bash
# 用cuimohan的环境作为模板创建新用户
# 用法: bash create_user_from_template.sh <username> <password> <port>

USER="$1"
PASS="$2"
PORT="$3"
TEMPLATE="cuimohan"

if [ -z "$USER" ] || [ -z "$PASS" ] || [ -z "$PORT" ]; then
    echo "用法: bash create_user_from_template.sh <username> <password> <port>"
    exit 1
fi

echo "=== 创建用户 $USER (端口 $PORT, 模板: $TEMPLATE) ==="

# 1. 创建Linux用户
echo "1. 创建Linux用户..."
useradd -m -s /bin/bash $USER 2>/dev/null || echo "用户已存在"
echo "$USER:$PASS" | chpasswd

# 2. 复制cuimohan的dsh配置（cordis.patch.yml + package.json）
echo "2. 复制dsh配置..."
su - $USER -c "mkdir -p ~/.dsh/profiles/web"
cp /home/$TEMPLATE/.dsh/profiles/web/cordis.patch.yml /home/$USER/.dsh/profiles/web/
cp /home/$TEMPLATE/.dsh/profiles/web/package.json /home/$USER/.dsh/profiles/web/

# 3. 安装dsh（如果还没有）
echo "3. 安装dsh..."
su - $USER -c "npm config set prefix ~/.local"
if [ ! -f /home/$USER/.local/bin/dsh ]; then
    su - $USER -c "npm install -g @deepseek-ai/dsh@0.1.1-rc.2 --registry https://registry.npmmirror.com"
fi

# 4. 创建node_modules目录和dsh-file-upload链接
echo "4. 创建插件链接..."
su - $USER -c "mkdir -p ~/.dsh/profiles/web/node_modules"
ln -sf /opt/dsh-plugins/dsh-file-upload /home/$USER/.dsh/profiles/web/node_modules/dsh-file-upload

# 5. 创建dsh-file-upload在dsh node_modules中的链接
echo "5. 创建dsh内部链接..."
ln -sf /opt/dsh-plugins/dsh-file-upload /home/$USER/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/dsh-file-upload

# 6. 复制已修补的JS文件（isLoopbackHostname补丁 + UI文案）
echo "6. 复制JS补丁..."
DSH_MODULES="/home/$USER/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai"
TEMPLATE_MODULES="/home/$TEMPLATE/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai"

# dsh-client-connection (isLoopbackHostname补丁)
cp $TEMPLATE_MODULES/dsh-client-connection/lib/client.js $DSH_MODULES/dsh-client-connection/lib/client.js
cp $TEMPLATE_MODULES/dsh-client-connection/lib/index.js $DSH_MODULES/dsh-client-connection/lib/index.js

# dsh-client-ui-conversation (UI文案: 拓展人类生存空间/星际天算)
cp $TEMPLATE_MODULES/dsh-client-ui-conversation/lib/client.js $DSH_MODULES/dsh-client-ui-conversation/lib/client.js

# 7. 设置权限
echo "7. 设置权限..."
chown -R $USER:$USER /home/$USER/.dsh
chown -R $USER:$USER /home/$USER/.local

# 8. 创建systemd服务
echo "8. 创建systemd服务..."
cat > /etc/systemd/system/dsh-$USER.service << EOF
[Unit]
Description=StarCompute dsh - $USER
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER
ExecStart=/home/$USER/.local/bin/dsh web --no-open --port $PORT --trusted-host 10.12.120.93 --trusted-host 10.12.120.93:$PORT
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PLAYWRIGHT_BROWSERS_PATH=/opt/dsh-plugins/browser-automation/.browser

[Install]
WantedBy=multi-user.target
EOF

# 9. 启用并启动服务
echo "9. 启动服务..."
systemctl daemon-reload
systemctl enable dsh-$USER
systemctl start dsh-$USER

sleep 5

# 10. 验证
echo ""
echo "=== 验证 ==="
echo "用户: $(id $USER 2>/dev/null && echo 'OK' || echo 'FAIL')"
echo "dsh: $(systemctl is-active dsh-$USER)"
echo "端口: $(ss -tlnp | grep $PORT | wc -l)"
echo "搜索插件: $(journalctl -u dsh-$USER --no-pager -n 5 | grep -c 'searxng')"
echo ""
echo "=== 完成 ==="
echo "用户名: $USER"
echo "密码: $PASS"
echo "端口: $PORT"
