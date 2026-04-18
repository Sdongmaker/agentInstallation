#Requires -Version 5.1
<#
.SYNOPSIS
    MAX API Windows installer for Claude Code, Codex CLI, and Gemini CLI.

.DESCRIPTION
    Installs and configures supported AI coding CLIs for Windows users.
    The script is written to stay compatible with Windows PowerShell 5.1.
#>

$Script:API_BASE_URL_CANDIDATES = @(
    [PSCustomObject]@{
        Name    = "橙云线路"
        BaseUrl = "https://new.28.al"
        Order   = 0
    },
    [PSCustomObject]@{
        Name    = "腾讯云CDN线路"
        BaseUrl = "https://new.1huanlesap02.top"
        Order   = 1
    }
)
$Script:API_BASE_URL   = $Script:API_BASE_URL_CANDIDATES[0].BaseUrl
$Script:API_ROUTE_NAME = $Script:API_BASE_URL_CANDIDATES[0].Name
$Script:NPM_MIRROR     = "https://registry.npmmirror.com"
$Script:GITHUB_PROXY   = "https://kk.eemby.de"
$Script:NODE_MIRROR    = "https://npmmirror.com/mirrors/node"
$Script:NODE_VERSION   = "v20.18.1"
$Script:GIT_VERSION    = "2.47.1"
$Script:GIT_RELEASE    = "v2.47.1.windows.2"
$Script:INSTALLER_VERSION = "v2.2"

$Script:CLAUDE_MODEL = "claude-opus-4-6"
$Script:CODEX_MODEL  = "gpt-5.4"
$Script:GEMINI_MODEL = "gemini-3.1-pro-preview"

$Script:UTF8NoBom = New-Object System.Text.UTF8Encoding($false)
$Script:NpmExe = $null

function Write-Banner {
    Write-Host ""
    Write-Host "  ███╗   ███╗ █████╗ ██╗  ██╗     █████╗ ██████╗ ██╗" -ForegroundColor Magenta
    Write-Host "  ████╗ ████║██╔══██╗╚██╗██╔╝    ██╔══██╗██╔══██╗██║" -ForegroundColor Magenta
    Write-Host "  ██╔████╔██║███████║ ╚███╔╝     ███████║██████╔╝██║" -ForegroundColor Magenta
    Write-Host "  ██║╚██╔╝██║██╔══██║ ██╔██╗     ██╔══██║██╔═══╝ ██║" -ForegroundColor Magenta
    Write-Host "  ██║ ╚═╝ ██║██║  ██║██╔╝ ██╗    ██║  ██║██║     ██║" -ForegroundColor Magenta
    Write-Host "  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝     ╚═╝" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host ("  │  AI 编程助手一键安装工具 {0,-23} │" -f $Script:INSTALLER_VERSION) -ForegroundColor Gray
    Write-Host "  │  支持: Claude Code · Codex CLI · Gemini CLI      │" -ForegroundColor Gray
    Write-Host ("  │  服务: {0,-39} │" -f "MAX API 自动测速选线") -ForegroundColor Gray
    Write-Host "  └──────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "▶ $Message" -ForegroundColor Green
    Write-Host ("-" * 60) -ForegroundColor DarkGray
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [信息] $Message" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [成功] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [警告] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [错误] $Message" -ForegroundColor Red
}

function Resolve-NpmPath {
    $cmd = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
    if ($cmd) {
        $Script:NpmExe = $cmd.Source
        return
    }

    $cmd = Get-Command "npm" -ErrorAction SilentlyContinue
    if ($cmd) {
        $Script:NpmExe = $cmd.Source
        return
    }

    $Script:NpmExe = $null
}

function Invoke-Npm {
    param([string[]]$Arguments)

    if (-not $Script:NpmExe) { Resolve-NpmPath }
    if (-not $Script:NpmExe) {
        Write-Err "未检测到 npm，请先安装 Node.js。"
        return $null
    }

    & $Script:NpmExe @Arguments
}

function Invoke-NpmCommand {
    param(
        [string[]]$Arguments,
        [switch]$SuppressOutput
    )

    if (-not $Script:NpmExe) { Resolve-NpmPath }
    if (-not $Script:NpmExe) {
        return [PSCustomObject]@{
            ExitCode = 1
            Output   = @("未检测到 npm 可执行文件")
        }
    }

    $output = @(& $Script:NpmExe @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $lines = @($output | ForEach-Object { "$_" })

    if (-not $SuppressOutput) {
        foreach ($line in $lines) {
            Write-Host "    $line" -ForegroundColor DarkGray
        }
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = $lines
    }
}

function Invoke-ToolCommandDetailed {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $cmd = Get-Command "$Command.cmd" -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    }

    if (-not $cmd) {
        return [PSCustomObject]@{
            Found      = $false
            Path       = $null
            ExitCode   = $null
            Output     = @()
            OutputText = $null
        }
    }

    $output = @(& $cmd.Source @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $lines = @($output | ForEach-Object { "$_" })

    return [PSCustomObject]@{
        Found      = $true
        Path       = $cmd.Source
        ExitCode   = $exitCode
        Output     = $lines
        OutputText = (($lines -join "`n").Trim())
    }
}

function Invoke-ToolCommandDetailedWithTimeout {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 0
    )

    if ($TimeoutSeconds -le 0) {
        $details = Invoke-ToolCommandDetailed -Command $Command -Arguments $Arguments
        $details | Add-Member -NotePropertyName TimedOut -NotePropertyValue $false -Force
        return $details
    }

    $cmd = Get-Command "$Command.cmd" -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    }

    if (-not $cmd) {
        return [PSCustomObject]@{
            Found      = $false
            Path       = $null
            ExitCode   = $null
            Output     = @()
            OutputText = $null
            TimedOut   = $false
        }
    }

    $job = Start-Job -ScriptBlock {
        param(
            [string]$CommandPath,
            [string[]]$CommandArguments,
            [string]$CommandWorkingDirectory
        )

        try {
            if (-not [string]::IsNullOrWhiteSpace($CommandWorkingDirectory)) {
                Set-Location -LiteralPath $CommandWorkingDirectory
            }

            $output = @(& $CommandPath @CommandArguments 2>&1)
            return [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output   = @($output | ForEach-Object { "$_" })
            }
        } catch {
            return [PSCustomObject]@{
                ExitCode = 1
                Output   = @("$($_.Exception.Message)")
            }
        }
    } -ArgumentList $cmd.Source, $Arguments, $WorkingDirectory

    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if (-not $completed) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
        return [PSCustomObject]@{
            Found      = $true
            Path       = $cmd.Source
            ExitCode   = $null
            Output     = @()
            OutputText = $null
            TimedOut   = $true
        }
    }

    $jobResult = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null

    $lines = @()
    $exitCode = 1
    if ($jobResult) {
        $firstResult = @($jobResult)[0]
        if ($firstResult.PSObject.Properties["Output"]) {
            $lines = @($firstResult.Output | ForEach-Object { "$_" })
        }
        if ($firstResult.PSObject.Properties["ExitCode"]) {
            $exitCode = $firstResult.ExitCode
        }
    }

    return [PSCustomObject]@{
        Found      = $true
        Path       = $cmd.Source
        ExitCode   = $exitCode
        Output     = $lines
        OutputText = (($lines -join "`n").Trim())
        TimedOut   = $false
    }
}

function Invoke-ToolCommand {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $details = Invoke-ToolCommandDetailed -Command $Command -Arguments $Arguments
    if (-not $details.Found -or $details.ExitCode -ne 0) {
        return $null
    }

    return $details.OutputText
}

function Test-ToolExists {
    param([string]$Command)

    return ($null -ne (Get-Command "$Command.cmd" -ErrorAction SilentlyContinue)) -or
           ($null -ne (Get-Command $Command -ErrorAction SilentlyContinue))
}

function Refresh-PathEnv {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-NodeMajorVersion {
    if (-not (Test-CommandExists "node")) { return 0 }

    try {
        $version = node --version 2>$null
        if ($version -match '^v(\d+)') {
            return [int]$Matches[1]
        }
    } catch {}

    return 0
}

function Test-WingetAvailable {
    return (Test-CommandExists "winget")
}

function Install-WithWinget {
    param(
        [string]$PackageId,
        [string]$FriendlyName,
        [switch]$Upgrade
    )

    if ($Upgrade) {
        Write-Info "正在通过 winget 升级 $FriendlyName ..."
        winget upgrade --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    } else {
        Write-Info "正在通过 winget 安装 $FriendlyName ..."
        winget install --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    }

    if ($LASTEXITCODE -eq 0) {
        Refresh-PathEnv
        Write-Success "$FriendlyName 已完成安装。"
        return $true
    }

    Write-Warn "$FriendlyName 的 winget 安装失败，正在回退到手动下载安装方案。"
    return $false
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile,
        [switch]$UseProxy
    )

    $downloadUrl = if ($UseProxy) { "$Script:GITHUB_PROXY/$Url" } else { $Url }
    Write-Info "正在下载 $downloadUrl"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        Write-Success "下载完成: $OutFile"
        return $true
    } catch {
        if ($UseProxy) {
            Write-Warn "代理下载失败，正在重试原始地址。"
            try {
                Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
                Write-Success "下载完成: $OutFile"
                return $true
            } catch {
                Write-Err "直连下载失败: $($_.Exception.Message)"
                return $false
            }
        }

        Write-Err "下载失败: $($_.Exception.Message)"
        return $false
    }
}

function Set-PersistentEnvVar {
    param(
        [string]$Name,
        [string]$Value
    )

    [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "Env:\$Name" -Value $Value
    Write-Info "已设置用户环境变量 $Name"
}

function Remove-PersistentEnvVar {
    param([string]$Name)

    [System.Environment]::SetEnvironmentVariable($Name, $null, "User")
    Remove-Item -Path "Env:\$Name" -ErrorAction SilentlyContinue
    Write-Info "已移除用户环境变量 $Name"
}

function Remove-PersistentEnvVarIfMatches {
    param(
        [string]$Name,
        [string]$ExpectedValue
    )

    $currentUserValue = [System.Environment]::GetEnvironmentVariable($Name, "User")
    if ([string]::IsNullOrEmpty($currentUserValue)) {
        Remove-Item -Path "Env:\$Name" -ErrorAction SilentlyContinue
        return
    }

    if ($currentUserValue -ne $ExpectedValue) {
        Write-Warn "环境变量 $Name 已存在且值不同，保持原值不变。"
        return
    }

    Remove-PersistentEnvVar -Name $Name
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Backup-FileIfExists {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$Path.bak.$timestamp"
    Copy-Item -Path $Path -Destination $backupPath -Force
    Write-Info "已备份现有文件到 $backupPath"
    return $backupPath
}

function Write-TextUtf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, $Script:UTF8NoBom)
}

