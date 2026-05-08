# 架构文档

## 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                        飞书 App                              │
│                    (用户发送消息/命令)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTP Webhook
                       ▼
┌─────────────────────────────────────────────────────────────┐
│               OpenClaw Agent (Node.js)                       │
│         F:\Claude Code\tools\openclaw\openclaw.mjs          │
│                                                              │
│  - 接收飞书消息                                              │
│  - 解析 /cc 前缀命令                                         │
│  - 调用 PowerShell 路由脚本                                  │
│  - 将结果返回飞书                                            │
└──────────────────────┬──────────────────────────────────────┘
                       │ 调用 PowerShell
                       ▼
┌─────────────────────────────────────────────────────────────┐
│             cc-command.ps1 (命令路由器)                      │
│          F:\Unity6_AI\tools\cc-command.ps1                   │
│                                                              │
│  解析命令:                                                   │
│    /cc-run <任务>    → claude-code-relay.ps1 -AllowEdit       │
│    /cc-run-big <任务> → claude-code-relay.ps1 -AllowEdit      │
│    /cc <消息>        → claude-code-relay.ps1 -RawPassThrough │
│    /cc-status        → cc-status.ps1                         │
│    /cc-last          → cc-last.ps1                           │
│    /cc-session       → cc-session.ps1                        │
│    /cc-use <名称>    → cc-use.ps1                            │
│    /cc-project-list  → cc-project.ps1 -Action list           │
│    /cc-project-use   → cc-project.ps1 -Action use            │
│    /cc-health        → cc-health.ps1 -Brief                  │
│    /oc-session       → oc-session.ps1                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
          ┌────────────┼──────────────┐
          ▼            ▼              ▼
  状态/会话查询   只读查询         可编辑任务
  (直接输出)   -RawPassThrough   -AllowEdit
          │            │              │
          └────────────┼──────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────┐
│          claude-code-relay.ps1 (安全中继)                    │
│        F:\Unity6_AI\tools\claude-code-relay.ps1              │
│                                                              │
│  1. 包装 Prompt + 安全规则                                   │
│  2. Git 快照 (before)                                       │
│  3. 启动 claude CLI 子进程 (PowerShell Job + 超时)           │
│  4. Git 快照 (after) + 变更对比                              │
│  5. 密钥脱敏                                                 │
│  6. 生成摘要 (claude-code-summary.ps1)                       │
│  7. 写入日志: prompt / output / meta / summary               │
└──────────────────────┬──────────────────────────────────────┘
                       │ --allowedTools / --disallowedTools
                       ▼
┌─────────────────────────────────────────────────────────────┐
│               Claude Code CLI (claude -p)                    │
│              DeepSeek API 后端 (Anthropic 兼容)              │
│                                                              │
│  模型: deepseek-v4-pro[1m]                                   │
│  工作目录: F:\Unity6_AI (或 worktree)                        │
│  工具: Read / Glob / Grep / Edit / Write / Bash (受控)       │
└─────────────────────────────────────────────────────────────┘
```

## 三种执行模式

### 1. 只读模式 (raw / 默认)

- 触发: `/cc <消息>` 或 `/cc-run <消息>` 的默认模式
- `--allowedTools`: `Read,Glob,Grep,Bash(git status:*),Bash(git log:*)`
- 禁止任何文件修改
- Prompt 尾部要求输出：已完成 / 发现的问题 / 下一步建议

### 2. 编辑模式 (allow-edit)

- 触发: `/cc-run <任务>`
- `--allowedTools`: `Read,Glob,Grep,Edit,Write,Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(powershell ...\tools\*:*)`
- `--disallowedTools`: `Bash(git push:*),Bash(Remove-Item:*),Bash(del:*),Bash(rmdir:*),Bash(rm:*)`
- Prompt 包装包含完整安全边界说明
- 执行后附加文件变更摘要

### 3. 大任务模式 (cc-run-big)

- 触发: `/cc-run-big <任务>`
- 调用 `claude-code-relay.ps1 -AllowEdit -MaxMinutes 0`
- 无超时限制
- 仍保留 relay 的 workspace 校验、工具白名单/黑名单、脱敏和审计

## 安全架构

### 层级防线

```
Layer 0: 项目注册白名单
  └─ ~/.openclaw/cc-projects.json 定义允许的 workspace 列表
     未注册路径 → relay 拒绝执行

Layer 1: OpenClaw 消息解析
  └─ SOUL.md 直通，只响应 /cc 前缀命令

Layer 2: cc-command.ps1 路由
  └─ 13 条路由，全部经过 relay 脚本

Layer 3: claude-code-relay.ps1 包装
  ├─ workspace 校验 (已注册项目白名单 + worktrees)
  ├─ FileStream 排他锁 (防止并发修改)
  ├─ --allowedTools / --disallowedTools 白名单/黑名单
  ├─ Prompt 注入安全规则到 claude 上下文
  └─ 自动重试 (网络/API 瞬时错误, 2次, 10s间隔)

