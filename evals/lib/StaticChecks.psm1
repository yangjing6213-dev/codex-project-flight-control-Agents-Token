Set-StrictMode -Version 2.0
$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PromptBudget.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'CodexRunner.psm1')

function Get-PfcV2TemplateBindings {
    param([System.IO.DirectoryInfo]$RepositoryRoot)
    $text = Get-Content -Raw -Encoding UTF8 (Join-Path $RepositoryRoot.FullName 'skill/project-flight-control/references/message-contracts.md')
    $fence = ([string][char]96) * 3
    $match = [regex]::Match($text, ('(?ms)^## V2 Template Bindings\s+.*?^' + $fence + 'json\s+(?<json>.*?)^' + $fence))
    if (-not $match.Success) { throw 'V2 template binding authority missing' }
    return ($match.Groups['json'].Value | ConvertFrom-Json)
}

# Local control-contract checks, not an extension of the frozen V1 JSON Schema engine.
# Git ancestry, user approval, preserved bytes and fresh evidence still require runtime gates.
function Test-PfcV2SchemaValue {
    param($Value, $Schema)
    function Test-ExactPropertyNames($Actual, $Node) {
        if ($Node.type -eq 'object') {
            if ($null -eq $Actual -or $Actual -is [string] -or $Actual -is [ValueType] -or $Actual -is [Array]) { return $false }
            $actualNames = @($Actual.PSObject.Properties | ForEach-Object { $_.Name })
            $allowedNames = @($Node.properties.PSObject.Properties | ForEach-Object { $_.Name })
            foreach ($name in $Node.required) { if ($actualNames -cnotcontains $name) { return $false } }
            foreach ($name in $actualNames) { if ($allowedNames -cnotcontains $name) { return $false } }
            foreach ($property in $Node.properties.PSObject.Properties) {
                if (-not (Test-ExactPropertyNames $Actual.($property.Name) $property.Value)) { return $false }
            }
        } elseif ($Node.type -eq 'array') {
            if ($Actual -isnot [Array]) { return $false }
            foreach ($item in $Actual) { if (-not (Test-ExactPropertyNames $item $Node.items)) { return $false } }
        }
        return $true
    }
    if (-not (Test-ExactPropertyNames $Value $Schema)) { return $false }
    return (& (Get-Module CodexRunner) { param($v,$s) Test-PfcSchemaValue -Value $v -Schema $s } $Value $Schema)
}

function Test-PfcV2GitBranch {
    param([string]$Branch)
    try {
        $checked = @(& git check-ref-format --branch $Branch 2>$null)
        return ($LASTEXITCODE -eq 0 -and $checked.Count -eq 1 -and $checked[0] -ceq $Branch)
    } catch { return $false }
}

function Test-PfcV2ControlSemantics {
    param([string]$Name, $Value)
    function Test-Date([string]$Text) {
        $date = [datetime]::MinValue
        return [datetime]::TryParseExact($Text, 'yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)
    }
    function Test-Unique($Items) { return @($Items).Count -eq @($Items | Sort-Object -Unique).Count }
    function Test-Validation($Record) {
        if ([string]::IsNullOrWhiteSpace($Record.applicability_reason)) { return $false }
        if ($Record.required -and @($Record.checks).Count -eq 0) { return $false }
        if ($Record.result -eq 'PASS' -and @($Record.evidence).Count -eq 0) { return $false }
        return (Test-Unique @($Record.evidence | ForEach-Object { $_.evidence_id }))
    }
    try {
        switch ($Name) {
            'continuous-authorization' {
                $triggers = @('CONTRACT_CHANGE','AUTHORIZED_SCOPE_EXHAUSTED','STOP_GATE_REACHED','BASELINE_DRIFT','BRANCH_CHANGE','UNKNOWN_DIRTY_WORKTREE','USER_PAUSE','HARD_BLOCKER','GOAL_CHANGE')
                return ($Value.goal.goal_version -ge 1 -and
                    (Test-Date $Value.approval.approved_at) -and
                    (Test-PfcV2GitBranch $Value.repository.source_branch) -and
                    (Test-PfcV2GitBranch $Value.repository.write_branch_namespace.TrimEnd('/')) -and
                    $Value.repository.write_branch_namespace -ceq ('codex/pfc/' + $Value.authorization_id + '/') -and
                    (@($Value.invalidation_triggers | Sort-Object) -join ',') -ceq (@($triggers | Sort-Object) -join ','))
            }
            'wave-plan' {
                $items = @($Value.milestones)
                if ($items.Count -lt 1 -or $items.Count -gt 5 -or -not (Test-Unique @($items | ForEach-Object { $_.milestone_id })) -or
                    -not (Test-Unique @($items | ForEach-Object { $_.exact_branch })) -or
                    -not (Test-Unique @($items | ForEach-Object { $_.worktree_identity }))) { return $false }
                if ($Value.wave_validation.tier -cne 'T3' -or -not $Value.wave_validation.required -or -not (Test-Validation $Value.wave_validation)) { return $false }
                $seen = @()
                $allIds = @($items | ForEach-Object { $_.milestone_id })
                foreach ($item in $items) {
                    if ($item.contract_version -lt 1 -or -not (Test-PfcV2GitBranch $item.exact_branch) -or
                        -not $item.exact_branch.StartsWith(('codex/pfc/' + $Value.authorization_id + '/'), [StringComparison]::Ordinal)) { return $false }
                    if ($item.risk_level -eq 'MEDIUM' -and $items.Count -gt 3) { return $false }
                    if ($item.risk_level -eq 'HIGH' -and $items.Count -ne 1) { return $false }
                    if (-not (Test-Unique $item.dependencies)) { return $false }
                    foreach ($dependency in $item.dependencies) { if ($allIds -contains $dependency -and $seen -notcontains $dependency) { return $false } }
                    $plan = @($item.validation_plan)
                    if (-not (Test-Unique @($plan | ForEach-Object { $_.tier }))) { return $false }
                    foreach ($record in $plan) { if (-not (Test-Validation $record)) { return $false } }
                    $requiredTiers = @($plan | Where-Object required | ForEach-Object { $_.tier })
                    foreach ($tier in @('T1','T2')) { if ($requiredTiers -notcontains $tier) { return $false } }
                    if ($item.risk_level -eq 'MEDIUM' -and $requiredTiers -notcontains 'ROLLBACK' -and $requiredTiers -notcontains 'UPGRADE_DOWNGRADE') { return $false }
                    if ($item.risk_level -eq 'HIGH') { foreach ($tier in @('T3','T4','FAULT_INJECTION','USER_GATE')) { if ($requiredTiers -notcontains $tier) { return $false } } }
                    $seen += $item.milestone_id
                }
                return $true
            }
            'continuation-checkpoint' {
                if ($Value.lease_epoch -lt 1 -or -not (Test-Date $Value.updated_at)) { return $false }
                if ($Value.previous_accepted_checkpoint_sha -cne 'FIRST_MILESTONE' -and $Value.previous_accepted_checkpoint_sha -cne $Value.current_milestone_base_sha) { return $false }
                $manifest = $Value.recovery_manifest
                $paths = @($manifest.allowed_paths) + @($manifest.files | ForEach-Object { $_.path; $_.recovery_copy }) +
                    @($manifest.git_status | ForEach-Object { $_.path; if ($_.original_path -cne 'NONE') { $_.original_path } })
                foreach ($path in $paths) {
                    if ($path -cne $path.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormC)) { return $false }
                }
                $statusPaths = @($manifest.git_status | ForEach-Object { $_.path })
                $filePaths = @($manifest.files | ForEach-Object { $_.path })
                foreach ($set in @(@{items=$statusPaths},@{items=$filePaths},@{items=@($manifest.allowed_paths)},@{items=@($manifest.files | ForEach-Object { $_.recovery_copy })})) {
                    if (-not (Test-Unique $set.items)) { return $false }
                }
                $expectedFiles = @($statusPaths)
                foreach ($entry in $manifest.git_status) {
                    $renamed = $entry.status -match '^[RC]'
                    if ($renamed -eq ($entry.original_path -ceq 'NONE')) { return $false }
                    if ($renamed) { $expectedFiles += $entry.original_path }
                }
                $expectedFiles = @($expectedFiles | Sort-Object -Unique)
                if ($expectedFiles.Count -ne $filePaths.Count) { return $false }
                foreach ($path in $expectedFiles) {
                    if ($filePaths -cnotcontains $path -or $manifest.allowed_paths -cnotcontains $path) { return $false }
                }
                foreach ($entry in $manifest.files) {
                    if ($entry.size_bytes -lt 0 -or $manifest.allowed_paths -cnotcontains $entry.path) { return $false }
                }
                return $true
            }
            'issue-classification' {
                if (@($Value.evidence).Count -lt 1 -or @($Value.affected_scope).Count -lt 1 -or -not (Test-Unique $Value.affected_scope)) { return $false }
                switch ($Value.classification) {
                    'PRODUCT_DEFECT' { return ($Value.blocking_scope -eq 'MILESTONE' -and $Value.next_action -eq 'REPAIR') }
                    'CONTROL_PLANE_DEFECT' { return ($Value.blocking_scope -eq 'GLOBAL' -and $Value.next_action -eq 'FREEZE_CONTROL') }
                    'SECURITY_OR_DATA_RISK' { return ($Value.blocking_scope -eq 'GLOBAL' -and $Value.next_action -eq 'STOP') }
                    'UNCLASSIFIED' { return ($Value.blocking_scope -ne 'NONE' -and $Value.next_action -eq 'PAUSE_COLLECT_EVIDENCE') }
                    'TEST_INFRASTRUCTURE_DEFECT' {
                        if ($Value.next_action -eq 'CONTINUE') {
                            return ($Value.blocking_scope -eq 'NONE' -and $Value.fallback_reference -ne 'NONE' -and
                                @($Value.evidence | Where-Object { $_ -cmatch '^INDEPENDENT_PRODUCT_EVIDENCE: \S' }).Count -gt 0)
                        }
                        return ($Value.blocking_scope -ne 'NONE' -and $Value.next_action -eq 'BLOCK_VERIFICATION')
                    }
                    { $_ -in @('KNOWN_ENVIRONMENT_LIMITATION','EXTERNAL_DEPENDENCY_FAILURE') } {
                        if ($Value.next_action -eq 'USE_APPROVED_FALLBACK') { return ($Value.fallback_reference -ne 'NONE' -and $Value.blocking_scope -eq 'NONE') }
                        return ($Value.blocking_scope -ne 'NONE' -and $Value.next_action -eq 'BLOCK_VERIFICATION')
                    }
                    'DOCUMENTATION_ONLY' { return ($Value.next_action -eq 'REPAIR' -and $Value.blocking_scope -eq 'MILESTONE') }
                }
                return $false
            }
            'wave-report' {
                $items = @($Value.milestones)
                if ($items.Count -lt 1 -or $items.Count -gt 5 -or -not (Test-Unique @($items | ForEach-Object { $_.milestone_id }))) { return $false }
                if ($Value.t3_result.tier -cne 'T3' -or -not $Value.t3_result.required -or -not (Test-Validation $Value.t3_result)) { return $false }
                $lastAccepted = $Value.base_checkpoint_sha
                foreach ($item in $items) {
                    if ($item.result -eq 'PASS') {
                        if ($item.candidate_sha -cne $item.evidence_sha -or $item.candidate_sha -cne $item.acceptance_sha) { return $false }
                        $lastAccepted = $item.accepted_checkpoint_sha
                    }
                }
                if ($lastAccepted -cne $Value.final_checkpoint_sha) { return $false }
                foreach ($evidence in $Value.t3_result.evidence) { if ($evidence.candidate_sha -cne $Value.final_checkpoint_sha) { return $false } }
                if ($Value.next_action -in @('SELECT_NEXT_WAVE','COMPLETED','STOP_GATE_REACHED')) {
                    if ($Value.t3_result.result -cne 'PASS' -or @($items | Where-Object { $_.result -cne 'PASS' }).Count -gt 0) { return $false }
                    if (($Value.next_action -ceq 'STOP_GATE_REACHED') -ne $Value.stop_gate_result.reached) { return $false }
                }
                return $true
            }
        }
    } catch { return $false }
    return $false
}

