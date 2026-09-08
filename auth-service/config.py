"""
StarCompute Auth Service — 配置文件
所有敏感值通过环境变量或此文件设置，部署时请替换占位符。
"""
import os

# 服务监听地址
HOST = os.getenv("AUTH_HOST", "0.0.0.0")
PORT = int(os.getenv("AUTH_PORT", "8000"))

# 数据库路径
DB_PATH = os.getenv("AUTH_DB_PATH", "/opt/starcompute/auth-service/users.db")

# Session 密钥 — 部署时必须替换为随机值
SECRET_KEY = os.getenv("AUTH_SECRET_KEY", "CHANGE_ME_TO_A_RANDOM_SECRET_KEY")

# 后端 dsh 实例的基础 IP（每个用户有独立端口）
DSH_SERVER_IP = os.getenv("DSH_SERVER_IP", "your-server-ip")

# dsh 端口范围起始值（用户端口 = BASE_PORT + user_id）
DSH_BASE_PORT = int(os.getenv("DSH_BASE_PORT", "8080"))

# Session cookie 有效期（秒）
SESSION_MAX_AGE = int(os.getenv("SESSION_MAX_AGE", "86400"))  # 24 小时
