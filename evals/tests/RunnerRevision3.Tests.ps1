[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $PSScriptRoot '..\lib\TestHarness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\lib\CodexRunner.psm1') -Force

function E([double]$At,[string]$Type,[string]$ItemType = '',[string]$Message = '') {
    [pscustomobject]@{ at_seconds = $At; type = $Type; item_type = $ItemType; message = $Message }
}
function Check([bool]$Condition,[string]$Id,[string]$Expected = 'PASS') {
    Assert-PfcTrue -Actual $Condition -ScenarioId $Id -Expected $Expected
}
$started = @((E 0 'thread.started'),(E 1 'turn.started'))
$completed = @($started + (E 100 'item.completed' 'agent_message' '{"status":"OK"}') + (E 200 'turn.completed'))

# R3-TIMEOUT-01..09: all timing is virtual; no wall-clock sleeps or process calls.
Check ((Invoke-PfcRunnerLifecycle -Events @() -ProcessCreated:$false).classification -eq 'INVALID_STARTUP_TIMEOUT' -and (Invoke-PfcRunnerLifecycle -Events @() -RawWritable:$false).classification -eq 'INVALID_STARTUP_TIMEOUT') 'R3-TIMEOUT-01.startup-prerequisites'
Check ((Invoke-PfcRunnerLifecycle -Events @((E 0 'thread.started'),(E 1 'turn.started'),(E 121 'error'),(E 121 'turn.completed'))).classification -eq 'VALID') 'R3-TIMEOUT-02.no-old-120-deadline'
Check ((Invoke-PfcRunnerLifecycle -Events @((E 0 'thread.started'),(E 1 'turn.started'),(E 300 'turn.completed'))).classification -eq 'VALID') 'R3-TIMEOUT-03.completion-at-300'
Check ((Invoke-PfcRunnerLifecycle -Events @((E 0 'thread.started'),(E 1 'turn.started'),(E 602 'error'))).classification -eq 'INVALID_PRE_TERMINAL_TIMEOUT') 'R3-TIMEOUT-04.absolute-deadline'
$recovered = Invoke-PfcRunnerLifecycle -Events @($started + (E 100 'error') + (E 599 'turn.completed'))
Check ($recovered.classification -eq 'VALID' -and $recovered.recovered_errors -and $recovered.automatic_retries -eq 0 -and $recovered.process_count -eq 1) 'R3-TIMEOUT-05.recovered-errors'
Check ((Invoke-PfcRunnerLifecycle -Events @($started + (E 100 'error') + (E 601 'error'))).classification -eq 'INVALID_PRE_TERMINAL_TIMEOUT' -and (Invoke-PfcRunnerLifecycle -Events @($started + (E 100 'error') + (E 601 'error'))).transport_status -eq 'UNRECOVERED') 'R3-TIMEOUT-06.errors-do-not-reset'
$failed = Invoke-PfcRunnerLifecycle -Events @($started + (E 2 'turn.failed'))
Check ($failed.classification -eq 'INVALID_TURN_FAILED') 'R3-TIMEOUT-07.turn-failed'
$late = Invoke-PfcRunnerLifecycle -Events @($started + (E 100 'turn.completed') + (E 116 'output.available')) -Output @{ output_at_seconds = 116; schema_valid = $true }
Check ($late.classification -eq 'VALID' -and $late.grace_deadline_seconds -eq 115 -and $late.local_finalization -eq 'DEGRADED' -and $late.process_cleanup -eq 'SAFE_TERMINATE') 'R3-TIMEOUT-08.post-terminal-grace'
$freeze = Invoke-PfcRunnerLifecycle -Events @($started + (E 3 'item.completed' 'agent_message' '{"status":"FIRST"}') + (E 4 'turn.completed') + (E 5 'item.completed' 'agent_message' '{"status":"LATE"}')) -Output @{ output_at_seconds = 4; schema_valid = $true }
Check ($freeze.last_completed_agent_message -eq '{"status":"FIRST"}' -and $freeze.output_source -eq 'OUTPUT_LAST_MESSAGE_FILE') 'R3-TIMEOUT-09.freeze-and-precedence'

