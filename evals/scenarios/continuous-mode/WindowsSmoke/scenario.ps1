[CmdletBinding()]
param(
    [ValidateSet('RED','GREEN')][string]$Phase='GREEN',
    [Parameter(Mandatory=$true)][string]$RepositoryRoot
)
# Only the dedicated, explicitly selected suite invokes this script. RepositoryRoot
# locates code; Git, installation, checkpoint and recovery writes use fixture roots.
$ErrorActionPreference='Stop'
Import-Module (Join-Path $RepositoryRoot 'evals/lib/TestHarness.psm1') -Force
$proofs=@('activation-default','worktree-identity','resume-lease','prewrite-prereview','low-wave','pause-recovery','installer-update-rollback','no-remote-mutation')
$results=New-Object 'System.Collections.Generic.List[object]'
$box=$null; $current='dependencies'
function Add-SmokePass([string]$Id) { $results.Add((New-PfcResult -ScenarioId ('windows.'+$Id) -Status PASS -Message 'Local fixture assertions executed.')) }
function Invoke-CmSmokeInstallerProof {
    param([hashtable]$box,[string]$RepositoryRoot)
    $package=Join-Path $box.State 'package-source';[void](New-Item -ItemType Directory -Path $package)
    $installState=Join-Path $box.State 'installer';[void](New-Item -ItemType Directory -Path $installState)
    # The reviewed fixture bindings and lifecycle proof are structurally frozen.
    $sourcePlan=Get-PfcInstallPlan -SourceRoot $RepositoryRoot -UserHome $box.Home -StateRoot $installState
    foreach($file in $sourcePlan.Files) {$destination=Join-Path $package $file.RelativePath;[void](Assert-PfcSafePath -Path $destination -Root $package -Operation 'smoke-source-copy');[void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force);Copy-Item -LiteralPath $file.SourcePath -Destination $destination}
    $versionPath=Join-Path $package 'VERSION';Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'VERSION') -Destination $versionPath
    $packageBox=$box.Clone();$packageBox.Repo=$package;Initialize-CmFixtureGit $packageBox
    [void](Invoke-CmFixtureGit $packageBox @('add','--','skill','codex-agents','VERSION'));[void](Invoke-CmFixtureGit $packageBox @('commit','--quiet','-m','smoke installer source'))
    $localDoctor={param($manifest)
        foreach($file in $manifest.ManagedFiles) {Assert-PfcEqual -Expected $file.SHA256 -Actual (Get-PfcSha256 $file.DestinationPath) -ScenarioId 'windows.installed-hash'}
        Assert-PfcEqual -Expected 2 -Actual @($manifest.ManagedFiles|Where-Object {$_.RelativePath -like 'codex-agents/*'}).Count -ScenarioId 'windows.two-agents'
        [pscustomobject]@{status='PASS';specialist_capability='UNKNOWN';source='fixture-file-hash-verification'}
    }
    $plan=Get-PfcInstallPlan -SourceRoot $package -UserHome $box.Home -StateRoot $installState
    $installed=Invoke-PfcInstallPlan -Plan $plan -PassiveDoctor $localDoctor;Equal 'PASS' $installed.status
    $manifestPath=Join-Path $installState 'install-state.json';$manifest=Read-PfcManifest $manifestPath;$version=([IO.File]::ReadAllText($versionPath)).Trim()
    Equal $version $manifest.Version;Equal $version $manifest.InstallerVersion
    foreach($name in @('continuous-execution.md','risk-validation-policy.md','blocker-classification.md','readiness-and-recovery.md','continuous-authorization.yaml','wave-plan.yaml','known-limitations.md','blocker-fallback-matrix.md','continuation-checkpoint.md','wave-report.md')) {True (@($manifest.ManagedFiles|Where-Object {(Split-Path -Leaf $_.DestinationPath) -ceq $name}).Count -eq 1)}
    $selected=@($plan.Files|Where-Object RelativePath -ceq 'skill/project-flight-control/SKILL.md');Equal 1 $selected.Count
    $managedSource=$selected[0].SourcePath;$managedDestination=$selected[0].DestinationPath
    $initialBytes=[IO.File]::ReadAllBytes($managedDestination);$initialHash=Get-PfcSha256 $managedDestination
    $unknown=Join-Path $box.Home 'unknown-user-file.txt';[IO.File]::WriteAllText($unknown,'preserve unknown fixture bytes')

    # A real content/version change must replace installed bytes and back up old bytes.
    $firstVersion='0.2.0-smoke.1';True ($firstVersion -cne $version)
    $firstBytes=[byte[]]($initialBytes+[Text.Encoding]::UTF8.GetBytes("`n<!-- fixture update one -->`n"))
    [IO.File]::WriteAllBytes($managedSource,$firstBytes);[IO.File]::WriteAllText($versionPath,$firstVersion)
    $firstHash=Get-PfcSha256 $managedSource;True ($firstHash -cne $initialHash)
    [void](Invoke-CmFixtureGit $packageBox @('add','--',$selected[0].RelativePath,'VERSION'));[void](Invoke-CmFixtureGit $packageBox @('commit','--quiet','-m','smoke installer update one'))
    $updated=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan -SourceRoot $package -UserHome $box.Home -StateRoot $installState) -Update -PassiveDoctor $localDoctor
    Equal 'PASS' $updated.status;Equal $firstHash (Get-PfcSha256 $managedDestination)
    Equal ([Convert]::ToBase64String($firstBytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($managedDestination)))
    $manifest=Read-PfcManifest $manifestPath;Equal $firstVersion $manifest.Version;Equal $firstVersion $manifest.InstallerVersion
    $oldCopy=@(Get-ChildItem -LiteralPath $updated.backup_reference -File|Where-Object Name -like '*-SKILL.md');Equal 1 $oldCopy.Count
    Equal $initialHash (Get-PfcSha256 $oldCopy[0].FullName);Equal ([Convert]::ToBase64String($initialBytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($oldCopy[0].FullName)))
    Equal 'preserve unknown fixture bytes' ([IO.File]::ReadAllText($unknown))
    $beforeHome=Get-CmFixtureSnapshot $box.Home;$beforeManifest=[Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath))

    # A second, different payload is observed installed before manifest failure.
    $secondBytes=[byte[]]($firstBytes+[Text.Encoding]::UTF8.GetBytes("`n<!-- fixture update two -->`n"))
    [IO.File]::WriteAllBytes($managedSource,$secondBytes);[IO.File]::WriteAllText($versionPath,'0.2.0-smoke.2')
    $secondHash=Get-PfcSha256 $managedSource;True ($secondHash -cne $firstHash)
    [void](Invoke-CmFixtureGit $packageBox @('add','--',$selected[0].RelativePath,'VERSION'));[void](Invoke-CmFixtureGit $packageBox @('commit','--quiet','-m','smoke installer update two'))
    $injection=@{Reached=$false};$secondBase64=[Convert]::ToBase64String($secondBytes)
    $failManifest={param($m,$path,$backup)
        if((Get-PfcSha256 $managedDestination) -cne $secondHash -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($managedDestination)) -cne $secondBase64) {throw 'Second payload was not installed before injected failure'}
        $injection.Reached=$true;[IO.File]::WriteAllText($path,'injected partial manifest');throw 'fixture manifest failure'
    }.GetNewClosure()
    $rollback=Invoke-PfcInstallPlan -Plan (Get-PfcInstallPlan -SourceRoot $package -UserHome $box.Home -StateRoot $installState) -Update -PassiveDoctor $localDoctor -ManifestWriter $failManifest
    True $injection.Reached;Equal 'FAIL' $rollback.status;Equal 'PASS' $rollback.rollback_result
    Equal $firstHash (Get-PfcSha256 $managedDestination);Equal ([Convert]::ToBase64String($firstBytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($managedDestination)))
    Equal $beforeHome (Get-CmFixtureSnapshot $box.Home);Equal $beforeManifest ([Convert]::ToBase64String([IO.File]::ReadAllBytes($manifestPath)));Equal 'preserve unknown fixture bytes' ([IO.File]::ReadAllText($unknown))
    return $packageBox
}
try {
    foreach ($path in @('evals/lib/ContinuousMode.psm1','evals/tests/ContinuousMode.Tests.ps1','evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1','scripts/lib/ProjectFlightControl.Install.psm1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $path) -PathType Leaf)) {throw 'Required source dependency unavailable'}
    }
    Import-Module (Join-Path $RepositoryRoot 'evals/lib/ContinuousMode.psm1') -Force
    Import-Module (Join-Path $RepositoryRoot 'scripts/lib/ProjectFlightControl.Install.psm1') -Force
    . (Join-Path $RepositoryRoot 'evals/tests/ContinuousMode.Tests.ps1')
    . (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1')
    . (Get-PfcContinuousFixtureSetup)
    foreach ($name in @('Get-PfcInstallPlan','Invoke-PfcInstallPlan','Read-PfcManifest','Test-PfcPreWriteIdentityGate','Test-PfcPreReviewIdentityGate','Test-PfcContinuousTransition')) {
        if ($null -eq (Get-Command $name -ErrorAction SilentlyContinue)) {throw 'Required API unavailable'}
    }
    $box=New-CmScenarioSandbox -Prefix 'pfc-continuous-smoke-'
    Initialize-CmFixtureGit -Box $box
    $configBefore=Invoke-CmFixtureGit $box @('config','--local','--list'); True ($configBefore -notmatch '(?im)^remote\.')

    $current='activation-default'
    $write=New-CmPhysicalWriteFixture $box; $base=$write.WorkOrder.current_milestone_base_sha
    $before=Get-CmFixtureSnapshot $box.Root
    $t=TransitionFixture; $t.Context.explicit_continuous=$false
    $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t
    Equal 'DISABLED' $r.execution_state; Equal 'PAUSE_AFTER_MILESTONE' $r.next_action; True (-not $r.writes_allowed); Equal $before (Get-CmFixtureSnapshot $box.Root)
    $gate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $write; True $gate.can_issue_builder_lease
    $t=TransitionFixture; $x=$t.Context; $t.Event='APPROVE'; $t.AuthorizationStatus='NONE'; $t.ExecutionState='DISABLED'
    $x.invocation_mode='START'; $x.actual_head_sha=$base; $x.governance_head_sha=$base; $x.next_milestone_id='M-1'; $x.next_work_order_id='ORDER-1'; $x.pre_write_gate=$gate
    $x.runtime.control_run_id='RUN-1'; $x.runtime.lease_epoch=1
    $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t; Equal 'ARMED' $r.execution_state; True (-not $r.writes_allowed)
    $t.AuthorizationStatus=$r.authorization_status; $t.ExecutionState=$r.execution_state; $t.Event='ACTIVATE'
    True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).writes_allowed
    Add-SmokePass $current

    $current='worktree-identity'
    $linkedPath=Join-Path $box.State 'milestone-worktree'
    [void](Invoke-CmFixtureGit $box @('worktree','add','--quiet','-b','codex/pfc/AUTH-1/m-smoke',$linkedPath,'HEAD'))
    $linked=$box.Clone(); $linked.Repo=$linkedPath; $work=New-CmPhysicalWriteFixture $linked
    Equal $write.WorkOrder.repository_identity $work.WorkOrder.repository_identity; True ($write.WorkOrder.worktree_identity -cne $work.WorkOrder.worktree_identity)
    Equal 'codex/pfc/AUTH-1/m-smoke' $work.WorkOrder.exact_branch
    True (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $work).can_issue_builder_lease
    $correct=$work.BuilderEcho.worktree_identity; $work.BuilderEcho.worktree_identity=$write.WorkOrder.worktree_identity
    True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $work).can_issue_builder_lease); $work.BuilderEcho.worktree_identity=$correct
    Add-SmokePass $current

    $current='resume-lease'
    $authorizationBefore=$work.Authorization|ConvertTo-Json -Depth 40 -Compress
    $oldGate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $work
    foreach ($o in @($work.WorkOrder,$work.MilestoneContract,$work.BuilderEcho,$work.Checkpoint)) {$o.control_run_id='RUN-2';$o.lease_epoch=2}
    $gate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $work; True $gate.can_issue_builder_lease
    $t.Event='RESUME';$t.AuthorizationStatus='PAUSED';$t.ExecutionState='BLOCKED';$x.invocation_mode='RESUME';$x.runtime.control_run_id='RUN-2';$x.runtime.lease_epoch=2;$x.pre_write_gate=$oldGate
    True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).writes_allowed)
    $x.pre_write_gate=$gate; True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).writes_allowed
    Equal $authorizationBefore ($work.Authorization|ConvertTo-Json -Depth 40 -Compress)
    Add-SmokePass $current

    $current='prewrite-prereview'
    $source=Join-Path $linked.Repo 'src/a.ps1';[IO.File]::WriteAllText($source,'$x = 2')
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors);Equal 0 @($errors).Count
    Equal '$x = 2' ([IO.File]::ReadAllText($source))
    [void](Invoke-CmFixtureGit $linked @('add','--','src/a.ps1'));[void](Invoke-CmFixtureGit $linked @('commit','--quiet','-m','smoke LOW Candidate'))
    $candidate=Invoke-CmFixtureGit $linked @('rev-parse','HEAD');[void](Invoke-CmFixtureGit $linked @('merge-base','--is-ancestor',$base,$candidate))
    $review=New-CmReviewFromWrite $work $candidate
    $review.Observed.diff.changed_paths=@((Invoke-CmFixtureGit $linked @('diff','--name-only',$base,$candidate)) -split "`n")
    True ([string]::IsNullOrWhiteSpace((Invoke-CmFixtureGit $linked @('status','--porcelain'))))
    $reviewGate=Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $review;True $reviewGate.can_start_review
    $review.Observed.builder_evidence[0].candidate_sha=$base;True (-not (Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $review).can_start_review)
    $review.Observed.builder_evidence[0].candidate_sha=$candidate
    Add-SmokePass $current

    $current='low-wave'
    Equal 5 (Resolve-PfcRiskValidationPlan LOW @() NONE $limits).max_wave_size
    [IO.File]::WriteAllText((Join-Path $linked.Repo $controls[1]),'fixture acceptance '+$candidate)
    [void](Invoke-CmFixtureGit $linked @('add','--',$controls[1]));[void](Invoke-CmFixtureGit $linked @('commit','--quiet','-m','smoke accepted checkpoint'))
    $checkpoint=Invoke-CmFixtureGit $linked @('rev-parse','HEAD');[void](Invoke-CmFixtureGit $linked @('merge-base','--is-ancestor',$candidate,$checkpoint))
    $controlDiff=@((Invoke-CmFixtureGit $linked @('diff','--name-only',$candidate,$checkpoint)) -split "`n");Equal $controls[1] ($controlDiff -join ',')
    $controlHistory=@(foreach($line in ((Invoke-CmFixtureGit $linked @('rev-list','--reverse','--parents',($candidate+'..'+$checkpoint))) -split "`n")) {
        $parts=$line.Split(' ');True ($parts.Count -eq 2)
        $paths=@((Invoke-CmFixtureGit $linked @('diff-tree','--no-commit-id','--name-only','-r',$parts[0])) -split "`n" | Where-Object {$_})
        @{commit_sha=$parts[0];parent_shas=@($parts[1]);changed_paths=$paths}
    })
    $wave=TransitionFixture;$wave.Event='WAVE_END';$wc=$wave.Context
    $wc.candidate_sha=$candidate;$wc.evidence_sha=$candidate;$wc.acceptance_sha=$candidate;$wc.current_builder_start_sha=$base;$wc.current_pre_write_gate=$gate;$wc.pre_review_gate=$reviewGate
    $wc.accepted_checkpoint_sha=$checkpoint;$wc.actual_head_sha=$checkpoint;$wc.governance_head_sha=$checkpoint
    $wc.ancestry=@(@{ancestor_sha=$candidate;descendant_sha=$checkpoint;proven=$true});$wc.diffs=@(@{from_sha=$candidate;to_sha=$checkpoint;observed=$true;changed_paths=$controlDiff;commits=$controlHistory})
    # Deterministic local observations only; this never claims a real Agent review.
    $wc.independent_review.candidate_sha=$candidate;$wc.validation_plan=@(Plan @('T1','T2') $candidate PASS)
    $wc.validation_observations=@(foreach($tier in @('T1','T2')) {@{evidence_id='E-'+$tier;candidate_sha=$candidate;reference='evidence/reference';observed=$true;fresh=$true}})
    $wc.validation_observations+=@{evidence_id='E-T3';candidate_sha=$checkpoint;reference='evidence/reference';observed=$true;fresh=$true}
    $wc.frozen_wave.milestone_ids=@('M-1');$wc.wave_milestones=@(@{milestone_id='M-1';candidate_sha=$candidate;evidence_sha=$candidate;acceptance_sha=$candidate;accepted_checkpoint_sha=$checkpoint;result='PASS'})
    $wc.wave_t3=@(Plan @('T3') $checkpoint PASS)[0];$wc.wave_verifier.candidate_sha=$checkpoint
    $wc.wave_persistence.final_checkpoint_sha=$checkpoint;$wc.wave_persistence.control_commit_sha=$checkpoint;$wc.scope_exhausted=$true
    $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $wave;True $r.allowed;Equal 'COMPLETED' $r.execution_state
    Add-SmokePass $current

    $current='pause-recovery'
    $t.AuthorizationStatus='ACTIVE';$t.ExecutionState='ACTIVE';$t.Event='PAUSE'
    $paused=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t;Equal 'PAUSED' $paused.authorization_status;Equal 'PERSIST_CHECKPOINT' $paused.next_action
    $pausePath=Join-Path $box.State 'continuation.json';$pauseJson=@{authorization=$work.Authorization;checkpoint=$work.Checkpoint;runtime=$x.runtime;pause=$paused}|ConvertTo-Json -Depth 40 -Compress
    [IO.File]::WriteAllText($pausePath,$pauseJson);Equal $pauseJson ([IO.File]::ReadAllText($pausePath))
    [IO.File]::AppendAllText($source,"`n# known unfinished fixture repair")
    $copy=Join-Path $box.Recovery 'a.ps1';Copy-Item -LiteralPath $source -Destination $copy
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();$copyHash=(Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant()
    Equal $hash $copyHash;Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($source))) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($copy)))
    $size=(Get-Item -LiteralPath $source).Length;Equal $size (Get-Item -LiteralPath $copy).Length;Equal ' M src/a.ps1' (Invoke-CmFixtureGit $linked @('status','--porcelain','--','src/a.ps1'))
    foreach($o in @($work.WorkOrder,$work.MilestoneContract,$work.BuilderEcho,$work.Checkpoint)) {$o.expected_builder_start_sha=$checkpoint}
    $work.BuilderEcho.actual_worktree_head=$checkpoint;$work.Observed.actual_worktree_head=$checkpoint;$work.Observed.governance_head_sha=$checkpoint
    $work.Checkpoint.repair_budget.candidate_revisions=1;$work.Observed.candidate_sha=$candidate
    $work.Observed.ancestry=@(@{ancestor_sha=$base;descendant_sha=$candidate;proven=$true},@{ancestor_sha=$candidate;descendant_sha=$checkpoint;proven=$true});$work.Observed.diffs=$wc.diffs
    $work.Checkpoint.recovery_manifest.git_status=@(@{path='src/a.ps1';status=' M';original_path='NONE'})
    $work.Checkpoint.recovery_manifest.files=@(@{path='src/a.ps1';sha256=$hash;size_bytes=$size;recovery_copy='a.ps1';classification='ACTIVE'})
    $work.Observed.git_status=@(Clone-CmFixture $work.Checkpoint.recovery_manifest.git_status);$work.Observed.files=@(Clone-CmFixture $work.Checkpoint.recovery_manifest.files)
    $outsideRepository=-not (Resolve-Path -LiteralPath $copy).ProviderPath.StartsWith((Resolve-Path -LiteralPath $linked.Repo).ProviderPath+'\',[StringComparison]::OrdinalIgnoreCase)
    True $outsideRepository
    $work.Observed|Add-Member NoteProperty recovery_package @{recovery_package_reference='RECOVERY-1';outside_repository=$outsideRepository;verified=$true}
    $work.Observed|Add-Member NoteProperty recovery_copies @(@{path='src/a.ps1';sha256=$copyHash;size_bytes=$size;recovery_copy='a.ps1';recovery_package_reference='RECOVERY-1';verified=$true})
    $recoveryGate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $work;True $recoveryGate.can_issue_builder_lease
    $t.Event='RESUME';$x.unknown_dirty=$true;$x.actual_head_sha=$checkpoint;$x.governance_head_sha=$checkpoint
    $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t;Equal 'RECOVERY_REQUIRED' $r.readiness;True (-not $r.writes_allowed)
    $t.AuthorizationStatus='INVALIDATED';$t.ExecutionState='BLOCKED';$t.Event='RECOVERY_COMPLETE';$x.unknown_dirty=$false
    $x.recovery_checkpoint=$work.Checkpoint;$x.recovery_observed=$work.Observed;$x.recovery_writable_paths=@('src/a.ps1');$x.recovery_forbidden_paths=@('secrets');$x.pre_write_gate=$recoveryGate
    $x.recovery_steps=@(@('READ_ONLY_INVENTORY','EXTERNAL_RECOVERY_PACKAGE','HASH_SIZE_MANIFEST','CLASSIFICATION','REVERSIBLE_ISOLATION','GOVERNANCE_CHECKPOINT','PRE_WRITE_IDENTITY_GATE')|ForEach-Object {@{name=$_;checkpoint_sha=$checkpoint;recovery_package_reference='RECOVERY-1';observed=$true}})
    $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t;Equal 'READY_WITH_PRECONDITIONS' $r.readiness;Equal 'REQUEST_REAUTHORIZATION' $r.next_action;True (-not $r.writes_allowed)
    Add-SmokePass $current

    $current='installer-update-rollback'
    $packageBox=Invoke-CmSmokeInstallerProof $box $RepositoryRoot
    Add-SmokePass $current

    $current='no-remote-mutation'
    Equal $configBefore (Invoke-CmFixtureGit $box @('config','--local','--list'));True ((Invoke-CmFixtureGit $packageBox @('config','--local','--list')) -notmatch '(?im)^remote\.')
    True (-not (Test-Path -LiteralPath (Join-Path $box.Home '.codex/config.toml')))
    Add-SmokePass $current
} catch {
    $status=if($current -ceq 'dependencies') {'NOT_RUN'} else {'FAIL'}
    $detail=$_.Exception.Message.Replace($RepositoryRoot,'<source>')
    if($null -ne $box) {$detail=$detail.Replace($box.Root,'<fixture>')}
    $detail=$detail.Replace([IO.Path]::GetTempPath(),'<temp>/')
    $results.Add((New-PfcResult -ScenarioId ('windows.'+$current) -Status $status -Message ('Local proof '+$current+' did not complete: '+$detail)))
} finally {
    if($null -ne $box) {try {Remove-CmScenarioSandbox -Sandbox $box} catch {$results.Add((New-PfcResult -ScenarioId 'windows.cleanup' -Status FAIL -Message 'Cleanup boundary failed; fixture retained for inspection.'))}}
}
foreach($proof in $proofs) {if(@($results|Where-Object {$_.ScenarioId -ceq ('windows.'+$proof)}).Count -eq 0) {$results.Add((New-PfcResult -ScenarioId ('windows.'+$proof) -Status NOT_RUN -Message 'Prerequisite unavailable or failed; this proof was not executed.'))}}
$results.ToArray()
