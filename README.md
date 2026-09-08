# StarCompute

**多用户 AI 工作站部署工具包** — 让每个用户拥有独立的 dsh 实例，通过统一的认证网关访问。

基于 [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness) + vLLM，一台 GPU 服务器即可服务整个团队。

## 架构

```
用户浏览器 ──HTTPS──▶ Nginx (443)
                          │
                          ▼
                    Auth Service (FastAPI, :5000)
                          │
                          ├── POST /_auth/login   → bcrypt 认证 → session cookie
                          ├── GET  /_auth/check   → 验证 session
                          ├── WS   /*             → WebSocket 双向转发
                          └── GET/POST /*          → HTTP 反向代理
                                │
                                ├── Host: 127.0.0.1:{port}  ← 关键：伪造 Host 头
                                ├── Origin: http://127.0.0.1:{port}
                                │
                                ▼
                    ┌── dsh-alice  (:3091) ──┐
                    ├── dsh-bob    (:3093) ──┤── 共享 vLLM (:8000)
                    ├── dsh-carol  (:3094) ──┤       │
                    └── dsh-N      (:30XX) ──┘   Qwen3.8-27B (BF16, TP8)
```

每个用户拥有：
- 独立的 Linux 系统账户
- 独立的 dsh 进程（独立端口，独立会话存储）
- 独立的插件配置
- 共享的 vLLM 后端（256 并发才饱和，多人无压力）

## 快速开始

### 前置条件

- Linux 服务器（Ubuntu 22.04+），NVIDIA GPU（24GB+ 显存）
- Python 3.10+、Node.js 22+、Nginx
- vLLM 或 Ollama 已部署

### 1. 克隆项目

```bash
git clone https://github.com/baililinghan/starcompute.git
cd starcompute
```

### 2. 部署 vLLM

```bash
vllm serve Qwen/Qwen3.8-27B \
  --port 8000 \
  --tensor-parallel-size 8 \
  --dtype bfloat16 \
  --max-model-len 262144 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --served-model-name qwen3.8-27b
```

### 3. 一键初始化服务器

```bash
# 编辑配置
vim scripts/setup_server.sh   # 修改 SERVER_IP 等变量

# 运行（需要 root）
sudo bash scripts/setup_server.sh
```

### 4. 创建用户

```bash
# 单个用户
sudo bash scripts/create_single_user.sh <username> <password> <port>

# 批量创建（从文件读取）
# users.txt 格式：每行 username password port
sudo bash scripts/create_users.sh users.txt
```

### 5. 初始化数据库

```bash
cd auth-service
source venv/bin/activate
# 编辑 init_users.py 中的用户列表
python3 init_users.py
systemctl restart starcompute-auth
```

### 6. 访问

浏览器打开 `https://your-server-ip`，接受证书警告，登录即可。

## 目录结构

```
starcompute/
├── README.md
├── LICENSE
├── auth-service/
│   ├── app.py              # FastAPI：登录 + 反向代理 + WebSocket
│   ├── auth.py             # bcrypt 密码哈希 + session 验证
│   ├── database.py         # aiosqlite CRUD
│   ├── config.py           # 环境变量配置
│   ├── init_users.py       # 用户初始化脚本
│   ├── requirements.txt    # Python 依赖
│   └── static/
│       └── login.html      # 黑金风格登录页
├── templates/
│   ├── cordis.patch.yml    # dsh 插件配置模板
│   ├── package.json        # dsh profile bundles 模板
│   ├── dsh-user.service    # systemd 单元模板
│   ├── starcompute-auth.service
│   └── nginx.conf
├── scripts/
│   ├── setup_server.sh     # 一键服务器初始化
│   ├── create_users.sh     # 批量创建用户
│   ├── create_single_user.sh
│   └── sync_plugins.sh     # 同步插件到所有用户
└── plugins/
    └── README.md           # 插件安装指南
```

## 技术栈

| 组件 | 技术 |
|------|------|
| 认证服务 | FastAPI + uvicorn |
| 密码哈希 | bcrypt（⚠️ 不用 passlib） |
| 数据库 | SQLite (aiosqlite) |
| HTTP 代理 | httpx（异步连接池） |
| WebSocket 代理 | websockets ≥16.0 |
| 反向代理 | Nginx (HTTPS + WebSocket) |
| 进程管理 | systemd |
| 前端 | 原生 HTML/CSS/JS |

---

## 踩坑记录（实战验证）

> 以下所有问题均在 2026-09-08 部署中实际遇到并解决。

### 🔴 dsh 版本：必须用 0.1.1-rc.2

dsh 0.1.2-rc.1 改用了 `??` 打包语法加载插件，浏览器访问返回 404，页面黑屏。

```bash
# 安装时指定版本
npm install -g @deepseek-ai/dsh@0.1.1-rc.2

# 验证
dsh --version  # 必须显示 0.1.1-rc.2
```

`@latest` 可能拉到 0.1.2-rc.1，批量部署时务必锁定版本。

### 🔴 settings.unavailable：dsh 的双重 loopback 检查