function Read-TextUtf8 {
    param([string]$Path)

    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Mask-SecretValue {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value.Length -le 0) { return "" }
    if ($Value.Length -le 8) { return ('*' * [Math]::Max($Value.Length, 4)) }

    $visiblePrefix = [Math]::Min(4, $Value.Length)
    $visibleSuffix = [Math]::Min(4, $Value.Length - $visiblePrefix)
    $maskedLength = [Math]::Max($Value.Length - $visiblePrefix - $visibleSuffix, 4)

    return ($Value.Substring(0, $visiblePrefix) + ('*' * $maskedLength) + $Value.Substring($Value.Length - $visibleSuffix))
}

function Test-SensitiveKeyName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return $Name -match '(?i)(api[_-]?key|auth[_-]?token|bearer|token|secret|password)'
}

function Redact-TextSecrets {
    param([string]$Content)

    if ([string]::IsNullOrEmpty($Content)) {
        return $Content
    }

    $lines = $Content -split "`r?`n", -1
    $redacted = foreach ($line in $lines) {
        if ($line -notmatch '[:=]') {
            $line
            continue
        }

        $separatorIndex = $line.IndexOf(':')
        $equalsIndex = $line.IndexOf('=')
        if ($separatorIndex -lt 0 -or ($equalsIndex -ge 0 -and $equalsIndex -lt $separatorIndex)) {
            $separatorIndex = $equalsIndex
        }

        if ($separatorIndex -lt 0) {
            $line
            continue
        }

        $prefix = $line.Substring(0, $separatorIndex + 1)
        $valueAndTail = $line.Substring($separatorIndex + 1).Trim()
        $normalizedKey = $prefix.Trim().TrimEnd(':', '=').Trim().Trim('"').Trim("'")
        if (-not (Test-SensitiveKeyName -Name $normalizedKey)) {
            $line
            continue
        }

        $comment = ""
        $commentIndex = $valueAndTail.IndexOf('#')
        if ($commentIndex -ge 0) {
            $comment = $valueAndTail.Substring($commentIndex)
            $valueAndTail = $valueAndTail.Substring(0, $commentIndex).TrimEnd()
        }

        $quote = ""
        $value = $valueAndTail
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $quote = '"'
            $value = $value.Substring(1, $value.Length - 2)
        } elseif ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) {
            $quote = "'"
            $value = $value.Substring(1, $value.Length - 2)
        }

        $masked = Mask-SecretValue -Value $value
        $safeValue = if ($quote) { "$quote$masked$quote" } else { $masked }

        if ($comment) {
            "$($prefix.TrimEnd()) $safeValue $comment".TrimEnd()
        } else {
            "$($prefix.TrimEnd()) $safeValue"
        }
    }

    return ($redacted -join "`n")
}

function New-ToolResult {
    param([string]$Command)

    return [PSCustomObject]@{
        command           = $Command
        success           = $false
        installed         = $false
        configured        = $false
        runtime_validated = $false
        version_before    = $null
        version_after     = $null
        smoke_tested      = $false
        smoke_test_success = $false
        smoke_test_output = $null
        warnings          = (New-Object System.Collections.ArrayList)
        failure_reason    = $null
    }
}

function Add-ToolWarning {
    param(
        [object]$Result,
        [string]$Message
    )

    if ($null -eq $Result -or [string]::IsNullOrWhiteSpace($Message)) { return }
    if (-not ($Result.warnings -contains $Message)) {
        [void]$Result.warnings.Add($Message)
    }
    Write-Warn $Message
}

function Set-ToolFailure {
    param(
        [object]$Result,
        [string]$Message
    )

    if ($null -eq $Result -or [string]::IsNullOrWhiteSpace($Message)) { return }
    $Result.failure_reason = $Message
    Write-Err $Message
}

function Complete-ToolResult {
    param([object]$Result)

    if ($null -eq $Result) { return $Result }

    $Result.success = [bool](
        $Result.installed -and
        $Result.configured -and
        $Result.runtime_validated -and
        [string]::IsNullOrWhiteSpace($Result.failure_reason)
    )

    return $Result
}

function Test-NpmLockFailure {
    param([object]$NpmResult)

    if ($null -eq $NpmResult -or $NpmResult.ExitCode -eq 0) {
        return $false
    }

    $text = (($NpmResult.Output | ForEach-Object { "$_" }) -join "`n")
    return $text -match '(?i)\bEBUSY\b|resource busy or locked|\bEPERM\b.*(rename|copyfile|unlink|move)'
}

function Get-ToolShimDirectory {
    param([string]$Command)

    $cmdShim = Get-Command "$Command.cmd" -ErrorAction SilentlyContinue
    if (-not $cmdShim) { return $null }

    return (Split-Path -Path $cmdShim.Source -Parent)
}

function Get-GlobalNpmPackageDirectory {
    param(
        [string]$Command,
        [string]$PackageRelativePath
    )

    $shimDir = Get-ToolShimDirectory -Command $Command
    if ([string]::IsNullOrWhiteSpace($shimDir)) { return $null }

    return (Join-Path $shimDir ("node_modules\" + $PackageRelativePath))
}

function Get-ProcessesUsingPathPrefix {
    param([string]$PathPrefix)

    if ([string]::IsNullOrWhiteSpace($PathPrefix)) {
        return @()
    }

    $normalized = $PathPrefix.TrimEnd('\')
    $matches = New-Object System.Collections.ArrayList

    foreach ($process in (Get-Process -ErrorAction SilentlyContinue)) {
        $processPath = $null
        try {
            $processPath = $process.Path
        } catch {}

        if ([string]::IsNullOrWhiteSpace($processPath)) {
            continue
        }

        if ($processPath.StartsWith($normalized, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$matches.Add([PSCustomObject]@{
                ProcessName = $process.ProcessName
                Id          = $process.Id
                Path        = $processPath
            })
        }
    }

    return @($matches)
}

function Format-ProcessSummary {
    param([object[]]$Processes)

    if ($null -eq $Processes -or $Processes.Count -eq 0) {
        return $null
    }

    return (($Processes | ForEach-Object { "$($_.ProcessName)#$($_.Id)" }) -join ", ")
}

function Ensure-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($null -eq $Object) { return }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Read-JsonConfigOrDefault {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path $Path)) {
        return [PSCustomObject]@{}
    }

    try {
        $raw = Read-TextUtf8 -Path $Path
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Warn "$Label 为空，将创建新的配置文件。"
            return [PSCustomObject]@{}
        }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed) {
            return [PSCustomObject]@{}
        }

        return $parsed
    } catch {
        Write-Warn "$Label 无法解析，备份当前文件后将重新生成配置。"
        return [PSCustomObject]@{}
    }
}

function Show-TextPreview {
    param(
        [string]$Title,
        [string]$Content,
        [string]$Path
    )

    Write-Warn "下方预览已做脱敏处理，不会输出原始密钥。"
    Write-Host "  + $Title" -ForegroundColor DarkGray
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        Write-Host "  路径: $Path" -ForegroundColor DarkGray
    }
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray

    $safeContent = Redact-TextSecrets -Content $Content
    if ([string]::IsNullOrEmpty($safeContent)) {
        Write-Host "  <空>" -ForegroundColor DarkGray
    } else {
        foreach ($line in ($safeContent -split "`r?`n")) {
            Write-Host "  $line" -ForegroundColor Gray
        }
    }

    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
}

function Show-FilePreview {
    param(
        [string]$Path,
        [string]$Title
    )

    if (-not (Test-Path $Path)) {
        Write-Warn "未找到要预览的文件: $Path"
        return
    }

    try {
        $content = Read-TextUtf8 -Path $Path
        Show-TextPreview -Title $Title -Content $content -Path $Path
    } catch {
        Write-Warn "无法读取 $Path 进行预览: $($_.Exception.Message)"
    }
}

function Show-EnvPreview {
    param(
        [string]$Title,
        [hashtable]$Entries
    )

    Write-Warn "下方环境变量预览已做脱敏处理。"
    Write-Host "  + $Title" -ForegroundColor DarkGray
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
    foreach ($key in ($Entries.Keys | Sort-Object)) {
        $value = [string]$Entries[$key]
        if (Test-SensitiveKeyName -Name $key) {
            $value = Mask-SecretValue -Value $value
        }
        Write-Host "  $key=$value" -ForegroundColor Gray
    }
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
}

function Write-JsonConfigFile {
    param(
        [string]$Path,
        [object]$Object,
        [string]$Title
    )

    Backup-FileIfExists -Path $Path | Out-Null
    $content = $Object | ConvertTo-Json -Depth 10
    Write-TextUtf8NoBom -Path $Path -Content $content
    Write-Success "已写入配置文件: $Path"
    Show-FilePreview -Path $Path -Title $Title
}

function ConvertTo-TomlBasicString {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '""' }

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Try-NormalizeCodexProjectSectionHeader {
    param([string]$SectionName)

    if (-not $SectionName.StartsWith("projects.")) {
        return [PSCustomObject]@{
            Applicable = $false
            Success    = $true
            Header     = "[" + $SectionName + "]"
            Warning    = $null
        }
    }

    $projectKey = $SectionName.Substring("projects.".Length).Trim()
    $projectPath = $null

    if ($projectKey.Length -ge 2 -and $projectKey.StartsWith("'") -and $projectKey.EndsWith("'")) {
        $projectPath = $projectKey.Substring(1, $projectKey.Length - 2)
    } elseif ($projectKey.Length -ge 2 -and $projectKey.StartsWith('"') -and $projectKey.EndsWith('"')) {
        try {
            $projectPath = [regex]::Unescape($projectKey.Substring(1, $projectKey.Length - 2))
        } catch {
            return [PSCustomObject]@{
                Applicable = $true
                Success    = $false
                Header     = $null
                Warning    = "已跳过格式错误的 Codex 项目表头: [$SectionName]"
            }
        }
    } else {
        return [PSCustomObject]@{
            Applicable = $true
            Success    = $false
            Header     = $null
            Warning    = "已跳过格式错误的 Codex 项目表头: [$SectionName]"
        }
    }

    return [PSCustomObject]@{
        Applicable = $true
        Success    = $true
        Header     = '[projects.' + (ConvertTo-TomlBasicString -Value $projectPath) + ']'
        Warning    = $null
    }
}

