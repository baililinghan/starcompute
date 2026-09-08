"""
StarCompute Auth Service — 认证逻辑
bcrypt 密码哈希/验证 + 基于签名的 session token 管理。
"""
import bcrypt
import hashlib
import hmac
import json
import time
import base64
from config import SECRET_KEY, SESSION_MAX_AGE


class AuthService:
    """认证服务：密码管理 + session 签名验证"""

    @staticmethod
    def hash_password(password: str) -> str:
        """使用 bcrypt 对密码进行哈希"""
        salt = bcrypt.gensalt()
        hashed = bcrypt.hashpw(password.encode("utf-8"), salt)
        return hashed.decode("utf-8")

    @staticmethod
    def verify_password(password: str, password_hash: str) -> bool:
        """验证密码是否匹配 bcrypt 哈希"""
        try:
            return bcrypt.checkpw(
                password.encode("utf-8"),
                password_hash.encode("utf-8")
            )
        except Exception:
            return False

    @staticmethod
    def create_session(user_id: int, username: str) -> str:
        """
        创建签名 session token。
        结构：base64(json(payload)) + "." + signature
        payload 包含 user_id, username, exp（过期时间戳）
        """
        payload = {
            "user_id": user_id,
            "username": username,
            "exp": int(time.time()) + SESSION_MAX_AGE
        }
        payload_bytes = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        payload_b64 = base64.urlsafe_b64encode(payload_bytes).decode("utf-8").rstrip("=")

        # HMAC-SHA256 签名
        signature = hmac.new(
            SECRET_KEY.encode("utf-8"),
            payload_b64.encode("utf-8"),
            hashlib.sha256
        ).hexdigest()

        return f"{payload_b64}.{signature}"

    @staticmethod
    def verify_session(token: str) -> dict | None:
        """
        验证 session token，返回 payload 或 None。
        检查签名有效性 + 是否过期。
        """
        try:
            parts = token.split(".")
            if len(parts) != 2:
                return None

            payload_b64, signature = parts

            # 验证签名
            expected_sig = hmac.new(
                SECRET_KEY.encode("utf-8"),
                payload_b64.encode("utf-8"),
                hashlib.sha256
            ).hexdigest()

            if not hmac.compare_digest(signature, expected_sig):
                return None

            # 解码 payload
            # 补齐 base64 padding
            padded = payload_b64 + "=" * (4 - len(payload_b64) % 4)
            payload_bytes = base64.urlsafe_b64decode(padded)
            payload = json.loads(payload_bytes)

            # 检查过期
            if payload.get("exp", 0) < time.time():
                return None

            return payload

        except Exception:
            return None