dsh 的 `settings.describe` 是特权方法，**客户端和服务端都有 isLoopbackHostname 检查**。只改一端不够。

**服务端**：检查 HTTP `Host` 头是否为 localhost → 代理设置 `Host: 127.0.0.1:{port}` 即可。

**客户端**：检查浏览器 `location.hostname` 是否为 localhost → 从 IP 访问时返回 false，settings 镜像进入 "memory" 模式（永不调用 settings.describe）。

**完整解决方案**（缺一不可）：

1. **Auth 代理设置 Host 头**：
```python
headers["host"] = f"127.0.0.1:{port}"
headers["origin"] = f"http://127.0.0.1:{port}"
```

2. **Patch 服务端 `lib/index.js`**（行号替换，非正则）：
```bash
# 先找到行号
grep -n 'function isLoopbackHostname' /path/to/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/index.js
# 用行号替换（假设第 100-104 行）
sed -i '100,104c\function isLoopbackHostname() { return true; }' lib/index.js
node -c lib/index.js  # 验证语法
```

3. **Patch 客户端 `lib/client.js`**（同样用行号替换）：
```bash
grep -n 'function isLoopbackHostname' lib/client.js
# 假设第 10249-10253 行
sed -i '10249,10253c\\t\tfunction isLoopbackHostname() { return true; }' lib/client.js
node -c lib/client.js  # 验证语法
```

### 🔴 绝对不要用正则替换 JS 文件

```bash
# ❌ 这会破坏文件，导致 "loaded without registering via __ModuleLoader__.load"
sed -i 's/function isLoopbackHostname(hostname) {/function isLoopbackHostname() { return true; }/' file.js

# ✅ 正确做法：用行号精确替换
sed -i '100,104c\function isLoopbackHostname() { return true; }' file.js
```

**原因**：正则 `[^}]+` 在嵌套代码中提前匹配到内部的 `}`，留下垃圾语法。`__ModuleLoader__` 检查文件完整性，patched 文件注册失败。

**恢复方法**：如果误用了正则，恢复 `.bak` 备份并重启所有 dsh 实例。

### 🔴 用户级文件必须单独更新

dsh 每个用户有独立的 npm 安装（`~/.local/lib/node_modules/`）。修改全局文件不会影响用户副本。

```bash
# ❌ 只改全局
sed -i '100,104c\...' /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/.../lib/index.js

# ✅ 改全局 + 所有用户
for user in alice bob carol; do
  cp /usr/local/.../lib/index.js /home/$user/.local/.../lib/index.js
  chown $user:$user /home/$user/.local/.../lib/index.js
done
systemctl restart dsh-alice dsh-bob dsh-carol
```

### 🔴 WebSocket 代理：Starlette 必须显式 accept

```python
@app.websocket("/{path:path}")
async def websocket_proxy(ws: WebSocket, path: str):
    # ⚠️ 必须第一行就 accept，否则 uvicorn 报：
    # "ASGI callable returned without sending handshake"
    await ws.accept()  # ← 这行不能省，不能放在 if 后面
    # ... 然后才能做验证、转发等操作
```

### 🔴 websockets v16+ API 变更

```python
# ❌ v16 以前的写法
websockets.connect(url, extra_headers=headers, ping_interval=30, ping_timeout=10)

# ✅ v16+ 正确写法
websockets.connect(url, additional_headers=headers, open_timeout=10)
# 不要传 ping_interval/ping_timeout，v16 中位置已变
```

### 🔴 客户端插件需要三件事

插件有前端 UI（如上传按钮）时，**只配 cordis.patch.yml 不够**。

| 配置 | 作用 | 缺少的后果 |
|------|------|-----------|
| `cordis.patch.yml` insert | 加载服务端代码 | 工具不可用 |
| `package.json` bundles | 告诉模块系统加载 client.js | 前端 UI 不出现 |
| `package.json` dependencies `link:` | Node.js 模块解析 | 启动报 ERR_MODULE_NOT_FOUND |

`~/.dsh/profiles/web/package.json` 示例：
```json
{
  "name": "dsh-profile-web",
  "private": true,
  "dsh": {
    "profile": {
      "bundles": ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "dsh-file-upload"]
    }
  },
  "dependencies": {
    "dsh-file-upload": "link:/opt/dsh-plugins/dsh-file-upload"
  }
}
```

### 🔴 不能重复注册插件

同一个插件不能同时出现在 cordis insert 和 package.json bundles 中，否则报：

```
Error: duplicate loader entry id: file-upload
```

**规则**：有 client.js 的插件 → 放 package.json（bundles + dependencies），不在 cordis insert 中重复。

### 🟡 dsh CORS：Origin 必须伪造

dsh 拒绝来自非 localhost Origin 的请求，返回 403。

```python
# 代理中必须替换 Origin
headers["origin"] = f"http://127.0.0.1:{port}"
# 同时去掉 Referer
```

### 🟡 auth 路由前缀：用 /_auth/ 不用 /api/

dsh 的 API 端点都以 `/api/` 开头。如果认证服务也用 `/api/login`，FastAPI 的 catch-all 路由会拦截 dsh 的 API 调用，返回 403。

