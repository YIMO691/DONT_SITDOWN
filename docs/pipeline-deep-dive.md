# 从飞书消息到代码修改：一条完整链路的深度拆解

> 你在手机上发 `/cc-run 修复 EnemyFSM.cs 的空引用`，30 秒后收到"已完成"。这中间发生了什么？本文把整条链路——从飞书 WebSocket 到 Claude Code CLI 再到手机屏幕——逐层拆开。

---

## 目录

1. [架构全景](#1-架构全景)
2. [第 0 层：启动时发生了什么](#2-第-0-层启动时发生了什么)
3. [第 1 层：飞书 WebSocket → OpenClaw Gateway](#3-第-1-层飞书-websocket--openclaw-gateway)
4. [第 2 层：cc-command.ps1 命令路由](#4-第-2-层cc-commandps1-命令路由)
5. [第 3 层：claude-code-relay.ps1 安全中继](#5-第-3-层claude-code-relayps1-安全中继)
6. [第 4 层：Claude Code CLI 代码执行](#6-第-4-层claude-code-cli-代码执行)
7. [返回路径](#7-返回路径)
8. [双模型设计：为什么用两个 AI](#8-双模型设计为什么用两个-ai)
9. [安全设计逐层分析](#9-安全设计逐层分析)
10. [一次真实请求的完整时间线](#10-一次真实请求的完整时间线)

---

## 1. 架构全景

```
┌──────────────────────────────────────────────────────────────────────────┐
│  你的手机                                你的电脑 (Windows 10)              │
│                                                                          │
│  ┌──────────┐       WebSocket          ┌───────────────────────────────┐ │
│  │ 飞书 App  │ ───────────────────────→│ 1. OpenClaw Gateway             │ │
│  │          │                         │    端口: ws://127.0.0.1:18789   │ │
│  │ /cc-run  │                         │    模型: deepseek-v4-flash      │ │
│  │ 修复...  │                         │    指令: SOUL.md → 直通         │ │
│  │          │                         │                                │ │
│  │          │                         │    ↓ 调用 PowerShell            │ │
│  │          │                         │                                │ │
│  │          │                         │ 2. cc-command.ps1 (路由器)      │ │
│  │          │                         │    "/cc-run" 匹配               │ │
│  │          │                         │    → Invoke-Relay               │ │
│  │          │                         │                                │ │
│  │          │                         │    ↓ 调用 relay                 │ │
│  │          │                         │                                │ │
│  │          │                         │ 3. claude-code-relay.ps1        │ │
│  │          │                         │    ① workspace 隔离校验         │ │
│  │          │                         │    ② Git 快照 Before            │ │
│  │          │                         │    ③ 包装 Prompt (注入安全规则) │ │
│  │          │                         │    ④ 调 claude CLI 子进程       │ │
│  │          │                         │    ⑤ Git 快照 After             │ │
│  │          │                         │    ⑥ 密钥脱敏                   │ │
│  │          │                         │    ⑦ 写审计日志                 │ │
│  │          │                         │                                │ │
│  │          │                         │    ↓ 调用 CLI                   │ │
│  │          │                         │                                │ │
│  │          │                         │ 4. Claude Code CLI              │ │
│  │          │ ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │    模型: deepseek-v4-pro[1m]    │ │
│  │ "已完成" │    返回脱敏摘要           │    Read → Edit → 修代码         │ │
│  └──────────┘                         └───────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

**两层 AI，各司其职：**

| | OpenClaw | Claude Code |
|---|---|---|
| 模型 | deepseek-v4-flash | deepseek-v4-pro[1m] |
| 端点 | api.deepseek.com/v1 (OpenAI 兼容) | api.deepseek.com/anthropic (Anthropic 兼容) |
| 上下文 | 8K（只读 SOUL.md） | 1M（读整个项目） |
| 职责 | 判断消息类型 → 调用脚本 | 理解代码 → 编辑文件 |
| 成本/次 | ~$0.001 | ~$0.05-0.20 |

---

## 2. 第 0 层：启动时发生了什么

在分析消息流之前，先看系统是怎么跑起来的。

### 2.1 启动 OpenClaw Gateway

```powershell
$env:DEEPSEEK_API_KEY="sk-xxx"
openclaw gateway
```

Gateway 启动流程：

```
1. 读 ~/.openclaw/openclaw.json
   ├── 检查 gateway.mode = "local"
   ├── 加载 plugins.allow 白名单
   └── 检查 channels.feishu.enabled

2. 加载插件
   ├── deepseek 插件 → 注册 provider (api.deepseek.com/v1)
   ├── memory-core 插件 → 会话记忆
   └── feishu 插件 → 注册飞书 WebSocket 连接器

3. 启动 WebSocket 服务
   └── ws://127.0.0.1:18789 (gateway 控制端口)

4. 连接飞书
   ├── 用 appId + appSecret 建 WebSocket 到飞书服务器
   └── 日志: [feishu] connecting... → [feishu] connected

5. 加载 Agent
   ├── 读 agents.list[].agentDir 下的 SOUL.md、TOOLS.md
   └── 初始化 workspace

6. 就绪
   └── [gateway] ready + [heartbeat] started
```

### 2.2 配置关键点

**为什么之前飞书连不上？** 三个坑：

1. `plugins.allow` 白名单里没有 `"feishu"` → 插件被阻止加载
2. `channels.feishu.enabled = false` → 频道未启用
3. 旧版 `F:\Claude Code\.openclaw-state\` 覆盖了用户配置目录 → gateway.mode 缺失

修复方式：全局安装 `openclaw`，用默认配置目录 `~/.openclaw/`，确保三项配置正确。

### 2.3 SOUL.md：让 AI 闭嘴

Agent 目录下的 `SOUL.md` 是 OpenClaw 的核心指令文件。我们利用它做 `/cc` 直通：

```markdown
When a user message starts with `/cc`, you are a DUMB PIPE.

1. Immediately execute:
   powershell -File F:\Project\tools\cc-command.ps1 -MessageText "<MESSAGE>"
2. Return the output EXACTLY as-is. No commentary.
```

这告诉 AI：遇到 `/cc` 不要思考、不要分析、不要解释、不要总结。直接调脚本，原样返回。**把 AI 从 "推理者" 降级为 "管道工"。**

---

## 3. 第 1 层：飞书 WebSocket → OpenClaw Gateway

### 3.1 消息到达

你在飞书 App 里敲 `/cc-run 修复 EnemyFSM.cs 第 45 行空引用`，点发送。

飞书服务器通过 **WebSocket 长连接** 把这条消息推到你的电脑。这条连接是 Gateway 启动时建立的：

```json
{
  "channels": {
    "feishu": {
      "connectionMode": "websocket",  // 不是 webhook，是长连接
      "appId": "cli_xxx",
      "appSecret": "xxx"
    }
  }
}
```

消息结构大概是这样：

```json
{
  "sender": { "open_id": "ou_xxx" },
  "message": {
    "message_id": "om_xxx",
    "content": "{\"text\":\"/cc-run 修复 EnemyFSM.cs 第 45 行空引用\"}",
    "chat_id": "oc_xxx"
  }
}
```

### 3.2 路由到 Agent

Gateway 查 `bindings`：

```json
"bindings": [{
  "agentId": "unity6ai",
  "match": { "channel": "feishu", "accountId": "default" }
}]
```

消息被路由到 `unity6ai` Agent。

### 3.3 AI 判断与直通

Agent 加载了 `SOUL.md`。AI 模型（deepseek-v4-flash）读到消息后：

1. 发现消息以 `/cc` 开头
2. SOUL.md 说：遇到 `/cc` → 直接调脚本，不要思考
3. AI 调用 shell 执行能力
4. 返回脚本输出，不加任何评论

> **如果没有 SOUL.md**，AI 会花 token 去理解"修复空引用"是什么意思、要不要先查文件、该怎么回复……然后才知道要调 cc-command.ps1。SOUL.md 省掉了这步推理。

---

## 4. 第 2 层：cc-command.ps1 命令路由

OpenClaw 实际执行的命令：

```
powershell -NoProfile -ExecutionPolicy Bypass \
  -File F:\Unity6_AI\tools\cc-command.ps1 \
  -MessageText "/cc-run 修复 EnemyFSM.cs 第 45 行空引用"
```

### 4.1 脚本入口

```powershell
# cc-command.ps1 开头
param([string]$MessageText)

. "$PSScriptRoot\lib\secret-utils.ps1"  # Redact-Secrets 函数

$RelayScript = Join-Path $PSScriptRoot "claude-code-relay.ps1"
# ... 其他脚本路径
```

### 4.2 路由表

```powershell
$trimmedMessage = Normalize-MessageText -Text $MessageText
# → "/cc-run 修复 EnemyFSM.cs 第 45 行空引用"

if ($trimmedMessage -eq "/cc-status") { ... }           # × 不匹配
elseif ($trimmedMessage -eq "/cc-last") { ... }         # × 不匹配
elseif ($trimmedMessage -match '^/cc-session-add(?:\s|$)')  # × 不匹配
elseif ($trimmedMessage -eq "/cc-session") { ... }      # × 不匹配
elseif ($trimmedMessage -match '^/cc-use(?:\s|$)') { ... }   # × 不匹配
elseif ($trimmedMessage -match '^/cc-run-big(?:\s|$)') {     # × 不匹配
elseif ($trimmedMessage -match '^/cc-run(?:\s|$)') {         # ✅ 命中！
    $runPromptText = $trimmedMessage.Substring("/cc-run".Length).Trim()
    # → "修复 EnemyFSM.cs 第 45 行空引用"
    Invoke-Relay -RelayArgs @("-PromptText", $runPromptText, "-AllowEdit")
}
```

### 4.3 Invoke-Relay 函数

```powershell
function Invoke-Relay {
    param([string[]]$RelayArgs)
    # @("-PromptText", "修复...", "-AllowEdit")

    $output = & powershell -NoProfile -ExecutionPolicy Bypass `
        -File $RelayScript @RelayArgs 2>&1

    $exitCode = $LASTEXITCODE

    # 优先返回 Summary Log 内容（结构化的飞书摘要）
    $summaryLogLine = $output |
        Where-Object { $_.ToString().StartsWith("Summary Log: ") } |
        Select-Object -Last 1

    if ($summaryLogLine) {
        $logPath = $summaryLogLine.ToString().Substring("Summary Log: ".Length)
        $content = Get-Content $logPath -Raw
        Write-Output (Redact-Secrets $content.Trim())
        exit $exitCode
    }
    # ... 否则返回完整脱敏输出
}
```

### 4.4 路由设计原则

- **长匹配优先**：`/cc-run-big` 在 `/cc-run` 之前，防止前缀误匹配
- **精确匹配优先**：`/cc-status` 在 `/cc` 兜底之前
- **兜底在最末**：`/cc <任意文本>` 走只读 relay

---

## 5. 第 3 层：claude-code-relay.ps1 安全中继

这是整个管线最大、最核心的脚本。

执行的命令：

```
powershell -File claude-code-relay.ps1 `
  -PromptText "修复 EnemyFSM.cs 第 45 行空引用" `
  -AllowEdit
```

### 5.1 ① Workspace 隔离校验

```powershell
function Resolve-RelayWorkspace {
    $candidate = $TargetConfig.workspace    # 从 cc-target.json 读
    $resolved = (Resolve-Path $candidate).ProviderPath

    # 必须是 F:\Unity6_AI 或其 worktrees 子目录
    $allowed = (Test-PathInsideRoot $resolved $ControlRoot) -or
               (Test-PathInsideRoot $resolved $WorktreesRoot)
    if (-not $allowed) { throw "不安全" }

    return $resolved
}
```

`GetFullPath` 先把 `..\Windows` 这样的相对路径展开成绝对路径，再 `StartsWith` 校验。简单的两个 .NET 调用，就杜绝了路径逃逸。

### 5.2 ② 并发互斥

```powershell
$ExistingTask = Read-CurrentTask  # 读 Logs/ClaudeRelay/current-task.json
if ($ExistingTask.status -eq "running") {
    Write-Output "当前已有任务在运行"
    exit 4
}
```

防止两个 relay 同时改文件导致冲突。简单的文件锁模式——读 JSON → 检查 running → 写 JSON。

### 5.3 ③ Git 快照 Before

```powershell
$GitStatusBefore = Get-GitStatusSnapshot
```

`Get-GitStatusSnapshot` 解析 `git status --short`，对每个文件算 SHA256：

```
{
  "UnityProject/Assets/_Project/Scripts/AI/EnemyFSM.cs": {
    path: "UnityProject/Assets/_Project/Scripts/AI/EnemyFSM.cs",
    status: " M",
    hash: "A1B2C3D4..."
  }
}
```

SHA256 是最精确的变更检测——比时间戳可靠，不会漏掉任何修改。

### 5.4 ④ 包装 Prompt

把用户的任务包裹进安全规则（编辑模式）：

```
You are executing a remote Feishu task inside F:\Unity6_AI.

User original task:
<USER_PROMPT>
修复 EnemyFSM.cs 第 45 行空引用
</USER_PROMPT>

Work mode: editing project files is allowed, but only within strict
safety boundaries.

Allowed:
- Modify normal source files, documentation, and configuration files
- Run read-only inspection commands
- Run necessary local test commands when they are safe
- Modify Unity project files when directly relevant to the task
- Update PROGRESS.md, TODO.md, and AI_DEV_LOG.md

Forbidden:
- Do not run git push
- Do not delete the project directory
- Do not run Remove-Item -Recurse, del /s, rmdir /s, rm -rf
- Do not expose any API Key, Token, App Secret, password
- Do not modify OpenClaw, Claude Code, or DeepSeek secret config
- Do not write secrets into any files
- Do not install unknown global tools
- Do not change Windows system-level settings
- Do not create git commits unless explicitly allowed

Execution requirements:
1. Read the project status first
2. Make a short plan
3. Only change files directly related to the user's task
4. After editing, list the files changed
5. Run safe tests if possible
6. End with sections: Completed work, Modified files,
   Verification result, Remaining issues, Next steps
```

### 5.5 ⑤ 调 Claude Code CLI

```powershell
$AllowedTools = "Read,Glob,Grep,Edit,Write,Bash(git *),Bash(powershell ...)"
$DisallowedTools = "Bash(git push:*),Bash(Remove-Item:*),Bash(rm *:),Bash(del *:)"

$ClaudeArgs = @("-p", $WrappedTask,
                "--output-format", "text",
                "--allowedTools", $AllowedTools,
                "--disallowedTools", $DisallowedTools)

# PowerShell Job 子进程
$ClaudeJob = Start-Job -ScriptBlock {
    & claude @ClaudeArgs 2>&1
} -ArgumentList ...

# 等 20 分钟
$CompletedJob = Wait-Job -Job $ClaudeJob -Timeout 1200
```

`--allowedTools` 和 `--disallowedTools` 是 Claude Code CLI 的[原生安全机制](https://docs.anthropic.com/en/docs/claude-code/security)。黑名单优先级高于白名单，递归删除命令被明确拦截。

### 5.6 ⑥ Git 快照 After + 变更对比

```powershell
$GitStatusAfter = Get-GitStatusSnapshot
$ChangedFiles = Compare-GitStatusSnapshots -Before $Before -After $After
```

对比算法：

```
After 中有，Before 中没有 → added
After 中有，Before 中有，hash 不同 → modified
After 中 status 含 "D" → deleted
```

输出：

```
{
  added: [],
  modified: ["UnityProject/Assets/_Project/Scripts/AI/FSM/EnemyFSM.cs"],
  deleted: []
}
```

### 5.7 ⑦ 密钥脱敏 + 审计日志

```powershell
# 10 种正则
$SafeOutput = Redact-Secrets $RawOutput
# sk-ant-xxx → [REDACTED_SECRET]
# DEEPSEEK_API_KEY=sk-xxx → DEEPSEEK_API_KEY=[REDACTED_SECRET]
# "appSecret":"xxx" → "appSecret":"[REDACTED_SECRET]"

Set-Content $OutputPath $SafeOutput       # -output.txt
Set-Content $MetaPath $MetaAsJson          # -meta.json
Set-Content $SummaryPath $FinalSummary     # -summary.txt
```

每次执行生成 4 个文件，完整可追溯：

```
Logs/ClaudeRelay/
├── 20260508-153000-001-prompt.txt    ← 包装后的完整 Prompt
├── 20260508-153000-001-output.txt    ← 脱敏后的 Claude 输出
├── 20260508-153000-001-meta.json     ← 运行元数据
└── 20260508-153000-001-summary.txt   ← 飞书摘要
```

---

## 6. 第 4 层：Claude Code CLI 代码执行

`claude -p` 收到包装后的 Prompt，通过 DeepSeek API 执行任务。

### 6.1 实际发生了什么

```
Claude Code 收到 Prompt:
  1. Read: EnemyFSM.cs   (读文件)
  2. 找到第 45 行: playerTransform.position  ← 如果 playerTransform 为 null 就空引用
  3. Edit: 在第 45 行前加 if (playerTransform == null) { return; }
  4. 输出结构化结果:
     ## Completed work
     在 EnemyFSM.cs:45 添加了 null check...
     ## Modified files
     - EnemyFSM.cs
     ## Verification result
     语法检查通过，Unity 中 Play 测试无异常
```

### 6.2 为什么要 1M 上下文

`deepseek-v4-pro[1m]` 有 100 万 token 的上下文窗口。这意味着：

- 可以一次性读几百个 `.cs` 文件
- 理解类的继承关系和方法调用链
- 修一个 Bug 时能看到所有相关代码

小模型（8K-128K）做不到这点——每次只能看几十个文件，理解力有限。

---

## 7. 返回路径

```
Claude Code 输出 (原始文本)
  │
  ▼
claude-code-relay.ps1
  ├── Redact-Secrets (脱敏)
  ├── 追加文件变更摘要
  └── claude-code-summary.ps1 (生成摘要)
  │
  ▼
cc-command.ps1 (Invoke-Relay)
  ├── 读 Summary Log
  └── 脱敏后输出
  │
  ▼
OpenClaw Gateway
  └── WebSocket → 飞书
  │
  ▼
你的手机
```

飞书最终显示：

```
状态: 已完成

摘要:
已完成: 在 EnemyFSM.cs:45 添加 null check，防止空引用...
修改文件:
- UnityProject/Assets/_Project/Scripts/AI/FSM/EnemyFSM.cs

变更文件摘要:
修改文件:
- UnityProject/Assets/_Project/Scripts/AI/FSM/EnemyFSM.cs
```

---

## 8. 双模型设计：为什么用两个 AI

这条管线有两个地方调用 AI，设计上刻意分开：

### 8.1 为什么不用一个模型？

| 如果用同一个模型 | 问题 |
|---|---|
| 都用 flash | 代码执行不够强，1M 上下文不可用 |
| 都用 pro | OpenClaw 消息路由用太浪费，成本高 |
| 都用本地模型 | 代码执行质量不够 |

### 8.2 当前方案

```
OpenClaw (v4-flash, 8K, ~$0.001/次)
  └── 只看 SOUL.md 指令 + 消息前缀
  └── "以 /cc 开头？→ 调用脚本"
  └── 几乎零推理，成本极低

Claude Code (v4-pro[1m], 1M, ~$0.05-0.20/次)
  └── 看整个项目代码
  └── 理解逻辑 → 修改文件
  └── 深度推理，成本花在刀刃上
```

**同一条 Key。分开计费，各用所需。**

---

## 9. 安全设计逐层分析

### 9.1 四条防线

```
用户消息
  │
  ▼
防线 1: Workspace 隔离
  GetFullPath + StartsWith → 路径必须在允许范围内
  │
  ▼
防线 2: 工具白/黑名单
  allowedTools: Read, Glob, Grep, Edit, Write, Bash(git/powershell)
  disallowedTools: git push, rm -rf, del /s, Remove-Item
  │
  ▼
防线 3: Prompt 注入防御
  安全规则注入到用户 Prompt 前面
  ├── Do not expose secrets
  ├── Do not install global tools
  ├── Do not modify system settings
  └── End with structured sections
  │
  ▼
防线 4: 事后审计
  ├── Git SHA256 快照 (before/after)
  ├── 10 种密钥正则脱敏 (输出必定执行)
  └── 结构化日志 (每次 4 个文件)
```

### 9.2 为什么不用内核沙箱？

业界最佳实践建议用 Landlock（Linux）/Seatbelt（macOS）做内核级沙箱。但本方案的应用级防护对于 **单人单机开发场景** 已经足够：

- 你不是在跑多租户 SaaS 平台
- Prompt 来自你自己（飞书是你自己的 App）
- 攻击面只有你一个人

如果未来要开放给多人使用，再加内核沙箱。

---

## 10. 一次真实请求的完整时间线

以 `/cc-run 修复 EnemyFSM.cs 空引用` 为例：

```
T+0.0s   你在飞书点发送
T+0.05s  飞书 WebSocket → 你的电脑
T+0.1s   OpenClaw 收到消息，SOUL.md 匹配 /cc 前缀
T+0.2s   OpenClaw 调 PowerShell: cc-command.ps1 -MessageText "..."
T+0.3s   cc-command.ps1 路由到 "/cc-run" → Invoke-Relay
T+0.4s   claude-code-relay.ps1 启动
          ├── 读 cc-target.json (5ms)
          ├── 校验 workspace (2ms)
          ├── 并发检查 (3ms)
          ├── Git 快照 Before (200ms)
          └── 包装 Prompt (10ms)
T+0.7s   Start-Job: claude -p "包装后的 Prompt"
T+1.0s   Claude Code 连接 DeepSeek API
T+1.5s   开始 Read EnemyFSM.cs
T+3.0s   理解代码，找到第 45 行空引用
T+4.0s   Edit: 添加 null check
T+5.0s   输出结构化结果
T+5.2s   relay 收到 Claude 输出
          ├── Redact-Secrets (5ms)
          ├── Git 快照 After (200ms)
          ├── 对比变更 (10ms)
          └── 写 4 个日志文件 (50ms)
T+5.5s   生成摘要
T+5.7s   OpenClaw 收到摘要
T+5.8s   飞书 WebSocket → 手机
T+6.0s   你在飞书看到 "状态: 已完成，修改了 EnemyFSM.cs"
```

**全程约 6 秒。** 其中 AI 推理占 ~3.5s，剩下的都是脚本执行、文件 I/O、网络传输。

---

## 附录

### 相关文档

- [架构文档](architecture.md) — 完整架构图 + 数据流
- [部署指南](deployment.md) — 从零到可用
- [脚本参考](scripts-reference.md) — 每个脚本的参数和逻辑
- [改进路线](improvement-roadmap.md) — 已知问题和优化计划

### 技术栈

| 层 | 技术 |
|---|---|
| 消息通道 | Feishu WebSocket |
| 消息网关 | OpenClaw (Node.js, global npm install) |
| 命令路由 | PowerShell 5.1 (cc-command.ps1) |
| 安全中继 | PowerShell 5.1 (claude-code-relay.ps1) |
| 代码执行 | Claude Code CLI + DeepSeek API |
| AI 模型 | deepseek-v4-flash (路由) + deepseek-v4-pro[1m] (执行) |
| 配置存储 | JSON (openclaw.json, config.json, cc-target.json) |
| 日志系统 | 文本日志 + JSON 元数据 (Logs/ClaudeRelay/) |
