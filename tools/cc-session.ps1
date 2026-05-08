[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"

function Read-Sessions {
    if (-not (Test-Path -LiteralPath $Script:SessionsPath)) { return @() }
    try { return @(Get-Content -LiteralPath $Script:SessionsPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return @() }
}

function Read-Target {
    if (-not (Test-Path -LiteralPath $Script:TargetConfigPath)) { return $null }
    try { return Get-Content -LiteralPath $Script:TargetConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return $null }
}

function Format-Timestamp {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "-" }
    try { $dt = [datetime]::Parse($Raw); return $dt.ToString("MM-dd HH:mm") }
    catch { return $Raw }
}

Set-Location -LiteralPath $Script:ProjectRoot
$sessions = Read-Sessions
$target = Read-Target

Write-Output ""
Write-Output "=============================="
Write-Output " Claude Code Sessions"
Write-Output "=============================="

if ($sessions.Count -eq 0) {
    Write-Output ""
    Write-Output "  (empty) No registered Claude Code sessions"
    Write-Output ""
    Write-Output "Use /cc-use <name> to register a new session"
    exit 0
}

foreach ($entry in $sessions) {
    $name = if ($entry.name) { $entry.name } else { "(unnamed)" }
    $status = if ($entry.status) { $entry.status } else { "idle" }
    $role = if ($entry.role) { $entry.role } else { "-" }
    $branch = if ($entry.gitBranch) { $entry.gitBranch } else { "-" }
    $updated = Format-Timestamp -Raw $entry.updatedAt

    Write-Output ""
    Write-Output "  [$name]"
    Write-Output "    Status: $status"
    Write-Output "    Role: $role"
    Write-Output "    Branch: $branch"
    Write-Output "    Updated: $updated"
}

$selectedName = if ($target -and -not [string]::IsNullOrWhiteSpace($target.defaultSessionName)) {
    $target.defaultSessionName
} else { "(none)" }

Write-Output ""
Write-Output "---"
Write-Output "Current: $selectedName"
Write-Output ""
Write-Output "Switch: /cc-use <name>"
