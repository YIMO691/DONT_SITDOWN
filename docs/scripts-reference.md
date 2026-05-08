# 脚本参考手册

## 总览

共 16 个 PowerShell 脚本，分为五层：

| 层 | 脚本 | 职责 |
|----|------|------|
| 入口路由 | `cc-command.ps1` | 解析飞书命令，分发到对应脚本 |
| 执行入口 | `cc-run.ps1`, `cc-run-big.ps1` | 编辑/大任务两种模式入口 |
| 核心中继 | `claude-code-relay.ps1` | 安全包装、执行、审计 |
| 支持工具 | `cc-status.ps1`, `cc-last.ps1`, `cc-session.ps1`, `cc-use.ps1`, `cc-session-add.ps1`, `cc-project.ps1`, `cc-health.ps1` | 状态查询、会话管理、多项目管理与健康检查 |
| 辅助输出 | `claude-code-summary.ps1`, `mobile-status.ps1`, `feishu-progress-command.ps1`, `unity-log-summary.ps1`, `oc-session.ps1` | 摘要生成与状态报告 |

---

## 入口路由层

### cc-command.ps1

**职责**: 解析飞书消息中的 `/cc` 命令，路由到对应处理脚本。

**参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `-MessageText` | string | 飞书原始消息文本 |

**路由表**:
| 输入 | 目标脚本 | 模式 |
|------|----------|------|
| `/cc-status` | cc-status.ps1 | 直接输出 |
| `/cc-last` | cc-last.ps1 | 直接输出 |
| `/cc-session-add <name> <path>` | cc-session-add.ps1 | 直接输出 |
| `/cc-session` | cc-session.ps1 | 直接输出 |
| `/cc-use <name>` | cc-use.ps1 -Session \<name\> | 直接输出 |
| `/cc-run-big <task>` | claude-code-relay.ps1 -AllowEdit -MaxMinutes 0 | 大任务编辑模式 |
| `/cc-run <task>` | claude-code-relay.ps1 -AllowEdit | 编辑模式 |
| `/cc-project-list` | cc-project.ps1 -Action list | 直接输出 |
| `/cc-project-use <name>` | cc-project.ps1 -Action use -Name \<name\> | 直接输出 |
| `/cc-health` | cc-health.ps1 -Brief | 直接输出 |
| `/oc-session` | oc-session.ps1 | 直接输出 |
| `/cc-help` | 内置帮助文本 | 直接输出 |
| `/cc <message>` | claude-code-relay.ps1 -RawPassThrough | 只读模式 |
| 其他命令 | 返回 `/cc-help` 提示 | - |

路由使用精确边界匹配，`/cc-run-big` 在 `/cc-run` 之前判断，避免前缀误匹配。

---

## 执行入口层

### cc-run.ps1

**职责**: 编辑模式入口。将用户任务转发给 `claude-code-relay.ps1 -AllowEdit`。

**参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `-PromptText` | string | 用户任务描述 |

**流程**:
1. 检查 PromptText 非空
2. 调用 `claude-code-relay.ps1 -PromptText $PromptText -AllowEdit`
3. 读取 relay 生成的 Summary Log
4. 脱敏后输出

**返回**: relay 的 exit code

---

### cc-run-big.ps1

**职责**: 大任务模式。通过 `claude-code-relay.ps1 -AllowEdit -MaxMinutes 0` 执行，无时间上限但仍保留 relay 安全防护。

**参数**: 通过 `$args` 接收

**流程**:
1. 拼接参数为 prompt 文本
2. 保存 prompt 到 `Logs/ClaudeRelay/bigtask-{timestamp}.txt`
3. 调用 `claude-code-relay.ps1 -PromptText <task> -AllowEdit -MaxMinutes 0`

**安全**: 仍经过 relay 的 workspace 校验、工具白名单/黑名单、脱敏和审计；区别是没有超时上限。

---

## 核心中继层

### claude-code-relay.ps1

**职责**: 整个管线的核心。包装用户任务、设置安全边界、执行 Claude Code、记录审计日志。

**参数**:
| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `-PromptText` | string (必需) | - | 用户任务原文 |
| `-Session` | string | 空 | 目标 Claude Code 会话 ID/名称 |
| `-RawPassThrough` | switch | false | 只读直通模式（不包装安全规则） |
| `-Readonly` | switch | false | 只读模式 |
| `-AllowEdit` | switch | false | 允许编辑 |
| `-MaxMinutes` | int | 20 | 超时时间（分钟） |

