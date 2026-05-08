# 项目与会话管理手册

本文说明 Feishu-CC 管线里 project、session、target 的日常管理方式。

核心原则：

- Project 是允许 Claude Code 操作的项目白名单。
- Session 是某个项目里的开发会话，通常对应主线 workspace 或某个 git worktree。
- Target 是当前选中的执行目标，由 `/cc-project-use` 和 `/cc-use` 更新。
- 出于安全原因，project 新增/删除必须在电脑本机手动编辑 JSON，不通过飞书远程添加。

## 文件位置

| 文件 | 作用 |
|------|------|
| `~\.openclaw\cc-projects.json` | 已注册 project 白名单 |
| `<project>\.openclaw\cc-sessions.json` | 当前 project 的 session 列表 |
| `<project>\.openclaw\cc-target.json` | 当前选中的 project/session/workspace |
| `<project>\config.json` | 管线基础配置 |

示例中 `~` 表示 `C:\Users\<你的用户名>`。

## Project 管理

### 查看已注册项目

飞书发送：

```text
/cc-project-list
```

输出里带 `>` 的项目是当前活跃项目。

### 添加 Project

Project 不支持通过飞书远程添加。请在电脑本机编辑：

```powershell
notepad $env:USERPROFILE\.openclaw\cc-projects.json
```

示例：

```json
[
  {
    "name": "unity6-ai",
    "workspace": "F:\\Unity6_AI",
    "worktreesRoot": "F:\\Unity6_AI.worktrees",
    "active": true,
    "description": "Unity 6 AI 项目",
    "updatedAt": "2026-05-08T21:10:02+08:00"
  },
  {
    "name": "dont-sitdown",
    "workspace": "F:\\DONT_SITDOWN",
    "worktreesRoot": "F:\\DONT_SITDOWN.worktrees",
    "active": false,
    "description": "Feishu-CC 管线",
    "updatedAt": "2026-05-08T21:10:02+08:00"
  }
]
```

字段说明：

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 飞书里使用的项目名，例如 `/cc-project-use dont-sitdown` |
| `workspace` | 是 | 项目根目录，必须真实存在 |
| `worktreesRoot` | 是 | 该项目允许使用的 worktree 根目录 |
| `active` | 是 | 是否当前活跃；同一时间建议只有一个为 `true` |
| `description` | 否 | `/cc-project-list` 展示说明 |
| `updatedAt` | 否 | 更新时间，ISO 字符串即可 |

保存后在飞书验证：

```text
/cc-project-list
```

### 切换 Project

飞书发送：

```text
/cc-project-use dont-sitdown
```

效果：

- 将 `~\.openclaw\cc-projects.json` 中目标 project 标记为 `active: true`。
- 将其他 project 标记为 `active: false`。
- 更新当前 project 的 `.openclaw\cc-target.json`。

### 删除 Project

Project 删除也只建议本机手动执行：

1. 如果要删除的是当前活跃项目，先切到其他项目：

```text
/cc-project-use unity6-ai
```

2. 打开注册表：

```powershell
notepad $env:USERPROFILE\.openclaw\cc-projects.json
```

3. 删除对应 project 对象。

4. 确认剩余列表里至少有一个项目 `active: true`。

5. 飞书验证：

```text
/cc-project-list
/cc-health
```

不要删除真实项目目录，除非你已经备份并确认不再需要。这里的“删除 Project”只指从白名单注册表移除。

## Session 管理

### 查看 Session

飞书发送：

```text
/cc-session
```

输出包含：

- session 名称
- 状态
- 角色说明
- git 分支
- 当前选中项

### 添加主线 Session

如果 session 指向项目根目录：

```text
/cc-session-add main F:\Unity6_AI -GitBranch main -Role "主线：查看状态、整理文档、轻量修改"
```

注意：

- `Name` 不能和已有 session 重名。
- `Workspace` 必须存在。
- `Workspace` 必须位于当前 project 根目录或 `worktreesRoot` 下。

### 添加 Worktree Session

