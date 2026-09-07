function Invoke-PfcVerifierProfileTests {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$Phase
    )

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
