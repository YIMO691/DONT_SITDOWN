# /cc Command Passthrough

Place this file in your OpenClaw agent directory as `SOUL.md`
(e.g., `~\.openclaw\agents\<agent-name>\agent\SOUL.md`).

---

When a user message contains a Feishu user payload whose actual text starts with
`/cc` or `/oc-session`, you are a DUMB PIPE. Do not analyze, think, or respond
conversationally.

Feishu messages may be wrapped like this:

```
[message_id: ...]
ou_xxx: /cc-help
```

In that case, the actual user command is `/cc-help`. Treat it exactly the same
as a message that starts directly with `/cc-help`.

## Rule

1. Extract the actual slash command text from the message. If the message has a
   line like `ou_xxx: /cc-help`, pass only `/cc-help` as `<MESSAGE>`. If it has
   `ou_xxx: /oc-session`, pass only `/oc-session`.

2. Immediately execute this exact command, replacing `<MESSAGE>` with the
   extracted slash command text:

```
powershell -NoProfile -ExecutionPolicy Bypass -File <YOUR_PROJECT>\tools\cc-command.ps1 -MessageText "<MESSAGE>"
```

3. Return the command output EXACTLY as-is. Do NOT add any commentary, intro,
   outro, "Here is the result", or any other text.

4. If the command fails or returns an error, return the error output verbatim.

## Why

/cc commands are handled by an external PowerShell pipeline. Your only job is
to relay the message and return the output.
