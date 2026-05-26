# OpenCC 部署指南

> 基于 [NanmiCoder/cc-haha](https://github.com/NanmiCoder/cc-haha) 源码构建的 Docker 镜像，内嵌微信/飞书 IM 适配器 + H5 远程访问，单容器即开即用。

---

## 1. 镜像信息

| 项目 | 值 |
|------|-----|
| 镜像名 | `ghcr.io/kovisun/opencc` |
| Tags | `latest`, `1.0.0` |
| 大小 | ~395MB |
| 基础镜像 | `oven/bun:alpine` |
| GitHub 源码 | `https://github.com/Kovisun/opencc` |
| 宿主机目录 | `/vol2/1000/Docker/OpenCC/` |
| 端口映射 | `3456 → 3456`（H5 前端） |

---

## 2. 首次部署

### 2.1 拉取镜像

```bash
docker pull ghcr.io/kovisun/opencc:latest
```

### 2.2 准备目录结构

```bash
mkdir -p /vol2/1000/Docker/OpenCC/{config,data,workspace,.env}
```

### 2.3 编写 docker-compose.yml

```yaml
services:
  claudecode:
    image: ghcr.io/kovisun/opencc:latest
    container_name: ClaudeCode
    network_mode: bridge
    ports:
      - "3456:3456"
    volumes:
      - ./config:/root/.claude
      - ./data:/root/.local/share/claude
      - ./workspace:/workspace
      - ./.env:/app/.env:ro
    environment:
      - SERVER_HOST=0.0.0.0
      - SERVER_PORT=3456
      - CLAUDE_APP_ROOT=/app
      - CLAUDE_H5_DIST_DIR=/app/desktop/dist
      - DISABLE_TELEMETRY=1
      - CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
      - IS_SANDBOX=1
      - TZ=Asia/Shanghai
    restart: always
    stdin_open: true
    tty: true
```

### 2.4 启动

```bash
docker compose up -d
docker compose logs -f
```

首次启动时 `config/` 目录为空，entrypoint 会自动从 `/app/.claude-defaults/` 回填预置配置（含微信/飞书绑定、固定 token、DeepSeek 提供商等）。

---

## 3. 配置说明

### 3.1 固定 H5 Token

Token: `15627567868`
SHA-256: `f5d56c179f781aab9c158c5f3125e4088711c297ebfe6ba5b1b48a0ff56c7400`

在 `config/settings.json` 中已预设：

```json
"h5Access": {
  "enabled": true,
  "tokenHash": "f5d56c179f781aab9c158c5f3125e4088711c297ebfe6ba5b1b48a0ff56c7400"
}
```

### 3.2 内网免认证

以下来源 IP 自动跳过 H5 token 认证：

- Loopback: `127.x.x.x`
- 私网 A: `10.x.x.x`
- 私网 B: `172.16-31.x.x`
- 私网 C: `192.168.x.x`
- 链路本地: `169.254.x.x`

两端实现：
- **服务端** `src/server/h5AccessPolicy.ts`：`isTrustedHost()` + `classifyH5Request`
- **前端** `desktop/src/lib/desktopRuntime.ts`：`isPrivateHostname()` + `requiresH5AuthForServerUrl`

### 3.3 配置文件清单

| 文件 | 用途 |
|------|------|
| `config/adapters.json` | IM 适配器绑定（微信/飞书 AppID、Token 等） |
| `config/settings.json` | CLI 默认设置 + H5 token 哈希 |
| `config/cc-haha/providers.json` | 模型提供商（DeepSeek + Ollama） |
| `config/cc-haha/settings.json` | cc-haha 专用设置 |
| `config/stats-cache.json` | 统计缓存 |

### 3.4 环境变量 (.env)

容器内可通过 `.env` 文件追加环境变量，挂载至 `/app/.env:ro`。示例：

```env
# 覆盖 IM 绑定
WECHAT_APP_ID=xxx
WECHAT_APP_SECRET=xxx
FEISHU_APP_ID=xxx
FEISHU_APP_SECRET=xxx
```

---

## 4. Entrypoint 模式

容器启动时通过 `MODE` 环境变量选择运行模式（默认 `all`）：

| MODE | 启动内容 |
|------|----------|
| `all` | Server + 微信 + 飞书 |
| `server` | 仅 HTTP Server（H5 前端） |
| `adapter` | 仅适配器（微信 + 飞书） |
| `adapter:wechat` | 仅微信适配器 |
| `adapter:feishu` | 仅飞书适配器 |

```yaml
environment:
  - MODE=server    # 仅启动 HTTP Server
```

---

## 5. 数据持久化

- **配置**: `./config:/root/.claude` — 用户设置、IM 绑定
- **数据**: `./data:/root/.local/share/claude` — 会话、缓存
- **工作区**: `./workspace:/workspace` — 代码项目

---

## 6. 健康检查

Docker 自动每 10s 检查 `/api/status`，失败超过 5 次后重启容器。

手动检查：

```bash
curl http://localhost:3456/api/status
# → {"status":"ok"}
```

---

## 7. 更新流程

```bash
# 拉取新镜像
docker pull ghcr.io/kovisun/opencc:latest

# 重建容器
docker compose down
docker compose up -d

# 查看日志
docker compose logs -f
```

如需从旧版 `ghcr.io/kovisun/cc-haha` 迁移：保留 `config/` 和 `data/` 目录不变，仅替换镜像名。

---

## 8. 注意事项

### 8.1 私网 IP 检测范围

Docker bridge 网络下，`server.requestIP(req)` 返回 Docker 网关 IP（如 `172.17.0.x`）而非真实客户端 IP。因此私网检测必须覆盖 `172.16.0.0/12`（172.16-31.x.x）范围。

### 8.2 适配器模块路径

新版 cc-haha 源码 `src/server/api/adapters.ts` 和 `sessions.ts` 直接 `import '../../../adapters/wechat/protocol.js'`，所以 `adapters/` 目录必须出现在 `/app/` 下且保留 `.ts` 源码。已打包在镜像内。

### 8.3 配置回填机制

`docker-compose.yml` 中 `./config:/root/.claude` volume 挂载会**覆盖**镜像内预置配置。Entrypoint 启动时检测 `/root/.claude/` 是否为空目录，若是则自动从 `/app/.claude-defaults/` 回填 5 个配置文件（`adapters.json`、`settings.json`、`stats-cache.json`、`cc-haha/settings.json`、`cc-haha/providers.json`）。`adapter-sessions.json` 不在默认配置中，会保持回退 `{}`。

### 8.4 工作区挂载

容器内工作区路径为 `/workspace`，包含 `AGENTS.md`（opencode agent 配置）。容器启动时可通过 `CALLER_DIR` 环境变量定位。

### 8.5 浏览器访问

H5 前端访问地址：`http://<主机IP>:3456`。如需在 H5 中访问工作区文件，在 Settings 中将 workDir 设为 `/workspace`。

---

## 9. 相关链接

- 源码仓库: `https://github.com/Kovisun/opencc`
- Docker 镜像: `ghcr.io/kovisun/opencc`
- 原始项目: `https://github.com/NanmiCoder/cc-haha`