```
❌ /api/login, /api/logout    → 和 dsh 的 /api/host.describe 冲突
✅ /_auth/login, /_auth/logout → 不冲突
```

### 🟡 passlib 在 Python 3.10+ 卡死

`passlib[bcrypt]==1.7.4` 读取 `bcrypt.__about__.__version__` 失败后无限重试，**脚本挂起不崩溃**。

```python
# ❌ 不要用
from passlib.context import CryptContext

# ✅ 直接用 bcrypt
import bcrypt
hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt())
verified = bcrypt.checkpw(password.encode(), hashed)
```

### 🟡 SameSite cookie 代理问题

dsh 设置 `SameSite=Strict`，通过代理访问时浏览器不发送 cookie。

```python
# 代理转发 Set-Cookie 时替换
v = v.replace("SameSite=Strict", "SameSite=Lax")
```

### 🟡 SQLite 损坏恢复

脚本被 kill -9 中断时，SQLite 可能损坏（`disk I/O error`）。

```bash
# 删除数据库和 WAL/SHM 文件，重新初始化
rm -f users.db users.db-wal users.db-shm
python3 init_users.py
systemctl restart starcompute-auth
```

### 🟡 cordis.patch.yml 缩进敏感

YAML 缩进错误会导致 `duplicated mapping key` 或静默丢失配置。

```bash
# ❌ 不要用 sed 插入单行（容易搞乱缩进）
sed -i '/pattern/a\\new_line' cordis.patch.yml

# ✅ 用 write_file / cat 写整个文件
cat > cordis.patch.yml << 'EOF'
- id: llm-pi-ai
  config:
    providers:
      vllm:
        ...
EOF
```

### 🟡 npm 国内镜像

服务器在国外源下载慢或被墙时：

```bash
npm config set registry https://registry.npmmirror.com
# 安装时不要设 HTTP_PROXY（镜像直连，代理反而 ECONNRESET）
unset HTTP_PROXY HTTPS_PROXY
npm install -g @deepseek-ai/dsh@0.1.1-rc.2
```

### 🟡 Qwen3.8 必须传 reasoning_effort

vLLM + Qwen3.8 模型不传 `reasoning_effort` 会返回 400。

```yaml
# cordis.patch.yml 中模型必须配置
models:
  - id: qwen3.8-27b
    reasoningEfforts:
      off: medium    # 用户不选级别时的默认值
      medium: medium
      low: low
      xhigh: xhigh
```

`off` 是 dsh 在用户未选择推理级别时发送的值。没有它，dsh 发送 `null`，vLLM 拒绝。

### 🟡 crypto.randomUUID 安全策略

浏览器的 `crypto.randomUUID()` 只在安全上下文可用（HTTPS 或 localhost）。直接通过 IP 访问（`http://10.x.x.x:3081`）时静默失败，UI 加载但聊天不工作。

**解决方案**（三选一）：
1. HTTPS（自签名证书即可）
2. SSH 隧道到 localhost
3. 本项目的 Auth 代理 + HTTPS

### 🟡 Node.js 版本要求

dsh 需要 Node.js ≥22.12.0。服务器默认的 v20 会报 EBADENGINE。

```bash
# 升级方法
n lts   # 安装最新 LTS（当前 v24）
node --version
```

---

## 品牌定制

### 修改界面文案

修改 dsh 界面的主标题和徽标文案：

```bash
# 默认修改为"拓展人类生存空间" + "星际天算"
sudo bash scripts/update_branding.sh

# 自定义文案
sudo bash scripts/update_branding.sh "你的主标题" "你的徽标"
```

**注意**：
- 修改在 `node_modules` 中，dsh 升级/重装后会回退到出厂默认
- 如需持久化，可在 `scripts/setup_server.sh` 中加入此脚本
- 仅修改中文语言包，英文版保持默认

### 修改登录页面

登录页面样式在 `auth-service/static/login.html`：
- 主题色：`#0a0a0a`（背景）、`#c9a84c`（金色强调）
- 字体：Cinzel（衬线体）
- 修改后重启认证服务：`systemctl restart starcompute-auth`

---

## 安全部署检查清单

- [ ] 修改所有 `CHANGE_ME` / `your_password` / `your-server-ip` 占位符
- [ ] `config.py` 的 `SECRET_KEY` 设为随机值（`openssl rand -hex 32`）
- [ ] 生成自签名证书或配置 Let's Encrypt
- [ ] vLLM 端口 8000 用 iptables 限制为内网访问
- [ ] 数据库文件 `.db` 不提交到版本控制（已在 .gitignore）
- [ ] 确认 dsh 版本为 0.1.1-rc.2（`dsh --version`）
- [ ] 确认 Qwen3.8 模型配置了 `reasoningEfforts`
- [ ] 确认所有用户的 cordis.patch.yml 语法正确（`python3 -c 'import yaml; yaml.safe_load(open(f))'`）

## License

[MIT](LICENSE)

## Credits

Built on [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) by DeepSeek AI.
