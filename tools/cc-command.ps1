param(
    [string]$MessageText
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

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
$ProjectScript = Join-Path $PSScriptRoot "cc-project.ps1"

$EmptyMessage = "请在 /cc 后输入要转发给 Claude Code 的任务。"
$EmptyUseMessage = "请在 /cc-use 后输入 Claude Code session 名称或 ID。"
$EmptyRunMessage = "请在 /cc-run 后输入要转发给 Claude Code 的任务。"
$UnknownCommandMessage = "未知命令。请发送 /cc-help 查看已注册命令。"

function Normalize-MessageText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    $trimmed = $Text.Trim()
    if ($trimmed -match '^(?:/cc(?:\s|-|$)|/oc-session(?:\s|$))') {
        return $trimmed
    }

    foreach ($line in ($Text -split "`r?`n")) {
        $lineText = $line.Trim()
        if ($lineText -match '^[^:]+:\s*((?:/cc(?:\s|-|$)|/oc-session(?:\s|$)).*)$') {
            return $Matches[1].Trim()
        }
    }

    return $trimmed
}

function Split-CommandArguments {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $matches = [regex]::Matches($Text, '"(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*''|\S+')
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        $value = $match.Value
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $items.Add($value)
    }
    return @($items)
}

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

if (-not [string]::IsNullOrWhiteSpace($MessageText)) {
    $trimmedMessage = Normalize-MessageText -Text $MessageText

    if ($trimmedMessage -eq "/cc-status") {
        Invoke-ChildScript -ScriptPath $StatusScript
    }
    elseif ($trimmedMessage -eq "/cc-last") {
        Invoke-ChildScript -ScriptPath $LastScript
    }
    elseif ($trimmedMessage -match '^/cc-session-add(?:\s|$)') {
        $rest = $trimmedMessage.Substring("/cc-session-add".Length).Trim()
        if ([string]::IsNullOrWhiteSpace($rest)) {
            Write-Output "Usage: /cc-session-add <Name> <Workspace> [-GitBranch <branch>] [-Role <role>]"
            exit 2
        }
        Invoke-ChildScript -ScriptPath $SessionAddScript -Arguments (Split-CommandArguments -Text $rest)
    }
    elseif ($trimmedMessage -eq "/cc-session") {
        Invoke-ChildScript -ScriptPath $SessionScript
    }
    elseif ($trimmedMessage -match '^/cc-use(?:\s|$)') {
        $sessionText = $trimmedMessage.Substring("/cc-use".Length).Trim()
        if ([string]::IsNullOrWhiteSpace($sessionText)) {
            Write-Output $EmptyUseMessage
            exit 0
        }
        Invoke-ChildScript -ScriptPath $UseScript -Arguments @("-Session", $sessionText)
    }
    elseif ($trimmedMessage -match '^/cc-run-big(?:\s|$)') {
        $runPromptText = $trimmedMessage.Substring("/cc-run-big".Length).Trim()
        if ([string]::IsNullOrWhiteSpace($runPromptText)) {
            Write-Output "Please enter task description after /cc-run-big"
            exit 0
        }
        Invoke-Relay -RelayArgs @("-PromptText", $runPromptText, "-AllowEdit", "-MaxMinutes", "0")
    }
    elseif ($trimmedMessage -match '^/cc-run(?:\s|$)') {
        $runPromptText = $trimmedMessage.Substring("/cc-run".Length).Trim()
        if ([string]::IsNullOrWhiteSpace($runPromptText)) {
            Write-Output $EmptyRunMessage
            exit 0
        }
        Invoke-Relay -RelayArgs @("-PromptText", $runPromptText, "-AllowEdit")
    }
    elseif ($trimmedMessage -eq "/oc-session") {
        Invoke-ChildScript -ScriptPath $OcSessionScript
    }
    elseif ($trimmedMessage -eq "/cc-project-list") {
        Invoke-ChildScript -ScriptPath $ProjectScript -Arguments @("-Action", "list")
    }
    elseif ($trimmedMessage -match '^/cc-project-use(?:\s|$)') {
        $projectName = $trimmedMessage.Substring("/cc-project-use".Length).Trim()
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            Write-Output "请在 /cc-project-use 后输入项目名称"
            exit 0
        }
        Invoke-ChildScript -ScriptPath $ProjectScript -Arguments @("-Action", "use", "-Name", $projectName)
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
        Write-Output "  /cc-session-add <name> <path>  Register new session"
        Write-Output "  /cc-use <name>      Switch active session"
        Write-Output "  /cc-project-list    List registered projects"
        Write-Output "  /cc-project-use <name>  Switch active project"
        Write-Output "  /cc-health          Pipeline health check"
        Write-Output "  /oc-session         OpenClaw runtime status"
        Write-Output "  /cc-help            Show this help"
        Write-Output ""
        exit 0
    }
    elseif ($trimmedMessage -match '^/cc(?:\s|$)') {
        $promptText = $trimmedMessage.Substring("/cc".Length).Trim()
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