Layer 4: Claude Code 工具层
  └─ allowedTools / disallowedTools 实际拦截

Layer 5: 事后审计
  ├─ Git 快照 before/after (SHA256)
  ├─ 密钥脱敏 (10 种模式, 共享 lib/secret-utils.ps1)
  ├─ 结构化日志 (prompt/output/meta/summary)
  └─ 日志 30 天自动轮转
```

### Workspace 隔离

- 允许范围: `~/.openclaw/cc-projects.json` 中注册的所有项目及其 `*.worktrees\*`
- 校验函数: `Test-PathInsideRoot`，使用 `System.IO.Path.GetFullPath` 防止 `..\..\` 逃逸
- 多项目支持: 通过 `/cc-project-use` 切换项目，通过 `/cc-use` 切换分支
- projectRoot / WorktreesRoot 从 `config.json` 和 `cc-projects.json` 双重读取

### 密钥脱敏

10 种正则模式覆盖:
- Anthropic: `sk-ant-*`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`
- OpenAI: `OPENAI_API_KEY`
- DeepSeek: `DEEPSEEK_API_KEY`
- Feishu: `FEISHU_APP_SECRET`, `appSecret`, `App Secret`
- Claude: `CLAUDE_TOKEN`

## 数据流: 一次完整的 /cc-run

```
输入:
  /cc-run 修复 EnemyFSM.cs 第45行空引用

1. OpenClaw 解析 → 调用:
   powershell -File cc-command.ps1 -MessageText "/cc-run 修复..."

2. cc-command.ps1 路由:
   匹配 "/cc-run" → 调用:
   powershell -File claude-code-relay.ps1 -PromptText "修复..." -AllowEdit

3. claude-code-relay.ps1:
   a. Ensure-TargetConfig → 读 .openclaw/cc-target.json
   b. Resolve-RelayWorkspace → 校验 workspace
   c. 检查 current-task.json → 是否已有任务在跑
   d. git status --short → 快照 before
   e. 生成 WrappedTask (安全规则 + 原始 Prompt)
   f. Start-Job → claude -p "$WrappedTask" --allowedTools ... --disallowedTools ...
   g. Wait-Job -Timeout 1200 (20min)
   h. git status --short → 快照 after
   i. Compare-GitStatusSnapshots → 变更列表
   j. Redact-Secrets → 输出脱敏
   k. claude-code-summary.ps1 → 摘要
   l. 写 current-task.json (completed/failed)

4. cc-command.ps1 → 读取 Summary Log → 返回脱敏文本

5. OpenClaw → 飞书消息 (摘要文本)
```

## 文件布局

```
F:\Unity6_AI\
├── tools/                          # 所有管线脚本
│   ├── claude-code-relay.ps1       ★ 核心中继 (599行)
│   ├── cc-command.ps1              ★ 命令路由器
│   ├── cc-run.ps1                  编辑模式入口
│   ├── cc-run-big.ps1              大任务模式
│   ├── cc-status.ps1               任务状态查询
│   ├── cc-last.ps1                 最近摘要查询
│   ├── cc-session.ps1              会话列表
│   ├── cc-session-add.ps1          注册会话
│   ├── cc-use.ps1                  切换当前会话
│   ├── cc-project.ps1              多项目管理
│   ├── cc-health.ps1               管线健康检查
│   ├── claude-code-summary.ps1     摘要生成器
│   ├── feishu-progress-command.ps1 飞书进度上报
│   ├── mobile-status.ps1           移动端状态报告
│   ├── oc-session.ps1              OpenClaw 会话
│   └── unity-log-summary.ps1       Unity 日志摘要
├── .openclaw/                     # OpenClaw 配置
│   ├── cc-target.json             当前会话/workspace
│   └── cc-sessions.json           已注册会话列表
├── .claude/
│   ├── settings.local.json        工具权限
│   ├── rules/remote-commands.md   远程指令规则
│   └── commands/progress.md       进度命令模板
└── Logs/ClaudeRelay/              执行日志
    ├── {runId}-prompt.txt          原始提示词
    ├── {runId}-output.txt          脱敏输出
    ├── {runId}-meta.json           元数据
    ├── {runId}-summary.txt         摘要
    └── current-task.json           当前任务状态
```

## 关键设计细节

### Git 变更检测

使用 `git status --short` + SHA256 校验和:
- Before: 记录每个文件的 path → status + hash
- After: 同上
- 对比: 新增 / 修改（hash 变化）/ 删除
- 输出: 飞书消息底部追加变更文件列表

### 超时机制

使用 PowerShell Job + Wait-Job -Timeout:
- 默认 20 分钟 (MaxMinutes=20)
- 超时后 Stop-Job，退出码 124
- 大任务模式无超时

### 并发控制

通过 `current-task.json` 互斥:
- status="running" → 拒绝新任务 (exit 4)
- status="completed"/"failed" → 允许
- 只检查不锁定（有微小竞态窗口）
