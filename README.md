# MAX API - AI 编程助手一键安装工具

MAX API 一键安装 **Claude Code**、**Codex CLI**、**Gemini CLI** 三大 AI 编程助手，专为中国大陆用户优化。

自动处理：Node.js/Git 依赖安装、npm 源选择与加速、安装前 MAX API 双线路预检查、API 配置、PowerShell 兼容修复。

## 一键安装

在 PowerShell 中粘贴以下命令并回车：

```powershell
irm https://kk.eemby.de/https://raw.githubusercontent.com/Sdongmaker/agentInstallation/main/install.ps1 | iex
```

> **如何打开 PowerShell？** 右键点击 Windows 开始菜单 → 选择「Windows PowerShell」或「终端」

## 支持的工具

| 工具 | 厂商 | 默认模型 | 启动命令 |
|------|------|---------|---------|
| Claude Code | Anthropic | claude-opus-4-6 | `claude` |
| Codex CLI | OpenAI | gpt-5.4 | `codex` |
| Gemini CLI | Google | gemini-3.1-pro-preview | `gemini` |

## 脚本会做什么

1. **检测环境** — 确认 Windows x86_64、PowerShell 版本
2. **选择工具** — 你可以选择安装全部或部分工具
3. **输入 API Key** — 输入一次，所有工具共用
4. **预检查 MAX API** — 在安装开始前先对两条 HTTPS 线路各执行 10 次 ping，优先选择丢包率更低的线路，再测试服务可达性与认证状态
5. **安装依赖** — 自动安装 Git（Claude Code 需要）和 Node.js 20+
6. **安装工具** — Codex CLI / Gemini CLI 默认走国内镜像；Claude Code 为确保 Windows 原生二进制完整，固定走官方 npm 源
7. **配置完成** — 自动写入配置文件、禁用 PowerShell `.ps1` shim、尝试修复执行策略，并执行一次真实 API 调用测试

## 系统要求

- Windows 10 / 11（64 位）
- 约 500MB 可用磁盘空间
- 网络连接
- Codex CLI / Gemini CLI 默认使用国内镜像
- Claude Code 安装时需要访问官方 `registry.npmjs.org`；多数大陆网络可直连，但部分公司网络或受限网络可能需要代理

## 安装后使用

安装完成后，在**任意项目目录**中打开终端，输入对应命令即可启动：

```powershell
# Claude Code
claude

# Codex CLI
codex

# Gemini CLI
gemini
```

> 如果提示「命令未找到」，请关闭并重新打开终端窗口。

## FAQ

### 安装命令执行报错「无法运行脚本」

PowerShell 执行策略限制。运行以下命令后重试：

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

新版安装脚本会优先禁用 npm 生成的 `claude.ps1`、`codex.ps1`、`gemini.ps1`，让 PowerShell 自动回落到对应的 `.cmd`；同时会尝试把当前用户执行策略设置为 `RemoteSigned`。

### 输入 `codex` / `gemini` / `claude` 提示「因为在此系统上禁止运行脚本」

这是 PowerShell 拦截了 npm 自动生成的 `.ps1` 启动脚本，不是 CLI 安装失败。

新版安装脚本会自动处理这个问题：

- 禁用 npm 生成的 `claude.ps1`、`codex.ps1`、`gemini.ps1`
- 清理旧版本脚本遗留的 PowerShell profile 托管包装器
- 尝试设置 `CurrentUser` 执行策略为 `RemoteSigned`
- 打印 shim 清理结果和执行策略诊断，便于检查

如果你是在旧版本脚本安装后遇到这个问题，重新运行最新版安装脚本即可修复。临时绕过方式是：

```powershell
codex.cmd
gemini.cmd
claude.cmd
```

### 为什么 Claude Code 不直接走国内镜像

Claude Code 的 Windows npm 包依赖平台原生 optional dependency。国内镜像有时能装下主包，但没把原生 `claude.exe` 一起正确拉下来，结果就是命令存在、运行却异常。

