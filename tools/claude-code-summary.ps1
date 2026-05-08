param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [Parameter(Mandatory = $true)]
    [string]$MetaPath,
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\lib\secret-utils.ps1"

$NoOutputMessage = "(Claude Code 没有输出内容。)"
$StatusDone = "状态：已完成"
$StatusFailedPrefix = "状态：执行失败，退出码 "
$LabelRunId = "运行 ID："
$LabelDirectory = "目录："
$LabelModePrefix = "模式："
$LabelSummary = "摘要："
$LabelLogs = "日志："
$LabelOutput = "输出："
$LabelMeta = "元数据："

function Get-TailText {
    param([string]$Text, [int]$MaxLength)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $NoOutputMessage }
    $trimmed = $Text.Trim()
    if ($trimmed.Length -le $MaxLength) { return $trimmed }
    return "..." + $trimmed.Substring($trimmed.Length - $MaxLength)
}

if (-not (Test-Path -LiteralPath $OutputPath)) { throw "Output file not found: $OutputPath" }
if (-not (Test-Path -LiteralPath $MetaPath)) { throw "Meta file not found: $MetaPath" }

$OutputText = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
$Meta = Get-Content -LiteralPath $MetaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$SafeTail = Redact-Secrets -Text (Get-TailText -Text $OutputText -MaxLength 1800)

if ($Meta.rawPassThrough) {
    $RawSummary = Redact-Secrets -Text (Get-TailText -Text $OutputText -MaxLength 4000)
    Set-Content -LiteralPath $SummaryPath -Value $RawSummary.Trim() -Encoding UTF8
    exit 0
}

$StatusLine = if ([int]$Meta.exitCode -eq 0) { $StatusDone } else { "$StatusFailedPrefix$($Meta.exitCode)" }
$ModeValue = if ($Meta.mode) { $Meta.mode } else { "readonly" }

$Summary = @"
$StatusLine
$LabelRunId$($Meta.runId)
$LabelDirectory$($Meta.projectRoot)
$LabelModePrefix$ModeValue

$LabelSummary
$SafeTail

$LabelLogs
- $LabelOutput$($Meta.outputPath)
- $LabelMeta$($MetaPath)
"@

$Summary = Redact-Secrets -Text $Summary
Set-Content -LiteralPath $SummaryPath -Value $Summary -Encoding UTF8
