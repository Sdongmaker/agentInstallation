#Requires -Version 5.1
<#
.SYNOPSIS
    MAX API Windows installer for Claude Code, Codex CLI, and Gemini CLI.

.DESCRIPTION
    Installs and configures supported AI coding CLIs for Windows users.
    The script is written to stay compatible with Windows PowerShell 5.1.
#>

$Script:API_BASE_URL   = "https://new.28.al"
$Script:NPM_MIRROR     = "https://registry.npmmirror.com"
$Script:GITHUB_PROXY   = "https://kk.eemby.de"
$Script:NODE_MIRROR    = "https://npmmirror.com/mirrors/node"
$Script:NODE_VERSION   = "v20.18.1"
$Script:GIT_VERSION    = "2.47.1"
$Script:GIT_RELEASE    = "v2.47.1.windows.2"

$Script:CLAUDE_MODEL = "claude-opus-4-6"
$Script:CODEX_MODEL  = "gpt-5.4"
$Script:GEMINI_MODEL = "gemini-3.1-pro-preview"

$Script:UTF8NoBom = New-Object System.Text.UTF8Encoding($false)
$Script:NpmExe = $null

function Write-Banner {
    Write-Host ""
    Write-Host "  MAX API Installer" -ForegroundColor Magenta
    Write-Host "  Claude Code / Codex CLI / Gemini CLI" -ForegroundColor Gray
    Write-Host "  Service: $Script:API_BASE_URL" -ForegroundColor Gray
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message" -ForegroundColor Green
    Write-Host ("-" * 60) -ForegroundColor DarkGray
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [ OK ] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [ERR ] $Message" -ForegroundColor Red
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
        Write-Err "npm was not found. Please install Node.js first."
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
            Output   = @("npm executable was not found")
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
        Write-Info "Upgrading $FriendlyName with winget..."
        winget upgrade --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    } else {
        Write-Info "Installing $FriendlyName with winget..."
        winget install --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    }

    if ($LASTEXITCODE -eq 0) {
        Refresh-PathEnv
        Write-Success "$FriendlyName completed successfully."
        return $true
    }

    Write-Warn "winget failed for $FriendlyName. Falling back to the manual download path."
    return $false
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile,
        [switch]$UseProxy
    )

    $downloadUrl = if ($UseProxy) { "$Script:GITHUB_PROXY/$Url" } else { $Url }
    Write-Info "Downloading $downloadUrl"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        Write-Success "Downloaded to $OutFile"
        return $true
    } catch {
        if ($UseProxy) {
            Write-Warn "Proxy download failed. Retrying the original URL."
            try {
                Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
                Write-Success "Downloaded to $OutFile"
                return $true
            } catch {
                Write-Err "Direct download failed: $($_.Exception.Message)"
                return $false
            }
        }

        Write-Err "Download failed: $($_.Exception.Message)"
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
    Write-Info "Set user environment variable $Name"
}

function Remove-PersistentEnvVar {
    param([string]$Name)

    [System.Environment]::SetEnvironmentVariable($Name, $null, "User")
    Remove-Item -Path "Env:\$Name" -ErrorAction SilentlyContinue
    Write-Info "Removed user environment variable $Name"
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
        Write-Warn "Environment variable $Name exists with a different value. Leaving it unchanged."
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
    Write-Info "Backed up existing file to $backupPath"
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
            Write-Warn "$Label is empty. A fresh config will be created."
            return [PSCustomObject]@{}
        }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed) {
            return [PSCustomObject]@{}
        }

        return $parsed
    } catch {
        Write-Warn "$Label could not be parsed. A fresh config will be created after backing up the current file."
        return [PSCustomObject]@{}
    }
}

function Show-TextPreview {
    param(
        [string]$Title,
        [string]$Content,
        [string]$Path
    )

    Write-Warn "Preview below is redacted to avoid printing raw secrets."
    Write-Host "  + $Title" -ForegroundColor DarkGray
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        Write-Host "  Path: $Path" -ForegroundColor DarkGray
    }
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray

    $safeContent = Redact-TextSecrets -Content $Content
    if ([string]::IsNullOrEmpty($safeContent)) {
        Write-Host "  <empty>" -ForegroundColor DarkGray
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
        Write-Warn "Preview file was not found: $Path"
        return
    }

    try {
        $content = Read-TextUtf8 -Path $Path
        Show-TextPreview -Title $Title -Content $content -Path $Path
    } catch {
        Write-Warn "Could not read $Path for preview: $($_.Exception.Message)"
    }
}

