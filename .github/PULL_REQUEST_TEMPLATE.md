## Summary

<!-- Brief description of changes -->

## Type

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor (no functional change)
- [ ] Documentation
- [ ] Test
- [ ] Security improvement

## Files Changed

<!-- List key files -->

## Test Plan

<!-- How did you verify these changes? -->

- [ ] `Invoke-Pester tests/` passes
- [ ] Manual test: `powershell -File tools/cc-command.ps1 -MessageText "/cc-help"`
- [ ] Manual test: relay dry-run with `-PromptText "test" -RawPassThrough`

## Security Impact

<!-- For changes to claude-code-relay.ps1 or secret-utils.ps1 -->

- [ ] No change to safety rules
- [ ] Tool allow/deny lists unchanged
- [ ] Secret redaction patterns unchanged
- [ ] Workspace isolation unchanged

## Docs

- [ ] README updated (if project structure changed)
- [ ] docs/ updated (if relevant)
