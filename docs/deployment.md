# Deployment Guide

Feishu -> OpenClaw -> Claude Code pipeline from scratch.

## Prerequisites

- Windows 10/11 x64
- Git for Windows
- Node.js 22+ (for global `npm install -g openclaw`)
- DeepSeek API Key (https://platform.deepseek.com)
- Feishu bot (app with message receive permission)
- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)

## Architecture

```
Both use the same DeepSeek API Key:

OpenClaw side:   DeepSeek API (deepseek-v4-flash, openai-completions)
                   -> Parse messages, route /cc commands, generate replies

Claude Code side: DeepSeek API (deepseek-v4-pro, anthropic endpoint)
                   -> Read code, edit files, execute tasks
```

## Step 1: Install OpenClaw (global)

```powershell
npm install -g openclaw@latest
openclaw --version
# Should show: OpenClaw 2026.x.x
```

## Step 2: Onboard with DeepSeek

```powershell
$env:DEEPSEEK_API_KEY="sk-your-key"
openclaw onboard --auth-choice deepseek-api-key --mode local
```

This configures the model provider, gateway mode, and agent defaults.

## Step 3: Install and configure Feishu plugin

```powershell
# Install
openclaw plugins install @openclaw/feishu --force

# Add to allowlist (critical!)
openclaw config set plugins.allow --json "[""deepseek"",""memory-core"",""feishu""]"

# Enable plugin
openclaw plugins enable feishu
```

## Step 4: Configure Feishu channel

```powershell
openclaw channels add feishu
# Enter your Feishu App ID and App Secret when prompted

# Enable the channel
openclaw config set channels.feishu.enabled true

# Verify
openclaw channels status feishu
```

## Step 5: Create agent and bind

```powershell
# Create agent bound to your project workspace
openclaw agents add myproject --workspace "F:\MyProject"

# Bind feishu channel to agent
openclaw agents bind --agent myproject --bind feishu:default
```

## Step 6: Install pipeline scripts

Copy the `tools/` directory and `.claude/` templates from this repo into your project:

```powershell
# From this repo's directory
cp -r tools "F:\MyProject\tools"
cp -r .claude "F:\MyProject\.claude"

# Run setup wizard in your project
cd F:\MyProject
powershell -ExecutionPolicy Bypass -File tools\install.ps1
```

## Step 7: Start gateway

```powershell
# Set API key
$env:DEEPSEEK_API_KEY="sk-your-key"

# Start
openclaw gateway
```

Expected output:
```
[gateway] loading configuration...
[gateway] starting channels and sidecars...
[feishu] connecting...
[feishu] connected
[gateway] ready
[heartbeat] started
```

## Step 8: Test from Feishu

Send `/cc-status` in your Feishu chat. You should get a response with project status.

## Common Issues

| Symptom | Fix |
|---------|-----|
| No `[feishu] connecting` | `openclaw plugins list` — feishu must be `enabled` and in allowlist |
| Plugin blocked by allowlist | `openclaw config set plugins.allow --json "[""deepseek"",""memory-core"",""feishu""]"` |
| Channel not connecting | `openclaw config set channels.feishu.enabled true` |
| Gateway won't start | `openclaw doctor --fix` to repair config |
| Model errors | Verify `$env:DEEPSEEK_API_KEY` is set before starting gateway |
| Old Ollama setup conflict | Remove any `OPENCLAW_STATE_DIR` override from your startup script |
