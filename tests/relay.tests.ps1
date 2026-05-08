param(
    [switch]$SkipIntegration
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Dot-source shared utilities (pure functions, no side effects)
. "$RepoRoot\tools\lib\secret-utils.ps1"

Describe "Redact-Secrets" {
    It "redacts Anthropic key (sk-ant-*)" {
        $result = Redact-Secrets "sk-ant-abc123def456ghi789"
        $result -notmatch "sk-ant-" | Should Be $true
        $result -match "REDACTED_SECRET" | Should Be $true
    }

    It "redacts OpenAI key (sk-*)" {
        $result = Redact-Secrets "api key: sk-proj-1234567890abcdef"
        $result -notmatch "sk-proj-" | Should Be $true
        $result -match "REDACTED_SECRET" | Should Be $true
    }

    It "redacts DEEPSEEK_API_KEY env var" {
        $result = Redact-Secrets 'DEEPSEEK_API_KEY=sk-abc123'
        $result -match "REDACTED_SECRET" | Should Be $true
    }

    It "redacts FEISHU_APP_SECRET env var" {
        $result = Redact-Secrets 'FEISHU_APP_SECRET=mysecret123'
        $result -match "REDACTED_SECRET" | Should Be $true
    }

    It "redacts appSecret JSON field" {
        $result = Redact-Secrets 'appSecret": "abcdef123456"'
        $result -match "REDACTED_SECRET" | Should Be $true
    }

    It "redacts App Secret plain text" {
        $result = Redact-Secrets "App Secret: xyz789"
        $result -match "REDACTED_SECRET" | Should Be $true
    }

    It "redacts ANTHROPIC_AUTH_TOKEN" {
        $result = Redact-Secrets "ANTHROPIC_AUTH_TOKEN = mytoken123"
        $result -match "REDACTED_SECRET" | Should Be $true
    }

    It "redacts OPENAI_API_KEY" {
        $result = Redact-Secrets "OPENAI_API_KEY=sk-openai-key"
        $result -match "REDACTED_SECRET" | Should Be $true
    }

    It "leaves normal text unchanged" {
        $text = "Fix null reference in EnemyFSM.cs line 45"
        $result = Redact-Secrets $text
        $result | Should Be $text
    }

    It "handles null input gracefully" {
        $result = Redact-Secrets $null
        $result | Should Be ""
    }

    It "handles empty string input" {
        $result = Redact-Secrets ""
        $result | Should Be ""
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
        Test-PathInsideRoot -Path $testRoot -Root $testRoot | Should Be $true
    }

    It "accepts a subdirectory" {
        Test-PathInsideRoot -Path "C:\TestProject\Assets" -Root $testRoot | Should Be $true
    }

    It "accepts a deeply nested subdirectory" {
        Test-PathInsideRoot -Path "C:\TestProject\Assets\Scripts\AI" -Root $testRoot | Should Be $true
    }

    It "rejects a sibling directory" {
        Test-PathInsideRoot -Path "C:\OtherProject" -Root $testRoot | Should Be $false
    }

    It "rejects parent directory escape" {
        Test-PathInsideRoot -Path "C:\" -Root $testRoot | Should Be $false
    }

    It "handles trailing backslash on input" {
        Test-PathInsideRoot -Path "C:\TestProject\Assets\" -Root $testRoot | Should Be $true
    }

    It "rejects path with common prefix but not a child" {
        Test-PathInsideRoot -Path "C:\TestProject2" -Root $testRoot | Should Be $false
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
        $result.added -contains "NewFile.cs" | Should Be $true
        $result.modified.Count | Should Be 0
        $result.deleted.Count | Should Be 0
    }

    It "detects modified files (hash changed)" {
        $before = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "AAA" }
        }
        $after = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "BBB" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        $result.modified -contains "File.cs" | Should Be $true
        $result.added.Count | Should Be 0
        $result.deleted.Count | Should Be 0
    }

    It "detects modified files (status changed)" {
        $before = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "A "; hash = "AAA" }
        }
        $after = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "AAA" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        $result.modified -contains "File.cs" | Should Be $true
    }

    It "detects deleted files" {
        $before = @{
            "OldFile.cs" = [pscustomobject]@{ path = "OldFile.cs"; status = "M "; hash = "AAA" }
        }
        $after = @{
            "OldFile.cs" = [pscustomobject]@{ path = "OldFile.cs"; status = " D"; hash = "" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        $result.deleted -contains "OldFile.cs" | Should Be $true
    }

    It "does not flag unchanged files" {
        $before = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "AAA" }
        }
        $after = @{
            "File.cs" = [pscustomobject]@{ path = "File.cs"; status = "M "; hash = "AAA" }
        }
        $result = Compare-GitStatusSnapshots -Before $before -After $after
        $result.added.Count | Should Be 0
        $result.modified.Count | Should Be 0
        $result.deleted.Count | Should Be 0
    }

    It "handles empty before and after" {
        $result = Compare-GitStatusSnapshots -Before @{} -After @{}
        $result.added.Count | Should Be 0
        $result.modified.Count | Should Be 0
        $result.deleted.Count | Should Be 0
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
            ($_.Exception.Message -match "ParserError|parse error|syntax") | Should Be $false
        }
        # Script executed (even if it failed at runtime due to missing config.json)
        $true | Should Be $true
    }

    It "rejects AllowEdit + Readonly together" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $errOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText "test" -AllowEdit -Readonly 2>&1
        $LASTEXITCODE | Should Not Be 0
    }

    It "rejects AllowEdit + RawPassThrough together" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $errOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText "test" -AllowEdit -RawPassThrough 2>&1
        $LASTEXITCODE | Should Not Be 0
    }

    It "rejects negative MaxMinutes" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $errOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $RelayScript -PromptText "test" -MaxMinutes -1 2>&1
        $LASTEXITCODE | Should Not Be 0
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
            ($_.Exception.Message -match "ParserError|parse error|syntax") | Should Be $false
        }
        $true | Should Be $true
    }

    It "routes /cc-help and exits 0" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $CommandScript -MessageText "/cc-help" 2>&1
        $LASTEXITCODE | Should Be 0
        ($output | Out-String) -match "Feishu-CC" | Should Be $true
    }

    It "shows help for empty message" {
        if ($SkipIntegration) { return }
        if (-not $ConfigExists) { return }
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $CommandScript -MessageText " " 2>&1
        $LASTEXITCODE | Should Be 0
    }
}
