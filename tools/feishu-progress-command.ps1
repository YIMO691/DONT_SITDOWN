$ErrorActionPreference = "Continue"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$mobileStatusScript = Join-Path $PSScriptRoot "mobile-status.ps1"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$status = powershell -ExecutionPolicy Bypass -File $mobileStatusScript

Write-Output "Summarize the project status below as a Chinese Feishu mobile message."
Write-Output "Requirements:"
Write-Output "1. Do not output secrets."
Write-Output "2. Keep the message under 1200 Chinese characters."
Write-Output "3. Use these sections in Chinese: current phase, completed, current issues, recent errors, next steps."
Write-Output "4. If no clear errors are found, explicitly say that no obvious errors were found."
Write-Output ""
Write-Output "===== RAW STATUS START ====="
$status | Select-Object -First 300
Write-Output "===== RAW STATUS END ====="