function Show-EnvPreview {
    param(
        [string]$Title,
        [hashtable]$Entries
    )

    Write-Warn "Environment preview below is redacted."
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
    Write-Success "Wrote config file: $Path"
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
                Warning    = "Skipped malformed Codex project table header: [$SectionName]"
            }
        }
    } else {
        return [PSCustomObject]@{
            Applicable = $true
            Success    = $false
            Header     = $null
            Warning    = "Skipped malformed Codex project table header: [$SectionName]"
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
# Codex CLI config - generated by MAX API installer
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
        Write-Warn "Could not find $Command.cmd, so no PowerShell shim was disabled."
        return $false
    }

    $cmdPath = $cmdShim.Source
    $ps1Path = [System.IO.Path]::ChangeExtension($cmdPath, ".ps1")
    $disabledPath = "$ps1Path.maxapi-disabled"

    Write-Info "$Command.cmd path: $cmdPath"
    Write-Info "$Command.ps1 path: $ps1Path"

    if (-not (Test-Path $ps1Path)) {
        Write-Success "$Command has no PowerShell shim to disable."
        return $true
    }

    try {
        if (Test-Path $disabledPath) {
            Remove-Item $disabledPath -Force -ErrorAction Stop
        }

        Move-Item -Path $ps1Path -Destination $disabledPath -Force -ErrorAction Stop
        Write-Success "Disabled $Command PowerShell shim: $disabledPath"
        return $true
    } catch {
        Write-Warn "Failed to disable $Command PowerShell shim: $($_.Exception.Message)"
        return $false
    }
}

function Disable-PowerShellShims {
    param([string[]]$Commands)

    $uniqueCommands = @($Commands | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($uniqueCommands.Count -eq 0) {
        Write-Info "No PowerShell shims need to be disabled."
        return
    }

    Write-Step "Disable PowerShell .ps1 shims"
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

    Write-Step "Clean legacy PowerShell profile wrappers"

    foreach ($profilePath in $profilePaths) {
        if (-not (Test-Path $profilePath)) {
            Write-Info "Profile file not found: $profilePath"
            continue
        }

        try {
            $existingContent = Read-TextUtf8 -Path $profilePath
        } catch {
            Write-Warn ("Could not read {0}: {1}" -f $profilePath, $_.Exception.Message)
            continue
        }

        if ([string]::IsNullOrEmpty($existingContent)) {
            Write-Info "Profile file is empty: $profilePath"
            continue
        }

        $match = [regex]::Match($existingContent, $pattern)
        if (-not $match.Success) {
            Write-Info "No legacy wrapper block found in $profilePath"
            continue
        }

        $removedBlock = $match.Value.Trim()
        $updatedContent = $existingContent.Substring(0, $match.Index) + $existingContent.Substring($match.Index + $match.Length)
        $updatedContent = ($updatedContent -replace '^[\r\n]+', '') -replace '[\r\n]+$', ''

        Backup-FileIfExists -Path $profilePath | Out-Null
        if ([string]::IsNullOrWhiteSpace($updatedContent)) {
            Remove-Item $profilePath -Force -ErrorAction SilentlyContinue
            Write-Success "Removed empty legacy profile file: $profilePath"
        } else {
            Write-TextUtf8NoBom -Path $profilePath -Content ($updatedContent + "`n")
            Write-Success "Removed legacy wrapper block from: $profilePath"
        }

        Show-TextPreview -Title "Removed legacy wrapper block" -Content $removedBlock -Path $profilePath
    }
}

function Repair-PowerShellExecutionPolicy {
    Write-Step "Repair PowerShell execution policy"

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        Write-Success "Set CurrentUser execution policy to RemoteSigned."
    } catch {
        Write-Warn "Failed to set CurrentUser execution policy: $($_.Exception.Message)"
    }

    try {
        $diagnostics = Get-ExecutionPolicy -List | ForEach-Object {
            "$($_.Scope): $($_.ExecutionPolicy)"
        }
        Show-TextPreview -Title "PowerShell execution policy diagnostics" -Content ($diagnostics -join "`n") -Path $null
    } catch {
        Write-Warn "Could not read execution policy diagnostics: $($_.Exception.Message)"
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Environment {
    Write-Step "Environment checks"

    if (-not ($env:OS -eq "Windows_NT")) {
        Write-Err "This installer only supports Windows."
        return $false
    }
    Write-Success "Operating system: Windows"

    if (-not [System.Environment]::Is64BitOperatingSystem) {
        Write-Err "This installer only supports 64-bit Windows."
        return $false
    }
    Write-Success "Architecture: x86_64"

    Write-Success "PowerShell version: $($PSVersionTable.PSVersion)"

    if (Test-IsAdmin) {
        Write-Success "Administrator privileges: yes"
    } else {
        Write-Warn "Administrator privileges: no. Admin rights may be required when installing Git or Node.js."
    }

    if (Test-WingetAvailable) {
        Write-Success "winget: available"
    } else {
        Write-Warn "winget: unavailable. The installer will fall back to direct downloads when needed."
    }

    return $true
}

function Show-ToolMenu {
    Write-Step "Choose which tools to install"
    Write-Host ""
    Write-Host "  [1] Claude Code" -ForegroundColor White
    Write-Host "  [2] Codex CLI" -ForegroundColor White
    Write-Host "  [3] Gemini CLI" -ForegroundColor White
    Write-Host ""
    Write-Host "  [A] All tools" -ForegroundColor Yellow
    Write-Host ""

    while ($true) {
        $choice = Read-Host "  Enter your choice (for example: 1,3 or A)"
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

        Write-Warn "Invalid selection. Use 1-3, separated by commas for multi-select, or A for all."
    }
}

function Read-ApiKey {
    Write-Step "Configure API key"
    Write-Host ""
    Write-Host "  Enter your MAX API key from $Script:API_BASE_URL" -ForegroundColor White
    Write-Host "  The input is hidden. That is expected." -ForegroundColor DarkGray
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
            Write-Warn "API key cannot be empty."
            continue
        }

        if ($apiKey.Length -lt 8) {
            Write-Warn "API key looks too short. Please double-check it."
            continue
        }

        return $apiKey
    }
}

