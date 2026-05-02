import os

import httpx

_BASE_URL = os.getenv("MEM0_BASE_URL", "http://localhost:8000").rstrip("/")
_API_KEY = os.getenv("MEM0_API_KEY", "")

_headers = {"X-Api-Key": _API_KEY} if _API_KEY else {}
_client = httpx.Client(base_url=_BASE_URL, headers=_headers, timeout=30)


def _raise(r: httpx.Response) -> httpx.Response:
    r.raise_for_status()
    return r


def add_memory(messages: list[dict], user_id: str, metadata: dict | None = None) -> dict:
    body: dict = {"messages": messages, "user_id": user_id}
    if metadata:
        body["metadata"] = metadata
    return _raise(_client.post("/memories", json=body)).json()


def search_memories(query: str, user_id: str, limit: int = 10) -> dict:
    body = {"query": query, "filters": {"user_id": user_id}, "limit": limit}
    return _raise(_client.post("/search", json=body)).json()


def get_memories(user_id: str, limit: int = 50) -> dict:
    return _raise(_client.get("/memories", params={"user_id": user_id, "limit": limit})).json()


def get_memory(memory_id: str) -> dict:
    return _raise(_client.get(f"/memories/{memory_id}")).json()


def update_memory(memory_id: str, data: str) -> dict:
    return _raise(_client.put(f"/memories/{memory_id}", json={"data": data})).json()


def delete_memory(memory_id: str) -> dict:
    return _raise(_client.delete(f"/memories/{memory_id}")).json()
