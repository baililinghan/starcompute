"""
StarCompute Auth Service — FastAPI 主服务
功能：登录认证 + 反向代理（HTTP/WebSocket）到用户独立的 dsh 实例。

架构：
  用户浏览器 → Nginx(HTTPS) → 本服务(:8000) → dsh 实例(:8080+user_id)
  
关键技术：
  - bcrypt 密码验证
  - 签名 session cookie（无状态）
  - httpx 异步反向代理 + Host 头伪造（127.0.0.1:port）
  - WebSocket 双向转发（ws.accept）
"""
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import httpx

from config import HOST, PORT, DSH_SERVER_IP
from auth import AuthService
from database import init_db, get_user_by_username

logger = logging.getLogger("starcompute-auth")

# 全局 httpx 客户端（连接池复用）
http_client: httpx.AsyncClient = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理：初始化数据库和 HTTP 客户端"""
    global http_client
    await init_db()
    http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(300.0, connect=10.0),
        limits=httpx.Limits(max_connections=100, max_keepalive_connections=20)
    )
    logger.info("StarCompute Auth Service 已启动")
    yield
    await http_client.aclose()
    logger.info("StarCompute Auth Service 已关闭")


app = FastAPI(title="StarCompute Auth", lifespan=lifespan)

# 挂载静态文件（登录页面）
app.mount("/static", StaticFiles(directory="static"), name="static")


# ============================================================
# 工具函数
# ============================================================

def get_session_token(request: Request) -> str | None:
    """从 cookie 提取 session token"""
    return request.cookies.get("session")


def get_authenticated_user(request: Request) -> dict | None:
    """验证 session，返回用户信息或 None"""
    token = get_session_token(request)
    if not token:
        return None
    payload = AuthService.verify_session(token)
    if not payload:
        return None
    return payload


# ============================================================
# 认证路由
# ============================================================

@app.get("/_auth/login", response_class=HTMLResponse)
async def login_page():
    """返回登录页面"""
    with open("static/login.html", "r", encoding="utf-8") as f:
        return HTMLResponse(content=f.read())


@app.post("/_auth/login")
async def login(request: Request):
    """处理登录请求"""
    form = await request.form()
    username = form.get("username", "").strip()
    password = form.get("password", "")

    if not username or not password:
        return JSONResponse(
            {"error": "请输入用户名和密码"},
            status_code=400
        )

    # 查找用户
    user = await get_user_by_username(username)
    if not user:
        return JSONResponse(
            {"error": "用户名或密码错误"},
            status_code=401
        )

    # 验证密码
    if not AuthService.verify_password(password, user["password_hash"]):
        return JSONResponse(
            {"error": "用户名或密码错误"},
            status_code=401
        )

    # 创建 session
    session_token = AuthService.create_session(user["id"], user["username"])

    # 重定向到首页，设置 cookie
    response = RedirectResponse(url="/", status_code=302)
    response.set_cookie(
        key="session",
        value=session_token,
        httponly=True,
        samesite="lax",
        max_age=86400  # 24 小时
    )
    logger.info(f"用户 '{username}' 登录成功")
    return response


@app.post("/_auth/logout")
async def logout():
    """登出：清除 session cookie"""
    response = RedirectResponse(url="/_auth/login", status_code=302)
    response.delete_cookie("session")
    return response


@app.get("/_auth/check")
async def auth_check(request: Request):
    """检查当前认证状态（供前端调用）"""
    user = get_authenticated_user(request)
    if user:
        return JSONResponse({"authenticated": True, "username": user["username"]})
    return JSONResponse({"authenticated": False}, status_code=401)


# ============================================================
# HTTP 反向代理（catch-all）
# ============================================================

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"])
async def proxy_http(request: Request, path: str):
    """
    将所有未匹配的 HTTP 请求代理到用户对应的 dsh 实例。
    - 验证 session 获取用户信息
    - 构造目标 URL（127.0.0.1:port）
    - 伪造 Host 头为 127.0.0.1:port（dsh 要求）
    - 替换 Origin 头
    - 转发请求并返回响应
    """
    # 验证认证
    user = get_authenticated_user(request)
    if not user:
        return RedirectResponse(url="/_auth/login", status_code=302)

    # 获取用户的完整信息（端口）
    user_db = await get_user_by_username(user["username"])
    if not user_db:
        return JSONResponse({"error": "用户配置异常"}, status_code=500)

    target_port = user_db["port"]

    # 构造目标 URL
    target_url = f"http://127.0.0.1:{target_port}/{path}"
    if request.url.query:
        target_url += f"?{request.url.query}"

    # 构造请求头 — 伪造 Host 和 Origin
    headers = dict(request.headers)
    headers["host"] = f"127.0.0.1:{target_port}"

    # 替换 Origin 头（防止 CORS 问题）
    if "origin" in headers:
        headers["origin"] = f"http://127.0.0.1:{target_port}"

    # 移除 hop-by-hop 头
    for hop_header in ["connection", "keep-alive", "transfer-encoding"]:
        headers.pop(hop_header, None)

    # 读取请求体
    body = await request.body()

    try:
        # 转发请求
        resp = await http_client.request(
            method=request.method,
            url=target_url,
            headers=headers,
            content=body if body else None
        )

        # 构造响应
        response_headers = dict(resp.headers)
        # 移除 hop-by-hop 响应头
        for hop_header in ["connection", "keep-alive", "transfer-encoding", "content-encoding"]:
            response_headers.pop(hop_header, None)

        return Response(
            content=resp.content,
            status_code=resp.status_code,
            headers=response_headers
        )

    except httpx.ConnectError:
        logger.error(f"无法连接到 dsh 实例 127.0.0.1:{target_port}")
        return JSONResponse(
            {"error": "后端服务不可用，请联系管理员"},
            status_code=502
        )
    except Exception as e:
        logger.error(f"代理请求异常: {e}")
        return JSONResponse(
            {"error": "代理请求失败"},
            status_code=500
        )


# ============================================================
# WebSocket 反向代理
# ============================================================

@app.websocket("/ws/{path:path}")
async def proxy_websocket(websocket: WebSocket, path: str):
    """
    WebSocket 双向代理。
    - 通过 cookie 验证身份
    - 连接到用户对应的 dsh 实例的 WebSocket
    - 双向转发消息（客户端 ↔ 本服务 ↔ dsh）
    """
    # 验证认证（从 cookie 中获取 token）
    session_token = websocket.cookies.get("session")
    if not session_token:
        await websocket.close(code=4001, reason="未认证")
        return

    payload = AuthService.verify_session(session_token)
    if not payload:
        await websocket.close(code=4001, reason="Session 已过期")
        return

    # 获取用户端口
    user_db = await get_user_by_username(payload["username"])
    if not user_db:
        await websocket.close(code=4002, reason="用户不存在")
        return

    target_port = user_db["port"]

    # 构造目标 WebSocket URL
    ws_url = f"ws://127.0.0.1:{target_port}/{path}"
    if websocket.url.query:
        ws_url += f"?{websocket.url.query}"

    try:
        # 先接受客户端的 WebSocket 连接
        await websocket.accept()

        # 连接到后端 dsh 的 WebSocket
        from starlette.websockets import WebSocketState
        import websockets

        async with websockets.connect(
            ws_url,
            extra_headers={"Host": f"127.0.0.1:{target_port}"}
        ) as backend_ws:
            logger.info(f"WebSocket 代理已建立: {payload['username']} -> {ws_url}")

            # 双向转发
            async def forward_to_backend():
                """客户端 → 后端"""
                try:
                    while True:
                        data = await websocket.receive_text()
                        await backend_ws.send(data)
                except WebSocketDisconnect:
                    logger.info("客户端 WebSocket 断开")
                except Exception as e:
                    logger.error(f"客户端→后端转发异常: {e}")

            async def forward_to_client():
                """后端 → 客户端"""
                try:
                    async for message in backend_ws:
                        if isinstance(message, str):
                            await websocket.send_text(message)
                        else:
                            await websocket.send_bytes(message)
                except Exception as e:
                    logger.error(f"后端→客户端转发异常: {e}")

            # 并发运行双向转发
            await asyncio.gather(
                forward_to_backend(),
                forward_to_client(),
                return_exceptions=True
            )

    except Exception as e:
        logger.error(f"WebSocket 代理异常: {e}")
        try:
            if websocket.client_state == WebSocketState.CONNECTED:
                await websocket.close(code=4000, reason="代理连接失败")
        except Exception:
            pass


# ============================================================
# 入口
# ============================================================

if __name__ == "__main__":
    import uvicorn
    logging.basicConfig(level=logging.INFO)
    uvicorn.run("app:app", host=HOST, port=PORT, reload=False, log_level="info")
