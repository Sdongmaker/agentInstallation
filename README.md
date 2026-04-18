# MAX API - AI 编程助手一键安装工具

MAX API 一键安装 **Claude Code**、**Codex CLI**、**Gemini CLI** 三大 AI 编程助手，专为中国大陆用户优化。

自动处理：Node.js/Git 依赖安装、npm 国内镜像加速、API 配置，并在安装后把最终写入的配置打印到终端，便于排查问题。

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
4. **安装依赖** — 自动安装 Git（Claude Code 需要）和 Node.js 20+
5. **安装工具** — 通过 npm 国内镜像安装，无需翻墙
6. **配置完成** — 自动写入配置文件并打印最终内容，方便核对

## 系统要求

- Windows 10 / 11（64 位）
- 约 500MB 可用磁盘空间
- 网络连接（无需翻墙，脚本使用国内镜像）

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

### Node.js 安装失败

MSI 静默安装需要管理员权限。右键以**管理员身份**运行 PowerShell 后重试。

### npm 安装超时

脚本已自动配置国内镜像。如仍超时，可手动设置后重试：

```powershell
npm config set registry https://registry.npmmirror.com
```

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
- 每次安装后，脚本都会把最终写入的配置内容打印到终端，并在覆盖前自动备份旧配置文件。

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
   npm install -g @anthropic-ai/claude-code
   npm install -g @openai/codex
   npm install -g @google/gemini-cli
   ```
4. 手动编辑上述配置文件，填入 API 地址和 Key
5. Gemini CLI 如使用 API Key 模式，仍需确保 `GEMINI_API_KEY` 环境变量存在

## License

MIT
