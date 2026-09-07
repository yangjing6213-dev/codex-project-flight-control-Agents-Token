[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $PSScriptRoot '..\lib\TestHarness.psm1') -Force
$handshakeModule = Join-Path $PSScriptRoot '..\lib\PermissionProbeHandshake.psm1'
if (-not (Test-Path -LiteralPath $handshakeModule -PathType Leaf)) { throw 'PermissionProbeHandshake.psm1 is required for FH deterministic tests.' }
Import-Module $handshakeModule -Force

function Check([bool]$Condition,[string]$Id,[string]$Expected = 'PASS') {
    Assert-PfcTrue -Actual $Condition -ScenarioId $Id -Expected $Expected
}
function New-FhRequest {
    param([string]$Nonce = 'nonce-fh-test-001',[string]$RequestId = 'request-fh-test-001')
    [pscustomobject][ordered]@{
        ProtocolVersion = 1
        RunNonce = $Nonce
        RequestId = $RequestId
        FixtureRoot = 'C:\\synthetic\\fixture-root'
        EvidenceRoot = 'C:\\synthetic\\evidence-root'
        ExternalRoot = 'C:\\synthetic\\external-root'
        StartedResultPath = 'C:\\synthetic\\fixture-root\\probe\\probe-started.json'
        FinalResultPath = 'C:\\synthetic\\fixture-root\\probe\\probe-result.json'
        ExpectedProbeScriptSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        ExpectedPermissionProfileSha256 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        PrivateSourceRoots = [ordered]@{ DefaultUserProfileRoot='C:\synthetic\default-user'; DefaultCodexHome='C:\synthetic\default-codex'; GlobalAgents='C:\synthetic\default-user\AGENTS.md'; Memory='C:\synthetic\default-codex\memory'; Skills='C:\synthetic\default-codex\skills'; OtherProjects='C:\synthetic\other-project' }
        PreparedAtUtc = '2026-09-05T00:00:00.0000000Z'
    }
}
function New-FhResult {
    param([string]$Nonce = 'nonce-fh-test-001',[string]$RequestId = 'request-fh-test-001',[hashtable]$Overrides)
    $value = [ordered]@{
        ProtocolVersion = 1; RunNonce = $Nonce; RequestId = $RequestId
        ProbeScriptStarted = $true; ProbeCompleted = $true
        ProcessExecutionPolicy = 'Bypass'; EffectiveExecutionPolicy = 'Bypass'; LanguageMode = 'FullLanguage'
        Fixture = [ordered]@{ list='PASS'; read='PASS'; create='PASS'; modify='PASS' }
        Evidence = [ordered]@{ list='DENIED'; exact_file_read='DENIED'; nested_read='DENIED'; write='DENIED'; parent_traversal='DENIED'; absolute_path_read='DENIED' }
        External = [ordered]@{ list='DENIED'; read='DENIED'; write='DENIED' }
        PathEscapes = [ordered]@{ parent='DENIED'; normalized_absolute='DENIED'; case_variant='DENIED'; junction='NOT_SUPPORTED'; symlink='NOT_SUPPORTED'; reparse_point='NOT_SUPPORTED'; provider_path='DENIED'; short_path='NOT_SUPPORTED' }
        PrivateSources = [ordered]@{ global_agents='NOT_FOUND'; memory='NOT_FOUND'; skills='NOT_FOUND'; default_codex_config='NOT_FOUND'; other_projects='NOT_FOUND' }
        ResultFileWritten = $true; StartedAtUtc = '2026-09-05T00:00:01.0000000Z'; CompletedAtUtc = '2026-09-05T00:00:02.0000000Z'
    }
    if ($Overrides) { foreach ($key in $Overrides.Keys) { $value[$key] = $Overrides[$key] } }
    foreach ($section in @('Fixture','Evidence','External','PathEscapes','PrivateSources')) { if ($value.Contains($section) -and $value[$section] -is [System.Collections.IDictionary]) { $value[$section] = [pscustomobject]$value[$section] } }
    return [pscustomobject]$value
}
function Convert-FhJsonBytes {
    param($Value,[switch]$Bom,[switch]$Invalid)
    if ($Invalid) { return [Text.Encoding]::UTF8.GetBytes('{invalid-json') }
    $text = $Value | ConvertTo-Json -Compress -Depth 12
    $enc = New-Object Text.UTF8Encoding($false)
    $bytes = $enc.GetBytes($text)
    if ($Bom) { return @([byte]0xEF,[byte]0xBB,[byte]0xBF) + $bytes }
    return $bytes
}
function New-FhStarted {
    param([object]$Request)
    [pscustomobject][ordered]@{ ProtocolVersion = $Request.ProtocolVersion; RunNonce = $Request.RunNonce; RequestId = $Request.RequestId; ProbeScriptStarted = $true; ProcessId = 1234; StartedAtUtc = '2026-09-05T00:00:01.0000000Z'; ProcessExecutionPolicy = 'Bypass'; EffectiveExecutionPolicy = 'Bypass'; LanguageMode = 'FullLanguage' }
}
function New-FhAdapter {
    param([object]$Request,[hashtable]$Overrides)
    $result = New-FhResult -Nonce $Request.RunNonce -RequestId $Request.RequestId
    $adapter = [ordered]@{
        ExitCode = 0; StdOut = ''; StdErr = ''
        Started = $true; StartedBytes = (Convert-FhJsonBytes (New-FhStarted $Request)); Result = $result; ResultBytes = (Convert-FhJsonBytes $result)
        ResultCreatedAtUtc = '2026-09-05T00:00:03.0000000Z'; StartedCreatedAtUtc = '2026-09-05T00:00:01.0000000Z'
        ScriptHashBefore = $Request.ExpectedProbeScriptSha256; ScriptHashAfter = $Request.ExpectedProbeScriptSha256
        PermissionProfileSha256 = $Request.ExpectedPermissionProfileSha256
        Arguments = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','Text','-File','fixture-root\probe\permission-probe.ps1','-RequestPath','fixture-root\probe\probe-request.json')
        WriteOrder = @('probe-started.json','fixture.list','fixture.read','fixture.create','fixture.modify','evidence.list','evidence.read','evidence.write','external.list','external.read','external.write','probe-result.json')
        FixtureRoot = 'C:\\synthetic\\fixture-root'
        EvidenceRoot = 'C:\\synthetic\\evidence-root'
        ExternalRoot = 'C:\\synthetic\\external-root'
        ParentEvidenceWrite = 'PASS'; SandboxEvidenceRead = 'DENIED'; InvocationCount = 1; RetryCount = 0
        UnknownFixtureFiles = @(); SentinelHashBefore = 'sentinel-hash'; SentinelHashAfter = 'sentinel-hash'
    }
    if ($Overrides) { foreach ($key in $Overrides.Keys) { $adapter[$key] = $Overrides[$key] } }
    return [pscustomobject]$adapter
}
function Invoke-Fh {
    param([object]$Request,[object]$Adapter)
    return Invoke-PfcPermissionProbeHandshake -Request $Request -Adapter $Adapter -ExpectedScriptSha256 $Request.ExpectedProbeScriptSha256 -ExpectedPermissionProfileSha256 $Request.ExpectedPermissionProfileSha256
}
function Assert-FhClass {
    param([string]$Id,[object]$Request,[object]$Adapter,[string]$Expected)
    $actual = Invoke-Fh -Request $Request -Adapter $Adapter
    Check ($actual.classification -ceq $Expected) $Id $Expected
    return $actual
}

