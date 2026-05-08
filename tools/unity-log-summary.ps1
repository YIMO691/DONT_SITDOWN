$ErrorActionPreference = "Continue"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"

. "$PSScriptRoot\lib\config.ps1"
. "$PSScriptRoot\lib\secret-utils.ps1"

Set-Location $Script:ProjectRoot

$logCandidates = @(
    ".\Logs\EditModeBatch.log",
    ".\Logs\EditModeResults.xml",
    ".\Logs\UnityBatch.log"
)

Write-Output "Unity Log Summary"
Write-Output "=================="
Write-Output ""

foreach ($log in $logCandidates) {
    if (Test-Path $log) {
        Write-Output "--- $log ---"
        try {
            $content = Get-Content -LiteralPath $log -Tail 50 -ErrorAction Stop
            foreach ($line in $content) { Write-Output (Redact-Secrets -Text $line) }
        } catch { Write-Output "(unable to read)" }
        Write-Output ""
    }
}

$errorPattern = 'error CS|Exception|Failed|FAIL|Compilation failed|NullReferenceException'
Write-Output "--- Error Scan ---"
foreach ($file in $logCandidates) {
    if (Test-Path $file) {
        $matches = Select-String -LiteralPath $file -Pattern $errorPattern -CaseSensitive:$false -ErrorAction Stop | Select-Object -Last 20
        if ($matches) { foreach ($m in $matches) { Write-Output (Redact-Secrets -Text $m.Line) } }
    }
}
Write-Output "--- End ---"
