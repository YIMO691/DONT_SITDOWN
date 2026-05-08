[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Continue"

. "$PSScriptRoot\lib\config.ps1"

Set-Location -LiteralPath $Script:ProjectRoot

Write-Output ""
Write-Output "=============================="
Write-Output " OpenClaw Agent Runtime Status"
Write-Output "=============================="
Write-Output ""

Write-Output "[OpenClaw Process]"
$openclawProc = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*openclaw*" }
if ($openclawProc) {
    $proc = if ($openclawProc -is [array]) { $openclawProc[0] } else { $openclawProc }
    Write-Output "  Status: node.exe running (openclaw)"
    Write-Output "  PID: $($proc.ProcessId)"
    $memMB = [math]::Round($proc.WorkingSetSize / 1MB, 1)
    Write-Output "  Memory: $memMB MB"
} else {
    Write-Output "  Status: OpenClaw process not found"
    Write-Output "  Hint: Start OpenClaw"
}

Write-Output ""
Write-Output "[Ollama Service]"
try {
    $ollamaResponse = Invoke-WebRequest -Uri "http://127.0.0.1:11434" -TimeoutSec 5 -ErrorAction Stop
    Write-Output "  Status: running (HTTP $($ollamaResponse.StatusCode))"
} catch {
    Write-Output "  Status: connection failed ($($_.Exception.Message))"
    Write-Output "  Hint: Ensure Ollama is running (ollama serve)"
}

Write-Output ""
Write-Output "[OpenClaw Config]"
$openclawConfigPath = Join-Path $Script:OpenClawStateDir "openclaw.json"
if (Test-Path -LiteralPath $openclawConfigPath) {
    try {
        $config = Get-Content -LiteralPath $openclawConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $primaryModel = $config.agents.defaults.model.primary
        Write-Output "  Primary Model: $primaryModel"
        foreach ($providerName in $config.models.providers.PSObject.Properties.Name) {
            $provider = $config.models.providers.$providerName
            Write-Output "  Provider: $providerName (api=$($provider.api), url=$($provider.baseUrl))"
        }
    } catch {
        Write-Output "  Config read failed: $($_.Exception.Message)"
    }
} else {
    Write-Output "  Config not found: $openclawConfigPath"
}

Write-Output ""
Write-Output "[Current Claude Code Target]"
if (Test-Path -LiteralPath $Script:TargetConfigPath) {
    try {
        $target = Get-Content -LiteralPath $Script:TargetConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Output "  Session: $($target.defaultSessionName)"
        Write-Output "  Workspace: $($target.workspace)"
        Write-Output "  Branch: $($target.gitBranch)"
        Write-Output "  Updated: $($target.updatedAt)"
    } catch {
        Write-Output "  Target config read failed"
    }
} else {
    Write-Output "  Target config not found (no relay executed yet?)"
}

Write-Output ""
Write-Output "---"
Write-Output "Claude Code sessions: /cc-session"
