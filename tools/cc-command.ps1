param(
    [string]$MessageText
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\secret-utils.ps1"

$RelayScript = Join-Path $PSScriptRoot "claude-code-relay.ps1"
$RunScript = Join-Path $PSScriptRoot "cc-run.ps1"
$UseScript = Join-Path $PSScriptRoot "cc-use.ps1"
$SessionScript = Join-Path $PSScriptRoot "cc-session.ps1"
$StatusScript = Join-Path $PSScriptRoot "cc-status.ps1"
$LastScript = Join-Path $PSScriptRoot "cc-last.ps1"
$SessionAddScript = Join-Path $PSScriptRoot "cc-session-add.ps1"
$OcSessionScript = Join-Path $PSScriptRoot "oc-session.ps1"
$HealthScript = Join-Path $PSScriptRoot "cc-health.ps1"

$EmptyMessage = "请在 /cc 后输入要转发给 Claude Code 的任务。"
$EmptyUseMessage = "请在 /cc-use 后输入 Claude Code session 名称或 ID。"
$EmptyRunMessage = "请在 /cc-run 后输入要转发给 Claude Code 的任务。"
$UnknownCommandMessage = "请发送 /cc、/cc-run、/cc-session、/cc-status 或 /cc-last 命令。"

function Invoke-ChildScript {
    param([string]$ScriptPath, [string[]]$Arguments)
    $childOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($childOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    Write-Output (Redact-Secrets -Text $text.Trim())
    exit $exitCode
}

function Invoke-Relay {
    param([string[]]$RelayArgs)
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript @RelayArgs 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $summaryLogLine = $output | Where-Object { $_.ToString().StartsWith("Summary Log: ") } | Select-Object -Last 1
    if ($summaryLogLine) {
        $logPath = $summaryLogLine.ToString().Substring("Summary Log: ".Length)
        if (Test-Path -LiteralPath $logPath) {
            $content = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
            Write-Output (Redact-Secrets -Text $content.Trim())
            exit $exitCode
        }
    }
    Write-Output (Redact-Secrets -Text $text.Trim())
    exit $exitCode
}

Set-Location -LiteralPath $Script:ProjectRoot

if (-not [string]::IsNullOrWhiteSpace($MessageText)) {
    $trimmedMessage = $MessageText.Trim()

    if ($trimmedMessage -eq "/cc-status") {
        Invoke-ChildScript -ScriptPath $StatusScript
    }
    elseif ($trimmedMessage -eq "/cc-last") {
        Invoke-ChildScript -ScriptPath $LastScript
    }
    elseif ($trimmedMessage.StartsWith("/cc-session-add")) {
        $rest = $trimmedMessage.Substring(16).Trim()
        if ([string]::IsNullOrWhiteSpace($rest)) {
            Write-Output "Usage: /cc-session-add <Name> <Workspace> [-GitBranch <branch>] [-Role <role>]"
            exit 2
        }
        $parts = $rest -split '\s+'
        $name = $parts[0]
        if ($parts.Count -gt 1) { $workspace = $parts[1] } else { $workspace = "" }
        $argList = @("-Name", $name, "-Workspace", $workspace)
        Invoke-ChildScript -ScriptPath $SessionAddScript -Arguments $argList
    }
    elseif ($trimmedMessage -eq "/cc-session") {
        Invoke-ChildScript -ScriptPath $SessionScript
    }
    elseif ($trimmedMessage.StartsWith("/cc-use")) {
        $sessionText = $trimmedMessage.Substring(7).Trim()
        if ([string]::IsNullOrWhiteSpace($sessionText)) {
            Write-Output $EmptyUseMessage
            exit 0
        }
        Invoke-ChildScript -ScriptPath $UseScript -Arguments @("-Session", $sessionText)
    }
    elseif ($trimmedMessage.StartsWith("/cc-run-big")) {
        $runPromptText = $trimmedMessage.Substring(11).Trim()
        if ([string]::IsNullOrWhiteSpace($runPromptText)) {
            Write-Output "Please enter task description after /cc-run-big"
            exit 0
        }
        Invoke-Relay -RelayArgs @("-PromptText", $runPromptText, "-AllowEdit", "-MaxMinutes", "0")
    }
    elseif ($trimmedMessage.StartsWith("/cc-run")) {
        $runPromptText = $trimmedMessage.Substring(7).Trim()
        if ([string]::IsNullOrWhiteSpace($runPromptText)) {
            Write-Output $EmptyRunMessage
            exit 0
        }
        Invoke-Relay -RelayArgs @("-PromptText", $runPromptText, "-AllowEdit")
    }
    elseif ($trimmedMessage -eq "/oc-session") {
        Invoke-ChildScript -ScriptPath $OcSessionScript
    }
    elseif ($trimmedMessage -eq "/cc-health") {
        Invoke-ChildScript -ScriptPath $HealthScript -Arguments @("-Brief")
    }
    elseif ($trimmedMessage -eq "/cc-help") {
        Write-Output ""
        Write-Output "Feishu-CC Pipeline Commands:"
        Write-Output ""
        Write-Output "  /cc <query>         Read-only query (file listing, git log, status)"
        Write-Output "  /cc-run <task>      Edit mode (20min timeout, relay safety)"
        Write-Output "  /cc-run-big <task>  Edit mode (no timeout, relay safety)"
        Write-Output "  /cc-status          Show current relay task"
        Write-Output "  /cc-last            Show last relay summary"
        Write-Output "  /cc-session         List registered sessions"
        Write-Output "  /cc-session-add     Register new session"
        Write-Output "  /cc-use <name>      Switch active session"
        Write-Output "  /oc-session         OpenClaw runtime status"
        Write-Output "  /cc-health          Pipeline health check"
        Write-Output "  /cc-help            Show this help"
        Write-Output ""
        exit 0
    }
    elseif ($trimmedMessage.StartsWith("/cc")) {
        $promptText = $trimmedMessage.Substring(3).Trim()
        if ([string]::IsNullOrWhiteSpace($promptText)) {
            Write-Output $UnknownCommandMessage
            exit 0
        }
        Invoke-Relay -RelayArgs @("-PromptText", $promptText, "-RawPassThrough")
    }
    else {
        Write-Output $UnknownCommandMessage
        exit 0
    }
}

Write-Output $EmptyMessage
exit 0
