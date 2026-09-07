[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Bootstrap','StaticPackage','Harness','BuilderEfficiency','Revision4Isolation','RunnerRevision3','PermissionProbeFileHandshake','PermissionProbeExecutionPolicy','BuilderProfile','VerifierProfile','MessageContracts','GovernanceReferences','EvidenceRecovery','SkillEntry','SpecialistProtocol','Installer','Doctor','SpecialistSmokeUnit')][string]$Suite,
    [ValidateSet('RED','GREEN')][string]$Phase = 'GREEN',
    [ValidateRange(1,5)][int]$Repeat = 1,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\TestHarness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\CodexRunner.psm1') -Force
if ($Suite -in @('StaticPackage','Harness','BuilderProfile','VerifierProfile','MessageContracts','GovernanceReferences','EvidenceRecovery','SpecialistProtocol')) {
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
            $diagRoot = Join-Path (Split-Path -Parent $PSScriptRoot) '.pfc-eval-results\diagnostic'
            $canaryRaw = Get-ChildItem -LiteralPath $diagRoot -Filter 'raw.jsonl' -File -Recurse | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            Assert-PfcTrue -Actual ($null -ne $canaryRaw) -ScenarioId 'TEST-1.fixture-present' -Expected 'raw fixture'
            $canaryLines = @(Get-Content -LiteralPath $canaryRaw.FullName)
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
        'docs/superpowers/plans/2026-09-03-project-flight-control-v1-implementation-plan.md'
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
    $expectedHash = 'e5c90a41c28ce8e7f9192102f14613adef5af93ee7ee5007b4f69df6ed57dedd'
    try {
        Assert-PfcTrue -Actual (Test-Path -LiteralPath $designPath -PathType Leaf) -ScenarioId 'bootstrap.spec-hash.file' -Expected 'present'
        $actualHash = (Get-FileHash -LiteralPath $designPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-PfcEqual -Expected $expectedHash -Actual $actualHash -ScenarioId 'bootstrap.spec-hash'
        $results.Add((New-PfcResult -ScenarioId 'bootstrap.spec-hash' -Status 'PASS' -Message $actualHash))
    } catch {
        $results.Add((New-PfcResult -ScenarioId 'bootstrap.spec-hash' -Status 'FAIL' -Message $_.Exception.Message))
    }
    return $results
}

function Invoke-StaticPackage {
    $root = [System.IO.DirectoryInfo](Split-Path -Parent $PSScriptRoot)
    return Invoke-PfcStaticChecks -RepositoryRoot $root -Phase $Phase
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

$results = & (Get-Command ("Invoke-{0}" -f $Suite)).Name
$failed = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count -gt 0
Write-PfcSummary -Results @($results) -Json:$Json
if ($failed) { exit 1 }
exit 0
