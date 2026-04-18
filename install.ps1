#Requires -Version 5.1
<#
.SYNOPSIS
    MAX API - AI 编程助手一键安装脚本
.DESCRIPTION
    一键安装 Claude Code / Codex CLI / Gemini CLI，自动处理依赖、镜像加速和 API 配置。
    专为中国大陆用户设计，由 MAX API 提供支持。
.NOTES
    用法: irm https://kk.eemby.de/https://raw.githubusercontent.com/Sdongmaker/agentInstallation/main/install.ps1 | iex
#>

# ============================================================
# 配置常量
# ============================================================
$Script:API_BASE_URL     = "https://new.28.al"
$Script:NPM_MIRROR       = "https://registry.npmmirror.com"
$Script:GITHUB_PROXY     = "https://kk.eemby.de"
$Script:NODE_MIRROR       = "https://npmmirror.com/mirrors/node"
$Script:NODE_VERSION      = "v20.18.1"
$Script:GIT_VERSION       = "2.47.1"
$Script:GIT_RELEASE_TAG   = "v2.47.1.windows.2"

$Script:CLAUDE_MODEL  = "claude-opus-4-6"
$Script:CODEX_MODEL   = "gpt-5.4"
$Script:GEMINI_MODEL  = "gemini-3.1-pro-preview"

# UTF-8 无 BOM 编码（PS 5.1 默认 UTF8 带 BOM，某些解析器不兼容）
$Script:UTF8NoBom = [System.Text.UTF8Encoding]::new($false)

# npm 可执行文件路径（稍后在 Resolve-NpmPath 中填充）
$Script:NpmExe = $null

# ============================================================
# 辅助函数
# ============================================================

function Resolve-NpmPath {
    <#
    .SYNOPSIS
        找到可用的 npm 可执行文件。
        优先使用 npm.cmd（不受 PS 执行策略限制），
        回退到 npm.ps1 或 npm。
    #>
    # 优先查找 npm.cmd
    $cmd = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
    if ($cmd) {
        $Script:NpmExe = $cmd.Source
        return
    }
    # 回退到 npm（可能是 .ps1 或 .exe）
    $cmd = Get-Command "npm" -ErrorAction SilentlyContinue
    if ($cmd) {
        $Script:NpmExe = $cmd.Source
        return
    }
    $Script:NpmExe = $null
}

function Invoke-Npm {
    <#
    .SYNOPSIS
        调用 npm，自动使用 .cmd 版本避免 PS 执行策略问题
    #>
    param([string[]]$Arguments)
    if (-not $Script:NpmExe) { Resolve-NpmPath }
    if (-not $Script:NpmExe) {
        Write-Err "npm 未找到，请确认 Node.js 已正确安装"
        return $null
    }
    & $Script:NpmExe @Arguments
}

function Invoke-ToolCommand {
    <#
    .SYNOPSIS
        调用工具命令（claude/codex/gemini），优先使用 .cmd 版本避免 PS 执行策略问题
    #>
    param([string]$Command, [string[]]$Arguments)
    # 优先 .cmd
    $cmd = Get-Command "$Command.cmd" -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    }
    if (-not $cmd) { return $null }
    & $cmd.Source @Arguments 2>$null
}

