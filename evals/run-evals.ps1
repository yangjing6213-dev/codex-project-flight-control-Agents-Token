[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Bootstrap','StaticPackage','Harness','BuilderEfficiency','Revision4Isolation','RunnerRevision3','PermissionProbeFileHandshake','PermissionProbeExecutionPolicy','BuilderProfile','VerifierProfile','MessageContracts','GovernanceReferences','EvidenceRecovery','SkillEntry','SpecialistProtocol','Installer','Doctor','SpecialistSmokeUnit','ContinuousContracts','ContinuousMode','ContinuousModeWindowsSmoke','ContinuousModeModelContract','ContinuousModeModel')][string]$Suite,
    [ValidateSet('RED','GREEN')][string]$Phase = 'GREEN',
    [ValidateRange(1,5)][int]$Repeat = 1,
    [switch]$Json,
    [string]$AuthorizationPath,
    # Optional full path for PowerShell sessions where `codex` is not on PATH.
    [AllowNull()][string]$CodexExecutablePath,
    [switch]$DiagnosticCanary
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -Force -ErrorAction Stop
if($DiagnosticCanary -and ($Suite -cne 'ContinuousModeModel' -or $Repeat -ne 1 -or -not $PSBoundParameters.ContainsKey('Phase') -or [string]::IsNullOrWhiteSpace($AuthorizationPath))) {
    throw 'Diagnostic Canary requires ContinuousModeModel, an explicit RED or GREEN phase, Repeat 1, and an authorization file.'
}
Import-Module (Join-Path $PSScriptRoot 'lib\TestHarness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\CodexRunner.psm1') -Force
if ($Suite -in @('StaticPackage','Harness','BuilderProfile','VerifierProfile','MessageContracts','GovernanceReferences','EvidenceRecovery','SpecialistProtocol','ContinuousMode','ContinuousModeWindowsSmoke')) {
    Import-Module (Join-Path $PSScriptRoot 'lib\StaticChecks.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'lib\TestHarness.psm1') -Force
}
if ($Suite -in @('PermissionProbeFileHandshake','PermissionProbeExecutionPolicy')) {
    Import-Module (Join-Path $PSScriptRoot 'lib\PermissionProbeHandshake.psm1') -Force
}

function Invoke-Installer {
    $scenario = Join-Path $PSScriptRoot 'scenarios\core-governance\SC-15-installer-round-trip\scenario.ps1'
    return @( & $scenario -Phase $Phase -RepositoryRoot (Split-Path -Parent $PSScriptRoot) )
}

function Invoke-Doctor {
    $root = Split-Path -Parent $PSScriptRoot
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($name in @('SC-28-passive-doctor','SC-31-specialist-core-boundary')) {
        $scenario = Join-Path $PSScriptRoot ('scenarios\core-governance\' + $name + '\scenario.ps1')
        $results.AddRange(@(& $scenario -Phase $Phase -RepositoryRoot $root))
    }
    return $results.ToArray()
}

function Invoke-SpecialistSmokeUnit {
    $root = Split-Path -Parent $PSScriptRoot
    $results = New-Object System.Collections.Generic.List[object]
    $scenario = Join-Path $PSScriptRoot 'scenarios\specialist-capability\SpecialistSmokeUnit\scenario.ps1'
    $results.AddRange(@(& $scenario -Phase $Phase -RepositoryRoot $root))
    foreach ($name in @('SC-21-fixed-sha-worktree','SC-22-no-formal-verdict','SC-23-unresolved-prerequisite','SC-25-stale-evidence','SC-26-resume-same-order','SC-29-explicit-smoke','SC-30-capability-invalidation')) {
        $entry = Join-Path $PSScriptRoot ('scenarios\specialist-capability\' + $name + '\scenario.ps1')
        $results.AddRange(@(& $entry -Phase $Phase -RepositoryRoot $root))
    }
    return $results.ToArray()
}

function Invoke-Revision4Isolation {
    $test = Join-Path $PSScriptRoot 'tests\Revision4Isolation.Tests.ps1'
    return @( & $test )
}

function Invoke-PermissionProbeFileHandshake {
    $test = Join-Path $PSScriptRoot 'tests\PermissionProbeFileHandshake.Tests.ps1'
    try {
        $output = @(& $test)
        return ,(New-PfcResult -ScenarioId 'PermissionProbeFileHandshake' -Status 'PASS' -Message (($output | Out-String).Trim()))
    } catch {
        return ,(New-PfcResult -ScenarioId 'PermissionProbeFileHandshake' -Status 'FAIL' -Message $_.Exception.Message)
    }
}

function Invoke-PermissionProbeExecutionPolicy {
    $test = Join-Path $PSScriptRoot 'tests\PermissionProbeExecutionPolicy.Tests.ps1'
    try {
        $output = @(& $test)
        return ,(New-PfcResult -ScenarioId 'PermissionProbeExecutionPolicy' -Status 'PASS' -Message (($output | Out-String).Trim()))
    } catch {
        return ,(New-PfcResult -ScenarioId 'PermissionProbeExecutionPolicy' -Status 'FAIL' -Message $_.Exception.Message)
    }
}

function Invoke-BuilderEfficiency {
    $root = Split-Path -Parent $PSScriptRoot
    $results = New-Object System.Collections.Generic.List[object]
    $tests = @(
        @{ Id = 'task3.contracts.all-scenarios'; Test = {
            $scenarioRoot = Join-Path $PSScriptRoot 'scenarios\builder-efficiency'
            $ids = @('EFF-01','EFF-02','EFF-03','EFF-04','EFF-05','EFF-06','EFF-07')
            $controlPath = Join-Path $root 'evals\schemas\schema-control.json'
            Assert-PfcTrue -Actual (Test-Path -LiteralPath $controlPath -PathType Leaf) -ScenarioId 'contract.schema-control.present' -Expected 'schema-control.json present'
            $control = Get-Content -Raw -LiteralPath $controlPath | ConvertFrom-Json
            Assert-PfcEqual -Expected 4 -Actual $control.eval_contract_revision -ScenarioId 'contract.schema-control.eval-revision'
            Assert-PfcEqual -Expected 2 -Actual $control.formal_schema_revision -ScenarioId 'contract.schema-control.formal-revision'
            Assert-PfcEqual -Expected 90 -Actual $control.runner.startup_timeout_seconds -ScenarioId 'contract.schema-control.startup-timeout'
            Assert-PfcEqual -Expected 600 -Actual $control.runner.pre_terminal_timeout_seconds -ScenarioId 'contract.schema-control.pre-terminal-timeout'
            Assert-PfcEqual -Expected 15 -Actual $control.runner.post_terminal_grace_seconds -ScenarioId 'contract.schema-control.post-terminal-grace'
            Assert-PfcEqual -Expected 'DISABLED' -Actual $control.runner.idle_timeout -ScenarioId 'contract.schema-control.idle-disabled'
            Assert-PfcEqual -Expected 0 -Actual $control.runner.automatic_retries -ScenarioId 'contract.schema-control.no-retries'
            Assert-PfcEqual -Expected ($ids -join ',') -Actual (@($control.scenarios) -join ',') -ScenarioId 'contract.schema-control.scenarios'
            $evalSchemaPath = Join-Path $root $control.schemas.eval_run.relative_path.Replace('/','\')
            $builderSchemaPath = Join-Path $root $control.schemas.builder_report.relative_path.Replace('/','\')
            foreach ($schemaInfo in @(@{key='eval_run';path=$evalSchemaPath},@{key='builder_report';path=$builderSchemaPath})) {
                Assert-PfcTrue -Actual (Test-Path -LiteralPath $schemaInfo.path -PathType Leaf) -ScenarioId ('contract.schema-control.' + $schemaInfo.key + '.present') -Expected 'present'
                Assert-PfcEqual -Expected $control.schemas.($schemaInfo.key).sha256 -Actual ((Get-FileHash -Algorithm SHA256 -LiteralPath $schemaInfo.path).Hash.ToLowerInvariant()) -ScenarioId ('contract.schema-control.' + $schemaInfo.key + '.hash')
                $preflight = Get-PfcSchemaPreflight -Path $schemaInfo.path
                Assert-PfcEqual -Expected 'PASS' -Actual $preflight.strict_schema_preflight -ScenarioId ('contract.schema-control.' + $schemaInfo.key + '.strict')
                Assert-PfcTrue -Actual (-not $preflight.schema_has_utf8_bom) -ScenarioId ('contract.schema-control.' + $schemaInfo.key + '.no-bom') -Expected 'no BOM'
            }
            foreach ($id in $ids) {
                $path = Join-Path (Join-Path $scenarioRoot ($id + '-' + (@{'EFF-01'='targeted-context';'EFF-02'='reuse-before-create';'EFF-03'='minimal-diff';'EFF-04'='delta-rework';'EFF-05'='incremental-verification';'EFF-06'='debugging-convergence';'EFF-07'='structured-recovery'}[$id]))) 'scenario.json'
                Assert-PfcTrue -Actual (Test-Path -LiteralPath $path -PathType Leaf) -ScenarioId ('contract.' + $id) -Expected 'scenario.json present'
                $c = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
                Assert-PfcEqual -Expected $id -Actual $c.scenario_id -ScenarioId ('contract.' + $id + '.id')
                Assert-PfcEqual -Expected 5 -Actual $c.repetition_count -ScenarioId ('contract.' + $id + '.repetitions')
                foreach ($field in @('primary_efficiency_metric','expected_improvement','allowed_trade_offs','forbidden_regressions','required_evidence','controls','prompt_sha256','schema_sha256')) {
                    Assert-PfcTrue -Actual ($null -ne $c.$field) -ScenarioId ('contract.' + $id + '.' + $field) -Expected 'declared'
                }
                $promptPath = Join-Path (Split-Path -Parent $path) 'common.md'
                $treatmentPath = Join-Path (Split-Path -Parent $path) 'treatment.md'
                Assert-PfcTrue -Actual (Test-Path -LiteralPath $promptPath -PathType Leaf) -ScenarioId ('contract.' + $id + '.common-prompt') -Expected 'common.md present'
                Assert-PfcTrue -Actual (Test-Path -LiteralPath $treatmentPath -PathType Leaf) -ScenarioId ('contract.' + $id + '.treatment-prompt') -Expected 'treatment.md present'
                Assert-PfcEqual -Expected $c.common_prompt_sha256 -Actual ((Get-FileHash -Algorithm SHA256 -LiteralPath $promptPath).Hash.ToLowerInvariant()) -ScenarioId ('contract.' + $id + '.common-prompt-hash')
                Assert-PfcEqual -Expected $c.treatment_sha256 -Actual ((Get-FileHash -Algorithm SHA256 -LiteralPath $treatmentPath).Hash.ToLowerInvariant()) -ScenarioId ('contract.' + $id + '.treatment-hash')
                Assert-PfcEqual -Expected '2' -Actual ([string]$c.controls.schema_version) -ScenarioId ('contract.' + $id + '.schema-revision')
                Assert-PfcEqual -Expected 4 -Actual $c.eval_contract_revision -ScenarioId ('contract.' + $id + '.eval-revision')
                Assert-PfcEqual -Expected $control.scenario_manifests.$id.sha256 -Actual ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()) -ScenarioId ('contract.' + $id + '.manifest-hash')
                Assert-PfcEqual -Expected $control.schemas.eval_run.sha256 -Actual $c.schema_sha256 -ScenarioId ('contract.' + $id + '.eval-schema-binding')
            }
        } },
        @{ Id = 'task3.fixture.sha-and-graph'; Test = {
            Import-Module (Join-Path $PSScriptRoot 'lib\FixtureRepository.psm1') -Force
            $dest = Join-Path ([IO.Path]::GetTempPath()) ('pfc-fixture-test-' + [guid]::NewGuid().ToString('N'))
            $dest2 = Join-Path ([IO.Path]::GetTempPath()) ('pfc-fixture-test-' + [guid]::NewGuid().ToString('N'))
            try {
                $f = New-PfcFixtureRepository -ScenarioId 'EFF-01' -DestinationRoot $dest
                $f2 = New-PfcFixtureRepository -ScenarioId 'EFF-01' -DestinationRoot $dest2
                Assert-PfcTrue -Actual (Test-Path -LiteralPath $f.root -PathType Container) -ScenarioId 'fixture.root' -Expected 'present'
                Assert-PfcTrue -Actual ($f.base_sha -match '^[0-9a-f]{40}$') -ScenarioId 'fixture.sha' -Expected '40-char sha'
                Assert-PfcEqual -Expected $f.base_sha -Actual $f2.base_sha -ScenarioId 'fixture.sha.deterministic'
                Assert-PfcTrue -Actual (@($f.expected_files).Count -gt 0) -ScenarioId 'fixture.files' -Expected 'non-empty'
                Assert-PfcTrue -Actual ($null -ne $f.expected_graph) -ScenarioId 'fixture.graph' -Expected 'declared'
                Assert-PfcEqual -Expected $f.head_sha -Actual (& git -C $f.root rev-parse HEAD).Trim() -ScenarioId 'fixture.graph.head-match'
                Assert-PfcEqual -Expected 0 -Actual $f.expected_graph.parent_count -ScenarioId 'fixture.graph.parent-count'
                Assert-PfcEqual -Expected 0 -Actual @(& git -C $f.root for-each-ref refs/heads).Count -ScenarioId 'fixture.graph.branch-refs'
                Assert-PfcTrue -Actual ((& git -C $f.root symbolic-ref -q --short HEAD 2>$null) -eq $null) -ScenarioId 'fixture.graph.detached' -Expected 'detached'
                foreach ($case in @(
                    @{ Id='EFF-02'; Paths=@('src/Helpers.ps1'); Pattern='Convert-ToReusableValue' },
                    @{ Id='EFF-04'; Paths=@('candidate/Candidate.ps1','CANDIDATE.md','REVIEW_REPORT.md'); Pattern='Narrow Verifier finding' },
                    @{ Id='EFF-05'; Paths=@('tests/Target.Tests.ps1','tests/Dependency.Signal.ps1'); Pattern='Seeded dependency signal' },
                    @{ Id='EFF-06'; Paths=@('FAILURE.md'); Pattern='Hypothesis A:|Hypothesis B:|third speculative patch' },
                    @{ Id='EFF-07'; Paths=@('CONTRACT.md','BUILD_REPORT.md','REVIEW_REPORT.md','STATUS'); Pattern='RESUMABLE|BASE_SHA|BUILD_REPORT' }
                )) {
                    $caseRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-fixture-case-' + [guid]::NewGuid().ToString('N'))
                    try { $cf = New-PfcFixtureRepository -ScenarioId $case.Id -DestinationRoot $caseRoot; foreach ($rp in $case.Paths) { Assert-PfcTrue -Actual (Test-Path -LiteralPath (Join-Path $cf.root $rp) -PathType Leaf) -ScenarioId ('fixture.' + $case.Id + '.' + $rp) -Expected 'present' }; $joined = ($case.Paths | ForEach-Object { Get-Content -Raw -LiteralPath (Join-Path $cf.root $_) }) -join "`n"; Assert-PfcTrue -Actual ($joined -match $case.Pattern) -ScenarioId ('fixture.' + $case.Id + '.content') -Expected $case.Pattern; if ($case.Id -eq 'EFF-04') { $candidateText = Get-Content -Raw -LiteralPath (Join-Path $cf.root 'CANDIDATE.md'); Assert-PfcTrue -Actual ($candidateText -match ('BASE_SHA:\s*' + $cf.base_sha)) -ScenarioId 'fixture.EFF-04.candidate-sha' -Expected 'candidate SHA persisted' }; if ($case.Id -eq 'EFF-07') { $persisted = (Get-Content -Raw -LiteralPath (Join-Path $cf.root 'BASE_SHA')).Trim(); Assert-PfcTrue -Actual ($persisted -match '^[0-9a-f]{40}$') -ScenarioId 'fixture.EFF-07.base-sha-format' -Expected '40-char SHA'; Assert-PfcEqual -Expected $cf.base_sha -Actual $persisted -ScenarioId 'fixture.EFF-07.base-sha-match'; Assert-PfcEqual -Expected $cf.head_sha -Actual ((& git -C $cf.root rev-parse HEAD).Trim()) -ScenarioId 'fixture.EFF-07.head-match'; Assert-PfcEqual -Expected 1 -Actual $cf.expected_graph.parent_count -ScenarioId 'fixture.EFF-07.parent-count'; Assert-PfcEqual -Expected 2 -Actual @($cf.expected_graph.commits).Count -ScenarioId 'fixture.EFF-07.commit-count'; Assert-PfcEqual -Expected $cf.base_sha -Actual $cf.expected_graph.commits[0] -ScenarioId 'fixture.EFF-07.graph-base'; Assert-PfcEqual -Expected $cf.head_sha -Actual $cf.expected_graph.commits[1] -ScenarioId 'fixture.EFF-07.graph-head'; $parents = @((& git -C $cf.root rev-list --parents -n 1 HEAD) -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }); Assert-PfcEqual -Expected 2 -Actual $parents.Count -ScenarioId 'fixture.EFF-07.rev-list-parent-count'; Assert-PfcEqual -Expected $cf.head_sha -Actual $parents[0] -ScenarioId 'fixture.EFF-07.rev-list-head'; Assert-PfcEqual -Expected $cf.base_sha -Actual $parents[1] -ScenarioId 'fixture.EFF-07.rev-list-base'; $clean = (& git -C $cf.root status --porcelain); if ($null -eq $clean) { $clean = '' }; Assert-PfcEqual -Expected '' -Actual ([string]$clean).Trim() -ScenarioId 'fixture.EFF-07.clean'; foreach ($meta in @('BASE_SHA','STATUS','CONTRACT.md')) { $tree = (& git -C $cf.root show ('HEAD:' + $meta)); Assert-PfcEqual -Expected (Get-Content -Raw -LiteralPath (Join-Path $cf.root $meta)) -Actual (($tree -join "`n") + "`n") -ScenarioId ('fixture.EFF-07.tree-' + $meta) } } } finally { if (Test-Path $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force } }
                }
            } finally { if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }; if (Test-Path $dest2) { Remove-Item -LiteralPath $dest2 -Recurse -Force } }
        } },
        @{ Id = 'task3.runner.allowlist-and-safety'; Test = {
            Import-Module (Join-Path $PSScriptRoot 'lib\CodexRunner.psm1') -Force
            $jsonl = @(
                (@{type='turn.started'; command='C:\Users\alice\secret.txt'} | ConvertTo-Json -Compress),
                (@{type='tool.call'; tool='git'; command='git status'; path='C:\Users\alice\repo\x.txt'} | ConvertTo-Json -Compress),
                (@{type='turn.completed'; usage=@{input_tokens=12; output_tokens=3}} | ConvertTo-Json -Compress),
                (@{type='turn.completed'; result='raw reasoning should be ignored'; usage=@{input_tokens=1}} | ConvertTo-Json -Compress)
            )
            $m = Read-PfcCodexJsonlMetrics -Lines $jsonl
            Assert-PfcTrue -Actual ($m.event_types -contains 'turn.completed') -ScenarioId 'runner.events' -Expected 'allowlisted events'
            Assert-PfcEqual -Expected 1 -Actual $m.tool_call_count -ScenarioId 'runner.tool-count'
            Assert-PfcTrue -Actual (($m | ConvertTo-Json -Compress) -match 'input_tokens.{0,4}12') -ScenarioId 'runner.usage' -Expected 'input_tokens=12'
            Assert-PfcTrue -Actual ($m.raw_result -eq $null) -ScenarioId 'runner.raw-ignored' -Expected 'null'
            Assert-PfcTrue -Actual (($m.file_change_paths -join '|') -notmatch 'C:\\Users\\alice') -ScenarioId 'runner.redaction' -Expected 'redacted'
            $missingMetrics = Read-PfcCodexJsonlMetrics -Lines @((@{type='turn.completed'} | ConvertTo-Json -Compress))
            Assert-PfcTrue -Actual ((($missingMetrics | ConvertTo-Json -Compress) -match 'NOT_AVAILABLE')) -ScenarioId 'runner.usage-unavailable' -Expected 'NOT_AVAILABLE'
            $itemLines = @(
                (@{type='item.completed'; item=@{type='command_execution'; command='git status'}} | ConvertTo-Json -Compress -Depth 5),
                (@{type='item.completed'; item=@{type='file_change'; changes=@(@{file_path='\\server\share\secret.txt'})}} | ConvertTo-Json -Compress -Depth 5),
                (@{type='item.completed'; item=@{type='file_change'; path='C:\tmp\sk-1234567890-ghp_1234567890-Bearer-token'}} | ConvertTo-Json -Compress -Depth 5),
                (@{type='item.completed'; item=@{type='file_change'; changes=@(@{path='/opt/project/x'; filePath='/root/.codex/auth.json'})}} | ConvertTo-Json -Compress -Depth 5),
                (@{type='turn.failed'; error='failed'} | ConvertTo-Json -Compress)
            )
            $itemMetrics = Read-PfcCodexJsonlMetrics -Lines $itemLines
            Assert-PfcEqual -Expected 1 -Actual $itemMetrics.command_count -ScenarioId 'runner.item-command-count'
            $activityMetrics = Read-PfcCodexJsonlMetrics -Lines @(
                (@{type='item.completed'; item=@{type='mcp_tool_call'}} | ConvertTo-Json -Compress -Depth 5),
                (@{type='item.completed'; item=@{type='web_search'}} | ConvertTo-Json -Compress -Depth 5)
            )
            Assert-PfcEqual -Expected 1 -Actual $activityMetrics.mcp_tool_call_count -ScenarioId 'runner.item-mcp-count'
            Assert-PfcEqual -Expected 1 -Actual $activityMetrics.web_search_count -ScenarioId 'runner.item-web-count'
            Assert-PfcTrue -Actual ($itemMetrics.event_types -contains 'turn.failed') -ScenarioId 'runner.failure-event' -Expected 'present'
            Assert-PfcEqual -Expected 'FAILED' -Actual $itemMetrics.turn_result -ScenarioId 'runner.failure-result'
            Assert-PfcTrue -Actual (($itemMetrics.file_change_paths -join '|') -notmatch '(?i)server|share|secret|sk-|gh[pousr]_|/opt/|/root/') -ScenarioId 'runner.unc-redaction' -Expected 'redacted'
            $sensitiveMessage = Read-PfcCodexJsonlMetrics -Lines @((@{type='item.completed'; item=@{type='agent_message'; text='done C:\Users\alice\secret.txt sk-1234567890'}} | ConvertTo-Json -Compress -Depth 5), '{"type":"turn.completed"}')
            Assert-PfcTrue -Actual (($sensitiveMessage.final_agent_message -notmatch '(?i)C:\\Users\\alice|sk-1234567890') -and $sensitiveMessage.final_agent_message -match '<ABSOLUTE_PATH>|<REDACTED_SECRET>') -ScenarioId 'runner.agent-redaction' -Expected 'redacted'
            $invalidJson = Read-PfcCodexJsonlMetrics -Lines @('not-json','{"type":"turn.completed"}')
            Assert-PfcEqual -Expected 1 -Actual $invalidJson.invalid_json_lines -ScenarioId 'runner.invalid-json-count'
        } },
        @{ Id = 'task3.runner.fail-closed'; Test = {
            Import-Module (Join-Path $PSScriptRoot 'lib\CodexRunner.psm1') -Force
            $thrown = $false
            try { Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath (Join-Path $root 'README.md') -OutputSchemaPath (Join-Path $root 'missing-schema.json') -SandboxMode 'workspace-write' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'RED' -ProcessInvoker { param($a) throw 'codex not found' } } catch { $thrown = $true }
            Assert-PfcTrue -Actual $thrown -ScenarioId 'runner.fail-closed' -Expected 'throw'
            $authThrown = $false
            try { Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath (Join-Path $root 'README.md') -OutputSchemaPath (Join-Path $root 'evals\schemas\eval-run.schema.json') -SandboxMode 'workspace-write' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'RED' -ProcessInvoker { param($a) [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'authentication required' } } } catch { $authThrown = $true }
            Assert-PfcTrue -Actual $authThrown -ScenarioId 'runner.unauthenticated' -Expected 'throw'
            $stdoutAuthThrown = $false
            try { Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath (Join-Path $root 'README.md') -OutputSchemaPath (Join-Path $root 'evals\schemas\eval-run.schema.json') -SandboxMode 'workspace-write' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'RED' -ProcessInvoker { param($a) [pscustomobject]@{ ExitCode = 0; StdOut = 'authentication required'; StdErr = '' } } } catch { $stdoutAuthThrown = $true }
            Assert-PfcTrue -Actual $stdoutAuthThrown -ScenarioId 'runner.stdout-unauthenticated' -Expected 'throw'
            $invalidThrown = $false
            try { Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath (Join-Path $root 'README.md') -OutputSchemaPath (Join-Path $root 'evals\schemas\eval-run.schema.json') -SandboxMode 'workspace-write' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'RED' -ProcessInvoker { param($a) [pscustomobject]@{ ExitCode = 0; StdOut = ('not-json' + [Environment]::NewLine + '{"type":"turn.completed"}'); StdErr = '' } } } catch { $invalidThrown = $_.Exception.Message -match 'invalid lines' }
            Assert-PfcTrue -Actual $invalidThrown -ScenarioId 'runner.invalid-json-fail-closed' -Expected 'throw'
        } },
        @{ Id = 'task3.runner.command-contract'; Test = {
            Import-Module (Join-Path $PSScriptRoot 'lib\CodexRunner.psm1') -Force
            $prompt = Join-Path $root 'README.md'; $schema = Join-Path $root 'evals\schemas\eval-run.schema.json'; $seen = $null
            $fake = { param($a) $script:seen = @($a); [pscustomobject]@{ ExitCode = 0; StdOut = '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":2}}'; StdErr = '' } }
            $result = Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath $prompt -OutputSchemaPath $schema -SandboxMode 'workspace-write' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'GREEN' -ProcessInvoker $fake
            Assert-PfcTrue -Actual ($result.arguments -contains '--json') -ScenarioId 'runner.args.json' -Expected 'present'
            Assert-PfcTrue -Actual ($result.arguments -contains '--sandbox') -ScenarioId 'runner.args.sandbox' -Expected 'present'
            Assert-PfcTrue -Actual ($result.arguments -contains 'workspace-write') -ScenarioId 'runner.args.workspace-write' -Expected 'present'
            Assert-PfcTrue -Actual ($result.arguments -notcontains 'danger-full-access') -ScenarioId 'runner.args.no-danger' -Expected 'absent'
            Assert-PfcTrue -Actual (($result.arguments -join ' ') -notmatch '(?i)[A-Za-z]:\\|\\\\|/tmp/') -ScenarioId 'runner.args.path-redaction' -Expected 'redacted'
            Assert-PfcTrue -Actual ($result.raw_jsonl_path -notmatch '^[A-Za-z]:|^/') -ScenarioId 'runner.raw-path-safe' -Expected 'relative'
            $override = Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath $prompt -OutputSchemaPath $schema -SandboxMode 'workspace-write' -Phase 'GREEN' -Model 'gpt-5.6-terra' -ReasoningEffort 'medium' -ResultDirectory (Join-Path $root '.pfc-eval-results') -ProcessInvoker $fake
            Assert-PfcTrue -Actual ($override.arguments -contains 'gpt-5.6-terra') -ScenarioId 'runner.args.model-override' -Expected 'terra'
            Assert-PfcTrue -Actual ($override.arguments -contains 'model_reasoning_effort="medium"') -ScenarioId 'runner.args.reasoning-override' -Expected 'medium'
            Assert-PfcTrue -Actual ($override.arguments -notcontains 'windows.sandbox="elevated"') -ScenarioId 'runner.args.windows-sandbox-default' -Expected 'absent without isolated config'
            $isolatedConfig = Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath $prompt -OutputSchemaPath $schema -SandboxMode 'workspace-write' -Phase 'GREEN' -IgnoreUserConfig -ResultDirectory (Join-Path $root '.pfc-eval-results') -ProcessInvoker $fake
            $windowsSandboxIndex = [array]::IndexOf(@($isolatedConfig.arguments), 'windows.sandbox="elevated"')
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                Assert-PfcTrue -Actual ($windowsSandboxIndex -gt 0 -and @($isolatedConfig.arguments | Where-Object { $_ -ceq 'windows.sandbox="elevated"' }).Count -eq 1 -and $isolatedConfig.arguments[$windowsSandboxIndex - 1] -ceq '-c') -ScenarioId 'runner.args.windows-sandbox-isolated' -Expected 'one elevated Windows backend override'
            } else {
                Assert-PfcTrue -Actual ($windowsSandboxIndex -eq -1) -ScenarioId 'runner.args.windows-sandbox-non-windows' -Expected 'absent on non-Windows'
            }
            foreach ($badDir in @((Join-Path (Split-Path -Parent $root) '.pfc-eval-results'), (([IO.Path]::GetFullPath($root) + '2') + '\.pfc-eval-results'), (Join-Path $root 'other-results'))) { $rejected = $false; try { Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath $prompt -OutputSchemaPath $schema -SandboxMode 'workspace-write' -ResultDirectory $badDir -Phase 'GREEN' -ProcessInvoker $fake } catch { $rejected = $true }; Assert-PfcTrue -Actual $rejected -ScenarioId 'runner.result-dir-boundary' -Expected 'rejected' }
        } },
        @{ Id = 'task3.runner.process-channel-regressions'; Test = {
            $runnerSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'lib\CodexRunner.psm1')
            foreach ($marker in @('ProcessStartInfo','RedirectStandardInput','RedirectStandardOutput','RedirectStandardError','StandardInput.Close()','BaseStream.ReadAsync','ReadToEndAsync()','Stop-PfcProcessTree','TimeoutSeconds','StreamWriter','OutputPath','CodexExecutablePath','ConvertFrom-Json')) {
                Assert-PfcTrue -Actual ($runnerSource.Contains($marker)) -ScenarioId ('runner.channel.' + $marker.Replace('.','-').Replace('(','').Replace(')','')) -Expected 'implementation marker'
            }
            Assert-PfcTrue -Actual ($runnerSource -notmatch '& codex @args 2>&1 \| Out-String') -ScenarioId 'runner.channel.no-merged-pipeline' -Expected 'direct process launch'
            Assert-PfcTrue -Actual ($runnerSource.Contains('rawStream.Write(') -and $runnerSource.Contains('rawStream.Flush()')) -ScenarioId 'runner.channel.realtime-flush' -Expected 'byte flush'
            $trailingNewline = { param($a) [pscustomobject]@{ ExitCode = 0; StdOut = ('{"type":"turn.completed"}' + [Environment]::NewLine); StdErr = '' } }
            $trailingResult = Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath (Join-Path $root 'README.md') -OutputSchemaPath (Join-Path $root 'evals\schemas\eval-run.schema.json') -SandboxMode 'workspace-write' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'GREEN' -ProcessInvoker $trailingNewline
            Assert-PfcEqual -Expected 'COMPLETED' -Actual $trailingResult.turn_result -ScenarioId 'runner.channel.trailing-newline'
            $timeoutRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-runner-timeout-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $timeoutRoot -Force | Out-Null
            try {
                $slowCmd = Join-Path $timeoutRoot 'codex.cmd'
                @('@echo off','powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 30; Write-Output PFC_TIMEOUT_CHILD"') | Set-Content -LiteralPath $slowCmd -Encoding ASCII
                $slowPrompt = Join-Path $timeoutRoot 'prompt.md'; $slowSchema = Join-Path $timeoutRoot 'schema.json'
                Set-Content -LiteralPath $slowPrompt -Value 'timeout' -Encoding UTF8; Write-PfcUtf8NoBom -Path $slowSchema -Content '{"type":"object","required":[],"properties":{},"additionalProperties":false}'
                $timedOut = $false; $timeoutError = ''
                try { Invoke-PfcCodexRun -WorkingDirectory $timeoutRoot -PromptPath $slowPrompt -OutputSchemaPath $slowSchema -SandboxMode 'workspace-write' -ResultDirectory (Join-Path $timeoutRoot '.pfc-eval-results') -Phase 'GREEN' -TimeoutSeconds 1 -CodexExecutablePath $slowCmd | Out-Null } catch { $timeoutError = $_.Exception.Message; $timedOut = $timeoutError -match 'timed out' }
                Assert-PfcTrue -Actual $timedOut -ScenarioId 'runner.channel.timeout' -Expected ('timed out; error=' + $timeoutError)
                Start-Sleep -Milliseconds 500
                $leftover = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'PFC_TIMEOUT_CHILD' })
                Assert-PfcEqual -Expected 0 -Actual $leftover.Count -ScenarioId 'runner.channel.tree-cleanup'
                Assert-PfcTrue -Actual (@(Get-ChildItem -LiteralPath (Join-Path $timeoutRoot '.pfc-eval-results') -Filter '*.stderr.txt' -ErrorAction SilentlyContinue).Count -gt 0) -ScenarioId 'runner.channel.stderr-evidence' -Expected 'sidecar'
            } finally {
                $leftover = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'PFC_TIMEOUT_CHILD' })
                foreach ($p in $leftover) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
                if (Test-Path -LiteralPath $timeoutRoot) { Remove-Item -LiteralPath $timeoutRoot -Recurse -Force }
            }
            $canaryLines = @(
                '{"type":"thread.started","thread_id":"SYNTHETIC-CANARY"}'
                '{"type":"turn.started"}'
                '{"type":"error","message":"synthetic error 1"}'
                '{"type":"error","message":"synthetic error 2"}'
                '{"type":"error","message":"synthetic error 3"}'
                '{"type":"error","message":"synthetic error 4"}'
                '{"type":"item.completed","item":{"type":"agent_message","text":"CANARY_OK"}}'
                '{"type":"turn.completed"}'
            )
            $canaryMetrics = Read-PfcCodexJsonlMetrics -Lines $canaryLines
            Assert-PfcTrue -Actual $canaryMetrics.thread_started -ScenarioId 'TEST-1.thread-started' -Expected 'true'
            Assert-PfcTrue -Actual $canaryMetrics.turn_started -ScenarioId 'TEST-1.turn-started' -Expected 'true'
            Assert-PfcEqual -Expected 'CANARY_OK' -Actual $canaryMetrics.last_completed_agent_message -ScenarioId 'TEST-2.last-agent-message'
            Assert-PfcTrue -Actual $canaryMetrics.turn_completed -ScenarioId 'TEST-3.turn-completed' -Expected 'true'
            Assert-PfcEqual -Expected 4 -Actual $canaryMetrics.error_events -ScenarioId 'TEST-4.error-events'
            Assert-PfcTrue -Actual ($null -ne $canaryMetrics.terminal_event_received_at_utc) -ScenarioId 'TEST-5.terminal-timestamp' -Expected 'timestamp'
            Assert-PfcTrue -Actual ($null -ne $canaryMetrics.last_jsonl_event_received_at_utc) -ScenarioId 'TEST-5.last-event-timestamp' -Expected 'timestamp'
            $recovered = Read-PfcCodexJsonlMetrics -Lines @('{"type":"turn.started"}','{"type":"error","message":"transient"}','{"type":"turn.completed"}')
            Assert-PfcEqual -Expected 'COMPLETED_WITH_RECOVERED_ERRORS' -Actual $recovered.turn_result -ScenarioId 'TEST-6.recovered-errors'
            $failed = Read-PfcCodexJsonlMetrics -Lines @('{"type":"turn.started"}','{"type":"turn.failed"}')
            Assert-PfcEqual -Expected 'FAILED' -Actual $failed.turn_result -ScenarioId 'TEST-7.turn-failed'
            Assert-PfcEqual -Expected 'CANARY_OK' -Actual $canaryMetrics.final_agent_message -ScenarioId 'TEST-8.agent-fallback'
            Assert-PfcEqual -Expected $canaryLines.Count -Actual $canaryMetrics.raw_lines -ScenarioId 'TEST-9.raw-line-count'
            $contentMessage = Read-PfcCodexJsonlMetrics -Lines @((@{type='item.completed'; item=@{type='agent_message'; content=@(@{type='output_text'; text='CONTENT_OK'})}} | ConvertTo-Json -Compress -Depth 6), '{"type":"turn.completed"}')
            Assert-PfcEqual -Expected 'CONTENT_OK' -Actual $contentMessage.last_completed_agent_message -ScenarioId 'TEST-9.content-agent-message'
            $frozenMessage = Read-PfcCodexJsonlMetrics -Lines @('{"type":"item.completed","item":{"type":"agent_message","text":"FIRST"}}','{"type":"turn.completed"}','{"type":"item.completed","item":{"type":"agent_message","text":"LATE"}}')
            Assert-PfcEqual -Expected 'FIRST' -Actual $frozenMessage.last_completed_agent_message -ScenarioId 'TEST-9.freeze-after-terminal'
        } }
    )
    foreach ($t in $tests) {
        try { & $t.Test; $results.Add((New-PfcResult -ScenarioId $t.Id -Status 'PASS' -Message 'verified')) }
        catch { $results.Add((New-PfcResult -ScenarioId $t.Id -Status 'FAIL' -Message $_.Exception.Message)) }
    }
    return $results
}

