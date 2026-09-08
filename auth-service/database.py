"""
StarCompute Auth Service — 数据库层
使用 aiosqlite 异步操作 SQLite，管理 users 表。
"""
import aiosqlite
from datetime import datetime
from config import DB_PATH


async def get_db() -> aiosqlite.Connection:
    """获取数据库连接"""
    db = await aiosqlite.connect(DB_PATH)
    db.row_factory = aiosqlite.Row
    return db


async def init_db():
    """初始化数据库表结构"""
    db = await get_db()
    try:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                port INTEGER NOT NULL,
                dsh_token TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        await db.commit()
    finally:
        await db.close()


async def create_user(username: str, password_hash: str, port: int, dsh_token: str = None) -> dict:
    """创建新用户，返回用户信息"""
    db = await get_db()
    try:
        cursor = await db.execute(
            "INSERT INTO users (username, password_hash, port, dsh_token) VALUES (?, ?, ?, ?)",
            (username, password_hash, port, dsh_token)
        )
        await db.commit()
        return {
            "id": cursor.lastrowid,
            "username": username,
            "port": port,
            "dsh_token": dsh_token,
            "created_at": datetime.now().isoformat()
        }
    finally:
        await db.close()


async def get_user_by_username(username: str) -> dict | None:
    """按用户名查找用户"""
    db = await get_db()
    try:
        cursor = await db.execute(
            "SELECT * FROM users WHERE username = ?", (username,)
        )
        row = await cursor.fetchone()
        if row:
            return dict(row)
        return None
    finally:
        await db.close()


async def get_user_by_id(user_id: int) -> dict | None:
    """按 ID 查找用户"""
    db = await get_db()
    try:
        cursor = await db.execute(
            "SELECT * FROM users WHERE id = ?", (user_id,)
        )
        row = await cursor.fetchone()
        if row:
            return dict(row)
        return None
    finally:
        await db.close()


async def get_all_users() -> list[dict]:
    """获取所有用户（不含密码哈希）"""
    db = await get_db()
    try:
        cursor = await db.execute(
            "SELECT id, username, port, dsh_token, created_at FROM users ORDER BY id"
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]
    finally:
        await db.close()


async def delete_user(username: str) -> bool:
    """删除用户"""
    db = await get_db()
    try:
        cursor = await db.execute(
            "DELETE FROM users WHERE username = ?", (username,)
        )
        await db.commit()
        return cursor.rowcount > 0
    finally:
        await db.close()


async def update_user_token(username: str, dsh_token: str) -> bool:
    """更新用户的 dsh_token"""
    db = await get_db()
    try:
        cursor = await db.execute(
            "UPDATE users SET dsh_token = ? WHERE username = ?",
            (dsh_token, username)
        )
        await db.commit()
        return cursor.rowcount > 0
    finally:
        await db.close()
