import contextvars
import os

from mcp.server.fastmcp import FastMCP
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from . import auth, client

mcp = FastMCP("mem0")

_current_key: contextvars.ContextVar[auth.ApiKey | None] = contextvars.ContextVar("current_key", default=None)


# ── auth middleware ───────────────────────────────────────────────────────────

class BearerAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        header = request.headers.get("Authorization", "")
        token = header.removeprefix("Bearer ").strip()
        key = auth.resolve(token)
        if key is None:
            return Response("Unauthorized", status_code=401, media_type="text/plain")
        _current_key.set(key)
        return await call_next(request)


# ── helpers ───────────────────────────────────────────────────────────────────

def _key() -> auth.ApiKey:
    k = _current_key.get()
    if k is None:
        raise PermissionError("No authenticated key in context")
    return k


def _require_admin() -> auth.ApiKey:
    k = _key()
    if k.role != "admin":
        raise PermissionError("Admin key required")
    return k


def _resolve_user(key: auth.ApiKey, requested: str | None) -> str:
    if key.role == "admin" and requested:
        return requested
    return key.user_id


# ── memory tools ──────────────────────────────────────────────────────────────

@mcp.tool()
def add_memory(content: str, user_id: str | None = None, metadata: dict | None = None) -> dict:
    """Store a new memory. Admin can specify any user_id; user is scoped to own."""
    k = _key()
    return client.add_memory([{"role": "user", "content": content}], _resolve_user(k, user_id), metadata)


@mcp.tool()
def search_memories(query: str, user_id: str | None = None, limit: int = 10) -> dict:
    """Search memories by semantic similarity."""
    k = _key()
    return client.search_memories(query, _resolve_user(k, user_id), limit)


@mcp.tool()
def get_memories(user_id: str | None = None, limit: int = 50) -> dict:
    """List all memories for a user."""
    k = _key()
    return client.get_memories(_resolve_user(k, user_id), limit)


@mcp.tool()
def get_memory(memory_id: str) -> dict:
    """Fetch a single memory by ID."""
    _key()
    return client.get_memory(memory_id)


@mcp.tool()
def update_memory(memory_id: str, data: str) -> dict:
    """Update the text of an existing memory."""
    _key()
    return client.update_memory(memory_id, data)


@mcp.tool()
def delete_memory(memory_id: str) -> dict:
    """Delete a single memory by ID."""
    _key()
    return client.delete_memory(memory_id)


# ── admin tools ───────────────────────────────────────────────────────────────

@mcp.tool()
def create_api_key(user_id: str, role: str = "user") -> dict:
    """Create a new API key. role must be 'admin' or 'user'. Admin only."""
    _require_admin()
    if role not in ("admin", "user"):
        raise ValueError("role must be 'admin' or 'user'")
    new_key = auth.create_key(user_id, role)  # type: ignore[arg-type]
    return {"token": new_key.token, "user_id": new_key.user_id, "role": new_key.role, "created_at": new_key.created_at}


@mcp.tool()
def revoke_api_key(target_token: str) -> dict:
    """Revoke an API key. Admin only."""
    _require_admin()
    removed = auth.revoke_key(target_token)
    return {"revoked": removed}


@mcp.tool()
def list_api_keys() -> list[dict]:
    """List all API keys. Admin only."""
    _require_admin()
    return [
        {"token": k.token, "user_id": k.user_id, "role": k.role, "created_at": k.created_at}
        for k in auth.list_keys()
    ]


# ── entrypoint ────────────────────────────────────────────────────────────────

def main() -> None:
    auth.init_db()
    transport = os.getenv("MEM0_MCP_TRANSPORT", "http")
    if transport == "stdio":
        mcp.run(transport="stdio")
    else:
        port = int(os.getenv("MEM0_MCP_PORT", "6969"))
        app = mcp.streamable_http_app()
        app.add_middleware(BearerAuthMiddleware)
        import uvicorn
        uvicorn.run(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
