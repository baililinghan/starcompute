#!/usr/bin/env python3
"""
StarCompute — 用户初始化脚本
在数据库中批量创建用户，分配端口和 dsh token。
部署时请替换下方的占位符。
"""
import asyncio
import sys
import os

# 将 auth-service 目录加入 path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from database import init_db, create_user, get_user_by_username
from auth import AuthService
from config import DSH_BASE_PORT

# ============================================================
# 用户配置模板 — 部署时替换为真实信息
# ============================================================
USERS = [
    {
        "username": "alice",
        "password": "changeme_alice",
        "port_offset": 0,          # 实际端口 = DSH_BASE_PORT + port_offset
        "dsh_token": "your_dsh_token_alice"
    },
    {
        "username": "bob",
        "password": "changeme_bob",
        "port_offset": 1,
        "dsh_token": "your_dsh_token_bob"
    },
    {
        "username": "charlie",
        "password": "changeme_charlie",
        "port_offset": 2,
        "dsh_token": "your_dsh_token_charlie"
    },
    # 按需添加更多用户...
]


async def main():
    """初始化数据库并创建用户"""
    print("[*] 初始化数据库...")
    await init_db()

    auth = AuthService()

    for user_cfg in USERS:
        username = user_cfg["username"]

        # 检查用户是否已存在
        existing = await get_user_by_username(username)
        if existing:
            print(f"[!] 用户 '{username}' 已存在，跳过")
            continue

        # 创建用户
        password_hash = auth.hash_password(user_cfg["password"])
        port = DSH_BASE_PORT + user_cfg["port_offset"]

        await create_user(
            username=username,
            password_hash=password_hash,
            port=port,
            dsh_token=user_cfg.get("dsh_token")
        )
        print(f"[+] 创建用户: {username} -> 127.0.0.1:{port}")

    print("[*] 用户初始化完成。")


if __name__ == "__main__":
    asyncio.run(main())