**模式互斥规则**:
- `AllowEdit` 和 `Readonly` 不能同时使用
- `AllowEdit` 和 `RawPassThrough` 不能同时使用

**执行流程** (599 行):

```
1. 参数校验 (283-307)
   ├─ PromptText 非空
   ├─ 模式互斥检查
   └─ 项目根目录存在性

2. 准备阶段 (309-346)
   ├─ 创建 Logs/ClaudeRelay 目录
   ├─ Set-Location 到项目根目录
   ├─ Ensure-TargetConfig
   ├─ 检查 current-task.json (并发互斥)
   ├─ 生成 RunId (yyyyMMdd-HHmmss-fff)
   └─ 创建日志文件路径

3. Prompt 包装 (349-418)
   ├─ AllowEdit: 完整安全规则 + 执行要求
   ├─ RawPassThrough: 原样传递
   └─ 默认/Readonly: 只读约束 + 输出格式

4. 工具权限 (420-433)
   ├─ 只读: Read,Glob,Grep,Bash(git *),Bash(mobile-status)
   ├─ 编辑: + Edit,Write,Bash(git diff),Bash(tools/*)
   └─ 禁止: Bash(git push),Bash(Remove-Item),Bash(del/rmdir/rm)

5. 执行 (434-521)
   ├─ Git 快照 before
   ├─ Start-Job → claude -p $WrappedTask --allowedTools --disallowedTools
   ├─ Wait-Job -Timeout (MaxMinutes * 60 秒)
   ├─ 超时 → Stop-Job, exit 124
   └─ 成功 → 收集输出

6. 后处理 (523-597)
   ├─ Git 快照 after
   ├─ Compare-GitStatusSnapshots
   ├─ Redact-Secrets (输出脱敏)
   ├─ 写 output.txt
   ├─ 写 meta.json (完整元数据)
   ├─ 调用 claude-code-summary.ps1
   ├─ AllowEdit 模式下追加文件变更摘要
   ├─ 更新 current-task.json (completed/failed)
   └─ 输出最终摘要
```

**Prompt 包装模板 (编辑模式)**:

```
You are executing a remote Feishu task inside {workspace}.

User original task:
<USER_PROMPT>
{用户任务原文}
</USER_PROMPT>

Work mode: editing project files is allowed, but only within strict safety boundaries.

Allowed:
- Modify normal source files, documentation, and configuration files
- Run read-only inspection commands
- Run necessary local test commands when they are safe
- Modify Unity project files when directly relevant to the task
- Update PROGRESS.md, TODO.md, and AI_DEV_LOG.md

Forbidden:
- Do not run git push
- Do not delete the project directory
- Do not run recursive delete commands
- Do not expose any API Key, Token, App Secret, password, or credential
- Do not modify OpenClaw, Claude Code, or DeepSeek secret configuration
- Do not write secrets into any files
- Do not install unknown global tools
- Do not change Windows system-level settings
- Do not create git commits unless explicitly allowed

Execution requirements:
1. Read the project status first
2. Make a short plan
3. Only change files directly related to the user's task
4. After editing, list the files changed
5. Run safe tests if possible; if not possible, explain why
6. End with sections: Completed work, Modified files, Verification result, Remaining issues, Next steps
```

**Git 快照函数**:
- `Get-GitStatusSnapshot`: 解析 `git status --short`，计算每个文件 SHA256
- `Compare-GitStatusSnapshots`: 对比 before/after，输出 added/modified/deleted 三类列表
- `Format-ChangeSummary`: 格式化为飞书可读文本

**安全函数**:
- `Redact-Secrets`: 10 种正则脱敏
- `Test-PathInsideRoot`: workspace 逃逸检测
- `Resolve-RelayWorkspace`: 校验 workspace 合法性

**状态追踪**:
- `Write-CurrentTask` / `Read-CurrentTask`: 维护 `current-task.json`
- 状态机: running → completed | failed

---

## 支持工具层

### cc-status.ps1

**职责**: 显示当前任务状态。

**输出字段**:
- 当前任务 (prompt 前 80 字符)
- 目标会话 (sessionName 或 session ID)
- workspace 路径
- git 分支
- 开始时间
- 状态 (running / completed / failed)
- 退出码
- 最近输出 (摘要后 240 字符)

**边界情况**: 无 current-task.json → 输出"暂无 Claude Code relay 任务"

---

### cc-last.ps1

**职责**: 显示最近一次 relay 执行的摘要。

