# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| main branch | ✅ |
| Older commits | ❌ |

## Reporting a Vulnerability

**Do not report security vulnerabilities via public GitHub issues.**

If you discover a security vulnerability in this project, please report it via:

- Email: [your security contact email]
- Or use GitHub's private vulnerability reporting (if enabled for this repo)

You should receive a response within 48 hours. If the issue is confirmed, we will release a patch as soon as possible.

## Security Model

This project is a remote code execution pipeline. The following security boundaries exist:

1. **Workspace isolation**: All file operations are confined to the configured project root and worktrees directories.
2. **Tool restrictions**: Claude Code CLI runs with `--allowedTools`/`--disallowedTools` whitelist/blacklist.
3. **Prompt injection defense**: User prompts are wrapped in safety rules before being passed to Claude Code CLI.
4. **Secret redaction**: 10 regex patterns redact API keys and tokens from all log output.
5. **File locking**: Concurrent relay execution is prevented via `FileStream` exclusive lock.
6. **Audit logging**: Every relay execution generates 4 log files (prompt, output, meta, summary).

## What to Report

- Path traversal or workspace escape vectors
- Secret leakage in logs or output
- Bypass of tool restrictions (allowedTools/disallowedTools)
- Prompt injection that defeats the safety wrapper
- Remote code execution beyond allowed boundaries

## What NOT to Report

- Missing features (use Issues for that)
- Config.json not found errors (deployment issue, not security)
- Claude Code CLI hallucination outputs (upstream model issue)
