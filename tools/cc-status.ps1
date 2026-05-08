[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\secret-utils.ps1"

$CurrentTaskPath = Join-Path $Script:LogRoot "current-task.json"
$NoTaskMessage = "暂无 Claude Code relay 任务"
$NoOutputMessage = "暂无输出日志。"
$NoSessionMessage = "(未指定)"
$UnknownMessage = "(未知)"
$LabelPrompt = "当前任务："
$LabelSession = "目标会话："
$LabelWorkspace = "workspace："
$LabelGit = "git："
$LabelStarted = "开始时间："
$LabelStatus = "状态："
$LabelExitCode = "退出码："
$LabelRecent = "最近日志："

function Limit-Text {
    param([string]$Text, [int]$MaxLength)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $trimmed = $Text.Trim()
    if ($trimmed.Length -le $MaxLength) { return $trimmed }
    return $trimmed.Substring(0, $MaxLength) + "..."
}

Set-Location -LiteralPath $Script:ProjectRoot

if (-not (Test-Path -LiteralPath $CurrentTaskPath)) {
    Write-Output $NoTaskMessage
    exit 0
}

try {
    $task = Get-Content -LiteralPath $CurrentTaskPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Output $NoTaskMessage
    exit 0
}

$recent = ""
if ($task.summaryLog -and (Test-Path -LiteralPath $task.summaryLog)) {
    $recent = Get-Content -LiteralPath $task.summaryLog -Raw -Encoding UTF8
} elseif ($task.outputLog -and (Test-Path -LiteralPath $task.outputLog)) {
    $recent = Get-Content -LiteralPath $task.outputLog -Raw -Encoding UTF8
}
$recent = Limit-Text -Text (Redact-Secrets -Text $recent) -MaxLength 240
if ([string]::IsNullOrWhiteSpace($recent)) { $recent = $NoOutputMessage }

$targetSession = if (-not [string]::IsNullOrWhiteSpace($task.sessionName)) {
    $task.sessionName
} elseif ([string]::IsNullOrWhiteSpace($task.session)) {
    $NoSessionMessage
} else { $task.session }

$started = if ($task.startedAt) { $task.startedAt } else { $UnknownMessage }
$prompt = Limit-Text -Text (Redact-Secrets -Text $task.prompt) -MaxLength 80

Write-Output "$LabelPrompt$prompt"
Write-Output "$LabelSession$targetSession"
if (-not [string]::IsNullOrWhiteSpace($task.workspace)) { Write-Output "$LabelWorkspace$($task.workspace)" }
if (-not [string]::IsNullOrWhiteSpace($task.gitBranch)) { Write-Output "$LabelGit$($task.gitBranch)" }
Write-Output "$LabelStarted$started"
Write-Output "$LabelStatus$($task.status)"
if ($task.exitCode -ne $null) { Write-Output "$LabelExitCode$($task.exitCode)" }
Write-Output "$LabelRecent$recent"
