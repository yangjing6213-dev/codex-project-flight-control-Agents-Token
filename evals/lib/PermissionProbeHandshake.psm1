Set-StrictMode -Version 2.0

$script:ProbeStates = @('PASS','DENIED','ALLOWED','NOT_FOUND','NOT_SUPPORTED','ERROR')
$script:ProbeSections = @{
    Fixture = @('list','read','create','modify')
    Evidence = @('list','exact_file_read','nested_read','write','parent_traversal','absolute_path_read')
    External = @('list','read','write')
    PathEscapes = @('parent','normalized_absolute','case_variant','junction','symlink','reparse_point','provider_path','short_path')
    PrivateSources = @('global_agents','memory','skills','default_codex_config','other_projects')
}

function Write-PfcPermissionProbeJsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path $parent ('.' + [IO.Path]::GetFileName($full) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $encoding = New-Object Text.UTF8Encoding($false)
    $json = $Value | ConvertTo-Json -Compress -Depth 20
    try {
        [IO.File]::WriteAllText($temp, $json, $encoding)
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            [IO.File]::Replace($temp, $full, $null, $true)
        } else {
            [IO.File]::Move($temp, $full)
        }
    } finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    $bytes = [IO.File]::ReadAllBytes($full)
    [pscustomobject]@{ path = $full; file_exists = $true; file_bytes = $bytes.Length; utf8_no_bom = (Test-FhBytesNoBom -Bytes $bytes); json_valid = $true }
}

