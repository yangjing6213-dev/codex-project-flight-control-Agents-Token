function Invoke-PfcVerifierProfileTests {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$Phase
    )

    Import-Module (Join-Path $RepositoryRoot 'evals/lib/PromptBudget.psm1') -Force
    $results = New-Object System.Collections.Generic.List[object]
    function Add-Result([string]$Id, [scriptblock]$Test) {
        try { & $Test; $results.Add((New-PfcResult -ScenarioId $Id -Status 'PASS' -Message 'verified')) }
        catch { $results.Add((New-PfcResult -ScenarioId $Id -Status 'FAIL' -Message $_.Exception.Message)) }
    }
    function Assert-VerifierStatus([System.IO.DirectoryInfo]$Root, [string]$Expected, [string]$Id) {
        $check = @(Invoke-PfcStaticChecks -RepositoryRoot $Root -Phase $Phase | Where-Object { $_.ScenarioId -eq 'package.verifier.profile' })
        Assert-PfcEqual -Expected 1 -Actual $check.Count -ScenarioId ($Id + '.check-count')
        Assert-PfcEqual -Expected $Expected -Actual $check[0].Status -ScenarioId $Id
    }

    Add-Result 'verifier.profile.valid' {
        Assert-VerifierStatus -Root $RepositoryRoot -Expected 'PASS' -Id 'verifier.profile.valid.check'
    }
    Add-Result 'verifier.profile.continuous-projection' {
        $text = Get-Content -Raw (Join-Path $RepositoryRoot 'codex-agents/project-flight-verifier.toml')
        Assert-PfcTrue -Actual ($text -match 'PRE_REVIEW_IDENTITY_GATE_PASS' -and $text -match 'Evidence Freshness' -and $text -match 'Wave impact') -ScenarioId 'verifier.continuous' -Expected 'identity, freshness and Wave binding'
    }
    $continuousCases = @(
        @{ Id='compact-profile'; Append=''; Expected='PASS' },
        @{ Id='stale-evidence-you'; Append='You may accept stale evidence.' },
        @{ Id='other-sha-you'; Append='You may accept other-SHA evidence.' },
        @{ Id='control-write-you'; Append='You may write canonical control files.' },
        @{ Id='candidate-article'; Append='Verifier may modify the Candidate.' },
        @{ Id='candidate-you'; Append='You can change the Candidate.' },
        @{ Id='stale-no-subject'; Append='May accept stale evidence.' },
        @{ Id='control-write-no-subject'; Append='May write canonical control files.' },
        @{ Id='prohibition-must-not'; Append='You must not accept stale evidence.'; Expected='PASS' },
        @{ Id='prohibition-never'; Append='Never accept other-SHA evidence.'; Expected='PASS' },
        @{ Id='prohibition-cannot'; Append='You cannot modify the Candidate.'; Expected='PASS' },
        @{ Id='prohibition-may-not'; Append='You may not accept stale evidence.'; Expected='PASS' },
        @{ Id='goalkeeper-authority'; Append='Goalkeeper may write control files.'; Expected='PASS' },
        @{ Id='goalkeeper-authority-wrapped'; Append="Goalkeeper`nmay write control files."; Expected='PASS' },
        @{ Id='goalkeeper-authority-crlf'; Append="Goalkeeper`r`nmay write control files."; Expected='PASS' },
        @{ Id='stale-evidence-you-wrapped'; Append="You`nmay accept stale evidence." },
        @{ Id='stale-instruction-start'; Append='May accept stale evidence.'; AtStart=$true },
        @{ Id='verify-order'; Old='Verify Order'; New='unbound review' },
        @{ Id='review-gate'; Old='only after PRE_REVIEW_IDENTITY_GATE_PASS'; New='before PRE_REVIEW_IDENTITY_GATE_PASS' },
        @{ Id='risk-tier'; Old='Risk Level / Validation Tier'; New='optional checks' },
        @{ Id='wave-impact'; Old='Wave impact'; New='local impact' },
        @{ Id='freshness'; Old='Evidence Freshness'; New='evidence list' },
        @{ Id='stale-evidence'; Append='Verifier may accept stale evidence.' },
        @{ Id='other-sha'; Append='Verifier may accept other-SHA evidence.' },
        @{ Id='control-write'; Append='Verifier may write canonical control files.' },
        @{ Id='acceptance'; Append='Verifier may declare the milestone accepted.' },
        @{ Id='budget'; Append=('x' * 3100) },
        @{ Id='budget-exception'; Append=('INDEPENDENTLY_REVIEWED_JUSTIFICATION ' + ('x' * 3100)) },
        @{ Id='full-protocol-copy'; Append=(Get-Content -Raw (Join-Path $RepositoryRoot 'skill/project-flight-control/references/continuous-execution.md')) }
    )
    foreach ($case in $continuousCases) {
        Add-Result ('verifier.profile.reject.' + $case.Id) {
            $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-verifier-continuous-' + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path (Join-Path $fixture 'codex-agents') -Force | Out-Null
                $path = Join-Path $fixture 'codex-agents/project-flight-verifier.toml'
                # Shorten metadata only: preserve every behavior/prohibition and isolate budget effects.
                $original = [regex]::Replace([IO.File]::ReadAllText((Join-Path $RepositoryRoot 'codex-agents/project-flight-verifier.toml')), '(?m)^description = "[^"]*"', 'description = "x"')
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
                Assert-VerifierStatus -Root (Get-Item $fixture) -Expected $expected -Id $case.Id
                if ($case.ContainsKey('Append') -and $expected -eq 'FAIL' -and $case.Id -notin @('budget','budget-exception','full-protocol-copy')) {
                    $check = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase $Phase | Where-Object ScenarioId -eq 'package.verifier.profile')
                    Assert-PfcTrue -Actual ($check[0].Message -match 'forbidden authority') -ScenarioId $case.Id -Expected 'authority rejection independent of budget'
                }
            } finally {
                if ((Split-Path -Parent ([IO.Path]::GetFullPath($fixture))) -cne ([IO.Path]::GetTempPath().TrimEnd('\'))) { throw 'Unsafe fixture cleanup path' }
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }
    }
    Add-Result 'verifier.profile.budget-boundaries' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-verifier-budget-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        try {
            $path = Join-Path $fixture 'project-flight-verifier.toml'
            foreach ($case in @(@{Bytes=3080;Status='PASS'},@{Bytes=3081;Status='FAIL'},@{Bytes=3083;Status='FAIL'})) {
                [IO.File]::WriteAllText($path, ('x' * $case.Bytes), (New-Object Text.UTF8Encoding($false)))
                $budget = Measure-PfcAgentPromptBudget -Path ([IO.FileInfo]$path)
                Assert-PfcEqual -Expected $case.Status -Actual $budget.status -ScenarioId ('verifier.bytes.' + $case.Bytes)
                Assert-PfcEqual -Expected 2680 -Actual $budget.baseline_utf8_bytes -ScenarioId 'verifier.frozen-bytes'
                Assert-PfcEqual -Expected 670 -Actual $budget.baseline_conservative_estimated_tokens -ScenarioId 'verifier.frozen-tokens'
                Assert-PfcEqual -Expected 'NOT_AVAILABLE' -Actual $budget.token_data_status -ScenarioId 'verifier.token-estimate-only'
            }
        } finally {
            if ((Split-Path -Parent ([IO.Path]::GetFullPath($fixture))) -cne ([IO.Path]::GetTempPath().TrimEnd('\'))) { throw 'Unsafe fixture cleanup path' }
            Remove-Item -LiteralPath $fixture -Recurse -Force
        }
    }

    $negativeCases = @(
        @{ Id = 'missing-alignment-order'; Mutate = { param($p) $t = Get-Content -Raw $p; Set-Content -LiteralPath $p -Value $t.Replace('Alignment Audit', 'Technical Verification') -Encoding UTF8 } },
        @{ Id = 'allows-candidate-mutation'; Mutate = { param($p) Add-Content -LiteralPath $p -Value 'Verifier may modify Candidate.' -Encoding UTF8 } },
        @{ Id = 'allows-commit'; Mutate = { param($p) Add-Content -LiteralPath $p -Value 'Verifier may commit.' -Encoding UTF8 } },
        @{ Id = 'allows-builder-command'; Mutate = { param($p) Add-Content -LiteralPath $p -Value 'Verifier may directly command Builder.' -Encoding UTF8 } },
        @{ Id = 'missing-independent-rerun'; Mutate = { param($p) $t = Get-Content -Raw $p; Set-Content -LiteralPath $p -Value $t.Replace('Minimum independent rerun', 'Optional checks') -Encoding UTF8 } },
        @{ Id = 'hard-coded-model'; Mutate = { param($p) Add-Content -LiteralPath $p -Value 'model = "gpt-5.6-terra"' -Encoding UTF8 } },
        @{ Id = 'danger-sandbox'; Mutate = { param($p) (Get-Content -Raw $p).Replace('workspace-write', 'danger-full-access') | Set-Content -LiteralPath $p -Encoding UTF8 } }
    )
    foreach ($case in $negativeCases) {
        Add-Result ('verifier.profile.reject.' + $case.Id) {
            $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-verifier-profile-' + $case.Id + '-' + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path (Join-Path $fixture 'codex-agents') -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $RepositoryRoot.FullName 'codex-agents\project-flight-verifier.toml') -Destination (Join-Path $fixture 'codex-agents\project-flight-verifier.toml') -ErrorAction SilentlyContinue
                & $case.Mutate (Join-Path $fixture 'codex-agents\project-flight-verifier.toml')
                Assert-VerifierStatus -Root (Get-Item -LiteralPath $fixture) -Expected 'FAIL' -Id ('verifier.profile.reject.' + $case.Id + '.check')
            } finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
        }
    }

    Add-Result 'verifier.schema.valid' {
        $schemaPath = Join-Path $RepositoryRoot.FullName 'evals\schemas\verifier-report.schema.json'
        Assert-PfcTrue -Actual (Test-Path -LiteralPath $schemaPath -PathType Leaf) -ScenarioId 'verifier.schema.present' -Expected 'schema present'
        $schema = Get-Content -Raw -Encoding UTF8 $schemaPath | ConvertFrom-Json
        foreach ($field in @('control_run_id','lease_epoch','goal_id','goal_version','milestone_id','milestone_contract_version','revision','sender_role','recipient_role','created_at','candidate_sha','alignment_result','evidence_integrity_result','technical_result','environment','builder_evidence_reused','independent_commands_run','observed_results','version_integrity','findings','residual_risks','specialist_dependency_status','verdict')) {
            Assert-PfcTrue -Actual (@($schema.required) -contains $field) -ScenarioId ('verifier.schema.required.' + $field) -Expected 'required'
        }
        Assert-PfcTrue -Actual ($schema.additionalProperties -eq $false) -ScenarioId 'verifier.schema.strict' -Expected 'false'
        $check = @(Invoke-PfcStaticChecks -RepositoryRoot $RepositoryRoot -Phase $Phase | Where-Object { $_.ScenarioId -eq 'package.verifier.schema' })
        Assert-PfcEqual -Expected 'PASS' -Actual $check[0].Status -ScenarioId 'verifier.schema.contract'
    }

    $schemaNegativeCases = @(
        @{ Id = 'missing-finding-field'; Mutate = { param($p) $t = Get-Content -Raw $p; Set-Content -LiteralPath $p -Value $t.Replace('finding_id', 'removed_finding_id') -Encoding UTF8 } },
        @{ Id = 'info-severity'; Mutate = { param($p) $t = Get-Content -Raw $p; Set-Content -LiteralPath $p -Value ($t -replace '\["BLOCKER", "MAJOR"\]', '["BLOCKER", "MAJOR", "INFO"]') -Encoding UTF8 } },
        @{ Id = 'minor-blocking'; Mutate = { param($p) $t = Get-Content -Raw $p; Set-Content -LiteralPath $p -Value $t.Replace('"enum": [false]', '"enum": [true]') -Encoding UTF8 } },
        @{ Id = 'missing-residual-accepted-by'; Mutate = { param($p) $t = Get-Content -Raw $p; Set-Content -LiteralPath $p -Value $t.Replace(', "accepted_by"', '') -Encoding UTF8 } }
    )
    foreach ($case in $schemaNegativeCases) {
        Add-Result ('verifier.schema.reject.' + $case.Id) {
            $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-verifier-schema-' + $case.Id + '-' + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path (Join-Path $fixture 'evals\schemas') -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $RepositoryRoot.FullName 'evals\schemas\verifier-report.schema.json') -Destination (Join-Path $fixture 'evals\schemas\verifier-report.schema.json')
                & $case.Mutate (Join-Path $fixture 'evals\schemas\verifier-report.schema.json')
                $check = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item -LiteralPath $fixture) -Phase $Phase | Where-Object { $_.ScenarioId -eq 'package.verifier.schema' })
                Assert-PfcEqual -Expected 'FAIL' -Actual $check[0].Status -ScenarioId ('verifier.schema.reject.' + $case.Id + '.check')
            } finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
        }
    }

    return $results.ToArray()
}