先在电脑本机创建 worktree：

```powershell
cd F:\Unity6_AI
git worktree add -b milestone/m2-behavior F:\Unity6_AI.worktrees\m2-behavior
```

再在飞书注册：

```text
/cc-session-add unity6ai-m2 F:\Unity6_AI.worktrees\m2-behavior -GitBranch milestone/m2-behavior -Role "M2 行为树开发"
```

验证：

```text
/cc-session
```

### 切换 Session

飞书发送：

```text
/cc-use unity6ai-m2
```

效果：

- 更新 `<project>\.openclaw\cc-target.json`。
- 后续 `/cc`、`/cc-run`、`/cc-run-big` 会使用该 session 的 workspace。

### 删除 Session

当前没有 `/cc-session-remove` 远程命令。请本机手动编辑：

```powershell
notepad F:\Unity6_AI\.openclaw\cc-sessions.json
```

删除对应对象，例如：

```json
{
  "name": "unity6ai-m2",
  "session": "",
  "workspace": "F:\\Unity6_AI.worktrees\\m2-behavior",
  "gitBranch": "milestone/m2-behavior",
  "role": "M2 行为树开发",
  "status": "idle",
  "updatedAt": "2026-05-08T21:10:02+08:00"
}
```

如果删除的是当前选中的 session，还要切回一个仍存在的 session：

```text
/cc-use main
```

如果这个 session 对应的 git worktree 也不再需要，另行本机删除：

```powershell
cd F:\Unity6_AI
git worktree remove F:\Unity6_AI.worktrees\m2-behavior
git branch -d milestone/m2-behavior
```

只在确认分支已合并或不再需要时删除分支。

### 修改 Session

修改 session 名称、角色、分支说明或 workspace，直接编辑：

```powershell
notepad F:\Unity6_AI\.openclaw\cc-sessions.json
```

修改后验证：

```text
/cc-session
/cc-use <name>
/cc-status
```

## Target 管理

通常不要手动编辑 `cc-target.json`，让命令更新它：

```text
/cc-project-use <project-name>
/cc-use <session-name>
```

需要排查时查看：

```powershell
type F:\Unity6_AI\.openclaw\cc-target.json
```

关键字段：

| 字段 | 说明 |
|------|------|
| `defaultSessionName` | 当前选中的 session 名 |
| `defaultSession` | Claude Code session ID，通常可为空 |
| `workspace` | 当前执行 workspace |
| `gitBranch` | 当前分支说明 |
| `mode` | 默认 `readonly` |
| `updatedAt` | 最近更新时间 |

## 常见操作流程

### 新增一个项目并切换过去

1. 本机编辑 `~\.openclaw\cc-projects.json`，添加 project。
2. 飞书发送 `/cc-project-list` 确认出现。
3. 飞书发送 `/cc-project-use <name>` 切换。
4. 飞书发送 `/cc-health` 检查。

### 新增一个开发分支并开始任务

1. 本机 `git worktree add ...` 创建 worktree。
2. 飞书 `/cc-session-add ...` 注册 session。
3. 飞书 `/cc-use <name>` 切换 session。
4. 飞书 `/cc-run <任务>` 执行编辑。
5. 飞书 `/cc-last` 查看摘要。

### 删除一个不用的开发分支

1. 飞书 `/cc-use main` 切回主线。
2. 本机编辑 `.openclaw\cc-sessions.json` 删除 session。
3. 本机 `git worktree remove ...` 删除 worktree。
4. 本机确认分支可删后 `git branch -d ...`。
5. 飞书 `/cc-session` 验证列表。

## 安全注意事项

- 不要通过飞书让 AI 远程添加 project 白名单。
- 不要把 `workspace` 指向未受信目录、下载目录或系统目录。
- 不要把密钥、token、飞书 app secret 写进任何 project/session JSON。
- 删除 project/session 注册项不会删除真实文件；删除真实目录必须本机确认。
- 一次只切换一个 project 或 session，切换后先跑 `/cc-status` 或 `/cc-health`。
