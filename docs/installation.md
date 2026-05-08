# 新电脑安装指南

从零到飞书可用的完整步骤，预计 15-20 分钟。

---

## 前提

- Windows 10/11 x64
- 管理员权限（安装全局包）
- DeepSeek API Key
- 飞书应用（已创建机器人，有 App ID 和 App Secret）

---

## 第 1 步：安装运行时

```powershell
# Node.js (LTS)
winget install OpenJS.NodeJS.LTS

# Claude Code CLI
npm install -g @anthropic-ai/claude-code

# OpenClaw Gateway
npm install -g openclaw@latest
```

验证：

```powershell
node --version      # >= 18
claude --version     # >= 2.0
openclaw --version
```

---

## 第 2 步：Clone 管线仓库

```powershell
git clone https://github.com/YIMO691/DONT_SITDOWN.git
cd DONT_SITDOWN
```

配置安装：

```powershell
# 创建 config.json（交互式，输入你的项目路径）
copy config.example.json config.json
notepad config.json
```

编辑 `config.json` 指向你的项目：

```json
{
  "projectRoot": "F:\\YourProject",
  "worktreesRoot": "F:\\YourProject.worktrees",
  "logSubPath": "Logs\\ClaudeRelay",
  "openclawStateDir": "C:\\Users\\你的用户名\\.openclaw",
  "claudeCodePath": "claude"
}
```

---

## 第 3 步：配置 OpenClaw

### 3.1 安装飞书插件

```powershell
openclaw plugins install @openclaw/feishu --force
openclaw config set plugins.allow --json "[""deepseek"",""memory-core"",""feishu""]"
openclaw plugins enable feishu
```

### 3.2 配置 DeepSeek 提供者

编辑 `~\.openclaw\openclaw.json`，添加或修改 `models` 段：

```json
{
  "models": {
    "providers": {
      "deepseek": {
        "api": "openai",
        "baseUrl": "https://api.deepseek.com/v1",
        "apiKeyEnv": "DEEPSEEK_API_KEY"
      }
    }
  }
}
```

### 3.3 添加飞书频道

```powershell
openclaw channels add feishu
# 输入 App ID
# 输入 App Secret
openclaw config set channels.feishu.enabled true
```

### 3.4 创建 Agent

```powershell
# 创建 agent（用你的项目名替换 myproject）
openclaw agents add myproject --workspace "F:\YourProject" --model deepseek/deepseek-v4-flash

# 绑定飞书频道
openclaw agents bind --agent myproject --bind feishu:default
```

### 3.5 配置 SOUL.md 直通

```powershell
# 将 SOUL.example.md 复制到 agent 目录
copy .\tools\..\.claude\rules\SOUL.example.md $env:USERPROFILE\.openclaw\agents\myproject\agent\SOUL.md

# 编辑 SOUL.md，确保 PowerShell 路径正确
notepad $env:USERPROFILE\.openclaw\agents\myproject\agent\SOUL.md
```

SOUL.md 中确保这一行指向你的 tools 目录：

```
powershell -NoProfile -ExecutionPolicy Bypass -File F:\YourProject\tools\cc-command.ps1 -MessageText "<MESSAGE>"
```

---

## 第 4 步：部署管线脚本到项目目录

```powershell
# 把 tools 和 lib 复制到你的项目
copy -Recurse .\tools\ F:\YourProject\tools\
copy .\config.json F:\YourProject\config.json

# 确保 .openclaw 目录存在
New-Item -ItemType Directory -Force -Path "F:\YourProject\.openclaw" | Out-Null
```

---

## 第 5 步：配置项目注册表

编辑 `~\.openclaw\cc-projects.json`（如果不存在则创建）：

```json
[
  {
    "name": "myproject",
    "workspace": "F:\\YourProject",
    "worktreesRoot": "F:\\YourProject.worktrees",
    "active": true,
    "description": "我的主项目"
  }
]
```

> 多个项目就加多条记录，`active: true` 的会作为默认项目。

---

## 第 6 步：设置环境变量并启动

```powershell
# 设置 API Key（每次启动前，或写入用户环境变量）
$env:DEEPSEEK_API_KEY = "sk-your-deepseek-key"

# 启动 Gateway（保持此窗口运行）
openclaw gateway
```

看到以下输出表示成功：

```
[feishu] connecting...
[feishu] connected
[heartbeat] started
[gateway] listening on ws://127.0.0.1:18789
```

---

## 第 7 步：验证

在飞书中发送：

```
/cc-help
```

应收到命令列表。继续测试：

```
/cc-project-list    →  查看已注册项目
/cc-health          →  全链路健康检查
/cc-run 写一个 Hello World   →  测试代码执行
```

---

## 多项目配置

在 `~\.openclaw\cc-projects.json` 中添加更多项目：

```json
[
  {
    "name": "game-project",
    "workspace": "F:\\GameProject",
    "worktreesRoot": "F:\\GameProject.worktrees",
    "active": true,
    "description": "Unity 游戏"
  },
  {
    "name": "web-backend",
    "workspace": "F:\\WebBackend",
    "worktreesRoot": "F:\\WebBackend.worktrees",
    "active": false,
    "description": "后端服务"
  }
]
```

> 每个项目的 workspace 目录必须存在、必须有 `tools\` 和 `config.json`。
> 在飞书用 `/cc-project-use web-backend` 切换。

---

## 故障排除

### 飞书发消息没反应

1. 检查 gateway 窗口是否有 `[feishu] connected`
2. 检查 `$env:DEEPSEEK_API_KEY` 是否已设置
3. 检查 `SOUL.md` 中的 `cc-command.ps1` 路径是否正确

### /cc-health 报 FAIL

按照 `/cc-health` 输出逐项排查。常见问题：
- Git 未安装 → `winget install Git.Git`
- Claude CLI 未安装 → `npm install -g @anthropic-ai/claude-code`
- DeepSeek API 不通 → 检查 Key 和网络

### 任务执行失败

查看日志：`F:\YourProject\Logs\ClaudeRelay\` 下的 `-meta.json` 和 `-output.txt`。

---

## 升级管线

当 GitHub 仓库有更新时：

```powershell
cd DONT_SITDOWN
git pull

# 同步到部署目录
copy -Recurse .\tools\* F:\YourProject\tools\
```

不需要重启 gateway。