function Invoke-RunnerRevision3 {
    $test = Join-Path $PSScriptRoot 'tests\RunnerRevision3.Tests.ps1'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test 2>&1
    if ($LASTEXITCODE -ne 0) { return ,(New-PfcResult -ScenarioId 'RunnerRevision3' -Status 'FAIL' -Message (($output | Out-String).Trim())) }
    return ,(New-PfcResult -ScenarioId 'RunnerRevision3' -Status 'PASS' -Message (($output | Out-String).Trim()))
}

function Invoke-Bootstrap {
    $root = Split-Path -Parent $PSScriptRoot
    $required = @(
        'AGENTS.md',
        'README.md',
        'VERSION',
        'CHANGELOG.md',
        'docs/project-flight-control-design.md',
        'docs/superpowers/plans/2026-09-03-project-flight-control-v1-implementation-plan.md',
        'docs/superpowers/plans/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan.md',
        'docs/exec-plans/active/project-flight-control-v2-continuous-mode.md'
    )
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($relative in $required) {
        $path = Join-Path $root $relative
        try {
            Assert-PfcTrue -Actual (Test-Path -LiteralPath $path -PathType Leaf) -ScenarioId ("bootstrap.file.{0}" -f $relative) -Expected 'present'
            $results.Add((New-PfcResult -ScenarioId ("bootstrap.file.{0}" -f $relative) -Status 'PASS' -Message 'present'))
        } catch {
            $results.Add((New-PfcResult -ScenarioId ("bootstrap.file.{0}" -f $relative) -Status 'FAIL' -Message $_.Exception.Message))
        }
    }

    $designPath = Join-Path $root 'docs/project-flight-control-design.md'
    $expectedHash = 'fda8edc9b476e94f387ad553118a9d4982cfb11439d018d8595fecbfeeb259f6'
    try {
        Assert-PfcTrue -Actual (Test-Path -LiteralPath $designPath -PathType Leaf) -ScenarioId 'bootstrap.v2.spec-hash.file' -Expected 'present'
        $actualHash = (Get-FileHash -LiteralPath $designPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-PfcEqual -Expected $expectedHash -Actual $actualHash -ScenarioId 'bootstrap.v2.spec-hash'
        $results.Add((New-PfcResult -ScenarioId 'bootstrap.v2.spec-hash' -Status 'PASS' -Message $actualHash))
    } catch {
        $results.Add((New-PfcResult -ScenarioId 'bootstrap.v2.spec-hash' -Status 'FAIL' -Message $_.Exception.Message))
    }

    function Add-BootstrapV2Assertion([string]$ScenarioId, [scriptblock]$Assertion, [string]$Message) {
        try {
            & $Assertion
            $results.Add((New-PfcResult -ScenarioId $ScenarioId -Status 'PASS' -Message $Message))
        } catch {
            $results.Add((New-PfcResult -ScenarioId $ScenarioId -Status 'FAIL' -Message $_.Exception.Message))
        }
    }

    $design = if (Test-Path -LiteralPath $designPath -PathType Leaf) { Get-Content -Raw -LiteralPath $designPath } else { '' }
    $designHeader = if (Test-Path -LiteralPath $designPath -PathType Leaf) { (Get-Content -LiteralPath $designPath -TotalCount 12) -join "`n" } else { '' }
    Add-BootstrapV2Assertion 'bootstrap.v2.spec-version' {
        Assert-PfcTrue -Actual ($design -match '(?m)^- \*\*文档版本\*\*：`PFC-DESIGN-v2\.0-approved`$') -ScenarioId 'bootstrap.v2.spec-version' -Expected 'PFC-DESIGN-v2.0-approved'
    } 'approved design version'
    Add-BootstrapV2Assertion 'bootstrap.v2.spec-state' {
        Assert-PfcTrue -Actual ($designHeader -match 'APPROVED_FOR_IMPLEMENTATION') -ScenarioId 'bootstrap.v2.spec-state' -Expected 'APPROVED_FOR_IMPLEMENTATION'
    } 'approved design state'

    $versionPath = Join-Path $root 'VERSION'
    Add-BootstrapV2Assertion 'bootstrap.v2.version' {
        Assert-PfcEqual -Expected '0.2.0-dev.0' -Actual ((Get-Content -Raw -LiteralPath $versionPath).Trim()) -ScenarioId 'bootstrap.v2.version'
    } 'V2 development version'

    $ledgerPath = Join-Path $root 'docs/exec-plans/active/project-flight-control-v2-continuous-mode.md'
    $ledger = if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) { Get-Content -Raw -LiteralPath $ledgerPath } else { '' }
    foreach ($assertion in @(
        @{ Id = 'bootstrap.v2.historical-exclusion.path'; Pattern = '(?m)^- Path: `task-3-report\.md`$'; Expected = 'historical path' },
        @{ Id = 'bootstrap.v2.historical-exclusion.classification'; Pattern = '(?m)^- Classification: `HISTORICAL_EXCLUDED`$'; Expected = 'HISTORICAL_EXCLUDED classification' },
        @{ Id = 'bootstrap.v2.historical-exclusion.commit-action'; Pattern = '(?m)^- Commit action: `FORBIDDEN`$'; Expected = 'FORBIDDEN commit action' },
        @{ Id = 'bootstrap.v2.historical-exclusion.delete-action'; Pattern = '(?m)^- Delete action: `FORBIDDEN`$'; Expected = 'FORBIDDEN delete action' },
        @{ Id = 'bootstrap.v2.historical-exclusion.candidate-action'; Pattern = '(?m)^- Candidate action: `FORBIDDEN`$'; Expected = 'FORBIDDEN candidate action' }
    )) {
        $current = $assertion
        Add-BootstrapV2Assertion $current.Id {
            Assert-PfcTrue -Actual ($ledger -match $current.Pattern) -ScenarioId $current.Id -Expected $current.Expected
        } $current.Expected
    }
    return $results
}