function Install-GitIfNeeded {
    Write-Step "Check Git"

    if (Test-CommandExists "git") {
        Write-Success "Git is already installed: $(git --version 2>$null)"
        return $true
    }

    Write-Info "Git is required for Claude Code."
    if (Test-WingetAvailable) {
        if (Install-WithWinget -PackageId "Git.Git" -FriendlyName "Git for Windows") {
            return $true
        }
    }

    if (-not (Test-IsAdmin)) {
        Write-Warn "Installing Git silently requires administrator privileges."
        Write-Info "Please rerun PowerShell as administrator or install Git manually from https://git-scm.com/downloads/win"
        return $false
    }

    $gitUrl = "https://github.com/git-for-windows/git/releases/download/$Script:GIT_RELEASE/Git-$Script:GIT_VERSION.2-64-bit.exe"
    $installerPath = Join-Path $env:TEMP "git-installer.exe"
    if (-not (Download-File -Url $gitUrl -OutFile $installerPath -UseProxy)) {
        Write-Err "Git download failed."
        return $false
    }

    Write-Info "Installing Git silently..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-" -Wait -PassThru
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        Write-Err "Git installer exited with code $($process.ExitCode)."
        return $false
    }

    Refresh-PathEnv
    if (Test-CommandExists "git") {
        Write-Success "Git installed successfully."
        return $true
    }

    Write-Err "Git still was not found after installation."
    return $false
}