function Build-CodexConfigContent {
    param(
        [string]$ExistingContent,
        [string]$ApiKey
    )

    $preSectionLines = New-Object System.Collections.ArrayList
    $remainingLines = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList

    $lines = @()
    if (-not [string]::IsNullOrEmpty($ExistingContent)) {
        $lines = $ExistingContent -split "`r?`n", -1
    }

    $seenSection = $false
    $skipSection = $false

    foreach ($line in $lines) {
        $sectionMatch = [regex]::Match($line, '^\s*\[([^\]]+)\]\s*$')
        if ($sectionMatch.Success) {
            $sectionName = $sectionMatch.Groups[1].Value.Trim()
            $seenSection = $true

            if ($sectionName.StartsWith("model_providers.maxapi", [System.StringComparison]::OrdinalIgnoreCase)) {
                $skipSection = $true
                continue
            }

            $skipSection = $false
            $normalizedProjectSection = Try-NormalizeCodexProjectSectionHeader -SectionName $sectionName
            if ($normalizedProjectSection.Applicable) {
                if (-not $normalizedProjectSection.Success) {
                    [void]$warnings.Add($normalizedProjectSection.Warning)
                    $skipSection = $true
                    continue
                }

                [void]$remainingLines.Add($normalizedProjectSection.Header)
            } else {
                [void]$remainingLines.Add($line)
            }
            continue
        }

        if ($skipSection) {
            continue
        }

        if (-not $seenSection) {
            if ($line -match '^\s*(model|model_provider|openai_base_url)\s*=') {
                continue
            }
            [void]$preSectionLines.Add($line)
        } else {
            [void]$remainingLines.Add($line)
        }
    }

    $preamble = (($preSectionLines | ForEach-Object { "$_" }) -join "`n").TrimEnd()
    $remaining = (($remainingLines | ForEach-Object { "$_" }) -join "`n").Trim()

    $topLevelBlock = @"
# Codex CLI 配置 - 由 MAX API 安装器生成
model = "$Script:CODEX_MODEL"
model_provider = "maxapi"
"@

    $providerBlock = @"
[model_providers.maxapi]
name = "MAX API"
base_url = "$Script:API_BASE_URL/v1"
wire_api = "responses"
experimental_bearer_token = "$ApiKey"
"@

    $parts = @()
    if ($preamble) { $parts += $preamble }
    $parts += $topLevelBlock.TrimEnd()
    if ($remaining) { $parts += $remaining }
    $parts += $providerBlock.TrimEnd()

    return [PSCustomObject]@{
        Content  = (($parts -join "`n`n").Trim() + "`n")
        Warnings = @($warnings)
    }
}

function Disable-PowerShellShimForCommand {
    param([string]$Command)

    $cmdShim = Get-Command "$Command.cmd" -ErrorAction SilentlyContinue
    if (-not $cmdShim) {
        Write-Warn "未找到 $Command.cmd，无法禁用对应的 PowerShell shim。"
        return $false
    }

    $cmdPath = $cmdShim.Source
    $ps1Path = [System.IO.Path]::ChangeExtension($cmdPath, ".ps1")
    $disabledPath = "$ps1Path.maxapi-disabled"

    Write-Info "$Command.cmd 路径: $cmdPath"
    Write-Info "$Command.ps1 路径: $ps1Path"

    if (-not (Test-Path $ps1Path)) {
        Write-Success "$Command 没有需要禁用的 PowerShell shim。"
        return $true
    }

    try {
        if (Test-Path $disabledPath) {
            Remove-Item $disabledPath -Force -ErrorAction Stop
        }

        Move-Item -Path $ps1Path -Destination $disabledPath -Force -ErrorAction Stop
        Write-Success "已禁用 $Command 的 PowerShell shim: $disabledPath"
        return $true
    } catch {
        Write-Warn "禁用 $Command 的 PowerShell shim 失败: $($_.Exception.Message)"
        return $false
    }
}

function Disable-PowerShellShims {
    param([string[]]$Commands)

    $uniqueCommands = @($Commands | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($uniqueCommands.Count -eq 0) {
        Write-Info "没有需要禁用的 PowerShell shim。"
        return
    }

    Write-Step "禁用 PowerShell .ps1 shim"
    foreach ($command in $uniqueCommands) {
        Disable-PowerShellShimForCommand -Command $command | Out-Null
    }
}

function Remove-LegacyPowerShellWrapperProfiles {
    $startMarker = "# >>> MAX API PowerShell CLI Wrappers >>>"
    $endMarker = "# <<< MAX API PowerShell CLI Wrappers <<<"
    $pattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))"

    $profilePaths = @(
        (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\profile.ps1"),
        (Join-Path $env:USERPROFILE "Documents\PowerShell\profile.ps1")
    ) | Select-Object -Unique

    Write-Step "清理旧版 PowerShell profile 包装器"

    foreach ($profilePath in $profilePaths) {
        if (-not (Test-Path $profilePath)) {
            Write-Info "未找到 profile 文件: $profilePath"
            continue
        }

        try {
            $existingContent = Read-TextUtf8 -Path $profilePath
        } catch {
            Write-Warn ("无法读取 {0}: {1}" -f $profilePath, $_.Exception.Message)
            continue
        }

        if ([string]::IsNullOrEmpty($existingContent)) {
            Write-Info "profile 文件为空: $profilePath"
            continue
        }

        $match = [regex]::Match($existingContent, $pattern)
        if (-not $match.Success) {
            Write-Info "未在 $profilePath 中发现旧版包装器代码块"
            continue
        }

        $removedBlock = $match.Value.Trim()
        $updatedContent = $existingContent.Substring(0, $match.Index) + $existingContent.Substring($match.Index + $match.Length)
        $updatedContent = ($updatedContent -replace '^[\r\n]+', '') -replace '[\r\n]+$', ''

        Backup-FileIfExists -Path $profilePath | Out-Null
        if ([string]::IsNullOrWhiteSpace($updatedContent)) {
            Remove-Item $profilePath -Force -ErrorAction SilentlyContinue
            Write-Success "已删除空的旧版 profile 文件: $profilePath"
        } else {
            Write-TextUtf8NoBom -Path $profilePath -Content ($updatedContent + "`n")
            Write-Success "已从 $profilePath 移除旧版包装器代码块"
        }

        Show-TextPreview -Title "已移除的旧版包装器代码块" -Content $removedBlock -Path $profilePath
    }
}

function Repair-PowerShellExecutionPolicy {
    Write-Step "修复 PowerShell 执行策略"

    $currentUserBefore = $null
    try {
        $currentUserBefore = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop
    } catch {}

    $setError = $null
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
    } catch {
        $setError = $_.Exception.Message
    }

    $currentUserAfter = $null
    try {
        $currentUserAfter = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop
    } catch {}

    if ($currentUserAfter -eq "RemoteSigned") {
        if ($currentUserBefore -eq "RemoteSigned") {
            Write-Success "CurrentUser 执行策略已是 RemoteSigned，无需修改。"
        } elseif ([string]::IsNullOrWhiteSpace($setError)) {
            Write-Success "已将 CurrentUser 执行策略设置为 RemoteSigned。"
        } else {
            Write-Success "尽管 Set-ExecutionPolicy 返回错误，但 CurrentUser 当前已是 RemoteSigned。"
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($setError)) {
        Write-Warn "设置 CurrentUser 执行策略失败: $setError"
    } elseif ([string]::IsNullOrWhiteSpace($currentUserAfter)) {
        Write-Warn "已执行 Set-ExecutionPolicy，但无法确认 CurrentUser 执行策略的最终状态。"
    } else {
        Write-Warn "已执行 Set-ExecutionPolicy，但 CurrentUser 当前仍为 $currentUserAfter。"
    }

    try {
        $diagnostics = Get-ExecutionPolicy -List | ForEach-Object {
            "$($_.Scope): $($_.ExecutionPolicy)"
        }
        Show-TextPreview -Title "PowerShell 执行策略诊断" -Content ($diagnostics -join "`n") -Path $null
    } catch {
        Write-Warn "无法读取 PowerShell 执行策略诊断信息: $($_.Exception.Message)"
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Environment {
    Write-Step "环境检测"

    if (-not ($env:OS -eq "Windows_NT")) {
        Write-Err "该安装器仅支持 Windows。"
        return $false
    }
    Write-Success "操作系统: Windows"

    if (-not [System.Environment]::Is64BitOperatingSystem) {
        Write-Err "该安装器仅支持 64 位 Windows。"
        return $false
    }
    Write-Success "系统架构: x86_64"

    Write-Success "PowerShell 版本: $($PSVersionTable.PSVersion)"

    if (Test-IsAdmin) {
        Write-Success "管理员权限: 是"
    } else {
        Write-Warn "管理员权限: 否。安装 Git 或 Node.js 时可能需要管理员权限。"
    }

    if (Test-WingetAvailable) {
        Write-Success "winget: 可用"
    } else {
        Write-Warn "winget: 不可用。需要时将回退到直接下载方案。"
    }

    return $true
}

function Show-ToolMenu {
    Write-Step "选择要安装的工具"
    Write-Host ""
    Write-Host "  [1] Claude Code" -ForegroundColor White
    Write-Host "  [2] Codex CLI" -ForegroundColor White
    Write-Host "  [3] Gemini CLI" -ForegroundColor White
    Write-Host ""
    Write-Host "  [A] 全部安装" -ForegroundColor Yellow
    Write-Host ""

    while ($true) {
        $choice = Read-Host "  请输入选项（例如：1,3 或 A）"
        $choice = $choice.Trim().ToUpper()

        if ($choice -eq "A") {
            return @("claude", "codex", "gemini")
        }

        $tools = @()
        $valid = $true

        foreach ($item in ($choice -split '[,\s]+' | Where-Object { $_ })) {
            switch ($item) {
                "1" { $tools += "claude" }
                "2" { $tools += "codex" }
                "3" { $tools += "gemini" }
                default { $valid = $false }
            }
        }

        if ($valid -and $tools.Count -gt 0) {
            return ($tools | Select-Object -Unique)
        }

        Write-Warn "无效选项。请输入 1-3，可用逗号分隔多选，或输入 A 表示全部安装。"
    }
}

function Read-ApiKey {
    Write-Step "配置 API Key"
    Write-Host ""
    Write-Host "  请输入来自 MAX API 的 API Key" -ForegroundColor White
    Write-Host "  输入内容不会显示，这是正常现象。" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        $secureKey = Read-Host "  API Key" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        try {
            $apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }

        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Write-Warn "API Key 不能为空。"
            continue
        }

        if ($apiKey.Length -lt 8) {
            Write-Warn "API Key 看起来过短，请检查后重新输入。"
            continue
        }

        return $apiKey
    }
}

