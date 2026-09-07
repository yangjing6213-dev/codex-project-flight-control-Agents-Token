Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'ProjectFlightControl.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProjectFlightControl.Doctor.psm1') -Force

function New-PfcError {
    param([string]$Operation,[string]$Path,[string]$Recovery,[object]$Inner)
    $e = "operation=$Operation; path=$Path; recovery=$Recovery"
    if ($Inner) { $e += "; detail=" + (($Inner.Exception.Message -replace '(?i)(token|password|secret|cookie|key)\s*=\s*[^;\s]+','$1=<REDACTED>') -replace '[\r\n]+',' ') }
    return $e
}

function Read-PfcManifest {
    param([string]$Path)
    $full = Resolve-PfcPath $Path; $parent = Split-Path -Parent $full
    Assert-PfcSafePath -Path $full -Root $parent -Operation 'read-manifest' | Out-Null
    try {
        if (-not (Test-Path -LiteralPath $full -PathType Leaf -ErrorAction Stop)) { return $null }
        return Get-Content -Raw -LiteralPath $full -ErrorAction Stop | ConvertFrom-Json
    } catch { throw (New-PfcError 'read-manifest' $full 'restore or remove the invalid install-state.json' $_) }
}

function Invoke-PfcInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Plan,
        [scriptblock]$PassiveDoctor = $null,
        [scriptblock]$CopyInvoker = $null,
        [scriptblock]$ManifestWriter = $null,
        [scriptblock]$RollbackInvoker = $null,
        [switch]$Update
    )
    $state = Assert-PfcSafePath -Path $Plan.StateRoot -Root $Plan.StateRoot -Operation 'validate-state-root'
    $userRoot = Assert-PfcSafePath -Path $Plan.UserHome -Root $Plan.UserHome -Operation 'validate-user-root'
    $manifestPath = Join-Path $state 'install-state.json'; $backupRoot = Join-Path $state 'backups'; $stagingRoot = Join-Path $state 'staging'; Assert-PfcSafePath $manifestPath $state 'validate-manifest' | Out-Null; Assert-PfcSafePath $backupRoot $state 'validate-backup-root' | Out-Null; Assert-PfcSafePath $stagingRoot $state 'validate-staging-root' | Out-Null
    try { New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null } catch { throw (New-PfcError 'create-backup-root' $backupRoot 'choose a writable state root' $_) }
    Assert-PfcSafePath -Path $manifestPath -Root $state -Operation 'read-manifest-bytes' | Out-Null
    $oldManifest = Read-PfcManifest $manifestPath
    $oldManifestBytes = if (Test-Path -LiteralPath $manifestPath -PathType Leaf -ErrorAction Stop) { Assert-PfcSafePath -Path $manifestPath -Root $state -Operation 'read-manifest-bytes' | Out-Null; [IO.File]::ReadAllBytes($manifestPath) } else { $null }
    $oldJson = if ($oldManifest) { $oldManifest | ConvertTo-Json -Depth 20 } else { $null }
    $backupId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N')
    $backupDir = Join-Path $backupRoot $backupId; $stageDir = Join-Path $stagingRoot $backupId; Assert-PfcSafePath $backupDir $state 'validate-backup' | Out-Null; Assert-PfcSafePath $stageDir $state 'validate-staging' | Out-Null
    $installed = New-Object System.Collections.Generic.List[string]; $backed = New-Object System.Collections.Generic.List[object]; $manifestBackup = $null
    $phase = 'VALIDATE_SOURCE'
    try {
        foreach ($item in @($Plan.Files)) {
            Assert-PfcSafePath -Path $item.SourcePath -Root $Plan.SourceRoot -Operation 'validate-source' | Out-Null
            if (-not (Test-Path -LiteralPath $item.SourcePath -PathType Leaf -ErrorAction Stop)) { throw (New-PfcError 'validate-source' $item.SourcePath 'restore the source package') }
            $item.SourceHash = Get-PfcSha256 $item.SourcePath
        }
        $phase = 'INSPECT_TARGETS'
        $oldByDest = @{}; if ($oldManifest -and $oldManifest.ManagedFiles) { foreach ($m in @($oldManifest.ManagedFiles)) { $oldDest = Assert-PfcSafePath -Path $m.DestinationPath -Root $userRoot -Operation 'inspect-manifest-destination'; $oldByDest[$oldDest] = $m } }
        foreach ($item in @($Plan.Files)) {
            $dest = Assert-PfcSafePath -Path $item.DestinationPath -Root $userRoot -Operation 'inspect-targets'; $item.DestinationPath = $dest
            $existing = if ($oldByDest.ContainsKey($dest)) { $oldByDest[$dest] } else { $null }
            $stateName = Get-PfcTargetState -DestinationPath $dest -ManagedHash $(if($existing){[string]$existing.SHA256}else{$null}) -Root $userRoot
            if ($stateName -in @('MANAGED_MODIFIED','UNMANAGED_CONFLICT')) { throw (New-PfcError 'inspect-targets' $dest 'restore the file or choose a clean isolated profile') }
            if ($stateName -eq 'MANAGED_UNCHANGED') { $item.Action = 'UPDATE' } else { $item.Action = 'INSTALL' }
        }
        $phase = 'STAGE_FILES'; Assert-PfcSafePath -Path $stageDir -Root $state -Operation 'create-staging' | Out-Null; try { New-Item -ItemType Directory -Path $stageDir -Force -ErrorAction Stop | Out-Null } catch { throw (New-PfcError 'create-staging' $stageDir 'choose a writable state root' $_) }; Assert-PfcSafePath -Path $stageDir -Root $state -Operation 'create-staging' | Out-Null
        foreach ($item in @($Plan.Files)) {
            $stage = Join-Path $stageDir ([guid]::NewGuid().ToString('N') + '-' + (Split-Path -Leaf $item.SourcePath));
            Assert-PfcSafePath -Path $item.SourcePath -Root $Plan.SourceRoot -Operation 'stage-source' | Out-Null; Assert-PfcSafePath -Path $stage -Root $state -Operation 'stage-destination' | Out-Null
            if ($CopyInvoker) { & $CopyInvoker $item.SourcePath $stage } else { Copy-Item -LiteralPath $item.SourcePath -Destination $stage -ErrorAction Stop }
            $item | Add-Member -NotePropertyName StagedPath -NotePropertyValue $stage -Force
        }
        $phase = 'VERIFY_STAGED_HASHES'; foreach ($item in @($Plan.Files)) { if ((Get-PfcSha256 $item.StagedPath) -cne $item.SourceHash) { throw (New-PfcError 'verify-staged-hashes' $item.StagedPath 'remove staging and retry') } }
        $phase = 'INSTALL'; Assert-PfcSafePath -Path $backupDir -Root $state -Operation 'create-backup' | Out-Null; try { New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null } catch { throw (New-PfcError 'create-backup' $backupDir 'choose a writable state root' $_) }; Assert-PfcSafePath -Path $backupDir -Root $state -Operation 'create-backup' | Out-Null
        foreach ($item in @($Plan.Files)) {
            $dest = $item.DestinationPath; $parent = Split-Path -Parent $dest; Assert-PfcSafePath $parent $userRoot 'validate-managed-parent' | Out-Null; try { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null } catch { throw (New-PfcError 'create-managed-parent' $parent 'choose a writable user home' $_) }; Assert-PfcSafePath $parent $userRoot 'validate-managed-parent' | Out-Null; Assert-PfcSafePath $dest $userRoot 'validate-destination' | Out-Null
            if (Test-Path -LiteralPath $dest -PathType Leaf -ErrorAction Stop) {
                $backup = Join-Path $backupDir ([guid]::NewGuid().ToString('N') + '-' + (Split-Path -Leaf $dest)); Assert-PfcSafePath $backup $state 'validate-backup-file' | Out-Null; Assert-PfcSafePath $dest $userRoot 'backup-source' | Out-Null; Assert-PfcSafePath $backup $state 'backup-destination' | Out-Null; [IO.File]::Copy($dest,$backup,$true)
                $backed.Add([pscustomobject]@{DestinationPath=$dest; BackupPath=$backup})
            }
            $installed.Add($dest)
            Assert-PfcSafePath -Path $item.StagedPath -Root $state -Operation 'install-source' | Out-Null; Assert-PfcSafePath -Path $dest -Root $userRoot -Operation 'install-destination' | Out-Null
            if ($CopyInvoker) { & $CopyInvoker $item.StagedPath $dest } else { [IO.File]::Copy($item.StagedPath,$dest,$true) }
        }
        $phase = 'WRITE_MANIFEST'
        $managed = @($Plan.Files | ForEach-Object { [pscustomobject]@{ DestinationPath=$_.DestinationPath; RelativePath=$_.RelativePath; SHA256=$_.SourceHash; SourcePath=$_.SourcePath } })
        $sourceVersion = $null; $versionPath = Join-Path $Plan.SourceRoot 'VERSION'; Assert-PfcSafePath -Path $versionPath -Root $Plan.SourceRoot -Operation 'source-version' | Out-Null; if (Test-Path -LiteralPath $versionPath -PathType Leaf -ErrorAction Stop) { $sourceVersion=(Get-Content -Raw -LiteralPath $versionPath -ErrorAction Stop).Trim() }
        $sourceCommit = (& git -C $Plan.SourceRoot rev-parse HEAD 2>$null).Trim(); if ($sourceCommit -notmatch '^[0-9a-fA-F]{40}$') { $sourceCommit=$null }
        $manifest = [pscustomobject]@{ Product='Project Flight Control'; Version='0.1.0-dev.0'; InstalledAt=[DateTime]::UtcNow.ToString('o'); SourceVersion=(Get-PfcSourceIdentity $Plan.SourceRoot); SourceCommit=$sourceCommit; SourceRoot=$Plan.SourceRoot; ManagedFiles=$managed; BackupReference=$backupDir; InstallerVersion='0.1.0-dev.0'; LastDoctor=$null; SpecialistCapabilityRecord=$null }
        $manifestBackup = Join-Path $backupDir 'install-state.json'; if ($ManifestWriter) { & $ManifestWriter $manifest $manifestPath $manifestBackup } else { Write-PfcJsonAtomic -InputObject $manifest -Path $manifestPath -BackupPath $manifestBackup }
        $phase = 'RUN_PASSIVE_DOCTOR'; $doctor = if ($PassiveDoctor) { & $PassiveDoctor $manifest } else { Invoke-PfcPassiveDoctor -UserHome $Plan.UserHome -StateRoot $Plan.StateRoot -RepositoryRoot $Plan.SourceRoot }
        if ($doctor -and $doctor.status -and [string]$doctor.status -notin @('PASS','OK')) { throw (New-PfcError 'run-passive-doctor' $state 'restore the previous install and inspect Doctor evidence') }
        $manifest.LastDoctor = $doctor
        if ($doctor -and $doctor.PSObject.Properties['specialist_capability'] -and $doctor.specialist_capability) {
            $doctorFingerprint = $null
            if ($doctor.PSObject.Properties['capability_fingerprint']) { $doctorFingerprint = [string]$doctor.capability_fingerprint }
            $record = [ordered]@{ status=[string]$doctor.specialist_capability; fingerprint=$doctorFingerprint; recorded_at=[DateTime]::UtcNow.ToString('o'); expires_at=[DateTime]::UtcNow.AddHours(24).ToString('o') }
            if ($doctor.PSObject.Properties['specialist_record']) { foreach ($p in $doctor.specialist_record.PSObject.Properties) { $record[$p.Name] = $p.Value } }
            $manifest.SpecialistCapabilityRecord = [pscustomobject]$record
        }
        if ($ManifestWriter) { & $ManifestWriter $manifest $manifestPath $manifestBackup } else { Write-PfcJsonAtomic -InputObject $manifest -Path $manifestPath -BackupPath $manifestBackup }
        return [pscustomobject]@{ status='PASS'; installed_files=$installed.ToArray(); backup_reference=$backupDir; rollback_result='NOT_REQUIRED'; manifest_path=$manifestPath; phase='PASS' }
    } catch {
        $original = $_; $rollback = 'PASS';
        try {
            if ($RollbackInvoker) { & $RollbackInvoker }
            foreach ($dest in $installed.ToArray()) { Assert-PfcSafePath -Path $dest -Root $userRoot -Operation 'rollback-delete' | Out-Null; if (Test-Path -LiteralPath $dest -PathType Leaf -ErrorAction Stop) { Assert-PfcSafePath -Path $dest -Root $userRoot -Operation 'rollback-delete' | Out-Null; Remove-Item -LiteralPath $dest -ErrorAction Stop } }
            foreach ($b in $backed.ToArray()) { $destParent = Split-Path -Parent $b.DestinationPath; Assert-PfcSafePath -Path $destParent -Root $userRoot -Operation 'rollback-parent' | Out-Null; try { New-Item -ItemType Directory -Path $destParent -Force -ErrorAction Stop | Out-Null } catch { throw (New-PfcError 'rollback-parent' $destParent 'restore the destination directory manually from retained backups' $_) }; Assert-PfcSafePath -Path $destParent -Root $userRoot -Operation 'rollback-parent' | Out-Null; Assert-PfcSafePath -Path $b.BackupPath -Root $state -Operation 'rollback-backup' | Out-Null; Assert-PfcSafePath -Path $b.DestinationPath -Root $userRoot -Operation 'rollback-destination' | Out-Null; [IO.File]::Copy($b.BackupPath,$b.DestinationPath,$true) }
            if ($oldManifestBytes -and $installed.Count -gt 0) { $tmpRollback="$manifestPath.rollback.$([guid]::NewGuid().ToString('N'))"; Assert-PfcSafePath -Path $tmpRollback -Root $state -Operation 'rollback-manifest-temp' | Out-Null; [IO.File]::WriteAllBytes($tmpRollback,$oldManifestBytes); $rb=(Join-Path $backupDir 'rollback-manifest.json'); Assert-PfcSafePath -Path $manifestPath -Root $state -Operation 'rollback-manifest-source' | Out-Null; Assert-PfcSafePath -Path $rb -Root $state -Operation 'rollback-manifest-backup' | Out-Null; [IO.File]::Copy($manifestPath,$rb,$true); Assert-PfcSafePath -Path $tmpRollback -Root $state -Operation 'rollback-manifest-temp' | Out-Null; Assert-PfcSafePath -Path $manifestPath -Root $state -Operation 'rollback-manifest-destination' | Out-Null; Assert-PfcSafePath -Path $rb -Root $state -Operation 'rollback-manifest-backup' | Out-Null; [IO.File]::Replace($tmpRollback,$manifestPath,$rb) } elseif (-not $oldJson -and (Test-Path -LiteralPath $manifestPath -ErrorAction Stop)) { Assert-PfcSafePath -Path $manifestPath -Root $state -Operation 'rollback-manifest-delete' | Out-Null; Remove-Item -LiteralPath $manifestPath -ErrorAction Stop }
        } catch { $rollback = 'MANUAL_RECOVERY_REQUIRED'; return [pscustomobject]@{ status='PARTIAL'; installed_files=$installed.ToArray(); backup_reference=$backupDir; rollback_result=$rollback; error=(New-PfcError $phase $manifestPath 'manual recovery required; backups retained' $_); phase=$phase } }
        return [pscustomobject]@{ status='FAIL'; installed_files=$installed.ToArray(); backup_reference=$backupDir; rollback_result=$rollback; error=(New-PfcError $phase $manifestPath 'previous files and manifest restored; inspect retained backups' $original); phase=$phase }
    } finally { try { Assert-PfcSafePath $stageDir $state 'cleanup-staging' | Out-Null; if (Test-Path -LiteralPath $stageDir -PathType Container -ErrorAction Stop) { Remove-Item -LiteralPath $stageDir -Recurse -ErrorAction Stop } } catch { throw (New-PfcError 'cleanup-staging' $stageDir 'remove staging manually after verifying the state root' $_) } }
}

