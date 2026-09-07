Set-StrictMode -Version 2.0

function Get-PfcSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}

function Get-PfcControlledProfile {
    param(
        [string]$Root,
        [AllowNull()][string]$WorkingDirectory,
        [AllowNull()][string]$ResultRoot,
        [AllowNull()][string]$DefaultCodexHome
    )
    if ([string]::IsNullOrWhiteSpace($Root)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $Root = Join-Path $localAppData 'ProjectFlightControl\EvalProfile-v1'
    }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $profile = [ordered]@{
        root = $rootFull
        codex_home = Join-Path $rootFull 'codex-home'
        home = Join-Path $rootFull 'home'
        userprofile = Join-Path $rootFull 'userprofile'
        version = 1
        permission_profile_name = 'pfc-controlled'
        permission_profile_extends = ':workspace'
    }
    $profile.permission_profile_config_path = Join-Path $profile.codex_home 'config.toml'
    $profile.permission_profile_denied_paths = @()
    if ($ResultRoot) { $profile.permission_profile_denied_paths += [IO.Path]::GetFullPath($ResultRoot).TrimEnd('\') }
    if ($DefaultCodexHome) { $profile.permission_profile_denied_paths += [IO.Path]::GetFullPath($DefaultCodexHome).TrimEnd('\') }
    $profile.permission_profile_denied_paths = @($profile.permission_profile_denied_paths | Select-Object -Unique)
    $fingerprintText = (@($profile.root,$profile.codex_home,$profile.home,$profile.userprofile,$profile.version) -join "`n")
    $profile.profile_fingerprint = Get-PfcSha256Text $fingerprintText
    return [pscustomobject]$profile
}

function Initialize-PfcControlledProfile {
    param([Parameter(Mandatory = $true)]$Profile)
    foreach ($path in @($Profile.root,$Profile.codex_home,$Profile.home,$Profile.userprofile)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { throw 'Controlled profile path is a file.' }
        if (Test-Path -LiteralPath $path -PathType Container) {
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Controlled profile path traverses a reparse point.' }
        }
    }
    foreach ($path in @($Profile.root,$Profile.codex_home,$Profile.home,$Profile.userprofile)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }
    if (Test-Path -LiteralPath $Profile.permission_profile_config_path) {
        $configItem = Get-Item -LiteralPath $Profile.permission_profile_config_path -Force -ErrorAction Stop
        if (($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Controlled profile config traverses a reparse point.' }
    }
    $config = @(
        'default_permissions = "pfc-controlled"',
        '',
        '[permissions.pfc-controlled]',
        'description = "Project Flight Control isolated evaluation profile"',
        'extends = ":workspace"',
        '',
        '[permissions.pfc-controlled.filesystem.":workspace_roots"]',
        '"**/.env" = "deny"',
        '"**/*.env" = "deny"',
        '"**/auth.json" = "deny"',
        '',
        '[permissions.pfc-controlled.filesystem]'
    )
    foreach ($denied in @($Profile.permission_profile_denied_paths)) {
        if ([string]::IsNullOrWhiteSpace($denied)) { continue }
        $escaped = $denied.Replace('\','\\').Replace('"','\"')
        $config += ('"' + $escaped + '" = "deny"')
    }
    [IO.File]::WriteAllText($Profile.permission_profile_config_path, ($config -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    return (Test-PfcControlledProfileIsolation -Profile $Profile)
}

function Test-PfcControlledProfileIsolation {
    param(
        [Parameter(Mandatory = $true)]$Profile,
        [string]$WorkingDirectory,
        [string]$RepositoryRoot,
        [string]$ResultRoot
    )
    $prohibited = @('AGENTS.md','AGENTS.override.md','.mcp.json','mcp.json','settings.json','execpolicy','hooks','memories','skills','agents','browser')
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Profile.root,$Profile.codex_home,$Profile.home,$Profile.userprofile)) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            foreach ($entry in @(Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction Stop)) {
                $leaf = [string]$entry.Name
                $isOwnedConfig = $entry.FullName.Equals([IO.Path]::GetFullPath($Profile.permission_profile_config_path),[StringComparison]::OrdinalIgnoreCase)
                $isOwnedAuth = $entry.FullName.Equals([IO.Path]::GetFullPath((Join-Path $Profile.codex_home 'auth.json')),[StringComparison]::OrdinalIgnoreCase)
                if ($prohibited -contains $leaf -or $leaf -match '(?i)^(AGENTS(?:\.override)?\.md)$' -or (($leaf -ieq 'config.toml') -and -not $isOwnedConfig) -or (($leaf -ieq 'auth.json') -and -not $isOwnedAuth)) { [void]$found.Add($entry.FullName) }
            }
        }
    }
    $rootFull = [IO.Path]::GetFullPath($Profile.root).TrimEnd('\')
    $profilePathsContained = $true
    foreach ($candidatePath in @($Profile.codex_home,$Profile.home,$Profile.userprofile,$Profile.permission_profile_config_path)) {
        try {
            $candidateFull = [IO.Path]::GetFullPath($candidatePath).TrimEnd('\')
            if (-not ($candidateFull.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase) -or $candidateFull.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase))) { $profilePathsContained = $false }
        } catch { $profilePathsContained = $false }
    }
    $defaultHome = if ($env:CODEX_HOME) { [IO.Path]::GetFullPath($env:CODEX_HOME).TrimEnd('\') } else { '' }
    $locationsDistinct = @($Profile.codex_home,$Profile.home,$Profile.userprofile | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique).Count -eq 3
    $outsideRepo = $true
    $outsideResult = $true
    if ($RepositoryRoot) { $repo = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\'); $outsideRepo = -not ($rootFull.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $rootFull.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) }
    if ($ResultRoot) { $result = [IO.Path]::GetFullPath($ResultRoot).TrimEnd('\'); $outsideResult = -not ($rootFull.Equals($result,[StringComparison]::OrdinalIgnoreCase) -or $rootFull.StartsWith($result+'\',[StringComparison]::OrdinalIgnoreCase) -or $result.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase)) }
    $workingAncestors = @()
    if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        $current = [IO.Path]::GetFullPath($WorkingDirectory)
        while ($current) {
            foreach ($name in @('AGENTS.md','AGENTS.override.md')) { $candidate = Join-Path $current $name; if (Test-Path -LiteralPath $candidate -PathType Leaf) { $workingAncestors += $candidate } }
            $parent = Split-Path -Parent $current; if ($parent -eq $current) { break }; $current = $parent
        }
    }
    $reparse = $false
    foreach ($path in @($Profile.root,$Profile.codex_home,$Profile.home,$Profile.userprofile)) {
        if (Test-Path -LiteralPath $path) {
            try { $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $reparse = $true } } catch { $reparse = $true }
        }
    }
    $auth = Join-Path $Profile.codex_home 'auth.json'
    $authOwned = $false
    if (Test-Path -LiteralPath $auth -PathType Leaf) {
        try { $authOwned = (($auth -eq ([IO.Path]::GetFullPath($auth))) -and -not ((Get-Item -LiteralPath $auth -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) } catch { $authOwned = $false }
    }
    $contaminated = ($found.Count -gt 0 -or -not $locationsDistinct -or -not $profilePathsContained -or -not $outsideRepo -or -not $outsideResult -or $workingAncestors.Count -gt 0 -or $reparse -or ($auth -and (Test-Path -LiteralPath $auth) -and -not $authOwned))
    [pscustomobject]@{
        controlled_profile_isolation = if ($contaminated) { 'UNRESOLVED' } else { 'PASS' }
        controlled_profile_contaminated = $contaminated
        prohibited_sources_found = @($found | ForEach-Object { '<PROFILE_ENTRY>' })
        ancestor_instruction_sources = @($workingAncestors | ForEach-Object { '<ANCESTOR_INSTRUCTION>' })
        default_auth_file_copied_or_linked = $false
        default_auth_checked = $false
        controlled_auth_present = [bool](Test-Path -LiteralPath $auth -PathType Leaf)
        controlled_auth_owned = $authOwned
        permission_profile_name = $Profile.permission_profile_name
        permission_profile_extends = $Profile.permission_profile_extends
        permission_profile_config_path = $Profile.permission_profile_config_path
        permission_profile_denied_paths = @($Profile.permission_profile_denied_paths)
        reparse_detected = $reparse
        profile_fingerprint = $Profile.profile_fingerprint
        codex_home = $Profile.codex_home
        home = $Profile.home
        userprofile = $Profile.userprofile
        locations_distinct = $locationsDistinct
        profile_paths_contained = $profilePathsContained
    }
}

function Get-PfcControlledProfileEnvironment {
    param([Parameter(Mandatory = $true)]$Profile)
    return @{
        CODEX_HOME = [string]$Profile.codex_home
        HOME = [string]$Profile.home
        USERPROFILE = [string]$Profile.userprofile
    }
}

function Get-PfcControlledProfileConfig {
    param([Parameter(Mandatory = $true)]$Profile)
    if (-not (Test-Path -LiteralPath $Profile.permission_profile_config_path -PathType Leaf)) { throw 'Controlled profile config is missing.' }
    return [pscustomobject]@{ path = $Profile.permission_profile_config_path; profile = $Profile.permission_profile_name; source = 'CONTROLLED_PROFILE_CONFIG' }
}

Export-ModuleMember -Function Get-PfcControlledProfile,Initialize-PfcControlledProfile,Test-PfcControlledProfileIsolation,Get-PfcControlledProfileEnvironment,Get-PfcControlledProfileConfig