function Get-MaxApiRoutePingStats {
    param(
        [object]$Route,
        [int]$Count = 10
    )

    $hostName = ([uri]$Route.BaseUrl).Host
    $samples = @()

    try {
        $samples = @(Test-Connection -ComputerName $hostName -Count $Count -ErrorAction SilentlyContinue)
    } catch {}

    $successSamples = @($samples | Where-Object {
        $_ -and
        $_.PSObject.Properties["StatusCode"] -and
        $_.StatusCode -eq 0
    })

    $received = $successSamples.Count
    $packetLoss = [Math]::Round((($Count - $received) * 100.0 / $Count), 2)
    $averageLatency = $null
    if ($received -gt 0) {
        $latencyMeasure = $successSamples | Measure-Object -Property ResponseTime -Average
        if ($latencyMeasure -and $null -ne $latencyMeasure.Average) {
            $averageLatency = [Math]::Round([double]$latencyMeasure.Average, 2)
        }
    }

    return [PSCustomObject]@{
        Name           = $Route.Name
        BaseUrl        = $Route.BaseUrl
        Host           = $hostName
        Order          = $Route.Order
        Sent           = $Count
        Received       = $received
        PacketLoss     = $packetLoss
        AverageLatency = $averageLatency
        Reachable      = ($received -gt 0)
    }
}

function Select-MaxApiRoute {
    $count = 10
    Write-Info "正在对候选 MAX API 线路执行 $count 次 ping 测试 ..."

    $routeStats = @()
    foreach ($route in $Script:API_BASE_URL_CANDIDATES) {
        $stats = Get-MaxApiRoutePingStats -Route $route -Count $count
        $routeStats += $stats

        $latencyText = if ($null -ne $stats.AverageLatency) { "$($stats.AverageLatency) ms" } else { "不可用" }
        if ($stats.Reachable) {
            Write-Info ("{0}: {1} | 丢包率 {2}% | 平均延迟 {3}" -f $stats.Name, $stats.Host, $stats.PacketLoss, $latencyText)
        } else {
            Write-Warn ("{0}: {1} | 10 次 ping 全部失败，当前线路可能屏蔽 ICMP 或暂时不可达。" -f $stats.Name, $stats.Host)
        }
    }

    $sortedStats = @(
        $routeStats |
            Sort-Object `
                @{ Expression = { [double]$_.PacketLoss }; Ascending = $true }, `
                @{ Expression = {
                    if ($null -eq $_.AverageLatency) {
                        [double]::PositiveInfinity
                    } else {
                        [double]$_.AverageLatency
                    }
                }; Ascending = $true }, `
                @{ Expression = { [int]$_.Order }; Ascending = $true }
    )

    $selected = $sortedStats | Select-Object -First 1
    if ($null -eq $selected) {
        $selected = [PSCustomObject]@{
            Name           = $Script:API_ROUTE_NAME
            BaseUrl        = $Script:API_BASE_URL
            Host           = ([uri]$Script:API_BASE_URL).Host
            Order          = 0
            Sent           = $count
            Received       = 0
            PacketLoss     = 100
            AverageLatency = $null
            Reachable      = $false
        }
    }

    $Script:API_BASE_URL = $selected.BaseUrl
    $Script:API_ROUTE_NAME = $selected.Name

    if ($routeStats.Count -gt 0 -and -not ($routeStats | Where-Object { $_.Reachable } | Select-Object -First 1)) {
        Write-Warn "两条 MAX API 线路的 ping 都没有收到响应，将先按默认优先级尝试 $($selected.Name)。"
    }

    Write-Success "已选择 MAX API 线路: $($selected.Name)（$($selected.BaseUrl)）"

    return [PSCustomObject]@{
        Selected  = $selected
        Candidates = $sortedStats
    }
}

function Invoke-MaxApiProbe {
    param(
        [object]$RouteStats,
        [string]$ApiKey
    )

    $probeUri = "$($RouteStats.BaseUrl)/v1/models"
    $headers = @{
        "Authorization" = "Bearer $ApiKey"
        "Accept"        = "application/json"
    }

    Write-Info "正在测试 $($RouteStats.Name) 的 HTTPS 可达性与认证状态 ..."
    Write-Info "探测端点: $probeUri"

    try {
        $response = Invoke-WebRequest -Uri $probeUri -Headers $headers -Method Get -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $statusCode = [int]$response.StatusCode
        $modelCount = $null
        $parsed = $null

        if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
            try {
                $parsed = $response.Content | ConvertFrom-Json -ErrorAction Stop
            } catch {}
        }

        if ($parsed -and $parsed.PSObject.Properties["data"] -and $null -ne $parsed.data) {
            try {
                $modelCount = @($parsed.data).Count
            } catch {}
        }

        return [PSCustomObject]@{
            Success         = $true
            Reachable       = $true
            Authenticated   = $true
            StatusCode      = $statusCode
            Endpoint        = $probeUri
            RouteName       = $RouteStats.Name
            BaseUrl         = $RouteStats.BaseUrl
            Message         = "MAX API 服务可达，认证通过。"
            ModelCount      = $modelCount
            SkipSmokeTests  = $false
            ShouldContinue  = $false
        }
    } catch {
        $statusCode = $null
        $statusDescription = $null
        $failureMessage = $_.Exception.Message

        if ($_.Exception.Response) {
            try {
                $statusCode = [int]$_.Exception.Response.StatusCode
            } catch {}
            try {
                $statusDescription = [string]$_.Exception.Response.StatusDescription
            } catch {}
        }

        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            $message = "MAX API 服务可达，但 API Key 未通过认证。"
            if (-not [string]::IsNullOrWhiteSpace($statusDescription)) {
                $message += " HTTP $statusCode $statusDescription。"
            } else {
                $message += " HTTP $statusCode。"
            }

            return [PSCustomObject]@{
                Success         = $false
                Reachable       = $true
                Authenticated   = $false
                StatusCode      = $statusCode
                Endpoint        = $probeUri
                RouteName       = $RouteStats.Name
                BaseUrl         = $RouteStats.BaseUrl
                Message         = $message
                ModelCount      = $null
                SkipSmokeTests  = $true
                ShouldContinue  = $false
            }
        }

        if ($null -ne $statusCode) {
            $message = "MAX API 已响应，但返回了异常状态。"
            if (-not [string]::IsNullOrWhiteSpace($statusDescription)) {
                $message += " HTTP $statusCode $statusDescription。"
            } else {
                $message += " HTTP $statusCode。"
            }

            return [PSCustomObject]@{
                Success         = $false
                Reachable       = $true
                Authenticated   = $false
                StatusCode      = $statusCode
                Endpoint        = $probeUri
                RouteName       = $RouteStats.Name
                BaseUrl         = $RouteStats.BaseUrl
                Message         = $message
                ModelCount      = $null
                SkipSmokeTests  = $true
                ShouldContinue  = $true
            }
        }

        return [PSCustomObject]@{
            Success         = $false
            Reachable       = $false
            Authenticated   = $false
            StatusCode      = $null
            Endpoint        = $probeUri
            RouteName       = $RouteStats.Name
            BaseUrl         = $RouteStats.BaseUrl
            Message         = "无法连接 MAX API 服务: $failureMessage"
            ModelCount      = $null
            SkipSmokeTests  = $true
            ShouldContinue  = $true
        }
    }
}

function Test-MaxApiReachability {
    param([string]$ApiKey)

    Write-Step "检测 MAX API 服务"
    $routeSelection = Select-MaxApiRoute
    $orderedRoutes = @($routeSelection.Candidates)
    $lastProbeResult = $null

    for ($index = 0; $index -lt $orderedRoutes.Count; $index++) {
        $routeStats = $orderedRoutes[$index]
        $probeResult = Invoke-MaxApiProbe -RouteStats $routeStats -ApiKey $ApiKey
        $lastProbeResult = $probeResult

        if ($probeResult.Success) {
            $Script:API_BASE_URL = $probeResult.BaseUrl
            $Script:API_ROUTE_NAME = $probeResult.RouteName

            Write-Success "MAX API 服务可达，认证通过。"
            Write-Info "已使用线路: $($probeResult.RouteName)"
            Write-Info "HTTP 状态: $($probeResult.StatusCode)"
            if ($null -ne $probeResult.ModelCount) {
                Write-Info "模型列表获取成功，共返回 $($probeResult.ModelCount) 个模型。"
            }

            return $probeResult
        }

        if ($probeResult.Reachable -and -not $probeResult.Authenticated -and ($probeResult.StatusCode -eq 401 -or $probeResult.StatusCode -eq 403)) {
            $Script:API_BASE_URL = $probeResult.BaseUrl
            $Script:API_ROUTE_NAME = $probeResult.RouteName

            Write-Warn $probeResult.Message
            Write-Warn "安装将继续，但会跳过最终真实调用测试。请检查 API Key 是否正确。"
            return $probeResult
        }

        Write-Warn "$($probeResult.RouteName) 预检查失败: $($probeResult.Message)"
        if ($probeResult.ShouldContinue -and $index -lt ($orderedRoutes.Count - 1)) {
            Write-Info "正在尝试下一条候选线路 ..."
            continue
        }

        break
    }

    if ($lastProbeResult) {
        $finalMessage = "所有候选线路的 HTTPS 预检查都未通过。已保留丢包率最低的线路 $Script:API_ROUTE_NAME。最后一次错误: $($lastProbeResult.Message)"
        Write-Warn $finalMessage
        Write-Warn "安装将继续，以便先完成 CLI 部署；最终真实调用测试将跳过。"
        return [PSCustomObject]@{
            Success         = $false
            Reachable       = $false
            Authenticated   = $false
            StatusCode      = $lastProbeResult.StatusCode
            Endpoint        = "$Script:API_BASE_URL/v1/models"
            RouteName       = $Script:API_ROUTE_NAME
            BaseUrl         = $Script:API_BASE_URL
            Message         = $finalMessage
            ModelCount      = $null
            SkipSmokeTests  = $true
            ShouldContinue  = $false
        }
    }

    $fallbackResult = [PSCustomObject]@{
        Success         = $false
        Reachable       = $false
        Authenticated   = $false
        StatusCode      = $null
        Endpoint        = "$Script:API_BASE_URL/v1/models"
        RouteName       = $Script:API_ROUTE_NAME
        BaseUrl         = $Script:API_BASE_URL
        Message         = "未能完成 MAX API 线路预检查。"
        ModelCount      = $null
        SkipSmokeTests  = $true
        ShouldContinue  = $false
    }

    Write-Warn $fallbackResult.Message
    Write-Warn "安装将继续，以便先完成 CLI 部署；最终真实调用测试将跳过。"
    return $fallbackResult
}

function Install-GitIfNeeded {
    Write-Step "检测 Git"

    if (Test-CommandExists "git") {
        Write-Success "Git 已安装: $(git --version 2>$null)"
        return $true
    }

    Write-Info "Claude Code 依赖 Git。"
    if (Test-WingetAvailable) {
        if (Install-WithWinget -PackageId "Git.Git" -FriendlyName "Git for Windows") {
            return $true
        }
    }

    if (-not (Test-IsAdmin)) {
        Write-Warn "静默安装 Git 需要管理员权限。"
        Write-Info "请以管理员身份重新运行 PowerShell，或手动从 https://git-scm.com/downloads/win 安装 Git。"
        return $false
    }

    $gitUrl = "https://github.com/git-for-windows/git/releases/download/$Script:GIT_RELEASE/Git-$Script:GIT_VERSION.2-64-bit.exe"
    $installerPath = Join-Path $env:TEMP "git-installer.exe"
    if (-not (Download-File -Url $gitUrl -OutFile $installerPath -UseProxy)) {
        Write-Err "Git 下载失败。"
        return $false
    }

    Write-Info "正在静默安装 Git ..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-" -Wait -PassThru
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        Write-Err "Git 安装程序退出，返回码: $($process.ExitCode)。"
        return $false
    }

    Refresh-PathEnv
    if (Test-CommandExists "git") {
        Write-Success "Git 安装成功。"
        return $true
    }

    Write-Err "Git 安装后仍未检测到命令。"
    return $false
}

function Install-NodeIfNeeded {
    Write-Step "检测 Node.js"

    $major = Get-NodeMajorVersion
    if ($major -ge 20) {
        Write-Success "Node.js 已安装: $(node --version)（满足 >=20 要求）"
        return $true
    }

    $isUpgrade = $major -gt 0
    if ($isUpgrade) {
        Write-Warn "Node.js 版本过低: $(node --version)。需要 Node.js 20 及以上版本。"
    } else {
        Write-Info "未检测到 Node.js。"
    }

    if (Test-WingetAvailable) {
        $wingetSucceeded = if ($isUpgrade) {
            Install-WithWinget -PackageId "OpenJS.NodeJS.LTS" -FriendlyName "Node.js LTS" -Upgrade
        } else {
            Install-WithWinget -PackageId "OpenJS.NodeJS.LTS" -FriendlyName "Node.js LTS"
        }

        if ($wingetSucceeded) {
            if ((Get-NodeMajorVersion) -ge 20) {
                return $true
            }
        }
    }

    if (-not (Test-IsAdmin)) {
        Write-Err "通过 MSI 安装 Node.js 需要管理员权限。"
        return $false
    }

    $nodeUrl = "$Script:NODE_MIRROR/$Script:NODE_VERSION/node-$Script:NODE_VERSION-x64.msi"
    $msiPath = Join-Path $env:TEMP "node-installer.msi"
    if (-not (Download-File -Url $nodeUrl -OutFile $msiPath)) {
        Write-Err "Node.js 下载失败。"
        return $false
    }

    Write-Info "正在静默安装 Node.js ..."
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$msiPath`"", "/qn", "/norestart" -Wait -PassThru
    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        Write-Err "Node.js 安装程序退出，返回码: $($process.ExitCode)。"
        return $false
    }

    Refresh-PathEnv
    if ((Get-NodeMajorVersion) -ge 20) {
        Write-Success "Node.js 安装成功。"
        return $true
    }

    Write-Err "Node.js 安装后仍未达到版本要求。"
    return $false
}

