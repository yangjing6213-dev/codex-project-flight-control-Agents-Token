[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $PSScriptRoot '..\lib\TestHarness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\lib\CodexRunner.psm1') -Force

function Write-TestSchema {
    param([Parameter(Mandatory = $true)]$Root)
    $path = Join-Path ([IO.Path]::GetTempPath()) ('pfc-strict-' + [guid]::NewGuid().ToString('N') + '.json')
    Write-PfcUtf8NoBom -Path $path -Content ($Root | ConvertTo-Json -Depth 20 -Compress)
    return $path
}
function Assert-StrictResult {
    param($Schema,[string]$Expected,[string]$Id)
    $path = Write-TestSchema $Schema
    try { $result = Get-PfcStrictSchemaPreflight -Path $path; Assert-PfcEqual -Expected $Expected -Actual $result.strict_schema_preflight -ScenarioId $Id }
    finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}
$valid = [ordered]@{ type='object'; required=@('status'); properties=[ordered]@{ status=[ordered]@{ type=@('string','null') } }; additionalProperties=$false }
$rootAdditional = [ordered]@{ type='object'; required=@('status'); properties=[ordered]@{ status=[ordered]@{ type=@('string','null') } }; additionalProperties=$true }
Assert-StrictResult $rootAdditional 'FAIL' 'STRICT-01.root-additional'
$nestedAdditional = [ordered]@{ type='object'; required=@('nested'); properties=[ordered]@{ nested=[ordered]@{ type='object'; required=@('value'); properties=[ordered]@{ value=[ordered]@{type='string'} }; additionalProperties=$true } }; additionalProperties=$false }
Assert-StrictResult $nestedAdditional 'FAIL' 'STRICT-02.nested-additional'
$arrayAdditional = [ordered]@{ type='object'; required=@('items'); properties=[ordered]@{ items=[ordered]@{ type='array'; items=[ordered]@{ type='object'; required=@('value'); properties=[ordered]@{ value=[ordered]@{type='string'} }; additionalProperties=$true } } }; additionalProperties=$false }
Assert-StrictResult $arrayAdditional 'FAIL' 'STRICT-03.array-item-additional'
$missingRequired = [ordered]@{ type='object'; required=@(); properties=[ordered]@{ status=[ordered]@{type='string'} }; additionalProperties=$false }
Assert-StrictResult $missingRequired 'FAIL' 'STRICT-04.missing-required'
Assert-StrictResult $valid 'PASS' 'STRICT-05.nullable-required'
$rootAnyOf = [ordered]@{ anyOf=@($valid); oneOf=@($valid); type='object'; required=@(); properties=[ordered]@{}; additionalProperties=$false }
Assert-StrictResult $rootAnyOf 'FAIL' 'STRICT-06.root-anyof'
$schemaPath = Join-Path $repoRoot 'evals\schemas\eval-run.schema.json'
$builderSchemaPath = Join-Path $repoRoot 'evals\schemas\builder-report.schema.json'
$controlPath = Join-Path $repoRoot 'evals\schemas\schema-control.json'
$control = Get-Content -Raw -LiteralPath $controlPath | ConvertFrom-Json
Assert-PfcEqual -Expected 4 -Actual $control.eval_contract_revision -ScenarioId 'STRICT-07.control.eval-revision'
Assert-PfcEqual -Expected 2 -Actual $control.formal_schema_revision -ScenarioId 'STRICT-07.control.formal-revision'
Assert-PfcEqual -Expected $control.schemas.eval_run.sha256 -Actual ((Get-FileHash -Algorithm SHA256 -LiteralPath $schemaPath).Hash.ToLowerInvariant()) -ScenarioId 'STRICT-07.eval-schema-hash'
Assert-PfcEqual -Expected $control.schemas.builder_report.sha256 -Actual ((Get-FileHash -Algorithm SHA256 -LiteralPath $builderSchemaPath).Hash.ToLowerInvariant()) -ScenarioId 'STRICT-07.builder-schema-hash'
Assert-PfcEqual -Expected 'PASS' -Actual (Get-PfcSchemaPreflight -Path $schemaPath).strict_schema_preflight -ScenarioId 'STRICT-07.eval-schema-strict'
Assert-PfcEqual -Expected 'PASS' -Actual (Get-PfcSchemaPreflight -Path $builderSchemaPath).strict_schema_preflight -ScenarioId 'STRICT-07.builder-schema-strict'
$allSchemas = @('EFF-01-targeted-context','EFF-02-reuse-before-create','EFF-03-minimal-diff','EFF-04-delta-rework','EFF-05-incremental-verification','EFF-06-debugging-convergence','EFF-07-structured-recovery')
foreach ($name in $allSchemas) { $contract = Get-Content -Raw (Join-Path $repoRoot ('evals\scenarios\builder-efficiency\' + $name + '\scenario.json')) | ConvertFrom-Json; Assert-PfcEqual -Expected $contract.schema_sha256 -Actual $control.schemas.eval_run.sha256 -ScenarioId ('STRICT-07.' + $contract.scenario_id); Assert-PfcEqual -Expected 4 -Actual $contract.eval_contract_revision -ScenarioId ('STRICT-07.' + $contract.scenario_id + '.revision') }
$schemaBytes = [IO.File]::ReadAllBytes($schemaPath); Assert-PfcTrue -Actual (-not ($schemaBytes.Length -ge 3 -and $schemaBytes[0] -eq 239 -and $schemaBytes[1] -eq 187 -and $schemaBytes[2] -eq 191)) -ScenarioId 'STRICT-08.no-bom' -Expected 'UTF-8 without BOM'
$strict = Get-PfcStrictSchemaPreflight -Path $schemaPath; Assert-PfcEqual -Expected 'PASS' -Actual $strict.strict_schema_preflight -ScenarioId 'STRICT-09.dynamic-map-array'
$unsupported = [ordered]@{ type='object'; required=@(); properties=[ordered]@{}; additionalProperties=$false; oneOf=@() }; Assert-StrictResult $unsupported 'FAIL' 'STRICT-09.unsupported-keyword'
$schema = Get-Content -Raw $schemaPath | ConvertFrom-Json; $valueTypes = @($schema.properties.metrics.items.properties.value.type); Assert-PfcTrue -Actual ($valueTypes -contains 'null') -ScenarioId 'STRICT-10.null-unavailable-compatibility' -Expected 'nullable value'
$normalized = Convert-PfcStructuredMetrics -Metrics @([pscustomobject]@{key='missing_metric';value=$null},[pscustomobject]@{key='count';value=2}); Assert-PfcEqual -Expected 'NOT_AVAILABLE' -Actual $normalized.missing_metric -ScenarioId 'STRICT-10.null-normalization'; Assert-PfcEqual -Expected 2 -Actual $normalized.count -ScenarioId 'STRICT-10.value-normalization'
# V2 assets are checked separately from the frozen V1 schema controls.
$v2Names = @('continuous-authorization','wave-plan','continuation-checkpoint','issue-classification','wave-report')
foreach ($name in $v2Names) {
    $path = Join-Path $repoRoot ('evals/schemas/' + $name + '.schema.json')
    Assert-PfcTrue -Actual (Test-Path -LiteralPath $path) -ScenarioId ('V2.missing-schema.' + $name) -Expected 'V2 schema present'
    Assert-PfcEqual -Expected 'PASS' -Actual (Get-PfcStrictSchemaPreflight -Path $path).strict_schema_preflight -ScenarioId ('V2.strict.' + $name)
}
Import-Module (Join-Path $PSScriptRoot '../lib/StaticChecks.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../lib/TestHarness.psm1') -Force
$bindingResults = @(Invoke-PfcV2ContractChecks -RepositoryRoot ([IO.DirectoryInfo]$repoRoot))
foreach ($result in $bindingResults) { Assert-PfcEqual -Expected 'PASS' -Actual $result.Status -ScenarioId $result.ScenarioId }
$productPaths = @(& (Get-Module StaticChecks) { param($root) Get-PfcTextFiles -Root ([IO.DirectoryInfo]$root) | ForEach-Object { $_.FullName } } $repoRoot)
Assert-PfcTrue -Actual ($productPaths -notcontains (Join-Path $repoRoot 'task-3-report.md')) -ScenarioId 'V2.scan.historical-excluded' -Expected 'protected root path never enters content scan'
$ignoredRoot = (Join-Path $repoRoot '.superpowers') + [IO.Path]::DirectorySeparatorChar
Assert-PfcEqual -Expected 0 -Actual @($productPaths | Where-Object { $_.StartsWith($ignoredRoot,[StringComparison]::OrdinalIgnoreCase) }).Count -ScenarioId 'V2.scan.ignored-reports-excluded'
Assert-PfcTrue -Actual ($productPaths -contains (Join-Path $repoRoot 'evals\schemas\continuous-authorization.schema.json')) -ScenarioId 'V2.scan.product-retained' -Expected 'product schema remains scanned'
$v2Examples = @'
{
  "continuous-authorization": {
    "schema_version": "pfc.continuous-authorization.v1",
    "authorization_id": "AUTH-20260920-001",
    "authorization_status": "ACTIVE",
    "execution_policy": "CONTINUOUS",
    "invocation_mode": "START",
    "goal": {
      "goal_id": "GOAL-001",
      "goal_version": 3
    },
    "scope": {
      "type": "MILESTONE_RANGE",
      "from": "A-015",
      "to": "A-030",
      "stop_gate": "A-030"
    },
    "repository": {
      "identity_algorithm": "PFC_GIT_COMMON_DIR_SHA256_V1",
      "repository_identity": "0000000000000000000000000000000000000000000000000000000000000000",
      "authorized_base_checkpoint_sha": "0000000000000000000000000000000000000000",
      "source_branch": "main",
      "write_branch_policy": "MILESTONE_WORKTREE_ONLY",
      "write_branch_namespace": "codex/pfc/AUTH-20260920-001/",
      "default_branch_write": false
    },
    "paths": {
      "hash_algorithm": "PFC_REPO_PATH_SET_SHA256_V1",
      "writable_paths_hash": "0000000000000000000000000000000000000000000000000000000000000000",
      "forbidden_paths_hash": "0000000000000000000000000000000000000000000000000000000000000000"
    },
    "permissions": {
      "local_commit": true,
      "existing_dependency_use": true,
      "planned_dependency_install": false,
      "non_destructive_migration": true,
      "automatic_repair": true
    },
    "limits": {
      "max_wave_size": 5,
      "max_builder_code_repair_attempts": 2,
      "max_auto_rework_rounds": 2,
      "max_candidate_revisions": 3,
      "max_consecutive_blocked_milestones": 1
    },
    "forbidden": {
      "push": true,
      "merge": true,
      "release": true,
      "deploy": true,
      "destructive_migration": true,
      "administrator_action": true,
      "paid_action": true,
      "cross_project_write": true
    },
    "approval": {
      "approved_by": "USER",
      "approved_at": "2026-09-20T00:00:00Z",
      "source_decision_id": "DEC-001"
    },
    "invalidation_triggers": [
      "CONTRACT_CHANGE",
      "AUTHORIZED_SCOPE_EXHAUSTED",
      "STOP_GATE_REACHED",
      "BASELINE_DRIFT",
      "BRANCH_CHANGE",
      "UNKNOWN_DIRTY_WORKTREE",
      "USER_PAUSE",
      "HARD_BLOCKER",
      "GOAL_CHANGE"
    ]
  },
  "wave-plan": {
    "schema_version": "pfc.wave-plan.v1",
    "wave_id": "WAVE-001",
    "authorization_id": "AUTH-20260920-001",
    "base_checkpoint_sha": "0000000000000000000000000000000000000000",
    "goal_id": "GOAL-001",
    "stop_gate": "A-030",
    "milestones": [
      {
        "milestone_id": "A-015",
        "contract_id": "MC-015",
        "contract_version": 1,
        "risk_level": "LOW",
        "dependencies": [],
        "exact_branch": "codex/pfc/AUTH-20260920-001/A-015",
        "worktree_identity_algorithm": "PFC_WORKTREE_ROOT_SHA256_V1",
        "worktree_identity": "0000000000000000000000000000000000000000000000000000000000000000",
        "validation_plan": [
          {
            "tier": "T1",
            "required": true,
            "applicability_reason": "Required by approved risk policy",
            "checks": [
              "SYNTHETIC check; replace with approved command"
            ],
            "result": "NOT_RUN",
            "evidence": []
          },
          {
            "tier": "T2",
            "required": true,
            "applicability_reason": "Required by approved risk policy",
            "checks": [
              "SYNTHETIC check; replace with approved command"
            ],
            "result": "NOT_RUN",
            "evidence": []
          }
        ]
      }
    ],
    "wave_validation": {
      "tier": "T3",
      "required": true,
      "applicability_reason": "Required by approved risk policy",
      "checks": [
        "SYNTHETIC check; replace with approved command"
      ],
      "result": "NOT_RUN",
      "evidence": []
    }
  },
  "continuation-checkpoint": {
    "schema_version": "pfc.continuation-checkpoint.v1",
    "authorization_id": "AUTH-20260920-001",
    "control_run_id": "RUN-001",
    "lease_epoch": 1,
    "wave_id": "WAVE-001",
    "milestone_id": "A-015",
    "previous_accepted_checkpoint_sha": "FIRST_MILESTONE",
    "current_milestone_base_sha": "0000000000000000000000000000000000000000",
    "expected_builder_start_sha": "0000000000000000000000000000000000000000",
    "repair_budget": {
      "builder_code_repair_attempts": 0,
      "auto_rework_rounds": 0,
      "candidate_revisions": 0
    },
    "recovery_manifest": {
      "recovery_package_reference": "RECOVERY-SYNTHETIC-001",
      "git_status": [
        {
          "path": "src/example.txt",
          "original_path": "NONE",
          "status": " M"
        }
      ],
      "files": [
        {
          "path": "src/example.txt",
          "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
          "size_bytes": 1,
          "recovery_copy": "files/example.txt",
          "classification": "ACTIVE"
        }
      ],
      "allowed_paths": [
        "src/example.txt"
      ]
    },
    "updated_at": "2026-09-20T00:00:00Z"
  },
  "issue-classification": {
    "schema_version": "pfc.issue-classification.v1",
    "classification": "UNCLASSIFIED",
    "evidence": [
      "SYNTHETIC observation; collect minimum evidence"
    ],
    "affected_scope": [
      "A-015"
    ],
    "blocking_scope": "MILESTONE",
    "fallback_reference": "NONE",
    "next_action": "PAUSE_COLLECT_EVIDENCE"
  },
  "wave-report": {
    "schema_version": "pfc.wave-report.v1",
    "wave_id": "WAVE-001",
    "authorization_id": "AUTH-20260920-001",
    "base_checkpoint_sha": "0000000000000000000000000000000000000000",
    "final_checkpoint_sha": "0000000000000000000000000000000000000000",
    "milestones": [
      {
        "milestone_id": "A-015",
        "candidate_sha": "0000000000000000000000000000000000000000",
        "evidence_sha": "0000000000000000000000000000000000000000",
        "acceptance_sha": "0000000000000000000000000000000000000000",
        "accepted_checkpoint_sha": "0000000000000000000000000000000000000000",
        "result": "PASS"
      }
    ],
    "t3_result": {
      "tier": "T3",
      "required": true,
      "applicability_reason": "Required by approved risk policy",
      "checks": [
        "SYNTHETIC check; replace with approved command"
      ],
      "result": "PASS",
      "evidence": [
        {
          "evidence_id": "EVID-001",
          "candidate_sha": "0000000000000000000000000000000000000000",
          "reference": "SYNTHETIC evidence; replace with actual record"
        }
      ]
    },
    "stop_gate_result": {
      "stop_gate": "A-030",
      "reached": false
    },
    "next_action": "PAUSE"
  }
}
'@ | ConvertFrom-Json

function Copy-V2Value($Value) {
    $copy = $Value | ConvertTo-Json -Depth 40 -Compress | ConvertFrom-Json
    if ($copy.PSObject.Properties['approval'] -and $copy.approval.approved_at -is [datetime]) {
        $copy.approval.approved_at = $copy.approval.approved_at.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    foreach ($field in @('approved_at','updated_at')) {
        if ($copy.PSObject.Properties[$field] -and $copy.$field -is [datetime]) { $copy.$field = $copy.$field.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
    return $copy
}
function Test-PfcSchemaValue($Value,$Schema) {
    return (& (Get-Module CodexRunner) { param($v,$s) Test-PfcSchemaValue -Value $v -Schema $s } $Value $Schema)
}
function Test-PfcSchemaShape($Value,[string]$SchemaPath) {
    $schema = Get-Content -Raw -Encoding UTF8 $SchemaPath | ConvertFrom-Json
    return (Test-PfcV2SchemaValue -Value $Value -Schema $schema)
}
# Mutate every declared node, including nested arrays: no permissive object can hide.
function Assert-V2Nodes($Schema, $Value, [string]$Id) {
    Assert-PfcTrue -Actual (Test-PfcSchemaValue -Schema $Schema -Value $Value) -ScenarioId ($Id + '.valid') -Expected 'valid node'
    Assert-PfcTrue -Actual (-not (Test-PfcSchemaValue -Schema $Schema -Value $null)) -ScenarioId ($Id + '.null') -Expected 'required value cannot be null'
    if ($Schema.type -eq 'object') {
        foreach ($field in @($Schema.properties.PSObject.Properties)) {
            $bad = Copy-V2Value $Value
            $bad.PSObject.Properties.Remove($field.Name)
            Assert-PfcTrue -Actual (-not (Test-PfcSchemaValue -Schema $Schema -Value $bad)) -ScenarioId ($Id + '.missing.' + $field.Name) -Expected 'required field rejected'
            $wrongCase = Copy-V2Value $Value
            $fieldValue = $wrongCase.($field.Name)
            $wrongCase.PSObject.Properties.Remove($field.Name)
            $wrongCase | Add-Member -NotePropertyName $field.Name.ToUpperInvariant() -NotePropertyValue $fieldValue
            Assert-PfcTrue -Actual (-not (Test-PfcV2SchemaValue -Schema $Schema -Value $wrongCase)) -ScenarioId ($Id + '.wrong-case.' + $field.Name) -Expected 'case-sensitive field names'
            Assert-V2Nodes $field.Value $Value.($field.Name) ($Id + '.' + $field.Name)
        }
        $bad = Copy-V2Value $Value
        $bad | Add-Member -NotePropertyName unexpected -NotePropertyValue 'extra'
        Assert-PfcTrue -Actual (-not (Test-PfcSchemaValue -Schema $Schema -Value $bad)) -ScenarioId ($Id + '.extra') -Expected 'extra field rejected'
    } elseif ($Schema.type -eq 'array') {
        foreach ($entry in $Value) { Assert-V2Nodes $Schema.items $entry ($Id + '.item') }
    } else {
        if ($null -ne $Schema.enum) {
            $bad = if ($Schema.type -eq 'integer') { 99 } elseif ($Schema.type -eq 'boolean') { -not $Value } else { 'INVALID_VALUE' }
            if (@($Schema.enum) -notcontains $bad) {
                Assert-PfcTrue -Actual (-not (Test-PfcSchemaValue -Schema $Schema -Value $bad)) -ScenarioId ($Id + '.enum') -Expected 'invalid enum rejected'
            }
        }
        if ($Schema.pattern) {
            Assert-PfcTrue -Actual (-not (Test-PfcSchemaValue -Schema $Schema -Value '')) -ScenarioId ($Id + '.empty') -Expected 'empty identity/text rejected'
            if ($Schema.pattern -match '\\z') {
                foreach ($suffix in @([string][char]10,([string][char]13 + [char]10))) {
                    Assert-PfcTrue -Actual (-not (Test-PfcSchemaValue -Schema $Schema -Value ($Value + $suffix))) -ScenarioId ($Id + '.trailing-newline') -Expected 'exact end of input'
                }
            }
        }
    }
}
foreach ($entry in $v2Examples.PSObject.Properties) {
    $entry.Value = Copy-V2Value $entry.Value
    $path = Join-Path $repoRoot ('evals/schemas/' + $entry.Name + '.schema.json')
    $schema = Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
    Assert-V2Nodes $schema $entry.Value ('V2.' + $entry.Name)
    Assert-PfcTrue -Actual (Test-PfcV2ControlSemantics -Name $entry.Name -Value $entry.Value) -ScenarioId ('V2.semantic.valid.' + $entry.Name) -Expected 'valid semantic contract'
}
function Assert-V2Rejected([string]$Name, [scriptblock]$Mutation, [string]$Id) {
    $value = Copy-V2Value $v2Examples.$Name
    & $Mutation $value
    $shape = Test-PfcSchemaShape -Value $value -SchemaPath (Join-Path $repoRoot ('evals/schemas/' + $Name + '.schema.json'))
    $semantic = Test-PfcV2ControlSemantics -Name $Name -Value $value
    Assert-PfcTrue -Actual (-not ($shape -and $semantic)) -ScenarioId ('V2.reject.' + $Id) -Expected 'invalid contract rejected'
}
foreach ($runtime in @('control_run_id','lease_epoch','wave_id','milestone_id')) {
    Assert-V2Rejected 'continuous-authorization' { param($v) $v | Add-Member -NotePropertyName $runtime -NotePropertyValue 'runtime' } ('stable.' + $runtime)
}
Assert-V2Rejected 'continuous-authorization' { param($v) $v.invocation_mode='CONTINUOUS_MODE' } 'fifth-mode'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.authorization_status='BLOCKED' } 'runtime-status-as-authorization'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.repository.repository_identity='invalid-path-identity' } 'identity-hash'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.paths.writable_paths_hash='A' * 64 } 'uppercase-path-hash'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.repository.authorized_base_checkpoint_sha='short' } 'sha'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.authorization_id='bad id' } 'id'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.limits.max_wave_size=6 } 'wave-budget'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.goal.goal_version=0 } 'goal-version'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.approval.approved_at='2026-02-30T00:00:00Z' } 'invalid-date'
Assert-V2Rejected 'continuous-authorization' { param($v) $v.invalidation_triggers=@('GOAL_CHANGE') } 'missing-invalidation'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones=@() } 'empty-wave'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones=@($v.milestones[0]) * 6 } 'oversize-wave'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones=@($v.milestones[0]) * 2 } 'duplicate-milestone'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones[0].exact_branch='main' } 'default-branch'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones[0].exact_branch='codex/pfc/AUTH-OTHER/A-015' } 'wrong-authorization-branch'
Assert-V2Rejected 'wave-plan' { param($v) $v.wave_validation.required=$false } 'required-wave-t3'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones[0].validation_plan[0].required=$false } 'required-t1'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones[0].risk_level='HIGH' } 'high-missing-gates'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones[0].risk_level='MEDIUM' } 'medium-missing-rollback'
Assert-V2Rejected 'wave-plan' { param($v) $v.wave_validation.result='N/A' } 'fifth-result'
Assert-V2Rejected 'wave-plan' { param($v) $v.wave_validation.result='PASS' } 'pass-without-evidence'
Assert-V2Rejected 'wave-plan' { param($v) $v.milestones[0].dependencies=@('A-015') } 'self-dependency'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.lease_epoch=-1 } 'negative-lease'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.previous_accepted_checkpoint_sha='1' * 40 } 'broken-accepted-base-chain'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.repair_budget.builder_code_repair_attempts=3 } 'builder-budget'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.repair_budget.auto_rework_rounds=3 } 'rework-budget'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.repair_budget.candidate_revisions=4 } 'candidate-r4'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.recovery_manifest.files[0].path='../escape' } 'path-traversal'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.recovery_manifest.files[0].size_bytes=-1 } 'negative-size'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.recovery_manifest.files[0].recovery_copy='' } 'missing-recovery-copy'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.recovery_manifest.allowed_paths=@() } 'unapproved-recovery-path'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.recovery_manifest.files=@() } 'missing-file-manifest'
Assert-V2Rejected 'issue-classification' { param($v) $v.classification='SECURITY_OR_DATA_RISK'; $v.next_action='CONTINUE' } 'security-stop'
Assert-V2Rejected 'issue-classification' { param($v) $v.classification='EXTERNAL_DEPENDENCY_FAILURE'; $v.next_action='CONTINUE'; $v.blocking_scope='NONE' } 'unapproved-fallback'
Assert-V2Rejected 'issue-classification' { param($v) $v.evidence=@() } 'classification-evidence'
Assert-V2Rejected 'wave-report' { param($v) $v.milestones[0].acceptance_sha='1' * 40 } 'stale-acceptance'
Assert-V2Rejected 'wave-report' { param($v) $v.final_checkpoint_sha='1' * 40 } 'wrong-final-checkpoint'
Assert-V2Rejected 'wave-report' { param($v) $v.next_action='SELECT_NEXT_WAVE'; $v.t3_result.result='FAIL' } 'advance-after-t3-fail'
Assert-V2Rejected 'wave-report' { param($v) $v.next_action='SELECT_NEXT_WAVE'; $v.stop_gate_result.reached=$true } 'advance-after-stop'
# Schema-valid non-applicability is explicit, never a fifth result; policy still requires T1/T2/T3.
$optional = Copy-V2Value $v2Examples.'wave-plan'.milestones[0].validation_plan[0]
$optional.tier='T4'; $optional.required=$false; $optional.applicability_reason='LOW milestone; no phase Gate'
$low = Copy-V2Value $v2Examples.'wave-plan'; $low.milestones[0].validation_plan += $optional
Assert-PfcTrue -Actual (Test-PfcV2ControlSemantics 'wave-plan' $low) -ScenarioId 'V2.optional.valid' -Expected 'explicit non-applicability'
$low.milestones[0].validation_plan[-1].applicability_reason=' '
Assert-PfcTrue -Actual (-not (Test-PfcV2ControlSemantics 'wave-plan' $low)) -ScenarioId 'V2.optional.reason' -Expected 'nonempty applicability reason'
# Distinct start SHA slots are intentional: rework/resume can start at a later Candidate.
$resume = Copy-V2Value $v2Examples.'continuation-checkpoint'
$resume.previous_accepted_checkpoint_sha='1' * 40
$resume.current_milestone_base_sha='1' * 40
$resume.expected_builder_start_sha='2' * 40
$resume.repair_budget.builder_code_repair_attempts=2
$resume.repair_budget.candidate_revisions=3
Assert-PfcTrue -Actual (Test-PfcV2ControlSemantics 'continuation-checkpoint' $resume) -ScenarioId 'V2.resume.distinct-slots' -Expected 'independent persisted counters and SHA slots'
$medium = Copy-V2Value $v2Examples.'wave-plan'
$medium.milestones[0].risk_level='MEDIUM'
$rollback = Copy-V2Value $medium.wave_validation
$rollback.tier='ROLLBACK'
$medium.milestones[0].validation_plan += $rollback
Assert-PfcTrue -Actual (Test-PfcV2ControlSemantics 'wave-plan' $medium) -ScenarioId 'V2.medium.valid' -Expected 'MEDIUM with required rollback'
$high = Copy-V2Value $v2Examples.'wave-plan'
$high.milestones[0].risk_level='HIGH'
foreach ($tier in @('T3','T4','FAULT_INJECTION','USER_GATE')) {
    $record = Copy-V2Value $high.wave_validation
    $record.tier=$tier
    $high.milestones[0].validation_plan += $record
}
Assert-PfcTrue -Actual (Test-PfcV2ControlSemantics 'wave-plan' $high) -ScenarioId 'V2.high.valid' -Expected 'HIGH with T1-T4 and gates'
foreach ($case in @(@{plan=$medium; count=4},@{plan=$high; count=2})) {
    $expanded = Copy-V2Value $case.plan
    $expanded.milestones=@()
    for ($index=1; $index -le $case.count; $index++) {
        $item = Copy-V2Value $case.plan.milestones[0]
        $item.milestone_id='A-00' + $index
        $item.exact_branch='codex/pfc/AUTH-20260920-001/' + $item.milestone_id
        $item.worktree_identity=([string]$index) * 64
        $expanded.milestones += $item
    }
    Assert-PfcTrue -Actual (-not (Test-PfcV2ControlSemantics 'wave-plan' $expanded)) -ScenarioId 'V2.risk.cardinality' -Expected 'risk cap rejected independently of duplicate identities'
}
$unicodeRecovery = Copy-V2Value $v2Examples.'continuation-checkpoint'
$unicodePath = 'src/' + [char]0x6587 + [char]0x4ef6 + ' name.txt'
$unicodeRecovery.recovery_manifest.git_status[0].path = $unicodePath
$unicodeRecovery.recovery_manifest.files[0].path = $unicodePath
$unicodeRecovery.recovery_manifest.allowed_paths = @($unicodePath)
Assert-PfcTrue -Actual (Test-PfcSchemaShape -Value $unicodeRecovery -SchemaPath (Join-Path $repoRoot 'evals/schemas/continuation-checkpoint.schema.json')) -ScenarioId 'V2.path.unicode-and-space' -Expected 'normalized Unicode paths supported'
Assert-PfcTrue -Actual (Test-PfcV2ControlSemantics 'continuation-checkpoint' $unicodeRecovery) -ScenarioId 'V2.path.unicode-semantic' -Expected 'normalized Unicode paths supported'
Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.recovery_manifest.files[0].path='SRC/example.txt' } 'noncanonical-path-case'
# Mutate disposable copies of only the V2 assets; never copy historical or ignored reports.
$reviewFailures = New-Object System.Collections.Generic.List[string]
function Assert-ReviewRegression([string]$Id, [scriptblock]$Assertion) {
    try { & $Assertion; Write-Output ($Id + '=PASS') }
    catch { $reviewFailures.Add($Id + ': ' + $_.Exception.Message); Write-Output ($Id + '=FAIL: ' + $_.Exception.Message) }
}
Assert-ReviewRegression 'I1.comma-path-correspondence' {
    $comma = Copy-V2Value $v2Examples.'continuation-checkpoint'
    $comma.recovery_manifest.git_status = @(
        [pscustomobject]@{path='a';original_path='NONE';status=' M'},
        [pscustomobject]@{path='b,c';original_path='NONE';status=' M'}
    )
    $one = Copy-V2Value $comma.recovery_manifest.files[0]; $one.path='a,b'; $one.recovery_copy='files/a'
    $two = Copy-V2Value $one; $two.path='c'; $two.recovery_copy='files/c'
    $comma.recovery_manifest.files=@($one,$two); $comma.recovery_manifest.allowed_paths=@('a,b','c')
    Assert-PfcTrue -Actual (-not (Test-PfcV2ControlSemantics 'continuation-checkpoint' $comma)) -ScenarioId 'I1.collision' -Expected 'distinct path sets rejected'
    $comma.recovery_manifest.git_status[0].path='a,b'; $comma.recovery_manifest.git_status[1].path='c'
    Assert-PfcTrue -Actual (Test-PfcV2ControlSemantics 'continuation-checkpoint' $comma) -ScenarioId 'I1.comma-valid' -Expected 'legal comma path retained'
}
Assert-ReviewRegression 'I2.true-end-of-input' {
    foreach ($suffix in @([string][char]10,([string][char]13 + [char]10))) {
        Assert-V2Rejected 'continuous-authorization' { param($v) $v.repository.authorized_base_checkpoint_sha += $suffix } 'I2.sha-newline'
        Assert-V2Rejected 'continuous-authorization' { param($v) $v.paths.writable_paths_hash += $suffix } 'I2.hash-newline'
        Assert-V2Rejected 'continuous-authorization' { param($v) $v.scope.from += $suffix } 'I2.id-newline'
        Assert-V2Rejected 'continuation-checkpoint' { param($v) $v.previous_accepted_checkpoint_sha += $suffix } 'I2.sentinel-newline'
    }
}
Assert-ReviewRegression 'I3.case-sensitive-root' {
    Assert-V2Rejected 'continuous-authorization' {
        param($v)
        $id=$v.authorization_id; $v.PSObject.Properties.Remove('authorization_id')
        $v | Add-Member -NotePropertyName AUTHORIZATION_ID -NotePropertyValue $id
    } 'I3.root-case'
}
Assert-ReviewRegression 'M2.git-ref-rules' {
    foreach ($branch in @('.hidden','feature/.hidden','feature.lock/child')) {
        Assert-V2Rejected 'continuous-authorization' { param($v) $v.repository.source_branch=$branch } 'M2.source-branch'
        Assert-V2Rejected 'wave-plan' { param($v) $v.milestones[0].exact_branch='codex/pfc/AUTH-20260920-001/' + $branch } 'M2.milestone-branch'
    }
}
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-v2-bindings-' + [guid]::NewGuid().ToString('N'))
try {
    $fixtureTemplates = Join-Path $fixtureRoot 'skill/project-flight-control/assets/templates'
    $fixtureSchemas = Join-Path $fixtureRoot 'evals/schemas'
    $fixtureReferences = Join-Path $fixtureRoot 'skill/project-flight-control/references'
    foreach ($directory in @($fixtureTemplates,$fixtureSchemas,$fixtureReferences)) { $null = New-Item -ItemType Directory -Path $directory -Force }
    foreach ($file in @('continuous-authorization.yaml','wave-plan.yaml','known-limitations.md','blocker-fallback-matrix.md','continuation-checkpoint.md','wave-report.md','project.md')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot ('skill/project-flight-control/assets/templates/' + $file)) -Destination (Join-Path $fixtureTemplates $file)
    }
    foreach ($name in $v2Names) { Copy-Item -LiteralPath (Join-Path $repoRoot ('evals/schemas/' + $name + '.schema.json')) -Destination $fixtureSchemas }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skill/project-flight-control/references/message-contracts.md') -Destination $fixtureReferences
    Assert-PfcEqual -Expected 'PASS' -Actual (Invoke-PfcV2ContractChecks ([IO.DirectoryInfo]$fixtureRoot)).Status -ScenarioId 'V2.binding.fixture-valid'
    Assert-ReviewRegression 'I3.case-sensitive-nested' {
        foreach ($case in @(@{file='continuous-authorization.yaml';key='goal_id'},@{file='wave-plan.yaml';key='milestone_id'})) {
            $path=Join-Path $fixtureTemplates $case.file
            $text=Get-Content -Raw -Encoding UTF8 $path
            try {
                Write-PfcUtf8NoBom -Path $path -Content ($text.Replace(('"' + $case.key + '"'),('"' + $case.key.ToUpperInvariant() + '"')))
                Assert-PfcEqual -Expected 'FAIL' -Actual (Invoke-PfcV2ContractChecks ([IO.DirectoryInfo]$fixtureRoot)).Status -ScenarioId ('I3.nested-case.' + $case.key)
            } finally { Write-PfcUtf8NoBom -Path $path -Content $text }
        }
    }
    Assert-ReviewRegression 'M1.single-json-object' {
        $fence=([string][char]96) * 3
        foreach ($file in @('continuation-checkpoint.md','wave-report.md')) {
            $path=Join-Path $fixtureTemplates $file; $text=Get-Content -Raw -Encoding UTF8 $path
            try {
                foreach ($indent in 0..3) {
                    $marker=(' ' * $indent) + $fence
                    $second=[Environment]::NewLine + $marker + 'json' + [Environment]::NewLine + '{"unexpected":"second authority"}' + [Environment]::NewLine + $marker
                    Write-PfcUtf8NoBom -Path $path -Content ($text + $second)
                    Assert-PfcEqual -Expected 'FAIL' -Actual (Invoke-PfcV2ContractChecks ([IO.DirectoryInfo]$fixtureRoot)).Status -ScenarioId ('M1.second-fence.' + $file + '.indent-' + $indent)
                    Write-PfcUtf8NoBom -Path $path -Content ($text + [Environment]::NewLine + $marker + 'json' + [Environment]::NewLine + '{"unclosed":true}')
                    Assert-PfcEqual -Expected 'FAIL' -Actual (Invoke-PfcV2ContractChecks ([IO.DirectoryInfo]$fixtureRoot)).Status -ScenarioId ('M1.unclosed-fence.' + $file + '.indent-' + $indent)
                }
                $indentedSingle = $text -replace ('(?m)^' + $fence), ('   ' + $fence)
                Write-PfcUtf8NoBom -Path $path -Content $indentedSingle
                Assert-PfcEqual -Expected 'PASS' -Actual (Invoke-PfcV2ContractChecks ([IO.DirectoryInfo]$fixtureRoot)).Status -ScenarioId ('M1.single-indented.' + $file)
                $codeMarker='    ' + $fence
                $codeBlock=[Environment]::NewLine + $codeMarker + 'json' + [Environment]::NewLine + '    {"code-example":true}' + [Environment]::NewLine + $codeMarker
                Write-PfcUtf8NoBom -Path $path -Content ($text + $codeBlock)
                Assert-PfcEqual -Expected 'PASS' -Actual (Invoke-PfcV2ContractChecks ([IO.DirectoryInfo]$fixtureRoot)).Status -ScenarioId ('M1.four-spaces-code.' + $file)
            } finally { Write-PfcUtf8NoBom -Path $path -Content $text }
        }
    }
    $limited = Join-Path $fixtureTemplates 'known-limitations.md'
    $original = Get-Content -Raw -Encoding UTF8 $limited
    foreach ($mutation in @(($original + [Environment]::NewLine + 'Unexpected: value'), ($original -replace '(?m)^Review Trigger:.*\r?\n?', ''))) {
        Write-PfcUtf8NoBom -Path $limited -Content $mutation
        Assert-PfcEqual -Expected 'FAIL' -Actual (Invoke-PfcV2ContractChecks ([IO.DirectoryInfo]$fixtureRoot)).Status -ScenarioId 'V2.binding.extra-or-missing-rejected'
    }
    Write-PfcUtf8NoBom -Path $limited -Content $original
    $seventh = Join-Path $fixtureTemplates 'project-control-report.md'
    Write-PfcUtf8NoBom -Path $seventh -Content 'invalid seventh template'
    Assert-PfcEqual -Expected 'FAIL' -Actual (Invoke-PfcV2ContractChecks ([IO.DirectoryInfo]$fixtureRoot)).Status -ScenarioId 'V2.binding.seventh-rejected'
    Remove-Item -LiteralPath $seventh
    # Fixtures prove enumeration excludes the protected root name and ignored report subtree
    # while retaining a same-named product document outside the protected root.
    Write-PfcUtf8NoBom -Path (Join-Path $fixtureRoot 'task-3-report.md') -Content 'synthetic sentinel; never read'
    Write-PfcUtf8NoBom -Path (Join-Path $fixtureRoot '.superpowers/ignored.md') -Content 'synthetic sentinel; never read'
    Write-PfcUtf8NoBom -Path (Join-Path $fixtureRoot 'docs/task-3-report.md') -Content 'synthetic product document'
    Write-PfcUtf8NoBom -Path (Join-Path $fixtureRoot 'docs/.superpowers/product.md') -Content 'synthetic nested product document'
    $listed = @(& (Get-Module StaticChecks) { param($root) Get-PfcTextFiles -Root ([IO.DirectoryInfo]$root) | ForEach-Object { $_.FullName } } $fixtureRoot)
    Assert-PfcTrue -Actual ($listed -notcontains (Join-Path $fixtureRoot 'task-3-report.md')) -ScenarioId 'V2.scan.synthetic-protected' -Expected 'root excluded without reading contents'
    Assert-PfcTrue -Actual ($listed -notcontains (Join-Path $fixtureRoot '.superpowers/ignored.md')) -ScenarioId 'V2.scan.synthetic-ignored' -Expected 'ignored directory excluded'
    Assert-PfcTrue -Actual ($listed -contains (Join-Path $fixtureRoot 'docs/task-3-report.md')) -ScenarioId 'V2.scan.only-root-protected' -Expected 'unrelated product document retained'
    Assert-ReviewRegression 'M3.root-only-ignore' {
        Assert-PfcTrue -Actual ($listed -contains (Join-Path $fixtureRoot 'docs/.superpowers/product.md')) -ScenarioId 'M3.nested-retained' -Expected 'nested product directory retained'
    }
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedFixture) -notlike 'pfc-v2-bindings-*') { throw 'unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}

if ($reviewFailures.Count -gt 0) { throw ($reviewFailures -join [Environment]::NewLine) }
Write-PfcSummary -Results @((New-PfcResult -ScenarioId 'StrictSchema' -Status 'PASS' -Message 'STRICT-01..10 and V2 strict contracts')) -Json
