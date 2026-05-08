# 日常操作手册

## 命令速查表

| 飞书命令 | 示例 | 用途 |
|----------|------|------|
| `/cc <问题>` | `/cc 最近3次提交改了哪些文件` | 只读查询 |
| `/cc-run <任务>` | `/cc-run 给 EnemyFSM.cs 添加状态转换日志` | 编辑文件 |
| `/cc-run-big <任务>` | `/cc-run-big 重构整个 AI/ 目录` | 大型编辑 |
| `/cc-status` | - | 当前任务状态 |
| `/cc-last` | - | 最近执行摘要 |
| `/cc-session` | - | 列出所有会话 |
| `/cc-use <名称>` | `/cc-use unity6ai-m1` | 切换到 M1 会话 |
| `/cc-session-add <名称> <路径>` | `/cc-session-add unity6ai-m2 F:\Unity6_AI.worktrees\m2` | 注册新会话 |


## 典型工作流

### 场景 1: 查看项目状态

```
/cc-status
/cc 列出 docs/status/ 下的文件和最近更新
/cc-last
```

### 场景 2: 修复 Bug

```
/cc-run 修复 EnemyFSM.cs 第 45 行空引用异常，
添加 null check 并记录警告日志
```

回复示例:
```
状态: 已完成
模式: allow-edit

变更文件摘要:
新增文件: 无
修改文件:
- UnityProject/Assets/_Project/Scripts/AI/EnemyFSM.cs
删除文件: 无

摘要:
已完成: 在 EnemyFSM.cs 添加 null 检查...
```

### 场景 3: 切换开发分支

```
# 查看可用会话
/cc-session

# 切换到 M1 开发分支
/cc-use unity6ai-m1

# 在 M1 分支上执行任务
/cc-run 给 EnemyPatrolState 添加 NavMesh 路径缓存
```

### 场景 4: 文档整理

```
/cc-run 更新 PROGRESS.md，记录 M1 FSM 模块已完成
/cc-run 把今天的修改总结写入 AI_DEV_LOG.md
```

### 场景 5: 大型重构

```
/cc-run-big 将 Assets/_Project/Scripts/AI/ 下的所有
public 字段改为 [SerializeField] private
```

⚠️ 大任务模式不经过 relay 安全防护，谨慎使用。

## 会话管理

### 会话是什么

一个"会话"绑定一个 workspace (通常是不同分支的 worktree)，用于隔离不同里程碑的开发工作。

### 查看当前选中

```
/cc-status
```
输出 `目标会话: unity6ai-main` 表示当前在主线。

### 创建新会话

先在 Windows 终端创建 worktree:
```powershell
git worktree add -b milestone/m2-behavior F:\Unity6_AI.worktrees\m2-behavior
```

然后在飞书注册:
```
/cc-session-add unity6ai-m2 F:\Unity6_AI.worktrees\m2-behavior -GitBranch milestone/m2-behavior -Role "M2行为树开发"
```

### 切换会话

```
/cc-use unity6ai-m2
```

### 移除会话

## 日志查询

每次 relay 执行在 `Logs/ClaudeRelay/` 生成四个文件:

```powershell
# 查看最近执行列表
dir F:\Unity6_AI\Logs\ClaudeRelay\ | Sort-Object LastWriteTime -Descending

# 查看特定执行的摘要
type F:\Unity6_AI\Logs\ClaudeRelay\{runId}-summary.txt

# 查看特定执行的完整输出
type F:\Unity6_AI\Logs\ClaudeRelay\{runId}-output.txt

# 查看执行的元数据 (JSON)
type F:\Unity6_AI\Logs\ClaudeRelay\{runId}-meta.json
```

## 排障指南

### 飞书发送命令无响应

1. 确认 OpenClaw gateway 在运行，终端应显示 `[heartbeat] started`
2. 确认终端有 `[feishu] connected` 日志
3. 如果没有 `[feishu] connecting`：`openclaw plugins list` — feishu 必须在 allowlist 且 enabled
4. 插件被 allowlist 阻止：`openclaw config set plugins.allow --json "[""deepseek"",""memory-core"",""feishu""]"`
5. 频道未启用：`openclaw config set channels.feishu.enabled true`
6. 确认 `$env:DEEPSEEK_API_KEY` 在启动 gateway 前已设置

### 任务执行超时

reply 输出:
```
Claude Code invocation timed out after 20 minute(s).
```

**原因**: 任务超过 20 分钟。

**解决**:
- 将任务拆分成多个较小的 `/cc-run`
- 或使用 `/cc-run-big` (无超时限制，但无安全防护)

### 任务执行失败

```
状态: 执行失败, 退出码 1
```

**解决**:
1. 查看完整输出: `type Logs\ClaudeRelay\{runId}-output.txt`
2. 检查错误类型:
   - `exit 4`: 已有任务在运行，等待完成
   - `exit 3`: 项目根目录未找到
   - `exit 124`: 超时
   - `exit 127`: Claude CLI 未安装

### 文件修改没有保存

1. 确认使用的是 `/cc-run` 而非 `/cc`（/cc 是只读模式）
2. 查看 `-summary.txt` 中的变更文件列表
3. 确认 relay 的 `--allowedTools` 包含 Edit/Write

### 无法切换会话

```
未找到会话记录: xxx
```

**解决**:
1. `/cc-session` 查看已注册会话列表
2. 确认名称拼写正确 (大小写不敏感)
3. 用 `/cc-session-add` 注册新会话

### Workspace 安全错误

```
安全限制: workspace 只允许位于 F:\Unity6_AI 或 F:\Unity6_AI.worktrees 下
```

**原因**: 试图使用不在允许范围内的路径。

**解决**: 确保 worktree 创建在 `F:\Unity6_AI.worktrees\` 下。

## 最佳实践

1. **小而频繁**: 优先使用 `/cc-run` 提交小任务（5-10 分钟），而不是一个大任务
2. **先查后改**: 不确定文件位置时，先用 `/cc` 查询，再用 `/cc-run` 修改
3. **一次一件事**: 每个 `/cc-run` 只做一件事，方便追踪和回滚
4. **检查摘要**: 每次执行后看 `/cc-last` 确认变更符合预期
5. **分支隔离**: 不同里程碑用 `/cc-use` 切换 worktree，避免交叉污染
6. **不用 big 模式**: 除非任务确实需要超过 20 分钟且你充分信任该任务，否则不要用 `/cc-run-big`