function Set-NpmMirror {
    Write-Step "配置 npm 国内镜像"

    Resolve-NpmPath
    if (-not $Script:NpmExe) {
        Write-Err "未检测到 npm，跳过镜像配置。"
        $env:npm_config_registry = $Script:NPM_MIRROR
        return
    }

    Invoke-Npm @("config", "set", "registry", $Script:NPM_MIRROR, "--location=user") 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Npm @("config", "set", "registry", $Script:NPM_MIRROR) 2>$null | Out-Null
    }

    $current = Invoke-Npm @("config", "get", "registry") 2>$null
    if ($current) {
        $current = $current.Trim().TrimEnd('/')
    }
    $expected = $Script:NPM_MIRROR.TrimEnd('/')

    if ($current -eq $expected) {
        Write-Success "npm 镜像已设置为 $Script:NPM_MIRROR"
    } else {
        $env:npm_config_registry = $Script:NPM_MIRROR
        Write-Warn "npm 镜像未能成功持久化，当前进程仍会使用 $Script:NPM_MIRROR"
    }

    Write-Info "Codex CLI 与 Gemini CLI 默认使用国内镜像；Claude Code 为确保原生 Windows 二进制完整，会单独使用官方 npm 源安装。"
}

function Get-ToolDisplayName {
    param([string]$Tool)

    switch ($Tool) {
        "claude" { return "Claude Code" }
        "codex"  { return "Codex CLI" }
        "gemini" { return "Gemini CLI" }
        default  { return $Tool }
    }
}

function Get-ToolCommandName {
    param([string]$Tool)

    switch ($Tool) {
        "claude" { return "claude" }
        "codex"  { return "codex" }
        "gemini" { return "gemini" }
        default  { return $Tool }
    }
}

function Get-PrimaryOutputLine {
    param([string[]]$Lines)

    $line = $Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return "$line"
}

function Format-OutputSnippet {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $safeText = (Redact-TextSecrets -Content $Text).Trim()
    if ($safeText.Length -le 240) {
        return $safeText
    }

    return ($safeText.Substring(0, 237) + "...")
}

function Test-ToolVersionCommand {
    param(
        [string]$Command,
        [string]$DisplayName
    )

    $details = Invoke-ToolCommandDetailed -Command $Command -Arguments @("--version")
    $versionLine = Get-PrimaryOutputLine -Lines $details.Output

    if (-not $details.Found) {
        return [PSCustomObject]@{
            Success = $false
            Version = $null
            Details = $details
            Message = "未找到 $DisplayName 命令。"
        }
    }

    if ($details.ExitCode -ne 0) {
        $snippet = Format-OutputSnippet -Text $details.OutputText
        $message = "$DisplayName 启动失败。"
        if ($snippet) {
            $message += " 输出: $snippet"
        }

        return [PSCustomObject]@{
            Success = $false
            Version = $null
            Details = $details
            Message = $message
        }
    }

    if ([string]::IsNullOrWhiteSpace($versionLine)) {
        return [PSCustomObject]@{
            Success = $false
            Version = $null
            Details = $details
            Message = "$DisplayName 没有返回版本信息。"
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Version = $versionLine
        Details = $details
        Message = $null
    }
}

function Get-NpmFailureMessage {
    param(
        [string]$DisplayName,
        [object]$NpmResult,
        [object[]]$ActiveProcesses
    )

    if (Test-NpmLockFailure -NpmResult $NpmResult) {
        $message = "$DisplayName 更新失败，原因是一个或多个已安装文件正在被占用。请关闭所有正在运行的 $DisplayName 会话后重试。"
        $processSummary = Format-ProcessSummary -Processes $ActiveProcesses
        if ($processSummary) {
            $message += " 检测到的进程: $processSummary。"
        }
        return $message
    }

    $snippet = Format-OutputSnippet -Text (($NpmResult.Output | ForEach-Object { "$_" }) -join "`n")
    $message = "$DisplayName 的 npm 安装失败"
    if ($null -ne $NpmResult.ExitCode) {
        $message += "（退出码 $($NpmResult.ExitCode)）"
    }
    $message += "。"
    if ($snippet) {
        $message += " 输出: $snippet"
    }

    return $message
}

function Get-ClaudeBinaryState {
    $packageDir = Get-GlobalNpmPackageDirectory -Command "claude" -PackageRelativePath "@anthropic-ai\claude-code"
    $binaryPath = if ($packageDir) { Join-Path $packageDir "bin\claude.exe" } else { $null }

    if ([string]::IsNullOrWhiteSpace($binaryPath) -or -not (Test-Path $binaryPath)) {
        return [PSCustomObject]@{
            PackageDir    = $packageDir
            BinaryPath    = $binaryPath
            Exists        = $false
            Size          = 0
            StubDetected  = $false
            NativeReady   = $false
        }
    }

    $fileInfo = Get-Item -LiteralPath $binaryPath -ErrorAction SilentlyContinue
    $size = if ($fileInfo) { [int64]$fileInfo.Length } else { 0 }
    $stubDetected = $size -le 4096

    return [PSCustomObject]@{
        PackageDir    = $packageDir
        BinaryPath    = $binaryPath
        Exists        = $true
        Size          = $size
        StubDetected  = $stubDetected
        NativeReady   = (-not $stubDetected)
    }
}

function Test-ClaudeRuntime {
    $binaryState = Get-ClaudeBinaryState
    $versionCheck = Test-ToolVersionCommand -Command "claude" -DisplayName "Claude Code"

    if (-not $binaryState.Exists) {
        return [PSCustomObject]@{
            Success          = $false
            Version          = $versionCheck.Version
            BinaryState      = $binaryState
            NeedsOfficialFix = $true
            Message          = "Claude Code 的原生启动器未能写入磁盘。"
        }
    }

    if ($binaryState.StubDetected) {
        return [PSCustomObject]@{
            Success          = $false
            Version          = $versionCheck.Version
            BinaryState      = $binaryState
            NeedsOfficialFix = $true
            Message          = "Claude Code 当前仍只有 stub 启动器，缺少原生 Windows 二进制文件。"
        }
    }

    if (-not $versionCheck.Success) {
        return [PSCustomObject]@{
            Success          = $false
            Version          = $null
            BinaryState      = $binaryState
            NeedsOfficialFix = $false
            Message          = $versionCheck.Message
        }
    }

    return [PSCustomObject]@{
        Success          = $true
        Version          = $versionCheck.Version
        BinaryState      = $binaryState
        NeedsOfficialFix = $false
        Message          = $null
    }
}

function Get-MissingGeminiMcpCommands {
    param([object]$Settings)

    $missing = New-Object System.Collections.ArrayList
    if ($null -eq $Settings) {
        return @()
    }

    $mcpProperty = $Settings.PSObject.Properties["mcpServers"]
    if (-not $mcpProperty -or $null -eq $Settings.mcpServers) {
        return @()
    }

    foreach ($serverProperty in $Settings.mcpServers.PSObject.Properties) {
        $serverName = $serverProperty.Name
        $server = $serverProperty.Value
        if ($null -eq $server) { continue }

        $commandProperty = $server.PSObject.Properties["command"]
        if (-not $commandProperty) { continue }

        $commandName = [string]$server.command
        if ([string]::IsNullOrWhiteSpace($commandName)) { continue }

        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            [void]$missing.Add("Gemini MCP 服务 '$serverName' 的命令不存在: $commandName")
        }
    }

    return @($missing)
}

