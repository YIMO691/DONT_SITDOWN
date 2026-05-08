[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\secret-utils.ps1"

$NoSummaryMessage = "暂无 Claude Code 执行摘要。"

Set-Location -LiteralPath $Script:ProjectRoot

if (-not (Test-Path -LiteralPath $Script:LogRoot)) {
    Write-Output $NoSummaryMessage
    exit 0
}

$latest = Get-ChildItem -LiteralPath $Script:LogRoot -Filter "*-summary.txt" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latest) {
    Write-Output $NoSummaryMessage
    exit 0
}

$summary = Get-Content -LiteralPath $latest.FullName -Raw -Encoding UTF8
Write-Output (Redact-Secrets -Text $summary.Trim())
