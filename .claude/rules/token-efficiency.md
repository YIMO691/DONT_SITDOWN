<!-- audience: all-agents -->
# Token 节省规则

- 先定位，再阅读：在 Claude Code/Codex 工具环境中优先用 Glob/Grep/Read；在 shell 中可用时再用 `rg --files` 和 `rg`。
- 少读长文档：先看目录、标题或相关小节，必要时再完整读取。
- 少复制日志：只提取错误行、堆栈核心、失败测试名和关键版本信息。
- 少写大计划：简单任务直接做；复杂任务用短清单维护状态。
- 把重复流程沉淀为脚本或 skill，避免每次重写操作细节。
- `SKILL.md` 只保留触发、流程和硬约束；长解释放到 `docs/` 或 `references/`。
- 总结时突出变更、验证和风险，不复述完整 diff。
