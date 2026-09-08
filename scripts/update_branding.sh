#!/bin/bash
# 修改所有用户的dsh界面品牌文案
# 用法: bash scripts/update_branding.sh "主标题" "徽标"
# 默认: "拓展人类生存空间" "星际天算"

HEADLINE="${1:-拓展人类生存空间}"
PREVIEW="${2:-星际天算}"

# 获取所有dsh用户（从systemd服务列表）
USERS=$(systemctl list-units --type=service --no-legend | grep 'dsh-' | sed 's/.*dsh-//;s/\.service.*//')

if [ -z "$USERS" ]; then
  echo "未找到dsh用户服务"
  exit 1
fi

echo "主标题: $HEADLINE"
echo "徽标: $PREVIEW"
echo ""

for user in $USERS; do
  # 尝试多个可能的路径
  FILE=""
  for path in \
    "/home/$user/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js" \
    "/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js"; do
    if [ -f "$path" ]; then
      FILE="$path"
      break
    fi
  done

  if [ -z "$FILE" ]; then
    echo "$user: client.js 未找到"
    continue
  fi

  # 修改中文语言包的 hero.headline
  # 匹配模式: "hero.headline": "旧文案" (在中文语言包区域内)
  sed -i "/\"hero\.headline\"/{s/\"hero\.headline\": \"[^\"]*\"/\"hero.headline\": \"$HEADLINE\"/}" "$FILE"

  # 修改中文语言包的 hero.preview
  sed -i "/\"hero\.preview\"/{s/\"hero\.preview\": \"[^\"]*\"/\"hero.preview\": \"$PREVIEW\"/}" "$FILE"

  # 验证
  H=$(grep -c "$HEADLINE" "$FILE")
  P=$(grep -c "$PREVIEW" "$FILE")
  if [ "$H" -ge 1 ] && [ "$P" -ge 1 ]; then
    echo "$user: ✅ 已更新 (headline=$H, preview=$P)"
  else
    echo "$user: ⚠️ 更新可能不完整 (headline=$H, preview=$P)"
  fi
done

# 重启所有dsh服务
echo ""
echo "重启dsh服务..."
systemctl restart dsh-* 2>/dev/null
sleep 5

echo ""
for user in $USERS; do
  echo "dsh-$user: $(systemctl is-active dsh-$user 2>/dev/null || echo '未知')"
done