function Install-NodeIfNeeded {
    Write-Step "Check Node.js"

    $major = Get-NodeMajorVersion
    if ($major -ge 20) {
        Write-Success "Node.js is already installed: $(node --version) (meets >=20 requirement)"
        return $true
    }

    $isUpgrade = $major -gt 0
    if ($isUpgrade) {
        Write-Warn "Node.js is too old: $(node --version). Node.js 20+ is required."
    } else {
        Write-Info "Node.js is not installed."
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
        Write-Err "Installing Node.js via MSI requires administrator privileges."
        return $false
    }

    $nodeUrl = "$Script:NODE_MIRROR/$Script:NODE_VERSION/node-$Script:NODE_VERSION-x64.msi"
    $msiPath = Join-Path $env:TEMP "node-installer.msi"
    if (-not (Download-File -Url $nodeUrl -OutFile $msiPath)) {
        Write-Err "Node.js download failed."
        return $false
    }

    Write-Info "Installing Node.js silently..."
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$msiPath`"", "/qn", "/norestart" -Wait -PassThru
    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        Write-Err "Node.js installer exited with code $($process.ExitCode)."
        return $false
    }

    Refresh-PathEnv
    if ((Get-NodeMajorVersion) -ge 20) {
        Write-Success "Node.js installed successfully."
        return $true
    }

    Write-Err "Node.js still does not meet the version requirement after installation."
    return $false
}

function Set-NpmMirror {
    Write-Step "Configure npm registry mirror"

    Resolve-NpmPath
    if (-not $Script:NpmExe) {
        Write-Err "npm was not found. Skipping registry configuration."
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
        Write-Success "npm registry is set to $Script:NPM_MIRROR"
    } else {
        $env:npm_config_registry = $Script:NPM_MIRROR
        Write-Warn "npm registry could not be persisted cleanly. The current process will still use $Script:NPM_MIRROR"
    }
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
            Message = "$DisplayName command was not found."
        }
    }

    if ($details.ExitCode -ne 0) {
        $snippet = Format-OutputSnippet -Text $details.OutputText
        $message = "$DisplayName did not start successfully."
        if ($snippet) {
            $message += " Output: $snippet"
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
            Message = "$DisplayName returned no version output."
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
        $message = "$DisplayName update failed because one or more installed files are in use. Close any running $DisplayName sessions and retry."
        $processSummary = Format-ProcessSummary -Processes $ActiveProcesses
        if ($processSummary) {
            $message += " Detected processes: $processSummary."
        }
        return $message
    }

    $snippet = Format-OutputSnippet -Text (($NpmResult.Output | ForEach-Object { "$_" }) -join "`n")
    $message = "$DisplayName npm install failed"
    if ($null -ne $NpmResult.ExitCode) {
        $message += " (exit code $($NpmResult.ExitCode))"
    }
    $message += "."
    if ($snippet) {
        $message += " Output: $snippet"
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
            Message          = "Claude Code native launcher was not written to disk."
        }
    }

    if ($binaryState.StubDetected) {
        return [PSCustomObject]@{
            Success          = $false
            Version          = $versionCheck.Version
            BinaryState      = $binaryState
            NeedsOfficialFix = $true
            Message          = "Claude Code still has only the stub launcher; the native Windows binary is missing."
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
            [void]$missing.Add("Gemini MCP server '$serverName' command was not found: $commandName")
        }
    }

    return @($missing)
}

function Install-ClaudeCode {
    param([string]$ApiKey)

    $result = New-ToolResult -Command "claude"
    $displayName = "Claude Code"

    Write-Step "Install Claude Code"

    $currentCheck = Test-ToolVersionCommand -Command "claude" -DisplayName $displayName
    $isUpdate = Test-ToolExists "claude"
    if ($currentCheck.Success) {
        $result.version_before = $currentCheck.Version
        Write-Info "$displayName is already installed: $($currentCheck.Version). The installer will update it."
    } elseif ($isUpdate) {
        Write-Warn "$displayName was found but is not currently healthy. Reinstalling it."
    }

    $packageDir = Get-GlobalNpmPackageDirectory -Command "claude" -PackageRelativePath "@anthropic-ai\claude-code"
    $activeProcesses = @()
    if ($isUpdate -and $packageDir) {
        $activeProcesses = Get-ProcessesUsingPathPrefix -PathPrefix $packageDir
        if ($activeProcesses.Count -gt 0) {
            Add-ToolWarning -Result $result -Message "Detected running Claude Code processes from the global npm install: $(Format-ProcessSummary -Processes $activeProcesses). The update may fail until they are closed."
        }
    }

    Write-Info "Installing Claude Code via npm..."
    $npmResult = Invoke-NpmCommand -Arguments @("install", "-g", "@anthropic-ai/claude-code")
    if ($npmResult.ExitCode -ne 0) {
        Set-ToolFailure -Result $result -Message (Get-NpmFailureMessage -DisplayName $displayName -NpmResult $npmResult -ActiveProcesses $activeProcesses)
        return (Complete-ToolResult -Result $result)
    }

    Refresh-PathEnv
    Resolve-NpmPath
    $result.installed = $true

    $runtimeCheck = Test-ClaudeRuntime
    if ($runtimeCheck.NeedsOfficialFix) {
        Add-ToolWarning -Result $result -Message "Claude Code native binary was not materialized from the mirror install. Retrying once against the official npm registry."
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
        Write-Success "$displayName updated: $($result.version_before) -> $($result.version_after)"
    } else {
        Write-Success "$displayName installed: $($result.version_after)"
    }

    Write-Info "Writing Claude Code configuration..."
    try {
        $claudeDir = Join-Path $env:USERPROFILE ".claude"
        Ensure-Directory $claudeDir

        $configPath = Join-Path $claudeDir "settings.json"
        $claudeSettings = Read-JsonConfigOrDefault -Path $configPath -Label "Claude Code settings.json"
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

        Write-JsonConfigFile -Path $configPath -Object $claudeSettings -Title "Claude Code config"

        Remove-PersistentEnvVarIfMatches -Name "ANTHROPIC_MODEL" -ExpectedValue $Script:CLAUDE_MODEL
        Remove-PersistentEnvVarIfMatches -Name "ANTHROPIC_API_KEY" -ExpectedValue $ApiKey
        Remove-PersistentEnvVarIfMatches -Name "ANTHROPIC_BASE_URL" -ExpectedValue $Script:API_BASE_URL
        Remove-PersistentEnvVarIfMatches -Name "ANTHROPIC_AUTH_TOKEN" -ExpectedValue $ApiKey

        $result.configured = $true
    } catch {
        Set-ToolFailure -Result $result -Message "Claude Code installed, but writing config failed: $($_.Exception.Message)"
    }

    return (Complete-ToolResult -Result $result)
}

