param(
    [string]$Session
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"

$EmptySessionMessage = "请在 /cc-use 后输入 Claude Code session 名称或 ID。"
$SwitchedPrefix = "已切换 Claude Code 目标会话："
$WorkspaceLabel = "工作区："
$BranchLabel = "分支："

if ([string]::IsNullOrWhiteSpace($Session)) {
    Write-Output $EmptySessionMessage
    exit 2
}

Set-Location -LiteralPath $Script:ProjectRoot
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Script:TargetConfigPath) | Out-Null

function Read-Sessions {
    if (-not (Test-Path -LiteralPath $Script:SessionsPath)) { return @() }
    try { return @(Get-Content -LiteralPath $Script:SessionsPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return @() }
}

$inputValue = $Session.Trim()
$sessions = Read-Sessions
$matched = $null
foreach ($entry in $sessions) {
    if ([string]::Equals($entry.name, $inputValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        $matched = $entry
        break
    }
}

if ($matched) {
    $config = [ordered]@{
        defaultSessionName = $matched.name
        defaultSession = if ($matched.session) { $matched.session } else { "" }
        workspace = $matched.workspace
        gitBranch = if ($matched.gitBranch) { $matched.gitBranch } else { "" }
        mode = "readonly"
        updatedAt = (Get-Date).ToString("o")
    }
} else {
    $config = [ordered]@{
        defaultSessionName = ""
        defaultSession = $inputValue
        workspace = $Script:ProjectRoot
        gitBranch = ""
        mode = "readonly"
        updatedAt = (Get-Date).ToString("o")
    }
}

$config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Script:TargetConfigPath -Encoding UTF8
$display = if ($config.defaultSessionName) { $config.defaultSessionName } elseif ($config.defaultSession) { $config.defaultSession } else { "(unbound)" }
Write-Output "$SwitchedPrefix$display"
Write-Output "$WorkspaceLabel$($config.workspace)"
if (-not [string]::IsNullOrWhiteSpace($config.gitBranch)) { Write-Output "$BranchLabel$($config.gitBranch)" }