function Test-ToolExists {
    <#
    .SYNOPSIS
        检测工具是否存在，同时查找 .cmd 和原始命令
    #>
    param([string]$Command)
    $null -ne (Get-Command "$Command.cmd" -ErrorAction SilentlyContinue) -or
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Write-Banner {
    Write-Host ""
    Write-Host "  ███╗   ███╗ █████╗ ██╗  ██╗     █████╗ ██████╗ ██╗" -ForegroundColor Magenta
    Write-Host "  ████╗ ████║██╔══██╗╚██╗██╔╝    ██╔══██╗██╔══██╗██║" -ForegroundColor Magenta
    Write-Host "  ██╔████╔██║███████║ ╚███╔╝     ███████║██████╔╝██║" -ForegroundColor Red
    Write-Host "  ██║╚██╔╝██║██╔══██║ ██╔██╗     ██╔══██║██╔═══╝ ██║" -ForegroundColor Red
    Write-Host "  ██║ ╚═╝ ██║██║  ██║██╔╝ ██╗    ██║  ██║██║     ██║" -ForegroundColor DarkRed
    Write-Host "  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝     ╚═╝" -ForegroundColor DarkRed
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  AI 编程助手 一键安装工具 v1.0                   │" -ForegroundColor Cyan
    Write-Host "  │  支持: Claude Code · Codex CLI · Gemini CLI      │" -ForegroundColor Gray
    Write-Host "  │  服务: $Script:API_BASE_URL" -NoNewline -ForegroundColor Gray
    Write-Host "$(' ' * (28 - $Script:API_BASE_URL.Length))│" -ForegroundColor DarkGray
    Write-Host "  └──────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "▶ $Message" -ForegroundColor Green
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Write-Info {
    param([string]$Message)
    Write-Host "  ℹ $Message" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✔ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  ✖ $Message" -ForegroundColor Red
}

function Refresh-PathEnv {
    <#
    .SYNOPSIS
        刷新当前进程的 PATH 环境变量，使新安装的程序立即可用
    #>
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-NodeMajorVersion {
    <#
    .SYNOPSIS
        获取已安装的 Node.js 主版本号，未安装则返回 0
    #>
    if (-not (Test-CommandExists "node")) { return 0 }
    try {
        $ver = (node --version 2>$null)
        if ($ver -match 'v(\d+)') { return [int]$Matches[1] }
    } catch {}
    return 0
}

function Test-WingetAvailable {
    Test-CommandExists "winget"
}

function Install-WithWinget {
    param([string]$PackageId, [string]$FriendlyName, [switch]$Upgrade)
    if ($Upgrade) {
        Write-Info "正在通过 winget 升级 $FriendlyName ..."
        $result = winget upgrade --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>&1
    } else {
        Write-Info "正在通过 winget 安装 $FriendlyName ..."
        $result = winget install --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>&1
    }
    $success = $LASTEXITCODE -eq 0
    if ($success) {
        Write-Success "$FriendlyName 安装完成"
        Refresh-PathEnv
    } else {
        Write-Warn "winget 安装 $FriendlyName 失败，将尝试备用方案"
    }
    return $success
}

function Download-File {
    <#
    .SYNOPSIS
        下载文件，优先通过 GitHub 加速器
    #>
    param(
        [string]$Url,
        [string]$OutFile,
        [switch]$UseProxy
    )
    $downloadUrl = if ($UseProxy) { "$Script:GITHUB_PROXY/$Url" } else { $Url }
    Write-Info "下载: $downloadUrl"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        Write-Success "下载完成: $OutFile"
        return $true
    } catch {
        Write-Warn "下载失败: $_"
        # 如果用了代理失败，尝试直连
        if ($UseProxy) {
            Write-Info "尝试直连下载 ..."
            try {
                Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
                Write-Success "直连下载完成: $OutFile"
                return $true
            } catch {
                Write-Err "直连也失败: $_"
            }
        }
        return $false
    }
}

function Set-PersistentEnvVar {
    <#
    .SYNOPSIS
        设置持久化的用户级环境变量，同时更新当前进程
    #>
    param(
        [string]$Name,
        [string]$Value
    )
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "Env:\$Name" -Value $Value
    Write-Info "环境变量已设置: $Name"
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================================
# 环境检测
# ============================================================

function Test-Environment {
    Write-Step "环境检测"

    # 检测操作系统
    if (-not ($env:OS -eq "Windows_NT")) {
        Write-Err "此脚本仅支持 Windows 系统"
        return $false
    }
    Write-Success "操作系统: Windows"

    # 检测架构
    $arch = [System.Environment]::Is64BitOperatingSystem
    if (-not $arch) {
        Write-Err "此脚本仅支持 64 位系统"
        return $false
    }
    Write-Success "系统架构: x86_64"

    # 检测 PowerShell 版本
    $psVer = $PSVersionTable.PSVersion
    Write-Success "PowerShell 版本: $psVer"

    # 检测管理员权限
    if (Test-IsAdmin) {
        Write-Success "管理员权限: 是"
    } else {
        Write-Warn "管理员权限: 否（如需安装 Node.js/Git 可能需要管理员权限）"
    }

    # 检测 winget
    if (Test-WingetAvailable) {
        Write-Success "winget: 可用"
    } else {
        Write-Warn "winget: 不可用（将使用备用下载方式安装依赖）"
    }

    return $true
}

# ============================================================
# 交互式菜单
# ============================================================

function Show-ToolMenu {
    Write-Step "选择要安装的工具"
    Write-Host ""
    Write-Host "  [1] Claude Code    — Anthropic AI 编程助手 (claude-opus-4-6)" -ForegroundColor White
    Write-Host "  [2] Codex CLI      — OpenAI AI 编程助手   (gpt-5.4)" -ForegroundColor White
    Write-Host "  [3] Gemini CLI     — Google AI 编程助手   (gemini-3.1-pro-preview)" -ForegroundColor White
    Write-Host ""
    Write-Host "  [A] 全部安装（推荐）" -ForegroundColor Yellow
    Write-Host ""

    while ($true) {
        $choice = Read-Host "  请输入选项 (如: 1,3 或 A)"
        $choice = $choice.Trim().ToUpper()

        if ($choice -eq "A") {
            return @("claude", "codex", "gemini")
        }

        $tools = @()
        $valid = $true
        foreach ($c in ($choice -split '[,\s]+')) {
            switch ($c.Trim()) {
                "1" { $tools += "claude" }
                "2" { $tools += "codex" }
                "3" { $tools += "gemini" }
                default { $valid = $false }
            }
        }

        if ($valid -and $tools.Count -gt 0) {
            return ($tools | Select-Object -Unique)
        }

        Write-Warn "无效输入，请输入 1-3 的数字（逗号分隔多选）或 A 全选"
    }
}

function Read-ApiKey {
    Write-Step "配置 API Key"
    Write-Host ""
    Write-Host "  请输入您的 MAX API Key（来自 $Script:API_BASE_URL ）" -ForegroundColor White
    Write-Host "  （输入时不会显示内容，这是正常的）" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        # PowerShell 5.1 没有 -MaskInput，使用 -AsSecureString 再转换
        $secureKey = Read-Host "  API Key" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        $apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Write-Warn "API Key 不能为空，请重新输入"
            continue
        }
        if ($apiKey.Length -lt 8) {
            Write-Warn "API Key 太短，请确认后重新输入"
            continue
        }
        return $apiKey
    }
}

# ============================================================
# 依赖安装
# ============================================================

function Install-GitIfNeeded {
    Write-Step "检测 Git"

    if (Test-CommandExists "git") {
        $gitVer = git --version 2>$null
        Write-Success "Git 已安装: $gitVer"
        return $true
    }

    Write-Info "Git 未安装，Claude Code 需要 Git 支持"

    # 方案1: winget
    if (Test-WingetAvailable) {
        if (Install-WithWinget "Git.Git" "Git for Windows") {
            return $true
        }
    }

    # 方案2: 通过加速器下载安装
    if (-not (Test-IsAdmin)) {
        Write-Warn "Git 静默安装需要管理员权限"
        Write-Info "请右键以管理员身份运行 PowerShell 后重试，或手动安装: https://git-scm.com/downloads/win"
        return $false
    }

    Write-Info "正在下载 Git for Windows ..."
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/$Script:GIT_RELEASE_TAG/Git-$Script:GIT_VERSION.2-64-bit.exe"
    $gitInstaller = Join-Path $env:TEMP "git-installer.exe"

    if (-not (Download-File -Url $gitUrl -OutFile $gitInstaller -UseProxy)) {
        Write-Err "Git 下载失败，请手动安装 Git for Windows: https://git-scm.com/downloads/win"
        return $false
    }

    Write-Info "正在静默安装 Git ..."
    $process = Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-" -Wait -PassThru
    Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        Write-Err "Git 安装失败（退出码: $($process.ExitCode)）"
        return $false
    }

    Refresh-PathEnv
    if (Test-CommandExists "git") {
        Write-Success "Git 安装完成"
        return $true
    }

    Write-Err "Git 安装后仍不可用，请重启终端后重试"
    return $false
}

