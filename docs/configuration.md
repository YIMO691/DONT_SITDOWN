# 配置文件手册

## 配置清单

| 文件 | 位置 | 用途 |
|------|------|------|
| `config.json` | 项目根目录 | 主配置 (projectRoot, worktreesRoot 等) |
| `settings.local.json` | `.claude/` | Claude Code 工具权限 |
| `cc-target.json` | `.openclaw/` | 当前目标会话/workspace |
| `cc-sessions.json` | `.openclaw/` | 已注册会话目录 |
| `cc-projects.json` | `~/.openclaw/` | 多项目注册白名单 |
| `openclaw.json` | `~/.openclaw/` | OpenClaw Agent 配置 |
| `SOUL.md` | `~/.openclaw/agents/<name>/agent/` | OpenClaw 直通指令 |
| `remote-commands.md` | `.claude/rules/` | 远程指令规则（Claude 上下文注入） |

---

## .claude/settings.local.json

Claude Code 权限配置，控制哪些 Bash/Read 操作可无需用户确认。

```json
{
  "permissions": {
    "allow": [
      "Bash(claude plugins *)",
      "Bash(git add *)",
      "Bash(git commit -m ' *)",
      "Bash(git push *)",
      "Bash(git pull *)",
      "Bash(git rebase *)",
      "Bash(git fetch *)",
      "Bash(git remote *)",
      "Bash(git rm *)",
      "Read(//c/Users/Administrator/AppData/Local/Programs/**)",
      "Read(//c/Program Files/**)",
      "Read(//c//**)"
    ]
  },
  "enabledPlugins": {
    "github@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true
  }
}
```

**关键项说明**:
- `Bash(git *)`: 允许 git 操作无需确认
- `Read(//c//**):`: 允许读取 C 盘任意文件
- 两个已启用插件: `github` 和 `superpowers`

**⚠️ 注意**: 此配置直接影响 Claude Code 在 relay 模式和普通模式下的权限。与 `claude-code-relay.ps1` 的 `--allowedTools` 是互补关系——前者控制用户确认提示，后者控制工具可用性。

---

## .openclaw/cc-target.json

当前选中的 Claude Code 工作目标，由 `cc-use.ps1` 写入，`claude-code-relay.ps1` 读取。

```json
{
  "defaultSessionName": "unity6ai-main",
  "defaultSession": "",
  "workspace": "F:\\Unity6_AI",
  "gitBranch": "main",
  "mode": "readonly",
  "updatedAt": "2026-05-07T22:00:00.0000000+08:00"
}
```

**字段**:
| 字段 | 说明 |
|------|------|
| `defaultSessionName` | 会话名称（与 cc-sessions.json 的 name 对应） |
| `defaultSession` | Claude Code session ID（直接传给 `--resume`） |
| `workspace` | 工作目录，relay 会校验其合法范围 |
| `gitBranch` | 当前工作分支 |
| `mode` | 预留字段，实际模式由 relay 参数决定 |
| `updatedAt` | 最后切换时间 |

**自动创建**: 首次 relay 执行时，`Ensure-TargetConfig` 会在 `.openclaw/` 目录下自动创建默认配置。

---

## .openclaw/cc-sessions.json

多会话注册表，支持多个 worktree 并行开发。

```json
[
  {
    "name": "unity6ai-main",
    "session": "",
    "workspace": "F:\\Unity6_AI",
    "gitBranch": "main",
    "role": "主线：查看状态、整理文档、轻量修改",
    "status": "idle",
    "updatedAt": "2026-05-07T22:00:00.0000000+08:00"
  },
  {
    "name": "unity6ai-m1",
    "session": "",
    "workspace": "F:\\Unity6_AI.worktrees\\m1-fsm",
    "gitBranch": "milestone/m1-fsm",
    "role": "M1 FSM 开发",
    "status": "idle",
    "updatedAt": "2026-05-07T22:30:00.0000000+08:00"
  }
]
```

