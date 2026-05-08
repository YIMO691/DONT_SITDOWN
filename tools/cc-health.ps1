param(
    [switch]$Brief
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$ErrorActionPreference = "Continue"

. "$PSScriptRoot\lib\config.ps1"

$Results = [ordered]@{}

# 1. Git
try {
    $gitVersion = git --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $Results["Git"] = "OK ($gitVersion)"
    } else {
        $Results["Git"] = "FAIL (not found)"
    }
} catch {
    $Results["Git"] = "FAIL ($($_.Exception.Message))"
}

# 2. Claude Code CLI
try {
    $claudeVersion = claude --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $Results["Claude CLI"] = "OK ($claudeVersion)"
    } else {
        $Results["Claude CLI"] = "FAIL (not found)"
    }
} catch {
    $Results["Claude CLI"] = "FAIL ($($_.Exception.Message))"
}

# 3. DeepSeek API
try {
    $apiBase = if ($env:DEEPSEEK_API_BASE) { $env:DEEPSEEK_API_BASE } else { "https://api.deepseek.com" }
    $response = Invoke-WebRequest -Uri "$apiBase/v1/models" -TimeoutSec 10 -ErrorAction Stop -Headers @{
        Authorization = "Bearer $env:DEEPSEEK_API_KEY"
    }
    if ($response.StatusCode -eq 200) {
        $latency = [math]::Round($response.Headers["x-response-time"] * 1000)
        $Results["DeepSeek API"] = "OK (200, ${latency}ms)"
    } else {
        $Results["DeepSeek API"] = "FAIL (HTTP $($response.StatusCode))"
    }
} catch {
    $Results["DeepSeek API"] = "FAIL ($($_.Exception.Message.Split([Environment]::NewLine)[0]))"
}

# 4. Workspace
$wsExists = Test-Path -LiteralPath $Script:ProjectRoot -PathType Container
if ($wsExists) {
    $Results["Workspace"] = "OK ($($Script:ProjectRoot))"
} else {
    $Results["Workspace"] = "FAIL (not found: $($Script:ProjectRoot))"
}

# 5. Log directory + current-task.json
$logExists = Test-Path -LiteralPath $Script:LogRoot -PathType Container
if (-not $logExists) {
    New-Item -ItemType Directory -Force -Path $Script:LogRoot | Out-Null
}
$currentTask = Join-Path $Script:LogRoot "current-task.json"
$taskExists = Test-Path -LiteralPath $currentTask

$logFiles = @(Get-ChildItem -LiteralPath $Script:LogRoot -File -ErrorAction SilentlyContinue)
$logSize = [math]::Round(($logFiles | Measure-Object -Property Length -Sum).Sum / 1KB, 1)
$Results["Logs"] = "OK ($($logFiles.Count) files, ${logSize}KB)"

if ($taskExists) {
    $Results["Task State"] = "OK (current-task.json exists)"
} else {
    try {
        [ordered]@{ status = "idle" } | ConvertTo-Json | Set-Content -LiteralPath $currentTask -Encoding UTF8
        Remove-Item -LiteralPath $currentTask -Force -ErrorAction SilentlyContinue
        $Results["Task State"] = "OK (writable)"
    } catch {
        $Results["Task State"] = "FAIL (not writable)"
    }
}

# 6. Config
$configExists = Test-Path -LiteralPath $Script:ConfigPath
$Results["Config"] = if ($configExists) { "OK (config.json)" } else { "WARN (copy config.example.json)" }

# Output
if ($Brief) {
    $allOk = $true
    foreach ($key in $Results.Keys) {
        if ($Results[$key] -match "^FAIL") { $allOk = $false; break }
    }
    if ($allOk) { Write-Output "OK: All checks passed" } else { Write-Output "FAIL: Some checks failed" }
    exit $(if ($allOk) { 0 } else { 1 })
}

Write-Output ""
Write-Output "Pipeline Health Check"
Write-Output "====================="
Write-Output ""
foreach ($key in $Results.Keys) {
    $status = if ($Results[$key] -match "^OK") { "OK" }
               elseif ($Results[$key] -match "^WARN") { "WARN" }
               else { "FAIL" }
    Write-Output "  $key`: $($Results[$key])"
}
Write-Output ""
Write-Output "---"
Write-Output "Test from Feishu: /cc-help"
Write-Output "Test relay: /cc-status"
