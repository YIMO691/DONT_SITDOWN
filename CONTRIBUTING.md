# Contributing

## Setup

```powershell
# Clone
git clone https://github.com/YIMO691/DONT_SITDOWN.git
cd DONT_SITDOWN

# Install deps
npm install -g @anthropic-ai/claude-code
npm install -g openclaw@latest

# Configure
copy config.example.json config.json
# Edit config.json with your project paths
```

## Development

### Project Layout

- `tools/` — PowerShell pipeline scripts (router, relay, session management)
- `tools/lib/` — Shared modules (config, secret-utils)
- `docs/` — Architecture, reference, and operations guides
- `tests/` — Pester test suite
- `.claude/` — Claude Code project config
- `.github/` — Issue/PR templates

### Code Style

**PowerShell:**
- UTF-8 with BOM encoding (required for PowerShell 5.1 Chinese character support)
- `$ErrorActionPreference = "Stop"` in all scripts
- Chinese UI strings as direct string literals
- Shared functions in `tools/lib/`, dot-sourced via `$PSScriptRoot`
- All scripts set `[Console]::InputEncoding` and `[Console]::OutputEncoding` to UTF-8

**Markdown:**
- Chinese documentation is primary; English comments for code identifiers

### Testing

```powershell
# Run all tests
Invoke-Pester tests/relay.tests.ps1

# Run unit tests only (skip integration)
Invoke-Pester tests/relay.tests.ps1 -ExcludeTag Integration

# Run specific test group
Invoke-Pester tests/relay.tests.ps1 -TestName "Redact-Secrets"
```

Add tests for any changes to:
- `Redact-Secrets` — secret detection regex changes
- `Test-PathInsideRoot` — path containment logic
- `Compare-GitStatusSnapshots` — Git change detection
- Relay parameter validation — new parameter combinations

### Commit Messages

- Use Chinese for what, English for why when relevant
- Format: `<type>: <brief description>`
- Types: `fix`, `feat`, `docs`, `test`, `refactor`, `security`

## Pull Request Process

1. Create a feature branch from `master`
2. Make changes and add/update tests
3. Run `Invoke-Pester tests/` — all tests must pass
4. Update relevant docs in `docs/`
5. Open PR with description of changes and test plan

## Code of Conduct

Be respectful. This is a tool for developers — keep feedback constructive and technical.
