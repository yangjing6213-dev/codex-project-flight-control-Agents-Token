function Invoke-PfcBuilderProfileTests {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$Phase
    )

    $results = New-Object System.Collections.Generic.List[object]
    function Add-BuilderProfileResult([string]$Id, [scriptblock]$Test) {
        try {
            & $Test
            $results.Add((New-PfcResult -ScenarioId $Id -Status 'PASS' -Message 'verified'))
        } catch {
            $results.Add((New-PfcResult -ScenarioId $Id -Status 'FAIL' -Message $_.Exception.Message))
        }
    }
    function Assert-BuilderProfileStatus([System.IO.DirectoryInfo]$Root, [string]$Expected, [string]$ScenarioId) {
        $check = @(Invoke-PfcStaticChecks -RepositoryRoot $Root -Phase $Phase | Where-Object { $_.ScenarioId -eq 'package.builder.profile' })
        Assert-PfcEqual -Expected 1 -Actual $check.Count -ScenarioId ($ScenarioId + '.check-count')
        Assert-PfcEqual -Expected $Expected -Actual $check[0].Status -ScenarioId $ScenarioId
    }
    function New-BuilderProfileFixture([string]$Id, [scriptblock]$Mutate) {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-builder-profile-' + $Id + '-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $fixture 'codex-agents') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fixture 'skill\project-flight-control\references') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot.FullName 'codex-agents\project-flight-builder.toml') -Destination (Join-Path $fixture 'codex-agents\project-flight-builder.toml')
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references\builder-debugging.md') -Destination (Join-Path $fixture 'skill\project-flight-control\references\builder-debugging.md')
        & $Mutate $fixture
        return $fixture
    }

    Add-BuilderProfileResult 'builder.profile.valid' {
        Assert-BuilderProfileStatus -Root $RepositoryRoot -Expected 'PASS' -ScenarioId 'builder.profile.valid.check'
    }
    $negativeCases = @(
        @{ Id = 'missing-expansion-condition'; Mutate = {
                param($Fixture)
                $path = Join-Path $Fixture 'codex-agents\project-flight-builder.toml'
                $text = Get-Content -Raw -LiteralPath $path
                Set-Content -LiteralPath $path -Value $text.Replace('Enter Level 2 only when Level 1 leaves a local dependency', 'Enter Level 2 after a broad scan') -Encoding UTF8
            } },
        @{ Id = 'missing-control-file-prohibition'; Mutate = {
                param($Fixture)
                $path = Join-Path $Fixture 'codex-agents\project-flight-builder.toml'
                $text = Get-Content -Raw -LiteralPath $path
                Set-Content -LiteralPath $path -Value $text.Replace('must not write control files', 'may write control files') -Encoding UTF8
            } },
        @{ Id = 'missing-git-reset-prohibition'; Mutate = {
                param($Fixture)
                $path = Join-Path $Fixture 'codex-agents\project-flight-builder.toml'
                $text = Get-Content -Raw -LiteralPath $path
                Set-Content -LiteralPath $path -Value $text.Replace('git reset', 'git status') -Encoding UTF8
            } },
        @{ Id = 'hard-coded-model'; Mutate = {
                param($Fixture)
                Add-Content -LiteralPath (Join-Path $Fixture 'codex-agents\project-flight-builder.toml') -Value 'model = "gpt-5.6-terra"' -Encoding UTF8
            } },
        @{ Id = 'global-high-reasoning'; Mutate = {
                param($Fixture)
                Add-Content -LiteralPath (Join-Path $Fixture 'codex-agents\project-flight-builder.toml') -Value 'reasoning_effort = "high"' -Encoding UTF8
            } }
    )
    foreach ($case in $negativeCases) {
        Add-BuilderProfileResult ('builder.profile.reject.' + $case.Id) {
            $fixture = $null
            try {
                $fixture = New-BuilderProfileFixture -Id $case.Id -Mutate $case.Mutate
                Assert-BuilderProfileStatus -Root (Get-Item -LiteralPath $fixture) -Expected 'FAIL' -ScenarioId ('builder.profile.reject.' + $case.Id + '.check')
            } finally {
                if ($null -ne $fixture -and (Test-Path -LiteralPath $fixture)) { Remove-Item -LiteralPath $fixture -Recurse -Force }
            }
        }
    }
    return $results.ToArray()
}
