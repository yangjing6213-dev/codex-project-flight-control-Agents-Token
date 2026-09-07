[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $PSScriptRoot '..\lib\TestHarness.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\lib\CodexRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\lib\ControlledProfile.psm1') -Force

$results = New-Object System.Collections.Generic.List[object]
function Check-R4 { param([string]$Id,[bool]$Condition,[string]$Message) if(-not $Condition){throw "${Id}: $Message"}; $results.Add((New-PfcResult -ScenarioId $Id -Status 'PASS' -Message $Message)) | Out-Null }
$scenarioRoot = Join-Path $repoRoot 'evals\scenarios\builder-efficiency'
$controlPath = Join-Path $repoRoot 'evals\schemas\schema-control.json'
$control = Get-Content -Raw -LiteralPath $controlPath | ConvertFrom-Json

try {
    $ids = @('EFF-01','EFF-02','EFF-03','EFF-04','EFF-05','EFF-06','EFF-07')
    $nameMap = @{'EFF-01'='EFF-01-targeted-context';'EFF-02'='EFF-02-reuse-before-create';'EFF-03'='EFF-03-minimal-diff';'EFF-04'='EFF-04-delta-rework';'EFF-05'='EFF-05-incremental-verification';'EFF-06'='EFF-06-debugging-convergence';'EFF-07'='EFF-07-structured-recovery'}
    $first = Get-Content -Raw (Join-Path (Join-Path $scenarioRoot $nameMap['EFF-01']) 'common.md')
    $banned = '(?i)(start\s+with|inspect\s+.*first|avoid\s+repository-wide|targeted\s+context|reuse\s+before\s+create|smallest\s+diff|do\s+not\s+reread|verify\s+incrementally|delta\s+rework|two\s+repair\s+attempts|incremental\s+verification)'
    Check-R4 'R4-01' ($first -notmatch $banned) 'RED common contract contains outcome constraints only'
    foreach($id in $ids){
        $d=Join-Path $scenarioRoot $nameMap[$id]
        $common=Get-Content -Raw (Join-Path $d 'common.md')
        $treat=Get-Content -Raw (Join-Path $d 'treatment.md')
        $red=(Get-PfcEvaluationPromptText -CommonPromptPath (Join-Path $d 'common.md') -TreatmentPromptPath $null -Phase RED)
        $green=(Get-PfcEvaluationPromptText -CommonPromptPath (Join-Path $d 'common.md') -TreatmentPromptPath (Join-Path $d 'treatment.md') -Phase GREEN)
        $redNorm=$red.text -replace "`r`n","`n"; $greenNorm=$green.text -replace "`r`n","`n"; $commonNorm=$common -replace "`r`n","`n"
        Check-R4 ('R4-02.'+$id) ($redNorm -eq $commonNorm -and $greenNorm -eq ($commonNorm.TrimEnd()+"`n`n"+$treat.Trim()+"`n") -and $greenNorm.Substring($commonNorm.TrimEnd().Length).Trim() -eq $treat.Trim()) 'RED/GREEN differ only by treatment'
        Check-R4 ('R4-03.'+$id) ($common -match '(?i)acceptance|behavior|preserve|verification' -and $treat -match '(?i)inspect|search|smallest|verify|reproduce|resume|read|run') 'outcome and process content remain classified separately'
    }
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-r4-fixture-' + [guid]::NewGuid().ToString('N'))
    $evidenceRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-r4-evidence-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    try {
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'README.md') -Value 'fixture' -Encoding UTF8
        $fakeOutput = '{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}' + [Environment]::NewLine + '{"type":"turn.completed"}'
        $fake = ({ param($a) [pscustomobject]@{ ExitCode=0; StdOut=$fakeOutput; StdErr='' } }).GetNewClosure()
        $r = Invoke-PfcCodexRun -WorkingDirectory $fixtureRoot -PromptPath (Join-Path $scenarioRoot ($nameMap['EFF-01'] + '\common.md')) -SandboxMode workspace-write -ResultDirectory $evidenceRoot -Phase RED -RequireExternalResultDirectory -ProcessInvoker $fake -Track CONTROLLED_EFFICACY -SampleId R4TEST -Scenario EFF-01 -Repetition 1
        Check-R4 'R4-04' ((-not (Test-PfcPathDescendant -Path $evidenceRoot -Parent $fixtureRoot)) -and (Test-Path -LiteralPath $evidenceRoot -PathType Container) -and -not (Test-Path -LiteralPath (Join-Path $fixtureRoot '.pfc-eval-results')) -and $r.result_root_outside_fixture -and $r.track -eq 'CONTROLLED_EFFICACY' -and $r.sample_id -eq 'R4TEST' -and $r.eval_contract_revision -eq 4) 'evidence root and runner metadata are controlled'
        $insideRejected=$false; try { Invoke-PfcCodexRun -WorkingDirectory $fixtureRoot -PromptPath (Join-Path $fixtureRoot 'README.md') -SandboxMode workspace-write -ResultDirectory (Join-Path $fixtureRoot 'evidence') -Phase RED -RequireExternalResultDirectory -ProcessInvoker $fake | Out-Null } catch { $insideRejected=$true }
        Check-R4 'R4-05' $insideRejected 'fixture descendant result root is rejected'
        $schema=Join-Path $repoRoot 'evals\schemas\eval-run.schema.json'
        $m=Get-PfcRunnerPhaseDecision -AuthorizedPhase RED -ModelReportedPhase GREEN
        Check-R4 'R4-06' ($m.runner_authorized_phase -eq 'RED' -and $m.model_reported_phase -eq 'GREEN' -and $m.model_report_consistency -eq 'FAIL') 'runner phase remains authoritative and mismatch is retained'
        $emptyTreatment=Join-Path $fixtureRoot 'empty-treatment.md'; [IO.File]::WriteAllText($emptyTreatment,'',(New-Object Text.UTF8Encoding($false)))
        $red=Get-PfcEvaluationPromptText -CommonPromptPath (Join-Path $scenarioRoot ($nameMap['EFF-01'] + '\common.md')) -TreatmentPromptPath $emptyTreatment -Phase RED
        $green=Get-PfcEvaluationPromptText -CommonPromptPath (Join-Path $scenarioRoot ($nameMap['EFF-01'] + '\common.md')) -TreatmentPromptPath (Join-Path $scenarioRoot ($nameMap['EFF-01'] + '\treatment.md')) -Phase GREEN
        Check-R4 'R4-07' (-not $red.treatment_enabled -and $green.treatment_enabled) 'RED treatment disabled and GREEN treatment enabled'
    } finally { if(Test-Path $fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force}; if(Test-Path $evidenceRoot){Remove-Item -LiteralPath $evidenceRoot -Recurse -Force} }
    $profileRoot=Join-Path ([IO.Path]::GetTempPath()) ('pfc-r4-profile-' + [guid]::NewGuid().ToString('N'))
    try {
        $profile=Get-PfcControlledProfile -Root $profileRoot -ResultRoot (Join-Path ([IO.Path]::GetTempPath()) 'pfc-r4-evidence') -DefaultCodexHome (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex')
        $state=Initialize-PfcControlledProfile -Profile $profile
        Check-R4 'R4-08' (-not $state.controlled_profile_contaminated -and $state.locations_distinct) 'clean dedicated profile passes isolation'
        Set-Content -LiteralPath (Join-Path $profile.codex_home 'AGENTS.md') -Value 'contamination' -Encoding UTF8
        $dirty=Test-PfcControlledProfileIsolation -Profile $profile
        Check-R4 'R4-08-negative' $dirty.controlled_profile_contaminated 'profile contamination fails closed'
        Remove-Item -LiteralPath (Join-Path $profile.codex_home 'AGENTS.md') -Force
        Check-R4 'R4-09' (-not $state.default_auth_file_copied_or_linked -and -not $state.default_auth_checked) 'default auth is neither copied nor read'
        Check-R4 'R4-10' ($state.controlled_profile_isolation -eq 'PASS' -and -not (Test-Path -LiteralPath (Join-Path $profile.codex_home 'auth.json'))) 'unautenticated dedicated profile remains login-required without exec'
        $configText = Get-Content -Raw -LiteralPath $profile.permission_profile_config_path
        Check-R4 'R4-15' ($configText -match 'default_permissions\s*=\s*"pfc-controlled"' -and $configText -match 'extends\s*=\s*":workspace"' -and $configText -match 'deny' -and $state.permission_profile_config_path -eq $profile.permission_profile_config_path) 'controlled profile config selects extends workspace and deny rules'
        Set-Content -LiteralPath (Join-Path $profile.codex_home 'auth.json') -Value '{"tokens":{}}' -Encoding UTF8
        $owned=Test-PfcControlledProfileIsolation -Profile $profile
        Check-R4 'R4-16' ($owned.controlled_auth_present -and $owned.controlled_auth_owned -and -not $owned.controlled_profile_contaminated) 'profile-owned auth artifact is accepted without default auth access'
        Remove-Item -LiteralPath (Join-Path $profile.codex_home 'auth.json') -Force
        $captured = New-Object System.Collections.Generic.List[string]
        $customFake = ({ param($a) foreach($arg in $a){ [void]$captured.Add([string]$arg) }; [pscustomobject]@{ ExitCode=0; StdOut='{"type":"turn.completed"}'; StdErr='' } }).GetNewClosure()
        $customEvidence = Join-Path ([IO.Path]::GetTempPath()) ('pfc-r4-custom-evidence-' + [guid]::NewGuid().ToString('N'))
        try {
            $customRun = Invoke-PfcCodexRun -WorkingDirectory $profile.home -PromptPath (Join-Path $scenarioRoot ($nameMap['EFF-01'] + '\common.md')) -SandboxMode workspace-write -ResultDirectory $customEvidence -RequireExternalResultDirectory -Phase RED -PermissionProfileName $profile.permission_profile_name -PermissionProfileConfigPath $profile.permission_profile_config_path -ProcessInvoker $customFake
            Check-R4 'R4-17' (($captured -contains '-c') -and (@($captured | Where-Object { $_ -match '^default_permissions=' }).Count -eq 1) -and -not ($captured -contains '--sandbox') -and $customRun.sandbox -eq 'workspace-write' -and $customRun.permission_profile -eq 'pfc-controlled' -and $customRun.config_source -eq 'CONTROLLED_PROFILE_CONFIG') 'custom profile uses unique config selection and preserves workspace-write metadata'
        } finally { if(Test-Path $customEvidence){Remove-Item -LiteralPath $customEvidence -Recurse -Force} }
        $observedCount = Get-PfcEvaluationArtifactReadCount -Lines @('{"path":"' + (Join-Path $evidenceRoot 'raw.jsonl').Replace('\','\\') + '"}') -ResultRoot $evidenceRoot
        $unknownCount = Get-PfcEvaluationArtifactReadCount -Lines @('{"type":"turn.completed"}') -ResultRoot $evidenceRoot
        Check-R4 'R4-18' ($observedCount -eq 1 -and $unknownCount -eq 'NOT_AVAILABLE') 'artifact read count is observation-based and honest when unavailable'
    } finally { if(Test-Path $profileRoot){Remove-Item -LiteralPath $profileRoot -Recurse -Force} }
    $excluded=@($control.primary_metric.excluded)
    Check-R4 'R4-11' ($control.primary_metric.name -eq 'files_read_before_first_relevant_edit' -and $control.primary_metric.boundary -eq 'FIXTURE_PROJECT_CONTENT_FILES_ONLY' -and -not $control.primary_metric.evaluation_artifact_counted -and $excluded -contains 'raw_jsonl' -and $excluded -contains 'evidence') 'primary metric excludes evaluation artifacts'
    Check-R4 'R4-12' ($control.primary_track -eq 'CONTROLLED_EFFICACY' -and $control.secondary_track -eq 'OPERATIONAL_PROFILE') 'operational and controlled evidence tracks are distinct'
    Check-R4 'R4-13' ($control.eval_contract_revision -eq 4 -and (@($control.scenarios).Count -eq 7) -and (@($control.scenarios | Where-Object { $_ -match '^EFF-0[1-7]$' }).Count -eq 7)) 'all scenarios are revision 4 controlled candidates'
    $schemaNowHash=(Get-FileHash -Algorithm SHA256 (Join-Path $repoRoot 'evals\schemas\eval-run.schema.json')).Hash.ToLowerInvariant()
    Check-R4 'R4-14' ($schemaNowHash -eq 'd28a58bb6f3b081268883ff4cf984b685297b6806fa184044e6e1fe79bb02bd8' -and (Get-ChildItem -LiteralPath (Join-Path $repoRoot '.pfc-eval-results') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'run-bad89|integrity-audit' }).Count -gt 0) 'formal schema and historical evidence remain preserved'
} catch {
    $results.Add((New-PfcResult -ScenarioId 'Revision4Isolation' -Status 'FAIL' -Message ($_.Exception.Message + ' @ ' + $_.InvocationInfo.PositionMessage))) | Out-Null
}
return $results.ToArray()
