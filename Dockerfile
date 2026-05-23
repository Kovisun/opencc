FROM oven/bun:alpine AS builder

WORKDIR /app

RUN apk add --no-cache bash python3

COPY package.json bun.lock bunfig.toml tsconfig.json ./
COPY adapters/package.json adapters/
RUN bun install --frozen-lockfile

COPY desktop/package.json desktop/bun.lock desktop/tsconfig.json desktop/
RUN cd desktop && bun install --frozen-lockfile

COPY . .
RUN cd adapters && bun install --frozen-lockfile && cd ..
RUN cd desktop && bun run build

# 瘦身：删除运行时不需要的目录和 dev 依赖
RUN rm -rf \
  desktop/src \
  desktop/node_modules \
  desktop/public \
  desktop/scripts \
  docs \
  fixtures \
  release-notes \
  scripts \
  stubs \
  tests \
  AGENTS.md CC.md CONTRIBUTING.md LICENSE \
  README.md README.en.md .env.example \
  .github .gitignore && \
  # 清除 bun 缓存
  rm -rf /root/.bun/install/cache && \
  rm -rf .git

# ============================================================
FROM oven/bun:alpine

WORKDIR /app

RUN apk add --no-cache bash

COPY --from=builder /app /app

RUN chmod +x /app/bin/claude-haha

RUN mkdir -p /app/.claude-defaults && \
    cp config/adapters.json .claude-defaults/ && \
    cp config/settings.json .claude-defaults/ && \
    cp config/stats-cache.json .claude-defaults/ && \
    mkdir -p .claude-defaults/cc-haha && \
    cp config/cc-haha/settings.json .claude-defaults/cc-haha/ && \
    cp config/cc-haha/providers.json .claude-defaults/cc-haha/

RUN cat > /entrypoint.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
if [ -d /root/.claude ] && [ -z "$(ls -A /root/.claude 2>/dev/null)" ]; then
  cp -r /app/.claude-defaults/* /root/.claude/
fi
MODE="${MODE:-all}"
case "$MODE" in
  server) exec bun run src/server/index.ts --host 0.0.0.0 --port "${SERVER_PORT:-3456}" ;;
  adapter) bun run adapters/wechat/index.ts & bun run adapters/feishu/index.ts & wait ;;
  adapter:wechat) exec bun run adapters/wechat/index.ts ;;
  adapter:feishu) exec bun run adapters/feishu/index.ts ;;
  all|*)
    bun run adapters/wechat/index.ts &
    bun run adapters/feishu/index.ts &
    exec bun run src/server/index.ts --host 0.0.0.0 --port "${SERVER_PORT:-3456}" ;;
esac
SCRIPT
RUN chmod +x /entrypoint.sh && chmod +x /app/bin/claude-haha

EXPOSE 3456
ENTRYPOINT ["/entrypoint.sh"]
