Set-StrictMode -Version 2.0
$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PromptBudget.psm1') -Force

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
    Get-ChildItem -LiteralPath $Root.FullName -Recurse -File | Where-Object {
        $_.FullName -notmatch '\\.git\\|\\.pfc-eval-results\\|\\tmp\\' -and $_.Extension -in @('.md','.yaml','.yml','.toml','.ps1','.psm1','.json','.txt')
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
                    $forbidden = @(
                        'Verifier\s+(?:may|can|is allowed to)\s+(?:modify|change)\s+Candidate',
                        'Verifier\s+(?:may|can|is allowed to)\s+commit',
                        'Verifier\s+(?:may|can|is allowed to)\s+(?:change|modify)\s+(?:control files|contracts?)',
                        'Verifier\s+(?:may|can|is allowed to)\s+directly\s+command\s+Builder'
                    )
                    foreach ($pattern in $forbidden) { if ($profile -match ('(?is)' + $pattern)) { $missing.Add('forbidden authority: ' + $pattern) } }
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
    foreach ($name in $required) {
        $path = Join-Path $templateRoot ($name + '.md')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add($name + '.md'); continue }
        $body = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
        $labels = @([regex]::Matches($body, '(?m)^(?=[^ \t#:])([^#:\r\n]+):\s*(\S.*)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
        $expected = @($common + $specific[$name])
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
    return @($results.ToArray())
}

Export-ModuleMember -Function Invoke-PfcStaticChecks, Invoke-PfcMessageContractChecks, Test-PfcEvidenceRecoveryRules, Test-PfcWindowsRuntimeRules
