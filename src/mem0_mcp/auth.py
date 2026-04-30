import os
import secrets
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Literal

DB_PATH = os.getenv("MEM0_KEYS_DB", "./mem0_keys.db")

Role = Literal["admin", "user"]


@dataclass
class ApiKey:
    token: str
    user_id: str
    role: Role
    created_at: str


@contextmanager
def _conn():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    try:
        yield con
        con.commit()
    finally:
        con.close()


def init_db() -> None:
    with _conn() as con:
        con.execute("""
            CREATE TABLE IF NOT EXISTS api_keys (
                token      TEXT PRIMARY KEY,
                user_id    TEXT NOT NULL,
                role       TEXT NOT NULL CHECK(role IN ('admin', 'user')),
                created_at TEXT NOT NULL
            )
        """)

    bootstrap = os.getenv("MEM0_BOOTSTRAP_ADMIN_KEY", "").strip()
    if bootstrap:
        _seed_key(bootstrap, "bootstrap-admin", "admin")
    elif _table_empty():
        token = secrets.token_urlsafe(32)
        _seed_key(token, "bootstrap-admin", "admin")
        print(f"[mem0-mcp] Bootstrap admin key (save this): {token}", flush=True)


def _table_empty() -> bool:
    with _conn() as con:
        row = con.execute("SELECT COUNT(*) FROM api_keys").fetchone()
        return row[0] == 0


def _seed_key(token: str, user_id: str, role: Role) -> None:
    with _conn() as con:
        con.execute(
            "INSERT OR IGNORE INTO api_keys (token, user_id, role, created_at) VALUES (?, ?, ?, ?)",
            (token, user_id, role, _now()),
        )


def resolve(token: str) -> ApiKey | None:
    with _conn() as con:
        row = con.execute("SELECT * FROM api_keys WHERE token = ?", (token,)).fetchone()
    if row is None:
        return None
    return ApiKey(token=row["token"], user_id=row["user_id"], role=row["role"], created_at=row["created_at"])


def create_key(user_id: str, role: Role) -> ApiKey:
    token = secrets.token_urlsafe(32)
    created_at = _now()
    with _conn() as con:
        con.execute(
            "INSERT INTO api_keys (token, user_id, role, created_at) VALUES (?, ?, ?, ?)",
            (token, user_id, role, created_at),
        )
    return ApiKey(token=token, user_id=user_id, role=role, created_at=created_at)


def revoke_key(token: str) -> bool:
    with _conn() as con:
        cur = con.execute("DELETE FROM api_keys WHERE token = ?", (token,))
        return cur.rowcount > 0


def list_keys() -> list[ApiKey]:
    with _conn() as con:
        rows = con.execute("SELECT * FROM api_keys ORDER BY created_at").fetchall()
    return [ApiKey(token=r["token"], user_id=r["user_id"], role=r["role"], created_at=r["created_at"]) for r in rows]


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()