function Install-CodexCli {
    param([string]$ApiKey)

    $result = New-ToolResult -Command "codex"
    $displayName = "Codex CLI"

    Write-Step "Install Codex CLI"

    $currentCheck = Test-ToolVersionCommand -Command "codex" -DisplayName $displayName
    $isUpdate = Test-ToolExists "codex"
    if ($currentCheck.Success) {
        $result.version_before = $currentCheck.Version
        Write-Info "$displayName is already installed: $($currentCheck.Version). The installer will update it."
    } elseif ($isUpdate) {
        Write-Warn "$displayName was found but is not currently healthy. Reinstalling it."
    }

    $packageDir = Get-GlobalNpmPackageDirectory -Command "codex" -PackageRelativePath "@openai\codex"
    $activeProcesses = @()
    if ($isUpdate -and $packageDir) {
        $activeProcesses = Get-ProcessesUsingPathPrefix -PathPrefix $packageDir
        if ($activeProcesses.Count -gt 0) {
            Add-ToolWarning -Result $result -Message "Detected running Codex CLI processes from the global npm install: $(Format-ProcessSummary -Processes $activeProcesses). The update may fail until they are closed."
        }
    }

    Write-Info "Installing Codex CLI via npm..."
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
        Write-Success "$displayName updated: $($result.version_before) -> $($result.version_after)"
    } else {
        Write-Success "$displayName installed: $($result.version_after)"
    }

    Write-Info "Writing Codex CLI configuration..."
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
        Write-Success "Wrote Codex CLI config: $configPath"
        Show-FilePreview -Path $configPath -Title "Codex CLI config"

        Remove-PersistentEnvVarIfMatches -Name "OPENAI_API_KEY" -ExpectedValue $ApiKey
        $result.configured = $true
    } catch {
        Set-ToolFailure -Result $result -Message "Codex CLI installed, but writing config failed: $($_.Exception.Message)"
    }

    return (Complete-ToolResult -Result $result)
}