function Ensure-GeminiNode20Runtime {
    $runtimeDir = Join-Path $env:USERPROFILE ".gemini\node20-runtime"
    $nodePath = Join-Path $runtimeDir "node_modules\node\bin\node.exe"

    if (Test-Path $nodePath) {
        return [PSCustomObject]@{
            Success   = $true
            NodePath  = $nodePath
            Installed = $false
            Message   = $null
        }
    }

    Ensure-Directory $runtimeDir
    Write-Info "检测到当前 Windows 环境使用 Node.js 24+，正在为 Gemini CLI 准备专用 Node.js 20 运行时 ..."
    $npmResult = Invoke-NpmCommand -Arguments @("install", "--prefix", $runtimeDir, "node@20", "--no-save")
    if ($npmResult.ExitCode -ne 0) {
        $snippet = Format-OutputSnippet -Text (($npmResult.Output | ForEach-Object { "$_" }) -join "`n")
        $message = "为 Gemini CLI 安装专用 Node.js 20 运行时失败。"
        if ($snippet) {
            $message += " 输出: $snippet"
        }

        return [PSCustomObject]@{
            Success   = $false
            NodePath  = $null
            Installed = $false
            Message   = $message
        }
    }

    if (-not (Test-Path $nodePath)) {
        return [PSCustomObject]@{
            Success   = $false
            NodePath  = $null
            Installed = $false
            Message   = "专用 Node.js 20 运行时安装完成，但未找到 node.exe。"
        }
    }

    return [PSCustomObject]@{
        Success   = $true
        NodePath  = $nodePath
        Installed = $true
        Message   = $null
    }
}

function Install-GeminiCmdWrapper {
    param([string]$NodePath)

    $cmdShim = Get-Command "gemini.cmd" -ErrorAction SilentlyContinue
    if (-not $cmdShim) {
        return [PSCustomObject]@{
            Success = $false
            Message = "未找到 gemini.cmd，无法安装 Gemini 启动包装器。"
        }
    }

    $cmdPath = $cmdShim.Source
    $shimDir = Split-Path -Path $cmdPath -Parent
    $geminiJsPath = Join-Path $shimDir "node_modules\@google\gemini-cli\bundle\gemini.js"
    $backupPath = "$cmdPath.maxapi-original"

    if (-not (Test-Path $geminiJsPath)) {
        return [PSCustomObject]@{
            Success = $false
            Message = "未找到 Gemini CLI 主脚本，无法安装 Gemini 启动包装器。"
        }
    }

    try {
        if (-not (Test-Path $backupPath)) {
            Copy-Item -Path $cmdPath -Destination $backupPath -Force
        }

        $wrapper = @"
@echo off
setlocal
set "MAXAPI_GEMINI_NODE20=$NodePath"
set "MAXAPI_GEMINI_JS=$geminiJsPath"
if exist "%MAXAPI_GEMINI_NODE20%" if exist "%MAXAPI_GEMINI_JS%" (
  "%MAXAPI_GEMINI_NODE20%" "%MAXAPI_GEMINI_JS%" %*
  exit /b %ERRORLEVEL%
)
node "%MAXAPI_GEMINI_JS%" %*
exit /b %ERRORLEVEL%
"@

        Write-TextUtf8NoBom -Path $cmdPath -Content $wrapper
        return [PSCustomObject]@{
            Success = $true
            Message = $null
        }
    } catch {
        return [PSCustomObject]@{
            Success = $false
            Message = "写入 Gemini 启动包装器失败: $($_.Exception.Message)"
        }
    }
}

function Install-ClaudeCode {
    param([string]$ApiKey)

    $result = New-ToolResult -Command "claude"
    $displayName = "Claude Code"

    Write-Step "安装 Claude Code"

    $currentCheck = Test-ToolVersionCommand -Command "claude" -DisplayName $displayName
    $isUpdate = Test-ToolExists "claude"
    if ($currentCheck.Success) {
        $result.version_before = $currentCheck.Version
        Write-Info "$displayName 已安装: $($currentCheck.Version)，将更新到最新版本。"
    } elseif ($isUpdate) {
        Write-Warn "检测到 $displayName，但当前状态异常，正在重新安装。"
    }

    $packageDir = Get-GlobalNpmPackageDirectory -Command "claude" -PackageRelativePath "@anthropic-ai\claude-code"
    $activeProcesses = @()
    if ($isUpdate -and $packageDir) {
        $activeProcesses = Get-ProcessesUsingPathPrefix -PathPrefix $packageDir
        if ($activeProcesses.Count -gt 0) {
            Add-ToolWarning -Result $result -Message "检测到全局 npm 安装目录中仍有 Claude Code 进程在运行: $(Format-ProcessSummary -Processes $activeProcesses)。请先关闭它们，否则更新可能失败。"
        }
    }

    Write-Info "Claude Code 依赖原生 optional dependency，为确保 Windows 二进制完整，将固定使用官方 npm 源安装。"
    Write-Info "正在通过官方 npm 源安装 Claude Code ..."
    $npmResult = Invoke-NpmCommand -Arguments @("install", "-g", "@anthropic-ai/claude-code", "--registry=https://registry.npmjs.org")
    if ($npmResult.ExitCode -ne 0) {
        Set-ToolFailure -Result $result -Message (Get-NpmFailureMessage -DisplayName $displayName -NpmResult $npmResult -ActiveProcesses $activeProcesses)
        return (Complete-ToolResult -Result $result)
    }

    Refresh-PathEnv
    Resolve-NpmPath
    $result.installed = $true

    $runtimeCheck = Test-ClaudeRuntime
    if ($runtimeCheck.NeedsOfficialFix) {
        Add-ToolWarning -Result $result -Message "官方 npm 源安装后仍未正确生成 Claude Code 原生二进制文件，正在再重试一次。"
        $retry = Invoke-NpmCommand -Arguments @("install", "-g", "@anthropic-ai/claude-code", "--registry=https://registry.npmjs.org")
        if ($retry.ExitCode -ne 0) {
            Set-ToolFailure -Result $result -Message (Get-NpmFailureMessage -DisplayName $displayName -NpmResult $retry -ActiveProcesses @())
            return (Complete-ToolResult -Result $result)
        }

        Refresh-PathEnv
        Resolve-NpmPath
        $runtimeCheck = Test-ClaudeRuntime
    }

    if (-not $runtimeCheck.Success) {
        Set-ToolFailure -Result $result -Message $runtimeCheck.Message
        return (Complete-ToolResult -Result $result)
    }

    $result.runtime_validated = $true
    $result.version_after = $runtimeCheck.Version

    if ($result.version_before) {
        Write-Success "$displayName 已更新: $($result.version_before) -> $($result.version_after)"
    } else {
        Write-Success "$displayName 安装完成: $($result.version_after)"
    }

    Write-Info "正在写入 Claude Code 配置 ..."
    try {
        $claudeDir = Join-Path $env:USERPROFILE ".claude"
        Ensure-Directory $claudeDir

        $configPath = Join-Path $claudeDir "settings.json"
        $claudeSettings = Read-JsonConfigOrDefault -Path $configPath -Label "Claude Code 配置文件"
        $claudeEnv = if ($claudeSettings.PSObject.Properties["env"] -and $claudeSettings.env) {
            $claudeSettings.env
        } else {
            [PSCustomObject]@{}
        }

        Ensure-ObjectProperty -Object $claudeEnv -Name "ANTHROPIC_MODEL" -Value $Script:CLAUDE_MODEL
        Ensure-ObjectProperty -Object $claudeEnv -Name "ANTHROPIC_API_KEY" -Value $ApiKey
        Ensure-ObjectProperty -Object $claudeEnv -Name "ANTHROPIC_BASE_URL" -Value $Script:API_BASE_URL
        Ensure-ObjectProperty -Object $claudeEnv -Name "ANTHROPIC_AUTH_TOKEN" -Value $ApiKey
        Ensure-ObjectProperty -Object $claudeSettings -Name "env" -Value $claudeEnv

        Write-JsonConfigFile -Path $configPath -Object $claudeSettings -Title "Claude Code 配置文件"

        Remove-PersistentEnvVarIfMatches -Name "ANTHROPIC_MODEL" -ExpectedValue $Script:CLAUDE_MODEL
        Remove-PersistentEnvVarIfMatches -Name "ANTHROPIC_API_KEY" -ExpectedValue $ApiKey
        Remove-PersistentEnvVarIfMatches -Name "ANTHROPIC_BASE_URL" -ExpectedValue $Script:API_BASE_URL
        Remove-PersistentEnvVarIfMatches -Name "ANTHROPIC_AUTH_TOKEN" -ExpectedValue $ApiKey

        $result.configured = $true
    } catch {
        Set-ToolFailure -Result $result -Message "Claude Code 已安装，但写入配置失败: $($_.Exception.Message)"
    }

    return (Complete-ToolResult -Result $result)
}