function Invoke-PfcV2ContractChecks {
    param([System.IO.DirectoryInfo]$RepositoryRoot)
    $results = New-Object System.Collections.Generic.List[object]
    try {
        $bindings = Get-PfcV2TemplateBindings $RepositoryRoot
        $templateRoot = Join-Path $RepositoryRoot.FullName 'skill/project-flight-control/assets/templates'
        $names = @('continuous-authorization.yaml','wave-plan.yaml','known-limitations.md','blocker-fallback-matrix.md','continuation-checkpoint.md','wave-report.md')
        if ((@($bindings.created.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@($names | Sort-Object) -join ',')) { throw 'exact six V2 template bindings required' }
        foreach ($forbidden in @((Join-Path $templateRoot 'project-control-report.md'),(Join-Path $RepositoryRoot.FullName 'evals/schemas/project-control-report.schema.json'))) {
            if (Test-Path -LiteralPath $forbidden) { throw 'seventh report asset forbidden' }
        }
        foreach ($name in $names) {
            $text = Get-Content -Raw -Encoding UTF8 (Join-Path $templateRoot $name)
            if ($name -in @('known-limitations.md','blocker-fallback-matrix.md')) {
                $actual = @([regex]::Matches($text, '(?m)^([^#:\r\n]+):\s*\S.*$') | ForEach-Object { $_.Groups[1].Value.Trim() })
            } else {
                $fence = ([string][char]96) * 3
                $json = $text
                if (-not $name.EndsWith('.yaml')) {
                    $blocks = [regex]::Matches($text, ('(?ms)^ {0,3}' + $fence + 'json[ \t]*\r?\n(?<json>.*?)^ {0,3}' + $fence + '[ \t]*(?:\r?\n|\z)'))
                    $fences = [regex]::Matches($text, ('(?m)^ {0,3}' + $fence + '[^\r\n]*\r?$'))
                    if ($blocks.Count -ne 1 -or $fences.Count -ne 2) { throw ($name + ' requires exactly one complete JSON fence') }
                    $json = $blocks[0].Groups['json'].Value
                }
                $value = $json | ConvertFrom-Json
                # Windows PowerShell converts ISO JSON strings into DateTime automatically.
                # Restore only the contract's two known string timestamp slots before shape validation.
                if ($name -in @('continuous-authorization.yaml','continuation-checkpoint.md')) {
                    $timestampField = if ($name -eq 'continuous-authorization.yaml') { 'approved_at' } else { 'updated_at' }
                    if ($json -notmatch ('"' + $timestampField + '"\s*:\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"')) { throw ($name + ' invalid timestamp serialization') }
                }
                if ($name -eq 'continuous-authorization.yaml' -and $value.approval.approved_at -is [datetime]) {
                    $value.approval.approved_at = $value.approval.approved_at.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                if ($name -eq 'continuation-checkpoint.md' -and $value.updated_at -is [datetime]) {
                    $value.updated_at = $value.updated_at.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                $actual = @($value.PSObject.Properties.Name)
                $schemaName = [IO.Path]::GetFileNameWithoutExtension($name)
                $schemaPath = Join-Path $RepositoryRoot.FullName ('evals/schemas/' + $schemaName + '.schema.json')
                $schema = Get-Content -Raw -Encoding UTF8 $schemaPath | ConvertFrom-Json
                if ((Get-PfcStrictSchemaPreflight $schemaPath).strict_schema_preflight -cne 'PASS' -or
                    -not (Test-PfcV2SchemaValue -Value $value -Schema $schema) -or
                    -not (Test-PfcV2ControlSemantics $schemaName $value)) { throw ($name + ' invalid control contract') }
                if ((@($schema.properties.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@($bindings.created.$name | Sort-Object) -join ',')) { throw ($name + ' schema fields differ from authority') }
            }
            if ((@($actual | Sort-Object) -join ',') -cne (@($bindings.created.$name | Sort-Object) -join ',')) { throw ($name + ' fields differ from authority') }
        }
        $issuePath = Join-Path $RepositoryRoot.FullName 'evals/schemas/issue-classification.schema.json'
        if ((Get-PfcStrictSchemaPreflight $issuePath).strict_schema_preflight -cne 'PASS') { throw 'issue-classification schema missing or non-strict' }
        $project = Get-Content -Raw -Encoding UTF8 (Join-Path $templateRoot 'project.md')
        if ($project -notmatch '(?m)^# PROJECT_CONTROL_REPORT$') { throw 'project.md must render fixed PROJECT_CONTROL_REPORT' }
        $results.Add((New-PfcResult -ScenarioId 'package.v2.control-contracts' -Status 'PASS' -Message 'six templates, five strict schemas and authority projections verified'))
    } catch {
        $results.Add((New-PfcResult -ScenarioId 'package.v2.control-contracts' -Status 'FAIL' -Message $_.Exception.Message))
    }
    return $results.ToArray()
}


function Test-PfcEvidenceRecoveryRules {
    param([string]$Text = '')
    $missing = New-Object System.Collections.Generic.List[string]
    $record = [regex]::Match($Text, '(?ms)^## Compact Evidence Record\s*(?<body>.*?)(?=^## )').Groups['body'].Value
    $attachments = [regex]::Match($Text, '(?ms)^## Restricted attachments and redaction\s*(?<body>.*?)(?=^## )').Groups['body'].Value
    $recovery = [regex]::Match($Text, '(?ms)^## Recovery sources and lease fencing\s*(?<body>.*)$').Groups['body'].Value
    if ([string]::IsNullOrWhiteSpace($record)) { $missing.Add('compact Evidence Record section') }
    foreach ($term in @('Evidence ID','Candidate SHA','Source','Command / Verification Action','Working Directory','Environment','Exit Code / Result Claimed','Observed Result','Covered Criteria','Created At','Candidate Timing')) {
        if ($record -notmatch ('(?im)^\s*' + [regex]::Escape($term) + '\s*:')) { $missing.Add('record: ' + $term) }
    }
    if ($record -notmatch '(?i)BEFORE_CANDIDATE' -or $record -notmatch '(?i)ON_CANDIDATE') { $missing.Add('record: Candidate Timing values') }
    foreach ($term in @('attachments?','redact|脱敏','Candidate change.*invalid','CONVERGENCE_SNAPSHOT','STATUS.md.*latest','historical.*BUILD_REPORT.*REVIEW_REPORT','Control Run ID','Lease Epoch','STALE_REPORT_REJECTED','same Specialist Order')) {
        if ($Text -notmatch ('(?is)' + $term)) { $missing.Add($term) }
    }
    if ([string]::IsNullOrWhiteSpace($attachments) -or $attachments -notmatch '(?i)200[^\r\n]{0,40}relevant lines' -or $attachments -notmatch '(?i)64\s*KiB') { $missing.Add('attachment bound: 200 relevant lines and 64 KiB') }
    foreach ($term in @('ACTIVE.*no Candidate','Candidate.*without.*valid Review','REPAIR','Review PASS','Specialist ACTIVE','EVIDENCE_NEEDED')) {
        if ($recovery -notmatch ('(?is)' + $term)) { $missing.Add($term) }
    }
    if ($recovery -notmatch '(?im)^\s*\* `ACCEPTED`.*do not recreate old roles') { $missing.Add('ACCEPTED recovery action') }
    [pscustomobject]@{ Passed = ($missing.Count -eq 0); Missing = $missing }
}

function Test-PfcWindowsRuntimeRules {
    param([string]$Text = '')
    $terms = @('Windows PowerShell 5\.1','powershell\.exe','pwsh\.exe','Git for Windows','path normalization','detached HEAD','sandbox','protected.*\.git','UTF-8','BOM','hard-code.*drive')
    $missing = @($terms | Where-Object { $Text -notmatch ('(?is)' + $_) })
    [pscustomobject]@{ Passed = ($missing.Count -eq 0); Missing = $missing }
}

function Get-PfcTextFiles {
    param([System.IO.DirectoryInfo]$Root)
    $historicalReport = Join-Path $Root.FullName 'task-3-report.md'
    $collaborationRoot = (Join-Path $Root.FullName '.superpowers') + [IO.Path]::DirectorySeparatorChar
    Get-ChildItem -LiteralPath $Root.FullName -Recurse -File | Where-Object {
        $_.FullName -notmatch '\\.git\\|\\.pfc-eval-results\\|\\tmp\\' -and
        -not $_.FullName.StartsWith($collaborationRoot,[StringComparison]::OrdinalIgnoreCase) -and
        $_.FullName -ne $historicalReport -and
        $_.Extension -in @('.md','.yaml','.yml','.toml','.ps1','.psm1','.json','.txt')
    }
}

function Test-PfcForbiddenGitScript {
    param([string]$Text)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    # Command ASTs omit comments/literal text and include executable nested expressions.
    foreach ($command in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $commandName = $command.GetCommandName()
        $arguments = @($command.CommandElements | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                $_.Value
            } else {
                $_.Extent.Text
            }
        })
        # Deployment commands and action arguments remain forbidden; output text is inert.
        if ($commandName -match '\bdeploy\b') { return $true }
        if ($commandName -notmatch '^(?:Write-(?:Host|Output|Verbose|Debug|Information|Warning|Error)|Out-String|echo)$' -and
            @($arguments | Where-Object { $_ -match '^(?:[^\s]*[-/:\\])?deploy(?:[-.:][^\s]*)?$' }).Count -gt 0) { return $true }
        if ($commandName -notmatch '(?:^|[/\\])git(?:\.exe)?$') { continue }
        $verbIndex = 0
        while ($verbIndex -lt $arguments.Count -and $arguments[$verbIndex] -eq '--no-pager') { $verbIndex++ }
        if ($verbIndex -ge $arguments.Count) { continue }
        $verb = $arguments[$verbIndex]
        $gitArguments = @($arguments | Select-Object -Skip ($verbIndex + 1))
        if ($verb -eq 'push' -and @($gitArguments | Where-Object { $_ -match '^--force(?:-with-lease)?(?:=|$)' -or $_ -match '^-+[A-Za-z]*f[A-Za-z]*$' }).Count -gt 0) { return $true }
        if ($verb -eq 'clean') {
            $hasForce = @($gitArguments | Where-Object { $_ -eq '--force' -or $_ -match '^-+[A-Za-z]*f[A-Za-z]*$' }).Count -gt 0
            $hasDir = @($gitArguments | Where-Object { $_ -eq '-d' -or $_ -match '^-+[A-Za-z]*d[A-Za-z]*$' }).Count -gt 0
            if ($hasForce -and $hasDir) { return $true }
        }
        if ($verb -eq 'reset' -and @($gitArguments | Where-Object { $_ -eq '--hard' }).Count -gt 0) { return $true }
        if ($verb -eq 'merge' -or $verb -eq 'rebase') { return $true }
    }
    return $false
}

function Get-PfcV2ReferenceTexts {
    param([string]$ReferenceRoot)
    $texts = @{}
    if (-not (Test-Path -LiteralPath $ReferenceRoot -PathType Container)) { return $texts }
    $root = (Get-Item -LiteralPath $ReferenceRoot).FullName.TrimEnd([IO.Path]::DirectorySeparatorChar)
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md')) {
        $name = $file.FullName.Substring($root.Length + 1).Replace('\','/')
        # The root message contract legitimately defines fields; no other reference is exempt.
        if ($name -eq 'message-contracts.md') { continue }
        $texts[$name] = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    }
    return $texts
}

function Test-PfcV2ReferenceRules {
    param([hashtable]$Texts, [ValidateSet('ownership','links','authority')][string]$Rule)
    $owners = @{
        'continuous-execution.md' = @('Activation and Canonical Sources','Stable Authorization and Runtime Lease','Pre-write Identity Gate','Pre-review Identity Gate','Wave Lifecycle','T3 PASS Transition Order')
        'risk-validation-policy.md' = @('Risk Matrix','Validation Tiers')
        'blocker-classification.md' = @('Issue Disposition','Independent Repair Limits')
        'readiness-and-recovery.md' = @('Readiness','Recovery Sequence','No-Candidate Resume','Candidate Rework')
    }
    $routes = @{
        'orchestration-protocol.md' = @('continuous-execution.md','risk-validation-policy.md','blocker-classification.md')
        'modes-and-state-machine.md' = @('continuous-execution.md')
        'roles-and-authority.md' = @('continuous-execution.md')
        'git-and-worktrees.md' = @('continuous-execution.md','readiness-and-recovery.md')
        'evidence-and-recovery.md' = @('readiness-and-recovery.md','blocker-classification.md')
        'windows-runtime.md' = @('continuous-execution.md','readiness-and-recovery.md')
    }
    $predicates = @{
        'continuous-execution.md' = 'explicit START CONTINUOUS_MODE or RESUME CONTINUOUS_MODE'
        'risk-validation-policy.md' = 'explicit Continuous policy is active and risk or validation selection is needed'
        'blocker-classification.md' = 'explicit Continuous policy is active and issue classification is needed'
        'readiness-and-recovery.md' = 'explicit Continuous policy is active and readiness, recovery, or dirty-state handling is needed'
    }
    $missing = New-Object System.Collections.Generic.List[string]
    if ($Rule -eq 'ownership') {
        foreach ($name in @($owners.Keys | Sort-Object)) {
            if (-not $Texts.ContainsKey($name)) { $missing.Add('missing V2 reference: ' + $name); continue }
            foreach ($heading in $owners[$name]) {
                $pattern = '(?m)^## ' + [regex]::Escape($heading) + '\s*$'
                if ([regex]::Matches($Texts[$name], $pattern).Count -ne 1) { $missing.Add($name + ': required section ' + $heading) }
                foreach ($other in @($Texts.Keys | Where-Object { $_ -ne $name })) {
                    if ($Texts[$other] -match $pattern) { $missing.Add($other + ': duplicate owner of ' + $heading) }
                }
            }
        }
    }
    if ($Rule -eq 'links') {
        foreach ($name in @($routes.Keys | Sort-Object)) {
            foreach ($target in $routes[$name]) {
                $pattern = '(?m)^Only when ' + [regex]::Escape($predicates[$target]) + ': \[' + [regex]::Escape($target) + '\]\(' + [regex]::Escape($target) + '\)\.\s*$'
                if (-not $Texts.ContainsKey($name) -or [regex]::Matches($Texts[$name], $pattern).Count -ne 1) { $missing.Add($name + ': conditional link to ' + $target) }
            }
            if ($Texts.ContainsKey($name)) {
                foreach ($line in @($Texts[$name] -split "`r?`n")) {
                    foreach ($target in $owners.Keys) {
                        if ($line -match [regex]::Escape($target) -and $line -notmatch ('^Only when ' + [regex]::Escape($predicates[$target]) + ': ')) { $missing.Add($name + ': unconditional or wrong-predicate V2 link') }
                    }
                }
            }
        }
    }
    if ($Rule -eq 'authority') {
        $paragraphOwners = @{}
        foreach ($name in @($Texts.Keys | Sort-Object)) {
            $body = $Texts[$name]
            if ($owners.ContainsKey($name) -and $body -notmatch '\[message-contracts\.md\]\(message-contracts\.md\)') { $missing.Add($name + ': field authority link') }
            if ($body -match '(?im)^\s*(Required root fields:|Exact property paths|##+\s+(Required fields by message|V2 Template Bindings))|"(?:schema_version|additionalProperties)"\s*:') { $missing.Add($name + ': duplicate field definitions') }
            if ($body -match '(?i)(?:this reference|this document)\s+(?:is|defines)\s+(?:the\s+)?(?:only\s+)?field[- ]definition authority') { $missing.Add($name + ': competing field authority') }
            foreach ($paragraph in @($body -split '(?:\r?\n){2,}')) {
                $proseLines = @($paragraph -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch '^\s{0,3}#{1,6}(?:\s|$)' -and $_ -notmatch '^Only when .+: \[[^\]]+\.md\]\([^)]+\)\.\s*$' })
                if ($proseLines.Count -eq 0) { continue }
                $normalized = (($proseLines -join ' ') -replace '\s+', ' ').Trim()
                if ($normalized.Length -lt 160) { continue }
                if ($paragraphOwners.ContainsKey($normalized) -and $paragraphOwners[$normalized] -ne $name) { $missing.Add($name + ': duplicate protocol prose from ' + $paragraphOwners[$normalized]) }
                else { $paragraphOwners[$normalized] = $name }
            }
        }
    }
    [pscustomobject]@{ Passed = ($missing.Count -eq 0); Missing = @($missing.ToArray()) }
}

function Test-PfcV2ReferenceNegatives {
    # Independent positive fixture: mutations must fail their own rule, not a missing-file rule.
    $valid = @{
        'continuous-execution.md' = "[message-contracts.md](message-contracts.md)`n## Activation and Canonical Sources`n## Stable Authorization and Runtime Lease`n## Pre-write Identity Gate`n## Pre-review Identity Gate`n## Wave Lifecycle`n## T3 PASS Transition Order"
        'risk-validation-policy.md' = "[message-contracts.md](message-contracts.md)`n## Risk Matrix`n## Validation Tiers"
        'blocker-classification.md' = "[message-contracts.md](message-contracts.md)`n## Issue Disposition`n## Independent Repair Limits"
        'readiness-and-recovery.md' = "[message-contracts.md](message-contracts.md)`n## Readiness`n## Recovery Sequence`n## No-Candidate Resume`n## Candidate Rework"
        'orchestration-protocol.md' = "Only when explicit START CONTINUOUS_MODE or RESUME CONTINUOUS_MODE: [continuous-execution.md](continuous-execution.md).`nOnly when explicit Continuous policy is active and risk or validation selection is needed: [risk-validation-policy.md](risk-validation-policy.md).`nOnly when explicit Continuous policy is active and issue classification is needed: [blocker-classification.md](blocker-classification.md)."
        'modes-and-state-machine.md' = 'Only when explicit START CONTINUOUS_MODE or RESUME CONTINUOUS_MODE: [continuous-execution.md](continuous-execution.md).'
        'roles-and-authority.md' = 'Only when explicit START CONTINUOUS_MODE or RESUME CONTINUOUS_MODE: [continuous-execution.md](continuous-execution.md).'
        'git-and-worktrees.md' = "Only when explicit START CONTINUOUS_MODE or RESUME CONTINUOUS_MODE: [continuous-execution.md](continuous-execution.md).`nOnly when explicit Continuous policy is active and readiness, recovery, or dirty-state handling is needed: [readiness-and-recovery.md](readiness-and-recovery.md)."
        'evidence-and-recovery.md' = "Only when explicit Continuous policy is active and readiness, recovery, or dirty-state handling is needed: [readiness-and-recovery.md](readiness-and-recovery.md).`nOnly when explicit Continuous policy is active and issue classification is needed: [blocker-classification.md](blocker-classification.md)."
        'windows-runtime.md' = "Only when explicit START CONTINUOUS_MODE or RESUME CONTINUOUS_MODE: [continuous-execution.md](continuous-execution.md).`nOnly when explicit Continuous policy is active and readiness, recovery, or dirty-state handling is needed: [readiness-and-recovery.md](readiness-and-recovery.md)."
    }
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($rule in @('ownership','links','authority')) {
        if (-not (Test-PfcV2ReferenceRules $valid $rule).Passed) { $failures.Add('positive fixture: ' + $rule) }
    }
    $cases = @(
        @{ Id='missing-reference'; Rule='ownership'; Mutate={param($t) $t.Remove('continuous-execution.md')} },
        @{ Id='missing-section'; Rule='ownership'; Mutate={param($t) $t['risk-validation-policy.md'] = $t['risk-validation-policy.md'].Replace('## Risk Matrix','')} },
        @{ Id='duplicate-owner'; Rule='ownership'; Mutate={param($t) $t['orchestration-protocol.md'] += "`n## T3 PASS Transition Order"} },
        @{ Id='unconditional-link'; Rule='links'; Mutate={param($t) $t['roles-and-authority.md'] = 'Always load [continuous-execution.md](continuous-execution.md).'} },
        @{ Id='wrong-condition'; Rule='links'; Mutate={param($t) $t['orchestration-protocol.md'] = $t['orchestration-protocol.md'].Replace('risk or validation selection','the moon is blue')} },
        @{ Id='extra-unconditional-link'; Rule='links'; Mutate={param($t) $t['windows-runtime.md'] += "`nAlways load [readiness-and-recovery.md](readiness-and-recovery.md)."} },
        @{ Id='duplicate-fields'; Rule='authority'; Mutate={param($t) $t['readiness-and-recovery.md'] += "`nRequired root fields: schema_version, authorization_id"} },
        @{ Id='competing-authority'; Rule='authority'; Mutate={param($t) $t['continuous-execution.md'] += "`nThis reference is the only field-definition authority."} },
        @{ Id='missing-field-link'; Rule='authority'; Mutate={param($t) $t['blocker-classification.md'] = $t['blocker-classification.md'].Replace('[message-contracts.md](message-contracts.md)','')} },
        @{ Id='duplicate-protocol'; Rule='authority'; Mutate={param($t)
            $prose = 'Goalkeeper must verify the active authorization and the registered canonical sources before issuing the single Builder lease; unknown identity or drift stops all business writes until reconciled.'
            $t['continuous-execution.md'] += "`n`n$prose"
            $t['orchestration-protocol.md'] += "`n`n$prose"
        } },
        @{ Id='heading-adjacent-protocol'; Rule='authority'; Mutate={param($t)
            $prose = 'Each milestone retains its own Work Order, Candidate, Review and Acceptance. Start the next item automatically only when the current item is ACCEPTED; Candidate, Evidence and Acceptance SHA agree; both applicable identity gates pass; all required validation is PASS; no BLOCKER or MAJOR remains; Contract, scope, paths and Goal are unchanged; no HIGH or irreversible action awaits decision; no acceptance-necessary Specialist is active or unresolved/unavailable; Convergence is neither STALLED nor REGRESSING; Authorization is ACTIVE; and the next item is inside the frozen Wave. Other Specialist authority remains in [specialist-protocol.md](specialist-protocol.md).'
            $t['continuous-execution.md'] += "`n`n$prose"
            $t['roles-and-authority.md'] += "`n`n## Local continuation rules`n$prose"
        } }
    )
    foreach ($case in $cases) {
        $mutated = $valid.Clone()
        & $case.Mutate $mutated
        if ((Test-PfcV2ReferenceRules $mutated $case.Rule).Passed) { $failures.Add($case.Id + ': mutation accepted') }
    }
    # Exercise the same directory collector used by package checks, including other references.
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $fixture = Join-Path $tempRoot ('pfc-v2-references-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $fixture | Out-Null
        $fixtureTexts = $valid.Clone()
        $prose = 'Each milestone retains its own Work Order, Candidate, Review and Acceptance. Start the next item automatically only when the current item is ACCEPTED; Candidate, Evidence and Acceptance SHA agree; both applicable identity gates pass; all required validation is PASS; no BLOCKER or MAJOR remains; Contract, scope, paths and Goal are unchanged; no HIGH or irreversible action awaits decision; no acceptance-necessary Specialist is active or unresolved/unavailable; Convergence is neither STALLED nor REGRESSING; Authorization is ACTIVE; and the next item is inside the frozen Wave. Other Specialist authority remains in [specialist-protocol.md](specialist-protocol.md).'
        $fixtureTexts['continuous-execution.md'] += "`n`n$prose"
        $fixtureTexts['builder-debugging.md'] = '# Builder debugging'
        $fixtureTexts['specialist-protocol.md'] = '# Specialist protocol'
        $fixtureTexts['message-contracts.md'] = "# Message Contracts`nRequired root fields: schema_version, authorization_id"
        foreach ($name in $fixtureTexts.Keys) { [IO.File]::WriteAllText((Join-Path $fixture $name), $fixtureTexts[$name], (New-Object Text.UTF8Encoding($false))) }
        $collected = Get-PfcV2ReferenceTexts $fixture
        foreach ($name in @('builder-debugging.md','specialist-protocol.md')) {
            if (-not $collected.ContainsKey($name)) { $failures.Add('directory coverage: ' + $name) }
        }
        if ($collected.ContainsKey('message-contracts.md')) { $failures.Add('canonical field authority must be distinguished') }
        foreach ($rule in @('ownership','links','authority')) {
            if (-not (Test-PfcV2ReferenceRules $collected $rule).Passed) { $failures.Add('directory positive fixture: ' + $rule) }
        }
        [IO.File]::AppendAllText((Join-Path $fixture 'builder-debugging.md'), "`n`n## Wave Lifecycle`n`n$prose", (New-Object Text.UTF8Encoding($false)))
        $collected = Get-PfcV2ReferenceTexts $fixture
        foreach ($rule in @('ownership','authority')) {
            if ((Test-PfcV2ReferenceRules $collected $rule).Passed) { $failures.Add('other-reference-duplicate-' + $rule + ': mutation accepted') }
        }
    } finally {
        $resolved = [IO.Path]::GetFullPath($fixture)
        if ((Split-Path -Parent $resolved) -cne $tempRoot -or (Split-Path -Leaf $resolved) -notmatch '^pfc-v2-references-[a-f0-9]{32}$') { throw 'Unsafe reference fixture cleanup path' }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
    [pscustomobject]@{ Passed = ($failures.Count -eq 0); Missing = @($failures.ToArray()) }
}

function Test-PfcContinuousSmokeResults {
    param([object[]]$Results)
    $expected=@('activation-default','worktree-identity','resume-lease','prewrite-prereview','low-wave','pause-recovery','installer-update-rollback','no-remote-mutation'|ForEach-Object {'windows.'+$_})
    if ($Results.Count -ne $expected.Count) {return $false}
    if ((@($Results|ForEach-Object {$_.ScenarioId}|Sort-Object) -join ',') -cne (@($expected|Sort-Object) -join ',')) {return $false}
    foreach ($result in $Results) {if ($null -eq $result -or @('PASS','FAIL','PARTIAL','NOT_RUN') -cnotcontains $result.Status) {return $false}}
    return $true
}

function Test-PfcContinuousSourceContract {
    param([hashtable]$Texts)
    $missing = New-Object 'System.Collections.Generic.List[string]'
    $asts = @{}
    foreach ($key in @('Scenarios','Smoke','Runner','Tests')) {
        if (-not $Texts.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($Texts[$key])) { $missing.Add('missing '+$key); continue }
        $tokens=$null; $errors=$null
        $asts[$key]=[Management.Automation.Language.Parser]::ParseInput($Texts[$key],[ref]$tokens,[ref]$errors)
        if (@($errors).Count -gt 0) { $missing.Add('syntax '+$key) }
    }
    if ($missing.Count -gt 0) { return [pscustomobject]@{Passed=$false;Missing=@($missing)} }
    function Find-Function($Ast, [string]$Name) {
        @($Ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true))
    }
    function Owner-Function($Node) {
        for ($p=$Node.Parent; $null -ne $p; $p=$p.Parent) { if ($p -is [Management.Automation.Language.FunctionDefinitionAst]) { return $p.Name } }
        return ''
    }
    function Has-Command($Ast, [string]$Name) {
        return @($Ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq $Name},$true)).Count -gt 0
    }
    # Narrow freeze of reviewed safety structures, not a general PowerShell
    # safety analyzer. A structural change requires review and a new signature.
    # Token kinds/text retain execution order and bindings but ignore formatting.
    $frozen=@(
        @('Scenarios','Test-CmFixtureBoundary','3213B6357F1C342D391B1DEE9A83BF98367B77C411B7D84B71BC3363FA15A690'),
        @('Scenarios','New-CmScenarioSandbox','89519D4BEF8B0331D0284ECF1DE64B8876CAFE314AADD999796B104A95BA8CA4'),
        @('Scenarios','Remove-CmScenarioSandbox','283CB30B7AC716EFCB1436168DE7DC9642E42E05D56EC90E2B4DE6380A8552B0'),
        @('Scenarios','Invoke-CmFixtureGit','1C3CCDDB33260C8FB861B10FB5EAEB9AB89947FD4A271C2D5CE42D8CA8BDB119'),
        @('Smoke','Invoke-CmSmokeInstallerProof','DE81A9301BFB380B54B1C5DCF8DB5AA0129C7AB4C45017F87C5C5AF6D9685F46'),
        @('Runner','Invoke-ContinuousModeWindowsSmoke','E489169CBC5C416BB35DE3257B96F562E331E696050C652CA9A0458C25B1DC7B')
    )
    foreach ($entry in $frozen) {
        $function=@(Find-Function $asts[$entry[0]] $entry[1])
        if ($function.Count -ne 1) {$missing.Add('frozen structure '+$entry[1]);continue}
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseInput($function[0].Extent.Text,[ref]$tokens,[ref]$errors)
        $shape=@($tokens|Where-Object {$_.Kind.ToString() -notin @('NewLine','LineContinuation','Comment','EndOfInput')}|ForEach-Object {$_.Kind.ToString()+':'+$_.Text}) -join '|'
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$signature=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($shape))).Replace('-','')} finally {$sha.Dispose()}
        if ($signature -cne $entry[2]) {$missing.Add('changed safety structure '+$entry[1])}
    }
    $boxAssignments=@($asts.Smoke.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -match '^\$box(?:\.|\[|$)'},$true))
    if ($boxAssignments.Count -ne 2 -or @($boxAssignments|Where-Object {$_.Extent.Text -cnotin @('$box=$null',"`$box=New-CmScenarioSandbox -Prefix 'pfc-continuous-smoke-'")}).Count -gt 0) {$missing.Add('smoke fixture root binding')}
    $installerCalls=@($asts.Smoke.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Invoke-CmSmokeInstallerProof'},$true))
    if ($installerCalls.Count -ne 1 -or $installerCalls[0].Extent.Text -cne 'Invoke-CmSmokeInstallerProof $box $RepositoryRoot') {$missing.Add('smoke installer fixture binding')}
    $table=@(Find-Function $asts.Scenarios 'Get-PfcContinuousModeScenarios')
    $ids=@()
    if ($table.Count -ne 1) { $missing.Add('one scenario table') }
    else {
        $entries=@($table[0].Body.FindAll({param($n)
            $n -is [Management.Automation.Language.HashtableAst] -and @($n.KeyValuePairs | Where-Object {$_.Item1.Value -ceq 'ScenarioId'}).Count -gt 0
        },$true))
        foreach ($entry in $entries) {
            $idPair=@($entry.KeyValuePairs | Where-Object {$_.Item1.Value -ceq 'ScenarioId'})
            if ($idPair.Count -ne 1) {$missing.Add('duplicate ScenarioId key');continue}
            $idExpression=$idPair[0].Item2.PipelineElements[0].Expression
            if ($idExpression -isnot [Management.Automation.Language.StringConstantExpressionAst]) {$missing.Add('literal scenario ID required');continue}
            $ids+=,$idExpression.Value
            foreach ($kind in @('Positive','Negative')) {
                $pair=@($entry.KeyValuePairs | Where-Object {$_.Item1.Value -ceq $kind})
                if ($pair.Count -ne 1) {$missing.Add($idExpression.Value+' '+$kind);continue}
                $cases=@($pair[0].Item2.FindAll({param($n) $n -is [Management.Automation.Language.HashtableAst] -and @($n.KeyValuePairs|Where-Object {$_.Item1.Value -ceq 'Test'}).Count -gt 0},$true))
                if ($cases.Count -eq 0) {$missing.Add($idExpression.Value+' executable '+$kind)}
                foreach ($case in $cases) {
                    $tests=@($case.KeyValuePairs|Where-Object {$_.Item1.Value -ceq 'Test'})
                    $names=@($case.KeyValuePairs|Where-Object {$_.Item1.Value -ceq 'Name'})
                    if ($tests.Count -ne 1 -or $names.Count -ne 1 -or @($tests[0].Item2.FindAll({param($n) $n -is [Management.Automation.Language.ScriptBlockExpressionAst]},$true)).Count -eq 0 -or -not (Has-Command $tests[0].Item2 'Invoke-CmScenarioOracle')) { $missing.Add($idExpression.Value+' non-oracle '+$kind) }
                }
            }
        }
    }
    $expected=@(32..60|ForEach-Object {'SC-'+$_})
    if (($ids -join ',') -cne ($expected -join ',')) {$missing.Add('exact ordered unique SC-32..SC-60 inventory')}
    foreach ($statement in $asts.Scenarios.EndBlock.Statements) {if ($statement -isnot [Management.Automation.Language.FunctionDefinitionAst]) {$missing.Add('scenario top-level side effect')}}
    if (@($asts.Scenarios.FindAll({param($n) $n -is [Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -ieq 'Phase'},$true)).Count -gt 0) {$missing.Add('scenario Phase-dependent behavior')}
    $suite=@($asts.Runner.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath -ceq 'Suite'})
    $registered=@($suite.Attributes | Where-Object {$_.TypeName.FullName -ceq 'ValidateSet'} | ForEach-Object {$_.PositionalArguments.Value})
    if ($registered -cnotcontains 'ContinuousModeWindowsSmoke') {$missing.Add('smoke suite registration')}
    $dispatch=@(Find-Function $asts.Runner 'Invoke-ContinuousModeWindowsSmoke')
    if ($dispatch.Count -ne 1) {$missing.Add('dedicated smoke dispatch')}
    $smokePaths=@($asts.Runner.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -match 'WindowsSmoke[\\/]scenario\.ps1'},$true))
    if ($smokePaths.Count -ne 1) {$missing.Add('single passive smoke path')}
    foreach ($path in $smokePaths) {
        if ((Owner-Function $path) -cne 'Invoke-ContinuousModeWindowsSmoke') {$missing.Add('smoke path outside dedicated dispatch')}
    }
    foreach ($command in $asts.Runner.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)) {
        if ($command.GetCommandName() -ceq 'Invoke-ContinuousModeWindowsSmoke') {$missing.Add('automatic smoke call')}
        if ($command.InvocationOperator -eq 'Dot' -and $command.Extent.Text -match 'WindowsSmoke') {$missing.Add('smoke dot-source')}
    }
    $aggregate=@(Find-Function $asts.Tests 'Invoke-PfcContinuousScenarioEntry')
    $inventory=@(Find-Function $asts.Tests 'Test-PfcContinuousScenarioInventory')
    $runner=@(Find-Function $asts.Tests 'Invoke-PfcContinuousScenarioTests')
    if ($aggregate.Count -ne 1 -or $inventory.Count -ne 1 -or $runner.Count -ne 1) {$missing.Add('runtime inventory and aggregate validation')}
    else {
        if (-not (Has-Command $aggregate[0].Body 'New-PfcResult') -or @($aggregate[0].Body.FindAll({param($n) $n -is [Management.Automation.Language.TryStatementAst] -and $n.CatchClauses.Count -gt 0},$true)).Count -eq 0) {$missing.Add('subcase failures retained in aggregate')}
        if (-not (Has-Command $runner[0].Body 'Invoke-PfcContinuousScenarioEntry') -or -not (Has-Command $runner[0].Body 'Test-PfcContinuousScenarioInventory')) {$missing.Add('aggregate and declared inventory checked')}
        $statuses=@($inventory[0].Body.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object {$_.Value})
        foreach ($status in @('PASS','FAIL','PARTIAL','NOT_RUN')) {if ($statuses -cnotcontains $status) {$missing.Add('normalized result '+$status)}}
    }
    # Command AST inspection ignores quoted adverse test inputs and comments.
    foreach ($key in @('Scenarios','Smoke')) {
        foreach ($command in $asts[$key].FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)) {
            $name=$command.GetCommandName();$owner=Owner-Function $command
            if ($name -match '^(?i:codex(?:\.exe)?|Invoke-PfcSpecialistSmoke|Invoke-WebRequest|Invoke-RestMethod|Start-Process|Invoke-Expression|iex|cmd(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?|rm|del|erase)$') {$missing.Add('forbidden command '+$name)}
            if ($name -match '^(?i:git(?:\.exe)?)$' -and ($owner -cne 'Invoke-CmFixtureGit' -or $command.Extent.Text -notmatch 'git\s+--no-pager\s+-C\s+\$Box\.Repo\s+@Arguments')) {$missing.Add('unbounded Git command')}
            if ($name -ceq 'Remove-Item' -and ($owner -cne 'Remove-CmScenarioSandbox' -or $command.Extent.Text -cne 'Remove-Item -LiteralPath $root -Recurse -Force')) {$missing.Add('unsafe fixture removal')}
        }
        foreach ($type in $asts[$key].FindAll({param($n) $n -is [Management.Automation.Language.TypeExpressionAst]},$true)) {
            if ($type.TypeName.FullName -match '(?i)(Process|Net\.|ManagementClass|ComObject)') {$missing.Add('external type '+$type.TypeName.FullName)}
        }
        foreach ($variable in $asts[$key].FindAll({param($n) $n -is [Management.Automation.Language.VariableExpressionAst]},$true)) {
            if ($variable.VariablePath.UserPath -match '^(?i:env:|global:|HOME$|CODEX_HOME$)') {$missing.Add('user/global environment access')}
        }
    }
    $boundary=@(Find-Function $asts.Scenarios 'Test-CmFixtureBoundary');$cleanup=@(Find-Function $asts.Scenarios 'Remove-CmScenarioSandbox');$create=@(Find-Function $asts.Scenarios 'New-CmScenarioSandbox');$git=@(Find-Function $asts.Scenarios 'Invoke-CmFixtureGit')
    if ($boundary.Count -ne 1 -or $cleanup.Count -ne 1 -or $create.Count -ne 1 -or $git.Count -ne 1) {$missing.Add('bounded fixture helpers')}
    else {
        foreach ($name in @('Resolve-Path','Test-CmFixtureBoundary','Get-ChildItem','Remove-Item')) {if (-not (Has-Command $cleanup[0].Body $name)) {$missing.Add('cleanup '+$name)}}
        foreach ($name in @('Resolve-Path','Test-CmFixtureBoundary','New-Item')) {if (-not (Has-Command $create[0].Body $name)) {$missing.Add('creation '+$name)}}
        $members=@($boundary[0].Body.FindAll({param($n) $n -is [Management.Automation.Language.MemberExpressionAst]},$true)|ForEach-Object {$_.Member.Value})
        foreach ($member in @('GetFullPath','OrdinalIgnoreCase','ReparsePoint','StartsWith')) {if ($members -cnotcontains $member) {$missing.Add('boundary '+$member)}}
        if (-not (Has-Command $boundary[0].Body 'Split-Path')) {$missing.Add('direct-child boundary')}
        $patterns=@($boundary[0].Body.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object {$_.Value})
        if ($patterns -cnotcontains '[0-9a-f]{32}\z') {$missing.Add('random fixture basename boundary')}
        $gitLiterals=@($git[0].Body.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object {$_.Value})
        foreach ($value in @('--local','--global','--system','config')) {if ($gitLiterals -cnotcontains $value) {$missing.Add('local-only Git '+$value)}}
    }
    $smokeLiterals=@($asts.Smoke.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object {$_.Value})
    foreach ($value in @('pfc-continuous-smoke-','NOT_RUN')) {if ($smokeLiterals -cnotcontains $value) {$missing.Add('smoke '+$value)}}
    foreach ($name in @('New-CmScenarioSandbox','Initialize-CmFixtureGit','Remove-CmScenarioSandbox')) {if (-not (Has-Command $asts.Smoke $name)) {$missing.Add('smoke '+$name)}}
    foreach ($name in @('Get-PfcInstallPlan','Invoke-PfcInstallPlan','Copy-Item','New-CmPhysicalWriteFixture','New-CmReviewFromWrite','Get-PfcContinuousFixtureSetup')) {if (-not (Has-Command $asts.Smoke $name)) {$missing.Add('smoke executable proof '+$name)}}
    foreach ($command in $asts.Smoke.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Invoke-PfcInstallPlan'},$true)) {
        if (@($command.CommandElements | Where-Object {$_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'PassiveDoctor'}).Count -ne 1) {$missing.Add('smoke installer must use local-only passive verification')}
    }
    [pscustomobject]@{Passed=($missing.Count -eq 0);Missing=@($missing)}
}

