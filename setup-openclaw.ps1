[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$ErrorActionPreference = "Continue"

Write-Output ""
Write-Output "============================================"
Write-Output " OpenClaw Setup for Feishu-CC Pipeline"
Write-Output "============================================"
Write-Output ""

# ===== Step 1: Prerequisites =====
Write-Output "[1/6] Checking prerequisites..."
Write-Output ""

$nodeOk = $false; try { node --version 2>$null; $nodeOk = $true } catch { }
if ($nodeOk) { Write-Output "  Node.js: OK" } else { Write-Output "  Node.js: NOT FOUND. Install from https://nodejs.org"; exit 1 }

$ocOk = $false; try { openclaw --version 2>$null; $ocOk = $true } catch { }
if ($ocOk) { Write-Output "  OpenClaw: OK ($(openclaw --version 2>$null))" }
else {
    Write-Output "  OpenClaw: NOT FOUND"
    Write-Output "  Installing: npm install -g openclaw@latest"
    npm install -g openclaw@latest 2>&1
    try { openclaw --version 2>$null; $ocOk = $true } catch { }
    if (-not $ocOk) { Write-Output "  Failed to install OpenClaw."; exit 1 }
    Write-Output "  OpenClaw installed."
}

$deepseekKey = $env:DEEPSEEK_API_KEY
if ([string]::IsNullOrWhiteSpace($deepseekKey)) {
    Write-Output ""
    Write-Output "  WARNING: DEEPSEEK_API_KEY is not set."
    Write-Output "  Set it before starting the gateway:"
    Write-Output '    $env:DEEPSEEK_API_KEY="sk-your-key"'
}
Write-Output ""

# ===== Step 2: OpenClaw onboard =====
Write-Output "[2/6] Checking OpenClaw configuration..."
Write-Output ""
$ocConfigPath = "$env:USERPROFILE\.openclaw\openclaw.json"
if (Test-Path $ocConfigPath) {
    try {
        $cfg = Get-Content $ocConfigPath -Raw | ConvertFrom-Json
        $hasGateway = ($cfg.gateway -and $cfg.gateway.mode -eq "local")
        if ($hasGateway) { Write-Output "  Gateway mode: local (OK)" }
        else { Write-Output "  Gateway mode: NOT SET. Run: openclaw onboard --mode local" }
    } catch { Write-Output "  Config exists but could not parse. Run: openclaw onboard --mode local" }
} else {
    Write-Output "  No config found. Run: openclaw onboard --auth-choice deepseek-api-key --mode local"
}
Write-Output ""

# ===== Step 3: Feishu plugin =====
Write-Output "[3/6] Setting up Feishu plugin..."
Write-Output ""

$hasFeishuPlugin = $false
try {
    $pluginList = openclaw plugins list 2>&1 | Out-String
    if ($pluginList -match "feishu.*enabled") { $hasFeishuPlugin = $true }
} catch { }

if (-not $hasFeishuPlugin) {
    Write-Output "  Installing @openclaw/feishu..."
    openclaw plugins install @openclaw/feishu --force 2>&1 | Out-Null
}

Write-Output "  Setting plugin allowlist..."
openclaw config set plugins.allow --json '["deepseek","memory-core","feishu"]' 2>&1 | Out-Null

Write-Output "  Enabling feishu plugin..."
openclaw plugins enable feishu 2>&1 | Out-Null

Write-Output "  Plugin setup complete."
Write-Output ""

# ===== Step 4: Feishu channel =====
Write-Output "[4/6] Feishu channel configuration..."
Write-Output ""
Write-Output "  You need your Feishu App ID and App Secret from:"
Write-Output "  https://open.feishu.cn/app → Your App → Credentials"
Write-Output ""
$setupChannel = Read-Host "  Do you have the credentials? (y/n)"

if ($setupChannel -eq "y") {
    Write-Output "  Running: openclaw channels add feishu"
    openclaw channels add feishu
    openclaw config set channels.feishu.enabled true
    Write-Output "  Channel enabled."
} else {
    Write-Output "  Skipping. Run later:"
    Write-Output "    openclaw channels add feishu"
    Write-Output "    openclaw config set channels.feishu.enabled true"
}
Write-Output ""

# ===== Step 5: Agent setup =====
Write-Output "[5/6] Agent configuration..."
Write-Output ""
$projectRoot = Read-Host "  Project path for agent workspace (e.g., F:\MyProject)"

if (-not [string]::IsNullOrWhiteSpace($projectRoot)) {
    $agentName = Read-Host "  Agent name (e.g., myproject)"
    if ([string]::IsNullOrWhiteSpace($agentName)) { $agentName = "myproject" }

    Write-Output "  Creating agent '$agentName'..."
    openclaw agents add $agentName --workspace $projectRoot 2>&1 | Out-Null

    Write-Output "  Binding to feishu:default..."
    openclaw agents bind --agent $agentName --bind feishu:default 2>&1 | Out-Null

    # Generate SOUL.md
    $agentDir = "$env:USERPROFILE\.openclaw\agents\$agentName\agent"
    New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
    $soulPath = Join-Path $agentDir "SOUL.md"
    $soulContent = @"
# /cc Command Passthrough

When a user message starts with ``/cc``, you are a DUMB PIPE.
Do not analyze, think, or respond conversationally.

## Rule

1. Immediately execute this exact command:

`powershell -NoProfile -ExecutionPolicy Bypass -File $projectRoot\tools\cc-command.ps1 -MessageText "<MESSAGE>"`

Replace `<MESSAGE>` with the user's raw message text (preserve the ``/cc`` prefix).

2. Return the command output EXACTLY as-is. No commentary, no "Here is the result".

3. If the command fails, return the error verbatim.
"@
    Set-Content -LiteralPath $soulPath -Value $soulContent -Encoding UTF8
    Write-Output "  SOUL.md generated: $soulPath"
} else {
    Write-Output "  Skipping. Run later:"
    Write-Output "    openclaw agents add myproject --workspace F:\MyProject"
    Write-Output "    openclaw agents bind --agent myproject --bind feishu:default"
    Write-Output "    (Then copy SOUL.example.md to agent directory)"
}
Write-Output ""

# ===== Step 6: Deploy scripts =====
Write-Output "[6/6] Deploying pipeline scripts to project..."
Write-Output ""
if (-not [string]::IsNullOrWhiteSpace($projectRoot)) {
    $srcTools = Join-Path $PSScriptRoot "tools"
    $dstTools = Join-Path $projectRoot "tools"
    if (Test-Path $dstTools) {
        Write-Output "  WARNING: tools\ already exists in project. Overwrite? (y/n)"
        $overwrite = Read-Host
        if ($overwrite -ne "y") { Write-Output "  Skipping script deployment."; exit 0 }
    }
    Copy-Item -Recurse -Force $srcTools $dstTools
    Write-Output "  Scripts deployed to: $dstTools"

    # Run install.ps1 in project context
    $installScript = Join-Path $PSScriptRoot "install.ps1"
    if (Test-Path $installScript) {
        Write-Output "  Run install.ps1 in your project to complete configuration."
    }
} else {
    Write-Output "  Skipping. Deploy manually:"
    Write-Output "    Copy tools\ from DONT_SITDOWN to your project"
}

Write-Output ""
Write-Output "============================================"
Write-Output " Setup Complete!"
Write-Output "============================================"
Write-Output ""
Write-Output "To start the pipeline:"
Write-Output '  $env:DEEPSEEK_API_KEY="sk-your-key"'
Write-Output "  openclaw gateway"
Write-Output ""
Write-Output "Then from Feishu: /cc-help"
Write-Output ""
Write-Output "Verify everything: powershell -File .\tools\verify-pipeline.ps1"
