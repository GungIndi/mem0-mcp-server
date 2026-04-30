FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml .
COPY src/ src/

RUN pip install --no-cache-dir -e .

ENV MEM0_MCP_PORT=6969
ENV MEM0_MCP_TRANSPORT=http
ENV MEM0_KEYS_DB=/data/mem0_keys.db

EXPOSE 6969

CMD ["mem0-mcp"]
