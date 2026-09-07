$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\CodexRunner.psm1') -Force

function Invoke-NormFixture {
    param([Parameter(Mandatory = $true)]$Payload,[ValidateSet('eval','builder')][string]$SchemaName = 'eval')
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pfc-normalizer-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    try {
        $prompt = Join-Path $root 'prompt.md'; Write-PfcUtf8NoBom -Path $prompt -Content 'fixture'
        $schema = Join-Path $root 'schema.json'
        $schemaFile = if ($SchemaName -eq 'builder') { 'builder-report.schema.json' } else { 'eval-run.schema.json' }
        $schemaText = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) ('schemas\' + $schemaFile))
        Write-PfcUtf8NoBom -Path $schema -Content $schemaText
        $fake = {
            param($args)
            Write-PfcUtf8NoBom -Path $script:normOutputPath -Content $script:normPayload
            [pscustomobject]@{ ExitCode = 0; StdOut = '{"type":"turn.completed"}'; StdErr = ''; OutputPath = $script:normOutputPath }
        }
        $script:normPayload = ($Payload | ConvertTo-Json -Compress -Depth 20)
        $script:normOutputPath = Join-Path $root 'fixture-final.json'
        return Invoke-PfcCodexRun -WorkingDirectory $root -PromptPath $prompt -OutputSchemaPath $schema -SandboxMode 'read-only' -ResultDirectory (Join-Path $root '.pfc-eval-results') -Phase 'RED' -ProcessInvoker $fake
    } finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
}

function Assert-Norm { param([bool]$Actual,[string]$Id,[string]$Message); if (-not $Actual) { throw ('[' + $Id + '] ' + $Message) } }
$results = New-Object System.Collections.Generic.List[object]
try {
    $base = [ordered]@{ scenario_id = 'EFF-01'; phase = 'RED'; status = 'PASS'; metrics = @([ordered]@{key='files_read';value=2}) }
    $r1 = Invoke-NormFixture $base
    Assert-Norm ($r1.structured_output_validated -eq $true -and $r1.normalized_metrics.files_read -eq 2) 'NORM-01' 'metrics key/value array did not normalize through Runner'
    $results.Add('NORM-01 PASS')

    $verificationPayload = [ordered]@{ scenario_id = 'EFF-01'; base_sha = ('a' * 40); candidate_sha = ('b' * 40); verification = @([ordered]@{key='target_test';value='PASS'}) }
    $r2 = Invoke-NormFixture $verificationPayload -SchemaName builder
    Assert-Norm ($r2.normalized_verification.target_test -ceq 'PASS') 'NORM-02' 'verification key/value array did not normalize through Runner'
    $results.Add('NORM-02 PASS')

    $nullPayload = [ordered]@{ scenario_id = 'EFF-01'; phase = 'RED'; status = 'PARTIAL'; metrics = @([ordered]@{key='unknown';value=$null}) }
    $r3 = Invoke-NormFixture $nullPayload
    Assert-Norm ($r3.normalized_metrics.unknown -ceq 'NOT_AVAILABLE') 'NORM-03' 'null value was not normalized to NOT_AVAILABLE'
    $results.Add('NORM-03 PASS')

    $multiPayload = [ordered]@{ scenario_id = 'EFF-01'; phase = 'RED'; status = 'PASS'; metrics = @([ordered]@{key='first';value=1},[ordered]@{key='second';value=2},[ordered]@{key='third';value=3}) }
    $r4 = Invoke-NormFixture $multiPayload
    $names = @($r4.normalized_metrics.PSObject.Properties.Name)
    Assert-Norm (($names -join ',') -ceq 'first,second,third' -and $r4.normalized_metrics.first -eq 1 -and $r4.normalized_metrics.third -eq 3) 'NORM-04 multiple metrics were lost, reordered, or duplicated'
    $results.Add('NORM-04 PASS')

    $duplicatePayload = [ordered]@{ scenario_id = 'EFF-01'; phase = 'RED'; status = 'PASS'; metrics = @([ordered]@{key='dup';value=1},[ordered]@{key='dup';value=2}) }
    $duplicateThrown = $false
    try { Invoke-NormFixture $duplicatePayload | Out-Null } catch { $duplicateThrown = $_.Exception.Message -match 'Duplicate structured metric key' }
    Assert-Norm $duplicateThrown 'NORM-05' 'duplicate key was not rejected closed'
    $results.Add('NORM-05 PASS')

    Assert-Norm ($r1.final_output_source -eq 'OUTPUT_LAST_MESSAGE_FILE' -and $r1.model_result -eq 'VALID' -and $r1.structured_output_validated -eq $true) 'NORM-06' 'formal Runner output path did not invoke Revision 2 adapter'
    $results.Add('NORM-06 PASS')
    $results | ForEach-Object { $_ }
    exit 0
} catch {
    $results.Add(('FAIL ' + $_.Exception.Message)); $results | ForEach-Object { $_ }; exit 1
}
