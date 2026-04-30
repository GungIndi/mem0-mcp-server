#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[mem0-mcp]${NC} $*"; }
success() { echo -e "${GREEN}[mem0-mcp]${NC} $*"; }
warn()    { echo -e "${YELLOW}[mem0-mcp]${NC} $*"; }
error()   { echo -e "${RED}[mem0-mcp]${NC} $*" >&2; exit 1; }

# ── usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  --project DIR     Target project dir to configure .mcp.json and install skill
                    (default: current directory)
  --transport MODE  http | stdio  (default: http)
  --mem0-url URL    mem0 server base URL (default: http://localhost:8888)
  --mem0-key KEY    mem0 server API key
  --mcp-url URL     HTTP MCP server URL (only for --transport http)
  --db PATH         SQLite key store path (only for --transport stdio)
  --skip-mcp        Skip .mcp.json update
  --skip-skill      Skip skill installation
  -h, --help        Show this help
EOF
}

# ── defaults ──────────────────────────────────────────────────────────────────
PROJECT_DIR="$(pwd)"
TRANSPORT="http"
MEM0_URL="http://localhost:8888"
MEM0_KEY=""
MCP_URL=""
DB_PATH="$REPO_DIR/mem0_keys.db"
SKIP_MCP=0
SKIP_SKILL=0

# ── parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)   PROJECT_DIR="$2"; shift 2 ;;
    --transport) TRANSPORT="$2";   shift 2 ;;
    --mem0-url)  MEM0_URL="$2";    shift 2 ;;
    --mem0-key)  MEM0_KEY="$2";    shift 2 ;;
    --mcp-url)   MCP_URL="$2";     shift 2 ;;
    --db)        DB_PATH="$2";     shift 2 ;;
    --skip-mcp)  SKIP_MCP=1;       shift   ;;
    --skip-skill) SKIP_SKILL=1;    shift   ;;
    -h|--help)   usage; exit 0     ;;
    *) error "Unknown option: $1"  ;;
  esac
done

# ── check deps ────────────────────────────────────────────────────────────────
info "Checking dependencies..."
command -v uv  >/dev/null 2>&1 || error "uv not found. Install: https://docs.astral.sh/uv/getting-started/installation/"
command -v python3 >/dev/null 2>&1 || error "python3 not found."

# ── install package ───────────────────────────────────────────────────────────
info "Installing mem0-mcp-server..."
cd "$REPO_DIR"
uv pip install -e . -q
success "Package installed."