因此新版脚本改成：

- Codex CLI / Gemini CLI 继续使用 `npmmirror`
- Claude Code 固定使用官方 `registry.npmjs.org`

这样做更慢一点，但更稳，也更容易把问题定位到真实网络链路，而不是被镜像问题误导。

### Node.js 安装失败

MSI 静默安装需要管理员权限。右键以**管理员身份**运行 PowerShell 后重试。

### npm 安装超时

Codex CLI / Gemini CLI 会自动使用国内镜像。如仍超时，可手动设置后重试：

```powershell
npm config set registry https://registry.npmmirror.com
```

如果是 Claude Code 安装阶段超时，原因通常是当前网络无法访问官方 `registry.npmjs.org`。这时请更换网络、配置代理，或在能访问官方 npm 的环境下重试。

### MAX API 会使用哪条线路

安装脚本目前内置两条 HTTPS 线路：

- `https://new.28.al`
- `https://new.1huanlesap02.top`

预检查阶段会分别对两条线路执行 10 次 ping，优先选择丢包率更低的线路；如果丢包率相同，则再比较平均延迟。选中的线路会用于：

- 安装前的 MAX API 连通性预检查
- Claude / Codex / Gemini 的配置写入
- 安装结束后的真实调用测试

### 为什么安装结束后还会再跑一次真实调用测试

只看 `--version` 只能证明命令装上了，不能证明：

- API Key 可用
- Base URL 配置生效
- CLI 真的能发请求并拿到返回

所以脚本会对每个安装成功的工具发起一次极小的真实请求，验证连通性。当前测试题是一个极小的数学题，只会产生很少的 token 消耗。

如果安装前的 MAX API 预检查已经明确失败，例如服务不可达、API Key 未通过认证或端点返回异常状态，脚本会先把这个问题单独打印出来，并跳过最终真实调用测试，避免把 API 故障误判成 CLI 安装故障。

### 想更换 MAX API Key 或模型

配置文件位置：

| 工具 | 配置文件 |
|------|---------|
| Claude Code | `%USERPROFILE%\.claude\settings.json` |
| Codex CLI | `%USERPROFILE%\.codex\config.toml` |
| Gemini CLI | `%USERPROFILE%\.gemini\settings.json` + 环境变量 |

说明：

- Claude Code：脚本会写入 `settings.json`，并清理旧版本脚本遗留的 `ANTHROPIC_*` 用户环境变量，避免冲突。
- Codex CLI：官方配置文件格式是 `TOML`，不是 JSON；脚本会写入 `%USERPROFILE%\.codex\config.toml`。
- Gemini CLI：当前官方版本在 API Key 模式下仍要求 `GEMINI_API_KEY` 环境变量；脚本会同时写入 `settings.json` 和该环境变量。
- 每次安装后，脚本都会把 MAX API 预检查结果、最终写入的配置内容、PowerShell shim 清理结果、执行策略诊断和真实调用测试结果打印到终端，并在覆盖前自动备份旧配置文件。

### 想卸载某个工具

```powershell
npm uninstall -g @anthropic-ai/claude-code
npm uninstall -g @openai/codex
npm uninstall -g @google/gemini-cli
```

## 手动安装（备选）

如果一键脚本不适用，可以手动执行以下步骤：

1. 安装 [Node.js 20+](https://nodejs.org/)
2. 设置 npm 镜像：`npm config set registry https://registry.npmmirror.com`
3. 安装工具：
   ```powershell
   npm install -g @anthropic-ai/claude-code --registry=https://registry.npmjs.org
   npm install -g @openai/codex
   npm install -g @google/gemini-cli
   ```
4. 手动编辑上述配置文件，填入 API 地址和 Key
5. Gemini CLI 如使用 API Key 模式，仍需确保 `GEMINI_API_KEY` 环境变量存在

## License

MIT
