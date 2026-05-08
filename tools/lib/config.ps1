$Script:ConfigPath = Join-Path $PSScriptRoot "..\..\config.json"
$Script:ProjectRoot = $null
$Script:WorktreesRoot = $null
$Script:LogRoot = $null
$Script:OpenClawStateDir = $null
$Script:ClaudeCodePath = $null
$Script:SessionsPath = $null
$Script:TargetConfigPath = $null

function Get-ProjectConfig {
    if (-not (Test-Path -LiteralPath $Script:ConfigPath)) {
        throw "config.json not found at $($Script:ConfigPath). Run install.ps1 first or copy config.example.json to config.json."
    }
    try {
        return Get-Content -LiteralPath $Script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Failed to parse config.json: $($_.Exception.Message)"
    }
}

function Initialize-Config {
    $config = Get-ProjectConfig

    $Script:ProjectRoot = $config.projectRoot
    if (-not (Test-Path -LiteralPath $Script:ProjectRoot -PathType Container)) {
        Write-Warning "Project root not found: $($Script:ProjectRoot)"
    }

    $Script:WorktreesRoot = $config.worktreesRoot
    $Script:LogRoot = Join-Path $Script:ProjectRoot $config.logSubPath
    $Script:OpenClawStateDir = $config.openclawStateDir
    $Script:ClaudeCodePath = $config.claudeCodePath

    $Script:SessionsPath = Join-Path $Script:ProjectRoot ".openclaw\cc-sessions.json"
    $Script:TargetConfigPath = Join-Path $Script:ProjectRoot ".openclaw\cc-target.json"
}

Initialize-Config