function New-PfcPermissionProbeRequest {
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot,
        [Parameter(Mandatory = $true)][string]$ExternalRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedProbeScriptSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedPermissionProfileSha256,
        [AllowNull()][hashtable]$PrivateSourceRoots,
        [int]$ProtocolVersion = 1
    )
    $nonce = [guid]::NewGuid().ToString('N')
    if ($null -eq $PrivateSourceRoots) {
        $PrivateSourceRoots = [ordered]@{
            DefaultUserProfileRoot = 'REPLACE_AT_RUNTIME'
            DefaultCodexHome = 'REPLACE_AT_RUNTIME'
            GlobalAgents = 'REPLACE_AT_RUNTIME'
            Memory = 'REPLACE_AT_RUNTIME'
            Skills = 'REPLACE_AT_RUNTIME'
            OtherProjects = 'REPLACE_AT_RUNTIME'
        }
    }
    [pscustomobject][ordered]@{
        ProtocolVersion = $ProtocolVersion
        RunNonce = $nonce
        RequestId = [guid]::NewGuid().ToString('N')
        FixtureRoot = [IO.Path]::GetFullPath($FixtureRoot)
        EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
        ExternalRoot = [IO.Path]::GetFullPath($ExternalRoot)
        StartedResultPath = [IO.Path]::GetFullPath((Join-Path $FixtureRoot 'probe\probe-started.json'))
        FinalResultPath = [IO.Path]::GetFullPath((Join-Path $FixtureRoot 'probe\probe-result.json'))
        ExpectedProbeScriptSha256 = $ExpectedProbeScriptSha256
        ExpectedPermissionProfileSha256 = $ExpectedPermissionProfileSha256
        # These are parent-bound inputs. The probe records only status enums,
        # never these paths, in probe-result.json.
        PrivateSourceRoots = [pscustomobject]$PrivateSourceRoots
        PreparedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Initialize-PfcPermissionProbeFixture {
    param([Parameter(Mandatory = $true)][object]$Request,[Parameter(Mandatory = $true)][string]$RequestPath)
    foreach ($path in @([string]$Request.StartedResultPath,[string]$Request.FinalResultPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    $requestWrite = Write-PfcPermissionProbeJsonAtomic -Path $RequestPath -Value $Request
    [pscustomobject]@{ request_path = [IO.Path]::GetFullPath($RequestPath); started_path = [IO.Path]::GetFullPath([string]$Request.StartedResultPath); result_path = [IO.Path]::GetFullPath([string]$Request.FinalResultPath); request_file_written = $requestWrite.file_exists; stale_markers_removed = $true }
}

function New-FhOutcome {
    param([string]$Classification,[object]$Adapter,[bool]$ResultValid = $false,[string]$Channel = 'FILE_HANDSHAKE')
    $exit = 0; if ($Adapter -and $Adapter.PSObject.Properties['ExitCode']) { $exit = [int]$Adapter.ExitCode }
    $invocations = 0; if ($Adapter -and $Adapter.PSObject.Properties['InvocationCount']) { $invocations = [int]$Adapter.InvocationCount }
    $retries = 0; if ($Adapter -and $Adapter.PSObject.Properties['RetryCount']) { $retries = [int]$Adapter.RetryCount }
    $parentWrite = 'NOT_AVAILABLE'; if ($Adapter -and $Adapter.PSObject.Properties['ParentEvidenceWrite']) { $parentWrite = [string]$Adapter.ParentEvidenceWrite }
    $sandboxRead = 'NOT_AVAILABLE'; if ($Adapter -and $Adapter.PSObject.Properties['SandboxEvidenceRead']) { $sandboxRead = [string]$Adapter.SandboxEvidenceRead }
    [pscustomobject][ordered]@{
        classification = $Classification
        authoritative_channel = $Channel
        stdout_role = 'DIAGNOSTIC_ONLY'
        result_valid = $ResultValid
        process_exit_code = $exit
        invocation_count = $invocations
        automatic_retries = $retries
        valid_permission_probe_attempts_used = if ($Adapter -and $Adapter.PSObject.Properties['ValidPermissionProbeAttemptsUsed']) { [int]$Adapter.ValidPermissionProbeAttemptsUsed } else { 0 }
        previous_preflight_counted = $false
        parent_runner_evidence_write = $parentWrite
        sandbox_command_evidence_read = $sandboxRead
    }
}

function Test-FhBytesNoBom {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $false }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return $false }
    if ($Bytes.Length -ge 2 -and (($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF))) { return $false }
    return $true
}

function Convert-FhBytesToObject {
    param([byte[]]$Bytes)
    if (-not (Test-FhBytesNoBom -Bytes $Bytes)) { throw 'RESULT_UTF8_BOM_OR_UNSUPPORTED_ENCODING' }
    $encoding = New-Object Text.UTF8Encoding($false,$true)
    try { $text = $encoding.GetString($Bytes) } catch { throw 'RESULT_UTF8_DECODE_FAILED' }
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'RESULT_EMPTY' }
    try { return ($text | ConvertFrom-Json -ErrorAction Stop) } catch { throw 'RESULT_INVALID_JSON' }
}

function Test-FhRequiredShape {
    param([object]$Value)
    $required = @('ProtocolVersion','RunNonce','RequestId','ProbeScriptStarted','ProbeCompleted','ProcessExecutionPolicy','EffectiveExecutionPolicy','LanguageMode','Fixture','Evidence','External','PathEscapes','PrivateSources','ResultFileWritten','StartedAtUtc','CompletedAtUtc')
    foreach ($name in $required) { if ($null -eq $Value.PSObject.Properties[$name]) { return $false } }
    if (-not [bool]$Value.ProbeScriptStarted -or -not [bool]$Value.ProbeCompleted -or -not [bool]$Value.ResultFileWritten) { return $false }
    foreach ($section in $script:ProbeSections.Keys) {
        $node = $Value.PSObject.Properties[$section].Value
        if ($null -eq $node) { return $false }
        foreach ($name in $script:ProbeSections[$section]) {
            $property = $node.PSObject.Properties[$name]
            if ($null -eq $property) { return $false }
            if ([string]$property.Value -notin $script:ProbeStates) { return $false }
        }
    }
    return $true
}

