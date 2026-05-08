# 改进路线图

## 问题分类

- **P0: 安全隐患** — 可导致数据丢失或密钥泄露
- **P1: 可靠性** — 影响管线稳定运行
- **P2: 可维护性** — 代码质量和维护成本
- **P3: 功能增强** — 新能力

---

## P1 — 可靠性

### #1 `/cc-run-big` 无安全防护

**现状**: `cc-run-big.ps1` 直接调用 `claude -p`，不经过 relay 包装，无 `--allowedTools`/`--disallowedTools` 限制。

**风险**: 可执行 git push、删除文件、暴露密钥。

**建议**:
1. 至少加上 `--disallowedTools "Bash(git push:*),Bash(rm *:),Bash(del *:)"` 
2. 或者让 `cc-run-big` 也经过 relay，只是 `MaxMinutes=0` (无超时)

**工作量**: 小 (~10 行改动)

---

### #2 并发控制有竞态窗口

**现状**: `current-task.json` 读取和写入之间存在竞态窗口。两个几乎同时到达的 `/cc-run` 都可能通过检查。

**建议**: 
- 方案 A: 使用文件锁 (`System.IO.FileStream` with `FileShare.None`)
- 方案 B: 任务队列 — 不拒绝，而是排队

**工作量**: 中 (需要改造 current-task.json 的读写逻辑)

---

### #3 无自动重试

**现状**: claude CLI 失败后直接标记 `failed`，不做重试。

**建议**: 对瞬时错误（网络超时、API 500）自动重试 1-2 次，间隔 10 秒。

**工作量**: 小 (~20 行在 relay 的 catch 块)

---

## P2 — 可维护性

### #4 Redact-Secrets 重复定义 7 次

**现状**: 以下 7 个脚本各自定义了完全相同的 `Redact-Secrets` 函数:
- `cc-command.ps1`
- `cc-run.ps1`
- `cc-status.ps1`
- `cc-last.ps1`
- `claude-code-relay.ps1`
- `claude-code-summary.ps1`
- `mobile-status.ps1`

**建议**: 创建 `tools/lib/secret-utils.ps1`，其他脚本 dot-source 引用:
```powershell
. "$PSScriptRoot\lib\secret-utils.ps1"
```

**工作量**: 小 (创建 1 个新文件 + 修改 7 个文件的引用)

---

### #5 路径硬编码

**现状**: `F:\Unity6_AI` 以字符串形式硬编码在 15+ 个位置。

**文件清单**:
- `cc-command.ps1`: 1 处
- `cc-run.ps1`: 1 处
- `cc-run-big.ps1`: 1 处
- `cc-status.ps1`: 1 处
- `cc-last.ps1`: 1 处
- `cc-session.ps1`: 2 处
- `cc-session-add.ps1`: 2 处
- `cc-session-remove.ps1`: 1 处
- `cc-use.ps1`: 1 处
- `claude-code-relay.ps1`: 3 处
- `mobile-status.ps1`: 通过 `$PSScriptRoot` 相对定位 (已正确)

**建议**: 
- 方案 A: 各脚本用 `$PSScriptRoot\..` 相对定位（适合在项目内的脚本）
- 方案 B: 创建 `tools/lib/project-config.ps1` 统一管理项目路径

**工作量**: 中 (需要逐脚本测试)

---

### #6 `cc-command.ps1` 路由用串行 if

**现状**: 行 94-124 用连续 `if` 而非 `elseif`，依赖 `Invoke-ChildScript` 内 `exit` 终止。

**风险**: 新增命令时容易忘记 `exit`，导致多个分支执行。

**建议**: 改为 `if/elseif/else` 结构，语义清晰。

**工作量**: 小 (~10 行调整)

---

### #7 中文字符串用 Unicode 码点数组

**现状**: 所有中文 UI 字符串使用 `-join ([char[]]@(0x...))` 形式，例如:
```powershell
$SectionDone = -join ([char[]]@(0x5B8C, 0x6210, 0x5185, 0x5BB9))
# 实际 = "完成内容"
```

**影响**: 代码完全不可读。新增或修改一个中文字符串需要查 Unicode 码表。

**原因**: 历史遗留，为了规避早期 PowerShell 版本在管道中的 UTF-8 问题。

**建议**: 当前环境已通过 `[Console]::OutputEncoding` + `$OutputEncoding` 正确设置了 UTF-8。直接写中文字符串并验证输出。

**工作量**: 中 (需要逐脚本转换并测试跨平台输出)

---

### #8 无日志轮转

**现状**: `Logs/ClaudeRelay/` 每次执行生成 4 个文件，无限累积。

**建议**: relay 脚本末尾加清理逻辑:
```powershell
# 保留最近 30 天
Get-ChildItem $LogRoot -File | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-30)
} | Remove-Item
```

**工作量**: 小 (~5 行)

---

## P3 — 功能增强

### #9 任务队列

**现状**: 并发 `/cc-run` 被直接拒绝。

**建议**: 支持排队模式:
```
/cc-run --queue <任务>
```

实现:
- 维护 `task-queue.json` 数组
- relay 完成后自动取下一个
- `/cc-status` 显示队列长度

**工作量**: 大 (需要改造 relay 的状态机 + 新增队列逻辑)

---

### #10 管线健康检查

**现状**: 没有一键验证全链路是否通畅的方法。

**建议**: 新增 `/cc-health` 命令，依次检查:
1. Git 可用
2. Claude Code CLI 可用
3. DeepSeek API 连通
4. Workspace 目录存在
5. current-task.json 可读写

输出:
```
管线状态:
  Git: ✅
  Claude CLI: ✅ (v1.x.x)
  DeepSeek: ✅ (200 OK, 120ms)
  Workspace: ✅ F:\Unity6_AI
  日志: ✅ (234 个文件, 45MB)
```

**工作量**: 小 (新建 cc-health.ps1 ~80 行)

---

### #11 `/cc-run` 支持 `--session` 参数

**现状**: `/cc-run` 只能使用 `cc-target.json` 中的默认 session。

**建议**: 支持临时指定 session:
```
/cc-run --session my-debug-session 继续调试之前的错误
```

**工作量**: 小 (cc-run.ps1 转发 -Session 参数到 relay)

---

### #12 Git commit 安全白名单

**现状**: relay 的 Prompt 包装说 "Do not create git commits unless explicitly allowed"，但没有机制让用户显式授权。

**建议**: 新增 `/cc-commit` 命令:
```
/cc-commit <消息>
```
会执行 `git add -A && git commit -m <消息>`。

**工作量**: 小 (~50 行新脚本)

---

### #13 OpenClaw 文档与实际部署对齐

**现状**: `openclaw-local-final.md` 描述的是 WSL2 方案，但实际 OpenClaw 跑在 Windows Node.js 上。

**建议**: 更新文档反映实际部署架构。

**工作量**: 小 (更新文档)

---

## 优先级排序建议

| 优先级 | 问题编号 | 说明 |
|--------|----------|------|
| 立即 | #1 | cc-run-big 安全防护 |
| 立即 | #4 | Redact-Secrets 去重 |
| 短期 | #6 | cc-command 改 elseif |
| 短期 | #8 | 日志轮转 |
| 短期 | #10 | 管线健康检查 |
| 中期 | #5 | 路径去硬编码 |
| 中期 | #3 | 自动重试 |
| 中期 | #11 | cc-run --session |
| 长期 | #7 | 中文码点数组替换 |
| 长期 | #2 | 并发队列 |
| 长期 | #9 | 任务队列 |
| 可选 | #12 | 安全 commit |
| 可选 | #13 | 文档对齐 |
