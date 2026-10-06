function Invoke-PfcContinuousContractTests {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$RepositoryRoot)

    $results = New-Object System.Collections.Generic.List[object]
    function Add-ContractCheck([string]$Id, [string]$Requirement, [scriptblock]$Assertion) {
        try {
            & $Assertion
            $results.Add((New-PfcResult -ScenarioId $Id -Status 'PASS' -Message 'verified'))
        } catch {
            $results.Add((New-PfcResult -ScenarioId $Id -Status 'FAIL' -Message ($Requirement + ': ' + $_.Exception.Message)))
        }
    }
    function Get-RequiredText([string]$RelativePath) {
        $path = Join-Path $RepositoryRoot.FullName $RelativePath
        Assert-PfcTrue -Actual (Test-Path -LiteralPath $path -PathType Leaf) -ScenarioId ('continuous.path.' + $RelativePath.Replace('\\', '.').Replace('/', '.')) -Expected 'present'
        return Get-Content -Raw -Encoding UTF8 -LiteralPath $path
    }
    function Assert-ContainsAll([string]$Text, [string[]]$Terms, [string]$ScenarioId) {
        foreach ($term in $Terms) {
            Assert-PfcTrue -Actual ($Text -match $term) -ScenarioId $ScenarioId -Expected ('required term: ' + $term)
        }
    }
    function Get-RequiredSection([string]$Text, [string]$Heading, [string]$ScenarioId) {
        $pattern = '(?ms)^##\s+' + [regex]::Escape($Heading) + '\s*$.*?(?=^##\s|\z)'
        $section = [regex]::Match($Text, $pattern)
        Assert-PfcTrue -Actual $section.Success -ScenarioId $ScenarioId -Expected ('section: ' + $Heading)
        return $section.Value
    }
    function Assert-StableAuthorization([string]$Text, [string]$ScenarioId) {
        $section = Get-RequiredSection -Text $Text -Heading 'Stable Authorization and Runtime Lease' -ScenarioId $ScenarioId
        Assert-ContainsAll -Text $section -Terms @('Authorization', 'Control Run ID', 'Lease Epoch', 'STATUS', 'Continuation Checkpoint') -ScenarioId $ScenarioId
        Assert-PfcTrue -Actual ($section -match 'Authorization[^\r\n]*(does not|must not|cannot)[^\r\n]*Control Run ID') -ScenarioId $ScenarioId -Expected 'Authorization excludes Control Run ID'
        Assert-PfcTrue -Actual ($section -match 'Authorization[^\r\n]*(does not|must not|cannot)[^\r\n]*Lease Epoch') -ScenarioId $ScenarioId -Expected 'Authorization excludes Lease Epoch'
        Assert-PfcTrue -Actual (-not ($section -match 'Authorization[^\r\n]*(stores|contains)[^\r\n]*(Control Run ID|Lease Epoch)')) -ScenarioId $ScenarioId -Expected 'Authorization has no runtime lease fields'
        Assert-PfcTrue -Actual ($section -match 'Control Run ID[^\r\n]*(STATUS|Continuation Checkpoint)') -ScenarioId $ScenarioId -Expected 'Control Run ID is runtime state'
        Assert-PfcTrue -Actual ($section -match 'Lease Epoch[^\r\n]*(STATUS|Continuation Checkpoint)') -ScenarioId $ScenarioId -Expected 'Lease Epoch is runtime state'
    }
    function Assert-IdentityGates([string]$Text, [string]$ScenarioId) {
        $preWrite = Get-RequiredSection -Text $Text -Heading 'Pre-write Identity Gate' -ScenarioId $ScenarioId
        Assert-ContainsAll -Text $preWrite -Terms @('PRE_WRITE_IDENTITY_GATE_PASS', 'Repository Identity', 'Exact Branch', 'Authorized Base Checkpoint SHA', 'Expected Builder Start SHA', 'Actual Worktree HEAD', 'Writable Path Hash', 'Forbidden Path Hash', 'Control Run ID', 'Lease Epoch') -ScenarioId $ScenarioId
        $preReview = Get-RequiredSection -Text $Text -Heading 'Pre-review Identity Gate' -ScenarioId $ScenarioId
        Assert-ContainsAll -Text $preReview -Terms @('PRE_REVIEW_IDENTITY_GATE_PASS', 'Repository Identity', 'Base SHA', 'Candidate SHA', 'Changed Files', 'Path Policy', 'Builder Evidence SHA', 'Wave ID') -ScenarioId $ScenarioId
    }
    function Assert-StopGateOrder([string]$Text, [string]$ScenarioId) {
        $section = Get-RequiredSection -Text $Text -Heading 'T3 PASS Transition Order' -ScenarioId $ScenarioId
        $steps = @($section -split "`r?`n" | Where-Object { $_ -match '^\d+\.\s' })
        Assert-PfcEqual -Expected 5 -Actual $steps.Count -ScenarioId ($ScenarioId + '.step-count')
        $requiredSteps = @('Persist WAVE_SUMMARY', 'Evaluate Stop Gate', 'Evaluate authorization scope exhaustion', 'Recheck Authorization', 'Select next Wave')
        for ($index = 0; $index -lt $requiredSteps.Count; $index++) {
            Assert-PfcTrue -Actual ($steps[$index] -match [regex]::Escape($requiredSteps[$index])) -ScenarioId ($ScenarioId + '.step-' + ($index + 1)) -Expected $requiredSteps[$index]
        }
    }
    function Assert-RepairLimits([string]$Text, [string]$ScenarioId) {
        $section = Get-RequiredSection -Text $Text -Heading 'Independent Repair Limits' -ScenarioId $ScenarioId
        $builderLines = @($section -split "`r?`n" | Where-Object { $_ -match '^Builder repair attempts:' })
        Assert-PfcEqual -Expected 1 -Actual $builderLines.Count -ScenarioId ($ScenarioId + '.builder-line-count')
        $builderCap = [regex]::Match($builderLines[0], '^Builder repair attempts:\s*(?:at most|maximum)\s+(\d+)\.\s*$')
        Assert-PfcTrue -Actual $builderCap.Success -ScenarioId $ScenarioId -Expected 'complete Builder repair cap'
        Assert-PfcEqual -Expected 2 -Actual ([int]$builderCap.Groups[1].Value) -ScenarioId ($ScenarioId + '.builder-cap')
        $reworkLines = @($section -split "`r?`n" | Where-Object { $_ -match '^automatic REWORK rounds:' })
        Assert-PfcEqual -Expected 1 -Actual $reworkLines.Count -ScenarioId ($ScenarioId + '.rework-line-count')
        $reworkCap = [regex]::Match($reworkLines[0], '^automatic REWORK rounds:\s*(?:at most|maximum)\s+(\d+)\.\s*$')
        Assert-PfcTrue -Actual $reworkCap.Success -ScenarioId $ScenarioId -Expected 'complete automatic REWORK cap'
        Assert-PfcEqual -Expected 2 -Actual ([int]$reworkCap.Groups[1].Value) -ScenarioId ($ScenarioId + '.rework-cap')
        Assert-PfcTrue -Actual ($section -match 'counters[^\r\n]*independent') -ScenarioId $ScenarioId -Expected 'repair counters remain independent'
        Assert-PfcTrue -Actual ($section -match 'Candidate[^\r\n]*only\s+R1,\s*R2,\s*R3') -ScenarioId $ScenarioId -Expected 'Candidate revisions are only R1-R3'
        Assert-PfcTrue -Actual ($section -match 'R4[^\r\n]*(rejected|forbidden)') -ScenarioId $ScenarioId -Expected 'R4 is rejected'
        Assert-PfcTrue -Actual (-not ($section -match 'R4[^\r\n]*(permitted|allowed)')) -ScenarioId $ScenarioId -Expected 'R4 cannot be permitted'
    }
    function Assert-ConditionalRoutes([string]$Text, [string]$ScenarioId) {
        $rules = @(
            @{ File = 'continuous-execution.md'; Predicate = 'START.*CONTINUOUS_MODE|RESUME.*CONTINUOUS_MODE' },
            @{ File = 'risk-validation-policy.md'; Predicate = 'risk|validation' },
            @{ File = 'blocker-classification.md'; Predicate = 'blocker|classification|issue' },
            @{ File = 'readiness-and-recovery.md'; Predicate = 'readiness|recovery|dirty' }
        )
        foreach ($rule in $rules) {
            $routes = @($Text -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($rule.File) })
            Assert-PfcEqual -Expected 1 -Actual $routes.Count -ScenarioId ($ScenarioId + '.' + $rule.File)
            $route = [regex]::Match($routes[0], ('(?i)^\s*-\s*only when\s+(?<predicate>.+?)\s*:\s*' + [regex]::Escape($rule.File) + '\s*$'))
            Assert-PfcTrue -Actual $route.Success -ScenarioId ($ScenarioId + '.' + $rule.File) -Expected 'only-when predicate before route target'
            Assert-PfcTrue -Actual ($route.Groups['predicate'].Value -match ('(?i)' + $rule.Predicate)) -ScenarioId ($ScenarioId + '.' + $rule.File) -Expected $rule.Predicate
        }
        Assert-PfcTrue -Actual (-not ($Text -match '(?i)(always|unconditionally)\s+load.*(four.*references|continuous-execution\.md|risk-validation-policy\.md|blocker-classification\.md|readiness-and-recovery\.md)')) -ScenarioId ($ScenarioId + '.no-unconditional-load') -Expected 'no unconditional V2 reference loading'
    }
    function Assert-Rejected([string]$Id, [scriptblock]$Assertion) {
        $rejected = $false
        try { & $Assertion } catch { $rejected = $true }
        Assert-PfcTrue -Actual $rejected -ScenarioId $Id -Expected 'conflicting contract rejected'
    }

    $skill = Get-RequiredText 'skill\project-flight-control\SKILL.md'
    Add-ContractCheck 'continuous.skill.entry-policy' 'missing explicit START/RESUME CONTINUOUS_MODE route or V1 default pause' {
        Assert-ContainsAll -Text $skill -Terms @('START\s+CONTINUOUS_MODE', 'RESUME\s+CONTINUOUS_MODE', 'PAUSE_AFTER_MILESTONE') -ScenarioId 'continuous.skill.entry-policy'
        Assert-PfcTrue -Actual ($skill -match 'START.*RESUME.*AUDIT.*STATUS_ONLY') -ScenarioId 'continuous.skill.top-level-modes' -Expected 'exactly four top-level modes retained'
        Assert-PfcTrue -Actual ($skill -match '(?i)not a fifth top-level mode|not a fifth mode') -ScenarioId 'continuous.skill.no-fifth-mode' -Expected 'CONTINUOUS_MODE remains a policy'
    }
    Add-ContractCheck 'continuous.skill.conditional-references' 'missing conditional routes for the four V2 references' {
        Assert-ConditionalRoutes -Text $skill -ScenarioId 'continuous.skill.conditional-references'
    }

    Add-ContractCheck 'continuous.references.execution-and-identity' 'missing continuous execution authorization, lease, Wave, or identity-gate contract' {
        $text = Get-RequiredText 'skill\project-flight-control\references\continuous-execution.md'
        Assert-ContainsAll -Text $text -Terms @('Wave', 'one to five') -ScenarioId 'continuous.references.execution-and-identity'
        Assert-StableAuthorization -Text $text -ScenarioId 'continuous.references.authorization-runtime-separation'
        Assert-IdentityGates -Text $text -ScenarioId 'continuous.references.identity-gates'
        Assert-StopGateOrder -Text $text -ScenarioId 'continuous.references.stop-gate-order'
    }
    Add-ContractCheck 'continuous.references.risk-and-validation' 'missing LOW/MEDIUM/HIGH risk or T1-T4 validation contract' {
        $text = Get-RequiredText 'skill\project-flight-control\references\risk-validation-policy.md'
        Assert-ContainsAll -Text $text -Terms @('LOW', 'MEDIUM', 'HIGH', 'T1', 'T2', 'T3', 'T4') -ScenarioId 'continuous.references.risk-and-validation'
    }
    Add-ContractCheck 'continuous.references.repair-limits' 'missing independent repair, rework, or Candidate revision limits' {
        $text = Get-RequiredText 'skill\project-flight-control\references\blocker-classification.md'
        Assert-RepairLimits -Text $text -ScenarioId 'continuous.references.repair-limits'
    }
    Add-ContractCheck 'continuous.references.recovery-fail-closed' 'missing recovery readiness or stop-before-write behavior' {
        $text = Get-RequiredText 'skill\project-flight-control\references\readiness-and-recovery.md'
        Assert-ContainsAll -Text $text -Terms @('RECOVERY_REQUIRED', 'STOP_BEFORE_WRITE', 'unknown', 'fail closed') -ScenarioId 'continuous.references.recovery-fail-closed'
    }

    Add-ContractCheck 'continuous.agents.fixed-count' 'fixed Agent TOMLs are not exactly Builder and Verifier' {
        $agents = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot.FullName 'codex-agents') -File -Filter '*.toml' | ForEach-Object { $_.Name } | Sort-Object)
        Assert-PfcEqual -Expected 'project-flight-builder.toml,project-flight-verifier.toml' -Actual ($agents -join ',') -ScenarioId 'continuous.agents.fixed-count'
    }
    Add-ContractCheck 'continuous.builder.pre-write-projection' 'Builder lacks required pre-write identity and bounded-continuation projection' {
        $text = Get-RequiredText 'codex-agents\project-flight-builder.toml'
        Assert-ContainsAll -Text $text -Terms @('Authorization ID', 'Wave ID', 'Repository Identity', 'Exact Branch', 'Expected Builder Start SHA', 'Writable Path Hash', 'Forbidden Path Hash', 'Lease Epoch', 'before any business-file write', 'must not start the next milestone') -ScenarioId 'continuous.builder.pre-write-projection'
    }
    Add-ContractCheck 'continuous.verifier.pre-review-projection' 'Verifier lacks required pre-review identity, risk, and Wave projection' {
        $text = Get-RequiredText 'codex-agents\project-flight-verifier.toml'
        Assert-ContainsAll -Text $text -Terms @('Authorization ID', 'Wave ID', 'Repository Identity', 'Base SHA', 'Candidate SHA', 'Changed Files', 'Path Policy', 'Risk Level', 'Validation Tier', 'PRE_REVIEW_IDENTITY_GATE_PASS', 'Wave impact') -ScenarioId 'continuous.verifier.pre-review-projection'
    }
    Add-ContractCheck 'continuous.contract.negative-self-check' 'contract relation negative self-check failed' {
        $validAuthorization = @'
## Stable Authorization and Runtime Lease
Authorization cannot store Control Run ID and cannot store Lease Epoch.
Control Run ID belongs in STATUS or Continuation Checkpoint.
Lease Epoch belongs in STATUS or Continuation Checkpoint.
'@
        $mergedAuthorization = @'
## Stable Authorization and Runtime Lease
Authorization cannot store Control Run ID and cannot store Lease Epoch.
Authorization stores Control Run ID and Lease Epoch permanently.
Control Run ID belongs in STATUS or Continuation Checkpoint.
Lease Epoch belongs in STATUS or Continuation Checkpoint.
'@
        Assert-StableAuthorization -Text $validAuthorization -ScenarioId 'continuous.self.authorization.valid'
        Assert-Rejected -Id 'continuous.self.authorization.merged-rejected' -Assertion { Assert-StableAuthorization -Text $mergedAuthorization -ScenarioId 'continuous.self.authorization.merged' }

        $validOrder = @'
## T3 PASS Transition Order
1. Persist WAVE_SUMMARY.
2. Evaluate Stop Gate.
3. Evaluate authorization scope exhaustion.
4. Recheck Authorization.
5. Select next Wave.
'@
        $reversedOrder = @'
## T3 PASS Transition Order
1. Persist WAVE_SUMMARY.
2. Evaluate authorization scope exhaustion.
3. Evaluate Stop Gate.
4. Recheck Authorization.
5. Select next Wave.
'@
        Assert-StopGateOrder -Text $validOrder -ScenarioId 'continuous.self.stop-order.valid'
        Assert-Rejected -Id 'continuous.self.stop-order.reversed-rejected' -Assertion { Assert-StopGateOrder -Text $reversedOrder -ScenarioId 'continuous.self.stop-order.reversed' }

        $validLimits = @'
## Independent Repair Limits
Builder repair attempts: at most 2.
automatic REWORK rounds: at most 2.
The counters remain independent.
Candidate revisions: only R1, R2, R3.
R4 is forbidden.
'@
        Assert-RepairLimits -Text $validLimits -ScenarioId 'continuous.self.limits.valid'
        $builderTwenty = $validLimits.Replace('Builder repair attempts: at most 2.', 'Builder repair attempts: at most 20.')
        Assert-Rejected -Id 'continuous.self.limits.builder-twenty-rejected' -Assertion { Assert-RepairLimits -Text $builderTwenty -ScenarioId 'continuous.self.limits.builder-twenty' }
        $reworkTwenty = $validLimits.Replace('automatic REWORK rounds: at most 2.', 'automatic REWORK rounds: at most 20.')
        Assert-Rejected -Id 'continuous.self.limits.rework-twenty-rejected' -Assertion { Assert-RepairLimits -Text $reworkTwenty -ScenarioId 'continuous.self.limits.rework-twenty' }
        $permittedR4 = $validLimits.Replace('R4 is forbidden.', 'R4 is permitted.')
        Assert-Rejected -Id 'continuous.self.limits.r4-permitted-rejected' -Assertion { Assert-RepairLimits -Text $permittedR4 -ScenarioId 'continuous.self.limits.r4-permitted' }

        $conditionalRoutes = @'
- only when START CONTINUOUS_MODE or RESUME CONTINUOUS_MODE: continuous-execution.md
- only when risk or validation selection is needed: risk-validation-policy.md
- only when blocker classification or issue handling is needed: blocker-classification.md
- only when readiness, recovery, or dirty-state handling is needed: readiness-and-recovery.md
'@
        $unconditionalRoutes = @'
- load continuous-execution.md
- load risk-validation-policy.md
- load blocker-classification.md
- load readiness-and-recovery.md
- always load all four references
'@
        Assert-ConditionalRoutes -Text $conditionalRoutes -ScenarioId 'continuous.self.routes.valid'
        Assert-Rejected -Id 'continuous.self.routes.unconditional-rejected' -Assertion { Assert-ConditionalRoutes -Text $unconditionalRoutes -ScenarioId 'continuous.self.routes.unconditional' }
        foreach ($file in @('risk-validation-policy.md', 'blocker-classification.md', 'readiness-and-recovery.md')) {
            $wrongPredicateRoutes = $conditionalRoutes -replace ('(?m)^- only when .+?:\s*' + [regex]::Escape($file) + '$'), ('- only when the moon is blue: ' + $file)
            Assert-Rejected -Id ('continuous.self.routes.' + $file + '.wrong-predicate-rejected') -Assertion { Assert-ConditionalRoutes -Text $wrongPredicateRoutes -ScenarioId ('continuous.self.routes.' + $file + '.wrong-predicate') }
        }
    }

    return $results.ToArray()
}