function Install-NodeIfNeeded {
    Write-Step "检测 Node.js"

    $nodeVer = Get-NodeMajorVersion
    if ($nodeVer -ge 20) {
        Write-Success "Node.js 已安装: $(node --version) (满足 ≥20 要求)"
        return $true
    }

    $isUpgrade = $nodeVer -gt 0
    if ($isUpgrade) {
        Write-Warn "Node.js 版本过低 ($(node --version))，需要 ≥ 20"
    } else {
        Write-Info "Node.js 未安装"
    }

    # 方案1: winget
    if (Test-WingetAvailable) {
        $wingetSuccess = if ($isUpgrade) {
            Install-WithWinget "OpenJS.NodeJS.LTS" "Node.js LTS" -Upgrade
        } else {
            Install-WithWinget "OpenJS.NodeJS.LTS" "Node.js LTS"
        }
        if ($wingetSuccess) {
            $newVer = Get-NodeMajorVersion
            if ($newVer -ge 20) { return $true }
        }
    }

    # 方案2: 从 npmmirror 下载 MSI
    if (-not (Test-IsAdmin)) {
        Write-Err "MSI 安装需要管理员权限，请右键以管理员身份运行 PowerShell 后重试"
        return $false
    }

    Write-Info "正在从国内镜像下载 Node.js $Script:NODE_VERSION ..."
    $nodeUrl = "$Script:NODE_MIRROR/$Script:NODE_VERSION/node-$Script:NODE_VERSION-x64.msi"
    $nodeMsi = Join-Path $env:TEMP "node-installer.msi"

    if (-not (Download-File -Url $nodeUrl -OutFile $nodeMsi)) {
        Write-Err "Node.js 下载失败，请手动安装 Node.js 20+: https://nodejs.org/"
        return $false
    }

    Write-Info "正在静默安装 Node.js（可能需要一两分钟）..."
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$nodeMsi`"", "/qn", "/norestart" -Wait -PassThru
    Remove-Item $nodeMsi -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        Write-Err "Node.js 安装失败（退出码: $($process.ExitCode)）"
        Write-Info "提示: MSI 安装可能需要管理员权限，请右键以管理员身份运行 PowerShell 后重试"
        return $false
    }

    Refresh-PathEnv
    $newVer = Get-NodeMajorVersion
    if ($newVer -ge 20) {
        Write-Success "Node.js $Script:NODE_VERSION 安装完成"
        return $true
    }

    Write-Err "Node.js 安装后版本仍不满足要求，请重启终端后重试"
    return $false
}

function Set-NpmMirror {
    Write-Step "配置 npm 国内镜像"

    # 解析 npm 路径
    Resolve-NpmPath
    if (-not $Script:NpmExe) {
        Write-Err "npm 未找到，跳过镜像配置"
        # 设置环境变量作为备用
        $env:npm_config_registry = $Script:NPM_MIRROR
        return
    }

    # 尝试多种方式设置，确保兼容不同 npm 版本
    Invoke-Npm @("config", "set", "registry", $Script:NPM_MIRROR, "--location=user") 2>$null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Npm @("config", "set", "registry", $Script:NPM_MIRROR) 2>$null
    }

    # 验证设置
    $current = Invoke-Npm @("config", "get", "registry") 2>$null
    if ($current) { $current = $current.Trim().TrimEnd('/') }
    $expected = $Script:NPM_MIRROR.TrimEnd('/')

    if ($current -eq $expected) {
        Write-Success "npm 镜像已设置: $Script:NPM_MIRROR"
    } else {
        $env:npm_config_registry = $Script:NPM_MIRROR
        Write-Warn "npm config 设置可能未生效（当前: $current），已通过环境变量补偿"
        Write-Info "后续 npm install 将使用镜像: $Script:NPM_MIRROR"
    }
}

# ============================================================
# 工具安装
# ============================================================

function Install-ClaudeCode {
    param([string]$ApiKey)

    Write-Step "安装 Claude Code"

    # 检测是否已安装
    $isUpdate = $false
    if (Test-ToolExists "claude") {
        $currentVer = Invoke-ToolCommand "claude" @("--version")
        Write-Info "Claude Code 已安装: $currentVer，将更新到最新版本"
        $isUpdate = $true
    }

    $action = if ($isUpdate) { "更新" } else { "安装" }
    Write-Info "正在通过 npm ${action} @anthropic-ai/claude-code ..."
    Invoke-Npm @("install", "-g", "@anthropic-ai/claude-code") 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    # 验证安装
    Refresh-PathEnv
    Resolve-NpmPath
    if (-not (Test-ToolExists "claude")) {
        Write-Err "Claude Code 安装失败"
        Write-Info "可尝试手动安装: npm install -g @anthropic-ai/claude-code"
        return $false
    }

    $newVer = Invoke-ToolCommand "claude" @("--version")
    if ($isUpdate) {
        Write-Success "Claude Code 已更新: $currentVer → $newVer"
    } else {
        Write-Success "Claude Code 安装成功: $newVer"
    }

    # 写入配置文件
    Write-Info "正在配置 Claude Code ..."
    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    Ensure-Directory $claudeDir

    $claudeConfig = @{
        env = @{
            ANTHROPIC_BASE_URL = $Script:API_BASE_URL
            ANTHROPIC_API_KEY  = $ApiKey
            ANTHROPIC_MODEL    = $Script:CLAUDE_MODEL
        }
    } | ConvertTo-Json -Depth 3

    $configPath = Join-Path $claudeDir "settings.json"
    # 如果已有配置文件，尝试合并 env 字段
    if (Test-Path $configPath) {
        try {
            $existing = Get-Content $configPath -Raw | ConvertFrom-Json
            $existing.env = @{
                ANTHROPIC_BASE_URL = $Script:API_BASE_URL
                ANTHROPIC_API_KEY  = $ApiKey
                ANTHROPIC_MODEL    = $Script:CLAUDE_MODEL
            }
            $claudeConfig = $existing | ConvertTo-Json -Depth 3
        } catch {
            Write-Warn "已有配置文件解析失败，将覆盖"
        }
    }

    [System.IO.File]::WriteAllText($configPath, $claudeConfig, $Script:UTF8NoBom)
    Write-Success "配置已写入: $configPath"

    # 设置持久化环境变量（Claude Code 从进程环境变量读取 API 配置，settings.json 的 env 字段仅用于子进程）
    Set-PersistentEnvVar "ANTHROPIC_BASE_URL" $Script:API_BASE_URL
    Set-PersistentEnvVar "ANTHROPIC_API_KEY" $ApiKey
    Set-PersistentEnvVar "ANTHROPIC_MODEL" $Script:CLAUDE_MODEL

    return $true
}

function Install-CodexCli {
    param([string]$ApiKey)

    Write-Step "安装 Codex CLI"

    # 检测是否已安装
    $isUpdate = $false
    $currentVer = $null
    if (Test-ToolExists "codex") {
        $currentVer = Invoke-ToolCommand "codex" @("--version")
        Write-Info "Codex CLI 已安装: $currentVer，将更新到最新版本"
        $isUpdate = $true
    }

    $action = if ($isUpdate) { "更新" } else { "安装" }
    Write-Info "正在通过 npm ${action} @openai/codex ..."
    Invoke-Npm @("install", "-g", "@openai/codex") 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    # 验证安装
    Refresh-PathEnv
    Resolve-NpmPath
    if (-not (Test-ToolExists "codex")) {
        Write-Err "Codex CLI 安装失败"
        Write-Info "可尝试手动安装: npm install -g @openai/codex"
        return $false
    }

    $newVer = Invoke-ToolCommand "codex" @("--version")
    if ($isUpdate) {
        Write-Success "Codex CLI 已更新: $currentVer → $newVer"
    } else {
        Write-Success "Codex CLI 安装成功: $newVer"
    }

    # 设置环境变量
    Write-Info "正在配置 Codex CLI ..."
    Set-PersistentEnvVar "OPENAI_API_KEY" $ApiKey

    # 写入配置文件
    $codexDir = Join-Path $env:USERPROFILE ".codex"
    Ensure-Directory $codexDir

    $configPath = Join-Path $codexDir "config.toml"
    # 如果已有配置文件，保留用户自定义内容，只更新 model 和 base_url
    $codexConfig = ""
    if (Test-Path $configPath) {
        $existingContent = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
        if ($existingContent) {
            # 替换已有的 model 和 openai_base_url 行，保留其他配置
            $codexConfig = $existingContent -replace 'model\s*=\s*"[^"]*"', "model = `"$Script:CODEX_MODEL`""
            $codexConfig = $codexConfig -replace 'openai_base_url\s*=\s*"[^"]*"', "openai_base_url = `"$Script:API_BASE_URL/v1`""
            # 如果原文件中没有这些字段，追加
            if ($codexConfig -notmatch 'model\s*=') {
                $codexConfig += "`nmodel = `"$Script:CODEX_MODEL`""
            }
            if ($codexConfig -notmatch 'openai_base_url\s*=') {
                $codexConfig += "`nopenai_base_url = `"$Script:API_BASE_URL/v1`""
            }
            Write-Info "已合并现有配置文件"
        }
    }
    if ([string]::IsNullOrWhiteSpace($codexConfig)) {
        $codexConfig = @"
# Codex CLI 配置 - 由 MAX API 安装脚本自动生成
model = "$Script:CODEX_MODEL"
openai_base_url = "$Script:API_BASE_URL/v1"
"@
    }
    [System.IO.File]::WriteAllText($configPath, $codexConfig, $Script:UTF8NoBom)
    Write-Success "配置已写入: $configPath"

    return $true
}

function Install-GeminiCli {
    param([string]$ApiKey)

    Write-Step "安装 Gemini CLI"

    # 检测是否已安装
    $isUpdate = $false
    $currentVer = $null
    if (Test-ToolExists "gemini") {
        $currentVer = Invoke-ToolCommand "gemini" @("--version")
        Write-Info "Gemini CLI 已安装: $currentVer，将更新到最新版本"
        $isUpdate = $true
    }

    $action = if ($isUpdate) { "更新" } else { "安装" }
    Write-Info "正在通过 npm ${action} @google/gemini-cli ..."
    Invoke-Npm @("install", "-g", "@google/gemini-cli") 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    # 验证安装
    Refresh-PathEnv
    Resolve-NpmPath
    if (-not (Test-ToolExists "gemini")) {
        Write-Err "Gemini CLI 安装失败"
        Write-Info "可尝试手动安装: npm install -g @google/gemini-cli"
        return $false
    }

    $newVer = Invoke-ToolCommand "gemini" @("--version")
    if ($isUpdate) {
        Write-Success "Gemini CLI 已更新: $currentVer → $newVer"
    } else {
        Write-Success "Gemini CLI 安装成功: $newVer"
    }

    # 设置环境变量
    Write-Info "正在配置 Gemini CLI ..."
    Set-PersistentEnvVar "GOOGLE_GEMINI_BASE_URL" $Script:API_BASE_URL
    Set-PersistentEnvVar "GEMINI_API_KEY" $ApiKey
    Set-PersistentEnvVar "GEMINI_MODEL" $Script:GEMINI_MODEL

    # 写入配置文件
    $geminiDir = Join-Path $env:USERPROFILE ".gemini"
    Ensure-Directory $geminiDir

    $settingsPath = Join-Path $geminiDir "settings.json"
    $geminiConfig = $null
    # 如果已有配置文件，合并而不是覆盖
    if (Test-Path $settingsPath) {
        try {
            $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if (-not $existing.model) {
                $existing | Add-Member -NotePropertyName "model" -NotePropertyValue @{ name = $Script:GEMINI_MODEL } -Force
            } else {
                $existing.model.name = $Script:GEMINI_MODEL
            }
            $geminiConfig = $existing | ConvertTo-Json -Depth 3
            Write-Info "已合并现有配置文件"
        } catch {
            Write-Warn "已有配置文件解析失败，将覆盖"
        }
    }
    if (-not $geminiConfig) {
        $geminiConfig = @{
            model = @{
                name = $Script:GEMINI_MODEL
            }
        } | ConvertTo-Json -Depth 3
    }

    [System.IO.File]::WriteAllText($settingsPath, $geminiConfig, $Script:UTF8NoBom)
    Write-Success "配置已写入: $settingsPath"

    return $true
}

# ============================================================
# 安装结果汇总
# ============================================================

function Show-Summary {
    param(
        [string[]]$SelectedTools,
        [hashtable]$Results
    )

    Write-Host ""
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║          MAX API · 安 装 结 果 汇 总            ║" -ForegroundColor Magenta
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""

    $toolNames = @{
        "claude" = "Claude Code"
        "codex"  = "Codex CLI"
        "gemini" = "Gemini CLI"
    }

    $toolCmds = @{
        "claude" = "claude"
        "codex"  = "codex"
        "gemini" = "gemini"
    }

    foreach ($tool in $SelectedTools) {
        $name = $toolNames[$tool]
        $status = if ($Results[$tool]) { "✔ 成功" } else { "✖ 失败" }
        $color  = if ($Results[$tool]) { "Green" } else { "Red" }
        Write-Host "    $name : " -NoNewline -ForegroundColor White
        Write-Host $status -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────" -ForegroundColor DarkGray

    # 使用说明
    $anySuccess = $Results.Values | Where-Object { $_ -eq $true }
    if ($anySuccess) {
        Write-Host ""
        Write-Host "  使用方法（在项目目录中运行）:" -ForegroundColor Yellow
        Write-Host ""

        foreach ($tool in $SelectedTools) {
            if ($Results[$tool]) {
                $cmd = $toolCmds[$tool]
                Write-Host "    $($toolNames[$tool]):" -ForegroundColor White
                Write-Host "      $cmd" -ForegroundColor Cyan
                Write-Host ""
            }
        }

        Write-Host "  MAX API 服务: $Script:API_BASE_URL" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  ⚠ 重要: 如果命令未找到，请关闭并重新打开终端窗口" -ForegroundColor Yellow
    }

    Write-Host ""
}

# ============================================================
# 主流程
# ============================================================

function Main {
    # 不使用 "Stop"，避免 npm 输出的警告行被当作终止错误
    $ErrorActionPreference = "Continue"

    # ★★★ 关键修复：设置当前进程的执行策略为 Bypass ★★★
    # 不需要管理员权限，仅影响当前 PowerShell 进程
    # 解决便携版 Node.js 的 npm.ps1 被执行策略拦截的问题
    try {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
    } catch {}

    # 设置终端编码为 UTF-8，确保中文和 Unicode 字符正常显示
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $OutputEncoding = [System.Text.Encoding]::UTF8
        }
    } catch {}
    # 确保 TLS 1.2 全局可用
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Clear-Host
    Write-Banner

    # 1. 环境检测
    if (-not (Test-Environment)) {
        Write-Err "环境检测未通过，安装中止"
        return
    }

    # 2. 选择工具
    $selectedTools = Show-ToolMenu
    Write-Info "已选择: $($selectedTools -join ', ')"

    # 3. 输入 API Key
    $apiKey = Read-ApiKey

    # 4. 安装依赖 — Git（仅 Claude Code 需要）
    if ($selectedTools -contains "claude") {
        if (-not (Install-GitIfNeeded)) {
            Write-Warn "Git 安装失败，Claude Code 可能无法正常工作"
        }
    }

    # 5. 安装依赖 — Node.js
    if (-not (Install-NodeIfNeeded)) {
        Write-Err "Node.js 安装失败，无法继续安装工具"
        Write-Info "请手动安装 Node.js 20+ 后重新运行此脚本"
        return
    }

    # 6. 配置 npm 镜像
    Set-NpmMirror

    # 7. 安装选定的工具
    $results = @{}

    if ($selectedTools -contains "claude") {
        $results["claude"] = Install-ClaudeCode -ApiKey $apiKey
    }
    if ($selectedTools -contains "codex") {
        $results["codex"] = Install-CodexCli -ApiKey $apiKey
    }
    if ($selectedTools -contains "gemini") {
        $results["gemini"] = Install-GeminiCli -ApiKey $apiKey
    }

    # 8. 汇总
    Show-Summary -SelectedTools $selectedTools -Results $results

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║     MAX API · 安装完毕！祝您使用愉快 🎉        ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
}

# 启动
Main