function Install-GeminiCli {
    param([string]$ApiKey)

    $result = New-ToolResult -Command "gemini"
    $displayName = "Gemini CLI"

    Write-Step "Install Gemini CLI"

    $currentCheck = Test-ToolVersionCommand -Command "gemini" -DisplayName $displayName
    $isUpdate = Test-ToolExists "gemini"
    if ($currentCheck.Success) {
        $result.version_before = $currentCheck.Version
        Write-Info "$displayName is already installed: $($currentCheck.Version). The installer will update it."
    } elseif ($isUpdate) {
        Write-Warn "$displayName was found but is not currently healthy. Reinstalling it."
    }

    Write-Info "Installing Gemini CLI via npm..."
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
        Write-Success "$displayName updated: $($result.version_before) -> $($result.version_after)"
    } else {
        Write-Success "$displayName installed: $($result.version_after)"
    }

    Write-Warn "Gemini CLI still requires GEMINI_API_KEY in the user environment."
    Write-Warn "This installer does not write GOOGLE_GEMINI_BASE_URL because current Gemini CLI releases do not expose an official custom base URL setting."

    Write-Info "Writing Gemini CLI configuration..."
    try {
        $geminiDir = Join-Path $env:USERPROFILE ".gemini"
        Ensure-Directory $geminiDir

        $settingsPath = Join-Path $geminiDir "settings.json"
        $geminiSettings = Read-JsonConfigOrDefault -Path $settingsPath -Label "Gemini CLI settings.json"

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

        Write-JsonConfigFile -Path $settingsPath -Object $geminiSettings -Title "Gemini CLI config"

        Remove-PersistentEnvVarIfMatches -Name "GOOGLE_GEMINI_BASE_URL" -ExpectedValue $Script:API_BASE_URL
        Remove-PersistentEnvVarIfMatches -Name "GEMINI_MODEL" -ExpectedValue $Script:GEMINI_MODEL
        Set-PersistentEnvVar -Name "GEMINI_API_KEY" -Value $ApiKey
        Show-EnvPreview -Title "Gemini required environment variables" -Entries @{ GEMINI_API_KEY = $ApiKey }

        foreach ($warning in (Get-MissingGeminiMcpCommands -Settings $geminiSettings)) {
            Add-ToolWarning -Result $result -Message $warning
        }

        $result.configured = $true
    } catch {
        Set-ToolFailure -Result $result -Message "Gemini CLI installed, but writing config failed: $($_.Exception.Message)"
    }

    return (Complete-ToolResult -Result $result)
}

function Show-Summary {
    param(
        [string[]]$SelectedTools,
        [hashtable]$Results
    )

    Write-Host ""
    Write-Host ""
    Write-Host "  Installation Summary" -ForegroundColor Magenta
    Write-Host ""

    foreach ($tool in $SelectedTools) {
        $result = $Results[$tool]
        $name = Get-ToolDisplayName -Tool $tool

        if ($null -eq $result) {
            Write-Host "    $name : not run" -ForegroundColor Yellow
            continue
        }

        if ($result.success) {
            $label = if ($result.warnings.Count -gt 0) { "success with warnings" } else { "success" }
            $color = if ($result.warnings.Count -gt 0) { "Yellow" } else { "Green" }
        } elseif ($result.installed -or $result.runtime_validated -or $result.configured) {
            $label = "partial"
            $color = "Yellow"
        } else {
            $label = "failed"
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
            Write-Host "      version: $versionText" -ForegroundColor DarkGray
        }

        if (-not [string]::IsNullOrWhiteSpace($result.failure_reason)) {
            Write-Host "      reason: $($result.failure_reason)" -ForegroundColor Red
        }

        foreach ($warning in $result.warnings) {
            Write-Host "      warning: $warning" -ForegroundColor Yellow
        }
    }

    $successfulTools = @($SelectedTools | Where-Object { $Results.ContainsKey($_) -and $Results[$_].success })
    if ($successfulTools.Count -gt 0) {
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor Yellow
        Write-Host ""
        foreach ($tool in $successfulTools) {
            Write-Host "    $(Get-ToolDisplayName -Tool $tool):" -ForegroundColor White
            Write-Host "      $(Get-ToolCommandName -Tool $tool)" -ForegroundColor Cyan
            Write-Host ""
        }

        Write-Host "  MAX API service: $Script:API_BASE_URL" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  PowerShell .ps1 shims were disabled only for tools that fully passed install and runtime validation." -ForegroundColor Gray
        Write-Host "  Reopen the terminal window if a command still is not found." -ForegroundColor Yellow
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
        Write-Err "Environment checks failed. Installation stopped."
        return
    }

    $selectedTools = Show-ToolMenu
    Write-Info "Selected tools: $($selectedTools -join ', ')"

    $apiKey = Read-ApiKey

    if ($selectedTools -contains "claude") {
        if (-not (Install-GitIfNeeded)) {
            Write-Warn "Git installation did not complete. Claude Code may remain limited until Git is available."
        }
    }

    if (-not (Install-NodeIfNeeded)) {
        Write-Err "Node.js installation failed, so the CLI tools cannot be installed."
        Write-Info "Install Node.js 20+ manually and rerun this script."
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

    Show-Summary -SelectedTools $selectedTools -Results $results

    Write-Host ""
    Write-Host "  Installation finished." -ForegroundColor Green
    Write-Host ""
}

Main
