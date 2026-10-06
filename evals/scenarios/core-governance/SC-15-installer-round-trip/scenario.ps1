param([ValidateSet('RED','GREEN')][string]$Phase='GREEN',[string]$RepositoryRoot=(Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $RepositoryRoot 'evals\lib\TestHarness.psm1') -Force
Import-Module (Join-Path $RepositoryRoot 'scripts\lib\ProjectFlightControl.Install.psm1') -Force
function New-Sc15Package {
    param([string]$Source,[string]$Destination,[string]$Version,[switch]$Legacy)
    New-Item -ItemType Directory -Path (Join-Path $Destination 'skill'),(Join-Path $Destination 'codex-agents') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Source 'skill\project-flight-control') -Destination (Join-Path $Destination 'skill') -Recurse
    foreach ($name in @('project-flight-builder.toml','project-flight-verifier.toml')) {
        Copy-Item -LiteralPath (Join-Path $Source ('codex-agents\' + $name)) -Destination (Join-Path $Destination 'codex-agents')
    }
    [IO.File]::WriteAllText((Join-Path $Destination 'VERSION'),$Version)
    if ($Legacy) {
        foreach ($name in @('assets/templates/continuous-authorization.yaml','assets/templates/wave-plan.yaml','assets/templates/known-limitations.md','assets/templates/blocker-fallback-matrix.md','assets/templates/continuation-checkpoint.md','assets/templates/wave-report.md','references/continuous-execution.md','references/risk-validation-policy.md','references/blocker-classification.md','references/readiness-and-recovery.md')) {
            Remove-Item -LiteralPath (Join-Path $Destination ('skill\project-flight-control\' + $name.Replace('/','\')))
        }
        Add-Content -LiteralPath (Join-Path $Destination 'skill\project-flight-control\SKILL.md') -Value 'V1 fixture content'
    }
}
function Get-Sc15Snapshot {
    param([string]$State)
    $path=Join-Path $State 'install-state.json'; $manifest=Read-PfcManifest $path; $files=@{}
    foreach ($entry in @($manifest.ManagedFiles)) { $files[[string]$entry.DestinationPath]=Get-PfcSha256 ([string]$entry.DestinationPath) }
    return [pscustomobject]@{ Bytes=[Convert]::ToBase64String([IO.File]::ReadAllBytes($path)); Files=$files }
}
function Assert-Sc15Snapshot {
    param($Snapshot,[string]$State,[string]$Id,[string[]]$NewPaths)
    foreach ($path in $Snapshot.Files.Keys) { Assert-PfcEqual $Snapshot.Files[$path] (Get-PfcSha256 $path) ($Id + '.old-file.' + (Split-Path -Leaf $path)) }
    Assert-PfcEqual $Snapshot.Bytes ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $State 'install-state.json')))) ($Id + '.manifest-bytes')
    foreach ($path in $NewPaths) { Assert-PfcTrue (-not (Test-Path -LiteralPath $path -PathType Leaf)) ($Id + '.new-absent.' + (Split-Path -Leaf $path)) 'absent' }
}
function Invoke-Sc15V2 {
    $results=New-Object System.Collections.Generic.List[object]
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $root=Join-Path $temp ('pfc-sc15-v2-' + [guid]::NewGuid().ToString('N'))
    $v1=Join-Path $root 'source-v1'; $v2=Join-Path $root 'source-v2'; $originalPath=$env:PATH
    try {
        $spyDir=Join-Path $root 'bin'; New-Item -ItemType Directory -Path $spyDir -Force | Out-Null
        $spyLog=Join-Path $root 'codex-invocations.txt'
        [IO.File]::WriteAllText((Join-Path $spyDir 'codex.cmd'),('@echo off' + "`r`n" + 'echo %*>>"' + $spyLog + '"' + "`r`n" + 'exit /b 91' + "`r`n"))
        $env:PATH=$spyDir + [IO.Path]::PathSeparator + $originalPath
        New-Sc15Package $RepositoryRoot $v1 '0.1.0-dev.0' -Legacy
        New-Sc15Package $RepositoryRoot $v2 '0.2.0-dev.0'
        $newNames=@('assets/templates/continuous-authorization.yaml','assets/templates/wave-plan.yaml','assets/templates/known-limitations.md','assets/templates/blocker-fallback-matrix.md','assets/templates/continuation-checkpoint.md','assets/templates/wave-report.md','references/continuous-execution.md','references/risk-validation-policy.md','references/blocker-classification.md','references/readiness-and-recovery.md')
        $expected=@(Get-ChildItem -LiteralPath (Join-Path $v2 'skill\project-flight-control') -File -Recurse | ForEach-Object { 'skill/project-flight-control/' + $_.FullName.Substring((Join-Path $v2 'skill\project-flight-control').Length).TrimStart('\').Replace('\','/') }) + @('codex-agents/project-flight-builder.toml','codex-agents/project-flight-verifier.toml')
        foreach ($name in $newNames) { Assert-PfcTrue ($expected -contains ('skill/project-flight-control/' + $name)) ('sc15.v2.package.' + $name) 'present'; Assert-PfcTrue (-not (Test-Path -LiteralPath (Join-Path $v1 ('skill\project-flight-control\' + $name.Replace('/','\'))))) ('sc15.v1.absent.' + $name) 'absent' }
        $schemas=@('continuous-authorization','wave-plan','continuation-checkpoint','issue-classification','wave-report')
        foreach ($name in $schemas) { Assert-PfcTrue (Test-Path -LiteralPath (Join-Path $RepositoryRoot ('evals\schemas\' + $name + '.schema.json')) -PathType Leaf) ('sc15.v2.schema-source.' + $name) 'repository-only source present' }
        $v2Home=Join-Path $root 'home'; $state=Join-Path $root 'state'; New-Item -ItemType Directory -Path $v2Home,$state -Force | Out-Null
        $first=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $v1 $v2Home $state) -PassiveDoctor { param($m) [pscustomobject]@{status='PASS';specialist_capability='UNKNOWN'} }
        Assert-PfcTrue ($first.status -eq 'PASS') 'sc15.v1.install' ('PASS; ' + [string]$first.error)
        $old=Get-Sc15Snapshot $state
        $oldManifest=Read-PfcManifest (Join-Path $state 'install-state.json')
        Assert-PfcEqual '0.1.0-dev.0' $oldManifest.Version 'sc15.v1.version'
        $unknown=Join-Path $v2Home '.codex\agents\unrelated.toml'; [IO.File]::WriteAllText($unknown,'keep unknown')
        $oldSkill=Join-Path $v2Home '.codex\skills\project-flight-control\SKILL.md'
        $oldSkillBytes=[Convert]::ToBase64String([IO.File]::ReadAllBytes($oldSkill))
        $plan=Get-PfcInstallPlan $v2 $v2Home $state
        $newPaths=@($plan.Files | Where-Object { $newNames -contains $_.RelativePath.Substring('skill/project-flight-control/'.Length) } | ForEach-Object { $_.DestinationPath })
        Assert-PfcEqual 10 $newPaths.Count 'sc15.v2.new-count'
        foreach ($kind in @('missing','blank')) {
            $invalid=Join-Path $root ('invalid-' + $kind)
            New-Sc15Package $RepositoryRoot $invalid '0.2.0-dev.0'
            if ($kind -eq 'missing') { Remove-Item -LiteralPath (Join-Path $invalid 'VERSION') }
            else { [IO.File]::WriteAllText((Join-Path $invalid 'VERSION'),'  ') }
            $invalidResult=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $invalid $v2Home $state) -Update -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}
            Assert-PfcEqual 'FAIL' $invalidResult.status ('sc15.v2.' + $kind + '-version')
            Assert-PfcEqual 'VALIDATE_SOURCE' $invalidResult.phase ('sc15.v2.' + $kind + '-version-phase')
            Assert-Sc15Snapshot $old $state ('sc15.v2.' + $kind) $newPaths
        }
        $collision=$newPaths[0]
        New-Item -ItemType Directory -Path (Split-Path -Parent $collision) -Force | Out-Null
        [IO.File]::WriteAllText($collision,'unknown V2 collision')
        $collisionResult=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $v2 $v2Home $state) -Update -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}
        Assert-PfcEqual 'FAIL' $collisionResult.status 'sc15.v2.unknown-collision'
        Assert-PfcEqual 'unknown V2 collision' ([IO.File]::ReadAllText($collision)) 'sc15.v2.unknown-collision-preserved'
        Assert-PfcEqual $old.Bytes ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $state 'install-state.json')))) 'sc15.v2.unknown-collision-manifest'
        Remove-Item -LiteralPath $collision
        $driftHome=Join-Path $root 'drift-home'; $driftState=Join-Path $root 'drift-state'
        New-Item -ItemType Directory -Path $driftHome,$driftState -Force | Out-Null
        $driftInitial=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $v1 $driftHome $driftState) -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}
        Assert-PfcEqual 'PASS' $driftInitial.status 'sc15.v2.version-drift-initial'
        $driftSnapshot=Get-Sc15Snapshot $driftState
        $driftPlan=Get-PfcInstallPlan $v2 $driftHome $driftState
        $driftNew=@($driftPlan.Files | Where-Object { $newNames -contains $_.RelativePath.Substring('skill/project-flight-control/'.Length) } | ForEach-Object { $_.DestinationPath })
        $versionPath=Join-Path $v2 'VERSION'; $flipped=$false
        $driftCopy={param($src,$dst) [IO.File]::Copy($src,$dst,$true); if (-not $flipped) { [IO.File]::WriteAllText($versionPath,'0.3.0-dev.0'); $flipped=$true }}.GetNewClosure()
        try { $driftResult=Invoke-PfcInstallPlan -Plan $driftPlan -Update -CopyInvoker $driftCopy -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}} }
        finally { [IO.File]::WriteAllText($versionPath,'0.2.0-dev.0') }
        Assert-PfcEqual 'FAIL' $driftResult.status 'sc15.v2.version-drift-rejected'
        Assert-PfcTrue ($driftResult.error -match 'operation=source-version-drift') 'sc15.v2.version-drift-reason' 'source-version-drift'
        Assert-PfcEqual 'PASS' $driftResult.rollback_result 'sc15.v2.version-drift-rollback'
        Assert-Sc15Snapshot $driftSnapshot $driftState 'sc15.v2.version-drift' $driftNew
        $doctorDrift={param($m) [IO.File]::WriteAllText($versionPath,'0.3.0-dev.0'); [pscustomobject]@{status='PASS'}}.GetNewClosure()
        try { $doctorDriftResult=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $v2 $driftHome $driftState) -Update -PassiveDoctor $doctorDrift }
        finally { [IO.File]::WriteAllText($versionPath,'0.2.0-dev.0') }
        Assert-PfcEqual 'FAIL' $doctorDriftResult.status 'sc15.v2.doctor-version-drift-rejected'
        Assert-PfcTrue ($doctorDriftResult.error -match 'operation=source-version-drift') 'sc15.v2.doctor-version-drift-reason' 'source-version-drift'
        Assert-PfcEqual 'PASS' $doctorDriftResult.rollback_result 'sc15.v2.doctor-version-drift-rollback'
        Assert-Sc15Snapshot $driftSnapshot $driftState 'sc15.v2.doctor-version-drift' $driftNew
        $results.Add((New-PfcResult 'sc15.v2.version-drift' 'PASS' 'source VERSION drift rejected with exact rollback'))
        $updated=Invoke-PfcInstallPlan -Plan $plan -Update -PassiveDoctor { param($m) [pscustomobject]@{status='PASS';specialist_capability='UNKNOWN'} }
        Assert-PfcEqual 'PASS' $updated.status 'sc15.v2.update'
        $manifest=Read-PfcManifest (Join-Path $state 'install-state.json')
        Assert-PfcEqual '0.2.0-dev.0' $manifest.Version 'sc15.v2.version'
        Assert-PfcEqual '0.2.0-dev.0' $manifest.InstallerVersion 'sc15.v2.installer-version'
        Assert-PfcEqual $expected.Count @($manifest.ManagedFiles).Count 'sc15.v2.managed-count'
        foreach ($entry in @($manifest.ManagedFiles)) {
            Assert-PfcTrue ($expected -contains $entry.RelativePath) ('sc15.v2.managed.' + $entry.RelativePath) 'managed'
            Assert-PfcEqual (Get-PfcSha256 ([string]$entry.SourcePath)) (Get-PfcSha256 ([string]$entry.DestinationPath)) ('sc15.v2.hash.' + $entry.RelativePath)
            Assert-PfcEqual (Get-PfcSha256 ([string]$entry.SourcePath)) $entry.SHA256 ('sc15.v2.manifest-hash.' + $entry.RelativePath)
            Assert-PfcTrue (-not ($entry.RelativePath -match '^evals/|\.schema\.json$|task-3-report')) ('sc15.v2.repository-only.' + $entry.RelativePath) 'excluded'
        }
        Assert-PfcEqual $expected.Count @($manifest.ManagedFiles | Select-Object -ExpandProperty RelativePath -Unique).Count 'sc15.v2.unique-paths'
        Assert-PfcEqual 2 @($manifest.ManagedFiles | Where-Object { $_.RelativePath -like 'codex-agents/*.toml' }).Count 'sc15.v2.two-agents'
        foreach ($name in $schemas) {
            Assert-PfcTrue (-not (Test-Path -LiteralPath (Join-Path $v2 ('evals\schemas\' + $name + '.schema.json')))) ('sc15.v2.schema-not-packaged.' + $name) 'absent'
            Assert-PfcTrue (-not (Test-Path -LiteralPath (Join-Path $v2Home ('.codex\skills\project-flight-control\evals\schemas\' + $name + '.schema.json')))) ('sc15.v2.schema-not-installed.' + $name) 'absent'
        }
        foreach ($name in $newNames) { Assert-PfcTrue (Test-Path -LiteralPath (Join-Path $v2Home ('.codex\skills\project-flight-control\' + $name.Replace('/','\'))) -PathType Leaf) ('sc15.v2.present.' + $name) 'present' }
        Assert-PfcTrue ($oldSkillBytes -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($oldSkill))) 'sc15.v2.replaced' 'different bytes'
        Assert-PfcTrue (@(Get-ChildItem -LiteralPath $updated.backup_reference -File | Where-Object { [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName)) -ceq $oldSkillBytes }).Count -eq 1) 'sc15.v2.old-bytes-backed-up' 'one backup'
        Assert-PfcTrue (Test-Path -LiteralPath $unknown -PathType Leaf) 'sc15.v2.unknown-preserved' 'present'
        $results.Add((New-PfcResult 'sc15.v2.update' 'PASS' 'V1 to V2 files, hashes, versions and prior-byte backup verified'))
        foreach ($kind in @('copy','manifest','doctor')) {
            $caseHome=Join-Path $root ($kind + '-home'); $caseState=Join-Path $root ($kind + '-state'); New-Item -ItemType Directory -Path $caseHome,$caseState -Force | Out-Null
            $initial=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $v1 $caseHome $caseState) -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}; Assert-PfcEqual 'PASS' $initial.status ('sc15.v2.' + $kind + '.initial')
            $snapshot=Get-Sc15Snapshot $caseState; $casePlan=Get-PfcInstallPlan $v2 $caseHome $caseState
            $caseNew=@($casePlan.Files | Where-Object { $newNames -contains $_.RelativePath.Substring('skill/project-flight-control/'.Length) } | ForEach-Object { $_.DestinationPath })
            if ($kind -eq 'copy') {
                $last=@($casePlan.Files)[-1].DestinationPath
                $copy={param($src,$dst) if($dst -ceq $last){ [IO.File]::WriteAllText($dst,'partial'); throw 'injected copy failure' }; [IO.File]::Copy($src,$dst,$true)}
                $failed=Invoke-PfcInstallPlan -Plan $casePlan -Update -CopyInvoker $copy -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}
            } elseif ($kind -eq 'manifest') {
                $writer={param($m,$p,$b) [IO.File]::WriteAllText($p,'partial'); throw 'injected manifest failure'}
                $failed=Invoke-PfcInstallPlan -Plan $casePlan -Update -ManifestWriter $writer -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}
            } else {
                $failed=Invoke-PfcInstallPlan -Plan $casePlan -Update -PassiveDoctor {param($m) [pscustomobject]@{status='FAIL'}}
            }
            Assert-PfcEqual 'FAIL' $failed.status ('sc15.v2.' + $kind + '.failure')
            Assert-PfcEqual 'PASS' $failed.rollback_result ('sc15.v2.' + $kind + '.rollback')
            Assert-Sc15Snapshot $snapshot $caseState ('sc15.v2.' + $kind) $caseNew
            $results.Add((New-PfcResult ('sc15.v2.' + $kind + '-rollback') 'PASS' 'old hashes and exact manifest restored; new files removed'))
        }
        $modified=$newPaths[0]; [IO.File]::AppendAllText($modified,'local change')
        $currentBytes=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $state 'install-state.json')))
        $conflict=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $v2 $v2Home $state) -Update -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}
        Assert-PfcEqual 'FAIL' $conflict.status 'sc15.v2.modified-stop'
        Assert-PfcTrue ((Get-Content -Raw -LiteralPath $modified) -match 'local change') 'sc15.v2.modified-preserved' 'present'
        Assert-PfcEqual $currentBytes ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $state 'install-state.json')))) 'sc15.v2.modified-manifest-preserved'
        $uninstalled=Invoke-PfcUninstall -UserHome $v2Home -StateRoot $state; Assert-PfcEqual 'PASS' $uninstalled.status 'sc15.v2.uninstall'
        foreach ($entry in @($manifest.ManagedFiles)) {
            if ($entry.DestinationPath -ceq $modified) { Assert-PfcTrue (Test-Path -LiteralPath $modified -PathType Leaf) 'sc15.v2.modified-retained' 'present' }
            else { Assert-PfcTrue (-not (Test-Path -LiteralPath $entry.DestinationPath -PathType Leaf)) ('sc15.v2.uninstalled.' + $entry.RelativePath) 'absent' }
        }
        Assert-PfcTrue (Test-Path -LiteralPath $unknown -PathType Leaf) 'sc15.v2.unknown-after-uninstall' 'present'
        Assert-PfcTrue (-not (Test-Path -LiteralPath $spyLog -PathType Leaf)) 'sc15.v2.no-model-or-smoke-invocation' 'no codex invocation'
        $results.Add((New-PfcResult 'sc15.v2.uninstall' 'PASS' 'only matching managed files removed'))
    } catch { $results.Add((New-PfcResult 'sc15.v2.failure' 'FAIL' $_.Exception.Message)) }
    finally {
        $env:PATH=$originalPath
        if (Test-Path -LiteralPath $root) {
            $resolved=(Resolve-Path -LiteralPath $root).Path
            if ((Split-Path -Parent $resolved) -cne $temp -or (Split-Path -Leaf $resolved) -notmatch '^pfc-sc15-v2-[a-f0-9]{32}$') { throw 'SC-15 V2 cleanup path escaped the disposable fixture root' }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    return $results.ToArray()
}
function Invoke-Sc15 {
    if ($Phase -eq 'RED') { return ,(New-PfcResult -ScenarioId 'SC-15.red-before-implementation' -Status 'FAIL' -Message 'Installer round-trip is intentionally RED before implementation') }
    $root=Join-Path ([IO.Path]::GetTempPath()) ('pfc-sc15-' + [guid]::NewGuid().ToString('N')); $fixtureHome=Join-Path $root 'home'; $state=Join-Path $root 'state'; New-Item -ItemType Directory -Path $fixtureHome,$state | Out-Null
    $results=New-Object System.Collections.Generic.List[object]
    try {
        $plan=Get-PfcInstallPlan -SourceRoot $RepositoryRoot -UserHome $fixtureHome -StateRoot $state
        $r=Invoke-PfcInstallPlan -Plan $plan -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'; specialist_capability='UNKNOWN'}}
        Assert-PfcEqual 'PASS' $r.status 'sc15.clean-install'; $manifest=Read-PfcManifest (Join-Path $state 'install-state.json'); Assert-PfcTrue (-not [string]::IsNullOrWhiteSpace([string]$manifest.SourceVersion)) 'sc15.source-version' 'True'; Assert-PfcTrue ([string]$manifest.SourceCommit -match '^[0-9a-f]{40}$') 'sc15.source-commit' 'True'; Assert-PfcEqual (Get-PfcSourceIdentity $RepositoryRoot) $manifest.SourceVersion 'sc15.source-identity'; Assert-PfcEqual ((Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'VERSION')).Trim()) $manifest.Version 'sc15.manifest-version'; Assert-PfcEqual ((Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'VERSION')).Trim()) $manifest.InstallerVersion 'sc15.installer-version'; $results.Add((New-PfcResult 'sc15.clean-install' 'PASS' 'installed in isolated temporary roots with source identity'))
        $r2=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state) -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}; Assert-PfcEqual 'PASS' $r2.status 'sc15.idempotent'; $results.Add((New-PfcResult 'sc15.idempotent' 'PASS' 'reinstall succeeds'))
        $target=@($plan.Files)[0].DestinationPath; Add-Content -LiteralPath $target -Value 'local change'; $r3=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state); Assert-PfcTrue ($r3.status -in @('FAIL','PARTIAL')) 'sc15.modified-stop' 'True'; Assert-PfcTrue (($r3.error -match 'operation=inspect-targets') -and ((Get-Content -Raw $target) -match 'local change')) 'sc15.modified-preserved' $r3.error; $results.Add((New-PfcResult 'sc15.modified-stop' 'PASS' ('managed modification preserved; ' + $r3.error)))
        Remove-Item -LiteralPath $target; $conflict=Join-Path $fixtureHome '.codex\agents\rogue.toml'; New-Item -ItemType Directory -Path (Split-Path -Parent $conflict) -Force|Out-Null; Set-Content $conflict 'unmanaged'; $r4=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state); Assert-PfcEqual 'PASS' $r4.status 'sc15.unmanaged-sibling'; $results.Add((New-PfcResult 'sc15.unmanaged-sibling' 'PASS' 'unknown sibling retained'))
        $fixtureHome2=Join-Path $root 'conflict-home'; $state2=Join-Path $root 'conflict-state'; New-Item -ItemType Directory -Path $fixtureHome2,$state2 | Out-Null; $p2=Get-PfcInstallPlan $RepositoryRoot $fixtureHome2 $state2; $c2=@($p2.Files)[0].DestinationPath; New-Item -ItemType Directory -Path (Split-Path -Parent $c2) -Force|Out-Null; Set-Content $c2 'unmanaged collision'; $r4b=Invoke-PfcInstallPlan -Plan $p2; Assert-PfcEqual 'FAIL' $r4b.status 'sc15.unmanaged-conflict'; Assert-PfcTrue ((Get-Content -Raw $c2) -match 'unmanaged collision') 'sc15.unmanaged-preserved' 'True'; $results.Add((New-PfcResult 'sc15.unmanaged-conflict' 'PASS' 'conflicting destination preserved'))
        $updateTarget=@((Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state).Files)[1].DestinationPath; $old=(Get-FileHash $updateTarget -Algorithm SHA256).Hash; $r5=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state) -Update -PassiveDoctor {param($m) [pscustomobject]@{status='PASS'}}; Assert-PfcEqual 'PASS' $r5.status 'sc15.update-backup'; $manifestAfterUpdate=Read-PfcManifest (Join-Path $state 'install-state.json'); Assert-PfcEqual (Get-PfcSourceIdentity $RepositoryRoot) $manifestAfterUpdate.SourceVersion 'sc15.update-source-identity'; Assert-PfcTrue (Test-Path $r5.backup_reference) 'sc15.backup-present' 'True'; $results.Add((New-PfcResult 'sc15.update-backup' 'PASS' 'timestamped backup created and source identity recorded'))
        $copyPlan=Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state; $selected=@($copyPlan.Files)[0].DestinationPath; Remove-Item -LiteralPath $selected; $beforeCopy=@{}; foreach($f in @($copyPlan.Files)){ $beforeCopy[$f.DestinationPath]=[pscustomobject]@{present=(Test-Path -LiteralPath $f.DestinationPath -PathType Leaf); hash=$(if(Test-Path -LiteralPath $f.DestinationPath -PathType Leaf){Get-PfcSha256 $f.DestinationPath}else{$null})} }; $manifestPath=Join-Path $state 'install-state.json'; $manifestBytesBefore=[IO.File]::ReadAllBytes($manifestPath)
        $copyFail={param($src,$dst) if($dst -ceq $selected){[IO.File]::WriteAllText($dst,'partial bytes'); throw 'injected install copy failure'}; [IO.File]::Copy($src,$dst,$true)}; $r6=Invoke-PfcInstallPlan -Plan $copyPlan -CopyInvoker $copyFail; Assert-PfcEqual 'FAIL' $r6.status 'sc15.copy-rollback'; foreach($k in $beforeCopy.Keys){$snap=$beforeCopy[$k]; Assert-PfcEqual $snap.present (Test-Path -LiteralPath $k -PathType Leaf) ('sc15.copy-presence.' + (Split-Path -Leaf $k)); if($snap.present){Assert-PfcTrue ((Get-PfcSha256 $k) -ceq $snap.hash) ('sc15.copy-restored.' + (Split-Path -Leaf $k)) 'True'}}; Assert-PfcTrue (-not (Test-Path -LiteralPath $selected -PathType Leaf)) 'sc15.copy-no-partial' 'True'; Assert-PfcTrue ([Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath)) -ceq [Convert]::ToBase64String($manifestBytesBefore)) 'sc15.copy-manifest-restored' 'True'; $results.Add((New-PfcResult 'sc15.copy-rollback' 'PASS' 'INSTALL partial copy restored bytes and manifest'))
        [IO.File]::Copy(@($copyPlan.Files)[0].SourcePath,$selected,$true); $beforeManifest=@{}; foreach($f in @((Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state).Files)){ $beforeManifest[$f.DestinationPath]=Get-PfcSha256 $f.DestinationPath }; $manifestBytesBefore2=[IO.File]::ReadAllBytes($manifestPath)
        $manifestFail={param($m,$p,$b) [IO.File]::WriteAllText($p,'partial manifest'); throw 'injected manifest failure'}; $r7=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state) -ManifestWriter $manifestFail; Assert-PfcTrue ($r7.status -in @('FAIL','PARTIAL')) 'sc15.manifest-rollback' 'True'; foreach($k in $beforeManifest.Keys){Assert-PfcTrue ((Get-PfcSha256 $k) -ceq $beforeManifest[$k]) ('sc15.manifest-restored.' + (Split-Path -Leaf $k)) 'True'}; Assert-PfcTrue ([Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath)) -ceq [Convert]::ToBase64String($manifestBytesBefore2)) 'sc15.manifest-bytes-restored' 'True'; $results.Add((New-PfcResult 'sc15.manifest-rollback' 'PASS' 'manifest failure restored bytes and manifest'))
        $r8=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan $RepositoryRoot $fixtureHome $state) -ManifestWriter {param($m,$p,$b) throw 'injected manifest failure'} -RollbackInvoker { throw 'injected rollback failure' }; Assert-PfcEqual 'PARTIAL' $r8.status 'sc15.rollback-failure'; Assert-PfcEqual 'MANUAL_RECOVERY_REQUIRED' $r8.rollback_result 'sc15.manual-recovery'; $results.Add((New-PfcResult 'sc15.rollback-failure' 'PASS' 'rollback failure is partial/manual recovery'))
        $managedForUninstall=@($plan.Files)[0].DestinationPath; Add-Content -LiteralPath $managedForUninstall -Value 'modified before uninstall'; $unknownDir=Join-Path (Split-Path -Parent $managedForUninstall) 'unknown-dir'; New-Item -ItemType Directory -Path $unknownDir -Force|Out-Null; Set-Content (Join-Path $unknownDir 'keep.txt') 'keep'; $u=Invoke-PfcUninstall -UserHome $fixtureHome -StateRoot $state; Assert-PfcEqual 'PASS' $u.status 'sc15.uninstall'; Assert-PfcTrue ($u.removed.Count -gt 0) 'sc15.uninstall-removed' 'True'; Assert-PfcTrue ($u.retained_modified -contains $managedForUninstall) 'sc15.modified-retained' 'True'; Assert-PfcTrue ($u.retained_unknown.Count -gt 0) 'sc15.unknown-listed' 'True'; Assert-PfcTrue (Test-Path $conflict) 'sc15.unknown-retained' 'True'; Assert-PfcTrue (Test-Path $unknownDir) 'sc15.unknown-dir-retained' 'True'; Assert-PfcTrue (Test-Path $r5.backup_reference) 'sc15.backups-retained' 'True'; $results.Add((New-PfcResult 'sc15.uninstall' 'PASS' 'hash-matching files removed; modified and unknown retained'))
        foreach ($result in @(Invoke-Sc15V2)) { $results.Add($result) }
    } catch { $results.Add((New-PfcResult 'sc15.failure' 'FAIL' $_.Exception.Message)) }
    finally {
        if (Test-Path -LiteralPath $root) {
            $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
            $resolved=(Resolve-Path -LiteralPath $root).Path
            if ((Split-Path -Parent $resolved) -cne $temp -or (Split-Path -Leaf $resolved) -notmatch '^pfc-sc15-[a-f0-9]{32}$') { throw 'SC-15 cleanup path escaped the disposable fixture root' }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    return $results.ToArray()
}
Invoke-Sc15
