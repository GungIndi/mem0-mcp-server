---
name: mem0-memory
description: >
  Persistent memory operations via self-hosted mem0.
  TRIGGER when: user says "remember this", "don't forget", "what do you know about me",
  "search my memories", "forget that", "update that memory", or asks a personal/contextual
  question that could benefit from past context (preferences, history, decisions, facts).
  DO NOT TRIGGER for API key or user management tasks (use mem0-admin skill).
license: MIT
metadata:
  author: GungIndi
  version: "0.1.0"
  category: ai-memory
  tags: "memory, mem0, self-hosted, mcp, personalization"
compatibility: Requires mem0-mcp-server running with MCP configured in .mcp.json.
---

# mem0-memory — Persistent Memory Tools

## Tools

| Tool | When to use |
|------|-------------|
| `search_memories` | Before answering personal/contextual questions |
| `add_memory` | User explicitly asks to remember, or fact is clearly persistent |
| `get_memories` | User asks "what do you know about me" |
| `get_memory` | Look up one specific memory by ID |
| `update_memory` | Correct or update an existing memory |
| `delete_memory` | User asks to forget something specific |

## Search — when to do it proactively

Search before answering when:
- User asks about their preferences, past decisions, or history
- Question is personal ("what should I eat", "which IDE do I use")
- User says "as I mentioned", "you should know", "like last time"

```
search_memories(query="user's dietary restrictions", limit=5)
```

## Save — when NOT to do it automatically

Only save when:
- User explicitly says "remember this" / "save this" / "don't forget"
- Fact is clearly biographical and persistent: name, allergy, strong preference, recurring pattern

Do NOT save:
- Temporary task context
- Anything the user won't care about next session
- Information already likely in memory (search first)

```
add_memory(content="User is allergic to peanuts")
add_memory(content="User prefers dark mode in all editors")
```

One fact per call. Be specific — "User prefers vim keybindings" not "editor stuff".

## user_id scoping

- User key: `user_id` auto-scoped — never pass it
- Admin key: pass `user_id` explicitly to target another user's memories
