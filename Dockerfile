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
RUN bun add color-diff-napi
RUN cd desktop && bun run build

RUN rm -rf \
    docs fixtures release-notes scripts tests \
    AGENTS.md CC.md CONTRIBUTING.md LICENSE \
    README.md README.en.md .env.example \
    .github .gitignore \
    desktop/src desktop/public desktop/scripts \
    desktop/node_modules \
    /root/.bun/install/cache .git

# ============================================================
FROM oven/bun:alpine

WORKDIR /app

RUN apk add --no-cache bash

# 安装生产依赖 + 删除不必要的大包（同一层，避免 docker 分层保留被删文件）
COPY package.json bun.lock bunfig.toml tsconfig.json ./
RUN bun install --production --frozen-lockfile && \
    rm -rf \
      node_modules/@aws-sdk \
      node_modules/@smithy \
      node_modules/@algolia \
      node_modules/@shikijs \
      node_modules/highlight.js \
      node_modules/@mixmark-io \
      node_modules/web-streams-polyfill \
      node_modules/es-toolkit \
      node_modules/cytoscape-fcose \
      node_modules/@vue \
      node_modules/@types \
      node_modules/hono

# 复制运行时需要的文件和目录
COPY --from=builder /app/src /app/src
COPY --from=builder /app/stubs /app/stubs
COPY --from=builder /app/config /app/config
COPY --from=builder /app/runtime /app/runtime
COPY --from=builder /app/bin /app/bin
COPY --from=builder /app/preload.ts /app/
COPY --from=builder /app/desktop/dist /app/desktop/dist

COPY --from=builder /app/adapters /app/adapters
RUN cd adapters && rm -rf node_modules && bun install --production && \
    rm -rf node_modules/@types

RUN chmod +x /app/bin/claude-haha

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
mkdir -p /root/.claude/skills
for d in /root/.claude/projects/*/; do
  mkdir -p "$d/memory"
done
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
