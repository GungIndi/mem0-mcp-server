# mem0-mcp-server

MCP server for self-hosted [mem0](https://github.com/mem0ai/mem0). Proxies memory CRUD to a mem0 REST API with API-key-based auth (admin vs user roles). Includes a Claude Code skill that teaches the AI when and how to use memory tools.

## Requirements

- Python 3.10+
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- A running self-hosted mem0 instance

## Install

```bash
git clone https://github.com/GungIndi/mem0-mcp-server
cd mem0-mcp-server
./install.sh --project /path/to/your/project --transport stdio
```

The script will:
1. Install the package via `uv`
2. Initialise the SQLite key store and print a bootstrap admin key
3. Write the `mem0` entry into your project's `.mcp.json`
4. Copy the Claude Code skill to `.claude/skills/mem0-mcp.md`

### Install options

```
./install.sh [OPTIONS]

  --project DIR     Target project dir (default: current directory)
  --transport MODE  http | stdio  (default: http)
  --mem0-url URL    mem0 server base URL (default: http://localhost:8888)
  --mem0-key KEY    mem0 server API key
  --mcp-url URL     HTTP MCP server URL (for --transport http)
  --db PATH         SQLite key store path (for --transport stdio)
  --skip-mcp        Skip .mcp.json update
  --skip-skill      Skip Claude Code skill installation
```

## Tools

| Tool | Role | Description |
|------|------|-------------|
| `add_memory` | any | Store a new memory |
| `search_memories` | any | Semantic search |
| `get_memories` | any | List all memories for a user |
| `get_memory` | any | Fetch one memory by ID |
| `update_memory` | any | Update memory text |
| `delete_memory` | any | Delete one memory by ID |
| `create_api_key` | admin | Create a new API key (user or admin role) |
| `revoke_api_key` | admin | Revoke an API key |
| `list_api_keys` | admin | List all API keys |

Admin keys can pass any `user_id`. User keys are scoped to their own `user_id`.

## Auth

Every MCP call requires `Authorization: Bearer <token>`. Tokens are stored in a local SQLite DB with a `role` (`admin` or `user`) and a `user_id`.

On first boot with an empty DB, a bootstrap admin key is auto-generated and printed once:

```
[mem0-mcp] Bootstrap admin key (save this): <token>
```

Set `MEM0_BOOTSTRAP_ADMIN_KEY` in env to seed a specific key instead.

## Config

| Env var | Default | Description |
|---------|---------|-------------|
| `MEM0_BASE_URL` | `http://localhost:8000` | Self-hosted mem0 URL |
| `MEM0_API_KEY` | — | API key for the mem0 server |
| `MEM0_KEYS_DB` | `./mem0_keys.db` | Path to SQLite token store |
| `MEM0_MCP_PORT` | `6969` | HTTP listen port |
| `MEM0_MCP_TRANSPORT` | `http` | `http` or `stdio` |
| `MEM0_BOOTSTRAP_ADMIN_KEY` | — | Seed a specific admin key on first boot |

Copy `.env.example` to `.env` and fill in values.

## Deploy with Docker Compose

Add to your existing mem0 `docker-compose.yaml`. The service connects to mem0 via the internal network (`http://mem0:8000`) and exposes port 6969.

```yaml
mem0-mcp:
  build:
    context: /path/to/mem0-mcp-server
    dockerfile: Dockerfile
  ports:
    - "6969:6969"
  networks:
    - mem0_network
  volumes:
    - mem0_mcp_keys:/data
  environment:
    - MEM0_BASE_URL=http://mem0:8000
    - MEM0_API_KEY=${MEM0_API_KEY}
    - MEM0_KEYS_DB=/data/mem0_keys.db
    - MEM0_BOOTSTRAP_ADMIN_KEY=${MEM0_BOOTSTRAP_ADMIN_KEY:-}
  depends_on:
    mem0:
      condition: service_started
```

```bash
docker compose up -d --build mem0-mcp
docker compose logs mem0-mcp | grep "Bootstrap admin key"
```

## Run locally

```bash
cp .env.example .env  # fill in values
uv run mem0-mcp
```

## Claude Code `.mcp.json`

**HTTP** (remote server):

```json
{
  "mcpServers": {
    "mem0": {
      "type": "http",
      "url": "http://<your-server>:6969/mcp",
      "headers": {
        "Authorization": "Bearer <your-token>"
      }
    }
  }
}
```

**stdio via uv** (local, no separate server):

```json
{
  "mcpServers": {
    "mem0": {
      "type": "stdio",
      "command": "uv",
      "args": ["run", "--project", "/path/to/mem0-mcp-server", "mem0-mcp"],
      "env": {
        "MEM0_BASE_URL": "http://<your-mem0-host>:8888",
        "MEM0_API_KEY": "<mem0-api-key>",
        "MEM0_KEYS_DB": "/path/to/mem0-mcp-server/mem0_keys.db",
        "MEM0_MCP_TRANSPORT": "stdio"
      }
    }
  }
}
```

## Claude Code Skills

The install script copies two skills to `.claude/skills/` and appends a memory policy block to `CLAUDE.md`.

| Skill | Trigger |
|-------|---------|
| `mem0-memory.md` | Remember, recall, search, forget — memory CRUD |
| `mem0-admin.md` | Create/revoke/list API keys — admin only |

**CLAUDE.md policy** (added automatically):
- Search memory before answering personal or contextual questions
- Save only when user explicitly asks or the fact is clearly persistent (name, allergy, preference) — not temporary task context

To install manually:

```bash
cp skills/mem0-memory.md /path/to/project/.claude/skills/
cp skills/mem0-admin.md  /path/to/project/.claude/skills/
```

Then add to your `CLAUDE.md`:

```markdown
## Memory (mem0)

- **Search first**: before answering personal or contextual questions, call `search_memories`.
- **Save selectively**: only when user explicitly asks or the fact is clearly persistent. Do not save temporary task context.
- Skills: `mem0-memory` for memory ops, `mem0-admin` for key management.
```

## License

MIT