function Invoke-StaticPackage {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    return Invoke-PfcStaticChecks -RepositoryRoot $root -Phase $Phase
}

function Invoke-ContinuousContracts {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    . (Join-Path $PSScriptRoot 'tests\ContinuousContracts.Tests.ps1')
    return Invoke-PfcContinuousContractTests -RepositoryRoot $root
}

function Invoke-ContinuousMode {
    Import-Module (Join-Path $PSScriptRoot 'lib\ContinuousMode.psm1') -Force
    . (Join-Path $PSScriptRoot 'tests\ContinuousMode.Tests.ps1')
    return Invoke-PfcContinuousModeTests -RepositoryRoot (Split-Path -Parent $PSScriptRoot)
}

function Invoke-ContinuousModeWindowsSmoke {
    $smokeResults=@(& (Join-Path $PSScriptRoot 'scenarios\continuous-mode\WindowsSmoke\scenario.ps1') -Phase $Phase -RepositoryRoot (Split-Path -Parent $PSScriptRoot))
    if (-not (Test-PfcContinuousSmokeResults -Results $smokeResults)) {
        $smokeResults+=New-PfcResult -ScenarioId 'windows.result-contract' -Status FAIL -Message 'Expected exactly eight unique smoke proofs with valid statuses.'
    }
    return $smokeResults
}

function Invoke-BuilderProfile {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    . (Join-Path $PSScriptRoot 'tests\BuilderProfile.Tests.ps1')
    return Invoke-PfcBuilderProfileTests -RepositoryRoot $root -Phase $Phase
}

function Invoke-VerifierProfile {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    . (Join-Path $PSScriptRoot 'tests\VerifierProfile.Tests.ps1')
    return Invoke-PfcVerifierProfileTests -RepositoryRoot $root -Phase $Phase
}

function Invoke-MessageContracts {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    return Invoke-PfcMessageContractChecks -RepositoryRoot $root -Phase $Phase
}

