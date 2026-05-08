# 改进路线图

## 问题分类

- **P0: 安全隐患** — 可导致数据丢失或密钥泄露
- **P1: 可靠性** — 影响管线稳定运行
- **P2: 可维护性** — 代码质量和维护成本
- **P3: 功能增强** — 新能力

---

## 已完成 (2026-05-08)

### #2 ✅ 并发互斥竞态窗口

**方案**: `System.IO.FileStream` 排他锁 (`FileShare.None`) + `try/finally` 确保释放。
**改动**: `tools/claude-code-relay.ps1` — 新增 `Lock-CurrentTask`/`Unlock-CurrentTask` 函数。

### #4 ✅ Redact-Secrets 重复定义

**方案**: 所有脚本统一 dot-source `tools/lib/secret-utils.ps1`。
**改动**: 7 个脚本的独立 `Redact-Secrets` 定义已删除，改为共享引用。

### #6 ✅ cc-command.ps1 路由用串行 if

**方案**: 改为 `if/elseif/else` 结构。
**改动**: `tools/cc-command.ps1` — 所有路由分支使用 `elseif`，末尾 `else` 兜底。

### #7 ✅ 中文字符串用 Unicode 码点数组

**方案**: 全部替换为直接中文字符串，文件编码为 UTF-8 with BOM 保证 PowerShell 5.1 兼容。
**改动**: 9 个 `.ps1` 文件，共 52 个变量。`[Console]::OutputEncoding` UTF-8 设置保留。

### #8 ✅ 无日志轮转

**方案**: relay 执行完成后清理 30 天前的旧文件，排除 `current-task.json`。
**改动**: `tools/claude-code-relay.ps1` 末尾追加 4 行清理逻辑。

### #14 ✅ 无测试覆盖

**方案**: 新建 Pester 测试文件，31 个测试覆盖核心函数。
**改动**: 新建 `tests/relay.tests.ps1`，覆盖 `Redact-Secrets`(11)、`Test-PathInsideRoot`(7)、`Compare-GitStatusSnapshots`(6)、参数校验(4)、cc-command 路由(3)。

### #15 ✅ cc-command.ps1 有死代码路径

**方案**: 删除 `-PromptText` 入口参数和对应的 35 行死代码（绕过路由直接调 relay 的第二条路径）。
**改动**: `tools/cc-command.ps1` — 只保留 `-MessageText` 单一入口。

---

## P1 — 可靠性

### #1 `/cc-run-big` 安全防护（已改善，仍有空间）

**现状**: `cc-run-big.ps1` 通过 relay `-AllowEdit -MaxMinutes 0` 调用，享有与 `cc-run` 相同的 `--allowedTools`/`--disallowedTools` 限制。
**剩余风险**: 无限超时意味着恶意/错误的长时间任务不会被自动终止。
**建议**: 考虑增加可配置的最大超时上限。
**工作量**: 小

---

### #3 无自动重试

**现状**: claude CLI 失败后直接标记 `failed`，不做重试。

**建议**: 对瞬时错误（网络超时、API 500）自动重试 1-2 次，间隔 10 秒。

**工作量**: 小 (~20 行在 relay 的 catch 块)

---

## P2 — 可维护性

### #5 路径硬编码

**现状**: `config.json` 的 `projectRoot` 配置已通过 `tools/lib/config.ps1` 集中管理。但部分脚本仍有隐式路径依赖（如 `$PSScriptRoot\..\..` 相对定位）。

**建议**: 所有路径统一通过 `config.ps1` 提供的 `$Script:ProjectRoot` / `$Script:WorktreesRoot` 访问。

**工作量**: 小

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

## 优先级排序 (更新)

| 优先级 | 问题编号 | 说明 |
|--------|----------|------|
| 短期 | #10 | 管线健康检查 |
| 短期 | #3 | 自动重试 |
| 短期 | #11 | cc-run --session |
| 中期 | #5 | 路径去隐式依赖 |
| 中期 | #1 | cc-run-big 超时上限 |
| 长期 | #9 | 任务队列 |
| 长期 | #12 | 安全 commit |
| 可选 | #13 | 文档对齐 |