function Install-CodexCli {
    param([string]$ApiKey)

    $result = New-ToolResult -Command "codex"
    $displayName = "Codex CLI"

    Write-Step "安装 Codex CLI"

    $currentCheck = Test-ToolVersionCommand -Command "codex" -DisplayName $displayName
    $isUpdate = Test-ToolExists "codex"
    if ($currentCheck.Success) {
        $result.version_before = $currentCheck.Version
        Write-Info "$displayName 已安装: $($currentCheck.Version)，将更新到最新版本。"
    } elseif ($isUpdate) {
        Write-Warn "检测到 $displayName，但当前状态异常，正在重新安装。"
    }

    $packageDir = Get-GlobalNpmPackageDirectory -Command "codex" -PackageRelativePath "@openai\codex"
    $activeProcesses = @()
    if ($isUpdate -and $packageDir) {
        $activeProcesses = Get-ProcessesUsingPathPrefix -PathPrefix $packageDir
        if ($activeProcesses.Count -gt 0) {
            Add-ToolWarning -Result $result -Message "检测到全局 npm 安装目录中仍有 Codex CLI 进程在运行: $(Format-ProcessSummary -Processes $activeProcesses)。请先关闭它们，否则更新可能失败。"
        }
    }

    Write-Info "正在通过 npm 安装 Codex CLI ..."
    $npmResult = Invoke-NpmCommand -Arguments @("install", "-g", "@openai/codex")
    if ($npmResult.ExitCode -ne 0) {
        Set-ToolFailure -Result $result -Message (Get-NpmFailureMessage -DisplayName $displayName -NpmResult $npmResult -ActiveProcesses $activeProcesses)
        return (Complete-ToolResult -Result $result)
    }

    Refresh-PathEnv
    Resolve-NpmPath
    $result.installed = $true

    $runtimeCheck = Test-ToolVersionCommand -Command "codex" -DisplayName $displayName
    if (-not $runtimeCheck.Success) {
        Set-ToolFailure -Result $result -Message $runtimeCheck.Message
        return (Complete-ToolResult -Result $result)
    }

    $result.runtime_validated = $true
    $result.version_after = $runtimeCheck.Version

    if ($result.version_before) {
        Write-Success "$displayName 已更新: $($result.version_before) -> $($result.version_after)"
    } else {
        Write-Success "$displayName 安装完成: $($result.version_after)"
    }

    Write-Info "正在写入 Codex CLI 配置 ..."
    try {
        $codexDir = Join-Path $env:USERPROFILE ".codex"
        Ensure-Directory $codexDir

        $configPath = Join-Path $codexDir "config.toml"
        $existingContent = ""
        if (Test-Path $configPath) {
            $existingContent = Read-TextUtf8 -Path $configPath
        }

        $codexConfig = Build-CodexConfigContent -ExistingContent $existingContent -ApiKey $ApiKey
        foreach ($warning in $codexConfig.Warnings) {
            Add-ToolWarning -Result $result -Message $warning
        }

        Backup-FileIfExists -Path $configPath | Out-Null
        Write-TextUtf8NoBom -Path $configPath -Content $codexConfig.Content
        Write-Success "已写入 Codex CLI 配置: $configPath"
        Show-FilePreview -Path $configPath -Title "Codex CLI 配置文件"

        Remove-PersistentEnvVarIfMatches -Name "OPENAI_API_KEY" -ExpectedValue $ApiKey
        $result.configured = $true
    } catch {
        Set-ToolFailure -Result $result -Message "Codex CLI 已安装，但写入配置失败: $($_.Exception.Message)"
    }

    return (Complete-ToolResult -Result $result)
}

function Install-GeminiCli {
    param([string]$ApiKey)

    $result = New-ToolResult -Command "gemini"
    $displayName = "Gemini CLI"

    Write-Step "安装 Gemini CLI"

    $currentCheck = Test-ToolVersionCommand -Command "gemini" -DisplayName $displayName
    $isUpdate = Test-ToolExists "gemini"
    if ($currentCheck.Success) {
        $result.version_before = $currentCheck.Version
        Write-Info "$displayName 已安装: $($currentCheck.Version)，将更新到最新版本。"
    } elseif ($isUpdate) {
        Write-Warn "检测到 $displayName，但当前状态异常，正在重新安装。"
    }

    Write-Info "正在通过 npm 安装 Gemini CLI ..."
    $npmResult = Invoke-NpmCommand -Arguments @("install", "-g", "@google/gemini-cli")
    if ($npmResult.ExitCode -ne 0) {
        Set-ToolFailure -Result $result -Message (Get-NpmFailureMessage -DisplayName $displayName -NpmResult $npmResult -ActiveProcesses @())
        return (Complete-ToolResult -Result $result)
    }

    Refresh-PathEnv
    Resolve-NpmPath
    $result.installed = $true

    $runtimeCheck = Test-ToolVersionCommand -Command "gemini" -DisplayName $displayName
    if (-not $runtimeCheck.Success) {
        Set-ToolFailure -Result $result -Message $runtimeCheck.Message
        return (Complete-ToolResult -Result $result)
    }

    $result.runtime_validated = $true
    $result.version_after = $runtimeCheck.Version

    if ($result.version_before) {
        Write-Success "$displayName 已更新: $($result.version_before) -> $($result.version_after)"
    } else {
        Write-Success "$displayName 安装完成: $($result.version_after)"
    }

    Write-Warn "Gemini CLI 仍要求在用户环境变量中保留 GEMINI_API_KEY。"
    Write-Info "当前版本 Gemini CLI 已支持通过 GOOGLE_GEMINI_BASE_URL 指向 MAX API。"

    Write-Info "正在写入 Gemini CLI 配置 ..."
    try {
        $geminiDir = Join-Path $env:USERPROFILE ".gemini"
        Ensure-Directory $geminiDir

        $settingsPath = Join-Path $geminiDir "settings.json"
        $geminiSettings = Read-JsonConfigOrDefault -Path $settingsPath -Label "Gemini CLI 配置文件"

        $modelSettings = if ($geminiSettings.PSObject.Properties["model"] -and $geminiSettings.model) {
            $geminiSettings.model
        } else {
            [PSCustomObject]@{}
        }
        Ensure-ObjectProperty -Object $modelSettings -Name "name" -Value $Script:GEMINI_MODEL
        Ensure-ObjectProperty -Object $geminiSettings -Name "model" -Value $modelSettings

        $securitySettings = if ($geminiSettings.PSObject.Properties["security"] -and $geminiSettings.security) {
            $geminiSettings.security
        } else {
            [PSCustomObject]@{}
        }
        $authSettings = if ($securitySettings.PSObject.Properties["auth"] -and $securitySettings.auth) {
            $securitySettings.auth
        } else {
            [PSCustomObject]@{}
        }
        Ensure-ObjectProperty -Object $authSettings -Name "selectedType" -Value "gemini-api-key"
        Ensure-ObjectProperty -Object $authSettings -Name "enforcedType" -Value "gemini-api-key"
        Ensure-ObjectProperty -Object $securitySettings -Name "auth" -Value $authSettings
        Ensure-ObjectProperty -Object $geminiSettings -Name "security" -Value $securitySettings

        Write-JsonConfigFile -Path $settingsPath -Object $geminiSettings -Title "Gemini CLI 配置文件"

        Remove-PersistentEnvVarIfMatches -Name "GEMINI_MODEL" -ExpectedValue $Script:GEMINI_MODEL
        Set-PersistentEnvVar -Name "GEMINI_API_KEY" -Value $ApiKey
        Set-PersistentEnvVar -Name "GOOGLE_GEMINI_BASE_URL" -Value $Script:API_BASE_URL
        Show-EnvPreview -Title "Gemini 必需环境变量" -Entries @{
            GEMINI_API_KEY          = $ApiKey
            GOOGLE_GEMINI_BASE_URL  = $Script:API_BASE_URL
        }

        foreach ($warning in (Get-MissingGeminiMcpCommands -Settings $geminiSettings)) {
            Add-ToolWarning -Result $result -Message $warning
        }

        $nodeMajor = Get-NodeMajorVersion
        if ($nodeMajor -ge 24) {
            $nodeRuntime = Ensure-GeminiNode20Runtime
            if (-not $nodeRuntime.Success) {
                Add-ToolWarning -Result $result -Message $nodeRuntime.Message
                Add-ToolWarning -Result $result -Message "当前系统 Node.js $(node --version 2>$null) 仍可能导致 Gemini CLI 在退出时触发断言错误。"
            } else {
                $wrapperInstall = Install-GeminiCmdWrapper -NodePath $nodeRuntime.NodePath
                if (-not $wrapperInstall.Success) {
                    Add-ToolWarning -Result $result -Message $wrapperInstall.Message
                    Add-ToolWarning -Result $result -Message "当前系统 Node.js $(node --version 2>$null) 仍可能导致 Gemini CLI 在退出时触发断言错误。"
                } else {
                    Write-Info "已为 Gemini CLI 配置专用 Node.js 20 启动器，用于规避 Windows + Node.js 24 的退出断言问题。"
                }
            }
        }

        $result.configured = $true
    } catch {
        Set-ToolFailure -Result $result -Message "Gemini CLI 已安装，但写入配置失败: $($_.Exception.Message)"
    }

    return (Complete-ToolResult -Result $result)
}

function Get-ActualCallPrompt {
    return "This is a post-install connectivity check. Do not use tools. What is 17 multiplied by 19? Reply with only the number."
}

function Get-ActualCallExpectedPattern {
    return '\b323\b'
}

function Get-SmokeTestWorkspace {
    param([string]$Tool)

    $root = Join-Path $env:TEMP "maxapi-cli-smoke-tests"
    Ensure-Directory $root

    $workspace = Join-Path $root $Tool
    Ensure-Directory $workspace

    return $workspace
}