function Invoke-SpecialistProtocol {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    $results = New-Object System.Collections.Generic.List[object]
    function Check([string]$Id, [bool]$Passed, [string]$Message) {
        $results.Add((New-PfcResult -ScenarioId $Id -Status $(if ($Passed) { 'PASS' } else { 'FAIL' }) -Message $Message))
    }
    $protocolPath = Join-Path $root.FullName 'skill\project-flight-control\references\specialist-protocol.md'
    $schemaPath = Join-Path $root.FullName 'evals\schemas\specialist-report.schema.json'
    $protocol = if (Test-Path -LiteralPath $protocolPath -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $protocolPath } else { '' }
    Check 'specialist.protocol.present' (Test-Path -LiteralPath $protocolPath -PathType Leaf) 'protocol present'
    Check 'specialist.schema.present' (Test-Path -LiteralPath $schemaPath -PathType Leaf) 'schema present'
    foreach ($term in @('Goalkeeper-only','SPECIALIST_REQUEST','advisory','SPECIALIST_ORDER','only authorized input','one active Specialist','one question','one evidence expansion','no nested agents','fixed Evidence SHA','narrow Context Packet','independent.*disposable worktree','static-first','minimum diagnostic command','synchronous pause','FINDING','EVIDENCE_NEEDED','UNRESOLVED','no formal state-machine verdict','Evidence.*Guidance.*applicability','necessary-prerequisite')) {
        Check ('specialist.protocol.' + ($term -replace '[^A-Za-z0-9]+','-').Trim('-')) ($protocol -match ('(?is)' + $term)) ('required rule: ' + $term)
    }
    try {
        $schema = Get-Content -Raw -Encoding UTF8 -LiteralPath $schemaPath | ConvertFrom-Json
        Check 'specialist.schema.strict-root' ($schema.type -ceq 'object' -and [string]$schema.additionalProperties -ceq 'False') 'strict root schema'
        Check 'specialist.schema.states' ((@($schema.oneOf)).Count -eq 3 -and (@($schema.oneOf | ForEach-Object { $_.properties.status.enum[0] }) | Sort-Object) -join '|' -ceq 'EVIDENCE_NEEDED|FINDING|UNRESOLVED') 'exact report states'
        Check 'specialist.schema.sha' ($schema.properties.evidence_sha.pattern -ceq '^[0-9a-f]{40}$') 'fixed Evidence SHA pattern'
        Check 'specialist.schema.no-formal-verdict' ((@($schema.oneOf | ForEach-Object { $_.properties.status.enum }) -notcontains 'ACCEPT') -and (@($schema.oneOf | ForEach-Object { $_.properties.status.enum }) -notcontains 'REWORK') -and (@($schema.oneOf | ForEach-Object { $_.properties.status.enum }) -notcontains 'BLOCKED')) 'formal verdict states absent'
    } catch { Check 'specialist.schema.parse' $false $_.Exception.Message }
    function Test-ClosedFields($Object, [string[]]$Required, [string[]]$Allowed) {
        foreach ($field in $Required) { if (-not $Object.PSObject.Properties.Name.Contains($field)) { return $false } }
        foreach ($field in $Object.PSObject.Properties.Name) { if ($Allowed -notcontains $field) { return $false } }
        return $true
    }
    $requestFields = @('request_id','requester','question','why_specialist_is_required','decision_affected','evidence_sha','relevant_acceptance_criteria','relevant_scope','known_evidence')
    $request = [pscustomobject]@{ request_id='RQ'; requester='Builder'; question='q'; why_specialist_is_required='r'; decision_affected='d'; evidence_sha=('a'*40); relevant_acceptance_criteria='a'; relevant_scope='s'; known_evidence='e' }
    Check 'specialist.request.fields' (Test-ClosedFields $request $requestFields $requestFields -and $request.evidence_sha -match '^[0-9a-f]{40}$') 'request fields are closed and SHA-bound'
    $orderFields = @('specialist_order_id','request_id','specialist_perspective','question','decision_affected','evidence_sha','allowed_files_symbols_evidence','known_evidence','allowed_diagnostic_action','evidence_round','required_output')
    $order = [pscustomobject]@{ specialist_order_id='O'; request_id='RQ'; specialist_perspective='p'; question='q'; decision_affected='d'; evidence_sha=('a'*40); allowed_files_symbols_evidence='x'; known_evidence='e'; allowed_diagnostic_action='NONE'; evidence_round=0; required_output='FINDING/EVIDENCE_NEEDED/UNRESOLVED' }
    Check 'specialist.order.fields' (Test-ClosedFields $order $orderFields $orderFields -and $order.evidence_round -in @(0,1) -and $order.evidence_sha -match '^[0-9a-f]{40}$') 'order fields, round and SHA are bound'
    foreach ($mutation in @(
        @{Id='request-unknown-field'; Mutate={ param($x) $x | Add-Member -NotePropertyName extra -NotePropertyValue x }},
        @{Id='order-round-two'; Mutate={ param($x) $x.evidence_round=2 }},
        @{Id='order-multiple-diagnostics'; Mutate={ param($x) $x.allowed_diagnostic_action='cmd1; cmd2' }},
        @{Id='order-missing-scope'; Mutate={ param($x) $x.PSObject.Properties.Remove('allowed_files_symbols_evidence') }}
    )) {
        $copy = [pscustomobject]@{}; foreach ($p in $order.PSObject.Properties) { $copy | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
        & $mutation.Mutate $copy
        $accepted = Test-ClosedFields $copy $orderFields $orderFields
        $accepted = $accepted -and ($copy.evidence_round -in @(0,1)) -and ($copy.allowed_diagnostic_action -notmatch ';')
        Check ('specialist.real-checker.negative.' + $mutation.Id) (-not $accepted) 'mutated request/order rejected'
    }
    # Real checker: validate state-specific required fields and reject authority states/extra fields.
    function Test-ReportShape($Report) {
        $common = @('control_run_id','lease_epoch','goal_id','goal_version','milestone_id','milestone_contract_version','revision','sender_role','recipient_role','created_at','status','specialist_report_id','specialist_order_id','evidence_sha')
        foreach ($f in $common) { if (-not $Report.PSObject.Properties.Name.Contains($f)) { return $false } }
        if ($Report.status -notin @('FINDING','EVIDENCE_NEEDED','UNRESOLVED') -or $Report.evidence_sha -notmatch '^[0-9a-f]{40}$' -or $Report.sender_role -ne 'Specialist' -or $Report.recipient_role -ne 'Goalkeeper') { return $false }
        $required = switch ($Report.status) {
            'FINDING' { @('question','finding','evidence','risk','recommendation','confidence','diagnostics_run') }
            'EVIDENCE_NEEDED' { @('missing_evidence','why_required','requested_scope','requested_diagnostic','risk') }
            'UNRESOLVED' { @('known','unknown','evidence_reviewed','why_unresolved','decision_risk','recommended_next_action') }
        }
        foreach ($f in $required) { if (-not $Report.PSObject.Properties.Name.Contains($f)) { return $false } }
        $allowed = @($common + $required | Sort-Object -Unique)
        foreach ($p in $Report.PSObject.Properties.Name) { if ($allowed -notcontains $p) { return $false } }
        return $true
    }
    $valid = [pscustomobject]@{ control_run_id='C'; lease_epoch='1'; goal_id='G'; goal_version='1'; milestone_id='M'; milestone_contract_version='1'; revision='0'; sender_role='Specialist'; recipient_role='Goalkeeper'; created_at='now'; status='FINDING'; specialist_report_id='R'; specialist_order_id='O'; evidence_sha=('a'*40); question='q'; finding='f'; evidence='e'; risk='r'; recommendation='n'; confidence='HIGH'; diagnostics_run='none' }
    Check 'specialist.real-checker.valid' (Test-ReportShape $valid) 'valid FINDING accepted'
    foreach ($mutation in @(
        @{Id='status-authority'; Mutate={ param($x) $x.status='ACCEPT' }},
        @{Id='missing-state-field'; Mutate={ param($x) $x.PSObject.Properties.Remove('finding') }},
        @{Id='extra-verdict'; Mutate={ param($x) $x | Add-Member -NotePropertyName verdict -NotePropertyValue 'PASS' }},
        @{Id='wrong-sha'; Mutate={ param($x) $x.evidence_sha='not-a-sha' }}
    )) {
        $copy = [pscustomobject]@{}; foreach ($p in $valid.PSObject.Properties) { $copy | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
        & $mutation.Mutate $copy
        $accepted = Test-ReportShape $copy
        if ($mutation.Id -eq 'wrong-sha') { $accepted = $accepted -and ($copy.evidence_sha -match '^[0-9a-f]{40}$') }
        Check ('specialist.real-checker.negative.' + $mutation.Id) (-not $accepted) 'mutated report rejected'
    }
    return $results.ToArray()
}

function Invoke-GovernanceReferences {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    $results = New-Object System.Collections.Generic.List[object]
    $cases = @(
        @{ Id = 'goalkeeper-business-code'; File = 'roles-and-authority.md'; Text = 'Goalkeeper may edit business code.' },
        @{ Id = 'builder-control-files'; File = 'roles-and-authority.md'; Text = 'Builder may change control files and contracts.' },
        @{ Id = 'verifier-candidate-mutation'; File = 'roles-and-authority.md'; Text = 'Verifier may modify Candidate.' },
        @{ Id = 'verifier-commit'; File = 'roles-and-authority.md'; Text = 'Verifier may commit.' },
        @{ Id = 'builder-self-acceptance'; File = 'roles-and-authority.md'; Text = 'Builder may self-accept.' },
        @{ Id = 'verifier-goal-acceptance'; File = 'roles-and-authority.md'; Text = 'Verifier may declare Goal accepted.' },
        @{ Id = 'verifier-main-thread-fallback'; File = 'orchestration-protocol.md'; Text = 'Fallback to the main thread when Verifier is unavailable.' },
        @{ Id = 'implicit-small-task-downgrade'; File = 'modes-and-state-machine.md'; Text = 'Implicit mode downgrade for small tasks is allowed.' },
        @{ Id = 'unaccepted-candidate-inheritance'; File = 'modes-and-state-machine.md'; Text = 'An unaccepted Candidate may become the next milestone base.' },
        @{ Id = 'continuous-unavailable-omission'; File = 'orchestration-protocol.md'; Remove = 'and any acceptance-necessary Specialist is neither `UNRESOLVED` nor `UNAVAILABLE`.' },
        @{ Id = 'specialist-handoff-omission'; File = 'git-and-worktrees.md'; Remove = 'When Builder needs specialist input' }
    )
    foreach ($case in $cases) {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-governance-' + [guid]::NewGuid().ToString('N'))
        try {
            $refRoot = Join-Path $fixture 'skill\project-flight-control\references'
            New-Item -ItemType Directory -Path $refRoot -Force | Out-Null
            foreach ($name in @('roles-and-authority.md','modes-and-state-machine.md','orchestration-protocol.md','git-and-worktrees.md')) {
                Copy-Item -LiteralPath (Join-Path $root.FullName ('skill\project-flight-control\references\' + $name)) -Destination (Join-Path $refRoot $name)
            }
            $casePath = Join-Path $refRoot $case.File
            if ($case.ContainsKey('Remove')) {
                $body = Get-Content -Raw -Encoding UTF8 -LiteralPath $casePath
                Set-Content -LiteralPath $casePath -Value ($body.Replace($case.Remove, '')) -Encoding UTF8
            } else { Add-Content -LiteralPath $casePath -Value $case.Text -Encoding UTF8 }
            $check = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED | Where-Object { $_.ScenarioId -eq 'package.governance.references' })
            Assert-PfcEqual -Expected 'FAIL' -Actual $check.Status -ScenarioId ('governance.reject.' + $case.Id)
            $results.Add((New-PfcResult -ScenarioId ('governance.reject.' + $case.Id) -Status 'PASS' -Message 'contradictory authority fixture rejected'))
        } catch {
            $results.Add((New-PfcResult -ScenarioId ('governance.reject.' + $case.Id) -Status 'FAIL' -Message $_.Exception.Message))
        } finally {
            if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
        }
    }
    $valid = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item -LiteralPath $root.FullName) -Phase GREEN | Where-Object { $_.ScenarioId -eq 'package.governance.references' })
    $validStatus = if ($valid.Status -eq 'PASS') { 'PASS' } else { 'FAIL' }
    $results.Add((New-PfcResult -ScenarioId 'governance.references.valid' -Status $validStatus -Message $valid.Message))
    return $results
}

function Invoke-EvidenceRecovery {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    $results = New-Object System.Collections.Generic.List[object]
    function Check([string]$Id, [bool]$Passed, [string]$Message) {
        $results.Add((New-PfcResult -ScenarioId $Id -Status $(if ($Passed) { 'PASS' } else { 'FAIL' }) -Message $Message))
    }
    $evidencePath = Join-Path $root.FullName 'skill\project-flight-control\references\evidence-and-recovery.md'
    $windowsPath = Join-Path $root.FullName 'skill\project-flight-control\references\windows-runtime.md'
    $evidence = if (Test-Path -LiteralPath $evidencePath -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $evidencePath } else { '' }
    $windows = if (Test-Path -LiteralPath $windowsPath -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $windowsPath } else { '' }
    Check 'evidence.reference.present' (Test-Path -LiteralPath $evidencePath -PathType Leaf) 'evidence-and-recovery.md present'
    Check 'recovery.reference.present' (Test-Path -LiteralPath $windowsPath -PathType Leaf) 'windows-runtime.md present'
    $evidenceTerms = @(
        'Git.*canonical project sources.*STATUS', 'Thread ID.*not.*recovery', 'compact Evidence Record',
        'Evidence ID', 'Candidate SHA', 'Source', 'Working Directory', 'Environment', 'Created At', 'Candidate Timing', 'Exit Code', 'Observed Result', 'Covered Criteria',
        'attachment', 'failure', 'BLOCKER|MAJOR', 'redact|脱敏', 'Candidate.*change.*invalid',
        'CONVERGENCE_SNAPSHOT', 'latest.*STATUS', 'historical.*BUILD_REPORT|REVIEW_REPORT',
        'ACTIVE.*no Candidate', 'Candidate.*no.*Review', 'REPAIR', 'Review PASS',
        'Specialist ACTIVE|EVIDENCE_NEEDED', 'ACCEPTED', 'Control Run ID', 'Lease Epoch',
        'STALE_REPORT_REJECTED', 'same.*Specialist Order|同一.*Specialist Order', '200 relevant lines', '64 KiB', 'BEFORE_CANDIDATE', 'ON_CANDIDATE'
    )
    foreach ($term in $evidenceTerms) { Check ('evidence.term.' + ($term -replace '[^A-Za-z0-9]+','-').Trim('-')) ($evidence -match ('(?is)' + $term)) ('required evidence/recovery rule: ' + $term) }
    $windowsTerms = @('Windows PowerShell 5\.1', 'powershell\.exe', 'pwsh\.exe', 'Git for Windows', 'path normalization', 'detached HEAD', 'sandbox', 'protected.*\.git', 'UTF-8', 'BOM', 'hard-coded drive')
    foreach ($term in $windowsTerms) { Check ('windows.term.' + ($term -replace '[^A-Za-z0-9]+','-').Trim('-')) ($windows -match ('(?is)' + $term)) ('required Windows runtime rule: ' + $term) }
    $status = Get-Content -Raw -Encoding UTF8 (Join-Path $root.FullName 'skill\project-flight-control\assets\templates\status.md')
    $build = Get-Content -Raw -Encoding UTF8 (Join-Path $root.FullName 'skill\project-flight-control\assets\templates\build-report.md')
    $review = Get-Content -Raw -Encoding UTF8 (Join-Path $root.FullName 'skill\project-flight-control\assets\templates\review-report.md')
    Check 'status.convergence.latest-only' (($status -match '(?i)Convergence Snapshot') -and ($status -match '(?i)latest') -and ($status -match '(?i)historical|history')) 'STATUS declares latest snapshot and historical reports'
    Check 'build.convergence.history' (($build -match '(?i)Convergence Inputs') -and ($build -match '(?i)Failure Signature|New Evidence Since Previous Revision')) 'BUILD_REPORT carries convergence history inputs'
    Check 'review.evidence.integrity' (($review -match '(?i)Evidence Integrity Result') -and ($review -match '(?i)Candidate SHA')) 'REVIEW_REPORT binds evidence integrity to Candidate SHA'
    Check 'evidence.redaction.no-secrets' (($evidence -notmatch '(?i)persist.*(?:token|cookie|password|secret)') -or ($evidence -match '(?i)redact|脱敏')) 'evidence rules require redaction'
    $rules = Test-PfcEvidenceRecoveryRules -Text $evidence
    Check 'evidence.actual-checker' $rules.Passed ('actual checker missing=' + (($rules.Missing) -join ', '))
    $staleRemoved = Test-PfcEvidenceRecoveryRules -Text ($evidence.Replace('STALE_REPORT_REJECTED', ''))
    Check 'evidence.negative.old-report-rejection' (-not $staleRemoved.Passed) 'removing stale-report rule fails the checker'
    $attachmentRemoved = Test-PfcEvidenceRecoveryRules -Text ($evidence -replace '(?i)attachments?', '')
    Check 'evidence.negative.attachment-gate' (-not $attachmentRemoved.Passed) 'mutating attachment rule fails the checker'
    foreach ($field in @('Source','Working Directory','Environment','Created At','Candidate Timing')) {
        $mutated = Test-PfcEvidenceRecoveryRules -Text ([regex]::Replace($evidence, '(?im)^\s*' + [regex]::Escape($field) + ':.*(?:\r?\n|$)', ''))
        Check ('evidence.negative.compact-field-' + ($field -replace '[^A-Za-z0-9]+','-').Trim('-')) (-not $mutated.Passed) ('removing ' + $field + ' fails the checker')
    }
    $timingRemoved = Test-PfcEvidenceRecoveryRules -Text ($evidence -replace '(?im)^\s*Candidate Timing:.*(?:\r?\n|$)', '')
    Check 'evidence.negative.candidate-timing' (-not $timingRemoved.Passed) 'removing Candidate Timing fails the checker'
    $acceptedRemoved = Test-PfcEvidenceRecoveryRules -Text ([regex]::Replace($evidence, '(?im)^\s*\* `ACCEPTED`.*(?:\r?\n|$)', ''))
    Check 'evidence.negative.accepted-recovery' (-not $acceptedRemoved.Passed) 'removing ACCEPTED recovery action fails the checker'
    $boundRemoved = Test-PfcEvidenceRecoveryRules -Text ($evidence -replace '(?i)no more than 200 relevant lines and 64 KiB', '')
    Check 'evidence.negative.attachment-bound' (-not $boundRemoved.Passed) 'removing finite attachment bound fails the checker'
    return $results.ToArray()
}

function Test-PfcSkillEntryCompactness {
    param([string]$Text)
    $headings = @($Text -split "`r?`n" | Where-Object { $_ -match '^#{1,3}\s+' })
    $bullets = @($Text -split "`r?`n" | Where-Object { $_ -match '^\s*[-*]\s+' })
    $literalDuplication = ($Text -match '(?i)full Builder efficiency checklist|debugging algorithm|Specialist field catalog|EFF-0[1-7]|Reuse Before Create|Minimal Diff|Hypothesis A|Root Cause Analysis')
    return (-not $literalDuplication) -and ($Text.Length -le 6000) -and ($headings.Count -le 10) -and ($bullets.Count -le 18)
}

function Invoke-SkillEntry {
    $root = Split-Path -Parent $PSScriptRoot
    $skillPath = Join-Path $root 'skill\project-flight-control\SKILL.md'
    $yamlPath = Join-Path $root 'skill\project-flight-control\agents\openai.yaml'
    $results = New-Object System.Collections.Generic.List[object]
    function Check([string]$Id, [bool]$Passed, [string]$Message) {
        $status = 'FAIL'; if ($Passed) { $status = 'PASS' }
        $results.Add((New-PfcResult -ScenarioId $Id -Status $status -Message $Message))
    }
    $skill = if (Test-Path -LiteralPath $skillPath -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $skillPath } else { '' }
    $yaml = if (Test-Path -LiteralPath $yamlPath -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $yamlPath } else { '' }
    Check 'skill.entry.path' (Test-Path -LiteralPath $skillPath -PathType Leaf) 'SKILL.md present'
    Check 'skill.entry.frontmatter' ($skill -match '(?ms)^---\s*\nname:\s*project-flight-control\s*\ndescription:\s*[^\r\n]+\s*\n---') 'frontmatter name and description'
    Check 'skill.entry.policy' (($yaml -match '(?im)allow_implicit_invocation:\s*false') -and ($yaml -match '(?im)display_name:') -and ($yaml -match '(?im)default_prompt:')) 'explicit invocation policy'
    Check 'skill.entry.modes' ($skill -match '(?s)START.*RESUME.*AUDIT.*STATUS_ONLY') 'top-level modes'
    Check 'skill.entry.preflight' (($skill -match 'SUBAGENT_PREFLIGHT') -and ($skill -match '(?i)no-role-simulation|role simulation')) 'subagent preflight gate'
    $refs = @('roles-and-authority.md','modes-and-state-machine.md','orchestration-protocol.md','git-and-worktrees.md','message-contracts.md')
    $routes = @('project-flight-builder.toml','project-flight-verifier.toml','builder-debugging.md','evidence-and-recovery.md','specialist-protocol.md','windows-runtime.md')
    $allRefs = (@($refs + $routes | Where-Object { $skill -notmatch [regex]::Escape($_) }).Count -eq 0)
    Check 'skill.entry.authority-references' $allRefs 'all authority references'
    Check 'skill.entry.receipt' ($skill -match '(?i)Project Control Report' -and $skill -match '(?i)final') 'fixed final receipt route'
    Check 'skill.entry.compact' (Test-PfcSkillEntryCompactness -Text $skill) 'bounded structural compactness contract'
    $negativeVariants = @(
        ($skill + "`n## Extra operating rules`n" + (1..20 | ForEach-Object { "- Rule ${_}: inspect the baseline, record evidence, and repeat the verification checkpoint." } | Out-String)),
        ($skill + "`n## Detailed procedure`n" + (1..20 | ForEach-Object { "- Step ${_}: preserve the handoff, compare the candidate, and document the result." } | Out-String))
    )
    $negativePass = $true
    foreach ($variant in $negativeVariants) {
        if (Test-PfcSkillEntryCompactness -Text $variant) { $negativePass = $false }
    }
    Check 'skill.entry.compact-negative' $negativePass 'representative paraphrased rule blocks rejected'
    if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
        Import-Module (Join-Path $PSScriptRoot 'lib\PromptBudget.psm1') -Force
        $budget = Measure-PfcPromptBudget -Path ([IO.FileInfo]$skillPath) -Budget 1500
        Check 'skill.entry.prompt-budget' ($budget.status -eq 'PASS') ('estimate=' + $budget.conservative_estimated_tokens + '; budget=' + $budget.budget)
        $over = Measure-PfcPromptBudget -Path ([IO.FileInfo]$skillPath) -Budget 1
        $metadataPass = ($over.status -eq 'FAIL') -and ($over.estimate_basis -eq 'utf8_bytes_divided_by_4') -and ($over.token_data_status -eq 'NOT_AVAILABLE') -and ($over.warning -match '(?i)estimate') -and ($over.warning -match '(?i)no savings')
        Check 'skill.entry.prompt-budget-negative' $metadataPass ('over-budget status=' + $over.status + '; basis=' + $over.estimate_basis + '; token_data=' + $over.token_data_status)
    } else { Check 'skill.entry.prompt-budget' $false 'SKILL.md missing for budget estimate'; Check 'skill.entry.prompt-budget-negative' $false 'SKILL.md missing for budget estimate' }
    return $results.ToArray()
}

