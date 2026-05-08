[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"

$RelayScript = Join-Path $PSScriptRoot "claude-code-relay.ps1"

Set-Location -LiteralPath $Script:ProjectRoot

if ($args.Count -eq 0 -or [string]::IsNullOrWhiteSpace($args[0])) {
    Write-Output "Please enter task description after /cc-run-big"
    exit 1
}

$promptText = $args -join " "

$promptDir = $Script:LogRoot
New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
$promptPath = Join-Path $promptDir "bigtask-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$promptText | Set-Content -Path $promptPath -Encoding UTF8

Write-Output "Task submitted to Claude Code (big mode, no timeout, relay safety enabled)"
Write-Output "Prompt backup: $promptPath"
Write-Output ""

& powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText $promptText -AllowEdit -MaxMinutes 0 2>&1
exit $LASTEXITCODE
