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
Write-PfcSummary -Results @((New-PfcResult -ScenarioId 'StrictSchema' -Status 'PASS' -Message 'STRICT-01..10')) -Json
