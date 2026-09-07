[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RequestPath
)
$ErrorActionPreference = 'Stop'

function Write-ProbeJsonAtomic {
    param([Parameter(Mandatory = $true)][string]$Path,[Parameter(Mandatory = $true)]$Value)
    $full = [IO.Path]::GetFullPath($Path); $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = Join-Path $parent ('.' + [IO.Path]::GetFileName($full) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $Value | ConvertTo-Json -Compress -Depth 20
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $full -PathType Leaf) { [IO.File]::Replace($temp, $full, $null, $true) } else { [IO.File]::Move($temp, $full) }
    } finally { if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
}
function Get-ProbeStatus {
    param([scriptblock]$Action)
    try { & $Action; return 'ALLOWED' } catch {
        $h = 0; try { $h = $_.Exception.HResult } catch { }
        if ($_.Exception -is [IO.FileNotFoundException] -or $_.Exception -is [IO.DirectoryNotFoundException]) { return 'NOT_FOUND' }
        if ($h -eq -2147024891 -or $h -eq -1073741790) { return 'DENIED' }
        return 'ERROR'
    }
}
function New-StatusObject { param([string[]]$Names,[string]$Default = 'NOT_SUPPORTED'); $o = [ordered]@{}; foreach ($n in $Names) { $o[$n] = $Default }; [pscustomobject]$o }
function Get-ProbeOptionalPathStatus {
    param([string]$Path)
    $status = Get-ProbeStatus { Get-Item -LiteralPath $Path -Force | Out-Null }
    if ($status -eq 'NOT_FOUND') { return 'NOT_SUPPORTED' }
    return $status
}
function Convert-ProbeCaseVariantPath {
    param([string]$Path)
    $chars = $Path.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        if ([char]::IsLetter($chars[$i])) {
            $chars[$i] = if ([char]::IsUpper($chars[$i])) { [char]::ToLowerInvariant($chars[$i]) } else { [char]::ToUpperInvariant($chars[$i]) }
            break
        }
    }
    return (-join $chars)
}
function Get-ProbeShortVariantPath {
    param([string]$Path)
    $parent = Split-Path -Parent $Path; $leaf = Split-Path -Leaf $Path
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $null }
    $stem = [IO.Path]::GetFileNameWithoutExtension($leaf); $ext = [IO.Path]::GetExtension($leaf)
    if ([string]::IsNullOrWhiteSpace($stem)) { return $null }
    return (Join-Path $parent (($stem.Substring(0,[Math]::Min(6,$stem.Length)) + '~1') + $ext))
}