**逻辑**: 按 LastWriteTime 降序排列 `*-summary.txt`，读取最新的一个。

---

### cc-session.ps1

**职责**: 列出所有注册的 Claude Code 会话。

**数据源**: `.openclaw/cc-sessions.json`

**输出**: 每个会话的 name, status, role, branch, updatedAt + 当前选中项。

---

### cc-session-add.ps1

**职责**: 注册一个新的开发会话（对应一个 worktree）。

**参数**:
| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `-Name` | string | 是 | 会话名称 |
| `-Workspace` | string | 是 | workspace 路径 |
| `-GitBranch` | string | 否 | git 分支名 |
| `-Role` | string | 否 | 会话角色描述 |
| `-Session` | string | 否 | Claude Code session ID |

**安全**: 校验 workspace 必须在允许范围内。不接受范围外的路径。

**默认会话**: 首次创建时自动生成 `unity6ai-main` 默认条目。

---

### cc-use.ps1

**职责**: 切换当前工作会话。

**参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `-Session` | string | 会话名称或 Claude Code session ID |

**行为**:
- 先在 `cc-sessions.json` 中按名称查找
- 找到 → 使用注册的 configuration
- 未找到 → 将输入当作 session ID 直接使用
- 更新 `cc-target.json`

---

### cc-project.ps1

**职责**: 列出和切换已注册项目。

**参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `-Action` | string | `list` 或 `use` |
| `-Name` | string | 切换目标项目名称 |

**数据源**: `~\.openclaw\cc-projects.json`

**行为**:
- `list` → 输出所有已注册项目和当前活跃项目
- `use` → 切换活跃项目并更新 `cc-target.json`
- 未注册项目不能通过飞书远程添加，需要本机手动编辑注册表

---

### cc-health.ps1

**职责**: 检查 Feishu-CC 管线的关键依赖和运行状态。

**参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `-Brief` | switch | 输出适合飞书查看的简短健康检查 |

**检查项**: Git、Claude CLI、DeepSeek API、workspace、日志目录、任务状态、配置文件。

---

## 辅助输出层

### claude-code-summary.ps1

**职责**: 从 relay 输出生成结构化摘要。

**参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `-OutputPath` | string | relay 输出文件路径 |
| `-MetaPath` | string | relay 元数据文件路径 |
| `-SummaryPath` | string | 摘要输出路径 |

**摘要格式**:
```
状态: 已完成 (或 状态: 执行失败, 退出码 N)
运行 ID: {runId}
目录: {projectRoot}
模式: {mode}

摘要:
{输出最后 1800 字符}

日志:
- 输出: {outputPath}
- 元数据: {metaPath}
```

**RawPassThrough 模式**: 直接返回输出最后 4000 字符，跳过格式化。

---

### mobile-status.ps1

**职责**: 生成 Unity6_AI 项目状态报告，适合移动端查看。

**输出章节**:
1. Unity 项目结构检查
2. Git 分支
3. 最近 5 次提交
4. 工作树状态
5. PROGRESS.md 内容
6. TODO.md 内容
7. AI_DEV_LOG.md 最近内容
8. Unity 日志 (EditModeBatch.log, EditModeResults.xml, UnityBatch.log)
9. 错误扫描 (error CS, Exception, Failed, FAIL, NullReferenceException)

---

### feishu-progress-command.ps1

**职责**: 包装 mobile-status 输出，添加飞书格式头。

**用法**: Claude Code command `/progress` 调用。

---

### unity-log-summary.ps1

**职责**: 从 Unity 构建/测试日志中提取关键信息。

---

### oc-session.ps1

**职责**: 管理 OpenClaw 侧的 session 信息。

---

## 通用模式

### UTF-8 编码初始化

所有脚本开头都有:
```powershell
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"
```

### 中文字符串编码

为避免跨平台/跨终端编码问题，中文字符串使用 Unicode 码点数组:
```powershell
$SectionDone = -join ([char[]]@(0x5B8C, 0x6210, 0x5185, 0x5BB9))
# 等价于: $SectionDone = "完成内容"
```

代价: 代码可读性显著下降。

### Redact-Secrets 函数

在 7 个脚本中重复定义 (cc-command, cc-run, cc-status, cc-last, claude-code-relay, claude-code-summary, mobile-status)。应抽取为共享模块。

### 错误处理偏好

所有脚本使用 `$ErrorActionPreference = "Stop"` (feishu-progress-command 和 mobile-status 除外，使用 "Continue")。