**字段**:
| 字段 | 说明 |
|------|------|
| `name` | 唯一会话名称（用于 `/cc-use`） |
| `session` | Claude Code session ID |
| `workspace` | 对应 worktree 路径 |
| `gitBranch` | 对应分支 |
| `role` | 用途说明 |
| `status` | idle / active / archived |
| `updatedAt` | 最后更新时间 |

**管理命令**:
- 添加: `/cc-session-add <Name> <Workspace> [-GitBranch <branch>] [-Role <role>]`
- 会话移除需在终端操作 `tools/cc-session-remove.ps1 -Name <name>`
- 查看: `/cc-session`

**默认保护**: `unity6ai-main` 不可删除。

---

## ~/.openclaw/cc-projects.json

多项目注册白名单，定义管线可以操作的项目列表。relay 执行前校验 workspace 是否在本文件中注册。

**字段说明**:

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `name` | string | ✅ | 项目简称（飞书切换用） |
| `workspace` | string | ✅ | 项目根目录绝对路径 |
| `worktreesRoot` | string | | worktrees 父目录，默认 `workspace.worktrees` |
| `active` | bool | | 是否活跃项目（只有一个为 true） |
| `description` | string | | 项目描述 |
| `updatedAt` | string | | 最后切换时间（ISO 8601） |

**示例**:

```json
[
  {
    "name": "unity6-ai",
    "workspace": "F:\\Unity6_AI",
    "worktreesRoot": "F:\\Unity6_AI.worktrees",
    "active": true,
    "description": "Unity 6 AI 项目"
  },
  {
    "name": "dont-sitdown",
    "workspace": "F:\\DONT_SITDOWN",
    "worktreesRoot": "F:\\DONT_SITDOWN.worktrees",
    "active": false,
    "description": "Feishu-CC 管线"
  }
]
```

**安全约束**: 此文件只能在本机手动编辑，不可通过飞书远程修改。新增未注册项目路径的 workspace 会被 relay 拒绝执行。

**相关命令**:
- 查看: `/cc-project-list`
- 切换: `/cc-project-use <name>`

---

## .openclaw-state/openclaw.json

OpenClaw Agent 的主配置，控制 AI 模型提供者和 Agent 行为。

```json
{
  "models": {
    "providers": {
      "ollama": {
        "api": "ollama",
        "baseUrl": "http://127.0.0.1:11434",
        "apiKey": "ollama-local",
        "models": []
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/qwen2.5-coder:7b"
      }
    }
  }
}
```

**关键项**:
- OpenClaw 本身使用本地 Ollama 模型（`qwen2.5-coder:7b`）处理飞书消息
- Claude Code CLI 使用 DeepSeek 后端（由 `start-claude-deepseek.cmd` 设置环境变量）
- OpenClaw 和 Claude Code 是两个独立的 AI 系统

---

## .claude/rules/remote-commands.md

注入到 Claude Code 会话的远程指令规则。通过 YAML frontmatter 中的 `paths` 字段限定生效范围。

```yaml
---
paths:
  - "tools/cc-run.ps1"
  - "tools/cc-run-big.ps1"
  - "tools/claude-code-relay.ps1"
---
```

**规则要点**:
- OpenClaw Agent 不直接编辑文件
- 文件修改必须通过 Claude Code CLI
- 只读操作可由 Agent 直接执行
- `/cc-run` / `/cc-run-big` 原封不动转述，不做包装
- 禁止 git push / 删除文件 / 输出密钥

---

## 配置交互关系

```
cc-projects.json ──→ claude-code-relay.ps1
  (项目白名单)          (安全校验 workspace)

cc-sessions.json ──→ cc-use.ps1 ──→ cc-target.json
  (会话注册表)          (切换会话)      (当前目标)
                                         │
cc-project.ps1 ──────────────────────────┘
  (切换项目, 更新 workspace)

cc-target.json ──→ claude-code-relay.ps1
  (当前目标)          (读取 workspace/session)

settings.local.json ──→ Claude Code CLI
  (工具权限)               (实际执行)
```
