---
paths:
  - "tools/cc-run.ps1"
  - "tools/cc-run-big.ps1"
  - "tools/claude-code-relay.ps1"
---

# Remote Command Rules

## Role Boundaries

- OpenClaw Agent does not edit project files directly.
- All file modifications must go through Claude Code CLI.
- Read-only operations (file reading, status checks, log viewing) can be performed by the Agent directly.

## Command Relay Rules

- `/cc-run <task>` — Pass <task> to relay script verbatim. Do not wrap, interpret, add, or remove anything.
- `/cc-run-big <task>` — Pass <task> to relay script verbatim with MaxMinutes=0. Do not wrap, interpret, add, or remove anything.

## Security Constraints

- No git push.
- No file or directory deletion.
- No output or saving of API Keys, Tokens, or passwords.
- No modification of OpenClaw/Claude Code secret configuration.
- No modification of Windows system-level settings.
