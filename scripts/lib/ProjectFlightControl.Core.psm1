Set-StrictMode -Version 2.0

function Resolve-PfcPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'operation=resolve-path; path=<empty>; recovery=provide a path' }
    try { return [IO.Path]::GetFullPath($Path) } catch { throw "operation=resolve-path; path=$Path; recovery=provide a valid path" }
}

function Assert-PfcWithinRoot {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Root)
    $p = (Resolve-PfcPath $Path).TrimEnd('\'); $r = (Resolve-PfcPath $Root).TrimEnd('\')
    if (-not ($p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r + '\',[StringComparison]::OrdinalIgnoreCase))) {
        throw "operation=path-boundary; path=$p; recovery=choose a path inside the named root"
    }
    return $p
}

function Assert-PfcSafePath {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Root,[string]$Operation='path-safety')
    $full = Assert-PfcWithinRoot $Path $Root
    $cursor = $full
    while ($cursor) {
        try { $exists = Test-Path -LiteralPath $cursor -ErrorAction Stop } catch { throw "operation=$Operation; path=$cursor; recovery=choose an inspectable path without reparse points" }
        if ($exists) { break }
        $nextMissing = Split-Path -Parent $cursor; if ($nextMissing -eq $cursor) { $cursor = $null; break }; $cursor = $nextMissing
    }
    while ($cursor) {
        try { $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop } catch { throw "operation=$Operation; path=$cursor; recovery=choose an inspectable path without reparse points" }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "operation=$Operation; path=$cursor; recovery=remove the symlink or junction and retry" }
        $canonical = ([IO.Path]::GetFullPath($item.FullName)).TrimEnd('\')
        $lexical = ([IO.Path]::GetFullPath($cursor)).TrimEnd('\')
        if (-not $canonical.Equals($lexical,[StringComparison]::OrdinalIgnoreCase)) { throw "operation=$Operation; path=$cursor; recovery=choose a path whose canonical location matches the requested path" }
        $next = Split-Path -Parent $cursor; if ($next -eq $cursor) { break }; $cursor = $next
    }
    return $full
}

function Get-PfcSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full=Resolve-PfcPath $Path; Assert-PfcSafePath -Path $full -Root (Split-Path -Parent $full) -Operation 'hash-file' | Out-Null
    try { return (Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
    catch { throw "operation=hash-file; path=$full; recovery=restore an inspectable file and retry" }
}

function Get-PfcSourceIdentity {
    param([Parameter(Mandatory=$true)][string]$SourceRoot)
    $root = Assert-PfcSafePath -Path $SourceRoot -Root $SourceRoot -Operation 'source-identity'
    $version = $null; $versionPath = Join-Path $root 'VERSION'; Assert-PfcSafePath -Path $versionPath -Root $root -Operation 'source-version' | Out-Null
    try { if (Test-Path -LiteralPath $versionPath -PathType Leaf -ErrorAction Stop) { $version = (Get-Content -Raw -LiteralPath $versionPath -ErrorAction Stop).Trim() } }
    catch { throw "operation=source-version; path=$versionPath; recovery=restore an inspectable VERSION file and retry" }
    $commit = $null
    try { $commit = (& git -C $root rev-parse HEAD 2>$null).Trim() } catch { $commit = $null }
    if ($commit -and $commit -notmatch '^[0-9a-fA-F]{40}$') { $commit = $null }
    if (-not $commit -and -not $version) { throw "operation=source-identity; path=$root; recovery=provide a VERSION file or local Git HEAD" }
    if ($version -and $commit) { return "$version@$commit" }
    if ($commit) { return $commit }
    return $version
}

function Get-PfcTargetState {
    param([Parameter(Mandatory=$true)][string]$DestinationPath,[string]$ManagedHash,[string]$Root)
    $path = Resolve-PfcPath $DestinationPath
    $checkRoot = if ($Root) { $Root } else { Split-Path -Parent $path }
    Assert-PfcSafePath -Path $path -Root $checkRoot -Operation 'target-state' | Out-Null
    try { if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop)) { return 'ABSENT' } }
    catch { throw "operation=target-state; path=$path; recovery=choose an inspectable target path and retry" }
    if ([string]::IsNullOrWhiteSpace($ManagedHash)) { return 'UNMANAGED_CONFLICT' }
    if ((Get-PfcSha256 $path) -ceq $ManagedHash.ToLowerInvariant()) { return 'MANAGED_UNCHANGED' }
    return 'MANAGED_MODIFIED'
}

