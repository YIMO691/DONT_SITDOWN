param(
    [string]$Name,
    [string]$Workspace,
    [string]$GitBranch = "",
    [string]$Role = "",
    [string]$Session = ""
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"

$NeedArgsMessage = "请在 /cc-session-add 后提供 Name 和 Workspace。"
$CreateWorktreeMessage = "请先创建 Git worktree，不要自动创建："
$DuplicateMessage = "会话名称已存在："
$AddedMessage = "已登记 Claude Code 开发分支："
$WorkspaceLimitMessage = "安全限制：workspace 只允许位于 project 或 worktrees 下。"
$DefaultRole = "主线：查看状态、整理文档、轻量修改"

function Ensure-SessionsFile {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Script:SessionsPath) | Out-Null
    if (-not (Test-Path -LiteralPath $Script:SessionsPath)) {
        $default = @([ordered]@{
            name = "main"
            session = ""
            workspace = $Script:ProjectRoot
            gitBranch = "main"
            role = $DefaultRole
            status = "idle"
            updatedAt = ""
        })
        ConvertTo-Json -InputObject $default -Depth 5 | Set-Content -LiteralPath $Script:SessionsPath -Encoding UTF8
    }
}

function Read-Sessions {
    Ensure-SessionsFile
    return @(Get-Content -LiteralPath $Script:SessionsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Save-Sessions {
    param([object[]]$Sessions)
    ConvertTo-Json -InputObject @($Sessions) -Depth 6 | Set-Content -LiteralPath $Script:SessionsPath -Encoding UTF8
}

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-WorkspaceAllowed {
    param([string]$Path)
    $full = Get-FullPath -Path $Path
    $root = Get-FullPath -Path $Script:ProjectRoot
    $worktrees = Get-FullPath -Path $Script:WorktreesRoot
    return ($full -eq $root -or $full.StartsWith($root + "\", [System.StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($worktrees + "\", [System.StringComparison]::OrdinalIgnoreCase))
}

Set-Location -LiteralPath $Script:ProjectRoot

if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Workspace)) {
    Write-Output $NeedArgsMessage
    exit 2
}

if (-not (Test-WorkspaceAllowed -Path $Workspace)) {
    Write-Output $WorkspaceLimitMessage
    exit 2
}

if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) {
    Write-Output "$CreateWorktreeMessage$Workspace"
    exit 2
}

$sessions = Read-Sessions
foreach ($entry in $sessions) {
    if ([string]::Equals($entry.name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Output "$DuplicateMessage$Name"
        exit 2
    }
}

$newEntry = [ordered]@{
    name = $Name.Trim()
    session = $Session.Trim()
    workspace = (Get-FullPath -Path $Workspace)
    gitBranch = $GitBranch.Trim()
    role = $Role.Trim()
    status = "idle"
    updatedAt = (Get-Date).ToString("o")
}

$updated = @($sessions) + [pscustomobject]$newEntry
Save-Sessions -Sessions $updated
Write-Output "$AddedMessage$($newEntry.name)"
