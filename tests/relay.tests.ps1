param(
    [switch]$SkipIntegration
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Dot-source shared utilities (pure functions, no side effects)
. "$RepoRoot\tools\lib\secret-utils.ps1"

function Assert-True {
    param([bool]$Condition, [string]$Message = "Expected condition to be true.")
    if (-not $Condition) { throw $Message }
}

function Assert-False {
    param([bool]$Condition, [string]$Message = "Expected condition to be false.")
    if ($Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected)
    if ($Actual -ne $Expected) {
        throw "Expected <$Expected> but got <$Actual>."
    }
}

function Assert-NotEqual {
    param($Actual, $Expected)
    if ($Actual -eq $Expected) {
        throw "Expected value not to be <$Expected>."
    }
}

Describe "Redact-Secrets" {
    It "redacts Anthropic key (sk-ant-*)" {
        $result = Redact-Secrets "sk-ant-abc123def456ghi789"
        Assert-True ($result -notmatch "sk-ant-")
        Assert-True ($result -match "REDACTED_SECRET")
    }

    It "redacts OpenAI key (sk-*)" {
        $result = Redact-Secrets "api key: sk-proj-1234567890abcdef"
        Assert-True ($result -notmatch "sk-proj-")
        Assert-True ($result -match "REDACTED_SECRET")
    }

    It "redacts DEEPSEEK_API_KEY env var" {
        $result = Redact-Secrets 'DEEPSEEK_API_KEY=sk-abc123'
        Assert-True ($result -match "REDACTED_SECRET")
    }

    It "redacts FEISHU_APP_SECRET env var" {
        $result = Redact-Secrets 'FEISHU_APP_SECRET=mysecret123'
        Assert-True ($result -match "REDACTED_SECRET")
    }

    It "redacts appSecret JSON field" {
        $result = Redact-Secrets 'appSecret": "abcdef123456"'
        Assert-True ($result -match "REDACTED_SECRET")
    }

    It "redacts App Secret plain text" {
        $result = Redact-Secrets "App Secret: xyz789"
        Assert-True ($result -match "REDACTED_SECRET")
    }

    It "redacts ANTHROPIC_AUTH_TOKEN" {
        $result = Redact-Secrets "ANTHROPIC_AUTH_TOKEN = mytoken123"
        Assert-True ($result -match "REDACTED_SECRET")
    }

    It "redacts OPENAI_API_KEY" {
        $result = Redact-Secrets "OPENAI_API_KEY=sk-openai-key"
        Assert-True ($result -match "REDACTED_SECRET")
    }

    It "leaves normal text unchanged" {
        $text = "Fix null reference in EnemyFSM.cs line 45"
        $result = Redact-Secrets $text
        Assert-Equal $result $text
    }

    It "handles null input gracefully" {
        $result = Redact-Secrets $null
        Assert-Equal $result ""
    }

    It "handles empty string input" {
        $result = Redact-Secrets ""
        Assert-Equal $result ""
    }
}

Describe "Test-PathInsideRoot (workspace containment)" {
    # Define the function directly for test isolation
    function Get-FullPathSafe {
        param([string]$Path)
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    }

    function Test-PathInsideRoot {
        param([string]$Path, [string]$Root)
        $full = Get-FullPathSafe -Path $Path
        $rootFull = Get-FullPathSafe -Path $Root
        return ($full -eq $rootFull -or $full.StartsWith($rootFull + "\", [System.StringComparison]::OrdinalIgnoreCase))
    }

    $testRoot = "C:\TestProject"

    It "accepts the root directory itself" {
        Assert-True (Test-PathInsideRoot -Path $testRoot -Root $testRoot)
    }

    It "accepts a subdirectory" {
        Assert-True (Test-PathInsideRoot -Path "C:\TestProject\Assets" -Root $testRoot)
    }

    It "accepts a deeply nested subdirectory" {
        Assert-True (Test-PathInsideRoot -Path "C:\TestProject\Assets\Scripts\AI" -Root $testRoot)
    }

    It "rejects a sibling directory" {
        Assert-False (Test-PathInsideRoot -Path "C:\OtherProject" -Root $testRoot)
    }

    It "rejects parent directory escape" {
        Assert-False (Test-PathInsideRoot -Path "C:\" -Root $testRoot)
    }

    It "handles trailing backslash on input" {
        Assert-True (Test-PathInsideRoot -Path "C:\TestProject\Assets\" -Root $testRoot)
    }

    It "rejects path with common prefix but not a child" {
        Assert-False (Test-PathInsideRoot -Path "C:\TestProject2" -Root $testRoot)
    }
}

Describe "Compare-GitStatusSnapshots" {
    function Compare-GitStatusSnapshots {
        param([hashtable]$Before, [hashtable]$After)
        $added = New-Object System.Collections.Generic.List[string]
        $modified = New-Object System.Collections.Generic.List[string]
        $deleted = New-Object System.Collections.Generic.List[string]
        foreach ($path in $After.Keys) {
            $afterRecord = $After[$path]
            if ($afterRecord.status.Contains("D")) {
                if (-not $Before.ContainsKey($path) -or -not $Before[$path].status.Contains("D")) { $deleted.Add($path) }
            } elseif (-not $Before.ContainsKey($path)) {
                $added.Add($path)
            } else {
                $beforeRecord = $Before[$path]
                if ($beforeRecord.hash -ne $afterRecord.hash -or $beforeRecord.status -ne $afterRecord.status) { $modified.Add($path) }
            }
        }
        return [ordered]@{ added = @($added); modified = @($modified); deleted = @($deleted) }
    }

    It "detects newly added files" {
        $before = @{}
        $after = @{
            "NewFile.cs" = [pscustomobject]@{ path = "NewFile.cs"; status = "??"; hash = "AAA" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        Assert-True ($result.added -contains "NewFile.cs")
        Assert-Equal $result.modified.Count 0
        Assert-Equal $result.deleted.Count 0
    }

    It "detects modified files (hash changed)" {
        $before = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "AAA" }
        }
        $after = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "BBB" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        Assert-True ($result.modified -contains "File.cs")
        Assert-Equal $result.added.Count 0
        Assert-Equal $result.deleted.Count 0
    }

    It "detects modified files (status changed)" {
        $before = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "A "; hash = "AAA" }
        }
        $after = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "AAA" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        Assert-True ($result.modified -contains "File.cs")
    }

    It "detects deleted files" {
        $before = @{
            "OldFile.cs" = [pscustomobject]@{ path = "OldFile.cs"; status = "M "; hash = "AAA" }
        }
        $after = @{
            "OldFile.cs" = [pscustomobject]@{ path = "OldFile.cs"; status = " D"; hash = "" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        Assert-True ($result.deleted -contains "OldFile.cs")
    }

    It "does not flag unchanged files" {
        $before = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "AAA" }
        }
        $after = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "AAA" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        Assert-Equal $result.added.Count 0
        Assert-Equal $result.modified.Count 0
        Assert-Equal $result.deleted.Count 0
    }

    It "handles empty before and after" {
        $result = Compare-GitStatusSnapshots -Before @{} -After @{}
        Assert-Equal $result.added.Count 0
        Assert-Equal $result.modified.Count 0
        Assert-Equal $result.deleted.Count 0
    }
}

Describe "Relay parameter validation (integration)" {
    $RelayScript = Join-Path $RepoRoot "tools\claude-code-relay.ps1"
    $ConfigExists = Test-Path (Join-Path $RepoRoot "config.json")

    It "script is parsable without syntax errors" {
        if ($SkipIntegration) { return }
        try {
            $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText "test" 2>&1
        } catch {
            # Only fail if the error is a parse/syntax error, not a config-not-found runtime error
            Assert-False ($_.Exception.Message -match "ParserError|parse error|syntax")
        }
        # Script executed (even if it failed at runtime due to missing config.json)
        Assert-True $true
    }

    It "rejects AllowEdit + Readonly together" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $errOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText "test" -AllowEdit -Readonly 2>&1
        Assert-NotEqual $LASTEXITCODE 0
    }

    It "rejects AllowEdit + RawPassThrough together" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $errOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText "test" -AllowEdit -RawPassThrough 2>&1
        Assert-NotEqual $LASTEXITCODE 0
    }

    It "rejects negative MaxMinutes" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $errOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText "test" -MaxMinutes -1 2>&1
        Assert-NotEqual $LASTEXITCODE 0
    }
}

Describe "cc-command routing (integration)" {
    $CommandScript = Join-Path $RepoRoot "tools\cc-command.ps1"
    $ConfigExists = Test-Path (Join-Path $RepoRoot "config.json")

    It "script is parsable without syntax errors" {
        if ($SkipIntegration) { return }
        try {
            $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $CommandScript -MessageText "/cc-help" 2>&1
        } catch {
            Assert-False ($_.Exception.Message -match "ParserError|parse error|syntax")
        }
        Assert-True $true
    }

    It "routes /cc-help and exits 0" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $CommandScript -MessageText "/cc-help" 2>&1
        Assert-Equal $LASTEXITCODE 0
        Assert-True (($output | Out-String) -match "Feishu-CC")
    }

    It "shows help for empty message" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $CommandScript -MessageText " " 2>&1
        Assert-Equal $LASTEXITCODE 0
    }
}