function Invoke-Harness {
    $results = New-Object System.Collections.Generic.List[object]
    $checks = @(
        @{ Id = 'harness.assertions'; Test = { Assert-PfcTrue -Actual $true -ScenarioId 'harness.assertions.true' -Expected 'True'; Assert-PfcEqual -Expected 'x' -Actual 'x' -ScenarioId 'harness.assertions.equal'; $thrown = $false; try { Assert-PfcTrue -Actual $false -ScenarioId 'harness.assertions.failure' -Expected 'True' } catch { $thrown = $true; Assert-PfcTrue -Actual ($_.Exception.Message -match 'harness.assertions.failure') -ScenarioId 'harness.assertions.failure.message' -Expected 'True' }; Assert-PfcTrue -Actual $thrown -ScenarioId 'harness.assertions.failure.thrown' -Expected 'True' } },
        @{ Id = 'harness.json-output'; Test = { $json = @(New-PfcResult -ScenarioId 'harness.json' -Status 'PASS' -Message 'ok') | ConvertTo-Json -Compress; $obj = $json | ConvertFrom-Json; Assert-PfcEqual -Expected 'PASS' -Actual $obj.Status -ScenarioId 'harness.json-output' } },
        @{ Id = 'harness.parser'; Test = { $tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseInput('$x = 1', [ref]$tokens, [ref]$errors) | Out-Null; Assert-PfcEqual -Expected 0 -Actual @($errors).Count -ScenarioId 'harness.parser' } },
        @{ Id = 'harness.ordering'; Test = { $ids = @('b','a','c') | Sort-Object; Assert-PfcEqual -Expected 'a' -Actual $ids[0] -ScenarioId 'harness.ordering' } },
        @{ Id = 'harness.static-role-lock'; Test = {
                $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-role-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path (Join-Path $fixture 'codex-agents') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $fixture 'codex-agents\alpha.toml') -Value "name = 'Alpha'`ndescription = 'x'`nmodel = 'x'"
                Set-Content -LiteralPath (Join-Path $fixture 'codex-agents\beta.toml') -Value "name = 'Beta'`ndescription = 'x'`nmodel = 'x'"
                try { $r = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED | Where-Object { $_.ScenarioId -eq 'package.custom_agent.fields' }); Assert-PfcEqual -Expected 'FAIL' -Actual $r.Status -ScenarioId 'harness.static-role-lock' } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
            } },
        @{ Id = 'harness.frontmatter-boundary'; Test = {
                $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-front-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path (Join-Path $fixture 'skill\project-flight-control') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $fixture 'skill\project-flight-control\SKILL.md') -Value "---`nname: x`ndescription: y`n# no closing delimiter"
                try { $r = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED | Where-Object { $_.ScenarioId -eq 'package.skill.frontmatter' }); Assert-PfcEqual -Expected 'FAIL' -Actual $r.Status -ScenarioId 'harness.frontmatter-boundary' } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
            } },
        @{ Id = 'harness.frontmatter-invalid-duplicate'; Test = {
                $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-frontbad-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path (Join-Path $fixture 'skill\project-flight-control') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $fixture 'skill\project-flight-control\SKILL.md') -Value "---`nname: x`nname: y`ndescription: valid`n---`nbody"
                try { $r = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED | Where-Object { $_.ScenarioId -eq 'package.skill.frontmatter' }); Assert-PfcEqual -Expected 'FAIL' -Actual $r.Status -ScenarioId 'harness.frontmatter-invalid-duplicate' } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
            } },
        @{ Id = 'harness.version-consistency'; Test = {
                $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-version-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $fixture -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $fixture 'VERSION') -Value '1.2.3'; Set-Content -LiteralPath (Join-Path $fixture 'SKILL.md') -Value "---`nname: x`ndescription: y`nversion: 1.2.3`n---"; Set-Content -LiteralPath (Join-Path $fixture 'manifest.json') -Value '{"version":"9.9.9"}'
                try { $r = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED | Where-Object { $_.ScenarioId -eq 'package.version.consistent' }); Assert-PfcEqual -Expected 'FAIL' -Actual $r.Status -ScenarioId 'harness.version-consistency' } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
            } },
        @{ Id = 'harness.version-nested'; Test = {
                $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pfc-versionnested-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $fixture -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $fixture 'VERSION') -Value '1.2.3'; Set-Content -LiteralPath (Join-Path $fixture 'manifest.yaml') -Value "metadata:`n  version: 9.9.9"
                try { $r = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED | Where-Object { $_.ScenarioId -eq 'package.version.consistent' }); Assert-PfcEqual -Expected 'FAIL' -Actual $r.Status -ScenarioId 'harness.version-nested' } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
            } }
    )
    foreach ($check in $checks) {
        try { & $check.Test; $results.Add((New-PfcResult -ScenarioId $check.Id -Status 'PASS' -Message 'verified')) }
        catch { $results.Add((New-PfcResult -ScenarioId $check.Id -Status 'FAIL' -Message $_.Exception.Message)) }
    }
    # One script and result per form: no rejected command can mask another bypass.
    $safetyCases = @(
        @{ Id = 'git.force-after-remote'; Text = 'git push origin --force-with-lease'; Expected = 'FAIL' },
        @{ Id = 'git.force-before-remote'; Text = 'git push -f origin'; Expected = 'FAIL' },
        @{ Id = 'git.force-single-quoted'; Text = "git push '--force'"; Expected = 'FAIL' },
        @{ Id = 'git.force-double-quoted'; Text = 'git push "--force"'; Expected = 'FAIL' },
        @{ Id = 'git.lease-quoted-assignment'; Text = 'git push "--force-with-lease=refs/heads/main"'; Expected = 'FAIL' },
        @{ Id = 'git.lease-assignment'; Text = 'git push --force-with-lease=refs/heads/main'; Expected = 'FAIL' },
        @{ Id = 'git.subexpression'; Text = '$(git push --force)'; Expected = 'FAIL' },
        @{ Id = 'git.parenthesized'; Text = '(git push --force)'; Expected = 'FAIL' },
        @{ Id = 'git.interpolated-subexpression'; Text = 'Write-Host "$(git push --force)"'; Expected = 'FAIL' },
        @{ Id = 'git.statement-separator'; Text = 'Write-Host x; git push --force'; Expected = 'FAIL' },
        @{ Id = 'git.control-block'; Text = 'if ($true) { git push --force }'; Expected = 'FAIL' },
        @{ Id = 'git.executable-suffix'; Text = 'git.exe push -f origin'; Expected = 'FAIL' },
        @{ Id = 'git.no-pager'; Text = 'git --no-pager push origin --force-with-lease'; Expected = 'FAIL' },
        @{ Id = 'git.semicolon-terminator'; Text = 'git push --force;'; Expected = 'FAIL' },
        @{ Id = 'git.brace-terminator'; Text = 'if ($true) {git push --force}'; Expected = 'FAIL' },
        @{ Id = 'git.pipeline'; Text = 'git push --force | Out-Null'; Expected = 'FAIL' },
        @{ Id = 'git.call-operator'; Text = '& "git.exe" push "--force"'; Expected = 'FAIL' },
        @{ Id = 'git.line-continuation'; Text = "git push ```n--force"; Expected = 'FAIL' },
        @{ Id = 'git.clean-force-directory'; Text = 'git clean -f -d'; Expected = 'FAIL' },
        @{ Id = 'git.clean-directory-force'; Text = 'git clean -d -f'; Expected = 'FAIL' },
        @{ Id = 'git.clean-long-force'; Text = 'git clean --force -d'; Expected = 'FAIL' },
        @{ Id = 'git.clean-combined'; Text = 'git clean -dfx'; Expected = 'FAIL' },
        @{ Id = 'git.clean-quoted'; Text = 'git clean "-fd"'; Expected = 'FAIL' },
        @{ Id = 'git.reset-hard'; Text = 'git reset --hard'; Expected = 'FAIL' },
        @{ Id = 'git.reset-quoted'; Text = 'git reset "--hard"'; Expected = 'FAIL' },
        @{ Id = 'git.merge'; Text = 'git merge feature'; Expected = 'FAIL' },
        @{ Id = 'git.rebase'; Text = 'git rebase main'; Expected = 'FAIL' },
        @{ Id = 'git.single-quoted-text'; Text = "Write-Host 'git push --force'"; Expected = 'PASS' },
        @{ Id = 'git.double-quoted-text'; Text = 'Write-Host "git push --force"'; Expected = 'PASS' },
        @{ Id = 'git.escaped-quoted-text'; Text = 'Write-Host "Say `"git push --force`""'; Expected = 'PASS' },
        @{ Id = 'git.line-comment'; Text = '# git push --force'; Expected = 'PASS' },
        @{ Id = 'git.trailing-comment'; Text = 'Write-Host x # git push --force'; Expected = 'PASS' },
        @{ Id = 'git.block-comment'; Text = "<#`ngit push --force`n#>"; Expected = 'PASS' },
        @{ Id = 'git.inline-block-comment'; Text = '<# comment #> git push --force'; Expected = 'FAIL' },
        @{ Id = 'git.literal-here-string'; Text = "@'`ngit push --force`n'@"; Expected = 'PASS' },
        @{ Id = 'git.safe-status'; Text = 'git status --short'; Expected = 'PASS' },
        @{ Id = 'deploy.automatic'; Text = 'deploy --auto'; Expected = 'FAIL' },
        @{ Id = 'deploy.script'; Text = '.\deploy.ps1 -Automatic'; Expected = 'FAIL' },
        @{ Id = 'deploy.cmdlet'; Text = 'Invoke-Deploy -Automatic'; Expected = 'FAIL' },
        @{ Id = 'deploy.npm-script'; Text = 'npm run deploy'; Expected = 'FAIL' },
        @{ Id = 'deploy.quoted-npm-script'; Text = 'npm run "deploy"'; Expected = 'FAIL' },
        @{ Id = 'deploy.quoted-text'; Text = 'Write-Host "deploy --auto"'; Expected = 'PASS' },
        @{ Id = 'deploy.comment'; Text = "<#`ndeploy --auto`n#>"; Expected = 'PASS' }
    )
    foreach ($case in $safetyCases) {
        $id = 'harness.safety.' + $case.Id
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        $fixture = Join-Path $tempRoot ('pfc-safety-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $fixture 'scripts\case.ps1') -Value $case.Text
            $r = @(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item $fixture) -Phase RED)
            $parse = @($r | Where-Object { $_.ScenarioId -eq 'package.powershell.parseable' })
            Assert-PfcEqual -Expected 'PASS' -Actual $parse.Status -ScenarioId ($id + '.parse')
            $safety = @($r | Where-Object { $_.ScenarioId -eq 'package.git.safe' })
            Assert-PfcEqual -Expected $case.Expected -Actual $safety.Status -ScenarioId $id
            $results.Add((New-PfcResult -ScenarioId $id -Status 'PASS' -Message 'verified'))
        } catch {
            $results.Add((New-PfcResult -ScenarioId $id -Status 'FAIL' -Message $_.Exception.Message))
        } finally {
            $resolvedFixture = (Resolve-Path -LiteralPath $fixture).Path
            if ((Split-Path -Parent $resolvedFixture) -cne $tempRoot -or (Split-Path -Leaf $resolvedFixture) -notmatch '^pfc-safety-[a-f0-9]{32}$') {
                throw 'Safety fixture cleanup path is outside the expected temporary directory.'
            }
            Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
        }
    }
    . (Join-Path $PSScriptRoot 'tests\StaticPackageSource.Tests.ps1')
    foreach ($result in @(Invoke-PfcStaticPackageSourceTests -RepositoryRoot (Split-Path -Parent $PSScriptRoot))) { $results.Add($result) }
    return $results
}

function Get-CmHash {
    param([string]$Text, [string]$Path)
    if ($Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-CmProperties {
    param($Value, [string[]]$Names)
    if ($null -eq $Value -or $Value -is [array] -or $Value -is [string] -or $Value -is [ValueType]) { throw 'Expected an object.' }
    $actual = @($Value.PSObject.Properties.Name)
    if ($actual.Count -ne $Names.Count -or @(Compare-Object ($Names | Sort-Object) ($actual | Sort-Object) -CaseSensitive).Count) { throw 'Unexpected or missing contract fields.' }
}

function Read-CmAuthorization {
    param([string]$Path)
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){throw 'Authorization must be UTF-8 without BOM.'}
    $text=(New-Object Text.UTF8Encoding($false,$true)).GetString($bytes)
    $value=$text|ConvertFrom-Json
    # ConvertFrom-Json accepts repeated identical keys on Windows PowerShell.
    # Track JSON object scopes so nested authorization bindings are strict too.
    $tokens=[regex]::Matches($text,'"(?:\\.|[^"\\])*"|[{}\[\]:,]')
    $stack=New-Object 'System.Collections.Generic.Stack[object]'
    for($i=0;$i -lt $tokens.Count;$i++) {
        $token=$tokens[$i].Value
        if($token -eq '{') { $stack.Push((New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase))) }
        elseif($token -eq '}') { $null=$stack.Pop() }
        elseif($token.StartsWith('"') -and $i+1 -lt $tokens.Count -and $tokens[$i+1].Value -eq ':') {
            $key=ConvertFrom-Json -InputObject ('['+$token+']')
            if(-not $stack.Peek().Add([string]$key)){throw 'Duplicate authorization JSON property.'}
        }
    }
    return $value
}

function Assert-CmPath {
    param([string]$Path, [string]$Parent, [string]$RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)' -or -not (Test-PfcPathDescendant -Path $Path -Parent $Parent) -or (Test-PfcReparsePath -Path $Path)) { throw 'CM path boundary failed.' }
    if ($RepositoryRoot) {
        & git --no-pager -C $RepositoryRoot check-ignore -q -- $Path
        if ($LASTEXITCODE -ne 0) { throw 'CM evidence and authorization must be locally ignored.' }
    }
}

function Assert-CmGitEnvironment {
    if (@([Environment]::GetEnvironmentVariables('Process').Keys | Where-Object { $_ -match '^GIT_' -and $_ -cne 'GIT_PAGER' }).Count) { throw 'Inherited Git environment is forbidden for CM fixture operations.' }
}

