param(
    [Parameter(Mandatory = $true)]
    [string]$PromptText,

    [string]$Session,

    [switch]$RawPassThrough,

    [switch]$Readonly,

    [switch]$AllowEdit,

    [int]$MaxMinutes = 20
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\secret-utils.ps1"

$SummaryScript = Join-Path $PSScriptRoot "claude-code-summary.ps1"
$CurrentTaskPath = Join-Path $Script:LogRoot "current-task.json"
$SectionDone = "完成内容"
$SectionIssues = "发现的问题"
$SectionNext = "下一步建议"
$FinalSummaryLabel = "Claude Code 最终摘要："
$RunningTaskMessage = "当前已有 Claude Code relay 任务正在运行，请先查看 /cc-status。"
$ChangeSummaryLabel = "变更文件摘要："
$AddedLabel = "新增文件"
$ModifiedLabel = "修改文件"
$DeletedLabel = "删除文件"
$NoneLabel = "无"
$DeleteWarningLabel = "警告：检测到删除文件，请人工确认。"
$WorkspaceLimitMessage = "安全限制：workspace 只允许位于 project 或 worktrees 下。"

function Ensure-TargetConfig {
    $configDir = Split-Path -Parent $Script:TargetConfigPath
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null

    if (-not (Test-Path -LiteralPath $Script:TargetConfigPath)) {
        $defaultConfig = [ordered]@{
            defaultSessionName = ""
            defaultSession = ""
            workspace = $Script:ProjectRoot
            gitBranch = ""
            mode = "readonly"
            updatedAt = ""
        }
        $defaultConfig | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Script:TargetConfigPath -Encoding UTF8
    }
}

function Read-TargetConfig {
    Ensure-TargetConfig
    try {
        return Get-Content -LiteralPath $Script:TargetConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            defaultSessionName = ""
            defaultSession = ""
            workspace = $Script:ProjectRoot
            gitBranch = ""
            mode = "readonly"
            updatedAt = ""
        }
    }
}