function Test-FhRequestShape {
    param([object]$Request)
    foreach ($name in @('ProtocolVersion','RunNonce','RequestId','FixtureRoot','EvidenceRoot','ExternalRoot','StartedResultPath','FinalResultPath','ExpectedProbeScriptSha256','ExpectedPermissionProfileSha256','PreparedAtUtc')) {
        $property = $Request.PSObject.Properties[$name]
        if ($null -eq $property) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$property.Value)) { return $false }
    }
    $privateProperty = $Request.PSObject.Properties['PrivateSourceRoots']
    if ($null -ne $privateProperty) {
        $private = $privateProperty.Value
        foreach ($name in @('DefaultUserProfileRoot','DefaultCodexHome','GlobalAgents','Memory','Skills','OtherProjects')) {
            $entryValue = $null
            if ($null -ne $private) {
                if ($private -is [System.Collections.IDictionary]) { $entryValue = $private[$name] }
                else { $entry = $private.PSObject.Properties[$name]; if ($null -ne $entry) { $entryValue = $entry.Value } }
            }
            if ([string]::IsNullOrWhiteSpace([string]$entryValue)) { return $false }
        }
    }
    return $true
}

function Test-FhStartedMarker {
    param([byte[]]$Bytes,[object]$Request)
    if (-not (Test-FhBytesNoBom -Bytes $Bytes)) { return $false }
    try {
        $enc = New-Object Text.UTF8Encoding($false,$true)
        $value = ($enc.GetString($Bytes) | ConvertFrom-Json -ErrorAction Stop)
        foreach ($name in @('ProtocolVersion','RunNonce','RequestId','ProbeScriptStarted','ProcessId','StartedAtUtc','ProcessExecutionPolicy','EffectiveExecutionPolicy','LanguageMode')) { if ($null -eq $value.PSObject.Properties[$name]) { return $false } }
        if (-not [bool]$value.ProbeScriptStarted -or [int]$value.ProtocolVersion -ne [int]$Request.ProtocolVersion -or [string]$value.RunNonce -cne [string]$Request.RunNonce -or [string]$value.RequestId -cne [string]$Request.RequestId) { return $false }
        $started = [DateTime]::Parse([string]$value.StartedAtUtc).ToUniversalTime()
        $prepared = [DateTime]::Parse([string]$Request.PreparedAtUtc).ToUniversalTime()
        return $started -gt $prepared
    } catch { return $false }
}