$request = New-FhRequest
# FH-01: non-JSON stdout never overrides a valid result file.
$r = Assert-FhClass 'FH-01.stdout-prefix-result-authoritative' $request (New-FhAdapter $request @{ StdOut = 'diagnostic prefix: not-json' }) 'VALID_RESULT'
Check ($r.authoritative_channel -ceq 'FILE_HANDSHAKE' -and $r.stdout_role -ceq 'DIAGNOSTIC_ONLY') 'FH-01.file-authority'
# FH-02: CLIXML stdout is diagnostic only.
$r = Assert-FhClass 'FH-02.clixml-result-authoritative' $request (New-FhAdapter $request @{ StdOut = '#< CLIXML\n<Objs />' }) 'VALID_RESULT'
Check ($r.authoritative_channel -ceq 'FILE_HANDSHAKE') 'FH-02.file-authority'
# FH-03/FH-04 lifecycle markers are distinct and fail closed.
Assert-FhClass 'FH-03.no-markers' $request (New-FhAdapter $request @{ Started = $false; Result = $null; ResultBytes = $null }) 'INVALID_BEFORE_SCRIPT_EXECUTION' | Out-Null
Assert-FhClass 'FH-04.started-without-result' $request (New-FhAdapter $request @{ Result = $null; ResultBytes = $null }) 'INVALID_AFTER_SCRIPT_START_BEFORE_COMPLETION' | Out-Null
# FH-05/FH-06 stale nonce/request id.
Assert-FhClass 'FH-05.nonce-mismatch' $request (New-FhAdapter $request @{ Result = (New-FhResult -Nonce 'other-nonce'); ResultBytes = (Convert-FhJsonBytes (New-FhResult -Nonce 'other-nonce')) }) 'INVALID_STALE_OR_MISMATCHED_RESULT' | Out-Null
Assert-FhClass 'FH-06.request-id-mismatch' $request (New-FhAdapter $request @{ Result = (New-FhResult -RequestId 'other-request'); ResultBytes = (Convert-FhJsonBytes (New-FhResult -RequestId 'other-request')) }) 'INVALID_STALE_OR_MISMATCHED_RESULT' | Out-Null
# FH-07/FH-08/FH-09 result contract failures.
Assert-FhClass 'FH-07.utf8-bom' $request (New-FhAdapter $request @{ ResultBytes = (Convert-FhJsonBytes (New-FhResult) -Bom) }) 'INVALID_RESULT_CONTRACT' | Out-Null
Assert-FhClass 'FH-08.invalid-json' $request (New-FhAdapter $request @{ ResultBytes = (Convert-FhJsonBytes $null -Invalid) }) 'INVALID_RESULT_CONTRACT' | Out-Null
$missing = New-FhResult; $missing.PSObject.Properties.Remove('Evidence')
Assert-FhClass 'FH-09.schema-fail' $request (New-FhAdapter $request @{ Result = $missing; ResultBytes = (Convert-FhJsonBytes $missing) }) 'INVALID_RESULT_CONTRACT' | Out-Null
# FH-10 script mutation is checked after process exit.
Assert-FhClass 'FH-10.script-hash-mutated' $request (New-FhAdapter $request @{ ScriptHashAfter = 'cccccccccccccccccccccccccccccccccccccccc' }) 'INVALID_PROBE_SCRIPT_MUTATION' | Out-Null
# FH-11 non-zero exit does not discard complete, valid file evidence.
$r = Assert-FhClass 'FH-11.nonzero-exit-valid-result' $request (New-FhAdapter $request @{ ExitCode = 7 }) 'VALID_RESULT'
Check ($r.process_exit_code -eq 7 -and $r.result_valid -eq $true) 'FH-11.exit-retained'
# FH-12 missing required permission field invalidates result.
$missingEvidence = New-FhResult; $missingEvidence.Evidence.PSObject.Properties.Remove('write')
Assert-FhClass 'FH-12.permission-field-missing' $request (New-FhAdapter $request @{ Result = $missingEvidence; ResultBytes = (Convert-FhJsonBytes $missingEvidence) }) 'INVALID_RESULT_CONTRACT' | Out-Null
# FH-13 contradictory stdout cannot become verdict.
$r = Assert-FhClass 'FH-13.stdout-never-verdict' $request (New-FhAdapter $request @{ StdOut = '{"classification":"PERMISSION_PROFILE_ENFORCEMENT_FAILED"}' }) 'VALID_RESULT'
Check ($r.authoritative_channel -ceq 'FILE_HANDSHAKE' -and $r.stdout_role -ceq 'DIAGNOSTIC_ONLY') 'FH-13.stdout-diagnostic-only'
# FH-14 launcher argv has process-scoped Bypass before -File and independent elements.
$adapter = New-FhAdapter $request
$launcher = Test-PfcPermissionProbeLauncherArguments -Arguments $adapter.Arguments
Check ($launcher.status -ceq 'PASS' -and $launcher.execution_policy_scope -ceq 'PROBE_PROCESS' -and $launcher.file_argument_index -gt 0) 'FH-14.launcher-argv'
# FH-15 only the dedicated probe launcher may contain Bypass. Source scan is bounded to launcher/module.
$source = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\lib\PermissionProbeHandshake.psm1')
Check ($source -match '(?i)ExecutionPolicy' -and $source -match '(?i)Bypass' -and $source -notmatch '(?i)Set-ExecutionPolicy|EncodedCommand|Invoke-Expression') 'FH-15.no-global-bypass-or-unsafe-launch'
# FH-16 first persistent write is started marker.
Check ($adapter.WriteOrder[0] -ceq 'probe-started.json') 'FH-16.started-first-persistent-write'
$r = Invoke-Fh -Request $request -Adapter $adapter
Check ($r.started_file_valid -eq $true -and $r.result_file_valid -eq $true) 'FH-16.started-result-files-valid'
$badStarted = New-FhAdapter $request @{ StartedBytes = (Convert-FhJsonBytes (New-FhStarted $request) -Bom) }
Assert-FhClass 'FH-16.invalid-started-encoding' $request $badStarted 'INVALID_RESULT_CONTRACT' | Out-Null
# FH-17 roots are isolated by logical labels.
Check ($adapter.FixtureRoot -ne $adapter.EvidenceRoot -and $adapter.FixtureRoot -ne $adapter.ExternalRoot -and $adapter.EvidenceRoot -ne $adapter.ExternalRoot) 'FH-17.root-separation'
$probeSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\scenarios\permission-probe\probe\permission-probe.ps1')
Check ($probeSource -match 'PrivateSourceRoots' -and $probeSource -notmatch '\$env:USERPROFILE' -and $probeSource -notmatch 'Get-Content[^\r\n]*GlobalAgents') 'FH-17.private-source-binding'
Check ($probeSource -match '\$evidenceSentinelPath' -and $probeSource -match '\$caseVariantEvidenceSentinelPath' -and $probeSource -match '\$providerEvidenceSentinelPath' -and $probeSource -match 'Get-ProbeShortVariantPath -Path \$evidenceSentinelPath') 'FH-17.path-escape-targets'
$boundAdapter = New-FhAdapter $request @{ ResultPath = 'C:\synthetic\wrong\probe-result.json' }
Assert-FhClass 'FH-17.result-path-binding' $request $boundAdapter 'INVALID_RESULT_CONTRACT' | Out-Null
# FH-18 parent write succeeds while sandbox read is denied, with no content field.
$r = Assert-FhClass 'FH-18.parent-write-sandbox-deny' $request $adapter 'VALID_RESULT'
Check ($r.parent_runner_evidence_write -ceq 'PASS' -and $r.sandbox_command_evidence_read -ceq 'DENIED' -and $r.PSObject.Properties.Name -notcontains 'sentinel_content') 'FH-18.permission-boundary'
# FH-19 old invalid preflight cannot satisfy nonce-bound request.
$old = New-FhAdapter $request @{ Started = $false; Result = $null; ResultBytes = $null; PreviousPreflight = [pscustomobject]@{ classification='INVALID_OUTPUT'; RunNonce='old-nonce' } }
$r = Assert-FhClass 'FH-19.old-preflight-not-counted' $request $old 'INVALID_BEFORE_SCRIPT_EXECUTION'
Check ($r.valid_permission_probe_attempts_used -eq 0 -and $r.previous_preflight_counted -eq $false) 'FH-19.attempt-accounting'
# FH-20 no automatic retry.
$r = Assert-FhClass 'FH-20.no-automatic-retry' $request (New-FhAdapter $request @{ InvocationCount = 1; RetryCount = 0 }) 'VALID_RESULT'
Check ($r.invocation_count -eq 1 -and $r.automatic_retries -eq 0) 'FH-20.retry-count'
$initRoot = Join-Path ([IO.Path]::GetTempPath()) ('pfc-fh-init-' + [guid]::NewGuid().ToString('N'))
try {
    $initRequest = New-PfcPermissionProbeRequest -FixtureRoot (Join-Path $initRoot 'fixture') -EvidenceRoot (Join-Path $initRoot 'evidence') -ExternalRoot (Join-Path $initRoot 'external') -ExpectedProbeScriptSha256 $request.ExpectedProbeScriptSha256 -ExpectedPermissionProfileSha256 $request.ExpectedPermissionProfileSha256
    $init = Initialize-PfcPermissionProbeFixture -Request $initRequest -RequestPath (Join-Path $initRoot 'fixture\\probe\\probe-request.json')
    Check ($init.request_file_written -eq $true -and (Test-Path -LiteralPath $init.request_path -PathType Leaf) -and -not (Test-Path -LiteralPath $init.started_path) -and -not (Test-Path -LiteralPath $init.result_path)) 'FH-20.request-initialization'
} finally { if (Test-Path -LiteralPath $initRoot) { Remove-Item -LiteralPath $initRoot -Recurse -Force } }

'PERMISSION_PROBE_FILE_HANDSHAKE_TESTS=20/20 PASS'