function Get-PfcInstallPlan {
    param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$UserHome,[Parameter(Mandatory=$true)][string]$StateRoot)
    $source = Assert-PfcSafePath -Path $SourceRoot -Root $SourceRoot -Operation 'validate-source'; $userRoot = Assert-PfcSafePath -Path $UserHome -Root $UserHome -Operation 'validate-user-root'; $state = Assert-PfcSafePath -Path $StateRoot -Root $StateRoot -Operation 'validate-state-root'
    $skillRoot = Join-Path $source 'skill\project-flight-control'; $agentRoot = Join-Path $source 'codex-agents'
    Assert-PfcSafePath -Path $skillRoot -Root $source -Operation 'validate-source' | Out-Null
    if (-not (Test-Path -LiteralPath $skillRoot -PathType Container -ErrorAction Stop)) { throw "operation=validate-source; path=$skillRoot; recovery=restore the skill package" }
    $items = New-Object System.Collections.Generic.List[object]
    try { $sourceFiles = @(Get-ChildItem -LiteralPath $skillRoot -File -Recurse -ErrorAction Stop) }
    catch { throw "operation=validate-source; path=$skillRoot; recovery=restore an inspectable skill package" }
    foreach ($file in $sourceFiles) {
        $rel = $file.FullName.Substring($skillRoot.Length).TrimStart('\'); $dest = Join-Path $userRoot (Join-Path '.codex\skills\project-flight-control' $rel)
        $dest = Assert-PfcSafePath -Path $dest -Root $userRoot -Operation 'validate-destination'
        $items.Add([pscustomobject]@{ SourcePath=$file.FullName; DestinationPath=$dest; RelativePath=('skill/project-flight-control/' + $rel.Replace('\','/')); SourceHash=(Get-PfcSha256 $file.FullName); Action='INSTALL' })
    }
    foreach ($name in @('project-flight-builder.toml','project-flight-verifier.toml')) {
        $src = Join-Path $agentRoot $name; Assert-PfcSafePath -Path $src -Root $source -Operation 'validate-source' | Out-Null; if (-not (Test-Path -LiteralPath $src -PathType Leaf -ErrorAction Stop)) { throw "operation=validate-source; path=$src; recovery=restore the two formal agent files" }
        $dest = Assert-PfcSafePath -Path (Join-Path $userRoot (Join-Path '.codex\agents' $name)) -Root $userRoot -Operation 'validate-destination'
        $items.Add([pscustomobject]@{ SourcePath=$src; DestinationPath=$dest; RelativePath=('codex-agents/' + $name); SourceHash=(Get-PfcSha256 $src); Action='INSTALL' })
    }
    [pscustomobject]@{ SourceRoot=$source; UserHome=$userRoot; StateRoot=$state; Files=$items.ToArray(); GeneratedAt=[DateTime]::UtcNow.ToString('o') }
}

function Write-PfcJsonAtomic {
    param([Parameter(Mandatory=$true)]$InputObject,[Parameter(Mandatory=$true)][string]$Path,[string]$BackupPath)
    $full = Resolve-PfcPath $Path; $dir = Split-Path -Parent $full; Assert-PfcSafePath -Path $full -Root $dir -Operation 'write-json' | Out-Null
    try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { throw "operation=write-json-parent; path=$dir; recovery=choose a writable manifest directory" }
    $tmp = "$full.tmp.$([guid]::NewGuid().ToString('N'))"
    try {
        Assert-PfcSafePath -Path $tmp -Root $dir -Operation 'write-json-temp' | Out-Null
        $InputObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmp -Encoding UTF8 -ErrorAction Stop
        Assert-PfcSafePath -Path $full -Root $dir -Operation 'write-json-replace' | Out-Null
        if (Test-Path -LiteralPath $full -PathType Leaf -ErrorAction Stop) {
            if (-not $BackupPath) { throw 'backup path required for replacement' }
            $backupFull = Resolve-PfcPath $BackupPath; $backupDir = Split-Path -Parent $backupFull; Assert-PfcSafePath -Path $backupFull -Root $backupDir -Operation 'write-json-backup' | Out-Null
            try { New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null } catch { throw "operation=write-json-backup-parent; path=$backupDir; recovery=choose a writable backup directory" }
            Assert-PfcSafePath -Path $full -Root $dir -Operation 'write-json-copy' | Out-Null; Assert-PfcSafePath -Path $backupFull -Root $backupDir -Operation 'write-json-copy-backup' | Out-Null
            if (-not (Test-Path -LiteralPath $backupFull -PathType Leaf -ErrorAction Stop)) { [IO.File]::Copy($full,$backupFull,$true) }
            Assert-PfcSafePath -Path $tmp -Root $dir -Operation 'write-json-replace-temp' | Out-Null; Assert-PfcSafePath -Path $full -Root $dir -Operation 'write-json-replace-destination' | Out-Null; Assert-PfcSafePath -Path $backupFull -Root $backupDir -Operation 'write-json-replace-backup' | Out-Null
            [IO.File]::Replace($tmp, $full, $backupFull)
        } else { Assert-PfcSafePath -Path $tmp -Root $dir -Operation 'write-json-move-temp' | Out-Null; Assert-PfcSafePath -Path $full -Root $dir -Operation 'write-json-move-destination' | Out-Null; [IO.File]::Move($tmp, $full) }
    } catch {
        $failure = $_; try { Assert-PfcSafePath -Path $tmp -Root $dir -Operation 'cleanup-json-temp' | Out-Null; if (Test-Path -LiteralPath $tmp -ErrorAction Stop) { Remove-Item -LiteralPath $tmp -Force -ErrorAction Stop } }
        catch { throw "operation=cleanup-json-temp; path=$tmp; recovery=remove the temporary manifest manually after verifying the manifest and backup" }
        throw "operation=write-json; path=$full; recovery=restore the prior manifest from backup"
    }
}

Export-ModuleMember -Function Resolve-PfcPath,Assert-PfcWithinRoot,Assert-PfcSafePath,Get-PfcSha256,Get-PfcSourceIdentity,Get-PfcTargetState,Get-PfcInstallPlan,Write-PfcJsonAtomic