function Invoke-PfcUninstall {
    param([Parameter(Mandatory=$true)][string]$UserHome,[Parameter(Mandatory=$true)][string]$StateRoot)
    $userRoot=Assert-PfcSafePath $UserHome $UserHome 'validate-user-root'; $state=Assert-PfcSafePath $StateRoot $StateRoot 'validate-state-root'; $manifestPath=Join-Path $state 'install-state.json'; Assert-PfcSafePath $manifestPath $state 'validate-manifest' | Out-Null; $m=Read-PfcManifest $manifestPath
    $removed=New-Object System.Collections.Generic.List[string]; $modified=New-Object System.Collections.Generic.List[string]; $unknown=New-Object System.Collections.Generic.List[string]
    if (-not $m) { return [pscustomobject]@{status='PASS'; removed=@(); retained_modified=@(); retained_unknown=@(); backups_retained=$true} }
    foreach ($entry in @($m.ManagedFiles)) {
        $dest=Assert-PfcSafePath -Path $entry.DestinationPath -Root $userRoot -Operation 'uninstall-inspect'
        Assert-PfcSafePath -Path $dest -Root $userRoot -Operation 'uninstall-inspect' | Out-Null
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf -ErrorAction Stop)) { continue }
        Assert-PfcSafePath -Path $dest -Root $userRoot -Operation 'uninstall-hash' | Out-Null
        if ((Get-PfcSha256 $dest) -ceq ([string]$entry.SHA256).ToLowerInvariant()) { try { Assert-PfcSafePath -Path $dest -Root $userRoot -Operation 'uninstall-delete' | Out-Null; Remove-Item -LiteralPath $dest -ErrorAction Stop; $removed.Add($dest) } catch { throw (New-PfcError 'uninstall-delete' $dest 'restore from backup or remove the lock and retry' $_) } } else { $modified.Add($dest) }
    }
    $managedPaths = @($m.ManagedFiles | ForEach-Object { Resolve-PfcPath $_.DestinationPath })
    $parents = @($managedPaths | ForEach-Object { Split-Path -Parent $_ } | Sort-Object -Unique)
    foreach ($parent in $parents) {
        Assert-PfcSafePath -Path $parent -Root $userRoot -Operation 'uninstall-parent' | Out-Null
        if (-not (Test-Path -LiteralPath $parent -PathType Container -ErrorAction Stop)) { continue }
        Assert-PfcSafePath -Path $parent -Root $userRoot -Operation 'uninstall-enumerate-unknown' | Out-Null
        try { $children=@(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop) } catch { throw (New-PfcError 'uninstall-enumerate-unknown' $parent 'inspect the managed parent and retry' $_) }
        foreach ($child in $children) {
            if ($managedPaths -notcontains (Resolve-PfcPath $child.FullName)) { $unknown.Add((Resolve-PfcPath $child.FullName)) }
        }
    }
    try { Assert-PfcSafePath -Path $manifestPath -Root $state -Operation 'uninstall-manifest-delete' | Out-Null; Remove-Item -LiteralPath $manifestPath -ErrorAction Stop } catch { throw (New-PfcError 'uninstall-manifest-delete' $manifestPath 'remove the lock or restore the manifest manually' $_) }
    [pscustomobject]@{status='PASS'; removed=$removed.ToArray(); retained_modified=$modified.ToArray(); retained_unknown=$unknown.ToArray(); backups_retained=$true}
}

Export-ModuleMember -Function Invoke-PfcInstallPlan,Invoke-PfcUninstall,Read-PfcManifest,Get-PfcInstallPlan,Get-PfcTargetState,Get-PfcSha256,Get-PfcSourceIdentity,Write-PfcJsonAtomic,Resolve-PfcPath,Assert-PfcWithinRoot,Assert-PfcSafePath
