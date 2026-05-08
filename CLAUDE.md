<!-- 精简提示：如需减少 token 开销，可保留"沟通方式""Skill 与 Agent 边界""Git 与安全""Project Overlay"四节，其余内容可用 .claude/rules/ 代替。 -->

# CLAUDE.md

This file provides reusable guidance for Claude Code or other coding agents working in a project that imports this kit.

## 沟通方式

- 默认使用中文沟通，代码标识符、文件名、API 名称保持英文。
- 先理解项目现状，再做改动。不要凭记忆锁定版本、命令或外部服务细节。
- 对不确定信息给出验证方式；高风险或会花钱的选择先说明取舍。

## 工作流

1. 读 README.md、CLAUDE.md、AGENTS.md 了解项目。
2. 最小上下文定位 → 写验收标准 → 小步实现 → 验证。

## Skill 与 Agent 边界

- `.claude/skills/` 是可触发工作流：描述何时使用、读什么、怎么做、如何验证。
- `.claude/agents/` 是角色预设：用于手动选择 engineer 或 coder 的语气、职责和默认模型。
- 简单实现、修 bug、配置、小文档：直接使用 `coder` 或当前上下文实现，不需要编排。
- 纯方案、架构、接口、任务拆解：直接使用 `engineer`。
- 复杂且要落地的功能：使用 `engineer-coder-orchestrator`，先产出 engineer brief，再由 coder scoped implementation。
- Unity 相关任务叠加 `unity6-project`；维护本 kit 时叠加 `claude-config-maintainer`。

## 代码原则

- 沿用项目现有框架、命名、目录结构和测试方式；只改必要文件。
- 处理空值、异常、超时、权限失败等边界；避免 XSS、SQL 注入、命令注入。

## Token 节省

- 优先用 Glob/Grep/Read 等可用工具定位上下文；在 shell 中可用时再用 `rg --files` 和 `rg`。
- 长文档只读取相关小节；需要完整背景时再扩大范围。
- 让 skill 保持短小：`SKILL.md` 放流程，详细材料放 `docs/` 或 `references/` 按需读取。
- 对重复操作使用脚本，避免每次让模型重写同一段流程。
- 汇报时只讲决策、变更、验证和下一步，不复述大段日志。

## Git 与安全

- 允许查看状态、diff、log。不要在用户不知情时推送到远端。
- 不使用 `git reset --hard`、批量删除或覆盖用户改动，除非用户明确要求。
- 遇到工作区已有改动，先判断是否相关；无关则保留，相关则兼容。
- 发布 GitHub 前检查 `.gitignore`、`.gitattributes`、`SECURITY.md`、`CONTRIBUTING.md`、PR 模板和 CODEOWNERS。

## Project Overlay

新项目可以在本文件下方追加项目专属内容，例如：

- 项目目标和当前阶段。
- 启动、测试、构建命令。
- 目录结构和文件放置规则。
- 技术栈版本、包管理方式、部署方式。
- 项目专属验收标准。

不要把项目私有密钥、个人账号、临时机器路径写入公共模板。
