# StarCompute

多用户 AI 工作站部署工具包 — 让每个用户拥有独立的 dsh 实例，通过统一的认证网关访问。

## 架构

```
用户浏览器 ──HTTPS──▶ Nginx ──▶ Auth Service (:8000) ──▶ dsh 实例 (:8080+N)
                                    │
                                    ├── 登录认证 (bcrypt + session)
                                    ├── HTTP 反向代理 (Host 头伪造)
                                    └── WebSocket 双向转发
```

每个用户拥有：
- 独立的系统账户
- 独立的 dsh 进程（独立端口）
- 独立的插件配置
- 共享的 vLLM 后端

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/your-org/starcompute.git
cd starcompute
```

### 2. 一键部署

```bash
# 编辑配置
vim scripts/setup_server.sh   # 修改 DOMAIN 和 SERVER_IP

# 运行初始化（需要 root）
sudo ./scripts/setup_server.sh
```

### 3. 创建用户

```bash
# 单个用户
sudo ./scripts/create_single_user.sh alice changeme_alice 8080 your_dsh_token

# 批量创建
echo "alice changeme_alice 8080 your_dsh_token" > users.txt
echo "bob changeme_bob 8081 your_dsh_token_bob" >> users.txt
sudo ./scripts/create_users.sh users.txt
```

### 4. 配置 SSL

```bash
sudo certbot --nginx -d your-domain.com
```

### 5. 同步插件

```bash
sudo ./scripts/sync_plugins.sh
```

## 目录结构

```
starcompute/
├── auth-service/            # 认证 + 反向代理服务
│   ├── app.py               # FastAPI 主服务
│   ├── auth.py              # 认证逻辑（bcrypt + session）
│   ├── database.py          # 数据库 CRUD
│   ├── config.py            # 配置文件
│   ├── init_users.py        # 用户初始化脚本
│   ├── requirements.txt     # Python 依赖
│   └── static/
│       └── login.html       # 黑金风格登录页
├── templates/               # 部署模板
│   ├── cordis.patch.yml     # dsh 插件配置
│   ├── package.json         # dsh profile bundles
│   ├── dsh-user.service     # 用户 dsh 服务单元
│   ├── starcompute-auth.service  # 认证服务单元
│   └── nginx.conf           # Nginx 配置
├── scripts/                 # 运维脚本
│   ├── setup_server.sh      # 一键服务器初始化
│   ├── create_users.sh      # 批量创建用户
│   ├── create_single_user.sh # 单用户创建
│   └── sync_plugins.sh      # 同步插件到所有用户
├── plugins/                 # 插件目录
│   └── README.md            # 插件安装指南
├── .gitignore
├── LICENSE                  # MIT
└── README.md
```

## 技术栈

| 组件 | 技术 |
|------|------|
| 认证服务 | FastAPI + uvicorn |
| 密码哈希 | bcrypt |
| 数据库 | SQLite (aiosqlite) |
| HTTP 代理 | httpx (异步连接池) |
| WebSocket 代理 | websockets |
| 反向代理 | Nginx (HTTPS + WebSocket) |
| 进程管理 | systemd |
| 前端 | 原生 HTML/CSS/JS |

## 关键设计决策

### Host 头伪造

Auth Service 在代理请求时将 `Host` 头替换为 `127.0.0.1:port`，使每个用户的 dsh 实例收到的请求看起来是本地调用。这是多用户隔离的核心机制。

### 无状态 Session

Session token 使用 HMAC-SHA256 签名，payload 包含用户信息和过期时间，无需服务端 session 存储。数据库仅存储用户凭据，不存储 session 状态。

### WebSocket 代理

WebSocket 连接通过 `ws.accept()` 先接受客户端连接，再建立到后端的 `websockets.connect()` 连接，使用 `asyncio.gather` 并发双向转发消息。

## 安全注意事项

- 部署前必须修改所有 `CHANGE_ME` / `your_password` 占位符
- `.env` 文件权限设为 600，仅 root 可读
- 使用 HTTPS（Let's Encrypt 免费证书）
- 定期更新密码和 dsh token
- 数据库文件不应提交到版本控制

## License

[MIT](LICENSE)