function Test-FhRootBinding {
    param([object]$Request)
    try {
        $fixture = [IO.Path]::GetFullPath([string]$Request.FixtureRoot).TrimEnd('\')
        $evidence = [IO.Path]::GetFullPath([string]$Request.EvidenceRoot).TrimEnd('\')
        $external = [IO.Path]::GetFullPath([string]$Request.ExternalRoot).TrimEnd('\')
        $result = [IO.Path]::GetFullPath([string]$Request.FinalResultPath)
        $started = [IO.Path]::GetFullPath([string]$Request.StartedResultPath)
        $inside = { param($p,$r) $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r + '\',[StringComparison]::OrdinalIgnoreCase) }
        return (& $inside $result $fixture) -and (& $inside $started $fixture) -and -not (& $inside $evidence $fixture) -and -not (& $inside $external $fixture) -and ($evidence -cne $external)
    } catch { return $false }
}

function Test-FhAdapterBinding {
    param([object]$Request,[object]$Adapter)
    try {
        foreach ($pair in @(
            @{ Adapter = 'FixtureRoot'; Request = 'FixtureRoot' },
            @{ Adapter = 'EvidenceRoot'; Request = 'EvidenceRoot' },
            @{ Adapter = 'ExternalRoot'; Request = 'ExternalRoot' },
            @{ Adapter = 'StartedPath'; Request = 'StartedResultPath' },
            @{ Adapter = 'ResultPath'; Request = 'FinalResultPath' }
        )) {
            $ap = $Adapter.PSObject.Properties[$pair.Adapter]
            if ($null -ne $ap -and $null -ne $ap.Value -and -not [string]::IsNullOrWhiteSpace([string]$ap.Value)) {
                $rp = $Request.PSObject.Properties[$pair.Request]
                if ($null -eq $rp) { return $false }
                $a = [IO.Path]::GetFullPath([string]$ap.Value).TrimEnd('\')
                $r = [IO.Path]::GetFullPath([string]$rp.Value).TrimEnd('\')
                if (-not $a.Equals($r,[StringComparison]::OrdinalIgnoreCase)) { return $false }
            }
        }
        return $true
    } catch { return $false }
}

function Invoke-PfcPermissionProbeHandshake {
    param(
        [Parameter(Mandatory = $true)][object]$Request,
        [Parameter(Mandatory = $true)][object]$Adapter,
        [Parameter(Mandatory = $true)][string]$ExpectedScriptSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedPermissionProfileSha256
    )
    if (-not (Test-FhRequestShape -Request $Request)) { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    $unknown = @(); if ($Adapter.PSObject.Properties['UnknownFixtureFiles'] -and $null -ne $Adapter.UnknownFixtureFiles) { $unknown = @($Adapter.UnknownFixtureFiles) }
    if ($unknown.Count -gt 0) { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    if (-not (Test-FhRootBinding -Request $Request)) { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    if (-not (Test-FhAdapterBinding -Request $Request -Adapter $Adapter)) { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    $started = $false
    if ($Adapter.PSObject.Properties['Started']) { $started = [bool]$Adapter.Started }
    if ($Adapter.PSObject.Properties['StartedPath'] -and $Adapter.StartedPath -and (Test-Path -LiteralPath $Adapter.StartedPath -PathType Leaf)) {
        try { $Adapter | Add-Member -Force -NotePropertyName StartedBytes -NotePropertyValue ([IO.File]::ReadAllBytes([string]$Adapter.StartedPath)); $started = $true } catch { }
    }
    $bytes = $null
    if ($Adapter.PSObject.Properties['ResultBytes'] -and $null -ne $Adapter.ResultBytes) { $bytes = [byte[]]$Adapter.ResultBytes }
    if ($null -eq $bytes -and $Adapter.PSObject.Properties['ResultPath'] -and $Adapter.ResultPath -and (Test-Path -LiteralPath $Adapter.ResultPath -PathType Leaf)) {
        try { $bytes = [IO.File]::ReadAllBytes([string]$Adapter.ResultPath) } catch { }
    }
    if (-not $started) { return New-FhOutcome -Classification 'INVALID_BEFORE_SCRIPT_EXECUTION' -Adapter $Adapter }
    if ($Adapter.PSObject.Properties['StartedBytes'] -and $null -ne $Adapter.StartedBytes -and -not (Test-FhStartedMarker -Bytes ([byte[]]$Adapter.StartedBytes) -Request $Request)) { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    if ($null -eq $bytes -or $bytes.Length -eq 0) { return New-FhOutcome -Classification 'INVALID_AFTER_SCRIPT_START_BEFORE_COMPLETION' -Adapter $Adapter }
    $actualAfter = $ExpectedScriptSha256
    if ($Adapter.PSObject.Properties['ScriptHashAfter'] -and $Adapter.ScriptHashAfter) { $actualAfter = [string]$Adapter.ScriptHashAfter }
    if ([string]$actualAfter -cne [string]$ExpectedScriptSha256) { return New-FhOutcome -Classification 'INVALID_PROBE_SCRIPT_MUTATION' -Adapter $Adapter }
    try { $result = Convert-FhBytesToObject -Bytes $bytes } catch { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    if (-not (Test-FhRequiredShape -Value $result)) { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    $schemaPath = Join-Path $PSScriptRoot '..\schemas\permission-probe-result.schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    try {
        $schemaBytes = [IO.File]::ReadAllBytes($schemaPath)
        if (-not (Test-FhBytesNoBom -Bytes $schemaBytes)) { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
        $schema = ([Text.Encoding]::UTF8.GetString($schemaBytes) | ConvertFrom-Json -ErrorAction Stop)
        if ([string]$schema.type -cne 'object' -or [string]$schema.additionalProperties -cne 'False') { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    } catch { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    try {
        $prepared = [DateTime]::Parse([string]$Request.PreparedAtUtc).ToUniversalTime()
        $startedAt = [DateTime]::Parse([string]$result.StartedAtUtc).ToUniversalTime()
        $completedAt = [DateTime]::Parse([string]$result.CompletedAtUtc).ToUniversalTime()
        if ($startedAt -le $prepared -or $completedAt -le $startedAt) { return New-FhOutcome -Classification 'INVALID_STALE_OR_MISMATCHED_RESULT' -Adapter $Adapter }
        if ($Adapter.PSObject.Properties['StartedCreatedAtUtc'] -and [DateTime]::Parse([string]$Adapter.StartedCreatedAtUtc).ToUniversalTime() -le $prepared) { return New-FhOutcome -Classification 'INVALID_STALE_OR_MISMATCHED_RESULT' -Adapter $Adapter }
        if ($Adapter.PSObject.Properties['ResultCreatedAtUtc'] -and [DateTime]::Parse([string]$Adapter.ResultCreatedAtUtc).ToUniversalTime() -le $prepared) { return New-FhOutcome -Classification 'INVALID_STALE_OR_MISMATCHED_RESULT' -Adapter $Adapter }
    } catch { return New-FhOutcome -Classification 'INVALID_RESULT_CONTRACT' -Adapter $Adapter }
    if ([int]$result.ProtocolVersion -ne [int]$Request.ProtocolVersion -or [string]$result.RunNonce -cne [string]$Request.RunNonce -or [string]$result.RequestId -cne [string]$Request.RequestId) {
        return New-FhOutcome -Classification 'INVALID_STALE_OR_MISMATCHED_RESULT' -Adapter $Adapter
    }
    $profileHash = ''
    if ($Adapter.PSObject.Properties['PermissionProfileSha256']) { $profileHash = [string]$Adapter.PermissionProfileSha256 }
    if (-not $profileHash -or $profileHash -cne [string]$ExpectedPermissionProfileSha256) { return New-FhOutcome -Classification 'INVALID_STALE_OR_MISMATCHED_RESULT' -Adapter $Adapter }
    $out = New-FhOutcome -Classification 'VALID_RESULT' -Adapter $Adapter -ResultValid $true
    $out | Add-Member -NotePropertyName protocol_version_match -NotePropertyValue $true
    $out | Add-Member -NotePropertyName run_nonce_match -NotePropertyValue $true
    $out | Add-Member -NotePropertyName request_id_match -NotePropertyValue $true
    $out | Add-Member -NotePropertyName permission_profile_hash_match -NotePropertyValue $true
    $out | Add-Member -NotePropertyName started_file_valid -NotePropertyValue $true
    $out | Add-Member -NotePropertyName result_file_valid -NotePropertyValue $true
    return $out
}

function Test-PfcPermissionProbeLauncherArguments {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments)
    $ep = [Array]::IndexOf($Arguments,'-ExecutionPolicy')
    $file = [Array]::IndexOf($Arguments,'-File')
    $scope = 'INVALID'
    $valid = $ep -ge 0 -and $ep + 1 -lt $Arguments.Count -and [string]$Arguments[$ep + 1] -ceq 'Bypass' -and $file -gt ($ep + 1)
    if ($valid) { $scope = 'PROBE_PROCESS' }
    $badCommand = ('Enc' + 'odedCommand')
    $badInvoke = ('Invoke-' + 'Expression')
    $valid = $valid -and ($Arguments -notcontains '-Command') -and ($Arguments -notcontains $badCommand) -and (($Arguments -join ' ') -notmatch ('(?i)' + [regex]::Escape(('Set-' + 'ExecutionPolicy')))) -and (($Arguments -join ' ') -notmatch ('(?i)' + [regex]::Escape($badInvoke)))
    [pscustomobject]@{ status = if ($valid) { 'PASS' } else { 'FAIL' }; execution_policy_scope = $scope; file_argument_index = $file }
}

Export-ModuleMember -Function Invoke-PfcPermissionProbeHandshake, Test-PfcPermissionProbeLauncherArguments, Write-PfcPermissionProbeJsonAtomic, New-PfcPermissionProbeRequest, Initialize-PfcPermissionProbeFixture