function Invoke-PfcStaticChecks {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$Phase
    )
    $manifestPath = Join-Path $moduleRoot 'expected\static-package.json'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $results = New-Object System.Collections.Generic.List[object]
    $allFiles = @(Get-PfcTextFiles -Root $RepositoryRoot)
    $packageFiles = @($allFiles | Where-Object { $_.FullName -notmatch '\\docs\\|\\evals\\' })
    $skillPath = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\SKILL.md'
    $policyPath = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\agents\openai.yaml'
    $agentsPath = Join-Path $RepositoryRoot.FullName 'codex-agents'
    function Add-CheckResult([string]$Id, [bool]$Passed, [string]$Message) {
        $status = if ($Passed) { 'PASS' } else { 'FAIL' }
        $results.Add((New-PfcResult -ScenarioId $Id -Status $status -Message $Message))
    }

    foreach ($check in @($manifest.checks | Sort-Object id)) {
        $passed = $false; $message = ''
        switch ($check.kind) {
            'continuous_mode_source' {
                $texts=@{}
                foreach ($pair in @(@('Scenarios','evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1'),@('Smoke','evals/scenarios/continuous-mode/WindowsSmoke/scenario.ps1'),@('Runner','evals/run-evals.ps1'),@('Tests','evals/tests/ContinuousMode.Tests.ps1'))) {
                    $path=Join-Path $RepositoryRoot.FullName $pair[1]
                    $texts[$pair[0]]=if (Test-Path -LiteralPath $path -PathType Leaf) {Get-Content -Raw -LiteralPath $path} else {''}
                }
                try {$contract=Test-PfcContinuousSourceContract -Texts $texts;$passed=$contract.Passed;$message=if ($passed) {'passive dispatch, exact scenario inventory, aggregates and fixture boundaries verified'} else {$contract.Missing -join '; '}}
                catch {$passed=$false;$message='continuous source contract failed: '+$_.Exception.Message}
            }
            'required_path' {
                $passed = Test-Path -LiteralPath (Join-Path $RepositoryRoot.FullName $check.path) -PathType Leaf
                $message = if ($passed) { 'present' } else { 'missing: ' + $check.path }
            }
            'required_directory' {
                $passed = Test-Path -LiteralPath (Join-Path $RepositoryRoot.FullName $check.path) -PathType Container
                $message = if ($passed) { 'present' } else { 'missing: ' + $check.path }
            }
            'release_only_path' {
                $passed = $true
                if ($Phase -ceq 'RED') { $message = 'release-only; omitted during development' }
                elseif (Test-Path -LiteralPath (Join-Path $RepositoryRoot.FullName $check.path)) { $message = 'present' }
                else { $message = 'release-only; omitted during development' }
            }
            'skill_frontmatter' {
                if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
                    $lines = @(Get-Content -LiteralPath $skillPath)
                    $close = -1
                    if ($lines.Count -gt 1 -and $lines[0].Trim() -ceq '---') {
                        for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ceq '---') { $close = $i; break } }
                    }
                    $frontLines = if ($close -gt 1) { @($lines[1..($close - 1)]) } else { @() }
                    $front = $frontLines -join "`n"
                    $keys = @{}
                    $structureOk = $close -gt 1
                    foreach ($line in $frontLines) {
                        if ([string]::IsNullOrWhiteSpace($line)) { continue }
                        $match = [regex]::Match($line, '^([A-Za-z][A-Za-z0-9_-]*):\s*(\S.*)$')
                        if (-not $match.Success) { $structureOk = $false; continue }
                        $key = $match.Groups[1].Value
                        if (-not $keys.ContainsKey($key)) { $keys[$key] = 0 }
                        $keys[$key]++
                    }
                    $passed = $structureOk -and $keys.ContainsKey('name') -and $keys.ContainsKey('description') -and $keys['name'] -eq 1 -and $keys['description'] -eq 1
                    $message = if ($passed) { 'name and description found' } else { 'missing required frontmatter keys' }
                } else { $message = 'SKILL.md missing' }
            }
            'skill_entry_metadata' {
                $entry = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\SKILL.md'
                $policy = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\agents\openai.yaml'
                $entryText = if (Test-Path -LiteralPath $entry -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $entry } else { '' }
                $policyText = if (Test-Path -LiteralPath $policy -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $policy } else { '' }
                $passed = ($entryText -match '(?ms)^---\s*\nname:\s*project-flight-control\s*\ndescription:\s*[^\r\n]+\s*\n---') -and ($policyText -match '(?im)allow_implicit_invocation:\s*false')
                $message = if ($passed) { 'skill entry metadata present' } else { 'skill entry metadata missing or implicit policy enabled' }
            }
            'agents_explicit_only' {
                if (Test-Path -LiteralPath $policyPath -PathType Leaf) {
                    $text = Get-Content -Raw -LiteralPath $policyPath
                    $policyKeys = [regex]::Matches($text, '(?im)^\s*allow_implicit_invocation\s*:')
                    $passed = ($policyKeys.Count -eq 1) -and ($text -match '(?im)^\s*allow_implicit_invocation\s*:\s*false\s*(?:#[^\r\n]*)?$') -and ($text -notmatch '(?im)FAST|STANDARD|DEEP|routing')
                    $message = if ($passed) { 'explicit-only policy present' } else { 'explicit-only policy missing or routing found' }
                } else { $message = 'skill/project-flight-control/agents/openai.yaml missing' }
            }
            'formal_agent_tomls' {
                $tomls = @(if (Test-Path $agentsPath) { Get-ChildItem -LiteralPath $agentsPath -Filter '*.toml' -File })
                $passed = $tomls.Count -eq 2
                $message = 'TOML count=' + $tomls.Count
            }
            'custom_agent_fields' {
                $tomls = @(if (Test-Path $agentsPath) { Get-ChildItem -LiteralPath $agentsPath -Filter '*.toml' -File })
                $names = @($tomls | Select-Object -ExpandProperty Name | Sort-Object)
                $passed = ($tomls.Count -eq 2) -and ((@($names) -join '|') -ceq 'project-flight-builder.toml|project-flight-verifier.toml')
                foreach ($toml in $tomls) {
                    $t = Get-Content -Raw -LiteralPath $toml.FullName
                    $passed = $passed -and ($t -match '(?im)^name\s*=') -and ($t -match '(?im)^description\s*=') -and ($t -match '(?im)^developer_instructions\s*=') -and ($t -notmatch '(?im)^model\s*=') -and ($t -notmatch '(?im)^reasoning_effort\s*=')
                }
                $message = if ($passed) { 'required fields found with inherited model settings' } else { 'required fields missing, profile names invalid, or model settings are hard-coded' }
            }
            'builder_profile' {
                $profilePath = Join-Path $RepositoryRoot.FullName 'codex-agents\project-flight-builder.toml'
                $debugPath = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references\builder-debugging.md'
                $missing = New-Object System.Collections.Generic.List[string]
                if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
                    $missing.Add('project-flight-builder.toml')
                } else {
                    $profile = Get-Content -Raw -Encoding UTF8 -LiteralPath $profilePath
                    $topLevelFields = @([regex]::Matches($profile, '(?im)^([A-Za-z_][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value })
                    if ((@($topLevelFields | Sort-Object -Unique) -join '|') -cne 'description|developer_instructions|name|sandbox_mode') { $missing.Add('only required Builder TOML fields plus sandbox_mode') }
                    if ($profile -notmatch '(?im)^name\s*=\s*["'']project_flight_builder["'']\s*$') { $missing.Add('project_flight_builder name') }
                    if ($profile -notmatch '(?im)^description\s*=\s*["'']\S') { $missing.Add('description') }
                    if ($profile -notmatch '(?im)^developer_instructions\s*=') { $missing.Add('developer_instructions') }
                    if ($profile -notmatch '(?im)^sandbox_mode\s*=\s*["'']workspace-write["'']\s*$') { $missing.Add('workspace-write sandbox') }
                    if ($profile -match '(?im)^\s*(?:model|reasoning_effort)\s*=') { $missing.Add('inherited model and reasoning settings') }
                    $requiredTerms = @(
                        'Start From Evidence',
                        'Targeted Context',
                        'Level 1',
                        'Level 2',
                        'Level 3',
                        'Reuse Before Create',
                        'Minimal Diff',
                        'Incremental Verification',
                        'Delta Rework',
                        'PASS / FAIL / PARTIAL / NOT_RUN',
                        'git reset',
                        'EFFICIENCY_EXCEPTION',
                        'BUILD_REPORT'
                    )
                    foreach ($term in $requiredTerms) { if ($profile -notlike ('*' + $term + '*')) { $missing.Add($term) } }
                    if ($profile -notmatch '(?is)Level 1.*Level 2 only.*Level 3 only') { $missing.Add('evidence-dependent Level 1 to 3 expansion') }
                    if ($profile -notmatch '(?i)EFFICIENCY_EXCEPTION.{0,180}only') { $missing.Add('conditional EFFICIENCY_EXCEPTION') }
                    if ($profile -notmatch '(?i)must not write.*control files') { $missing.Add('control-file write prohibition') }
                    if ($profile -notmatch '(?i)must not.*declare.*acceptance') { $missing.Add('acceptance declaration prohibition') }
                    if ($profile -notmatch '(?i)must not.*create.*Specialist') { $missing.Add('Specialist creation prohibition') }
                    if ($profile -notmatch '(?i)must not.*direct.*Verifier') { $missing.Add('direct Verifier command prohibition') }
                    if ($profile -notmatch '(?i)must not.*unrelated dirty') { $missing.Add('unrelated dirty-file prohibition') }
                    if ($profile -notmatch '(?i)builder-debugging\.md.*only.*failure|only.*failure.*builder-debugging\.md') { $missing.Add('failure-only debugging reference') }
                    $continuousTerms = @('Authorization ID / Status / Scope','Goal ID / Version','Active Plan Milestone ID','Milestone Contract ID / Version','Work Order ID / Milestone ID','Wave ID','Repository Identity','Milestone Worktree Identity','Exact Branch','Authorized Base Checkpoint SHA','Previous Accepted Checkpoint SHA','Current Milestone Base SHA','Expected Builder Start SHA','Actual Worktree HEAD','Writable Path Hash','Forbidden Path Hash','Control Run ID','Lease Epoch','Risk Level','Validation Plan','STOP_BEFORE_WRITE','Candidate SHA only if already present','must not start the next milestone','Goalkeeper alone writes canonical control files and decides acceptance')
                    foreach ($term in $continuousTerms) { if ($profile -notlike ('*' + $term + '*')) { $missing.Add('continuous: ' + $term) } }
                    if ($profile -notmatch '(?is)In Continuous Mode return Builder Echo before any business-file write:.+?Only after Goalkeeper confirms PRE_WRITE_IDENTITY_GATE_PASS and issues the matching Lease may you write\.') { $missing.Add('Echo -> Goalkeeper identity gate -> matching Lease -> business write') }
                    if ($profile -notmatch '(?i)at most two code-changing attempts per failure path, then return Lease; never reset counters on RESUME') { $missing.Add('independent two-attempt repair limit without reset') }
                    # A soft line wrap does not end a subject. Subjectless grants start at the
                    # instruction body's beginning or a sentence boundary, never any physical line.
                    $instructions = [regex]::Match($profile, '(?s)developer_instructions\s*=\s*"""(.*?)"""').Groups[1].Value
                    $grant = '(?i)(?:\b(?:Builder|You)\s+|(?:^|[.!?;]\s+)\s*)(?:may|can|(?:is|are) allowed to)\s+'
                    $forbidden = @(
                        '(?:write|modify|change)\s+(?:canonical\s+)?control files',
                        'start\s+(?:the\s+)?next milestone',
                        '(?:issue|grant|self-issue)\s+(?:(?:its|your) own\s+)?Lease',
                        'reset\s+(?:repair\s+)?counters'
                    )
                    foreach ($pattern in $forbidden) { if ($instructions -match ($grant + $pattern)) { $missing.Add('forbidden authority: ' + $pattern) } }
                    if ((Measure-PfcAgentPromptBudget -Path ([IO.FileInfo]$profilePath)).status -ne 'PASS') { $missing.Add('frozen V1 Agent byte/token budget +15%') }
                }
                if (-not (Test-Path -LiteralPath $debugPath -PathType Leaf)) {
                    $missing.Add('builder-debugging.md')
                } else {
                    $debug = Get-Content -Raw -Encoding UTF8 -LiteralPath $debugPath
                    $debugTerms = @('read error fully','reproduce','inspect current Revision/diff','form one hypothesis','smallest test','one root-cause fix','rerun affected verification','two code-changing attempts','status FAIL or PARTIAL','DEBUGGING_SUMMARY','stacked speculative patches','delete tests','weaken assertions','relabeling the same failure')
                    foreach ($term in $debugTerms) { if ($debug -notlike ('*' + $term + '*')) { $missing.Add('debugging: ' + $term) } }
                }
                $passed = $missing.Count -eq 0
                $message = if ($passed) { 'Builder profile and failure-only debugging protocol satisfy the product contract' } else { 'missing or invalid: ' + (($missing | Select-Object -First 12) -join ', ') }
            }
            'verifier_profile' {
                $profilePath = Join-Path $RepositoryRoot.FullName 'codex-agents\project-flight-verifier.toml'
                $missing = New-Object System.Collections.Generic.List[string]
                if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
                    $missing.Add('project-flight-verifier.toml')
                } else {
                    $profile = Get-Content -Raw -Encoding UTF8 -LiteralPath $profilePath
                    $topLevelFields = @([regex]::Matches($profile, '(?im)^([A-Za-z_][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value })
                    if ((@($topLevelFields | Sort-Object -Unique) -join '|') -cne 'description|developer_instructions|name|sandbox_mode') { $missing.Add('only required Verifier TOML fields plus sandbox_mode') }
                    if ($profile -notmatch '(?im)^name\s*=\s*["'']project_flight_verifier["'']\s*$') { $missing.Add('project_flight_verifier name') }
                    if ($profile -notmatch '(?im)^description\s*=\s*["'']\S') { $missing.Add('description') }
                    if ($profile -notmatch '(?im)^developer_instructions\s*=') { $missing.Add('developer_instructions') }
                    if ($profile -notmatch '(?im)^sandbox_mode\s*=\s*["'']workspace-write["'']\s*$') { $missing.Add('workspace-write sandbox') }
                    if ($profile -match '(?im)^\s*(?:model|reasoning_effort)\s*=') { $missing.Add('inherited model and reasoning settings') }
                    $requiredTerms = @(
                        'Alignment Audit',
                        'Evidence Integrity',
                        'Technical Verification',
                        'Candidate SHA',
                        'Builder evidence may be reused',
                        'Builder conclusions may not',
                        'minimum independent rerun',
                        'risk-triggered verification expansion',
                        'tracked-file immutability',
                        'before-and-after git status --porcelain',
                        'BLOCKER',
                        'MAJOR',
                        'MINOR',
                        'REVIEW_REPORT'
                    )
                    foreach ($term in $requiredTerms) { if ($profile -notlike ('*' + $term + '*')) { $missing.Add($term) } }
                    if ($profile -notmatch '(?is)Alignment Audit.*Evidence Integrity.*Technical Verification') { $missing.Add('ordered alignment/evidence/technical phases') }
                    if ($profile -notmatch '(?i)must not.*(?:modify|change).*Candidate') { $missing.Add('Candidate mutation prohibition') }
                    if ($profile -notmatch '(?i)must not.*commit') { $missing.Add('commit prohibition') }
                    if ($profile -notmatch '(?i)must not.*contract') { $missing.Add('contract-change prohibition') }
                    if ($profile -notmatch '(?i)must not.*direct(?:ly)?.*command.*Builder') { $missing.Add('direct Builder command prohibition') }
                    if ($profile -notmatch '(?i)must not.*create.*Specialist') { $missing.Add('Specialist creation prohibition') }
                    if ($profile -notmatch '(?i)control files') { $missing.Add('control-file boundary') }
                    $continuousTerms = @('Verify Order','Authorization ID / Status','Goal / Milestone / Work Order / Verify Order','Repository Identity','Base SHA','Changed Files','Path Policy','Risk Level / Validation Tier','Builder Evidence SHA','Wave ID','Acceptance Record Target','Evidence Freshness','Wave impact','Validation Plan','CONTROL_PLANE_DEFECT','STALE_REPORT_REJECTED','VERSION_INTEGRITY_FAIL','Goalkeeper alone writes canonical control files and decides acceptance')
                    foreach ($term in $continuousTerms) { if ($profile -notlike ('*' + $term + '*')) { $missing.Add('continuous: ' + $term) } }
                    if ($profile -notmatch '(?is)Alignment Audit:.+Evidence Integrity:.+Technical Verification follows Alignment Audit and Evidence Integrity; in Continuous Mode only after PRE_REVIEW_IDENTITY_GATE_PASS') { $missing.Add('identity gate before technical review') }
                    if ($profile -notmatch '(?i)bound to VERIFY_ORDER \(Verify Order\) and Candidate SHA' -or $profile -notmatch '(?i)only when complete, redacted, fresh and bound to current Candidate SHA and order') { $missing.Add('order/Candidate/freshness evidence binding') }
                    if ((Measure-PfcAgentPromptBudget -Path ([IO.FileInfo]$profilePath)).status -ne 'PASS') { $missing.Add('frozen V1 Agent byte/token budget +15%') }
                    $instructions = [regex]::Match($profile, '(?s)developer_instructions\s*=\s*"""(.*?)"""').Groups[1].Value
                    $grant = '(?i)(?:\b(?:Verifier|You)\s+|(?:^|[.!?;]\s+)\s*)(?:may|can|(?:is|are) allowed to)\s+'
                    $forbidden = @(
                        '(?:modify|change)\s+(?:the\s+)?Candidate',
                        'commit',
                        '(?:change|modify)\s+(?:control files|contracts?)',
                        'directly\s+command\s+Builder',
                        '(?:write|modify|change)\s+(?:canonical\s+)?control files',
                        'accept\s+(?:stale|other-SHA)\s+evidence',
                        'declare\s+(?:the\s+)?(?:milestone|Goal)\s+accepted'
                    )
                    foreach ($pattern in $forbidden) { if ($instructions -match ($grant + $pattern)) { $missing.Add('forbidden authority: ' + $pattern) } }
                }
                $passed = $missing.Count -eq 0
                $message = if ($passed) { 'Verifier profile satisfies independent review and immutability contract' } else { 'missing or invalid: ' + (($missing | Select-Object -First 16) -join ', ') }
            }
            'verifier_report_schema' {
                $schemaPath = Join-Path $RepositoryRoot.FullName 'evals\schemas\verifier-report.schema.json'
                $missing = New-Object System.Collections.Generic.List[string]
                if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
                    $missing.Add('verifier-report.schema.json')
                } else {
                    try {
                        $schema = Get-Content -Raw -Encoding UTF8 -LiteralPath $schemaPath | ConvertFrom-Json
                        if ($schema.type -cne 'object') { $missing.Add('object type') }
                        if ([string]$schema.additionalProperties -cne 'False') { $missing.Add('additionalProperties false') }
                        $required = @($schema.required)
                        foreach ($field in @('control_run_id','lease_epoch','goal_id','goal_version','milestone_id','milestone_contract_version','revision','sender_role','recipient_role','created_at','candidate_sha','alignment_result','evidence_integrity_result','technical_result','environment','builder_evidence_reused','independent_commands_run','observed_results','version_integrity','findings','residual_risks','specialist_dependency_status','verdict')) {
                            if ($required -notcontains $field) { $missing.Add('required ' + $field) }
                        }
                        if ($schema.properties.candidate_sha.pattern -cne '^[0-9a-f]{40}$') { $missing.Add('candidate SHA pattern') }
                        $findingFields = @('finding_id','finding_type','severity','candidate_sha','related_acceptance_criterion','related_constraint','objective_risk','expected_result','observed_result','reproduction_command','evidence','impact','blocking_reason','suggested_direction','blocking')
                        $findingItem = $schema.properties.findings.items
                        $branches = @($findingItem.anyOf)
                        if ($branches.Count -ne 2) { $missing.Add('finding severity branches') }
                        foreach ($branch in $branches) {
                            foreach ($field in $findingFields) { if (@($branch.required) -notcontains $field) { $missing.Add('finding required ' + $field) } }
                            if ([string]$branch.additionalProperties -cne 'False') { $missing.Add('finding additionalProperties false') }
                            if ($branch.properties.candidate_sha.pattern -cne '^[0-9a-f]{40}$') { $missing.Add('finding candidate SHA pattern') }
                        }
                        $blocker = @($branches | Where-Object { ((@($_.properties.severity.enum) | Sort-Object) -join '|') -ceq 'BLOCKER|MAJOR' })
                        $minor = @($branches | Where-Object { ((@($_.properties.severity.enum) | Sort-Object) -join '|') -ceq 'MINOR' })
                        if ($blocker.Count -ne 1 -or ((@($blocker[0].properties.blocking.enum) -join '|') -cne 'True')) { $missing.Add('BLOCKER/MAJOR blocking=true') }
                        if ($minor.Count -ne 1 -or ((@($minor[0].properties.blocking.enum) -join '|') -cne 'False')) { $missing.Add('MINOR blocking=false') }
                        if ((@($branches | ForEach-Object { @($_.properties.severity.enum) } | Where-Object { $_ -eq 'INFO' }).Count -gt 0)) { $missing.Add('INFO severity forbidden') }
                        $residualFields = @('risk','why_non_blocking','accepted_by','affected_scope','future_action')
                        $residualItem = $schema.properties.residual_risks.items
                        foreach ($field in $residualFields) { if (@($residualItem.required) -notcontains $field) { $missing.Add('residual required ' + $field) } }
                        if ([string]$residualItem.additionalProperties -cne 'False') { $missing.Add('residual additionalProperties false') }
                    } catch { $missing.Add('valid JSON schema') }
                }
                $passed = $missing.Count -eq 0
                $message = if ($passed) { 'strict REVIEW_REPORT schema present' } else { 'missing or invalid: ' + (($missing | Select-Object -First 16) -join ', ') }
            }
            'no_specialist_toml' {
                $specialists = @($allFiles | Where-Object { $_.Extension -eq '.toml' -and $_.Name -match '(?i)specialist' })
                $passed = $specialists.Count -eq 0
                $message = 'specialist TOML count=' + $specialists.Count
            }
            'builder_efficiency_terms' {
                $builder = Join-Path $agentsPath 'project-flight-builder.toml'
                $text = if (Test-Path -LiteralPath $builder -PathType Leaf) { Get-Content -Raw -LiteralPath $builder } else { '' }
                $passed = ($text -match '(?i)efficiency') -and ($text -match '(?i)targeted')
                if ($passed) { $message = 'efficiency protocol terms found' } else { $message = 'builder efficiency terms missing' }
            }
            'verifier_evidence_terms' {
                $verifier = Join-Path $agentsPath 'project-flight-verifier.toml'
                $text = if (Test-Path -LiteralPath $verifier -PathType Leaf) { Get-Content -Raw -LiteralPath $verifier } else { '' }
                $passed = ($text -match '(?i)evidence') -and ($text -match '(?i)integrity|frozen')
                if ($passed) { $message = 'evidence-integrity terms found' } else { $message = 'verifier evidence terms missing' }
            }
            'reference_template_links' {
                $bad = New-Object System.Collections.Generic.List[string]
                foreach ($file in @($packageFiles | Where-Object { $_.Extension -eq '.md' })) {
                    $body = Get-Content -Raw -LiteralPath $file.FullName
                    foreach ($m in [regex]::Matches($body, '\[[^\]]+\]\(([^)#]+)\)')) {
                        $target = $m.Groups[1].Value
                        if ($target -notmatch '^(?i:https?://|mailto:)') {
                            $resolved = Join-Path $file.DirectoryName $target
                            if (-not (Test-Path -LiteralPath $resolved)) { $bad.Add($target) }
                        }
                    }
                }
                $passed = $bad.Count -eq 0
                $message = if ($passed) { 'links resolve' } else { 'missing links: ' + (($bad | Sort-Object -Unique) -join ', ') }
            }
            'powershell_parseable' {
                $bad = New-Object System.Collections.Generic.List[string]
                foreach ($file in @($allFiles | Where-Object { $_.Extension -in @('.ps1','.psm1') })) {
                    $tokens = $null; $errors = $null
                    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
                    if (@($errors).Count -gt 0) { $bad.Add($file.Name) }
                }
                $passed = $bad.Count -eq 0
                $message = if ($passed) { 'PowerShell parser reports no errors' } else { 'parse errors: ' + ($bad -join ', ') }
            }
            'forbidden_git_commands' {
                $bad = @($packageFiles | Where-Object { $_.Extension -in @('.ps1','.psm1') } | Where-Object {
                    Test-PfcForbiddenGitScript -Text (Get-Content -Raw -LiteralPath $_.FullName)
                })
                $passed = $bad.Count -eq 0
                $message = if ($passed) { 'no destructive git/deploy commands' } else { 'forbidden command in: ' + (($bad | Select-Object -ExpandProperty Name) -join ', ') }
            }
            'hard_coded_drive_letters' {
                $bad = @($packageFiles | Where-Object { (Get-Content -Raw -LiteralPath $_.FullName) -match '(?<![A-Za-z])[A-Za-z]:\\' })
                $passed = $bad.Count -eq 0
                $message = if ($passed) { 'no hard-coded drive letters' } else { 'drive letter in: ' + (($bad | Select-Object -ExpandProperty Name) -join ', ') }
            }
            'version_consistency' {
                $versionPath = Join-Path $RepositoryRoot.FullName 'VERSION'
                $version = if (Test-Path $versionPath) { (Get-Content -Raw $versionPath).Trim() } else { '' }
                $passed = $version -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'
                $declared = New-Object System.Collections.Generic.List[string]
                foreach ($file in @($packageFiles | Where-Object { $_.Extension -in @('.md','.yaml','.yml','.toml','.json') })) {
                    $body = Get-Content -Raw -LiteralPath $file.FullName
                    foreach ($m in [regex]::Matches($body, '(?im)(?:^|[,{\[-])\s*["'']?version["'']?\s*[:=]\s*["'']?([0-9A-Za-z._-]+)')) { $declared.Add($m.Groups[1].Value) }
                }
                if ($passed) { foreach ($v in $declared) { if ($v -cne $version) { $passed = $false } } }
                $message = if ($passed) { 'VERSION=' + $version } else { 'invalid or missing VERSION' }
            }
            'install_state_schema' {
                $schema = @($allFiles | Where-Object { $_.Name -match '(?i)install.*state.*schema|schema.*install.*state' })
                $passed = $schema.Count -gt 0
                $message = if ($passed) { 'install-state schema present' } else { 'install-state schema missing' }
            }
            'forbidden_features' {
                $bad = @($packageFiles | Where-Object { $_.Extension -ne '.md' -and (Get-Content -Raw -LiteralPath $_.FullName) -match '(?i)Company OS|Repo Map|long[- ]term Memory|runtime telemetry' })
                $passed = $bad.Count -eq 0
                $message = if ($passed) { 'forbidden feature terms absent' } else { 'forbidden terms in: ' + (($bad | Select-Object -ExpandProperty Name) -join ', ') }
            }
            'doctor_passive' {
                $doctor = @($allFiles | Where-Object { $_.Name -match '(?i)doctor' })
                $text = ($doctor | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
                $passed = ($doctor.Count -eq 0) -or (($text -notmatch '(?i)codex\s+exec|create\s+(?:a\s+)?agents?|New-PfcAgent') -and ($text -match '(?i)passive|read-only|diagnos'))
                $message = if ($passed) { 'Doctor is absent or passive' } else { 'Doctor invokes Codex/agents or lacks passive marker' }
            }
            'prompt_budget_report' {
                if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
                    $report = Measure-PfcPromptBudget -Path ([System.IO.FileInfo]$skillPath) -Budget 1500
                    $passed = $report.status -eq 'PASS'
                    $message = 'CONSERVATIVE_ESTIMATE tokens=' + $report.conservative_estimated_tokens + '; budget=' + $report.budget
                } else { $message = 'SKILL.md missing for prompt budget' }
            }
            'message_contracts' {
                $contract = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references\message-contracts.md'
                $templateRoot = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\assets\templates'
                $required = @('project','roadmap','status','decisions','work-order','build-report','verify-order','review-report','rework-order','evidence-record','decision-packet','human-verification-request','human-verification-response','acceptance-report','final-review-report')
                $missing = New-Object System.Collections.Generic.List[string]
                if (-not (Test-Path -LiteralPath $contract -PathType Leaf)) { $missing.Add('message-contracts.md') }
                foreach ($name in $required) {
                    $path = Join-Path $templateRoot ($name + '.md')
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add($name + '.md'); continue }
                    $body = Get-Content -Raw -LiteralPath $path
                    foreach ($field in @('Control Run ID','Lease Epoch','Goal Version','Milestone Contract Version','Revision','Sender Role','Recipient Role','Created At')) {
                        if ($body -notmatch [regex]::Escape($field)) { $missing.Add($name + ': ' + $field) }
                    }
                    if ($body -notmatch '(?m)^(?:Base SHA|Candidate SHA|Evidence SHA)\s*:') { $missing.Add($name + ': SHA') }
                    if ($body -match '(?i)defines?\s+(?:the\s+)?state\s+transition|authoritative\s+field\s+definition') { $missing.Add($name + ': duplicate authority prose') }
                }
                $passed = $missing.Count -eq 0
                $message = if ($passed) { 'all message contracts and templates present' } else { 'missing: ' + (($missing | Select-Object -First 12) -join ', ') }
            }
            'message_contract_authority' {
                $contract = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references\message-contracts.md'
                if (Test-Path -LiteralPath $contract -PathType Leaf) {
                    $body = Get-Content -Raw -LiteralPath $contract
                    $passed = ($body -match '(?i)only field-definition authority') -and ($body -match '(?i)WORK_ORDER') -and ($body -match '(?i)PROJECT_CONTROL_REPORT') -and ($body -notmatch '(?i)EFFICIENCY_EXCEPTION\s*\n\s*##')
                    $message = if ($passed) { 'single field authority and formal message families declared' } else { 'authority or message family declaration missing' }
                } else { $message = 'message-contracts.md missing' }
            }
            'v2_control_contracts' {
                $v2Results = @(Invoke-PfcV2ContractChecks -RepositoryRoot $RepositoryRoot)
                $passed = @($v2Results | Where-Object Status -ne 'PASS').Count -eq 0
                $message = ($v2Results | ForEach-Object { $_.Message }) -join '; '
            }
            { $_ -in @('v2_reference_ownership','v2_reference_links','v2_reference_authority','v2_reference_negatives') } {
                if ($check.kind -eq 'v2_reference_negatives') { $ruleCheck = Test-PfcV2ReferenceNegatives }
                else {
                    $referenceRoot = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references'
                    $texts = Get-PfcV2ReferenceTexts $referenceRoot
                    $ruleCheck = Test-PfcV2ReferenceRules -Texts $texts -Rule $check.kind.Replace('v2_reference_','')
                }
                $passed = $ruleCheck.Passed
                $message = if ($passed) { 'V2 reference boundary verified' } else { $ruleCheck.Missing -join '; ' }
            }
            'governance_references' {
                $referenceRoot = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references'
                $required = @('roles-and-authority.md','modes-and-state-machine.md','orchestration-protocol.md','git-and-worktrees.md')
                $missing = New-Object System.Collections.Generic.List[string]
                foreach ($name in $required) {
                    $path = Join-Path $referenceRoot $name
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add($name); continue }
                    $body = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
                    if ($body -notmatch '(?i)one source of truth' -and $name -eq 'roles-and-authority.md') { $missing.Add($name + ': single authority') }
                }
                $roles = if (Test-Path (Join-Path $referenceRoot 'roles-and-authority.md')) { Get-Content -Raw -Encoding UTF8 (Join-Path $referenceRoot 'roles-and-authority.md') } else { '' }
                $modes = if (Test-Path (Join-Path $referenceRoot 'modes-and-state-machine.md')) { Get-Content -Raw -Encoding UTF8 (Join-Path $referenceRoot 'modes-and-state-machine.md') } else { '' }
                $orchestration = if (Test-Path (Join-Path $referenceRoot 'orchestration-protocol.md')) { Get-Content -Raw -Encoding UTF8 (Join-Path $referenceRoot 'orchestration-protocol.md') } else { '' }
                $git = if (Test-Path (Join-Path $referenceRoot 'git-and-worktrees.md')) { Get-Content -Raw -Encoding UTF8 (Join-Path $referenceRoot 'git-and-worktrees.md') } else { '' }
                $requiredTerms = @(
                    @{Text=$roles; Pattern='Builder.*(?:must not|不得).*(?:control|contract)'; Label='Builder control-file prohibition'},
                    @{Text=$roles; Pattern='Verifier.*(?:must not|不得).*(?:Candidate|commit)'; Label='Verifier mutation prohibition'},
                    @{Text=$modes; Pattern='(?s)START.*RESUME.*AUDIT.*STATUS_ONLY'; Label='run modes'},
                    @{Text=$modes; Pattern='(?s)PLANNED.*READY.*ACTIVE.*REVIEW.*REPAIR.*BLOCKED.*CHANGED.*ACCEPTED'; Label='milestone states'},
                    @{Text=$modes; Pattern='GOAL_REVIEW.*GOAL_ACCEPTED'; Label='goal states'},
                    @{Text=$modes; Pattern='(?s)ACTIVE.*EVIDENCE_NEEDED.*RESOLVED.*UNRESOLVED'; Label='specialist states'},
                    @{Text=$orchestration; Pattern='Candidate.*(?:freeze|冻结)'; Label='candidate freeze'},
                    @{Text=$orchestration; Pattern='PAUSE_AFTER_MILESTONE|CONTINUOUS_MODE'; Label='pause/continuous policy'},
                    @{Text=$orchestration; Pattern='acceptance-necessary Specialist.*UNRESOLVED.*UNAVAILABLE'; Label='continuous Specialist unavailable gate'},
                    @{Text=$git; Pattern='fixed.*SHA.*Verifier|Verifier.*fixed.*SHA'; Label='fixed candidate worktree'},
                    @{Text=$git; Pattern='Builder needs specialist.*returns the lease to Goalkeeper.*SPECIALIST_IN_PROGRESS'; Label='Builder Specialist handoff'},
                    @{Text=$git; Pattern='Verifier needs specialist.*Candidate.*Evidence SHA remain frozen.*returns control to Goalkeeper.*SPECIALIST_IN_PROGRESS'; Label='Verifier Specialist handoff'},
                    @{Text=$git; Pattern='git diff --exit-code'; Label='working-tree diff invariant'},
                    @{Text=$git; Pattern='git diff --cached --exit-code'; Label='index diff invariant'},
                    @{Text=$git; Pattern='REVIEW_INVALID'; Label='review invalid outcome'},
                    @{Text=$git; Pattern='VERSION_INTEGRITY_FAIL'; Label='version integrity outcome'},
                    @{Text=$git; Pattern='control-only.*acceptance|control.*acceptance.*commit'; Label='control acceptance commit'},
                    @{Text=$git; Pattern='git\s+push|rebase|reset\s+--hard'; Label='prohibited git operations'}
                )
                if ($roles -notlike '*Goalkeeper -> Builder*' -and $roles -notlike '*Goalkeeper → Builder*') { $missing.Add('formal command edge') }
                if ($roles -notlike '*Goalkeeper -> Verifier*' -and $roles -notlike '*Goalkeeper → Verifier*') { $missing.Add('formal command edge') }
                foreach ($entry in $requiredTerms) { if ($entry.Text -notmatch $entry.Pattern) { $missing.Add($entry.Label) } }
                $combined = ($roles + "`n" + $modes + "`n" + $orchestration + "`n" + $git)
                $forbiddenPositive = @(
                    @{Pattern='Goalkeeper\s+(?:may|can|is allowed to)\s+(?:edit|modify)\s+business'; Label='Goalkeeper business-code authority'},
                    @{Pattern='Builder\s+(?:may|can|is allowed to)\s+(?:change|modify)\s+(?:contracts?|control files?)'; Label='Builder control authority'},
                    @{Pattern='Verifier\s+(?:may|can|is allowed to)\s+(?:modify|change)\s+Candidate'; Label='Verifier candidate mutation'},
                    @{Pattern='Verifier\s+(?:may|can|is allowed to)\s+commit'; Label='Verifier commit authority'},
                    @{Pattern='Builder\s+(?:may|can|is allowed to)\s+(?:self-)?accept'; Label='Builder self-acceptance'},
                    @{Pattern='Verifier\s+(?:may|can|is allowed to)\s+(?:give|make|declare).*Goal.*(?:accept|accepted)'; Label='Verifier goal acceptance'},
                    @{Pattern='fallback\s+to\s+(?:the\s+)?main thread\s+when\s+Verifier'; Label='Verifier fallback'},
                    @{Pattern='(?:small|simple) tasks?.*(?:downgrade|skip).*?(?:\ballowed\b|\bmay\b|\bcan\b)|implicit.*mode.*downgrade.*?(?:\ballowed\b|\bmay\b|\bcan\b)'; Label='implicit mode downgrade'},
                    @{Pattern='unaccepted Candidate.*(?:\ballowed\b|\bmay\b|\bcan\b).*(?:next|new).*milestone.*base|Candidate.*(?:always|\bmay\b).*be.*next.*base'; Label='unaccepted candidate inheritance'}
                )
                $lines = @($combined -split "`r?`n")
                foreach ($entry in $forbiddenPositive) {
                    if (@($lines | Where-Object { $_ -match ('(?i)' + $entry.Pattern) }).Count -gt 0) { $missing.Add('forbidden: ' + $entry.Label) }
                }
                $passed = $missing.Count -eq 0
                $message = if ($passed) { 'governance references and authority constraints present' } else { 'missing or contradictory: ' + (($missing | Select-Object -First 12) -join ', ') }
            }
            'evidence_recovery' {
                $path = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references\evidence-and-recovery.md'
                $body = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $path } else { '' }
                $ruleCheck = Test-PfcEvidenceRecoveryRules -Text $body
                $passed = (Test-Path -LiteralPath $path -PathType Leaf) -and $ruleCheck.Passed
                $message = if ($passed) { 'evidence, convergence, and recovery rules present' } else { 'missing: ' + (($ruleCheck.Missing | Select-Object -First 8) -join ', ') }
            }
            'windows_runtime' {
                $path = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references\windows-runtime.md'
                $body = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $path } else { '' }
                $ruleCheck = Test-PfcWindowsRuntimeRules -Text $body
                $passed = (Test-Path -LiteralPath $path -PathType Leaf) -and $ruleCheck.Passed
                $message = if ($passed) { 'Windows runtime rules present' } else { 'missing: ' + (($ruleCheck.Missing | Select-Object -First 8) -join ', ') }
            }
            'specialist_protocol' {
                $path = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references\specialist-protocol.md'
                $body = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $path } else { '' }
                $terms = @(
                    'Goalkeeper-only', 'SPECIALIST_REQUEST', 'advisory', 'SPECIALIST_ORDER', 'only authorized input',
                    'one active Specialist', 'one question', 'one evidence expansion', 'no nested agents',
                    'fixed Evidence SHA', 'narrow Context Packet', 'independent.*disposable worktree',
                    'static-first', 'minimum diagnostic command', 'synchronous pause',
                    'FINDING', 'EVIDENCE_NEEDED', 'UNRESOLVED', 'ACCEPT', 'REWORK', 'BLOCKED',
                    'Evidence.*Guidance.*applicability', 'necessary-prerequisite', 'no formal state-machine verdict',
                    'Candidate.*(?:modify|modification|mutation)', 'commit', 'network', 'installation', 'full-context', 'whole-repository scan',
                    'same.*Order ID', 'Evidence Round.*0.*1', 'at most once', 'persist.*approved.*Order', 'final.*Report'
                )
                $missing = @($terms | Where-Object { $body -notmatch ('(?is)' + $_) })
                if ($body -match '(?is)Candidate\s+(?:modification|changes?)\s+(?:is\s+)?(?:allowed|permitted)|Specialist\s+(?:may|can)\s+(?:modify|change)\s+Candidate') { $missing += 'Candidate modification permission' }
                $passed = (Test-Path -LiteralPath $path -PathType Leaf) -and $missing.Count -eq 0
                $message = if ($passed) { 'conditional Specialist protocol constraints present' } else { 'missing: ' + (($missing | Select-Object -First 12) -join ', ') }
            }
            'specialist_schema' {
                $path = Join-Path $RepositoryRoot.FullName 'evals\schemas\specialist-report.schema.json'
                $missing = New-Object System.Collections.Generic.List[string]
                try {
                    $schema = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
                    if ($schema.type -cne 'object') { $missing.Add('object type') }
                    if ([string]$schema.additionalProperties -cne 'False') { $missing.Add('root additionalProperties false') }
                    if (@($schema.required) -notcontains 'status') { $missing.Add('required status') }
                    if ((@($schema.oneOf)).Count -ne 3) { $missing.Add('three state branches') }
                    $allowed = @('FINDING','EVIDENCE_NEEDED','UNRESOLVED')
                    foreach ($state in $allowed) {
                        $branch = @($schema.oneOf | Where-Object { (@($_.properties.status.enum) -contains $state) })
                        if ($branch.Count -ne 1) { $missing.Add('branch ' + $state) ; continue }
                        if ([string]$branch[0].additionalProperties -cne 'False') { $missing.Add($state + ' additionalProperties false') }
                        if (@($branch[0].required) -notcontains 'status') { $missing.Add($state + ' required status') }
                    }
                    $sha = $schema.properties.evidence_sha.pattern
                    if ($sha -cne '^[0-9a-f]{40}$') { $missing.Add('evidence SHA pattern') }
                    if (@($schema.properties.status.enum) -contains 'ACCEPT' -or @($schema.properties.status.enum) -contains 'REWORK' -or @($schema.properties.status.enum) -contains 'BLOCKED') { $missing.Add('formal verdict states forbidden') }
                } catch { $missing.Add('valid JSON schema') }
                $passed = (Test-Path -LiteralPath $path -PathType Leaf) -and $missing.Count -eq 0
                $message = if ($passed) { 'strict state-specific Specialist report schema present' } else { 'missing or invalid: ' + (($missing | Select-Object -First 12) -join ', ') }
            }
        }
        if ([string]::IsNullOrEmpty($message)) { $message = if ($passed) { 'verified' } else { 'check failed' } }
        Add-CheckResult -Id $check.id -Passed $passed -Message $message
    }
    return @($results | Sort-Object ScenarioId)
}

