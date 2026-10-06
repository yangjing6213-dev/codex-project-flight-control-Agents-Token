function Invoke-PfcBuilderProfileTests {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$Phase
    )

    Import-Module (Join-Path $RepositoryRoot 'evals/lib/PromptBudget.psm1') -Force
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
    Add-BuilderProfileResult 'builder.profile.continuous-projection' {
        $text = Get-Content -Raw (Join-Path $RepositoryRoot 'codex-agents/project-flight-builder.toml')
        Assert-PfcTrue -Actual ($text -match 'Echo.*before any business-file write' -and $text -match 'PRE_WRITE_IDENTITY_GATE_PASS' -and $text -match 'must not start the next milestone') -ScenarioId 'builder.continuous' -Expected 'pre-write Echo and Goalkeeper gate; current milestone only'
    }
    # Exercise actual profile rejection, including contradictory grants with prohibitions retained.
    $continuousCases = @(
        @{ Id='compact-profile'; Append=''; Expected='PASS' },
        @{ Id='control-write-you'; Append='You may write canonical control files.' },
        @{ Id='control-write-no-subject'; Append='May write canonical control files.' },
        @{ Id='next-milestone-you'; Append='You may start the next milestone.' },
        @{ Id='repair-reset-you'; Append='You may reset repair counters on RESUME.' },
        @{ Id='self-lease-you'; Append='You may issue your own Lease.' },
        @{ Id='self-lease-no-subject'; Append='Can issue your own Lease.' },
        @{ Id='prohibition-must-not'; Append='You must not write canonical control files.'; Expected='PASS' },
        @{ Id='prohibition-never'; Append='Never start the next milestone.'; Expected='PASS' },
        @{ Id='prohibition-cannot'; Append='You cannot issue your own Lease.'; Expected='PASS' },
        @{ Id='prohibition-may-not'; Append='You may not reset repair counters.'; Expected='PASS' },
        @{ Id='goalkeeper-authority'; Append='Goalkeeper may write control files.'; Expected='PASS' },
        @{ Id='goalkeeper-authority-wrapped'; Append="Goalkeeper`nmay write control files."; Expected='PASS' },
        @{ Id='goalkeeper-authority-crlf'; Append="Goalkeeper`r`nmay write control files."; Expected='PASS' },
        @{ Id='control-write-you-wrapped'; Append="You`nmay write canonical control files." },
        @{ Id='control-write-instruction-start'; Append='May write canonical control files.'; AtStart=$true },
        @{ Id='echo-identity'; Old='Writable Path Hash'; New='unbound paths' },
        @{ Id='gate-order'; Old='Only after Goalkeeper confirms PRE_WRITE_IDENTITY_GATE_PASS and issues the matching Lease may you write'; New='Write before Goalkeeper confirms PRE_WRITE_IDENTITY_GATE_PASS and issues the matching Lease' },
        @{ Id='candidate-required-first'; Old='Candidate SHA only if already present'; New='Candidate SHA required before first write' },
        @{ Id='repair-limit'; Old='At most two code-changing attempts'; New='At most twenty code-changing attempts' },
        @{ Id='repair-reset'; Append='Builder may reset repair counters on RESUME.' },
        @{ Id='next-milestone'; Append='Builder may start the next milestone.' },
        @{ Id='control-write'; Append='Builder may write canonical control files.' },
        @{ Id='self-lease'; Append='Builder may issue its own Lease.' },
        @{ Id='budget'; Append=('x' * 3300) },
        @{ Id='budget-exception'; Append=('INDEPENDENTLY_REVIEWED_JUSTIFICATION ' + ('x' * 3300)) },
        @{ Id='full-protocol-copy'; Append=(Get-Content -Raw (Join-Path $RepositoryRoot 'skill/project-flight-control/references/continuous-execution.md')) }
    )
    foreach ($case in $continuousCases) {
        Add-BuilderProfileResult ('builder.profile.reject.' + $case.Id) {
            $fixture = New-BuilderProfileFixture -Id $case.Id -Mutate { param($root) }
            try {
                $path = Join-Path $fixture 'codex-agents/project-flight-builder.toml'
                # Shorten metadata only: preserve every behavior/prohibition and isolate budget effects.
                $original = [regex]::Replace([IO.File]::ReadAllText($path), '(?m)^description = "[^"]*"', 'description = "x"')
                $mutated = if ($case.ContainsKey('Append')) {
                    $position = if ($case.ContainsKey('AtStart')) { $original.IndexOf('"""') + 3 } else { $original.LastIndexOf('"""') }
                    $original.Insert($position, $case.Append + "`n")
                } else { $original.Replace($case.Old, $case.New) }
                Assert-PfcTrue -Actual ($mutated -cne $original) -ScenarioId $case.Id -Expected 'mutation applied'
                $instructions = [regex]::Match($mutated, '(?s)developer_instructions\s*=\s*"""(?<body>.*?)"""\s*\z')
                Assert-PfcTrue -Actual ($instructions.Success -and [regex]::Matches($mutated, '"""').Count -eq 2) -ScenarioId $case.Id -Expected 'intact TOML instruction string'
                if ($case.ContainsKey('Append')) { Assert-PfcTrue -Actual ($instructions.Groups['body'].Value.Contains($case.Append)) -ScenarioId $case.Id -Expected 'permission inside developer_instructions' }
                [IO.File]::WriteAllText($path, $mutated, (New-Object Text.UTF8Encoding($false)))
                if ($case.Id -notin @('budget','budget-exception','full-protocol-copy')) {
                    Assert-PfcEqual -Expected 'PASS' -Actual (Measure-PfcAgentPromptBudget -Path ([IO.FileInfo]$path)).status -ScenarioId ($case.Id + '.budget')
                }
                $expected = if ($case.ContainsKey('Expected')) { $case.Expected } else { 'FAIL' }
                Assert-BuilderProfileStatus -Root (Get-Item $fixture) -Expected $expected -ScenarioId $case.Id
                if ($case.ContainsKey('Append') -and $expected -eq 'FAIL' -and $case.Id -notin @('budget','budget-exception','full-protocol-copy')) {
                    $check = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase $Phase | Where-Object ScenarioId -eq 'package.builder.profile')
                    Assert-PfcTrue -Actual ($check[0].Message -match 'forbidden authority') -ScenarioId $case.Id -Expected 'authority rejection independent of budget'
                }
            } finally {
                if ((Split-Path -Parent ([IO.Path]::GetFullPath($fixture))) -cne ([IO.Path]::GetTempPath().TrimEnd('\'))) { throw 'Unsafe fixture cleanup path' }
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }
    }
    Add-BuilderProfileResult 'builder.profile.budget-boundaries' {
        $fixture = New-BuilderProfileFixture -Id 'budget-boundary' -Mutate { param($root) }
        try {
            $path = Join-Path $fixture 'codex-agents/project-flight-builder.toml'
            foreach ($case in @(@{Bytes=3212;Status='PASS'},@{Bytes=3213;Status='FAIL'},@{Bytes=3215;Status='FAIL'})) {
                [IO.File]::WriteAllText($path, ('x' * $case.Bytes), (New-Object Text.UTF8Encoding($false)))
                $budget = Measure-PfcAgentPromptBudget -Path ([IO.FileInfo]$path)
                Assert-PfcEqual -Expected $case.Status -Actual $budget.status -ScenarioId ('builder.bytes.' + $case.Bytes)
                Assert-PfcEqual -Expected 2795 -Actual $budget.baseline_utf8_bytes -ScenarioId 'builder.frozen-bytes'
                Assert-PfcEqual -Expected 699 -Actual $budget.baseline_conservative_estimated_tokens -ScenarioId 'builder.frozen-tokens'
                Assert-PfcEqual -Expected 'NOT_AVAILABLE' -Actual $budget.token_data_status -ScenarioId 'builder.token-estimate-only'
            }
        } finally {
            if ((Split-Path -Parent ([IO.Path]::GetFullPath($fixture))) -cne ([IO.Path]::GetTempPath().TrimEnd('\'))) { throw 'Unsafe fixture cleanup path' }
            Remove-Item -LiteralPath $fixture -Recurse -Force
        }
    }
    Add-BuilderProfileResult 'builder.profile.reject.third-fixed-agent' {
        $fixture = New-BuilderProfileFixture -Id 'third-agent' -Mutate { param($root) }
        try {
            Copy-Item (Join-Path $RepositoryRoot 'codex-agents/project-flight-verifier.toml') (Join-Path $fixture 'codex-agents/project-flight-verifier.toml')
            Copy-Item (Join-Path $fixture 'codex-agents/project-flight-builder.toml') (Join-Path $fixture 'codex-agents/third.toml')
            $checks = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase $Phase | Where-Object { $_.ScenarioId -in @('package.formal_agents.count','package.custom_agent.fields') })
            Assert-PfcTrue -Actual ($checks.Count -eq 2 -and @($checks | Where-Object Status -ne 'FAIL').Count -eq 0) -ScenarioId 'third-agent' -Expected 'fixed Agent count and names rejected'
        } finally {
            if ((Split-Path -Parent ([IO.Path]::GetFullPath($fixture))) -cne ([IO.Path]::GetTempPath().TrimEnd('\'))) { throw 'Unsafe fixture cleanup path' }
            Remove-Item -LiteralPath $fixture -Recurse -Force
        }
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
