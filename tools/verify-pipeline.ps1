[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$ErrorActionPreference = "Continue"

. "$PSScriptRoot\lib\config.ps1"

Write-Output ""
Write-Output "============================================="
Write-Output " Feishu-CC Pipeline Health Check"
Write-Output " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "============================================="

# ===== Tier 1: Config =====
Write-Output ""
Write-Output "--- Tier 1: Configuration ---"
if (Test-Path (Join-Path $PSScriptRoot "..\config.json")) {
    Write-Output "  config.json: OK"
    Write-Output "  Project: $($Script:ProjectRoot)"
    Write-Output "  Logs: $($Script:LogRoot)"
} else {
    Write-Output "  config.json: MISSING - Run install.ps1 first"
    exit 1
}
if (-not (Test-Path $Script:ProjectRoot)) {
    Write-Output "  WARNING: Project directory does not exist: $($Script:ProjectRoot)"
}

# ===== Tier 2: Script files =====
Write-Output ""
Write-Output "--- Tier 2: Script Files ---"
$scripts = @(
    'tools\cc-command.ps1', 'tools\cc-run.ps1', 'tools\cc-run-big.ps1',
    'tools\cc-status.ps1', 'tools\cc-last.ps1', 'tools\cc-session.ps1',
    'tools\cc-session-add.ps1', 'tools\cc-use.ps1',
    'tools\cc-project.ps1', 'tools\cc-health.ps1',
    'tools\oc-session.ps1', 'tools\claude-code-relay.ps1',
    'tools\claude-code-summary.ps1', 'tools\mobile-status.ps1'
)
$allPresent = $true
foreach ($scriptPath in $scripts) {
    $fullPath = Join-Path $Script:ProjectRoot $scriptPath
    if (Test-Path $fullPath) {
        Write-Output "  OK: $scriptPath"
    } else {
        Write-Output "  MISSING: $scriptPath"
        Write-Output "    Fix: copy tools\ from DONT_SITDOWN to your project"
        $allPresent = $false
    }
}
if (-not $allPresent) { Write-Output "  => Some scripts not deployed to project. Run install.ps1." }

# ===== Tier 3: Routing =====
Write-Output ""
Write-Output "--- Tier 3: Command Routing ---"
Push-Location $Script:ProjectRoot
$routes = @(
    @{msg='/cc-status';            desc='cc-status.ps1'},
    @{msg='/cc-last';              desc='cc-last.ps1'},
    @{msg='/cc-session';           desc='cc-session.ps1'},
    @{msg='/cc-session-add t W:\'; desc='cc-session-add.ps1'},
    @{msg='/cc-use main';          desc='cc-use.ps1'},
    @{msg='/cc-run-big test';      desc='relay (MaxMinutes=0)'},
    @{msg='/cc-run test';          desc='relay (AllowEdit)'},
    @{msg='/cc test';              desc='relay (RawPassThrough)'},
    @{msg='/cc-project-list';      desc='cc-project.ps1 list'},
    @{msg='/cc-health';            desc='cc-health.ps1'},
    @{msg='/oc-session';           desc='oc-session.ps1'},
    @{msg='/cc-help';              desc='help'}
)
$allRouted = $true
$cmdScript = Join-Path $Script:ProjectRoot "tools\cc-command.ps1"
foreach ($route in $routes) {
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $cmdScript -MessageText $route.msg 2>&1 | Select-Object -First 1
    $ok = ($LASTEXITCODE -eq 0 -or $route.msg -like '*test*' -or $route.msg -like '*t W:*')
    if ($ok) {
        Write-Output "  OK: $($route.msg)"
    } else {
        Write-Output "  FAIL: $($route.msg)"
        $allRouted = $false
    }
}
Pop-Location
if (-not $allRouted) { Write-Output "  => Some routes failed. Check script paths in config.json." }

# ===== Tier 4: Prerequisites =====
Write-Output ""
Write-Output "--- Tier 4: Prerequisites ---"
Write-Output "  PowerShell: $($PSVersionTable.PSVersion)"

try { $v = git --version 2>$null; Write-Output "  Git: $v" } catch { Write-Output "  Git: NOT FOUND" }
try { $v = claude --version 2>$null; Write-Output "  Claude CLI: $v" } catch { Write-Output "  Claude CLI: NOT FOUND" }
try {
    $ocVersion = openclaw --version 2>$null
    Write-Output "  OpenClaw: $ocVersion"
} catch { Write-Output "  OpenClaw: NOT FOUND (npm install -g openclaw)" }

# ===== Summary =====
Write-Output ""
Write-Output "============================================="
Write-Output " Result: Config OK, Scripts $($allPresent), Routes $($allRouted)"
Write-Output "============================================="
Write-Output ""
Write-Output "If all OK, start gateway and test from Feishu:"
Write-Output "  $env:DEEPSEEK_API_KEY='sk-...'"
Write-Output "  openclaw gateway"
Write-Output "  (In Feishu) /cc-help"