# R3 production observability: injected execution proves one process/no retries
# and exposes transport recovery status through the real Invoke-PfcCodexRun path.
$obsRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-r3-observability-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $obsRoot -Force | Out-Null
try {
    $obsPrompt = Join-Path $obsRoot 'prompt.md'; Write-PfcUtf8NoBom -Path $obsPrompt -Content 'fixture'
    $obsSchema = Join-Path $obsRoot 'schema.json'; Write-PfcUtf8NoBom -Path $obsSchema -Content '{"type":"object","required":["status"],"properties":{"status":{"type":"string","enum":["OK"]}},"additionalProperties":false}'
    $script:r3ProcessCalls = 0
    $script:r3ObsOutputPath = Join-Path $obsRoot 'fixture-final.json'
    $obsInvoker = {
        param($args)
        $script:r3ProcessCalls++
        Write-PfcUtf8NoBom -Path $script:r3ObsOutputPath -Content '{"status":"OK"}'
        [pscustomobject]@{ ExitCode = 0; StdOut = "{`"type`":`"thread.started`"}`n{`"type`":`"turn.started`"}`n{`"type`":`"error`",`"message`":`"transient reconnect`"}`n{`"type`":`"error`",`"message`":`"transient reconnect`"}`n{`"type`":`"error`",`"message`":`"transient reconnect`"}`n{`"type`":`"error`",`"message`":`"transient reconnect`"}`n{`"type`":`"turn.completed`"}"; StdErr = ''; OutputPath = $script:r3ObsOutputPath; ProcessCount = 1; AutomaticRetries = 0 }
    }
    $obs = Invoke-PfcCodexRun -WorkingDirectory $obsRoot -PromptPath $obsPrompt -OutputSchemaPath $obsSchema -SandboxMode 'read-only' -ResultDirectory (Join-Path $obsRoot '.pfc-eval-results') -Phase 'RED' -ProcessInvoker $obsInvoker
    Check ($script:r3ProcessCalls -eq 1 -and $obs.process_count -eq 1 -and $obs.automatic_retries -eq 0 -and $obs.transport_status -eq 'RECOVERED') 'R3-OBS-01.one-process-recovered'
} finally { if (Test-Path -LiteralPath $obsRoot) { Remove-Item -LiteralPath $obsRoot -Recurse -Force } }

# R3 production fail-closed classifications retain the legacy messages while
# attaching a machine-readable classification to the thrown exception.
$classificationRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-r3-classification-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classificationRoot -Force | Out-Null
try {
    $classPrompt = Join-Path $classificationRoot 'prompt.md'; Write-PfcUtf8NoBom -Path $classPrompt -Content 'fixture'
    $classSchema = Join-Path $classificationRoot 'schema.json'; Write-PfcUtf8NoBom -Path $classSchema -Content '{"type":"object","required":["status"],"properties":{"status":{"type":"string","enum":["OK"]}},"additionalProperties":false}'
    $badSchemaInvoker = { param($args) [pscustomobject]@{ StdOut = '{"type":"turn.completed"}'; StdErr = ''; OutputPath = $null } }
    $caught = $null
    try { Invoke-PfcCodexRun -WorkingDirectory $classificationRoot -PromptPath $classPrompt -OutputSchemaPath $classSchema -SandboxMode 'read-only' -ResultDirectory (Join-Path $classificationRoot '.pfc-eval-results') -Phase 'RED' -ProcessInvoker $badSchemaInvoker | Out-Null } catch { $caught = $_.Exception }
    Check ($null -ne $caught -and $caught.Data['classification'] -eq 'INVALID_SCHEMA') 'R3-OBS-02.schema-classification'
    $bindingInvoker = { param($args) [pscustomobject]@{ StdOut = '{"type":"turn.completed"}'; StdErr = ''; OutputPath = $null; FixtureBindingValid = $false } }
    $caught = $null
    try { Invoke-PfcCodexRun -WorkingDirectory $classificationRoot -PromptPath $classPrompt -OutputSchemaPath $classSchema -SandboxMode 'read-only' -ResultDirectory (Join-Path $classificationRoot '.pfc-eval-results') -Phase 'RED' -ProcessInvoker $bindingInvoker | Out-Null } catch { $caught = $_.Exception }
    Check ($null -ne $caught -and $caught.Data['classification'] -eq 'INVALID_FIXTURE_BINDING') 'R3-OBS-03.fixture-classification'
    $normalizationInvoker = { param($args) [pscustomobject]@{ StdOut = '{"type":"turn.completed"}'; StdErr = ''; OutputPath = $null; NormalizationValid = $false } }
    $caught = $null
    try { Invoke-PfcCodexRun -WorkingDirectory $classificationRoot -PromptPath $classPrompt -OutputSchemaPath $classSchema -SandboxMode 'read-only' -ResultDirectory (Join-Path $classificationRoot '.pfc-eval-results') -Phase 'RED' -ProcessInvoker $normalizationInvoker | Out-Null } catch { $caught = $_.Exception }
    Check ($null -ne $caught -and $caught.Data['classification'] -eq 'INVALID_NORMALIZATION') 'R3-OBS-04.normalization-classification'
    $worktreeInvoker = { param($args) [pscustomobject]@{ StdOut = '{"type":"turn.completed"}'; StdErr = ''; OutputPath = $null; WorktreeContaminationDetected = $true } }
    $caught = $null
    try { Invoke-PfcCodexRun -WorkingDirectory $classificationRoot -PromptPath $classPrompt -OutputSchemaPath $classSchema -SandboxMode 'read-only' -ResultDirectory (Join-Path $classificationRoot '.pfc-eval-results') -Phase 'RED' -ProcessInvoker $worktreeInvoker | Out-Null } catch { $caught = $_.Exception }
    Check ($null -ne $caught -and $caught.Data['classification'] -eq 'INVALID_WORKTREE_CONTAMINATION') 'R3-OBS-05.worktree-classification'
    $cleanupInvoker = { param($args) [pscustomobject]@{ StdOut = '{"type":"turn.completed"}'; StdErr = ''; OutputPath = $null; ProcessCleanupValid = $false } }
    $caught = $null
    try { Invoke-PfcCodexRun -WorkingDirectory $classificationRoot -PromptPath $classPrompt -OutputSchemaPath $classSchema -SandboxMode 'read-only' -ResultDirectory (Join-Path $classificationRoot '.pfc-eval-results') -Phase 'RED' -ProcessInvoker $cleanupInvoker | Out-Null } catch { $caught = $_.Exception }
    Check ($null -ne $caught -and $caught.Data['classification'] -eq 'INVALID_PROCESS_CLEANUP') 'R3-OBS-06.cleanup-classification'
} finally { if (Test-Path -LiteralPath $classificationRoot) { Remove-Item -LiteralPath $classificationRoot -Recurse -Force } }

$control = Get-Content -Raw (Join-Path $repoRoot 'evals\schemas\schema-control.json') | ConvertFrom-Json
Check ($control.eval_contract_revision -eq 4 -and $control.formal_schema_revision -eq 2) 'R3-CONTROL-01.revision-binding'
Check ($control.runner.startup_timeout_seconds -eq 90 -and $control.runner.pre_terminal_timeout_seconds -eq 600 -and $control.runner.post_terminal_grace_seconds -eq 15 -and $control.runner.idle_timeout -eq 'DISABLED') 'R3-CONTROL-02.timing-controls'
 $runnerSource = Get-Content -Raw (Join-Path $repoRoot 'evals\lib\CodexRunner.psm1')
Check ($control.runner.automatic_retries -eq 0 -and $control.runner.model -and $control.runner.reasoning_effort -and $control.runner.sandbox -and $control.runner.project_doc_max_bytes -eq 0 -and $runnerSource -notmatch 'TimeoutSeconds\s*=\s*120') 'R3-CONTROL-03.execution-controls'
$schemaPath = Join-Path $repoRoot 'evals\schemas\eval-run.schema.json'; $builderPath = Join-Path $repoRoot 'evals\schemas\builder-report.schema.json'
$expectedEval = 'd28a58bb6f3b081268883ff4cf984b685297b6806fa184044e6e1fe79bb02bd8'; $expectedBuilder = '96020cdc296f788e4a7103f1273fdfcd083b5a3f692e8cd73be2ad9317f1ac89'
Check ($control.schemas.eval_run.sha256 -eq $expectedEval -and $control.schemas.builder_report.sha256 -eq $expectedBuilder -and (Get-FileHash $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedEval -and (Get-FileHash $builderPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedBuilder) 'R3-CONTROL-04.frozen-schema-hashes'
foreach ($manifestId in @('EFF-01','EFF-02','EFF-03','EFF-04','EFF-05','EFF-06','EFF-07')) {
    $entry = $control.scenario_manifests.$manifestId
    $manifestPath = Join-Path $repoRoot ($entry.relative_path.Replace('/','\'))
    $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
    Check ($entry.sha256 -eq (Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -and $manifest.eval_contract_revision -eq 4 -and $manifest.controls.startup_timeout_seconds -eq 90 -and $manifest.controls.pre_terminal_timeout_seconds -eq 600 -and $manifest.controls.post_terminal_grace_seconds -eq 15 -and $manifest.controls.automatic_retries -eq 0) ('R3-CONTROL-04.' + $manifestId + '.manifest-binding')
}

'RUNNER_REVISION3_TESTS=17/17 PASS'