function Test-ToolActualCall {
    param([string]$Tool)

    $displayName = Get-ToolDisplayName -Tool $Tool
    $workspace = Get-SmokeTestWorkspace -Tool $Tool
    $prompt = Get-ActualCallPrompt
    $expectedPattern = Get-ActualCallExpectedPattern
    $outputPath = $null

    switch ($Tool) {
        "claude" {
            $arguments = @(
                "-p", $prompt,
                "--output-format", "text",
                "--permission-mode", "plan",
                "--tools", "",
                "--no-session-persistence"
            )
        }
        "codex" {
            $outputPath = Join-Path $workspace "codex-last-message.txt"
            Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
            $arguments = @(
                "exec",
                "--skip-git-repo-check",
                "--ephemeral",
                "--color", "never",
                "-o", $outputPath,
                $prompt
            )
        }
        "gemini" {
            $arguments = @(
                "-p", $prompt,
                "--output-format", "text"
            )
        }
        default {
            return [PSCustomObject]@{
                Success       = $false
                Message       = "未定义 $displayName 的实际调用测试命令。"
                OutputPreview = $null
            }
        }
    }

    $details = Invoke-ToolCommandDetailedWithTimeout -Command $Tool -Arguments $arguments -WorkingDirectory $workspace -TimeoutSeconds 120
    $rawOutput = $details.OutputText

    if ($outputPath -and (Test-Path $outputPath)) {
        try {
            $fileOutput = Read-TextUtf8 -Path $outputPath
            if (-not [string]::IsNullOrWhiteSpace($fileOutput)) {
                $rawOutput = $fileOutput.Trim()
            }
        } catch {}
    }

    $outputPreview = Format-OutputSnippet -Text $rawOutput

    if (-not $details.Found) {
        return [PSCustomObject]@{
            Success       = $false
            Message       = "未找到 $displayName 命令。"
            OutputPreview = $null
        }
    }

    if ($details.TimedOut) {
        return [PSCustomObject]@{
            Success       = $false
            Message       = "$displayName 在 120 秒内未完成实际调用，可能仍在等待登录、权限确认或网络响应。"
            OutputPreview = $outputPreview
        }
    }

    if ($details.ExitCode -ne 0) {
        $message = "$displayName 实际调用失败"
        if ($null -ne $details.ExitCode) {
            $message += "（退出码 $($details.ExitCode)）"
        }
        if ($outputPreview) {
            $message += "。输出摘要: $outputPreview"
        }

        return [PSCustomObject]@{
            Success       = $false
            Message       = $message
            OutputPreview = $outputPreview
        }
    }

    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        return [PSCustomObject]@{
            Success       = $false
            Message       = "$displayName 实际调用已结束，但没有返回可验证的内容。"
            OutputPreview = $null
        }
    }

    if ($rawOutput -notmatch $expectedPattern) {
        $message = "$displayName 实际调用返回内容不符合预期，应包含 323。"
        if ($outputPreview) {
            $message += " 输出摘要: $outputPreview"
        }

        return [PSCustomObject]@{
            Success       = $false
            Message       = $message
            OutputPreview = $outputPreview
        }
    }

    return [PSCustomObject]@{
        Success       = $true
        Message       = "$displayName 实际调用成功。"
        OutputPreview = $outputPreview
    }
}

function Run-ActualCallTests {
    param(
        [string[]]$SelectedTools,
        [hashtable]$Results,
        [object]$ApiPreflightResult
    )

    $testableTools = @($SelectedTools | Where-Object {
        $Results.ContainsKey($_) -and
        $Results[$_].success
    })

    if ($testableTools.Count -eq 0) {
        Write-Info "没有可执行实际调用测试的工具。"
        return
    }

    Write-Step "最终实际调用测试"

    if ($ApiPreflightResult -and $ApiPreflightResult.SkipSmokeTests) {
        Write-Warn "由于安装前的 MAX API 服务预检查未通过，已跳过最终真实调用测试。"
        foreach ($tool in $testableTools) {
            Add-ToolWarning -Result $Results[$tool] -Message "已跳过实际调用测试：$($ApiPreflightResult.Message)"
        }
        return
    }

    Write-Info "将对每个安装成功的工具发起一次极小的真实请求，以验证 API 连通性。"

    foreach ($tool in $testableTools) {
        $result = $Results[$tool]
        $name = Get-ToolDisplayName -Tool $tool

        Write-Info "正在验证 $name 的真实 API 调用 ..."
        $testResult = Test-ToolActualCall -Tool $tool

        $result.smoke_tested = $true
        $result.smoke_test_success = $testResult.Success
        $result.smoke_test_output = $testResult.OutputPreview

        if ($testResult.Success) {
            Write-Success $testResult.Message
            if ($testResult.OutputPreview) {
                Write-Info "返回摘要: $($testResult.OutputPreview)"
            }
            continue
        }

        $result.success = $false
        $result.failure_reason = "实际调用测试失败: $($testResult.Message)"
        Write-Err $result.failure_reason
    }
}

function Show-Summary {
    param(
        [string[]]$SelectedTools,
        [hashtable]$Results,
        [object]$ApiPreflightResult
    )

    Write-Host ""
    Write-Host ""
    Write-Host "  安装结果汇总" -ForegroundColor Magenta
    Write-Host ""

    if ($ApiPreflightResult) {
        $preflightLabel = if ($ApiPreflightResult.Success) { "成功" } else { "警告" }
        $preflightColor = if ($ApiPreflightResult.Success) { "Green" } else { "Yellow" }
        Write-Host "    MAX API 预检查 : " -NoNewline -ForegroundColor White
        Write-Host $preflightLabel -ForegroundColor $preflightColor
        if (-not [string]::IsNullOrWhiteSpace($ApiPreflightResult.RouteName)) {
            Write-Host "      线路: $($ApiPreflightResult.RouteName)" -ForegroundColor DarkGray
        }
        if (-not [string]::IsNullOrWhiteSpace($ApiPreflightResult.BaseUrl)) {
            Write-Host "      地址: $($ApiPreflightResult.BaseUrl)" -ForegroundColor DarkGray
        }
        Write-Host "      结果: $($ApiPreflightResult.Message)" -ForegroundColor DarkGray
        if ($null -ne $ApiPreflightResult.StatusCode) {
            Write-Host "      HTTP 状态: $($ApiPreflightResult.StatusCode)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    foreach ($tool in $SelectedTools) {
        $result = $Results[$tool]
        $name = Get-ToolDisplayName -Tool $tool

        if ($null -eq $result) {
            Write-Host "    $name : 未执行" -ForegroundColor Yellow
            continue
        }

        if ($result.success) {
            $label = if ($result.warnings.Count -gt 0) { "成功（有警告）" } else { "成功" }
            $color = if ($result.warnings.Count -gt 0) { "Yellow" } else { "Green" }
        } elseif ($result.installed -or $result.runtime_validated -or $result.configured) {
            $label = "部分成功"
            $color = "Yellow"
        } else {
            $label = "失败"
            $color = "Red"
        }

        Write-Host "    $name : " -NoNewline -ForegroundColor White
        Write-Host $label -ForegroundColor $color

        if ($result.version_after) {
            $versionText = if ($result.version_before) {
                "$($result.version_before) -> $($result.version_after)"
            } else {
                $result.version_after
            }
            Write-Host "      版本: $versionText" -ForegroundColor DarkGray
        }

        if ($result.smoke_tested) {
            $smokeLabel = if ($result.smoke_test_success) { "成功" } else { "失败" }
            $smokeColor = if ($result.smoke_test_success) { "Green" } else { "Red" }
            Write-Host "      实际调用: $smokeLabel" -ForegroundColor $smokeColor
            if (-not [string]::IsNullOrWhiteSpace($result.smoke_test_output)) {
                Write-Host "      返回摘要: $($result.smoke_test_output)" -ForegroundColor DarkGray
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($result.failure_reason)) {
            Write-Host "      原因: $($result.failure_reason)" -ForegroundColor Red
        }

        foreach ($warning in $result.warnings) {
            Write-Host "      警告: $warning" -ForegroundColor Yellow
        }
    }

    $successfulTools = @($SelectedTools | Where-Object { $Results.ContainsKey($_) -and $Results[$_].success })
    if ($successfulTools.Count -gt 0) {
        Write-Host ""
        Write-Host "  使用方法:" -ForegroundColor Yellow
        Write-Host ""
        foreach ($tool in $successfulTools) {
            Write-Host "    $(Get-ToolDisplayName -Tool $tool):" -ForegroundColor White
            Write-Host "      $(Get-ToolCommandName -Tool $tool)" -ForegroundColor Cyan
            Write-Host ""
        }

        Write-Host "  MAX API 服务: $Script:API_ROUTE_NAME ($Script:API_BASE_URL)" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  已仅对完成安装与基础启动验证的工具禁用 PowerShell .ps1 shim。" -ForegroundColor Gray
        Write-Host "  Claude Code 为确保原生 Windows 二进制完整，固定使用官方 npm 源安装。" -ForegroundColor Gray
        Write-Host "  已对安装成功的工具执行一次真实 API 调用测试。" -ForegroundColor Gray
        Write-Host "  如果命令仍未找到，请关闭并重新打开终端窗口。" -ForegroundColor Yellow
    }

    Write-Host ""
}

function Main {
    $ErrorActionPreference = "Continue"

    try {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
    } catch {}

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding = [System.Text.Encoding]::UTF8
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $OutputEncoding = [System.Text.Encoding]::UTF8
        }
    } catch {}

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Clear-Host
    Write-Banner

    if (-not (Test-Environment)) {
        Write-Err "环境检测失败，安装已终止。"
        return
    }

    $selectedTools = Show-ToolMenu
    Write-Info "已选择: $($selectedTools -join ', ')"

    $apiKey = Read-ApiKey
    $apiPreflightResult = Test-MaxApiReachability -ApiKey $apiKey

    if ($selectedTools -contains "claude") {
        if (-not (Install-GitIfNeeded)) {
            Write-Warn "Git 安装未完成。在 Git 可用前，Claude Code 的部分能力可能受限。"
        }
    }

    if (-not (Install-NodeIfNeeded)) {
        Write-Err "Node.js 安装失败，无法继续安装这些 CLI 工具。"
        Write-Info "请先手动安装 Node.js 20+，然后重新运行本脚本。"
        return
    }

    Set-NpmMirror

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

    $successfulCommands = @()
    foreach ($tool in $selectedTools) {
        if (-not $results.ContainsKey($tool)) { continue }
        if (-not $results[$tool].success) { continue }
        $successfulCommands += (Get-ToolCommandName -Tool $tool)
    }

    Disable-PowerShellShims -Commands $successfulCommands
    Remove-LegacyPowerShellWrapperProfiles
    Repair-PowerShellExecutionPolicy
    Run-ActualCallTests -SelectedTools $selectedTools -Results $results -ApiPreflightResult $apiPreflightResult

    Show-Summary -SelectedTools $selectedTools -Results $results -ApiPreflightResult $apiPreflightResult

    Write-Host ""
    Write-Host "  安装完成。" -ForegroundColor Green
    Write-Host ""
}

Main