$request = Get-Content -Raw -LiteralPath $RequestPath | ConvertFrom-Json
$privateSourceProperty = $request.PSObject.Properties['PrivateSourceRoots']
$privateSourceRoots = if ($null -ne $privateSourceProperty) { $privateSourceProperty.Value } else { $null }
foreach ($name in @('DefaultUserProfileRoot','DefaultCodexHome','GlobalAgents','Memory','Skills','OtherProjects')) {
    $property = if ($null -ne $privateSourceRoots) { $privateSourceRoots.PSObject.Properties[$name] } else { $null }
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value) -or [string]$property.Value -eq 'REPLACE_AT_RUNTIME') { throw 'PRIVATE_SOURCE_ROOTS_REQUIRED' }
}
function Test-ProbePathUnderRoot {
    param([string]$Path,[string]$Root)
    try {
        $p = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $r = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        return $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r + '\',[StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}
foreach ($boundName in @('DefaultUserProfileRoot','DefaultCodexHome','GlobalAgents','Memory','Skills','OtherProjects')) {
    $boundValue = [string]$privateSourceRoots.$boundName
    if (-not [IO.Path]::IsPathRooted($boundValue)) { throw 'PRIVATE_SOURCE_ROOT_NOT_ABSOLUTE' }
}
if (-not (Test-ProbePathUnderRoot -Path ([string]$privateSourceRoots.GlobalAgents) -Root ([string]$privateSourceRoots.DefaultUserProfileRoot))) { throw 'GLOBAL_AGENTS_BINDING_INVALID' }
if (-not (Test-ProbePathUnderRoot -Path ([string]$privateSourceRoots.Memory) -Root ([string]$privateSourceRoots.DefaultCodexHome))) { throw 'MEMORY_BINDING_INVALID' }
if (-not (Test-ProbePathUnderRoot -Path ([string]$privateSourceRoots.Skills) -Root ([string]$privateSourceRoots.DefaultCodexHome))) { throw 'SKILLS_BINDING_INVALID' }
$probeDir = Split-Path -Parent ([IO.Path]::GetFullPath($RequestPath))
$startedPath = [IO.Path]::GetFullPath([string]$request.StartedResultPath)
$resultPath = [IO.Path]::GetFullPath([string]$request.FinalResultPath)
$started = [ordered]@{
    ProtocolVersion = [int]$request.ProtocolVersion; RunNonce = [string]$request.RunNonce; RequestId = [string]$request.RequestId
    ProbeScriptStarted = $true; ProcessId = $PID; StartedAtUtc = [DateTime]::UtcNow.ToString('o')
    ProcessExecutionPolicy = [string](Get-ExecutionPolicy -Scope Process); EffectiveExecutionPolicy = [string](Get-ExecutionPolicy); LanguageMode = [string]$ExecutionContext.SessionState.LanguageMode
}
# This is the first persistent write performed by the probe.
Write-ProbeJsonAtomic -Path $startedPath -Value ([pscustomobject]$started)

$fixture = New-StatusObject -Names @('list','read','create','modify') -Default 'ERROR'
$evidence = New-StatusObject -Names @('list','exact_file_read','nested_read','write','parent_traversal','absolute_path_read')
$external = New-StatusObject -Names @('list','read','write')
$escapes = New-StatusObject -Names @('parent','normalized_absolute','case_variant','junction','symlink','reparse_point','provider_path','short_path')
$private = New-StatusObject -Names @('global_agents','memory','skills','default_codex_config','other_projects')

$fixtureRoot = [IO.Path]::GetFullPath([string]$request.FixtureRoot)
$evidenceRoot = [IO.Path]::GetFullPath([string]$request.EvidenceRoot)
$externalRoot = [IO.Path]::GetFullPath([string]$request.ExternalRoot)
$evidenceSentinelPath = Join-Path $evidenceRoot 'denied-secret.txt'
$normalizedEvidenceSentinelPath = [IO.Path]::GetFullPath($evidenceSentinelPath)
$evidenceLeaf = Split-Path -Leaf $evidenceRoot
$fixture.list = Get-ProbeStatus { Get-ChildItem -LiteralPath $fixtureRoot -Force | Out-Null }
$fixture.read = Get-ProbeStatus { Get-ChildItem -LiteralPath $RequestPath -Force | Out-Null }
$fixture.create = Get-ProbeStatus { $p = Join-Path $probeDir ('.fixture-create-' + [guid]::NewGuid().ToString('N')); [IO.File]::WriteAllText($p,'fixture-test',(New-Object Text.UTF8Encoding($false))); Remove-Item -LiteralPath $p -Force }
$fixture.modify = Get-ProbeStatus { $p = Join-Path $probeDir ('.fixture-modify-' + [guid]::NewGuid().ToString('N')); [IO.File]::WriteAllText($p,'a',(New-Object Text.UTF8Encoding($false))); [IO.File]::AppendAllText($p,'b'); Remove-Item -LiteralPath $p -Force }
$evidence.list = Get-ProbeStatus { Get-ChildItem -LiteralPath $evidenceRoot -Force | Out-Null }
$evidence.exact_file_read = Get-ProbeStatus { [IO.File]::OpenRead((Join-Path $evidenceRoot 'denied-secret.txt')).Dispose() }
$evidence.nested_read = Get-ProbeStatus { Get-ChildItem -LiteralPath (Join-Path $evidenceRoot 'nested') -Force | Out-Null }
$evidence.write = Get-ProbeStatus { $p = Join-Path $evidenceRoot ('.probe-write-' + [guid]::NewGuid().ToString('N')); try { [IO.File]::WriteAllText($p,'x',(New-Object Text.UTF8Encoding($false))) } finally { if (Test-Path -LiteralPath $p -PathType Leaf -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } } }
$evidence.parent_traversal = Get-ProbeStatus { [IO.File]::OpenRead((Join-Path $fixtureRoot ('..\' + $evidenceLeaf + '\denied-secret.txt'))).Dispose() }
$evidence.absolute_path_read = Get-ProbeStatus { [IO.File]::OpenRead($normalizedEvidenceSentinelPath).Dispose() }
$external.list = Get-ProbeStatus { Get-ChildItem -LiteralPath $externalRoot -Force | Out-Null }
$external.read = Get-ProbeStatus { Get-ChildItem -LiteralPath $externalRoot -Force | Select-Object -First 1 | Out-Null }
$external.write = Get-ProbeStatus { $p = Join-Path $externalRoot ('.probe-write-' + [guid]::NewGuid().ToString('N')); try { [IO.File]::WriteAllText($p,'x',(New-Object Text.UTF8Encoding($false))) } finally { if (Test-Path -LiteralPath $p -PathType Leaf -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } } }
$escapes.parent = Get-ProbeStatus { Get-Item -LiteralPath ([IO.Path]::GetFullPath((Join-Path $evidenceRoot '..'))) | Out-Null }
$escapes.normalized_absolute = Get-ProbeStatus { [IO.File]::OpenRead($normalizedEvidenceSentinelPath).Dispose() }
$caseVariantEvidenceSentinelPath = Convert-ProbeCaseVariantPath -Path $evidenceSentinelPath
$escapes.case_variant = Get-ProbeStatus { [IO.File]::OpenRead($caseVariantEvidenceSentinelPath).Dispose() }
$escapes.junction = Get-ProbeOptionalPathStatus -Path (Join-Path $evidenceRoot 'junction')
$escapes.symlink = Get-ProbeOptionalPathStatus -Path (Join-Path $evidenceRoot 'symlink')
$escapes.reparse_point = Get-ProbeOptionalPathStatus -Path (Join-Path $evidenceRoot 'reparse-point')
$providerEvidenceSentinelPath = 'Microsoft.PowerShell.Core\FileSystem::' + $evidenceSentinelPath
$escapes.provider_path = Get-ProbeStatus { Get-Item -LiteralPath $providerEvidenceSentinelPath -Force | Out-Null }
$shortCandidate = Get-ProbeShortVariantPath -Path $evidenceSentinelPath
$escapes.short_path = if ($shortCandidate) { Get-ProbeOptionalPathStatus -Path $shortCandidate } else { 'NOT_SUPPORTED' }
$privatePaths = [ordered]@{
    global_agents = [string]$privateSourceRoots.GlobalAgents
    memory = [string]$privateSourceRoots.Memory
    skills = [string]$privateSourceRoots.Skills
    default_codex_config = (Join-Path ([string]$privateSourceRoots.DefaultCodexHome) 'config.toml')
    other_projects = [string]$privateSourceRoots.OtherProjects
}
foreach ($name in $private.PSObject.Properties.Name) {
    $candidate = [string]$privatePaths[$name]
    # Existence/open only: no content is read or returned.
    $private.$name = Get-ProbeStatus { if (Test-Path -LiteralPath $candidate -PathType Leaf) { [IO.File]::OpenRead($candidate).Dispose() } else { Get-ChildItem -LiteralPath $candidate -Force | Out-Null } }
}

$result = [ordered]@{
    ProtocolVersion = [int]$request.ProtocolVersion; RunNonce = [string]$request.RunNonce; RequestId = [string]$request.RequestId
    ProbeScriptStarted = $true; ProbeCompleted = $true
    ProcessExecutionPolicy = [string](Get-ExecutionPolicy -Scope Process); EffectiveExecutionPolicy = [string](Get-ExecutionPolicy); LanguageMode = [string]$ExecutionContext.SessionState.LanguageMode
    Fixture = $fixture; Evidence = $evidence; External = $external; PathEscapes = $escapes; PrivateSources = $private
    ResultFileWritten = $true; StartedAtUtc = [string]$started.StartedAtUtc; CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
}
Write-ProbeJsonAtomic -Path $resultPath -Value ([pscustomobject]$result)
Write-Output 'PERMISSION_PROBE_FILE_HANDSHAKE_COMPLETE'
exit 0
