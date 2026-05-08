$ErrorActionPreference = "Continue"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\secret-utils.ps1"

function Write-Section {
    param([string]$Title)
    Write-Output ""
    Write-Output "===== $Title ====="
}

Set-Location $Script:ProjectRoot
$NoLocalUnityLogsMessage = "未找到项目本地 Unity 日志，请先运行 Unity 测试或构建生成 Logs 文件。"

Write-Output "Project Mobile Status Report"
Write-Output "Generated At: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "Project Root: $($Script:ProjectRoot)"

Write-Section "Unity Project Check"
if ((Test-Path ".\Assets") -and (Test-Path ".\Packages") -and (Test-Path ".\ProjectSettings")) {
    Write-Output "Unity project structure: OK"
} elseif ((Test-Path ".\UnityProject\Assets") -and (Test-Path ".\UnityProject\Packages") -and (Test-Path ".\UnityProject\ProjectSettings")) {
    Write-Output "Unity project structure: OK (nested UnityProject/)"
} else {
    Write-Output "Warning: Unity project structure may be incomplete."
}

Write-Section "Git Branch"
try { git branch --show-current } catch { Write-Output "Git branch unavailable." }

Write-Section "Recent Commits"
try { git log --oneline -5 } catch { Write-Output "Git log unavailable." }

Write-Section "Working Tree"
try { git status --short } catch { Write-Output "Git status unavailable." }

$ProgressPath = ".\docs\status\PROGRESS.md"
$TodoPath = ".\docs\status\TODO.md"
$DevLogPath = ".\docs\status\AI_DEV_LOG.md"

Write-Section "docs/status/PROGRESS.md"
if (Test-Path $ProgressPath) {
    $lines = Get-Content $ProgressPath -TotalCount 120
    foreach ($line in $lines) { Write-Output (Redact-Secrets -Text $line) }
} else { Write-Output "docs/status/PROGRESS.md not found." }

Write-Section "docs/status/TODO.md"
if (Test-Path $TodoPath) {
    $lines = Get-Content $TodoPath -TotalCount 120
    foreach ($line in $lines) { Write-Output (Redact-Secrets -Text $line) }
} else { Write-Output "docs/status/TODO.md not found." }

Write-Section "docs/status/AI_DEV_LOG.md"
if (Test-Path $DevLogPath) {
    $lines = Get-Content $DevLogPath -Tail 120
    foreach ($line in $lines) { Write-Output (Redact-Secrets -Text $line) }
} else { Write-Output "docs/status/AI_DEV_LOG.md not found." }

Write-Section "Unity Logs"
$logCandidates = @(".\Logs\EditModeBatch.log", ".\Logs\EditModeResults.xml", ".\Logs\UnityBatch.log")
$foundLocalLogs = $false
foreach ($log in $logCandidates) {
    if (Test-Path $log) {
        $foundLocalLogs = $true
        Write-Output "--- $log ---"
        try {
            $logLines = Get-Content -LiteralPath $log -Tail 80 -ErrorAction Stop
            foreach ($l in $logLines) { Write-Output (Redact-Secrets -Text $l) }
        } catch { Write-Output "Unable to read log: $($_.Exception.Message)" }
    }
}
if (-not $foundLocalLogs) { Write-Output $NoLocalUnityLogsMessage }

Write-Section "Likely Errors"
$errorPattern = 'error CS|Exception|Failed|FAIL|Compilation failed|NullReferenceException'
$scanFiles = @(".\Logs\EditModeBatch.log", ".\Logs\EditModeResults.xml", ".\Logs\UnityBatch.log")
$foundLocalLogsForScan = $false
foreach ($file in $scanFiles) {
    if (Test-Path $file) {
        $foundLocalLogsForScan = $true
        Write-Output "--- scanning $file ---"
        try {
            $matches = Select-String -LiteralPath $file -Pattern $errorPattern -CaseSensitive:$false -ErrorAction Stop | Select-Object -Last 40
            if ($matches) { foreach ($m in $matches) { Write-Output (Redact-Secrets -Text $m.Line) } }
            else { Write-Output "No obvious recent errors found." }
        } catch { Write-Output "Unable to scan log: $($_.Exception.Message)" }
    }
}
if (-not $foundLocalLogsForScan) { Write-Output $NoLocalUnityLogsMessage }

Write-Section "Summary Hint"
Write-Output "Use this output to summarize: current phase, completed work, blockers, recent errors, next step."
