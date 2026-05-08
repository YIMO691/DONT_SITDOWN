param(
    [string]$PromptText
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
$EmptyRunMessage = "请在 /cc-run 后输入要转发给 Claude Code 的任务。"

Set-Location -LiteralPath $Script:ProjectRoot

if ([string]::IsNullOrWhiteSpace($PromptText)) {
    Write-Output $EmptyRunMessage
    exit 0
}

$RelayOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText $PromptText -AllowEdit 2>&1
$ExitCode = $LASTEXITCODE
$RelayText = ($RelayOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
$SummaryLogLine = $RelayOutput | Where-Object { $_.ToString().StartsWith("Summary Log: ") } | Select-Object -Last 1

if ($SummaryLogLine) {
    $SummaryLog = $SummaryLogLine.ToString().Substring("Summary Log: ".Length)
    if (Test-Path -LiteralPath $SummaryLog) {
        $SummaryText = Get-Content -LiteralPath $SummaryLog -Raw -Encoding UTF8
        Write-Output (Redact-Secrets -Text $SummaryText.Trim())
        exit $ExitCode
    }
}

Write-Output (Redact-Secrets -Text $RelayText.Trim())
exit $ExitCode