function New-CmFixture {
    param($Manifest,[string]$RepositoryRoot=(Split-Path -Parent $PSScriptRoot))
    Assert-CmGitEnvironment
    $path = Join-Path ([IO.Path]::GetTempPath()) ('pfc-cm-fixture-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    $environmentNames = @('GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL','GIT_AUTHOR_DATE','GIT_COMMITTER_DATE')
    $saved = @{}; foreach($name in $environmentNames) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
    try {
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM','1','Process')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL',(Join-Path $path '.git/cm-empty-config'),'Process')
        foreach($name in @('GIT_AUTHOR_NAME','GIT_COMMITTER_NAME')) { [Environment]::SetEnvironmentVariable($name,'CM Fixture','Process') }
        foreach($name in @('GIT_AUTHOR_EMAIL','GIT_COMMITTER_EMAIL')) { [Environment]::SetEnvironmentVariable($name,'cm-fixture@example.invalid','Process') }
        foreach($name in @('GIT_AUTHOR_DATE','GIT_COMMITTER_DATE')) { [Environment]::SetEnvironmentVariable($name,'2026-09-20T00:00:00Z','Process') }
        $gitArgs=@('-c','core.autocrlf=false','-c','core.safecrlf=false','-c','commit.gpgSign=false','-c','core.hooksPath=NUL','-c','core.attributesFile=NUL','-c','init.defaultBranch=cm-fixture','-C',$path)
        & git --no-pager @gitArgs init --quiet --template= 2>&1 | Out-Null; if($LASTEXITCODE -ne 0){throw 'Fixture Git init failed.'}
        [IO.File]::AppendAllText((Join-Path $path '.git/config'),"`n[core]`n autocrlf = false`n safecrlf = false`n hooksPath = NUL`n attributesFile = NUL`n[commit]`n gpgSign = false`n",[Text.Encoding]::UTF8)
        foreach($file in $Manifest.fixture.files) {
            $target=Join-Path $path $file.path
            if ($file.path -match '(^|[\\/])\.git([\\/]|$)|(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($file.path)) { throw 'Unsafe fixture recipe path.' }
            Assert-CmPath -Path $target -Parent $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Write-PfcUtf8NoBom -Path $target -Content $file.content
        }
        foreach($productInput in $Manifest.product_inputs) {
            $source=Join-Path $RepositoryRoot $productInput.path
            Assert-CmPath $source $RepositoryRoot
            if((Get-CmHash -Path $source) -cne $productInput.sha256){throw 'Product input drift before fixture creation.'}
            $target=Join-Path $path ('.pfc-product/'+$productInput.path)
            Assert-CmPath $target $path
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
            [IO.File]::WriteAllBytes($target,[IO.File]::ReadAllBytes($source))
            if($productInput.path -cmatch '^codex-agents/project-flight-(builder|verifier)\.toml$') {
                $profile=Join-Path $path ('.codex/agents/'+(Split-Path -Leaf $productInput.path))
                New-Item -ItemType Directory -Path (Split-Path -Parent $profile) -Force|Out-Null
                [IO.File]::WriteAllBytes($profile,[IO.File]::ReadAllBytes($source))
            }
        }
        & git --no-pager @gitArgs add --all; if($LASTEXITCODE -ne 0){throw 'Fixture Git add failed.'}
        & git --no-pager @gitArgs commit --quiet -m ('Frozen '+$Manifest.scenario_id+' fixture'); if($LASTEXITCODE -ne 0){throw 'Fixture Git commit failed.'}
        $global:LASTEXITCODE=$null
        $headOutput=@(& git --no-pager @gitArgs rev-parse HEAD);$headExit=$LASTEXITCODE
        if($null -eq $headExit -or $headExit -ne 0 -or $headOutput.Count -ne 1 -or $headOutput[0] -cnotmatch '\A[0-9a-f]{40}\z' -or $headOutput[0] -ceq ('0'*40)){throw 'Missing physical Git base.'}
        $base=[string]$headOutput[0]
        foreach($file in $Manifest.fixture.dirty_files) {
            $target=Join-Path $path $file.path
            if ([IO.Path]::IsPathRooted($file.path) -or $file.path -match '(^|[\\/])(\.git|\.\.)([\\/]|$)') { throw 'Unsafe dirty fixture path.' }
            Assert-CmPath -Path $target -Parent $path
            Write-PfcUtf8NoBom -Path $target -Content $file.content
        }
        $global:LASTEXITCODE=$null
        $statusOutput=@(& git --no-pager @gitArgs status --porcelain);$statusExit=$LASTEXITCODE
        if($null -eq $statusExit -or $statusExit -ne 0){throw 'Initial fixture status unavailable.'}
        return [pscustomobject]@{path=$path;base_sha=$base;context_id=(Split-Path -Leaf $path);initial_status=($statusOutput -join "`n")}
    } catch { Remove-CmFixture -Path $path; throw }
    finally { foreach($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') } }
}

function Remove-CmFixture {
    param([string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    if ((Split-Path -Leaf $full) -cnotmatch '^pfc-cm-fixture-[0-9a-f]{32}$' -or -not ((Split-Path -Parent $full).Equals([IO.Path]::GetTempPath().TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) -or (Test-PfcReparsePath -Path $full)) { throw 'Refusing fixture cleanup outside owned temporary root.' }
    if (Test-Path -LiteralPath $full) {
        if (@(Get-ChildItem -LiteralPath $full -Force -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Refusing cleanup of a fixture containing reparse points.' }
        Remove-Item -LiteralPath $full -Force -Recurse
    }
}

function Get-CmPrompt {
    param([string]$Directory,[string]$Phase)
    $common=[IO.File]::ReadAllText((Join-Path $Directory 'common.md'),[Text.Encoding]::UTF8)
    $task=[IO.File]::ReadAllText((Join-Path $Directory 'prompt.md'),[Text.Encoding]::UTF8)
    $text=$common.TrimEnd()+"`n`n"+$task.Trim()+"`n"
    if($Phase -ceq 'GREEN') { $text=$text.TrimEnd()+"`n`n"+[IO.File]::ReadAllText((Join-Path $Directory 'treatment.md'),[Text.Encoding]::UTF8).Trim()+"`n" }
    return $text
}

function Assert-CmRunnerManagedRoleControl {
    param([object]$RoleControl)
    if($null -eq $RoleControl -or $RoleControl.launch_source -cne 'runner' -or $RoleControl.launch_mode -cne 'separate_codex_processes' -or $RoleControl.execution_order -cne 'builder_then_verifier_serial' -or $RoleControl.goalkeeper_session_mode -cne 'persistent_resumed' -or $RoleControl.subagents_enabled -ne $false -or $RoleControl.explicit_role_context_permission -ne $true -or ($RoleControl.roles -join ',') -cne 'project_flight_builder,project_flight_verifier' -or $RoleControl.maximum_concurrent_role_contexts -ne 2 -or $RoleControl.maximum_authorized_role_contexts_per_attempt -ne 13 -or $RoleControl.maximum_authorized_role_contexts_per_phase -ne 455 -or $RoleControl.context_budget_semantics -cne 'MAXIMUM_NOT_EXPECTED_USAGE' -or $RoleControl.enforcement -cne 'instruction_and_trace_audit' -or $RoleControl.hard_total_cap_available -ne $false -or $RoleControl.acknowledge_additional_model_usage -ne $true -or $RoleControl.recursive_delegation -ne $false -or $RoleControl.replacement_calls -ne $false -or $RoleControl.maximum_candidate_revisions -ne 3 -or $RoleControl.maximum_auto_rework_rounds -ne 2 -or $RoleControl.maximum_builder_repairs -ne 2 -or $RoleControl.maximum_scenario_milestones -ne 2 -or $RoleControl.model -cne 'gpt-5.6-terra' -or $RoleControl.reasoning_effort -cne 'medium' -or $RoleControl.top_level_attempt_cap -ne 35 -or $RoleControl.missing_or_exceeded_trace -cne 'STOP_PRESERVE_NO_RETRY' -or $RoleControl.token_usage_scope -cne 'ALL_CONTEXTS_OR_NOT_AVAILABLE' -or $RoleControl.trace_contract -cne 'runner_owned_lifecycle_jsonl_with_persistent_goalkeeper_resume' -or $RoleControl.safe_no_dispatch_collection -cne 'CM05_frozen_identity_reads_and_unchanged_physical_evidence_only'){throw 'Invalid Runner-managed Builder/Verifier role contract.'}
}

function Assert-CmRunnerRoleAuthorization {
    param([object]$Expected,[object]$Authorized)
    if($null -eq $Expected -or $null -eq $Authorized -or ($Authorized|ConvertTo-Json -Depth 60 -Compress) -cne ($Expected|ConvertTo-Json -Depth 60 -Compress)){throw 'Runner-managed role authorization missing or mismatched.'}
}

function Get-CmFrozenControl {
    param([string]$RepositoryRoot)
    $controlPath=Join-Path $RepositoryRoot 'evals/expected/continuous-mode-model/frozen-control.json'
    $control=Get-Content -Raw -Encoding UTF8 -LiteralPath $controlPath|ConvertFrom-Json
    Assert-CmProperties $control @('contract','model','reasoning_effort','sandbox','repetition_count','scenario_ids','metrics','hard_gates','efficiency_gate','artifacts','scenarios','product','runner_managed_roles')
    if($control.product.candidate_sha -cnotmatch '\A[0-9a-f]{40}\z' -or $control.product.inputs.Count -lt 3 -or (Get-CmHash -Text ($control.product.inputs|ConvertTo-Json -Depth 60 -Compress)) -cne $control.product.inputs_sha256){throw 'Invalid product Candidate binding.'}
    $global:LASTEXITCODE=$null
    $productTree=@(& git --no-pager -C $RepositoryRoot ls-tree -r $control.product.candidate_sha -- skill/project-flight-control codex-agents);$treeExit=$LASTEXITCODE
    if($null -eq $treeExit -or $treeExit -ne 0 -or $productTree.Count -ne $control.product.inputs.Count){throw 'Product source Candidate tree unavailable.'}
    foreach($productInput in $control.product.inputs) {
        $path=Join-Path $RepositoryRoot $productInput.path;Assert-CmPath $path $RepositoryRoot
        if((Get-CmHash -Path $path) -cne $productInput.sha256){throw 'Product input drift.'}
        if(@($productTree|Where-Object {$_ -ceq ('100644 blob '+$productInput.git_blob_sha+"`t"+$productInput.path)}).Count -ne 1){throw 'Product input not bound to source Candidate.'}
        $bytes=[IO.File]::ReadAllBytes($path);$prefix=[Text.Encoding]::ASCII.GetBytes('blob '+$bytes.Length+[char]0);$sha=[Security.Cryptography.SHA1]::Create()
        try{$blob=[BitConverter]::ToString($sha.ComputeHash([byte[]]($prefix+$bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($blob -cne $productInput.git_blob_sha){throw 'Product Candidate byte mismatch.'}
    }
    Assert-CmRunnerManagedRoleControl -RoleControl $control.runner_managed_roles
    if($control.contract -cne 'CM1' -or $control.model -cne 'gpt-5.6-terra' -or $control.reasoning_effort -cne 'medium' -or $control.sandbox -cne 'workspace-write' -or $control.repetition_count -ne 5 -or ($control.scenario_ids -join ',') -cne 'CM-01,CM-02,CM-03,CM-04,CM-05,CM-06,CM-07' -or $control.scenarios.Count -ne 7) { throw 'Invalid frozen CM controls.' }
    foreach($artifact in $control.artifacts) {
        $path=Join-Path $RepositoryRoot $artifact.path; Assert-CmPath $path $RepositoryRoot
        if((Get-CmHash -Path $path) -cne $artifact.sha256) { throw ('Frozen artifact drift: '+$artifact.path) }
    }
    $schema=Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode-model/continuous-mode-eval-run.schema.json'
    if((Get-PfcStrictSchemaPreflight -Path $schema).strict_schema_preflight -cne 'PASS'){throw 'CM isolated schema is not strict UTF-8 without BOM.'}
    foreach($entry in $control.scenarios) {
        $path=Join-Path $RepositoryRoot $entry.manifest_path; Assert-CmPath $path (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode-model')
        if((Get-CmHash -Path $path) -cne $entry.manifest_sha256){throw 'Frozen scenario manifest drift.'}
        $manifest=Get-Content -Raw -Encoding UTF8 -LiteralPath $path|ConvertFrom-Json
        if($manifest.product_candidate_sha -cne $control.product.candidate_sha -or $manifest.product_inputs_sha256 -cne $control.product.inputs_sha256 -or ($manifest.product_inputs|ConvertTo-Json -Depth 60 -Compress) -cne ($control.product.inputs|ConvertTo-Json -Depth 60 -Compress)){throw 'Scenario product binding drift.'}
        if($manifest.scenario_id -cne $entry.scenario_id -or $manifest.base_sha -cne $entry.base_sha -or $manifest.base_sha -cnotmatch '^[0-9a-f]{40}$' -or $manifest.fixture_sha -cne (Get-CmHash -Text ($manifest.fixture|ConvertTo-Json -Depth 60 -Compress)) -or $manifest.task_contract_sha -cne (Get-CmHash -Text ($manifest.task_contract|ConvertTo-Json -Depth 60 -Compress))) {throw 'Fixture or task contract drift.'}
        foreach($field in @('model','reasoning_effort','sandbox','repetition_count')) { if($manifest.$field -cne $control.$field){throw 'Scenario control mismatch.'} }
        $directory=Split-Path -Parent $path
        foreach($pair in @(@('common.md','common_prompt_sha256'),@('prompt.md','prompt_sha256'),@('treatment.md','treatment_sha256'))) {
            $promptPath=Join-Path $directory $pair[0];Assert-CmPath $promptPath $directory
            if((Get-CmHash -Path $promptPath) -cne $manifest.($pair[1])){throw 'Prompt bytes drifted.'}
        }
        if($manifest.schema_sha256 -cne (Get-CmHash -Path $schema) -or $manifest.runner_sha256 -cne (Get-CmHash -Path (Join-Path $RepositoryRoot 'evals/lib/CodexRunner.psm1'))) {throw 'Runner/schema drift.'}
        foreach($phaseName in @('RED','GREEN')) { if((Get-CmHash -Text (Get-CmPrompt $directory $phaseName)) -cne $entry.effective_prompt_sha256.$phaseName) {throw 'Effective prompt drift.'} }
    }
    return $control
}

function Convert-CmEvidenceText {
    param([string]$Text)
    # Persist only allowlisted fields. Strings in nested metric/evidence entries
    # receive the same redaction before leaving ignored raw storage.
    $value=$Text -replace '(?i)(?<![A-Za-z0-9_])["'']?(?:api[_-]?key|token|password|secret)["'']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|[^\s,;}\]]+)','<REDACTED_SECRET>'
    $value=$value -replace '(?i)(?:[A-Za-z]:[\\/]|\\\\)[^\s"'']+','<ABSOLUTE_PATH>'
    $value=$value -replace '(?<![A-Za-z0-9])/[^\s"'']+','<ABSOLUTE_PATH>'
    return ($value -replace '(?i)(sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_-]{8,}|Bearer\s+[A-Za-z0-9._-]+|(?:api[_-]?key|token|password|secret)\s*[:=]\s*[^\s,;]+)','<REDACTED_SECRET>')
}

function Read-CmNativeTrace {
    param([string]$Path,[bool]$FakeTransport=$false)
    # Only native transport items are evidence of distinct contexts. Agent text,
    # tool stdout and model-reported counters cannot manufacture these records.
    $out=[ordered]@{status='NOT_AVAILABLE';observed_child_contexts='NOT_AVAILABLE';independent_handoffs=@();source=$(if($FakeTransport){'FAKE_TRANSPORT_ONLY'}else{'NATIVE_TRANSPORT'});correctness='NOT_RUN';lifecycle='NOT_AVAILABLE';no_dispatch_readonly=$false;error_event_count=0}
    $root=$null;$contexts=@{};$handoffs=@();$pendingBuilder=$null;$candidate=$null;$terminal=$false;$turn=$false;$items=@{};$readonly=$true;$identityReads=@{}
    foreach($line in [IO.File]::ReadAllLines($Path)) {
        $event=$line|ConvertFrom-Json
        if($terminal){return [pscustomobject]$out}
        if($event.type -ceq 'error'){$out.error_event_count++;continue}
        if($event.type -ceq 'thread.started'){if($root -or -not $event.thread_id){return [pscustomobject]$out};$root=$event.thread_id;continue}
        if($event.type -ceq 'turn.started'){if(-not $root -or $turn){return [pscustomobject]$out};$turn=$true;continue}
        if(-not $turn){return [pscustomobject]$out}
        if($event.type -ceq 'turn.completed'){$terminal=$true;continue}
        if($event.type -cnotin @('item.started','item.updated','item.completed')){return [pscustomobject]$out}
        $item=$event.item
        if($event.type -ceq 'item.completed' -and $item.type -ceq 'error'){$out.error_event_count++}
        if(-not $item.id -or $item.type -cnotin @('agent_message','reasoning','command_execution','file_change','todo_list','collab_tool_call','collabAgentToolCall','error')){return [pscustomobject]$out}
        if($event.type -ceq 'item.started') {
            if($items.ContainsKey($item.id)){return [pscustomobject]$out}
            $items[$item.id]=@{type=$item.type;done=$false};continue
        }
        if($event.type -ceq 'item.updated'){if(-not $items.ContainsKey($item.id) -or $items[$item.id].done -or $items[$item.id].type -cne $item.type){return [pscustomobject]$out};continue}
        if(-not $items.ContainsKey($item.id)) {
            if($item.type -cnotin @('agent_message','reasoning','file_change','error')){return [pscustomobject]$out}
            $items[$item.id]=@{type=$item.type;done=$false}
        }
        if($items[$item.id].done -or $items[$item.id].type -cne $item.type){return [pscustomobject]$out}
        $items[$item.id].done=$true
        if($item.type -ceq 'error'){continue}
        if($item.type -ceq 'command_execution') {
            # The no-dispatch CM-05 route permits only directly observed simple
            # reads. Scripts, chaining, unknown tools and hidden dispatch stay unknown.
            if($item.status -cne 'completed' -or $null -eq $item.exit_code -or $item.exit_code -ne 0 -or [string]$item.command -cnotmatch '^(?:git (?:status --porcelain|rev-parse HEAD|diff --no-ext-diff --no-textconv)|Get-Content (?:-Raw )?(?:-LiteralPath )?[A-Za-z0-9_./-]+)$'){$readonly=$false}
            foreach($path in @('docs/project-control/WORK_ORDER.md','docs/project-control/STATUS.md')){if([string]$item.command -cmatch ('^Get-Content (?:-Raw )?(?:-LiteralPath )?'+[regex]::Escape($path)+'$')){$identityReads[$path]=[string]$item.aggregated_output}}
        }
        if($item.type -ceq 'file_change'){$readonly=$false}
        if($item.type -ceq 'collab_tool_call') {
            $item=[pscustomobject]@{type='collabAgentToolCall';tool=(@{spawn_agent='spawnAgent';wait='wait';close_agent='closeAgent';send_input='sendInput'})[$item.tool];senderThreadId=$item.sender_thread_id;receiverThreadIds=$item.receiver_thread_ids;prompt=$item.prompt;agentsStates=$item.agents_states;status=$item.status}
        }
        if($item.type -cne 'collabAgentToolCall'){continue}
        if(-not $root -or $item.senderThreadId -cne $root -or $item.status -cne 'completed'){return [pscustomobject]$out}
        if($item.tool -ceq 'spawnAgent') {
            $ids=@($item.receiverThreadIds)
            $role=[regex]::Match([string]$item.prompt,'ROLE=(project_flight_builder|project_flight_verifier)(?:\s|$)').Groups[1].Value
            if($ids.Count -ne 1 -or -not $ids[0] -or $ids[0] -ceq $root -or $contexts.ContainsKey($ids[0]) -or -not $role){return [pscustomobject]$out}
            $context=@{role=$role;terminal=$false;consumed=$false;builder=$null;requested=$null}
            if($role -ceq 'project_flight_builder') {
                if($pendingBuilder){return [pscustomobject]$out}
                $pendingBuilder=$ids[0];$candidate=$null
            } else {
                $requestedSha=[regex]::Match([string]$item.prompt,'CANDIDATE_SHA=([a-f0-9]{40})(?:\s|$)').Groups[1].Value
                if(-not $requestedSha -or $requestedSha -cne $candidate){return [pscustomobject]$out}
                $context.requested=$requestedSha;$context.builder=$pendingBuilder
            }
            $contexts[$ids[0]]=$context
            if($contexts.Count -gt 13){$out.status='EXCEEDED';$out.observed_child_contexts=$contexts.Count;return [pscustomobject]$out}
        }
        elseif($item.tool -cnotin @('wait','closeAgent')){return [pscustomobject]$out}
        foreach($id in $item.receiverThreadIds){if(-not $contexts.ContainsKey($id)){return [pscustomobject]$out}}
        foreach($state in $item.agentsStates.PSObject.Properties) {
            if(-not $contexts.ContainsKey($state.Name)){return [pscustomobject]$out}
            $context=$contexts[$state.Name]
            if($context.consumed){continue}
            if($state.Value.status -cne 'completed'){continue}
            $context.terminal=$true;$context.consumed=$true
            if($context.role -ceq 'project_flight_builder' -and $state.Name -ceq $pendingBuilder -and ([string]$state.Value.message).Contains('BUILD_REPORT')) {
                $candidate=[regex]::Match([string]$state.Value.message,'CANDIDATE_SHA=([a-f0-9]{40})(?:\s|$)').Groups[1].Value
            }
            if($context.role -cne 'project_flight_verifier'){continue}
            $sha=[regex]::Match([string]$state.Value.message,'CANDIDATE_SHA=([a-f0-9]{40})(?:\s|$)').Groups[1].Value
            if($sha -and $sha -ceq $context.requested -and $sha -ceq $candidate -and $context.builder -ceq $pendingBuilder -and ([string]$state.Value.message).Contains('REVIEW_REPORT')) {
                $handoffs+= [pscustomobject]@{builder_context=$context.builder;verifier_context=$state.Name;candidate_sha=$sha;review='REPORTED_BY_INDEPENDENT_CONTEXT_UNVERIFIED'}
                $pendingBuilder=$null
            } else {return [pscustomobject]$out}
        }
    }
    if($terminal -and @($items.Values|Where-Object {-not $_.done}).Count -eq 0 -and @($contexts.Values|Where-Object {-not $_.terminal}).Count -eq 0){$out.lifecycle='TERMINAL_OBSERVED'}
    if($out.error_event_count -gt 0){$out.status='ERRORS_OBSERVED';$out.observed_child_contexts='NOT_AVAILABLE';return [pscustomobject]$out}
    if($out.lifecycle -ceq 'TERMINAL_OBSERVED' -and $contexts.Count -eq 0) {
        if($readonly -and $identityReads.Count -eq 2){$out.status='NO_DISPATCH_OBSERVED';$out.observed_child_contexts=0;$out.no_dispatch_readonly=$true;$out.identity_reads=$identityReads}
        else {$out.lifecycle='NOT_AVAILABLE'}
    }
    if($out.lifecycle -ceq 'TERMINAL_OBSERVED' -and $handoffs.Count -gt 0 -and -not $pendingBuilder){$out.status='OBSERVED';$out.observed_child_contexts=$contexts.Count;$out.independent_handoffs=$handoffs}
    return [pscustomobject]$out
}

function Read-CmRunnerTrace {
    param([string]$Path,[switch]$FakeTransport)
    $isFake = [bool]$FakeTransport
    return Read-PfcRunnerLifecycle -Path $Path -FakeTransport:$isFake
}

function Invoke-CmModelSample {
    param([string]$RepositoryRoot,$Manifest,$Fixture,[string]$Phase,[int]$Repetition,[string]$ResultDirectory,[AllowNull()][string]$CodexExecutablePath,[scriptblock]$ProcessInvoker)
    Assert-CmGitEnvironment
    Assert-CmPath $ResultDirectory (Join-Path $RepositoryRoot '.pfc-eval-results') $RepositoryRoot
    $control=Get-CmFrozenControl $RepositoryRoot
    $entry=@($control.scenarios|Where-Object scenario_id -CEQ $Manifest.scenario_id)[0]
    $global:LASTEXITCODE=$null
    $headOutput=@(& git --no-pager -C $Fixture.path rev-parse HEAD);$headExit=$LASTEXITCODE
    if($null -eq $headExit -or $headExit -ne 0 -or $headOutput.Count -ne 1 -or $headOutput[0] -cnotmatch '\A[0-9a-f]{40}\z' -or $headOutput[0] -ceq ('0'*40)){throw 'Pre-call HEAD unavailable.'}
    $global:LASTEXITCODE=$null
    $statusOutput=@(& git --no-pager -C $Fixture.path status --porcelain);$statusExit=$LASTEXITCODE
    if($null -eq $statusExit -or $statusExit -ne 0){throw 'Pre-call status unavailable.'}
    if($Fixture.base_sha -cne $Manifest.base_sha -or $headOutput[0] -cne $Manifest.base_sha -or ($statusOutput -join "`n") -cne $Fixture.initial_status) {throw 'Pre-call fixture drift.'}
    $directory=Split-Path -Parent (Join-Path $RepositoryRoot $entry.manifest_path)
    $shared=Get-CmPrompt $directory RED
    $sharedPath=Join-Path $ResultDirectory ('shared-'+[guid]::NewGuid().ToString('N')+'.md')
    Write-PfcUtf8NoBom -Path $sharedPath -Content $shared
    $runnerLifecyclePath=Join-Path $ResultDirectory ('runner-events-'+$Manifest.scenario_id+'-'+$Phase+'-'+$Repetition+'-'+[guid]::NewGuid().ToString('N')+'.jsonl')
    $parameters=@{WorkingDirectory=$Fixture.path;PromptPath=$sharedPath;OutputSchemaPath=(Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode-model/continuous-mode-eval-run.schema.json');SandboxMode=$Manifest.sandbox;CodexExecutablePath=$CodexExecutablePath;MaximumChildren=13;ResultDirectory=$ResultDirectory;LifecyclePath=$runnerLifecyclePath;Phase=$Phase;Model=$Manifest.model;ReasoningEffort=$Manifest.reasoning_effort;RequireExternalResultDirectory=$true;Scenario=$Manifest.scenario_id;Repetition=$Repetition;FixtureBaseSha=$Fixture.base_sha;FixtureId=$Fixture.context_id;SampleId=($Manifest.scenario_id+'-'+$Phase+'-'+$Repetition);ContinuousModeAgentDirectory=(Join-Path $Fixture.path '.codex/agents')}
    if($Phase -ceq 'GREEN'){$parameters.TreatmentPromptPath=Join-Path $directory 'treatment.md'}
    $composition=Get-PfcEvaluationPromptText -CommonPromptPath $sharedPath -TreatmentPromptPath $parameters.TreatmentPromptPath -Phase $Phase
    if((Get-CmHash -Text $composition.text) -cne $entry.effective_prompt_sha256.$Phase){throw 'Invocation prompt does not match freeze.'}
    if($ProcessInvoker){$parameters.ProcessInvoker=$ProcessInvoker}
    $flow=Invoke-PfcRunnerManagedCodexFlow @parameters
    $raw=$flow.raw
    $payload=$raw.continuous_model_output
    if($raw.process_count -ne 1 -or $raw.automatic_retries -ne 0 -or $raw.turn_result -cne 'COMPLETED' -or $raw.error_events -gt 0 -or $raw.structured_output_validated -ne $true -or $payload.phase -cne $Phase -or $payload.scenario_id -cne $Manifest.scenario_id) {throw 'Invalid CM terminal/output identity.'}
    $normalized=[ordered]@{scenario_id=$Manifest.scenario_id;phase=$Phase;repetition=$Repetition;context_id=$Fixture.context_id;base_sha=$Fixture.base_sha;model_status=$payload.status;correctness='NOT_RUN';metrics=[ordered]@{};verification=[ordered]@{};evidence=@();token_usage='NOT_AVAILABLE';raw_jsonl=($raw.raw_jsonl_path -replace '^external-evidence/','')}
    $tracePath=Join-Path $ResultDirectory $normalized.raw_jsonl
    Assert-CmPath $tracePath $ResultDirectory
    $normalized.native_trace=Read-CmNativeTrace $tracePath ([bool]$ProcessInvoker)
    # A complete Runner handoff cannot make a native error a valid sample.
    if($normalized.native_trace.status -ceq 'ERRORS_OBSERVED' -or $normalized.native_trace.error_event_count -gt 0){throw 'CM native error events invalidate the sample; no retry.'}
    $normalized.runner_trace=$flow.runner_trace
    $normalized.runner_lifecycle_jsonl=if(Test-Path -LiteralPath $runnerLifecyclePath -PathType Leaf){[IO.Path]::GetFileName($runnerLifecyclePath)}else{'NOT_AVAILABLE'}
    $normalized.runner_child_contexts=$flow.runner_child_contexts
    $normalized.goalkeeper_resumptions=$flow.goalkeeper_resumptions
    $normalized.codex_process_invocations=$flow.codex_process_invocations
    $normalized.top_level_token_usage='NOT_AVAILABLE'
    foreach($field in @('metrics','verification')) {
        $expected=if($field -eq 'metrics'){@($control.metrics)}else{@($control.hard_gates)}
        $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($item in $payload.$field) {
            if(-not $seen.Add($item.key) -or $expected -cnotcontains $item.key){throw 'Unknown or duplicate CM metric key.'}
            if($null -ne $item.value -and ($item.value -isnot [ValueType] -or $item.value -is [bool] -or [double]$item.value -lt 0 -or [double]$item.value -ne [math]::Floor([double]$item.value))) {throw 'CM metrics require nonnegative integers or null.'}
            $normalized[$field][$item.key]=if($null -eq $item.value){'NOT_AVAILABLE'}else{$item.value}
            $normalized.evidence+= [pscustomobject]@{key=$item.key;source='MODEL_REPORTED_UNVERIFIED';text=(Convert-CmEvidenceText $item.evidence)}
        }
        if($seen.Count -ne $expected.Count){throw 'CM metric coverage incomplete.'}
    }
    $usage=$raw.usage
    if($usage -isnot [string] -and $null -ne $usage) {
        $valid=$true;$values=[ordered]@{}
        foreach($key in @('input_tokens','output_tokens')) {
            $property=$usage.PSObject.Properties[$key]
            if($null -eq $property -or $null -eq $property.Value -or $property.Value -isnot [ValueType] -or $property.Value -is [bool] -or [double]$property.Value -lt 0 -or [double]$property.Value -ne [math]::Floor([double]$property.Value)){$valid=$false;break}
            $values[$key]=$property.Value
        }
        # Runner-managed Builder and Verifier sessions are separate contexts.
        # A top-level terminal usage field does not establish whole-scenario usage.
        if($valid){$normalized.top_level_token_usage=[pscustomobject]$values}
    }
    return [pscustomobject]$normalized
}

function Write-CmReservation {
    param([string]$Path,[string]$Text)
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes=[Text.Encoding]::UTF8.GetBytes($Text);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true) } finally {$stream.Dispose()}
}

function Save-CmFixtureEvidence {
    param($Fixture,[string]$ResultDirectory)
    Assert-CmGitEnvironment
    Assert-CmPath (Join-Path $Fixture.path '.git') $Fixture.path
    $destination=Join-Path $ResultDirectory $Fixture.context_id
    Assert-CmPath $destination $ResultDirectory
    New-Item -ItemType Directory -Path $destination -Force|Out-Null
    $gitEvidence=@{}
    foreach($request in @(
        @{Name='candidate';Arguments=@('rev-parse','HEAD')},
        @{Name='status';Arguments=@('status','--porcelain')},
        @{Name='graph';Arguments=@('log','--format=%H %P','--all')},
        @{Name='diff';Arguments=@('diff','--no-ext-diff','--no-textconv','--binary',$Fixture.base_sha,'--')}
    )) {
        $gitArguments=$request.Arguments
        $lines=@(& git --no-pager -C $Fixture.path @gitArguments)
        $gitExit=$LASTEXITCODE
        if($gitExit -ne 0){throw ('CM evidence Git '+$request.Name+' failed with exit '+$gitExit)}
        $gitEvidence[$request.Name]=$lines
    }
    if($gitEvidence.candidate.Count -ne 1 -or $gitEvidence.candidate[0] -cnotmatch '^[0-9a-f]{40}$' -or $Fixture.base_sha -cnotmatch '^[0-9a-f]{40}$' -or $gitEvidence.graph.Count -eq 0){throw 'CM evidence requires valid Base/Candidate SHA and a nonempty commit graph.'}
    $commits=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $parents=New-Object 'System.Collections.Generic.List[string]'
    foreach($line in $gitEvidence.graph) {
        $row=([string]$line).Trim()
        if($row -cnotmatch '^[0-9a-f]{40}( [0-9a-f]{40})*$'){throw 'CM evidence commit graph contains malformed SHAs.'}
        $shaFields=$row.Split(' ')
        if(-not $commits.Add($shaFields[0])){throw 'CM evidence commit graph contains duplicate commits.'}
        for($i=1;$i -lt $shaFields.Count;$i++){$parents.Add($shaFields[$i])}
    }
    if(-not $commits.Contains($Fixture.base_sha) -or -not $commits.Contains($gitEvidence.candidate[0]) -or @($parents|Where-Object {-not $commits.Contains($_)}).Count){throw 'CM evidence commit graph omits Base, Candidate or a parent.'}
    $record=[ordered]@{base_sha=$Fixture.base_sha;candidate_sha=$gitEvidence.candidate[0];initial_status=$Fixture.initial_status;final_status=($gitEvidence.status -join "`n");graph=$gitEvidence.graph;files=@()}
    $global:LASTEXITCODE=$null
    $worktreeLines=@(& git --no-pager -C $Fixture.path worktree list --porcelain);$worktreeExit=$LASTEXITCODE
    if($null -eq $worktreeExit -or $worktreeExit -ne 0){throw 'CM worktree inventory unavailable; preserve fixture.'}
    $record.worktrees=@()
    foreach($line in $worktreeLines) {
        if($line -cnotmatch '^worktree (.+)$'){continue}
        $worktree=[IO.Path]::GetFullPath($Matches[1])
        if(-not $worktree.Equals([IO.Path]::GetFullPath($Fixture.path),[StringComparison]::OrdinalIgnoreCase)) {Assert-CmPath $worktree (Join-Path $Fixture.path '.pfc-worktrees')}
        $capture=@{}
        foreach($request in @(@{name='head';args=@('rev-parse','HEAD')},@{name='status';args=@('status','--porcelain')},@{name='diff';args=@('diff','--no-ext-diff','--no-textconv','--binary',$Fixture.base_sha,'--')})) {
            $global:LASTEXITCODE=$null;$arguments=$request.args
            $value=@(& git --no-pager -C $worktree @arguments);$exit=$LASTEXITCODE
            if($null -eq $exit -or $exit -ne 0){throw 'CM linked worktree capture failed; preserve fixture.'}
            $capture[$request.name]=$value
        }
        if($capture.head.Count -ne 1 -or -not $commits.Contains($capture.head[0])){throw 'CM worktree HEAD absent from saved graph.'}
        $relative=if($worktree.Equals([IO.Path]::GetFullPath($Fixture.path),[StringComparison]::OrdinalIgnoreCase)){'.'}else{$worktree.Substring($Fixture.path.TrimEnd('\').Length).TrimStart('\').Replace('\','/')}
        $diffName='worktree-'+$record.worktrees.Count+'.diff'
        Write-PfcUtf8NoBom (Join-Path $destination $diffName) ($capture.diff -join "`n")
        $record.worktrees+= [pscustomobject]@{path=$relative;head_sha=$capture.head[0];status=($capture.status -join "`n");diff=$diffName;files_prefix=('files/'+$relative)}
    }
    if($record.worktrees.Count -lt 1){throw 'CM worktree inventory is empty.'}
    Write-PfcUtf8NoBom -Path (Join-Path $destination 'changes.diff') -Content ($gitEvidence.diff -join "`n")
    # Enumerate the owned tree, including ignored files. Check each entry before
    # descending; never follow reparse points or copy .git internals.
    $directories=New-Object 'System.Collections.Generic.Stack[string]'
    $directories.Push($Fixture.path)
    while($directories.Count -gt 0) {
        foreach($item in Get-ChildItem -LiteralPath $directories.Pop() -Force -ErrorAction Stop) {
            if($item.Name -eq '.git'){continue}
            Assert-CmPath $item.FullName $Fixture.path
            if($item.PSIsContainer){$directories.Push($item.FullName);continue}
            $relative=$item.FullName.Substring($Fixture.path.TrimEnd('\').Length).TrimStart('\').Replace('\','/')
            $storedPath='files/'+$relative
            # PS5.1/.NET file copies may still enforce MAX_PATH. Keep long nested
            # worktree artifacts in a short owned location, with an exact path map.
            if((Join-Path $destination $storedPath).Length -ge 240){$storedPath='_long_files/'+$record.files.Count+'.bin'}
            $target=Join-Path $destination $storedPath;Assert-CmPath $target $destination
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
            [IO.File]::Copy($item.FullName,$target,$false)
            $record.files+= [ordered]@{path=$relative;stored_path=$storedPath;sha256=(Get-CmHash -Path $target);bytes=(Get-Item -LiteralPath $target).Length}
        }
    }
    Write-PfcUtf8NoBom -Path (Join-Path $destination 'fixture-evidence.json') -Content ($record|ConvertTo-Json -Depth 30)
    return [pscustomobject]@{relative_path=($Fixture.context_id+'/fixture-evidence.json');sha256=(Get-CmHash -Path (Join-Path $destination 'fixture-evidence.json'))}
}

function Test-CmSafeIdentityStop {
    param($Manifest,$Sample,$FixtureEvidence,[string]$ResultDirectory)
    # Narrow CM-05 collection evidence only. This never supplies correctness PASS.
    if($Manifest.scenario_id -cne 'CM-05' -or $null -eq $Sample.runner_trace -or $Sample.runner_trace.source -cne 'RUNNER' -or $Sample.runner_trace.status -cne 'NO_DISPATCH_OBSERVED' -or $Sample.runner_trace.lifecycle -cne 'NO_CHILD_PROCESSES' -or $Sample.runner_trace.observed_child_contexts -isnot [int] -or $Sample.runner_trace.observed_child_contexts -ne 0 -or $Sample.native_trace.status -cne 'NO_DISPATCH_OBSERVED' -or $Sample.native_trace.lifecycle -cne 'TERMINAL_OBSERVED' -or $Sample.native_trace.observed_child_contexts -isnot [int] -or $Sample.native_trace.observed_child_contexts -ne 0 -or -not $Sample.native_trace.no_dispatch_readonly){return $false}
    $path=Join-Path $ResultDirectory $FixtureEvidence.relative_path;Assert-CmPath $path $ResultDirectory
    if((Get-CmHash -Path $path) -cne $FixtureEvidence.sha256){return $false}
    $record=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    $directory=Split-Path -Parent $path
    if($record.base_sha -cne $Manifest.base_sha -or $record.candidate_sha -cne $record.base_sha -or $record.initial_status -cne '' -or $record.final_status -cne '' -or $record.worktrees.Count -ne 1 -or $record.worktrees[0].path -cne '.' -or $record.worktrees[0].head_sha -cne $Manifest.base_sha -or $record.worktrees[0].status -cne '' -or [IO.File]::ReadAllText((Join-Path $directory 'changes.diff')) -cne ''){return $false}
    $expected=@{}
    foreach($file in $Manifest.fixture.files){$expected[$file.path]=Get-CmHash -Text $file.content}
    foreach($file in $Manifest.product_inputs){
        $expected['.pfc-product/'+$file.path]=$file.sha256
        if($file.path -cmatch '^codex-agents/project-flight-(builder|verifier)\.toml$'){$expected['.codex/agents/'+(Split-Path -Leaf $file.path)]=$file.sha256}
    }
    if($record.files.Count -ne $expected.Count){return $false}
    $seen=@{}
    foreach($file in $record.files){
        $stored=Join-Path $directory $file.stored_path;Assert-CmPath $stored $directory
        if($seen.ContainsKey($file.path) -or -not $expected.ContainsKey($file.path) -or $expected[$file.path] -cne $file.sha256 -or (Get-CmHash -Path $stored) -cne $file.sha256){return $false};$seen[$file.path]=$true
    }
    $identities=@()
    foreach($name in @('WORK_ORDER','STATUS')) {
        $relative='docs/project-control/'+$name+'.md'
        $file=@($Manifest.fixture.files|Where-Object path -ceq $relative)[0]
        if(([string]$Sample.native_trace.identity_reads[$relative]).Replace("`r`n","`n").TrimEnd("`n") -cne ([string]$file.content).Replace("`r`n","`n").TrimEnd("`n")){return $false}
        $milestone=[regex]::Match($file.content,'(?m)^Milestone: (.+)$').Groups[1].Value
        $lease=[regex]::Match($file.content,'(?m)^Lease: (.+)$').Groups[1].Value
        if(-not $milestone -or -not $lease){return $false};$identities+=($milestone+'|'+$lease)
    }
    return ($identities[0] -cne $identities[1])
}

function Test-CmFixtureCleanupEligible {
    param($Sample)
    if($null -eq $Sample -or $null -eq $Sample.runner_trace -or $null -eq $Sample.native_trace -or $Sample.runner_trace.source -cne 'RUNNER' -or $Sample.native_trace.lifecycle -cne 'TERMINAL_OBSERVED' -or $Sample.runner_trace.observed_child_contexts -isnot [int]){return $false}
    $runnerHasNoChildren=$Sample.runner_trace.status -ceq 'NO_DISPATCH_OBSERVED' -and $Sample.runner_trace.lifecycle -ceq 'NO_CHILD_PROCESSES' -and $Sample.runner_trace.observed_child_contexts -eq 0
    $runnerChildrenComplete=$Sample.runner_trace.status -cin @('OBSERVED','NO_COMPLETE_HANDOFF') -and $Sample.runner_trace.lifecycle -ceq 'TERMINAL_OBSERVED' -and $Sample.runner_trace.observed_child_contexts -gt 0
    return ($runnerHasNoChildren -or $runnerChildrenComplete)
}

function Invoke-CmModelDispatch {
    param([string]$RepositoryRoot,[string]$Phase,[int]$Repeat,[string]$AuthorizationPath,[string]$ResultDirectory,[AllowNull()][string]$CodexExecutablePath,[scriptblock]$ProcessInvoker,[switch]$DiagnosticCanary)
    $result=[ordered]@{status='NOT_RUN';attempts=0;valid_samples=0;formal_samples=0;correctness='NOT_RUN';automatic_retries=0;samples=@();reason='Preflight not complete.'}
    $claimed=$false
    try {
        Assert-CmGitEnvironment
        $expectedScenarioIds=@('CM-01','CM-02','CM-03','CM-04','CM-05','CM-06','CM-07')
        $expectedRepeatCount=5
        $expectedSampleTarget=35
        $expectedMaximumAttempts=35
        if($DiagnosticCanary) {
            if($Phase -cnotin @('RED','GREEN') -or $Repeat -ne 1){throw 'Diagnostic CM requires RED or GREEN and Repeat 1.'}
            $expectedScenarioIds=@('CM-01')
            $expectedRepeatCount=1
            $expectedSampleTarget=1
            $expectedMaximumAttempts=1
        } elseif($Phase -cnotin @('RED','GREEN') -or $Repeat -ne 5) {
            throw 'Formal CM requires RED or GREEN and Repeat 5.'
        }
        Assert-CmPath $AuthorizationPath (Join-Path $RepositoryRoot '.pfc-eval-results/authorizations') $RepositoryRoot
        Assert-CmPath $ResultDirectory (Join-Path $RepositoryRoot '.pfc-eval-results') $RepositoryRoot
        $authorizationHash=Get-CmHash -Path $AuthorizationPath
        $authorization=Read-CmAuthorization $AuthorizationPath
        Assert-CmProperties $authorization @('authorization_id','phase','scenario_ids','repetitions_per_scenario','valid_run_target','maximum_attempts','model','reasoning_effort','sandbox','control_sha256','bindings','no_retry','remote_actions','issued_at','test_only','product','runner_managed_roles')
        foreach($textName in @('authorization_id','phase','model','reasoning_effort','sandbox','control_sha256','issued_at')) {if($authorization.$textName -isnot [string]){throw 'Authorization control must be a JSON string.'}}
        if($authorization.scenario_ids -isnot [array] -or $authorization.scenario_ids.Count -ne $expectedScenarioIds.Count -or @($authorization.scenario_ids|Where-Object {$_ -isnot [string]}).Count -or $authorization.bindings -isnot [array] -or $authorization.bindings.Count -ne $expectedScenarioIds.Count){throw 'Authorization scenario IDs and bindings do not match this run scope.'}
        $issued=[DateTimeOffset]::MinValue
        foreach($countName in @('repetitions_per_scenario','valid_run_target','maximum_attempts')) {if($authorization.$countName -isnot [int]){throw 'Authorization quota must be a JSON integer.'}}
        if($authorization.issued_at -isnot [string] -or $authorization.issued_at -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$'){throw 'Authorization timestamp requires an explicit timezone.'}
        if($authorization.authorization_id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{7,100}$' -or $authorization.phase -cne $Phase -or ($authorization.scenario_ids -join ',') -cne ($expectedScenarioIds -join ',') -or $authorization.repetitions_per_scenario -ne $expectedRepeatCount -or $authorization.valid_run_target -ne $expectedSampleTarget -or $authorization.maximum_attempts -ne $expectedMaximumAttempts -or $authorization.no_retry -isnot [bool] -or -not $authorization.no_retry -or $authorization.remote_actions -isnot [bool] -or $authorization.remote_actions -or -not [DateTimeOffset]::TryParse($authorization.issued_at,[ref]$issued)) {throw 'Authorization scope or issue timestamp is invalid.'}
        if($authorization.test_only -isnot [bool] -or $authorization.test_only -ne [bool]$ProcessInvoker -or ($authorization.authorization_id -cmatch '^FAKE-' -and -not $ProcessInvoker)) {throw 'Fake authorization is forbidden at the formal boundary.'}
        if($authorization.control_sha256 -cne (Get-CmHash -Path (Join-Path $RepositoryRoot 'evals/expected/continuous-mode-model/frozen-control.json'))){throw 'Authorization control hash drift.'}
        $control=Get-CmFrozenControl $RepositoryRoot
        $selectedEntries=@($control.scenarios|Where-Object {$expectedScenarioIds -contains $_.scenario_id})
        if($selectedEntries.Count -ne $expectedScenarioIds.Count){throw 'Authorized scenario is absent from frozen control.'}
        if($DiagnosticCanary -and [int]$control.runner_managed_roles.maximum_authorized_role_contexts_per_attempt -ne 13){throw 'Diagnostic Runner role limit differs from 13.'}
        if(($authorization.product|ConvertTo-Json -Depth 60 -Compress) -cne ($control.product|ConvertTo-Json -Depth 60 -Compress)){throw 'Explicit product authorization missing or mismatched.'}
        Assert-CmRunnerRoleAuthorization -Expected $control.runner_managed_roles -Authorized $authorization.runner_managed_roles
        foreach($field in @('model','reasoning_effort','sandbox')) {if($authorization.$field -cne $control.$field){throw 'Authorization process controls mismatch.'}}
        if(($authorization.bindings|ConvertTo-Json -Depth 60 -Compress) -cne ($selectedEntries|ConvertTo-Json -Depth 60 -Compress)){throw 'Authorization scenario bindings mismatch.'}
        $claimRoot=Join-Path $RepositoryRoot '.pfc-eval-results/continuous-mode-model-claims';Assert-CmPath $claimRoot (Join-Path $RepositoryRoot '.pfc-eval-results') $RepositoryRoot
        New-Item -ItemType Directory -Path $claimRoot,$ResultDirectory -Force | Out-Null
        $claimName=Get-CmHash -Text $authorization.authorization_id
        $claim=Join-Path $claimRoot ($claimName+'.claim')
        if(Test-Path -LiteralPath $claim){throw 'Authorization already claimed; replay/crash cannot reset attempts.'}
        # Rebuild every selected fixture before acquiring the claim or starting any model.
        foreach($entry in $selectedEntries) {
            $manifest=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepositoryRoot $entry.manifest_path)|ConvertFrom-Json
            $fixture=New-CmFixture $manifest
            try {if($fixture.base_sha -cne $manifest.base_sha){throw 'Physical fixture base does not match authorization.'}}finally{Remove-CmFixture $fixture.path}
        }
        if((Get-CmHash -Path $AuthorizationPath) -cne $authorizationHash){throw 'Authorization changed during preflight.'}
        Write-CmReservation $claim ('authorization_sha256='+$authorizationHash+[Environment]::NewLine+'maximum_attempts='+$expectedMaximumAttempts+[Environment]::NewLine)
        $claimed=$true
        foreach($entry in $selectedEntries) {
            for($repetition=1;$repetition -le $Repeat;$repetition++) {
                if($result.attempts -ge $expectedMaximumAttempts){throw 'Attempt cap reached.'}
                if((Get-CmHash -Path $AuthorizationPath) -cne $authorizationHash){throw 'Authorization changed after claim; no further attempt permitted.'}
                # Revalidate all frozen artifacts between attempts as well as before the first.
                $null=Get-CmFrozenControl $RepositoryRoot
                $manifest=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepositoryRoot $entry.manifest_path)|ConvertFrom-Json
                $fixture=New-CmFixture $manifest
                $sample=$null
                try {
                    $result.attempts++
                    $reservation=Join-Path $claimRoot ($claimName+'.attempt-'+$result.attempts+'.json')
                    Write-CmReservation $reservation (@{scenario_id=$entry.scenario_id;phase=$Phase;repetition=$repetition;context_id=$fixture.context_id;test_only=[bool]$ProcessInvoker}|ConvertTo-Json -Compress)
                    $sample=Invoke-CmModelSample -RepositoryRoot $RepositoryRoot -Manifest $manifest -Fixture $fixture -Phase $Phase -Repetition $repetition -ResultDirectory $ResultDirectory -CodexExecutablePath $CodexExecutablePath -ProcessInvoker $ProcessInvoker
                    if($DiagnosticCanary -and ($sample.runner_child_contexts -gt 13 -or $sample.goalkeeper_resumptions -gt 13 -or $sample.codex_process_invocations -gt 27)){throw 'Diagnostic Runner or Codex process limit exceeded; no retry.'}
                } finally {
                    try {$fixtureEvidence=Save-CmFixtureEvidence -Fixture $fixture -ResultDirectory $ResultDirectory}
                    catch {throw ('Fixture retained after incomplete capture: '+$fixture.context_id+'; '+$_.Exception.Message)}
                    # Keep evidence on disk until both Runner and Goalkeeper lifecycle records are complete.
                    if(Test-CmFixtureCleanupEligible -Sample $sample){Remove-CmFixture $fixture.path}
                }
                $sample|Add-Member -NotePropertyName fixture_evidence -NotePropertyValue $fixtureEvidence
                $sample|Add-Member -NotePropertyName fixture_retained -NotePropertyValue (Test-Path -LiteralPath $fixture.path)
                $sample|Add-Member -NotePropertyName sample_validity -NotePropertyValue 'NOT_AVAILABLE'
                if($sample.runner_trace.status -ceq 'OBSERVED'){$sample.sample_validity='RUNNER_MANAGED_INDEPENDENT_HANDOFF_OBSERVED'}
                elseif(Test-CmSafeIdentityStop $manifest $sample $fixtureEvidence $ResultDirectory){$sample.sample_validity='CM05_IDENTITY_STOP_OBSERVED'}
                else {$result.samples+=$sample;throw 'Required Runner-owned handoff or bounded identity-stop evidence unavailable; no retry. Unknown child lifecycle retains the fixture.'}
                $result.samples+= $sample;$result.valid_samples++
                if(-not $ProcessInvoker -and -not $DiagnosticCanary){$result.formal_samples++}
                Write-PfcUtf8NoBom -Path (Join-Path $ResultDirectory ($claimName+'.normalized.json')) -Content ($result|ConvertTo-Json -Depth 60)
            }
        }
        $result.status=if($ProcessInvoker){'SIMULATED'}else{'COLLECTED'}
        $result.reason='Collection only; independent correctness/evidence review and comparison gates remain NOT_RUN.'
    } catch {
        if($result.attempts -gt 0){$result.status='STOPPED'}
        $result.reason=Convert-CmEvidenceText $_.Exception.Message
    }
    if($claimed){Write-PfcUtf8NoBom -Path (Join-Path $ResultDirectory ($claimName+'.normalized.json')) -Content ($result|ConvertTo-Json -Depth 60)}
    return [pscustomobject]$result
}

function Invoke-ContinuousModeModel {
    $repository=Split-Path -Parent $PSScriptRoot
    $result=Invoke-CmModelDispatch -RepositoryRoot $repository -Phase $Phase -Repeat $Repeat -AuthorizationPath $AuthorizationPath -ResultDirectory (Join-Path $repository '.pfc-eval-results/continuous-mode-model') -CodexExecutablePath $CodexExecutablePath -DiagnosticCanary:$DiagnosticCanary
    return New-PfcResult -ScenarioId 'continuous-mode-model' -Status $(if($result.status -eq 'COLLECTED'){'PARTIAL'}elseif($result.status -eq 'NOT_RUN'){'NOT_RUN'}else{'FAIL'}) -Message ($result|ConvertTo-Json -Depth 60 -Compress)
}

function Invoke-ContinuousModeModelContract {
    . (Join-Path $PSScriptRoot 'tests\ContinuousModeModelContract.Tests.ps1')
    return Invoke-CmModelContractTests -RepositoryRoot (Split-Path -Parent $PSScriptRoot)
}

$results = & (Get-Command ("Invoke-{0}" -f $Suite)).Name
$failed = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0
if ($Suite -in @('ContinuousMode','ContinuousModeWindowsSmoke') -and @($results | Where-Object { $_.Status -cne 'PASS' }).Count -gt 0) { $failed = $true }
if ($Suite -eq 'ContinuousModeModel' -and @($results | Where-Object { $_.Status -cne 'PARTIAL' }).Count -gt 0) { $failed = $true }
Write-PfcSummary -Results @($results) -Json:$Json
if ($failed) { exit 1 }
exit 0
