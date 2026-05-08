[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Continue"

Write-Output ""
Write-Output "============================================"
Write-Output " Feishu-CC Pipeline - Installation Wizard"
Write-Output "============================================"
Write-Output ""
Write-Output "This wizard will configure the Feishu -> OpenClaw -> Claude Code"
Write-Output "remote command pipeline for your project."
Write-Output ""

# === Step 1: Prerequisite check ===
Write-Output "[Step 1/5] Checking prerequisites..."
Write-Output ""

$psVersion = $PSVersionTable.PSVersion
Write-Output "  PowerShell: $psVersion"
if ($psVersion.Major -lt 5) {
    Write-Output "  ERROR: PowerShell 5.1 or later is required."
    exit 1
}

$gitOk = $false
try { git --version 2>$null | Out-Null; $gitOk = $true } catch { }
if ($gitOk) { Write-Output "  Git: OK" } else { Write-Output "  Git: NOT FOUND (optional for relay)" }

$claudeOk = $false
try { claude --version 2>$null | Out-Null; $claudeOk = $true } catch { }
if ($claudeOk) { Write-Output "  Claude Code CLI: OK" } else { Write-Output "  Claude Code CLI: NOT FOUND (required for relay)" }

Write-Output ""

# === Step 2: Project root ===
Write-Output "[Step 2/5] Project workspace path"
Write-Output ""
Write-Output "  Enter the full path to your project directory."
Write-Output "  This is where Claude Code will read/write files."
Write-Output "  Example: F:\MyProject"
Write-Output ""
$projectRoot = Read-Host "  Project path"
if ([string]::IsNullOrWhiteSpace($projectRoot)) {
    Write-Output "  ERROR: Project path cannot be empty."
    exit 1
}
$projectRoot = [System.IO.Path]::GetFullPath($projectRoot.Trim()).TrimEnd('\')
Write-Output ""
Write-Output "  Project: $projectRoot"

# === Step 3: Worktrees root ===
Write-Output ""
Write-Output "[Step 3/5] Worktrees path (optional)"
Write-Output ""
Write-Output "  Enter the path for Git worktrees, or press Enter to use default."
$defaultWorktrees = $projectRoot + ".worktrees"
Write-Output "  Default: $defaultWorktrees"
Write-Output ""
$worktreesInput = Read-Host "  Worktrees path"
if ([string]::IsNullOrWhiteSpace($worktreesInput)) {
    $worktreesRoot = $defaultWorktrees
} else {
    $worktreesRoot = [System.IO.Path]::GetFullPath($worktreesInput.Trim()).TrimEnd('\')
}
Write-Output "  Worktrees: $worktreesRoot"

# === Step 4: OpenClaw state dir ===
$openclawStateDir = "$env:USERPROFILE\.openclaw"
Write-Output ""
Write-Output "[Step 4/5] OpenClaw config directory"
Write-Output "  Using default: $openclawStateDir"
Write-Output "  (This is the standard location for global openclaw installs)"

# === Step 5: Write config ===
Write-Output ""
Write-Output "[Step 5/5] Writing config.json..."
Write-Output ""

$config = [ordered]@{
    projectRoot = $projectRoot
    worktreesRoot = $worktreesRoot
    logSubPath = "Logs\ClaudeRelay"
    openclawStateDir = $openclawStateDir
    claudeCodePath = "claude"
}

$configPath = Join-Path $PSScriptRoot "config.json"
$config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding UTF8
Write-Output "  Config written to: $configPath"

# Initialize log directory
$logDir = Join-Path $projectRoot "Logs\ClaudeRelay"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Write-Output "  Log directory created: $logDir"

# Initialize .openclaw session directory
$sessionDir = Join-Path $projectRoot ".openclaw"
New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
Write-Output "  Session directory created: $sessionDir"

# === Summary ===
Write-Output ""
Write-Output "============================================"
Write-Output " Pipeline scripts installed!"
Write-Output "============================================"
Write-Output ""
Write-Output "Next:"
Write-Output ""
Write-Output "  1. Run the OpenClaw setup wizard:"
Write-Output "     powershell -File setup-openclaw.ps1"
Write-Output ""
Write-Output "  2. Verify everything:"
Write-Output "     powershell -File .\tools\verify-pipeline.ps1"
Write-Output ""
Write-Output "  3. Start the gateway and test from Feishu: /cc-help"
Write-Output ""
Write-Output "Docs: README.md + docs\"
Write-Output ""

exit 0