function Invoke-PfcMessageContractChecks {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('RED','GREEN')][string]$Phase
    )
    $results = New-Object System.Collections.Generic.List[object]
    $contract = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\references\message-contracts.md'
    $templateRoot = Join-Path $RepositoryRoot.FullName 'skill\project-flight-control\assets\templates'
    $common = @('Control Run ID','Lease Epoch','Goal ID','Goal Version','Milestone ID','Milestone Contract Version','Revision','Sender Role','Recipient Role','Created At')
    $required = @('project','roadmap','status','decisions','work-order','build-report','verify-order','review-report','rework-order','evidence-record','decision-packet','human-verification-request','human-verification-response','acceptance-report','final-review-report','specialist-request','specialist-order','specialist-report')
    $cnPurpose = (([char]0x9A8C),([char]0x8BC1),([char]0x76EE),([char]0x7684) -join '')
    $cnPrereq = (([char]0x524D),([char]0x7F6E),([char]0x6761),([char]0x4EF6) -join '')
    $cnSteps = (([char]0x64CD),([char]0x4F5C),([char]0x6B65),([char]0x9AA4) -join '')
    $cnExpected = (([char]0x9884),([char]0x671F),([char]0x7ED3),([char]0x679C) -join '')
    $cnFailure = (([char]0x5931),([char]0x8D25),([char]0x8868),([char]0x73B0) -join '')
    $cnEvidence = (([char]0x9700),([char]0x8981),([char]0x7684),([char]0x8BC1),([char]0x636E) -join '')
    $cnRedact = (([char]0x8131),([char]0x654F),([char]0x8981),([char]0x6C42) -join '')
    $cnValidity = (([char]0x8BC1),([char]0x636E),([char]0x6709),([char]0x6548),([char]0x671F) -join '')
    $specific = @{
        project = @('Base SHA','Project Name','Goal Statement','Canonical Project Sources','Non-goals','Constraints','Acceptance Criteria','Current State')
        roadmap = @('Base SHA','Roadmap Version','Milestones','Dependencies','Next Authorized Action')
        status = @('Base SHA','Candidate SHA','Updated At','Goal State','Milestone State','Current Owner','Current Lease','Convergence Snapshot','Done','In Progress','Next','Blockers','Pending Decision','Next Authorized Action')
        decisions = @('Candidate SHA','Decision','Evidence Basis','Required Repairs','Non-blocking Backlog Items','Residual Risk','Contract Change','Scope Impact','Roadmap Impact','Forecast Impact','Next Authorized Action')
        'work-order' = @('Base SHA','Work Order ID','Goal / Target Result','Authorized Scope','Non-goals / Forbidden Scope','Constraints','Dependencies','Acceptance Criteria','Required Verification','Relevant Baseline Observations','Relevant Evidence References','Known Risks','Expected Evidence')
        'build-report' = @('Base SHA','Candidate SHA','Work Order ID','Changed Files','Implemented Criteria','Commands Run','Observed Results','Verification Status','NOT_RUN Items','Known Limitations','Scope Deviations','Open Risks','Evidence IDs / Locations','Efficiency Exception','Debugging Summary','Convergence Inputs')
        'verify-order' = @('Base SHA','Candidate SHA','Verify Order ID','Acceptance Criteria','Constraints','Changed Files','Required Verification','Builder Evidence IDs','Known Risks','Relevant Specialist Order / Report IDs','Required Independent Checks')
        'review-report' = @('Candidate SHA','Alignment Result','Evidence Integrity Result','Technical Result','Environment','Builder Evidence Reused','Independent Commands Run','Observed Results','Version Integrity','Findings','Residual Risks','Specialist Dependency Status','Verdict')
        'rework-order' = @('Base SHA','Candidate SHA','Rework Order ID','Source Review Report ID','Required Repairs','Acceptance Criteria','Scope','Constraints','Verification After Repair','Repair Round')
        'evidence-record' = @('Candidate SHA','Candidate Timing','Evidence ID','Source','Command / Verification Action','Working Directory','Environment','Exit Code / Result Claimed','Observed Result','Covered Criteria','Evidence Location')
        'decision-packet' = @('Candidate SHA','Decision Context','Options','Recommendation','Evidence Basis','Scope Impact','Roadmap Impact','Forecast Impact','Next Authorized Action')
        'human-verification-request' = @('Candidate SHA','Evidence SHA','Verification ID','Related Acceptance Criterion',$cnPurpose,$cnPrereq,$cnSteps,$cnExpected,$cnFailure,$cnEvidence,$cnRedact,$cnValidity)
        'human-verification-response' = @('Candidate SHA','Evidence SHA','Verification ID','Environment','Observed Result','Evidence','Unexpected Behavior','Result Claimed')
        'acceptance-report' = @('Base SHA','Candidate SHA','Goal Code SHA','Goal Checkpoint SHA','Overall Result','Goal Alignment','Milestone State','Verification','Blockers','Residual Risks')
        'final-review-report' = @('Base SHA','Candidate SHA','Goal Code SHA','Goal Checkpoint SHA','Overall Result','Goal Alignment','Milestone State','Verification','Blockers','Residual Risks','Version Integrity','Findings')
        'specialist-request' = @('Evidence SHA','Request ID','Requester','Question','Why Specialist Is Required','Decision Affected','Relevant Acceptance Criteria','Relevant Scope','Known Evidence')
        'specialist-order' = @('Evidence SHA','Specialist Order ID','Request ID','Specialist Perspective','Question','Decision Affected','Allowed Files / Symbols / Evidence','Known Evidence','Allowed Diagnostic Action','Evidence Round','Required Output')
        'specialist-report' = @('Evidence SHA','Specialist Report ID','Specialist Order ID','Question','Finding','Evidence','Risk','Recommendation','Confidence','Diagnostics Run','Status','Missing Evidence','Why Required','Requested Scope','Requested Diagnostic','Known','Unknown','Evidence Reviewed','Why Unresolved','Decision Risk','Recommended Next Action')
    }
    $missing = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $contract -PathType Leaf)) { $missing.Add('message-contracts.md') }
    $v2Bindings = Get-PfcV2TemplateBindings -RepositoryRoot $RepositoryRoot
    foreach ($name in $required) {
        $path = Join-Path $templateRoot ($name + '.md')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add($name + '.md'); continue }
        $body = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
        $labels = @([regex]::Matches($body, '(?m)^(?=[^ \t#:])([^#:\r\n]+):\s*(\S.*)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
        $additional = $v2Bindings.existing.PSObject.Properties[$name]
        $expected = @($common + $specific[$name])
        if ($null -ne $additional) { $expected += @($additional.Value) }
        foreach ($field in $expected) { if ($labels -notcontains $field) { $missing.Add($name + ': missing ' + $field) } }
        $duplicates = @($labels | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
        foreach ($field in $duplicates) { $missing.Add($name + ': duplicate ' + $field) }
        foreach ($label in $labels) { if ($expected -notcontains $label) { $missing.Add($name + ': unknown ' + $label) } }
        foreach ($line in @($body -split "`r?`n")) {
            if ($line -match '^(?=[^ \t#:])([^#:\r\n]+):\s*(.*)$') {
                $value = $Matches[2].Trim(); if ([string]::IsNullOrWhiteSpace($value)) { $missing.Add($name + ': invalid empty value') }
            }
        }
        if ($body -match '(?i)defines?\s+(?:the\s+)?state\s+transition|authoritative\s+field\s+definition') { $missing.Add($name + ': duplicate authority prose') }
    }
    $status = if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }
    $message = if ($missing.Count -eq 0) { 'all message contracts and templates present' } else { 'missing: ' + (($missing | Select-Object -First 12) -join ', ') }
    $results.Add((New-PfcResult -ScenarioId 'package.message_contracts.templates' -Status $status -Message $message))
    $authorityBody = if (Test-Path -LiteralPath $contract -PathType Leaf) { Get-Content -Raw -Encoding UTF8 -LiteralPath $contract } else { '' }
    $authorityPass = ($authorityBody -match '(?i)only field-definition authority') -and ($authorityBody -match '(?i)WORK_ORDER') -and ($authorityBody -match '(?i)PROJECT_CONTROL_REPORT')
    $authorityMessage = if ($authorityPass) { 'single field authority and formal message families declared' } else { 'authority or message family declaration missing' }
    $authorityStatus = if ($authorityPass) { 'PASS' } else { 'FAIL' }
    $results.Add((New-PfcResult -ScenarioId 'package.message_contracts.authority' -Status $authorityStatus -Message $authorityMessage))
    foreach ($result in @(Invoke-PfcV2ContractChecks -RepositoryRoot $RepositoryRoot)) { $results.Add($result) }
    return @($results.ToArray())
}

Export-ModuleMember -Function Invoke-PfcStaticChecks, Invoke-PfcMessageContractChecks, Test-PfcEvidenceRecoveryRules, Test-PfcWindowsRuntimeRules, Invoke-PfcV2ContractChecks, Test-PfcV2ControlSemantics, Test-PfcV2SchemaValue, Test-PfcContinuousSourceContract, Test-PfcContinuousSmokeResults
