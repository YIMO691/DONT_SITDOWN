param(
    [string]$Action,
    [string]$Name
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"

$ProjectRegistryPath = Join-Path $Script:OpenClawStateDir "cc-projects.json"

function Read-ProjectRegistry {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProjectRegistryPath) | Out-Null
    if (-not (Test-Path -LiteralPath $ProjectRegistryPath)) {
        $default = @(
            [ordered]@{
                name = "default"
                workspace = $Script:ProjectRoot
                worktreesRoot = $Script:WorktreesRoot
                active = $true
                description = "默认项目 (来自 config.json)"
            }
        )
        ConvertTo-Json -InputObject @($default) -Depth 4 | Set-Content -LiteralPath $ProjectRegistryPath -Encoding UTF8
    }
    try {
        return @(Get-Content -LiteralPath $ProjectRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return @()
    }
}

function Save-ProjectRegistry {
    param([object[]]$Projects)
    ConvertTo-Json -InputObject @($Projects) -Depth 4 | Set-Content -LiteralPath $ProjectRegistryPath -Encoding UTF8
}

function Get-ActiveProject {
    $registry = Read-ProjectRegistry
    foreach ($entry in $registry) {
        if ($entry.active) { return $entry }
    }
    return $null
}

# ==========================================
# Action: list
# ==========================================
if ($Action -eq "list") {
    $registry = Read-ProjectRegistry
    $active = Get-ActiveProject

    Write-Output ""
    Write-Output "Registered Projects"
    Write-Output "==================="

    if ($registry.Count -eq 0) {
        Write-Output "  (no projects registered)"
        Write-Output ""
        Write-Output "Register projects by editing: $ProjectRegistryPath"
        exit 0
    }

    foreach ($entry in $registry) {
        $marker = if ($entry.active) { ">" } else { " " }
        $desc = if ($entry.description) { "— $($entry.description)" } else { "" }
        Write-Output "  $marker $($entry.name)"
        Write-Output "    workspace: $($entry.workspace) $desc"
    }

    Write-Output ""
    Write-Output "Switch: /cc-project-use <name>"
    exit 0
}

# ==========================================
# Action: use
# ==========================================
if ($Action -eq "use") {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Output "请在 /cc-project-use 后输入项目名称，例如: /cc-project-use dont-sitdown"
        exit 2
    }

    $registry = Read-ProjectRegistry
    $matched = $null
    foreach ($entry in $registry) {
        if ([string]::Equals($entry.name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $matched = $entry
            break
        }
    }

    if (-not $matched) {
        Write-Output "未找到项目: $Name"
        Write-Output ""
        Write-Output "已注册的项目:"
        foreach ($entry in $registry) {
            Write-Output "  - $($entry.name) ($($entry.workspace))"
        }
        Write-Output ""
        Write-Output "请编辑 $ProjectRegistryPath 添加新项目。"
        exit 4
    }

    if (-not (Test-Path -LiteralPath $matched.workspace -PathType Container)) {
        Write-Output "项目 workspace 不存在: $($matched.workspace)"
        exit 4
    }

    # Mark this project as active
    foreach ($entry in $registry) { $entry.active = $false }
    $matched.active = $true
    $matched.updatedAt = (Get-Date).ToString("o")
    Save-ProjectRegistry -Projects $registry

    # Update cc-target.json
    $targetDir = Split-Path -Parent $Script:TargetConfigPath
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    $targetConfig = [ordered]@{
        defaultSessionName = ""
        defaultSession = ""
        workspace = $matched.workspace
        gitBranch = ""
        mode = "readonly"
        updatedAt = (Get-Date).ToString("o")
    }
    $targetConfig | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Script:TargetConfigPath -Encoding UTF8

    Write-Output "已切换项目: $($matched.name)"
    Write-Output "workspace: $($matched.workspace)"
    exit 0
}

# ==========================================
# Fallback
# ==========================================
Write-Output "Usage: /cc-project-list  or  /cc-project-use <name>"
exit 0
