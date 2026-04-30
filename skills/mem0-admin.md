---
name: mem0-admin
description: >
  mem0 API key and user management. Admin-only.
  TRIGGER only when: user explicitly asks to create, revoke, or list API keys;
  provision access for a new user or app; audit who has memory access.
  DO NOT TRIGGER for memory read/write operations (use mem0-memory skill).
license: MIT
metadata:
  author: GungIndi
  version: "0.1.0"
  category: ai-memory
  tags: "memory, mem0, admin, api-keys, user-management"
compatibility: Requires admin API key. mem0-mcp-server must be running.
---

# mem0-admin — API Key Management

Admin-only tools. Requires a key with `role: admin`.

## Tools

| Tool | Description |
|------|-------------|
| `create_api_key` | Provision a new user or admin key |
| `revoke_api_key` | Remove access for a key |
| `list_api_keys` | Audit all keys, roles, and user_ids |

## Create a key

```
create_api_key(user_id="alice", role="user")
→ { "token": "...", "user_id": "alice", "role": "user", "created_at": "..." }
```

Roles: `user` (scoped to own memories) or `admin` (any user_id, all admin tools).

## Revoke a key

```
revoke_api_key(target_token="<token>")
→ { "revoked": true }
```

## List all keys

```
list_api_keys()
→ [{ "token": "...", "user_id": "...", "role": "...", "created_at": "..." }, ...]
```

Tokens are shown in full — treat output as sensitive.