# ── bootstrap DB (stdio: generate initial admin key) ─────────────────────────
if [[ "$TRANSPORT" == "stdio" ]]; then
  info "Initialising key store at $DB_PATH ..."
  BOOTSTRAP_KEY=$(MEM0_KEYS_DB="$DB_PATH" MEM0_BASE_URL="$MEM0_URL" MEM0_MCP_TRANSPORT=stdio \
    python3 -c "
import sys; sys.path.insert(0, '$REPO_DIR/src')
from mem0_mcp import auth
auth.DB_PATH = '$DB_PATH'
auth.init_db()
keys = auth.list_keys()
print(keys[0].token)
" 2>&1 | grep -v '^\[mem0-mcp\].*Bootstrap' || true)
  # re-run to capture the printed key if it was just generated
  ADMIN_KEY=$(MEM0_KEYS_DB="$DB_PATH" python3 -c "
import sys; sys.path.insert(0, '$REPO_DIR/src')
from mem0_mcp import auth
auth.DB_PATH = '$DB_PATH'
keys = auth.list_keys()
print(keys[0].token)
")
  success "Admin key: $ADMIN_KEY"
fi

# ── write .mcp.json ──────────────────────────────────────────────────────────
if [[ "$SKIP_MCP" -eq 0 ]]; then
  mkdir -p "$PROJECT_DIR"
  MCP_JSON="$PROJECT_DIR/.mcp.json"

  if [[ "$TRANSPORT" == "http" ]]; then
    [[ -z "$MCP_URL" ]] && MCP_URL="http://localhost:6969/mcp"
    warn "HTTP transport: you need a running mem0-mcp server."
    warn "Set Authorization token in .mcp.json after getting your admin key from server logs."
    NEW_ENTRY=$(cat <<EOF
    "mem0": {
      "type": "http",
      "url": "$MCP_URL",
      "headers": {
        "Authorization": "Bearer REPLACE_WITH_YOUR_TOKEN"
      }
    }
EOF
)
  else
    NEW_ENTRY=$(cat <<EOF
    "mem0": {
      "type": "stdio",
      "command": "uv",
      "args": ["run", "--project", "$REPO_DIR", "mem0-mcp"],
      "env": {
        "MEM0_BASE_URL": "$MEM0_URL",
        "MEM0_API_KEY": "$MEM0_KEY",
        "MEM0_KEYS_DB": "$DB_PATH",
        "MEM0_MCP_TRANSPORT": "stdio"
      }
    }
EOF
)
  fi

  if [[ -f "$MCP_JSON" ]]; then
    # merge: inject into existing mcpServers block using python
    python3 - "$MCP_JSON" "$NEW_ENTRY" <<'PYEOF'
import sys, json, re

path = sys.argv[1]
entry_raw = sys.argv[2]

with open(path) as f:
    data = json.load(f)

data.setdefault("mcpServers", {})

# parse the entry key/value from the raw JSON fragment
wrapped = json.loads("{" + entry_raw + "}")
for k, v in wrapped.items():
    if k in data["mcpServers"]:
        print(f"[mem0-mcp] .mcp.json already has '{k}' entry — skipped.", file=sys.stderr)
    else:
        data["mcpServers"][k] = v
        print(f"[mem0-mcp] Added '{k}' to .mcp.json", file=sys.stderr)

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
  else
    # create fresh
    python3 - "$MCP_JSON" "$NEW_ENTRY" <<'PYEOF'
import sys, json

path = sys.argv[1]
entry_raw = sys.argv[2]
wrapped = json.loads("{" + entry_raw + "}")
data = {"mcpServers": wrapped}

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"[mem0-mcp] Created {path}", file=sys.stderr)
PYEOF
  fi

  success ".mcp.json updated at $MCP_JSON"
fi

# ── install skills ────────────────────────────────────────────────────────────
if [[ "$SKIP_SKILL" -eq 0 ]]; then
  SKILL_DIR="$PROJECT_DIR/.claude/skills"
  mkdir -p "$SKILL_DIR"
  cp "$REPO_DIR/skills/mem0-memory.md" "$SKILL_DIR/mem0-memory.md"
  cp "$REPO_DIR/skills/mem0-admin.md"  "$SKILL_DIR/mem0-admin.md"
  success "Skills installed at $SKILL_DIR"

  # ── write CLAUDE.md memory instructions ─────────────────────────────────────
  CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
  MARKER="<!-- mem0-mcp -->"
  if [[ -f "$CLAUDE_MD" ]] && grep -q "$MARKER" "$CLAUDE_MD"; then
    warn "CLAUDE.md already has mem0-mcp block — skipped."
  else
    cat >> "$CLAUDE_MD" <<'EOF'

<!-- mem0-mcp -->
## Memory (mem0)

- **Search first**: before answering personal or contextual questions, call `search_memories` to check for relevant past context.
- **Save selectively**: only add to memory when the user explicitly asks ("remember this", "don't forget") or the fact is clearly persistent (name, allergy, strong preference, recurring pattern). Do not save temporary task context.
- Skills: `mem0-memory` for memory ops, `mem0-admin` for key management.
<!-- /mem0-mcp -->
EOF
    success "Memory instructions added to $CLAUDE_MD"
  fi
fi

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
success "Done!"
if [[ "$TRANSPORT" == "stdio" ]]; then
  echo -e "  Admin key : ${YELLOW}$ADMIN_KEY${NC}"
  echo -e "  Key store : $DB_PATH"
fi
echo -e "  Restart Claude Code to pick up the new MCP server."