function Get-FullPathSafe {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-PathInsideRoot {
    param([string]$Path, [string]$Root)
    $full = Get-FullPathSafe -Path $Path
    $rootFull = Get-FullPathSafe -Path $Root
    return ($full -eq $rootFull -or $full.StartsWith($rootFull + "\", [System.StringComparison]::OrdinalIgnoreCase))
}

function Resolve-RelayWorkspace {
    param([object]$TargetConfig)
    $candidate = $Script:ProjectRoot
    if ($TargetConfig -and -not [string]::IsNullOrWhiteSpace($TargetConfig.workspace)) {
        $candidate = [string]$TargetConfig.workspace
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "Workspace not found: $candidate"
    }
    $resolved = (Resolve-Path -LiteralPath $candidate).ProviderPath
    $allowed = (Test-PathInsideRoot -Path $resolved -Root $Script:ProjectRoot) -or (Test-PathInsideRoot -Path $resolved -Root $Script:WorktreesRoot)
    if (-not $allowed) {
        throw $WorkspaceLimitMessage
    }
    return (Get-FullPathSafe -Path $resolved)
}

function Write-CurrentTask {
    param([hashtable]$Task)
    $ordered = [ordered]@{}
    foreach ($key in $Task.Keys) { $ordered[$key] = $Task[$key] }
    $ordered | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $CurrentTaskPath -Encoding UTF8
}

function Read-CurrentTask {
    if (-not (Test-Path -LiteralPath $CurrentTaskPath)) { return $null }
    try { return Get-Content -LiteralPath $CurrentTaskPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return $null }
}

function Lock-CurrentTask {
    try {
        $Script:_TaskLockStream = [System.IO.FileStream]::new(
            $CurrentTaskPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        return $true
    } catch {
        return $false
    }
}

function Unlock-CurrentTask {
    if ($Script:_TaskLockStream) {
        try { $Script:_TaskLockStream.Dispose() } catch {}
        $Script:_TaskLockStream = $null
    }
}

function Get-GitStatusSnapshot {
    $records = @{}
    $lines = @()
    try { $lines = git status --short 2>$null } catch { $lines = @() }
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
        $status = $line.Substring(0, 2)
        $pathText = $line.Substring(3).Trim()
        if ($pathText.Contains(" -> ")) { $pathText = ($pathText -split " -> ")[-1].Trim() }
        $fullPath = Join-Path $ProjectRoot $pathText
        $hash = ""
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            try { $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash } catch { $hash = "" }
        }
        $records[$pathText] = [pscustomobject]@{ path = $pathText; status = $status; hash = $hash; line = $line }
    }
    return $records
}

function Compare-GitStatusSnapshots {
    param([hashtable]$Before, [hashtable]$After)
    $added = New-Object System.Collections.Generic.List[string]
    $modified = New-Object System.Collections.Generic.List[string]
    $deleted = New-Object System.Collections.Generic.List[string]
    foreach ($path in $After.Keys) {
        $afterRecord = $After[$path]
        if ($afterRecord.status.Contains("D")) {
            if (-not $Before.ContainsKey($path) -or -not $Before[$path].status.Contains("D")) { $deleted.Add($path) }
        } elseif (-not $Before.ContainsKey($path)) {
            $added.Add($path)
        } else {
            $beforeRecord = $Before[$path]
            if ($beforeRecord.hash -ne $afterRecord.hash -or $beforeRecord.status -ne $afterRecord.status) { $modified.Add($path) }
        }
    }
    return [ordered]@{ added = @($added); modified = @($modified); deleted = @($deleted) }
}

function Format-FileList {
    param([string[]]$Items)
    if (-not $Items -or $Items.Count -eq 0) { return $NoneLabel }
    return ($Items | Sort-Object | ForEach-Object { "- $_" }) -join [Environment]::NewLine
}

function Format-ChangeSummary {
    param([hashtable]$ChangedFiles)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("")
    $lines.Add($ChangeSummaryLabel)
    $lines.Add("${AddedLabel}:")
    $lines.Add((Format-FileList -Items $ChangedFiles["added"]))
    $lines.Add("${ModifiedLabel}:")
    $lines.Add((Format-FileList -Items $ChangedFiles["modified"]))
    $lines.Add("${DeletedLabel}:")
    $lines.Add((Format-FileList -Items $ChangedFiles["deleted"]))
    if ($ChangedFiles["deleted"] -and $ChangedFiles["deleted"].Count -gt 0) { $lines.Add($DeleteWarningLabel) }
    return ($lines -join [Environment]::NewLine)
}

# === Parameter validation ===
if ([string]::IsNullOrWhiteSpace($PromptText)) { Write-Error "PromptText cannot be empty."; exit 2 }
if ($AllowEdit -and $Readonly) { Write-Error "AllowEdit and Readonly cannot be used together."; exit 2 }
if ($AllowEdit -and $RawPassThrough) { Write-Error "RawPassThrough is only allowed in readonly mode."; exit 2 }
if ($MaxMinutes -lt 0) { Write-Error "MaxMinutes cannot be negative."; exit 2 }

New-Item -ItemType Directory -Force -Path $Script:LogRoot | Out-Null
Set-Location -LiteralPath $Script:ProjectRoot
Ensure-TargetConfig

if (-not (Lock-CurrentTask)) {
    Write-Output $RunningTaskMessage
    exit 4
}
$ExistingTask = Read-CurrentTask
if ($ExistingTask -and $ExistingTask.status -eq "running") {
    Unlock-CurrentTask
    Write-Output $RunningTaskMessage
    exit 4
}

$RunId = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$PromptPath = Join-Path $Script:LogRoot "$RunId-prompt.txt"
$OutputPath = Join-Path $Script:LogRoot "$RunId-output.txt"
$MetaPath = Join-Path $Script:LogRoot "$RunId-meta.json"
$SummaryPath = Join-Path $Script:LogRoot "$RunId-summary.txt"
$TargetConfig = Read-TargetConfig
$ProjectRoot = Resolve-RelayWorkspace -TargetConfig $TargetConfig
$EffectiveSessionName = if ($TargetConfig -and -not [string]::IsNullOrWhiteSpace($TargetConfig.defaultSessionName)) { [string]$TargetConfig.defaultSessionName } else { "" }
$EffectiveGitBranch = if ($TargetConfig -and -not [string]::IsNullOrWhiteSpace($TargetConfig.gitBranch)) { [string]$TargetConfig.gitBranch } else { "" }
$EffectiveSession = if (-not [string]::IsNullOrWhiteSpace($Session)) { $Session } elseif ($TargetConfig -and -not [string]::IsNullOrWhiteSpace($TargetConfig.defaultSession)) { [string]$TargetConfig.defaultSession } else { "" }
$IsReadonly = -not $AllowEdit
$ModeName = if ($IsReadonly) { "readonly" } else { "allow-edit" }
Set-Location -LiteralPath $ProjectRoot

Set-Content -LiteralPath $PromptPath -Value $PromptText -Encoding UTF8

$WrappedTask = if ($AllowEdit) {
@"
You are executing a remote Feishu task inside $ProjectRoot.

User original task:
<USER_PROMPT>
$PromptText
</USER_PROMPT>

Work mode: editing project files is allowed, but only within strict safety boundaries.

Allowed:
- Modify normal source files, documentation, and configuration files inside $ProjectRoot.
- Run read-only inspection commands.
- Run necessary local test commands when they are safe.
- Modify Unity project files when directly relevant to the task.
- Update PROGRESS.md, TODO.md, and AI_DEV_LOG.md.

Forbidden:
- Do not run git push.
- Do not delete the project directory.
- Do not run Remove-Item -Recurse, del /s, rmdir /s, rm -rf, or equivalent recursive delete commands.
- Do not modify, output, save, or expose any API Key, Token, App Secret, password, or credential.
- Do not modify OpenClaw, Claude Code, or DeepSeek secret configuration.
- Do not write secrets into README, blog posts, logs, Git, or documentation.
- Do not install unknown global tools.
- Do not change Windows system-level settings.
- Do not create git commits unless the user explicitly says commit is allowed.

Execution requirements:
1. Read the project status first.
2. Make a short plan.
3. Only change files directly related to the user's task.
4. After editing, list the files changed.
5. Run safe tests if possible; if not possible, explain why.
6. End with these sections:
   - Completed work
   - Modified files
   - Verification result
   - Remaining issues
   - Next steps
"@
} elseif ($RawPassThrough) {
    $PromptText
} else {
@"
User original instruction:
$PromptText

Current working directory:
$ProjectRoot

Mode and safety rules:
- Read-only mode.
- Do not modify, create, move, rename, or delete files.
- Do not commit code.
- Do not run git push.
- Only inspect files, check Git status/log, and run .\tools\mobile-status.ps1 if useful.
- Do not output secrets. Redact any secret-looking value as [REDACTED_SECRET].
- Keep the answer concise and suitable for relay back to Feishu.

At the end, output these sections:
1. $SectionDone
2. $SectionIssues
3. $SectionNext
"@
}

$AllowedTools = if ($IsReadonly) {
    if ($RawPassThrough) {
        "Read,Glob,Grep,Bash(git status:*),Bash(git log:*)"
    } else {
        "Read,Glob,Grep,Bash(git status:*),Bash(git log:*),Bash(powershell -ExecutionPolicy Bypass -File .\tools\mobile-status.ps1:*)"
    }
} else {
    "Read,Glob,Grep,Edit,MultiEdit,Write,Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\*:*)"
}
$DisallowedTools = if ($AllowEdit) {
    "Bash(git push:*),Bash(Remove-Item:*),Bash(del:*),Bash(rmdir:*),Bash(rm:*),Bash(cmd /c del:*),Bash(cmd /c rmdir:*)"
} else { "" }

$StartedAt = Get-Date
$ExitCode = 0
$RawOutput = ""
$GitStatusBefore = Get-GitStatusSnapshot
$TaskBase = @{
    status = "running"; mode = $ModeName; runId = $RunId
    sessionName = $EffectiveSessionName; session = $EffectiveSession
    workspace = $ProjectRoot; gitBranch = $EffectiveGitBranch
    prompt = (Redact-Secrets -Text $PromptText)
    startedAt = $StartedAt.ToString("o"); outputLog = $OutputPath; summaryLog = ""
}
Write-CurrentTask -Task $TaskBase

try {
    $MaxRetries = 2
    $RetryDelay = 10
    for ($Attempt = 0; $Attempt -le $MaxRetries; $Attempt++) {
        try {
            if ($Attempt -gt 0) {
                Write-Output "Claude Code retry $Attempt/$MaxRetries after $RetryDelay seconds..."
                Start-Sleep -Seconds $RetryDelay
            }

            $ClaudeCommand = Get-Command "claude" -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($EffectiveSession)) {
                $ClaudeArgs = @("-p", $WrappedTask, "--output-format", "text", "--allowedTools", $AllowedTools)
            } else {
                $ClaudeArgs = @("-p", "--resume", $EffectiveSession, $WrappedTask, "--output-format", "text", "--allowedTools", $AllowedTools)
            }
            if (-not [string]::IsNullOrWhiteSpace($DisallowedTools)) { $ClaudeArgs += @("--disallowedTools", $DisallowedTools) }

            $TimeoutSeconds = $MaxMinutes * 60
            $ClaudeJob = Start-Job -ScriptBlock {
                param([string]$CommandPath, [string[]]$CommandArgs, [string]$WorkingDirectory)
                [Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
                [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
                $OutputEncoding = [System.Text.UTF8Encoding]::new()
                $env:LANG = "zh_CN.UTF-8"; $env:LC_ALL = "zh_CN.UTF-8"
                Set-Location -LiteralPath $WorkingDirectory
                $jobOutput = & $CommandPath @CommandArgs 2>&1
                $jobExitCode = $LASTEXITCODE
                if ($null -eq $jobExitCode) { $jobExitCode = 0 }
                [pscustomobject]@{ exitCode = $jobExitCode; output = (($jobOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine) }
            } -ArgumentList $ClaudeCommand.Source, $ClaudeArgs, $ProjectRoot

            if ($MaxMinutes -eq 0) {
                $CompletedJob = Wait-Job -Job $ClaudeJob
            } else {
                $CompletedJob = Wait-Job -Job $ClaudeJob -Timeout $TimeoutSeconds
            }
            if ($CompletedJob) {
                $JobResult = Receive-Job -Job $ClaudeJob
                $ExitCode = [int]$JobResult.exitCode
                $RawOutput = [string]$JobResult.output
            } else {
                Stop-Job -Job $ClaudeJob | Out-Null
                $ExitCode = 124
                $RawOutput = "Claude Code invocation timed out after $MaxMinutes minute(s)."
            }
            Remove-Job -Job $ClaudeJob -Force | Out-Null

            # Success: exit code 0 or non-retryable failure, break loop
            break
        } catch {
            if ($Attempt -lt $MaxRetries -and $_.Exception.Message -match "network|timeout|500|503|rate.?limit|unavailable") {
                $LastError = $_.Exception.Message
                continue
            }
            $ExitCode = 127
            $RawOutput = "Claude Code invocation failed: $($_.Exception.Message)"
            break
        }
    }

    $GitStatusAfter = Get-GitStatusSnapshot
    $ChangedFiles = Compare-GitStatusSnapshots -Before $GitStatusBefore -After $GitStatusAfter

    $SafeOutput = Redact-Secrets -Text $RawOutput
    Set-Content -LiteralPath $OutputPath -Value $SafeOutput -Encoding UTF8

    $EndedAt = Get-Date
    $Meta = [ordered]@{
        runId = $RunId; projectRoot = $ProjectRoot
        promptPath = $PromptPath; outputPath = $OutputPath; summaryPath = $SummaryPath
        startedAt = $StartedAt.ToString("o"); endedAt = $EndedAt.ToString("o")
        exitCode = $ExitCode; mode = $ModeName
        requestedSession = $Session; sessionName = $EffectiveSessionName; session = $EffectiveSession
        workspace = $ProjectRoot; gitBranch = $EffectiveGitBranch
        rawPassThrough = [bool]$RawPassThrough
        allowedTools = $AllowedTools; disallowedTools = $DisallowedTools
        maxMinutes = $MaxMinutes; changedFiles = $ChangedFiles
    }
    $Meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $MetaPath -Encoding UTF8

    if (Test-Path -LiteralPath $SummaryScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $SummaryScript -OutputPath $OutputPath -MetaPath $MetaPath -SummaryPath $SummaryPath | Out-Null
    } else {
        Set-Content -LiteralPath $SummaryPath -Value "Claude Code summary script not found: $SummaryScript" -Encoding UTF8
    }

    $FinalSummary = Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8
    if ($AllowEdit) {
        $ChangeSummary = Format-ChangeSummary -ChangedFiles $ChangedFiles
        $FinalSummary = ($FinalSummary.Trim() + [Environment]::NewLine + $ChangeSummary).Trim()
        Set-Content -LiteralPath $SummaryPath -Value $FinalSummary -Encoding UTF8
    }

    $TaskCompleted = @{
        status = if ($ExitCode -eq 0) { "completed" } else { "failed" }
        mode = $ModeName; runId = $RunId; sessionName = $EffectiveSessionName; session = $EffectiveSession
        workspace = $ProjectRoot; gitBranch = $EffectiveGitBranch
        prompt = (Redact-Secrets -Text $PromptText)
        startedAt = $StartedAt.ToString("o"); outputLog = $OutputPath; summaryLog = $SummaryPath
        exitCode = $ExitCode; completedAt = $EndedAt.ToString("o"); changedFiles = $ChangedFiles
    }
    if ($ExitCode -ne 0) {
        $ErrorText = if ([string]::IsNullOrWhiteSpace($SafeOutput)) { "Claude Code failed." } else { $SafeOutput.Trim() }
        $TaskCompleted["error"] = (Redact-Secrets -Text $ErrorText)
    }
    Write-CurrentTask -Task $TaskCompleted

    Write-Output "Claude Code Relay Run: $RunId"
    Write-Output "Prompt Log: $PromptPath"
    Write-Output "Output Log: $OutputPath"
    Write-Output "Meta Log: $MetaPath"
    Write-Output "Summary Log: $SummaryPath"
    Write-Output ""
    Write-Output $FinalSummaryLabel
    Write-Output $FinalSummary
} finally {
    Unlock-CurrentTask
}

# 清理 30 天前的旧日志（排除 current-task.json）
$CutoffDate = (Get-Date).AddDays(-30)
Get-ChildItem -LiteralPath $Script:LogRoot -File |
    Where-Object { $_.LastWriteTime -lt $CutoffDate -and $_.Name -ne "current-task.json" } |
    Remove-Item -Force -ErrorAction SilentlyContinue

exit $ExitCode
