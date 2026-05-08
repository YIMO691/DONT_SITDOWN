# Feishu-CC Pipeline

从飞书手机 App 远程控制 Claude Code CLI 写代码、修 Bug、查状态。

```
你在飞书发一条消息 "/cc-run 修复空引用异常"
       ↓
电脑上的 Claude Code 自动改代码
       ↓
改完飞书回复你 "已完成，修改了 EnemyFSM.cs:45"
```

---

## 目录

- [完整链路](#完整链路)
- [快速开始](#快速开始)
- [命令参考](#命令参考)
- [架构详解](#架构详解)
- [安全机制](#安全机制)
- [双模型设计](#双模型设计)
- [多分支开发](#多分支开发)
- [项目结构](#项目结构)
- [常见问题](#常见问题)
- [文档索引](#文档索引)

---

## 完整链路

从飞书发一条 `/cc-run 修复 EnemyFSM.cs 的空引用` 到收到回复，全链路拆解：

```
┌─────────────────────────────────────────────────────────────────────────┐
│  你的手机                          你的电脑 (Windows)                    │
│                                       ┌──────────────────────────────┐  │
│  ┌──────────┐   WebSocket 长连接      │ 1. OpenClaw Gateway           │  │
│  │ 飞书 App  │ ──────────────────────→│    全局安装, v2026.5.7         │  │
│  │          │                        │    模型: deepseek-v4-flash    │  │
│  │ /cc-run  │                        │    API:  api.deepseek.com/v1  │  │
│  │ 修复...  │                        │    端口: ws://127.0.0.1:18789 │  │
│  │          │                        │    读到 SOUL.md → 直通        │  │
│  │          │ ←────────────────────── │                               │  │
│  │ 已完成   │   返回脱敏摘要          │ 2. cc-command.ps1 (路由器)     │  │
│  └──────────┘                        │    "/cc-run" → Invoke-Relay   │  │
│                                       │                               │  │
│                                       │ 3. claude-code-relay.ps1      │  │
│                                       │    · workspace 隔离校验        │  │
│                                       │    · Git 快照 before/after    │  │
│                                       │    · 注入安全规则到 Prompt     │  │
│                                       │    · 启动 claude CLI 子进程   │  │
│                                       │    · 密钥脱敏 + 审计日志       │  │
│                                       │                               │  │
│                                       │ 4. Claude Code CLI            │  │
│                                       │    模型: deepseek-v4-pro[1m]  │  │
│                                       │    API:  api.deepseek.com/    │  │
│                                       │          anthropic            │  │
│                                       │    执行: Read/Edit/Write      │  │
│                                       └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### 第 1 层：飞书 → OpenClaw Gateway（消息接收与直通）

飞书通过 **WebSocket 长连接** 把消息推送到电脑。

OpenClaw Gateway（`openclaw gateway` 启动）在 `ws://127.0.0.1:18789` 监听。核心配置在 `~/.openclaw/openclaw.json`：

```json
"channels": { "feishu": { "enabled": true, "connectionMode": "websocket" } },
"bindings": [{ "agentId": "myproject", "match": { "channel": "feishu" } }]
```

收到消息后，Agent 目录下的 `SOUL.md` 指令告诉 AI：**消息以 `/cc` 开头 → 不做任何分析，直接调用外部 PowerShell 脚本。**

```
OpenClaw AI（不分析消息内容）
  → 立即执行: powershell -File cc-command.ps1 -MessageText "<原始消息>"
  → 返回输出，不加任何评论
```

### 第 2 层：cc-command.ps1（命令路由器）

解析消息，走 `if/elseif` 链（长匹配优先）：

```
/cc-status          → cc-status.ps1（查询）
/cc-last            → cc-last.ps1（查询）
/cc-session-add ... → cc-session-add.ps1（管理）
/cc-session         → cc-session.ps1（查询）
/cc-use ...         → cc-use.ps1（管理）
/cc-run-big ...     → claude-code-relay.ps1 -AllowEdit -MaxMinutes 0（编辑，无超时）
/cc-run ...         → claude-code-relay.ps1 -AllowEdit（编辑，20min 超时）
/cc-project-list    → cc-project.ps1 -Action list（查询）
/cc-project-use ... → cc-project.ps1 -Action use（管理）
/cc-health          → cc-health.ps1 -Brief（查询）
/oc-session         → oc-session.ps1（OpenClaw 运行时状态）
/cc-help            → 命令帮助
/cc ...             → claude-code-relay.ps1 -RawPassThrough（只读查询，兜底）
其他                → "请发送 /cc ... 命令"
```

关键设计：`/cc-run-big` 在 `/cc-run` 之前判断，避免被前缀误匹配。

### 第 3 层：claude-code-relay.ps1（安全中继，599行）

这是整个管线最核心的脚本，做 7 件事：

| 步骤 | 操作 |
|------|------|
| ① 确定 workspace | 读 `.openclaw/cc-target.json`，校验路径合法性，防止 `..\` 逃逸 |
| ② 并发互斥 | 检查 `Logs/ClaudeRelay/current-task.json`，已有任务在跑则拒绝 |
| ③ Git 快照 Before | `git status --short` + SHA256 hash 记录每个文件状态 |
| ④ 包装 Prompt | 把用户任务包裹进 ~40 行安全规则（允许/禁止列表、输出要求） |
| ⑤ 调 Claude CLI | `Start-Job { claude -p ... --allowedTools ... --disallowedTools ... }` + `Wait-Job -Timeout 1200` |
| ⑥ Git 快照 After | 对比 SHA256，输出 added/modified/deleted 文件列表 |
| ⑦ 脱敏 + 日志 | 10 种正则脱敏，写 4 个日志文件（prompt/output/meta/summary） |

### 第 4 层：Claude Code CLI → 返回

Claude Code 通过 **DeepSeek API（Anthropic 兼容端点）** 执行任务——读代码、编辑文件、运行检查。

**返回路径**（原路返回）：

```
Claude Code 输出
  → relay 脱敏 + 追加变更摘要
    → OpenClaw 接收
      → 飞书 WebSocket → 你的手机
```

最终飞书回复示例：

```
状态: 已完成
模式: allow-edit

摘要:
已完成: 在 EnemyFSM.cs:45 添加了 null check...

变更文件摘要:
修改文件:
- UnityProject/Assets/_Project/Scripts/AI/FSM/EnemyFSM.cs
```

---

## 快速开始

### 前提

- Windows 10/11 x64
- PowerShell 5.1+
- [Claude Code CLI](https://claude.ai/code) — `npm install -g @anthropic-ai/claude-code`
- [OpenClaw](https://openclaw.ai/) — `npm install -g openclaw@latest`
- [DeepSeek API Key](https://platform.deepseek.com)
- 飞书机器人（有消息接收权限）

### 安装管线

```powershell
# 1. Clone 本仓库
git clone https://github.com/YIMO691/DONT_SITDOWN.git
cd DONT_SITDOWN

# 2. 运行安装向导（交互式，生成 config.json）
powershell -ExecutionPolicy Bypass -File install.ps1

# 3. 验证
powershell -File tools/cc-command.ps1 -MessageText "/cc-status"
```

### 配置 OpenClaw

**Step 1：安装飞书插件**

```powershell
openclaw plugins install @openclaw/feishu --force
openclaw config set plugins.allow --json "[""deepseek"",""memory-core"",""feishu""]"
openclaw plugins enable feishu
```

**Step 2：配置飞书频道**

```powershell
openclaw channels add feishu
# 输入 App ID 和 App Secret
openclaw config set channels.feishu.enabled true
```

**Step 3：创建 Agent 并绑定**

```powershell
openclaw agents add myproject --workspace "F:\MyProject" --model deepseek/deepseek-v4-flash
openclaw agents bind --agent myproject --bind feishu:default
```

**Step 4：配置 SOUL.md 直通（跳过 AI 分析 `/cc` 消息）**

将 `SOUL.example.md` 复制到 agent 目录并改名为 `SOUL.md`：

```powershell
copy .claude\rules\SOUL.example.md $env:USERPROFILE\.openclaw\agents\myproject\agent\SOUL.md
# 编辑 SOUL.md，把 <YOUR_PROJECT> 替换为你的项目路径
```

**Step 5：启动**

```powershell
$env:DEEPSEEK_API_KEY="sk-你的key"
openclaw gateway
```

看到 `[feishu] connected` + `[heartbeat] started` 即成功。

### 飞书测试

在飞书发：

```
/cc-help
```

应该收到命令列表。

---

## 命令参考

| 命令 | 模式 | 说明 |
|------|------|------|
| `/cc <查询>` | 只读 | 查文件、git log、项目状态 |
| `/cc-run <任务>` | 可编辑 (20min) | 改代码/文档，relay 安全防护 |
| `/cc-run-big <任务>` | 可编辑 (无限) | 大型任务，relay 安全防护 |
| `/cc-status` | 查询 | 当前 relay 任务状态 |
| `/cc-last` | 查询 | 最近一次执行摘要 |
| `/cc-session` | 查询 | 列出已注册开发会话 |
| `/cc-session-add <name> <path>` | 管理 | 注册新会话 |
| `/cc-use <name>` | 管理 | 切换工作会话 |
| `/cc-project-list` | 查询 | 列出已注册项目 |
| `/cc-project-use <name>` | 管理 | 切换活跃项目 |
| `/cc-health` | 查询 | 全链路健康检查 |
| `/oc-session` | 查询 | OpenClaw 进程/模型/配置 |
| `/cc-help` | 查询 | 显示此命令列表 |

---

## 架构详解

### 双重 AI 模型设计

管线里有两个 AI 调用，各用不同的 DeepSeek 模型：

| | OpenClaw | Claude Code |
|------|----------|-------------|
| **模型** | `deepseek-v4-flash` | `deepseek-v4-pro[1m]` |
| **API 端点** | `api.deepseek.com/v1` (OpenAI 兼容) | `api.deepseek.com/anthropic` (Anthropic 兼容) |
| **用途** | 判断消息是否 `/cc` 命令 → 直通 | 读代码、写文件、执行任务 |
| **上下文** | 短（只读 SOUL.md 指令） | 1M token（可读大型项目） |
| **每次 /cc 消耗** | ~1 次轻量调用 | ~1 次重量调用 |
| **同一 Key?** | ✅ | ✅ |

配合 `SOUL.md`，OpenClaw 对 `/cc` 消息几乎不做推理——读到指令直接调用脚本，省掉了 OpenClaw 这层的分析成本。

### 安全层级

```
防线 0: 项目注册白名单
  relay 校验 workspace 必须在 ~/.openclaw/cc-projects.json 已注册项目中
  未注册路径 → 拒绝执行。新增项目需本机手动编辑，不可远程添加。

防线 1: Workspace 隔离
  GetFullPath + StartsWith 校验，路径必须在已注册项目根或 worktrees 下

防线 2: 工具白名单/黑名单
  --allowedTools:  Read,Glob,Grep,Edit,Write,Bash(powershell ...)
  --disallowedTools: Bash(git push:*), Bash(rm *:), Bash(del *:)

防线 3: 并发互斥
  System.IO.FileStream 排他锁，防止两个 relay 同时修改同一项目

防线 4: Prompt 注入防御
  编辑模式下在用户 Prompt 前注入 ~40 行安全规则

防线 5: 事后审计
  Git SHA256 快照 (before/after) + 密钥脱敏 (10 种正则) + 结构化日志 (4 文件/次) + 自动重试 (2 次)
```

### 日志系统

每次 relay 执行在 `Logs/ClaudeRelay/` 生成 4 个文件：

| 文件 | 内容 |
|------|------|
| `{runId}-prompt.txt` | 包装后的完整 Prompt（含安全规则） |
| `{runId}-output.txt` | 脱敏后的 Claude Code 完整输出 |
| `{runId}-meta.json` | 运行元数据（时间、exit code、模式、变更文件列表） |
| `{runId}-summary.txt` | 面向飞书的结构化摘要 |

---

## 安全机制

### 禁止的操作

| 操作 | 阻止方式 |
|------|---------|
| `git push` | `--disallowedTools Bash(git push:*)` |
| `rm -rf` / `del /s` / `Remove-Item -Recurse` | `--disallowedTools` 黑名单 |
| 路径逃逸 `..\..\Windows` | `GetFullPath` + `StartsWith` 校验 |
| 泄露 API Key | 10 种正则脱敏，输出前必定执行 |
| 安装全局工具 | Prompt 注入规则明确禁止 |
| 修改系统设置 | Prompt 注入规则明确禁止 |

### 脱敏覆盖的密钥类型

Anthropic (`sk-ant-*`), OpenAI (`sk-*`), DeepSeek (`DEEPSEEK_API_KEY=`), Feishu (`FEISHU_APP_SECRET=`, `appSecret`), Claude Token (`CLAUDE_TOKEN`)

### 并发互斥

`current-task.json` 记录当前运行状态。status=running 时拒绝新任务，防止两个 relay 同时改同一个项目。

---

## 双模型设计

### 为什么用两个模型？

| 需求 | OpenClaw | Claude Code |
|------|----------|-------------|
| 任务 | 判断消息类型 + 直通 | 理解代码 + 编辑文件 |
| 模型需求 | 快速、轻量 | 深度推理、大上下文 |
| 成本 | 尽量低 | 值得投入 |

用 `deepseek-v4-flash`（便宜）做消息路由，用 `deepseek-v4-pro[1m]`（强）做代码执行。同一条 Key，成本最优。

### 配合 SOUL.md 减少浪费

加上 SOUL.md 后，OpenClaw 不再花 token 去理解 `/cc` 消息的内容——直接透传给 PowerShell 脚本。OpenClaw 的 AI 调用只用于：
- 非 `/cc` 的闲聊消息
- `/cc` 消息的格式判断（毫秒级）

真正的推理发生在 Claude Code 那层。

---

## 多分支开发

```powershell
# 创建 worktree 隔离开发
git worktree add -b feature/my-branch F:\MyProject.worktrees\my-branch

# 注册为会话
powershell -File tools/cc-session-add.ps1 -Name my-branch -Workspace "F:\MyProject.worktrees\my-branch" -GitBranch feature/my-branch -Role "My feature"

# 飞书切换
/cc-use my-branch

# 后续 /cc-run 都在这个分支上执行
```

---

## 多项目管理

管线的安全模型基于**项目注册白名单**。`~\.openclaw\cc-projects.json` 列出了所有允许操作的项目：

```json
[
  { "name": "unity6-ai",    "workspace": "F:\\Unity6_AI",       "active": true },
  { "name": "dont-sitdown", "workspace": "F:\\DONT_SITDOWN",     "active": false }
]
```

在飞书中：

```
/cc-project-list              →  查看所有已注册项目
/cc-project-use dont-sitdown  →  切换到管线项目
```

任何 relay 任务执行前，workspace 必须匹配已注册项目的路径或其 worktrees 子目录，否则拒绝执行。

新项目需在电脑上手动编辑 `cc-projects.json`，不可通过飞书远程添加——这保证了攻击者即使控制飞书也无法将管线指向未授权目录。

---

## 项目结构

```
DONT_SITDOWN/
├── README.md                     ← 你正在读
├── LICENSE                       MIT
├── CLAUDE.md                     AI 协作指令
├── AGENTS.md                     AI 代理交接说明
├── SECURITY.md                   安全策略
├── CONTRIBUTING.md               贡献指南
├── .gitignore
├── .gitattributes                行尾规范化
├── config.example.json           配置模板
├── config.json                   你的配置 (git-ignored, 由 install.ps1 生成)
├── install.ps1                   交互式安装向导
├── setup-openclaw.ps1            OpenClaw 安装和配置向导
│
├── tests/
│   └── relay.tests.ps1           31 个 Pester 测试
│
├── tools/
│   ├── lib/
│   │   ├── config.ps1            共享路径模块
│   │   └── secret-utils.ps1      共享脱敏模块
│   │
│   ├── cc-command.ps1            命令路由器 (13 条路由, if/elseif 链)
│   ├── cc-run.ps1                编辑模式入口
│   ├── cc-run-big.ps1            大任务模式入口
│   ├── cc-status.ps1             当前 relay 任务状态
│   ├── cc-last.ps1               最近 relay 执行摘要
│   ├── cc-session.ps1            已注册会话列表
│   ├── cc-session-add.ps1        注册新会话
│   ├── cc-use.ps1                切换工作会话
│   ├── cc-project.ps1            多项目管理 (list/use)
│   ├── cc-health.ps1             全链路健康检查
│   ├── oc-session.ps1            OpenClaw 运行时检查
│   │
│   ├── claude-code-relay.ps1     核心安全中继 (文件锁 + 日志轮转 + 自动重试)
│   ├── claude-code-summary.ps1   摘要生成器
│   ├── mobile-status.ps1         项目状态报告
│   ├── feishu-progress-command.ps1 飞书进度上报包装
│   ├── unity-log-summary.ps1     Unity 日志扫描
│   └── verify-pipeline.ps1       管线验证脚本
│
├── .claude/
│   ├── settings.example.json     Claude Code 权限配置模板
│   └── rules/
│       ├── SOUL.example.md       OpenClaw Agent SOUL.md 模板
│       └── remote-commands.md    远程指令规则
│
├── .github/
│   ├── workflows/
│   │   └── test.yml              CI: push/PR 自动 Pester 测试
│   ├── ISSUE_TEMPLATE.md
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── CODEOWNERS
│
└── docs/
    ├── architecture.md           完整架构文档 + 数据流图
    ├── pipeline-deep-dive.md     全链路深度拆解
    ├── scripts-reference.md      已废弃 (以 README 为准)
    ├── configuration.md          所有配置文件字段说明
    ├── installation.md           新电脑从零安装指南
    ├── deployment.md             从零部署 (含故障排除)
    ├── operations.md             日常操作 + 排障指南
    └── improvement-roadmap.md    改进路线 (已完成 7 项, 剩余 6 项)
```

---

## 常见问题

### 飞书发消息没反应

**1. 确认 gateway 在跑**

终端应持续显示 `[heartbeat] started`，不能退出。

**2. 确认飞书频道已连接**

启动日志里必须有：
```
[feishu] connecting...
[feishu] connected
```

没有的话：

```powershell
# 检查插件状态
openclaw plugins list
# feishu 必须在 allowlist 且 enabled

# 如果 missing from allowlist
openclaw config set plugins.allow --json "[""deepseek"",""memory-core"",""feishu""]"

# 如果 disabled
openclaw plugins enable feishu
openclaw config set channels.feishu.enabled true
```

**3. 确认 API Key 已设置**

启动 gateway 前必须在同一个终端：
```powershell
$env:DEEPSEEK_API_KEY="sk-你的key"
```

### 任务执行超时

`/cc-run` 默认 20 分钟超时。大任务用 `/cc-run-big`（无超时限制）。

### Claude Code CLI 报错

```powershell
claude --version
# 确认已安装: npm install -g @anthropic-ai/claude-code
```

### 路径校验失败

`config.json` 里的 `projectRoot` 必须存在。worktree 路径必须在 `worktreesRoot` 下。

### 卸载

```powershell
# 删除本项目
Remove-Item -Recurse F:\DONT_SITDOWN

# 删除 OpenClaw（可选）
npm uninstall -g openclaw
Remove-Item -Recurse $env:USERPROFILE\.openclaw
```

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [docs/architecture.md](docs/architecture.md) | 完整架构 + 数据流图 + 安全层级 |
| [docs/scripts-reference.md](docs/scripts-reference.md) | 每个脚本的参数、流程、边界情况 |
| [docs/configuration.md](docs/configuration.md) | config.json / openclaw.json / cc-target.json 字段全解 |
| [docs/admin-manual.md](docs/admin-manual.md) | Project / Session / Target 的增删改查操作手册 |
| [docs/deployment.md](docs/deployment.md) | 从零到飞书可用的逐步指南 |
| [docs/installation.md](docs/installation.md) | 新电脑从零安装指南 |
| [docs/operations.md](docs/operations.md) | 日常操作、会话管理、排障 |
| [docs/improvement-roadmap.md](docs/improvement-roadmap.md) | 已知问题 + 优先级改进计划 |

---

## License

MIT — [LICENSE](LICENSE)
