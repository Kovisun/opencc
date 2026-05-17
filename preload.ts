// Polyfill for bun:bundle feature() — stripped at build time
// 对于服务器模式，关闭所有需要 bundled 代码的实验性功能
if (typeof (globalThis as any).feature !== 'function') {
  (globalThis as any).feature = (_name: string) => false
}

const version = process.env.CLAUDE_CODE_LOCAL_VERSION ?? '999.0.0-local';
const packageUrl = process.env.CLAUDE_CODE_LOCAL_PACKAGE_URL ?? 'claude-code-local';
const buildTime = process.env.CLAUDE_CODE_LOCAL_BUILD_TIME ?? new Date().toISOString();

process.env.CLAUDE_CODE_LOCAL_SKIP_REMOTE_PREFETCH ??= '1';

Object.assign(globalThis, {
  MACRO: {
    VERSION: version,
    PACKAGE_URL: packageUrl,
    NATIVE_PACKAGE_URL: packageUrl,
    BUILD_TIME: buildTime,
    FEEDBACK_CHANNEL: 'local',
    VERSION_CHANGELOG: '',
    ISSUES_EXPLAINER: '',
  },
});
// Switch to the current workspace
if (process.env.CALLER_DIR) {
  process.chdir(process.env.CALLER_DIR);
}