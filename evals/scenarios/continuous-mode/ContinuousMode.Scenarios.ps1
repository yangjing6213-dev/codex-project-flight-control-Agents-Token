# Data and test helpers only. Dot-sourcing does not create fixtures or run cases.
# The accepted Task 7 fixture constructors are shared from ContinuousMode.Tests.ps1.
function Invoke-CmScenarioOracle {
    param([ValidateSet('Get-PfcRepositoryIdentityV1','Get-PfcRepoPathSetIdentityV1','Get-PfcWorktreeIdentityV1','Test-PfcPreWriteIdentityGate','Test-PfcPreReviewIdentityGate','Resolve-PfcRiskValidationPlan','Resolve-PfcIssueDisposition','Test-PfcRepairBudget','Test-PfcContinuousTransition')][string]$Name, [hashtable]$Inputs)
    $before = $Inputs | ConvertTo-Json -Depth 70 -Compress
    $answer = & $Name @Inputs
    Assert-PfcTrue -Actual ($null -ne $answer) -ScenarioId $Name -Expected 'oracle result'
    Assert-PfcEqual -Expected $before -Actual ($Inputs | ConvertTo-Json -Depth 70 -Compress) -ScenarioId ($Name + '.immutable-input')
    return $answer
}

function Test-CmFixtureBoundary {
    param([string]$Root, [string]$TempRoot, [string]$Prefix, [object[]]$Nodes = @())
    if (@('pfc-continuous-case-','pfc-continuous-smoke-') -cnotcontains $Prefix) { return $false }
    $temp = [IO.Path]::GetFullPath($TempRoot).TrimEnd('\','/')
    $full = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($full, $Root.TrimEnd('\','/'))) { return $false }
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals((Split-Path -Parent $full), $temp)) { return $false }
    if ((Split-Path -Leaf $full) -cnotmatch ('\A' + [regex]::Escape($Prefix) + '[0-9a-f]{32}\z')) { return $false }
    foreach ($node in $Nodes) {
        if (($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($node.FullName, $full) -and -not $node.FullName.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
}

function New-CmScenarioSandbox {
    param([string]$Prefix = 'pfc-continuous-case-')
    $temp = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).ProviderPath.TrimEnd('\','/')
    if (((Get-Item -LiteralPath $temp).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Temporary root is a reparse point' }
    $owner = [guid]::NewGuid().ToString('N')
    $root = Join-Path $temp ($Prefix + $owner)
    if (-not (Test-CmFixtureBoundary $root $temp $Prefix)) { throw 'Unsafe fixture creation boundary' }
    if (Test-Path -LiteralPath $root) { throw 'Fixture already exists' }
    [void](New-Item -ItemType Directory -Path $root)
    [IO.File]::WriteAllText((Join-Path $root '.owner'), $owner)
    $box = @{Root=$root;TempRoot=$temp;Prefix=$Prefix;Owner=$owner}
    foreach ($pair in @(@('Repo','fixture-repo'),@('Home','fixture-home'),@('State','fixture-state'),@('Recovery','fixture-recovery'))) {
        $box[$pair[0]] = Join-Path $root $pair[1]
        [void](New-Item -ItemType Directory -Path $box[$pair[0]])
    }
    return $box
}

function Remove-CmScenarioSandbox {
    param([hashtable]$Sandbox)
    $temp = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).ProviderPath.TrimEnd('\','/')
    $root = (Resolve-Path -LiteralPath $Sandbox.Root).ProviderPath.TrimEnd('\','/')
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($temp, $Sandbox.TempRoot)) { throw 'Fixture temp root changed' }
    if (-not (Test-CmFixtureBoundary $root $temp $Sandbox.Prefix @((Get-Item -LiteralPath $root)))) { throw 'Unsafe fixture cleanup boundary' }
    if ([IO.File]::ReadAllText((Join-Path $root '.owner')) -cne $Sandbox.Owner) { throw 'Fixture owner mismatch' }
    # Inspect each directory before entering it; do not follow a reparse child.
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue($root)
    while ($pending.Count -gt 0) {
        $parent = $pending.Dequeue()
        foreach ($node in @(Get-ChildItem -LiteralPath $parent -Force)) {
            if (-not (Test-CmFixtureBoundary $root $temp $Sandbox.Prefix @($node))) { throw 'Reparse or escaping fixture node; preserve fixture' }
            if ($parent -ceq $root -and @('.owner','fixture-repo','fixture-home','fixture-state','fixture-recovery') -cnotcontains $node.Name) { throw 'Unknown fixture root child; preserve fixture' }
            if ($node.PSIsContainer) { $pending.Enqueue($node.FullName) }
        }
    }
    Remove-Item -LiteralPath $root -Recurse -Force
}

function Invoke-CmFixtureGit {
    param([hashtable]$Box, [string[]]$Arguments)
    # Fail before any Git call. Only the display-only pager setting is tolerated;
    # --no-pager below prevents even that inherited command from being launched.
    $gitEnvironment=@([Environment]::GetEnvironmentVariables('Process').Keys | Where-Object { $_.StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase) -and $_ -ine 'GIT_PAGER' })
    if ($gitEnvironment.Count -gt 0) { throw 'INHERITED_GIT_ENVIRONMENT' }
    if (@('init','config','add','commit','rev-parse','rev-list','diff-tree','diff','merge-base','status','worktree') -cnotcontains $Arguments[0] -or $Arguments -ccontains '--global' -or $Arguments -ccontains '--system') { throw 'Fixture Git command not allowed' }
    if ($Arguments[0] -ceq 'config' -and $Arguments -cnotcontains '--local') { throw 'Only local fixture Git configuration is allowed' }
    if ($Arguments[0] -ceq 'config' -and @('--list','user.name','user.email','commit.gpgsign','core.autocrlf','core.hooksPath') -cnotcontains $Arguments[2]) { throw 'Fixture Git configuration key not allowed' }
    $resolvedRepo=(Resolve-Path -LiteralPath $Box.Repo).ProviderPath
    if (-not $resolvedRepo.StartsWith($Box.Root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Git target outside fixture' }
    if ($Arguments[0] -ceq 'worktree' -and ($Arguments.Count -ne 7 -or $Arguments[1] -cne 'add' -or $Arguments[2] -cne '--quiet' -or $Arguments[3] -cne '-b' -or $Arguments[4] -cne 'codex/pfc/AUTH-1/m-smoke' -or -not [IO.Path]::GetFullPath($Arguments[5]).StartsWith($Box.State+'\',[StringComparison]::OrdinalIgnoreCase) -or $Arguments[6] -cne 'HEAD')) { throw 'Unbounded fixture worktree request' }
    $output = @(& git --no-pager -C $Box.Repo @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('Fixture Git failed: ' + $Arguments[0]) }
    return ($output -join "`n")
}

function Initialize-CmFixtureGit {
    param([hashtable]$Box)
    [void](Invoke-CmFixtureGit $Box @('init','--quiet','-b','codex/pfc/AUTH-1/m-1'))
    foreach ($pair in @(@('user.name','PFC Fixture'),@('user.email','fixture@example.invalid'),@('commit.gpgsign','false'),@('core.autocrlf','false'),@('core.hooksPath',$Box.State))) {
        [void](Invoke-CmFixtureGit $Box @('config','--local',$pair[0],$pair[1]))
    }
    [void](New-Item -ItemType Directory -Path (Join-Path $Box.Repo 'src'))
    [void](New-Item -ItemType Directory -Path (Join-Path $Box.Repo 'docs/project-control') -Force)
    [IO.File]::WriteAllText((Join-Path $Box.Repo 'src/a.ps1'), '$x = 1')
    [IO.File]::WriteAllText((Join-Path $Box.Repo 'docs/project-control/status.md'), 'initial fixture status')
    [void](Invoke-CmFixtureGit $Box @('add','--','src/a.ps1','docs/project-control/status.md'))
    [void](Invoke-CmFixtureGit $Box @('commit','--quiet','-m','fixture baseline'))
}

function Get-CmFixtureSnapshot {
    param([string]$Root)
    @(Get-ChildItem -LiteralPath $Root -Force -Recurse | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length)
        if ($_.PSIsContainer) { 'directory:' + $relative }
        else { 'file:' + $relative + ':' + $_.Length + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }) -join "`n"
}

function New-CmPhysicalWriteFixture {
    param([hashtable]$Box)
    $f = WriteFixture
    $head = Invoke-CmFixtureGit $Box @('rev-parse','HEAD')
    $common = Invoke-CmFixtureGit $Box @('rev-parse','--git-common-dir')
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Box.Repo $common }
    $ri = Get-PfcRepositoryIdentityV1 (Resolve-Path -LiteralPath $common).ProviderPath
    $wi = Get-PfcWorktreeIdentityV1 (Resolve-Path -LiteralPath $Box.Repo).ProviderPath
    foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho)) { $o.repository_identity=$ri.repository_identity; $o.worktree_identity=$wi.worktree_identity; $o.authorized_base_checkpoint_sha=$head }
    foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.Checkpoint)) { $o.current_milestone_base_sha=$head; $o.expected_builder_start_sha=$head }
    $f.Authorization.repository.repository_identity=$ri.repository_identity; $f.Authorization.repository.authorized_base_checkpoint_sha=$head
    $f.WavePlan.milestones[0].worktree_identity=$wi.worktree_identity; $f.WavePlan.base_checkpoint_sha=$head
    $f.Observed.repository_identity=$ri.repository_identity; $f.Observed.worktree_identity=$wi.worktree_identity; $f.Observed.registered_worktrees[0].worktree_identity=$wi.worktree_identity
    $f.Observed.actual_worktree_head=$head; $f.Observed.governance_head_sha=$head; $f.BuilderEcho.actual_worktree_head=$head
    $f.Observed.exact_branch=Invoke-CmFixtureGit $Box @('rev-parse','--abbrev-ref','HEAD')
    foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.WavePlan.milestones[0],$f.Observed.registered_worktrees[0])) {$o.exact_branch=$f.Observed.exact_branch}
    $f.Observed.ancestry=@(@{ancestor_sha=$head;descendant_sha=$head;proven=$true})
    return $f
}

function Get-CmCandidateSha([int]$Number) { return (16 + $Number).ToString('x40') }
function Get-CmCheckpointSha([int]$Number) { if ($Number -eq 0) { return $a }; return (32 + $Number).ToString('x40') }

function New-CmSequenceWriteFixture {
    param([int]$Number, [int[]]$WaveNumbers)
    $f=WriteFixture; $base=Get-CmCheckpointSha ($Number-1); $waveId='WAVE-'+$WaveNumbers[0]; $id='M-'+$Number
    foreach ($o in @($f.Authorization,$f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho)) { $o.scope.to='M-7' }
    foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.Checkpoint)) {
        $o.milestone_id=$id; $o.wave_id=$waveId; $o.current_milestone_base_sha=$base; $o.expected_builder_start_sha=$base
        $o.previous_accepted_checkpoint_sha=if ($Number -eq 1) {'FIRST_MILESTONE'} else {$base}
    }
    foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho)) { $o.work_order_id='ORDER-'+$Number; $o.contract_id='CONTRACT-'+$Number; $o.exact_branch='codex/pfc/AUTH-1/m-'+$Number }
    $entry=$f.WavePlan.milestones[0]
    $f.WavePlan.milestones=@(foreach ($n in $WaveNumbers) { $item=Clone-CmFixture $entry; $item.milestone_id='M-'+$n; $item.contract_id='CONTRACT-'+$n; $item.exact_branch='codex/pfc/AUTH-1/m-'+$n; $item.dependencies=@(if ($n -gt 1) {'M-'+($n-1)}); $item })
    $f.WavePlan.wave_id=$waveId; $f.WavePlan.base_checkpoint_sha=Get-CmCheckpointSha ($WaveNumbers[0]-1)
    $f.CanonicalSources.wave_sources[0].wave_id=$waveId
    $f.Observed.roadmap_ids=@(1..7 | ForEach-Object {'M-'+$_}); $f.Observed.active_plan_milestone_id=$id
    $f.Observed.accepted_milestone_ids=@(if ($Number -gt 1) {1..($Number-1) | ForEach-Object {'M-'+$_}})
    $f.Observed.registered_worktrees[0].milestone_id=$id; $f.Observed.registered_worktrees[0].exact_branch=$f.WorkOrder.exact_branch; $f.Observed.exact_branch=$f.WorkOrder.exact_branch
    $f.Observed.actual_worktree_head=$base; $f.Observed.governance_head_sha=$base; $f.BuilderEcho.actual_worktree_head=$base
    $f.Observed.ancestry=@(@{ancestor_sha=$a;descendant_sha=$base;proven=$true})
    if ($Number -gt 1) { $f.Observed | Add-Member NoteProperty previous_acceptance @{result='ACCEPTED';accepted_checkpoint_sha=$base;milestone_id=('M-'+($Number-1))} }
    $f.Observed | Add-Member NoteProperty accepted_checkpoints @(if($Number -gt 1){foreach($n in 1..($Number-1)){@{result='ACCEPTED';milestone_id=('M-'+$n);accepted_checkpoint_sha=(Get-CmCheckpointSha $n);observed=$true}}})
    $f.Observed | Add-Member NoteProperty latest_acceptance @{result='ACCEPTED';milestone_id=('M-'+($Number-1));accepted_checkpoint_sha=$base;wave_id='WAVE-PREVIOUS';observed=$true}
    return $f
}

function New-CmReviewFromWrite {
    param([hashtable]$Write, [string]$CandidateSha)
    $f=ReviewFixture
    foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.VerifyOrder,$f.BuilderReport,$f.Candidate)) {
        $projection=Clone-CmFixture $Write.WorkOrder
        foreach ($property in $projection.PSObject.Properties) { $o.($property.Name)=$property.Value }
    }
    $f.Authorization=$Write.Authorization; $f.WavePlan=$Write.WavePlan
    foreach ($o in @($f.VerifyOrder,$f.BuilderReport,$f.Candidate)) {
        $o.base_sha=$Write.WorkOrder.current_milestone_base_sha; $o.candidate_sha=$CandidateSha; $o.builder_evidence_sha=$CandidateSha
        $o.wave_impact.candidate_sha=$CandidateSha; $o.wave_impact.wave_id=$Write.WorkOrder.wave_id; $o.wave_impact.milestone_id=$Write.WorkOrder.milestone_id
        $selected=@($Write.WavePlan.milestones | Where-Object {$_.milestone_id -ceq $Write.WorkOrder.milestone_id})[0]
        $o.wave_impact.dependencies=@($selected.dependencies)
        $o.wave_impact_checks[0].candidate_sha=$CandidateSha; $o.wave_impact_checks[0].wave_id=$Write.WorkOrder.wave_id; $o.wave_impact_checks[0].milestone_id=$Write.WorkOrder.milestone_id; $o.wave_impact_checks[0].dependencies=@($selected.dependencies)
    }
    $f.Observed.repository_identity=$Write.WorkOrder.repository_identity; $f.Observed.candidate_sha=$CandidateSha; $f.Observed.actual_head_sha=$CandidateSha
    $f.Observed.ancestry=@(@{ancestor_sha=$Write.WorkOrder.current_milestone_base_sha;descendant_sha=$CandidateSha;proven=$true})
    $f.Observed.diff.from_sha=$Write.WorkOrder.current_milestone_base_sha; $f.Observed.diff.to_sha=$CandidateSha
    $f.Observed.builder_evidence[0].candidate_sha=$CandidateSha; $f.Observed.builder_evidence[0].work_order_id=$Write.WorkOrder.work_order_id
    return $f
}

function New-CmSequenceTransitionFixture {
    param([int]$Number=1, [int[]]$WaveNumbers=@(1))
    $f=TransitionFixture; $x=$f.Context; $w=New-CmSequenceWriteFixture $Number $WaveNumbers
    $sha=Get-CmCandidateSha $Number; $checkpoint=Get-CmCheckpointSha $Number
    $x.milestone_id='M-'+$Number; $x.current_work_order_id=$w.WorkOrder.work_order_id; $x.current_builder_start_sha=$w.WorkOrder.expected_builder_start_sha
    $x.current_pre_write_gate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w
    True $x.current_pre_write_gate.can_issue_builder_lease
    $review=New-CmReviewFromWrite $w $sha; $x.pre_review_gate=Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $review
    True $x.pre_review_gate.can_start_review
    $x.candidate_sha=$sha; $x.evidence_sha=$sha; $x.acceptance_sha=$sha; $x.accepted_checkpoint_sha=$checkpoint; $x.actual_head_sha=$checkpoint; $x.governance_head_sha=$checkpoint
    $x.independent_review.candidate_sha=$sha; $x.validation_plan=@(Plan @('T1','T2') $sha PASS)
    $x.validation_observations=@(foreach ($tier in @('T1','T2')) {@{evidence_id='E-'+$tier;candidate_sha=$sha;reference='evidence/reference';observed=$true;fresh=$true}})
    $x.validation_observations+=@{evidence_id='E-T3';candidate_sha=$checkpoint;reference='evidence/reference';observed=$true;fresh=$true}
    $x.wave_id=$w.WorkOrder.wave_id; $x.frozen_wave.wave_id=$x.wave_id; $x.frozen_wave.milestone_ids=@($WaveNumbers | ForEach-Object {'M-'+$_})
    $x.accepted_milestone_ids=@(1..$Number | ForEach-Object {'M-'+$_})
    $x.ancestry=@(); $x.diffs=@(); $x.wave_milestones=@()
    foreach ($n in @($WaveNumbers | Where-Object {$_ -le $Number})) {
        $candidate=Get-CmCandidateSha $n; $accepted=Get-CmCheckpointSha $n
        $x.ancestry+=@{ancestor_sha=$candidate;descendant_sha=$accepted;proven=$true}
        $x.diffs+=@{from_sha=$candidate;to_sha=$accepted;observed=$true;changed_paths=@($controls[1]);commits=@(@{commit_sha=$accepted;parent_shas=@($candidate);changed_paths=@($controls[1])})}
        $x.wave_milestones+=@{milestone_id='M-'+$n;candidate_sha=$candidate;evidence_sha=$candidate;acceptance_sha=$candidate;accepted_checkpoint_sha=$accepted;result='PASS'}
    }
    $x.wave_t3=@(Plan @('T3') $checkpoint PASS)[0]; $x.wave_verifier.candidate_sha=$checkpoint
    $x.wave_persistence.wave_id=$x.wave_id; $x.wave_persistence.final_checkpoint_sha=$checkpoint; $x.wave_persistence.control_commit_sha=$checkpoint
    $x.next_base_sha=$checkpoint
    if ($Number -lt 7) {
        $nextWave=if ($Number -eq $WaveNumbers[-1]) {@(6,7)} else {$WaveNumbers}
        $next=New-CmSequenceWriteFixture ($Number+1) $nextWave
        $x.next_milestone_id='M-'+($Number+1); $x.next_work_order_id=$next.WorkOrder.work_order_id
        $x.pre_write_gate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $next
        $x.runtime.control_run_id=$next.WorkOrder.control_run_id; $x.runtime.lease_epoch=$next.WorkOrder.lease_epoch
    }
    $f.Event=if ($Number -eq $WaveNumbers[-1]) {'WAVE_END'} else {'NEXT_MILESTONE'}
    return $f
}

function Set-CmScenarioRisk {
    param([hashtable]$Fixture, [string]$Risk)
    $plan=Resolve-PfcRiskValidationPlan $Risk @() ROLLBACK $limits
    True $plan.allowed
    $Fixture.Context.risk_level=$Risk
    $Fixture.Context.validation_plan=@(Plan $plan.required_milestone_tiers $Fixture.Context.candidate_sha PASS)
    foreach ($record in $Fixture.Context.validation_plan) { $record.evidence[0].evidence_id='E-'+$record.tier.Replace('_','-') }
    $Fixture.Context.validation_observations=@(foreach ($tier in $plan.required_milestone_tiers) {@{evidence_id='E-'+$tier.Replace('_','-');candidate_sha=$Fixture.Context.candidate_sha;reference='evidence/reference';observed=$true;fresh=$true}})
    # Wave T3 has a distinct observation ID, bound to the accepted checkpoint.
    $Fixture.Context.wave_t3.evidence[0].evidence_id='WAVE-T3'
    $Fixture.Context.validation_observations+=@{evidence_id='WAVE-T3';candidate_sha=$Fixture.Context.accepted_checkpoint_sha;reference='evidence/reference';observed=$true;fresh=$true}
}

function New-CmIssueFixture {
    @{Classification='TEST_INFRASTRUCTURE_DEFECT';Evidence=@('observed infrastructure failure');AffectedScope=@('M-1');Phase='MILESTONE';Fallback=@{fallback_id='FALLBACK-1';registered=$true;approved=$true;applicable=$true;review_trigger='ENV-1';observed_trigger='ENV-1';trigger_fired=$false};IndependentProductEvidence=@{observed=$true;independent=$true;fresh=$true;result='PASS';candidate_sha=$c;expected_candidate_sha=$c;reference='independent/evidence'};Budget=@{allowed=$true;requires_new_candidate=$false};SpecialistRequirement='NONE'}
}

function Get-PfcContinuousModeScenarios {
    @(
        @{ScenarioId='SC-32';Positive=@(@{Name='explicit-approval-gate-activation';Test={
            $f=RealRuntimeTransitionFixture; $f.Event='APPROVE'; $f.AuthorizationStatus='NONE'; $f.ExecutionState='DISABLED'; $f.Context.invocation_mode='START'
            $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f; True $r.allowed; Equal 'ACTIVE' $r.authorization_status; Equal 'ARMED' $r.execution_state; True (-not $r.writes_allowed)
            $f.AuthorizationStatus=$r.authorization_status; $f.ExecutionState=$r.execution_state; $f.Event='ACTIVATE'
            $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f; True $r.writes_allowed; Equal 'ACTIVE' $r.execution_state; Equal 'START' $f.Context.invocation_mode
        }});Negative=@(@{Name='implicit-unapproved-or-failed-gate';Test={
            foreach ($field in @('explicit_continuous','approval.observed','invocation_mode','pre_write_gate.can_issue_builder_lease')) {
                $f=RealRuntimeTransitionFixture; $f.Event='ACTIVATE'; $f.ExecutionState='ARMED'
                if ($field -eq 'approval.observed') {$f.Event='APPROVE'}
                Change $f.Context $field $(if ($field -eq 'invocation_mode') {'CONTINUOUS_MODE'} else {$false})
                $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f; True (-not $r.writes_allowed); if ($field -ne 'explicit_continuous') {True (-not $r.allowed)}
            }
        }})},
        @{ScenarioId='SC-33';Positive=@(@{Name='ordinary-start-resume-no-controls';Test={
            $box=New-CmScenarioSandbox
            try { $before=Get-CmFixtureSnapshot $box.Root; foreach ($mode in @('START','RESUME')) {$f=TransitionFixture; $f.Context.explicit_continuous=$false; $f.Context.invocation_mode=$mode; $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f; Equal 'DISABLED' $r.execution_state; Equal 'PAUSE_AFTER_MILESTONE' $r.next_action; True (-not $r.writes_allowed)}; Equal $before (Get-CmFixtureSnapshot $box.Root) }
            finally {Remove-CmScenarioSandbox $box}
        }});Negative=@(@{Name='stale-template-and-keep-going-do-not-enable';Test={
            $box=New-CmScenarioSandbox
            try { [IO.File]::WriteAllText((Join-Path $box.State 'stale-authorization.txt'),'keep going; old ACTIVE'); $before=Get-CmFixtureSnapshot $box.Root; $f=TransitionFixture; $f.Context.explicit_continuous=$false; $f.Event='RESUME'; $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f; Equal 'DISABLED' $r.execution_state; True (-not $r.writes_allowed); Equal $before (Get-CmFixtureSnapshot $box.Root) }
            finally {Remove-CmScenarioSandbox $box}
        }})},
        @{ScenarioId='SC-34';Positive=@(@{Name='stable-authorization-new-lease-and-bound-start';Test={
            foreach ($candidate in @($false,$true)) {
                $w=WriteFixture; $approval=$w.Authorization|ConvertTo-Json -Depth 40 -Compress
                foreach ($o in @($w.WorkOrder,$w.MilestoneContract,$w.BuilderEcho,$w.Checkpoint)) {$o.control_run_id='RUN-2';$o.lease_epoch=2;$o.expected_builder_start_sha=$d}
                $origin=if ($candidate) {$c} else {$a}
                $w.Observed.actual_worktree_head=$d;$w.Observed.governance_head_sha=$d;$w.BuilderEcho.actual_worktree_head=$d
                $w.Observed.ancestry+=@{ancestor_sha=$origin;descendant_sha=$d;proven=$true};$w.Observed.diffs=@(@{from_sha=$origin;to_sha=$d;observed=$true;changed_paths=@($controls[0]);commits=@(@{commit_sha=$d;parent_shas=@($origin);changed_paths=@($controls[0])})})
                if ($candidate) {$w.Observed.candidate_sha=$c;$w.Checkpoint.repair_budget.candidate_revisions=2;$w.Observed.ancestry+=@{ancestor_sha=$a;descendant_sha=$c;proven=$true}}
                $gate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w;True $gate.can_issue_builder_lease
                $f=RealRuntimeTransitionFixture;$f.Event='RESUME';$f.AuthorizationStatus='PAUSED';$f.ExecutionState='BLOCKED';$f.Context.pre_write_gate=$gate;$f.Context.actual_head_sha=$d;$f.Context.governance_head_sha=$d
                $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True $r.writes_allowed;Equal $approval ($w.Authorization|ConvertTo-Json -Depth 40 -Compress)
                $budget=RepairFixture;$budget.RequestedAction='RESUME';$budget.RepairBudget.builder_code_repair_attempts=2;$budget.PreviousBudget.builder_code_repair_attempts=2;Equal 0 (Invoke-CmScenarioOracle Test-PfcRepairBudget $budget).builder_attempts_remaining
            }
        }});Negative=@(@{Name='old-user-runtime-authority-and-counter-reset';Test={
            foreach ($field in @('user_resume.observed','user_resume.approved_by','runtime.control_run_id','pre_write_gate.lease_epoch')) {
                $f=RealRuntimeTransitionFixture;$f.Event='RESUME';$f.AuthorizationStatus='PAUSED';$f.ExecutionState='BLOCKED'
                $value=switch ($field) {'user_resume.observed' {$false} 'user_resume.approved_by' {'OTHER'} 'runtime.control_run_id' {'RUN-1'} default {1}}
                Change $f.Context $field $value;True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).writes_allowed)
            }
            $f=RealRuntimeTransitionFixture;$f.Event='RESUME';$f.AuthorizationStatus='INVALIDATED';True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).writes_allowed)
            $w=WriteFixture;$w.Authorization.scope.to='M-7';True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w).can_issue_builder_lease)
            $bgt=RepairFixture;$bgt.RequestedAction='RESUME';$bgt.PreviousBudget.builder_code_repair_attempts=2;True (-not (Invoke-CmScenarioOracle Test-PfcRepairBudget $bgt).allowed)
        }})},
        @{ScenarioId='SC-35';Positive=@(@{Name='canonical-source-reused';Test={
            $f=WriteFixture;$r=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f;Equal 'PRE_WRITE_IDENTITY_GATE_PASS' $r.result;Equal 'REUSE_AND_REGISTER' $r.canonical_source_action;True $r.can_issue_builder_lease;Equal 1 $f.CanonicalSources.authorization_sources.Count;Equal 1 $f.CanonicalSources.wave_sources.Count
        }});Negative=@(@{Name='task-mismatch-and-two-independent-duplicates';Test={
            foreach ($field in @('WorkOrder.milestone_id','BuilderEcho.work_order_id','Observed.active_plan_milestone_id')) {$f=WriteFixture;Change $f $field 'OTHER';$r=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f;Equal 'STOP_BEFORE_WRITE' $r.result;True (-not $r.can_issue_builder_lease)}
            foreach ($kind in @('authorization_sources','wave_sources')) {$f=WriteFixture;$f.CanonicalSources.$kind=@($f.CanonicalSources.$kind[0],$f.CanonicalSources.$kind[0]);$r=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f;Equal 'CONTROL_PLANE_DEFECT' $r.result;True (-not $r.can_issue_builder_lease)}
        }})},
        @{ScenarioId='SC-36';Positive=@(@{Name='physical-git-identity-and-accepted-ancestry';Test={param($log)
            $box=New-CmScenarioSandbox
            try {
                Initialize-CmFixtureGit $box;$f=New-CmPhysicalWriteFixture $box;True (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f).can_issue_builder_lease
                $first=$f.WorkOrder.current_milestone_base_sha
                [IO.File]::AppendAllText((Join-Path $box.Repo $controls[0]),' accepted')
                [void](Invoke-CmFixtureGit $box @('add','--',$controls[0]));[void](Invoke-CmFixtureGit $box @('commit','--quiet','-m','accepted checkpoint'))
                $head=Invoke-CmFixtureGit $box @('rev-parse','HEAD');[void](Invoke-CmFixtureGit $box @('merge-base','--is-ancestor',$first,$head))
                foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.Checkpoint)) {$o.milestone_id='M-2';$o.current_milestone_base_sha=$head;$o.expected_builder_start_sha=$head;$o.previous_accepted_checkpoint_sha=$head}
                $f.WavePlan.milestones[0].milestone_id='M-2';$f.WavePlan.base_checkpoint_sha=$head;$f.Observed.registered_worktrees[0].milestone_id='M-2';$f.Observed.active_plan_milestone_id='M-2';$f.Observed.accepted_milestone_ids=@('M-1')
                $f.Observed|Add-Member NoteProperty previous_acceptance @{result='ACCEPTED';milestone_id='M-1';accepted_checkpoint_sha=$head}
                $f.Observed|Add-Member NoteProperty accepted_checkpoints @(@{result='ACCEPTED';milestone_id='M-1';accepted_checkpoint_sha=$head;observed=$true})
                $f.Observed|Add-Member NoteProperty latest_acceptance @{result='ACCEPTED';milestone_id='M-1';accepted_checkpoint_sha=$head;wave_id='WAVE-0';observed=$true}
                $f.Observed.actual_worktree_head=$head;$f.Observed.governance_head_sha=$head;$f.BuilderEcho.actual_worktree_head=$head;$f.Observed.ancestry=@(@{ancestor_sha=$first;descendant_sha=$head;proven=$true})
                True (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f).can_issue_builder_lease
                Equal 'fc4628eaecd7833573e6a1bcde6f0580c80e154b6cb5649f0c46fb89a2204c15' (Get-PfcRepoPathSetIdentityV1 @('src/a.ps1')).paths_hash
                $log.Add('fixture-repo: real Git ancestry '+$first+' -> '+$head)
            } finally {Remove-CmScenarioSandbox $box}
        }});Negative=@(@{Name='each-identity-drift-and-unbound-proof';Test={
            $box=New-CmScenarioSandbox
            try {
                Initialize-CmFixtureGit $box
                foreach ($field in @('Observed.repository_identity','Observed.worktree_identity','Observed.exact_branch','Authorization.repository.authorized_base_checkpoint_sha','WorkOrder.current_milestone_base_sha','Observed.actual_worktree_head','Observed.writable_paths','Observed.forbidden_paths')) {
                    $f=New-CmPhysicalWriteFixture $box;$value='MISMATCH';if ($field -like '*paths') {$value=@('other/path');True ($value -is [array])};Change $f $field $value
                    $r=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f;True (-not $r.can_issue_builder_lease)
                    if ($field -like '*paths') {True ($r.reasons -ccontains 'PATH_SET_MISMATCH');True ($r.reasons -cnotcontains 'MALFORMED_INPUT')}
                }
            } finally {Remove-CmScenarioSandbox $box}
            foreach ($kind in @('lookalike','nonancestor','stale-endpoint','implementation-descendant','traversal')) {
                $f=New-CmSequenceWriteFixture 6 @(6,7)
                switch ($kind) {
                    lookalike {$f.Observed.exact_branch='codex/pfc/AUTH-10/m-6'}
                    nonancestor {$f.Observed.ancestry[0].proven=$false}
                    stale-endpoint {$f.Observed.ancestry[0].descendant_sha=$c}
                    traversal {$f.Observed.writable_paths=@('../escape')}
                    implementation-descendant {
                        $origin=$f.WorkOrder.current_milestone_base_sha;foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.Checkpoint)) {$o.expected_builder_start_sha=$d};$f.Observed.actual_worktree_head=$d;$f.Observed.governance_head_sha=$d;$f.BuilderEcho.actual_worktree_head=$d
                        $f.Observed.ancestry+=@{ancestor_sha=$origin;descendant_sha=$d;proven=$true};$f.Observed.diffs=@(@{from_sha=$origin;to_sha=$d;observed=$true;changed_paths=@($controls[0],'src/a.ps1');commits=@(@{commit_sha=$d;parent_shas=@($origin);changed_paths=@($controls[0],'src/a.ps1')})})
                    }
                }
                True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f).can_issue_builder_lease)
            }
        }})},
        @{ScenarioId='SC-37';Positive=@(@{Name='seven-low-sequential-five-plus-two';Test={param($log)
            $risk=Resolve-PfcRiskValidationPlan LOW @() NONE $limits;Equal 5 $risk.max_wave_size
            $firstWave=@(1,2,3,4,5);$secondWave=@(6,7)
            foreach ($n in $firstWave) {$f=New-CmSequenceTransitionFixture $n $firstWave;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True $r.allowed;True (-not $r.requires_user_decision);Equal $(if ($n -eq 5) {'SELECT_NEXT_WAVE'} else {'START_NEXT_MILESTONE'}) $r.next_action}
            Equal 'ARMED' $r.execution_state;True (-not $r.writes_allowed);$immutable=$f.Context.wave_milestones|ConvertTo-Json -Depth 20 -Compress
            $next=New-CmSequenceWriteFixture 6 $secondWave;$gate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $next;True $gate.can_issue_builder_lease;Equal (Get-CmCheckpointSha 5) $next.WavePlan.base_checkpoint_sha
            $f.Event='ACTIVATE';$f.ExecutionState=$r.execution_state;$f.Context.pre_write_gate=$gate;$f.Context.next_milestone_id='M-6';$f.Context.next_work_order_id='ORDER-6'
            $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True $r.writes_allowed;True (-not $r.requires_user_decision);Equal $immutable ($f.Context.wave_milestones|ConvertTo-Json -Depth 20 -Compress)
            foreach ($n in $secondWave) {$f=New-CmSequenceTransitionFixture $n $secondWave;if ($n -eq 7) {$f.Context.scope_exhausted=$true};$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True $r.allowed;True (-not $r.requires_user_decision)}
            Equal 'COMPLETED' $r.execution_state;$log.Add('W1=M-1..M-5; W2=M-6,M-7; seven bound gates; no per-task/Wave decision')
        }});Negative=@(@{Name='capacity-acceptance-t3-persistence-scope-dependency-gate';Test={
            $w=New-CmSequenceWriteFixture 1 @(1,2,3,4,5,6);True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w).can_issue_builder_lease)
            foreach ($kind in @('missing-last','stale-t3','failed-t3','missing-persistence','missing-recheck')) {
                $f=New-CmSequenceTransitionFixture 5 @(1,2,3,4,5)
                switch ($kind) {missing-last {$f.Context.wave_milestones=$f.Context.wave_milestones[0..3]} stale-t3 {$f.Context.wave_t3.evidence[0].candidate_sha=$a} failed-t3 {$f.Context.wave_t3.result='NOT_RUN'} missing-persistence {$f.Context.wave_persistence.observed=$false} missing-recheck {$f.Context.authorization_rechecked=$false}}
                True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).allowed)
            }
            foreach ($kind in @('scope','dependency','gate')) {$w=New-CmSequenceWriteFixture 6 @(6,7);switch ($kind) {scope {$w.Observed.roadmap_ids=@('M-1','M-2')} dependency {$w.WavePlan.milestones[0].dependencies=@('UNKNOWN')} gate {$w.BuilderEcho.work_order_id='OLD'}};True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w).can_issue_builder_lease)}
        }})},
        @{ScenarioId='SC-38';Positive=@(@{Name='low-medium-low-required-evidence';Test={
            foreach ($risk in @('LOW','MEDIUM','LOW')) {$plan=Resolve-PfcRiskValidationPlan $risk @() ROLLBACK $limits;Equal $(if ($risk -eq 'MEDIUM') {3} else {5}) $plan.max_wave_size;Equal 'T3' ($plan.required_wave_tiers -join ',');$f=New-CmSequenceTransitionFixture 1 @(1);Set-CmScenarioRisk $f $risk;True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).allowed}
            Equal 'MEDIUM' (Resolve-PfcRiskValidationPlan LOW @('UNCERTAINTY') ROLLBACK $limits).risk_level
            Equal 'HIGH' (Resolve-PfcRiskValidationPlan LOW @('PERMISSIONS') NONE $limits).risk_level
        }});Negative=@(@{Name='risk-floor-missing-rollback-waiver-stale-low';Test={
            $w=WriteFixture;$w.Observed.risk_factors=@('FILE_WRITE');$w.Observed.medium_validation='ROLLBACK';True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w).can_issue_builder_lease)
            foreach ($kind in @('missing','optional','old-low')) {$f=New-CmSequenceTransitionFixture 1 @(1);Set-CmScenarioRisk $f MEDIUM;switch ($kind) {missing {$f.Context.validation_plan=$f.Context.validation_plan[0..1]} optional {$f.Context.validation_plan[2].required=$false} old-low {$f.Context.validation_plan[2].evidence[0].candidate_sha=$a}};True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).allowed)}
        }})},
        @{ScenarioId='SC-39';Positive=@(@{Name='high-single-wave-user-gate';Test={
            $p=Resolve-PfcRiskValidationPlan HIGH @('PERMISSIONS') NONE $limits;Equal 1 $p.max_wave_size;Equal 'T1,T2,T3,T4,FAULT_INJECTION,USER_GATE' ($p.required_milestone_tiers -join ',')
            $f=New-CmSequenceTransitionFixture 1 @(1);Set-CmScenarioRisk $f HIGH;$f.Context.stop_gate_reached=$true;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True $r.allowed;Equal 'STOP_GATE_REACHED' $r.execution_state;True $r.requires_user_decision;True (-not $r.writes_allowed)
        }});Negative=@(
            @{Name='missing-T4';Test={param($log)
                $f=New-CmSequenceTransitionFixture 1 @(1);Set-CmScenarioRisk $f HIGH;$f.Context.stop_gate_reached=$true
                True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).allowed
                @($f.Context.validation_plan|Where-Object tier -ceq T4)[0].result='NOT_RUN'
                $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);True ($r.reasons -ccontains 'REQUIRED_VALIDATION_NOT_PASS')
                $log.Add('T4=NOT_RUN; stop gate=true; reason='+($r.reasons -join ','))
            }},
            @{Name='missing-FAULT_INJECTION';Test={param($log)
                $f=New-CmSequenceTransitionFixture 1 @(1);Set-CmScenarioRisk $f HIGH;$f.Context.stop_gate_reached=$true
                True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).allowed
                @($f.Context.validation_plan|Where-Object tier -ceq FAULT_INJECTION)[0].result='NOT_RUN'
                $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);True ($r.reasons -ccontains 'REQUIRED_VALIDATION_NOT_PASS')
                $log.Add('FAULT_INJECTION=NOT_RUN; stop gate=true; reason='+($r.reasons -join ','))
            }},
            @{Name='missing-USER_GATE';Test={param($log)
                $f=New-CmSequenceTransitionFixture 1 @(1);Set-CmScenarioRisk $f HIGH;$f.Context.stop_gate_reached=$true
                True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).allowed
                @($f.Context.validation_plan|Where-Object tier -ceq USER_GATE)[0].result='NOT_RUN'
                $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);True ($r.reasons -ccontains 'REQUIRED_VALIDATION_NOT_PASS')
                $log.Add('USER_GATE=NOT_RUN; stop gate=true; reason='+($r.reasons -join ','))
            }},
            @{Name='two-complete-items-exceed-capacity';Test={param($log)
                $f=New-CmSequenceTransitionFixture 2 @(1,2);Set-CmScenarioRisk $f HIGH;$f.Context.stop_gate_reached=$true
                Equal 2 $f.Context.wave_milestones.Count
                $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);True ($r.reasons -ccontains 'WAVE_MISMATCH')
                $log.Add('complete two-item HIGH Wave; stop gate=true; reason='+($r.reasons -join ','))
            }},
            @{Name='no-stop-gate';Test={param($log)
                $f=New-CmSequenceTransitionFixture 1 @(1);Set-CmScenarioRisk $f HIGH;$f.Context.stop_gate_reached=$true
                True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).allowed;$f.Context.stop_gate_reached=$false
                $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);True ($r.reasons -ccontains 'HIGH_REQUIRES_USER_GATE')
                $log.Add('complete HIGH validation; stop gate=false; reason='+($r.reasons -join ','))
            }}
        )},
        @{ScenarioId='SC-40';Positive=@(@{Name='infra-remains-failed-with-independent-fallback';Test={
            $f=New-CmIssueFixture;$infrastructure=@{result='FAIL'};$r=Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f;Equal 'TEST_INFRASTRUCTURE_DEFECT' $r.classification;Equal 'CONTINUE' $r.next_action;Equal 'NONE' $r.blocking_scope;Equal 'REGISTER_LIMITATION_AND_TECHNICAL_DEBT' $r.residual_risk;Equal 'FAIL' $infrastructure.result
            $t=TransitionFixture;True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).allowed
        }});Negative=@(@{Name='no-product-evidence-no-waiver';Test={
            foreach ($field in @('IndependentProductEvidence.fresh','IndependentProductEvidence.independent','Fallback.approved')) {$f=New-CmIssueFixture;Change $f $field $false;Equal 'BLOCK_VERIFICATION' (Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f).next_action}
            $f=New-CmIssueFixture;$f.IndependentProductEvidence=$null;Equal 'BLOCK_VERIFICATION' (Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f).next_action
            $t=TransitionFixture;$t.Context.validation_plan[0].result='FAIL';True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).allowed)
        }})},
        @{ScenarioId='SC-41';Positive=@(@{Name='product-failure-repairs-without-acceptance';Test={
            $budget=RepairFixture;$budget.ChangedTrackedPaths=@('src/a.ps1');$f=New-CmIssueFixture;$f.Classification='PRODUCT_DEFECT';$f.Budget=Invoke-CmScenarioOracle Test-PfcRepairBudget $budget;$r=Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f;Equal 'REPAIR' $r.next_action;Equal 'MILESTONE' $r.blocking_scope;True $r.requires_new_candidate
            $t=TransitionFixture;$t.Context.validation_plan[0].result='FAIL';True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).allowed)
        }});Negative=@(@{Name='relabel-unrelated-pass-and-exhausted-budget';Test={
            foreach ($classification in @('TEST_INFRASTRUCTURE_DEFECT','KNOWN_ENVIRONMENT_LIMITATION')) {$f=New-CmIssueFixture;$f.Classification=$classification;$f.IndependentProductEvidence.candidate_sha=$a;$t=TransitionFixture;$t.Context.validation_plan[0].result='FAIL';$t.Context.independent_review.candidate_sha=$a;[void](Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f);True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).allowed)}
            $budget=RepairFixture;$budget.RepairBudget.builder_code_repair_attempts=2;$f=New-CmIssueFixture;$f.Classification='PRODUCT_DEFECT';$f.Budget=Invoke-CmScenarioOracle Test-PfcRepairBudget $budget;True ((Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f).next_action -cne 'REPAIR')
        }})},
        @{ScenarioId='SC-42';Positive=@(@{Name='review-start-before-verifier-output';Test={
            $f=ReviewFixture;$r=Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $f;Equal 'PRE_REVIEW_IDENTITY_GATE_PASS' $r.result;True $r.can_start_review
        }});Negative=@(@{Name='control-wave-contract-target-mismatch';Test={
            foreach ($field in @('Authorization.authorization_id','WavePlan.wave_id','Observed.acceptance_record_target','MilestoneContract.contract_id')) {$f=ReviewFixture;Change $f $field 'OTHER';$r=Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $f;Equal 'CONTROL_PLANE_DEFECT' $r.result;True (-not $r.can_start_review)}
        }})},
        @{ScenarioId='SC-43';Positive=@(@{Name='exact-candidate-and-control-descendant';Test={
            $f=ReviewFixture;$f.Observed.actual_head_sha=$d;$f.Observed.ancestry+=@{ancestor_sha=$c;descendant_sha=$d;proven=$true};$f.Observed.diffs=@(@{from_sha=$c;to_sha=$d;observed=$true;changed_paths=@($controls[0]);commits=@(@{commit_sha=$d;parent_shas=@($c);changed_paths=@($controls[0])})});$f.Observed.canonical_control_paths=$controls
            $r=Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $f;True $r.can_start_review;Equal $c $r.candidate_sha;True (Invoke-CmScenarioOracle Test-PfcContinuousTransition (TransitionFixture)).allowed
        }});Negative=@(@{Name='stale-reports-and-verification-mutations';Test={
            foreach ($field in @('Observed.builder_evidence.0.candidate_sha')) {$f=ReviewFixture;$f.Observed.builder_evidence[0].candidate_sha=$a;$r=Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $f;True (-not $r.can_start_review);True ($r.reasons -ccontains 'STALE_REPORT_REJECTED')}
            foreach ($kind in @('old-order','diff','tracked','staged','rebind-head')) {$f=ReviewFixture;switch ($kind) {old-order {$f.BuilderReport.work_order_id='OLD'} diff {$f.Observed.diff.to_sha=$a} tracked {$f.Observed.tracked_mutations=@('src/a.ps1')} staged {$f.Observed.staged_mutations=@('src/a.ps1')} rebind-head {$f.Observed.builder_evidence[0].candidate_sha=$d}};$r=Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $f;True (-not $r.can_start_review);True (@('STALE_REPORT_REJECTED','VERSION_INTEGRITY_FAIL') -ccontains $r.reasons[0])}
        }})},
        @{ScenarioId='SC-44';Positive=@(@{Name='physical-migration-head-new-candidate';Test={param($log)
            $box=New-CmScenarioSandbox
            try {Initialize-CmFixtureGit $box;$w=New-CmPhysicalWriteFixture $box;$base=$w.WorkOrder.current_milestone_base_sha;[IO.File]::AppendAllText((Join-Path $box.Repo 'src/a.ps1'),"`n# migration head v2");[void](Invoke-CmFixtureGit $box @('add','--','src/a.ps1'));[void](Invoke-CmFixtureGit $box @('commit','--quiet','-m','fixture migration repair'));$head=Invoke-CmFixtureGit $box @('rev-parse','HEAD');$paths=@((Invoke-CmFixtureGit $box @('diff','--name-only',$base,$head)) -split "`n");$bgt=RepairFixture;$bgt.ChangedTrackedPaths=$paths;$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $bgt;True $r.requires_new_candidate;Equal 2 $r.next_candidate_revision;$review=New-CmReviewFromWrite $w $head;True (Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $review).can_start_review;Equal $base $review.WorkOrder.current_milestone_base_sha;$log.Add('migration fixture Candidate '+$base+' -> '+$head)} finally {Remove-CmScenarioSandbox $box}
        }});Negative=@(@{Name='old-pass-mixed-control-and-r4-denied';Test={
            $f=ReviewFixture;$f.Observed.builder_evidence[0].candidate_sha=$a;True (-not (Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $f).can_start_review)
            $bgt=RepairFixture;$bgt.ChangedTrackedPaths=@($controls[0],'migration.sql');$bgt.RequestedAction='CONTROL_RECORD';$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $bgt;True $r.requires_new_candidate;True (-not $r.allowed)
            $bgt.RequestedAction='FREEZE_CANDIDATE';$bgt.RepairBudget.candidate_revisions=3;$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $bgt;True $r.hard_stop;Equal 'REPAIR_LOOP_STOPPED' $r.reason
        }})},
        @{ScenarioId='SC-45';Positive=@(@{Name='physical-format-ast-equivalent-still-new-candidate';Test={param($log)
            $box=New-CmScenarioSandbox
            try {Initialize-CmFixtureGit $box;$base=Invoke-CmFixtureGit $box @('rev-parse','HEAD');$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput('$x = 1',[ref]$tokens,[ref]$errors);$before=(@($tokens|Where-Object {$_.Kind -ne 'EndOfInput'}|ForEach-Object {$_.Kind.ToString()+':'+$_.Text}) -join '|');[IO.File]::WriteAllText((Join-Path $box.Repo 'src/a.ps1'),'$x    =    1');[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $box.Repo 'src/a.ps1'),[ref]$tokens,[ref]$errors);Equal 0 @($errors).Count;Equal $before (@($tokens|Where-Object {$_.Kind -ne 'EndOfInput'}|ForEach-Object {$_.Kind.ToString()+':'+$_.Text}) -join '|');[void](Invoke-CmFixtureGit $box @('add','--','src/a.ps1'));[void](Invoke-CmFixtureGit $box @('commit','--quiet','-m','fixture formatting'));$head=Invoke-CmFixtureGit $box @('rev-parse','HEAD');$bgt=RepairFixture;$bgt.ChangedTrackedPaths=@((Invoke-CmFixtureGit $box @('diff','--name-only',$base,$head)) -split "`n");$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $bgt;True $r.requires_new_candidate;Equal 2 $r.next_candidate_revision;$log.Add('format token sequence unchanged; tracked Candidate changed '+$head)} finally {Remove-CmScenarioSandbox $box}
        }});Negative=@(@{Name='markdown-not-control-and-old-evidence-denied';Test={
            $bgt=RepairFixture;$bgt.RequestedAction='CONTROL_RECORD';$bgt.ChangedTrackedPaths=@('docs/readme.md');True (-not (Invoke-CmScenarioOracle Test-PfcRepairBudget $bgt).allowed)
            $bgt.ChangedTrackedPaths=@($controls[0]);$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $bgt;True $r.allowed;True (-not $r.requires_new_candidate);Equal 1 $r.next_candidate_revision
            $f=ReviewFixture;$f.Observed.builder_evidence[0].candidate_sha=$a;True (-not (Invoke-CmScenarioOracle Test-PfcPreReviewIdentityGate $f).can_start_review)
        }})},
        @{ScenarioId='SC-46';Positive=@(@{Name='registered-trigger-bounded-fallback';Test={
            $f=New-CmIssueFixture;$f.Classification='KNOWN_ENVIRONMENT_LIMITATION';$r=Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f;Equal 'USE_APPROVED_FALLBACK' $r.next_action;Equal 'FALLBACK-1' $r.fallback_reference;True ($r.residual_risk -cne 'NONE');True (Invoke-CmScenarioOracle Test-PfcContinuousTransition (TransitionFixture)).allowed
        }});Negative=@(@{Name='trigger-environment-version-expiry-and-approval';Test={
            foreach ($kind in @('ENV-2','VERSION-2','EXPIRED')) {$f=New-CmIssueFixture;$f.Classification='KNOWN_ENVIRONMENT_LIMITATION';$f.Fallback.observed_trigger=$kind;Equal 'BLOCK_VERIFICATION' (Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f).next_action}
            foreach ($flag in @('registered','approved','applicable','trigger_fired')) {$f=New-CmIssueFixture;$f.Classification='KNOWN_ENVIRONMENT_LIMITATION';$f.Fallback.$flag=($flag -eq 'trigger_fired');Equal 'BLOCK_VERIFICATION' (Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f).next_action}
            $t=TransitionFixture;$t.Context.validation_observations[0].fresh=$false;True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).allowed)
        }})},
        @{ScenarioId='SC-47';Positive=@(@{Name='known-exact-dirty-inventory';Test={
            True (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate (DirtyFixture)).can_issue_builder_lease
        }});Negative=@(@{Name='extra-bytes-status-rename-session-git-operation';Test={
            foreach ($kind in @('extra','hash','size','status','rename','session','operation')) {$f=DirtyFixture;switch ($kind) {extra {$f.Observed.git_status+=@{path='unknown.txt';status='??';original_path='NONE'}} hash {$f.Observed.files[0].sha256='f'*64} size {$f.Observed.files[0].size_bytes=43} status {$f.Observed.git_status[0].status='M '} rename {$f.Observed.git_status[0].status='R ';$f.Observed.git_status[0].original_path='src/old.ps1'} session {$f.Observed.unknown_active_session=$true} operation {$f.Observed.git_operation_in_progress=$true}};$r=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f;True (-not $r.can_issue_builder_lease);True ($r.reasons -ccontains 'RECOVERY_REQUIRED')}
            $t=TransitionFixture;$t.Context.unknown_dirty=$true;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t;Equal 'RECOVERY_REQUIRED' $r.readiness;Equal 'INVALIDATED' $r.authorization_status;True (-not $r.writes_allowed)
        }})},
        @{ScenarioId='SC-48';Positive=@(@{Name='actual-recovery-byte-copies-and-manifest';Test={param($log)
            $box=New-CmScenarioSandbox
            try {
                Initialize-CmFixtureGit $box;$f=New-CmPhysicalWriteFixture $box;$source=Join-Path $box.Repo 'src/a.ps1';$copy=Join-Path $box.Recovery 'a.ps1';$bytes=[byte[]](0,13,10,65,255,66,10);[IO.File]::WriteAllBytes($source,$bytes);Copy-Item -LiteralPath $source -Destination $copy
                $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();$copyHash=(Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant();$size=(Get-Item -LiteralPath $source).Length
                Equal ([Convert]::ToBase64String($bytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($copy)));Equal $hash $copyHash;Equal $size (Get-Item -LiteralPath $copy).Length
                $status=Invoke-CmFixtureGit $box @('status','--porcelain','--','src/a.ps1');Equal ' M src/a.ps1' $status
                $f.Checkpoint.recovery_manifest.git_status=@(@{path='src/a.ps1';status=$status.Substring(0,2);original_path='NONE'});$f.Checkpoint.recovery_manifest.files=@(@{path='src/a.ps1';sha256=$hash;size_bytes=$size;recovery_copy='a.ps1';classification='ACTIVE'})
                $f.Observed.git_status=@(Clone-CmFixture $f.Checkpoint.recovery_manifest.git_status);$f.Observed.files=@(Clone-CmFixture $f.Checkpoint.recovery_manifest.files)
                $f.Observed|Add-Member NoteProperty recovery_package @{recovery_package_reference='RECOVERY-1';outside_repository=(-not $copy.StartsWith($box.Repo+'\',[StringComparison]::OrdinalIgnoreCase));verified=$true}
                $f.Observed|Add-Member NoteProperty recovery_copies @(@{path='src/a.ps1';sha256=$copyHash;size_bytes=(Get-Item -LiteralPath $copy).Length;recovery_copy='a.ps1';recovery_package_reference='RECOVERY-1';verified=$true})
                True (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f).can_issue_builder_lease
                $t=RealRuntimeTransitionFixture;$t.Event='RECOVERY_COMPLETE';$t.AuthorizationStatus='INVALIDATED';$t.ExecutionState='BLOCKED';$head=$f.Observed.actual_worktree_head;$t.Context.actual_head_sha=$head;$t.Context.governance_head_sha=$head;$t.Context.pre_write_gate=Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f
                $t.Context.recovery_checkpoint=$f.Checkpoint;$t.Context.recovery_observed=$f.Observed;$t.Context.recovery_writable_paths=@('src/a.ps1');$t.Context.recovery_forbidden_paths=@('secrets');$t.Context.recovery_steps=@(@('READ_ONLY_INVENTORY','EXTERNAL_RECOVERY_PACKAGE','HASH_SIZE_MANIFEST','CLASSIFICATION','REVERSIBLE_ISOLATION','GOVERNANCE_CHECKPOINT','PRE_WRITE_IDENTITY_GATE')|ForEach-Object {@{name=$_;checkpoint_sha=$head;recovery_package_reference='RECOVERY-1';observed=$true}})
                $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t;Equal 'READY_WITH_PRECONDITIONS' $r.readiness;Equal 'REQUEST_REAUTHORIZATION' $r.next_action;True (-not $r.writes_allowed)
                Equal $hash (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();$log.Add('fixture-recovery/a.ps1: actual copied bytes; sha256='+$hash+'; size='+$size)
                [IO.File]::WriteAllBytes($copy,[byte[]](0,13,10,65,255,67,10));$f.Observed.recovery_copies[0].sha256=(Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant();True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f).can_issue_builder_lease)
            } finally {Remove-CmScenarioSandbox $box}
        }});Negative=@(@{Name='missing-corrupt-omitted-unknown-and-inside-copy';Test={
            foreach ($kind in @('missing','size','omitted','unknown','inside','unverified')) {$f=DirtyFixture;switch ($kind) {missing {$f.Observed.recovery_copies=@()} size {$f.Observed.recovery_copies[0].size_bytes=41} omitted {$f.Checkpoint.recovery_manifest.files=@()} unknown {$f.Checkpoint.recovery_manifest.files[0].classification='UNKNOWN'} inside {$f.Observed.recovery_package.outside_repository=$false} unverified {$f.Observed.recovery_copies[0].verified=$false}};True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $f).can_issue_builder_lease)}
        }})},
        @{ScenarioId='SC-49';Positive=@(@{Name='unchanged-authorization-and-contract';Test={
            True (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate (WriteFixture)).can_issue_builder_lease;True (Invoke-CmScenarioOracle Test-PfcContinuousTransition (TransitionFixture)).allowed
        }});Negative=@(@{Name='each-stable-fact-invalidates-without-rewrite';Test={
            foreach ($change in @('CONTRACT_CHANGE','GOAL_CHANGE','SCOPE_CHANGE','DEPENDENCY_CHANGE','WRITABLE_PATH_CHANGE','FORBIDDEN_PATH_CHANGE','BASELINE_DRIFT','BRANCH_CHANGE')) {$f=TransitionFixture;$f.Context.invalidation_reasons=@($change);$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;Equal 'INVALIDATED' $r.authorization_status;Equal 'BLOCKED' $r.execution_state;True $r.requires_user_decision;True (-not $r.writes_allowed);$f.AuthorizationStatus=$r.authorization_status;$f.Event='RESUME';$f.Context.invalidation_reasons=@();True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).writes_allowed)}
            foreach ($field in @('MilestoneContract.contract_version','Authorization.goal.goal_version','Authorization.scope.to','Authorization.paths.writable_paths_hash','Authorization.paths.forbidden_paths_hash','Observed.exact_branch')) {$w=WriteFixture;Change $w $field 'CHANGED';True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w).can_issue_builder_lease)}
            $w=WriteFixture;$w.WavePlan.milestones[0].dependencies=@('UNKNOWN');True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w).can_issue_builder_lease)
        }})},
        @{ScenarioId='SC-50';Positive=@(@{Name='local-reversible-eligible';Test={
            True (Invoke-CmScenarioOracle Test-PfcContinuousTransition (TransitionFixture)).allowed
        }});Negative=@(@{Name='remote-irreversible-and-security-refused';Test={
            foreach ($action in @('PUSH','MERGE','REBASE','FORCE','RELEASE','DEPLOY','PRODUCTION_CHANGE','ACCOUNT_CHANGE','PAID_ACTION','DELETE_DATA')) {$f=TransitionFixture;$f.Event=$action;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);True (-not $r.writes_allowed)}
            $f=TransitionFixture;$f.Context.irreversible_pending=$true;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);True $r.requires_user_decision
            $issue=New-CmIssueFixture;$issue.Classification='SECURITY_OR_DATA_RISK';$r=Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $issue;Equal 'GLOBAL' $r.blocking_scope;Equal 'STOP' $r.next_action
        }})},
        @{ScenarioId='SC-51';Positive=@(@{Name='r3-pass-accepts-no-extra-revision';Test={
            $f=RepairFixture;$f.RepairBudget.candidate_revisions=3;$f.RequestedAction='ACCEPT_CURRENT_CANDIDATE';$f.CandidateResult='PASS';$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $f;True $r.allowed;Equal 3 $r.next_candidate_revision;Equal 0 $r.candidate_revisions_remaining;True (Invoke-CmScenarioOracle Test-PfcContinuousTransition (TransitionFixture)).allowed
            foreach ($action in @('CONTROL_RECORD','ENVIRONMENT_RECOVERY')) {$f.RequestedAction=$action;$f.ChangedTrackedPaths=@(if ($action -eq 'CONTROL_RECORD') {$controls[0]});$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $f;True $r.allowed;Equal 3 $r.next_candidate_revision}
        }});Negative=@(@{Name='r3-fail-stops-before-r4';Test={
            $f=RepairFixture;$f.RepairBudget.candidate_revisions=3;$f.RequestedAction='FREEZE_CANDIDATE';$f.ChangedTrackedPaths=@('src/a.ps1');$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $f;True (-not $r.allowed);True $r.hard_stop;Equal 'REPAIR_LOOP_STOPPED' $r.reason
            $t=TransitionFixture;$t.Context.stop_reason=$r.reason;True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).allowed)
            foreach ($bad in @($null,'3',4,-1)) {$f=RepairFixture;$f.RepairBudget.candidate_revisions=$bad;True (-not (Invoke-CmScenarioOracle Test-PfcRepairBudget $f).allowed)}
        }})},
        @{ScenarioId='SC-52';Positive=@(@{Name='only-remaining-confirmed-repair';Test={
            $f=RepairFixture;$f.RepairBudget.builder_code_repair_attempts=1;$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $f;True $r.allowed;Equal 1 $r.builder_attempts_remaining;Equal 2 $r.auto_rework_remaining
        }});Negative=@(@{Name='third-repair-unknown-cause-and-convergence';Test={
            $f=RepairFixture;$f.RepairBudget.builder_code_repair_attempts=2;$r=Invoke-CmScenarioOracle Test-PfcRepairBudget $f;True (-not $r.allowed);True $r.return_lease;Equal 'BUILDER_REPAIR_LIMIT' $r.reason
            foreach ($kind in @('root','same-failure','no-new-pass','STALLED','REGRESSING','auto-limit')) {$f=RepairFixture;switch ($kind) {root {$f.FailureHistory.root_cause_confirmed=$false} same-failure {$f.FailureHistory.same_core_failure_rounds=2} no-new-pass {$f.FailureHistory.rounds_without_new_pass=2} auto-limit {$f.RequestedAction='START_AUTO_REWORK';$f.RepairBudget.auto_rework_rounds=2} default {$f.Convergence=$kind}};True (-not (Invoke-CmScenarioOracle Test-PfcRepairBudget $f).allowed)}
            foreach ($action in @('RESUME','CONTROL_RECORD')) {$f=RepairFixture;$f.RequestedAction=$action;$f.PreviousBudget.auto_rework_rounds=2;True (-not (Invoke-CmScenarioOracle Test-PfcRepairBudget $f).allowed)}
        }})},
        @{ScenarioId='SC-53';Positive=@(@{Name='t3-pass-or-only-evidence-linked-m2';Test={
            $f=New-CmSequenceTransitionFixture 5 @(1,2,3,4,5);True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).allowed;$before=$f.Context.wave_milestones|ConvertTo-Json -Depth 20 -Compress
            $f.Context.wave_t3.result='FAIL';$f.Context.t3_failure_links=@(@{milestone_id='M-2';checkpoint_sha=$f.Context.accepted_checkpoint_sha;evidence_reference='wave/failure';observed=$true});$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);Equal 'REOPEN_LINKED_MILESTONES' $r.next_action;Equal 'M-2' ($r.reopen_milestone_ids -join ',');Equal $before ($f.Context.wave_milestones|ConvertTo-Json -Depth 20 -Compress)
        }});Negative=@(@{Name='unattributable-stale-unrelated-links-block-wave';Test={
            foreach ($kind in @('none','unobserved','old-checkpoint','other-task')) {$f=New-CmSequenceTransitionFixture 5 @(1,2,3,4,5);$f.Context.wave_t3.result='FAIL';$f.Context.t3_failure_links=@(@{milestone_id='M-2';checkpoint_sha=$f.Context.accepted_checkpoint_sha;evidence_reference='wave/failure';observed=$true});switch ($kind) {none {$f.Context.t3_failure_links=@()} unobserved {$f.Context.t3_failure_links[0].observed=$false} old-checkpoint {$f.Context.t3_failure_links[0].checkpoint_sha=$a} other-task {$f.Context.t3_failure_links[0].milestone_id='M-7'}};$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);Equal 'BLOCK_WAVE' $r.next_action;Equal 0 $r.reopen_milestone_ids.Count}
        }})},
        @{ScenarioId='SC-54';Positive=@(@{Name='persist-then-stop-before-exhaustion-and-replan';Test={
            $f=New-CmSequenceTransitionFixture 1 @(1);$f.Context.stop_gate_reached=$true;$f.Context.scope_exhausted=$true;$f.Context.authorization_rechecked=$false;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True $r.allowed;Equal 'STOP_GATE_REACHED' $r.next_action;Equal 'STOP_GATE_REACHED' $r.execution_state;Equal 'EXHAUSTED' $r.authorization_status
            $f.Context.stop_gate_reached=$false;Equal 'COMPLETED' (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).next_action
            $f.Context.scope_exhausted=$false;$f.Context.authorization_rechecked=$true;Equal 'SELECT_NEXT_WAVE' (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).next_action
        }});Negative=@(@{Name='no-boundary-without-persistence-or-t3';Test={
            foreach ($kind in @('persistence','T3','recheck')) {$f=New-CmSequenceTransitionFixture 1 @(1);switch ($kind) {persistence {$f.Context.stop_gate_reached=$true;$f.Context.wave_persistence.observed=$false} T3 {$f.Context.scope_exhausted=$true;$f.Context.wave_t3.result='NOT_RUN'} recheck {$f.Context.authorization_rechecked=$false}};$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not $r.allowed);True (-not $r.writes_allowed)}
        }})},
        @{ScenarioId='SC-55';Positive=@(@{Name='fresh-final-code-and-checkpoint-audit';Test={
            $f=New-CmSequenceTransitionFixture 7 @(6,7);$f.Context.scope_exhausted=$true
            # At the final boundary independent_review binds Goal Code SHA and
            # wave_verifier is the fresh final audit of Goal Checkpoint SHA.
            $f.Context.wave_verifier=@{candidate_sha=$f.Context.accepted_checkpoint_sha;observed=$true;fresh=$true;result='PASS'}
            $r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True $r.allowed;Equal 'COMPLETED' $r.execution_state;Equal 'EXHAUSTED' $r.authorization_status
        }});Negative=@(@{Name='old-milestone-pass-is-not-final-audit';Test={
            foreach ($kind in @('old-code','old-audit','earlier-milestone','absent','not-fresh','PARTIAL','NOT_RUN','gate')) {$f=New-CmSequenceTransitionFixture 7 @(6,7);$f.Context.scope_exhausted=$true;switch ($kind) {old-code {$f.Context.independent_review.candidate_sha=Get-CmCandidateSha 6} old-audit {$f.Context.wave_verifier.candidate_sha=Get-CmCheckpointSha 6} earlier-milestone {$f.Context.wave_verifier=$f.Context.independent_review} absent {$f.Context.wave_verifier=$null} not-fresh {$f.Context.wave_verifier.fresh=$false} PARTIAL {$f.Context.wave_t3.result='PARTIAL'} NOT_RUN {$f.Context.validation_plan[0].result='NOT_RUN'} gate {$f.Context.stop_gate_reached=$true}};$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True ($r.execution_state -cne 'COMPLETED');True (-not $r.writes_allowed)}
        }})},
        @{ScenarioId='SC-56';Positive=@(@{Name='nonessential-unavailability-recorded-as-risk';Test={
            foreach ($capability in @('UNKNOWN','UNAVAILABLE')) {$f=New-CmIssueFixture;$f.Evidence=@('Specialist capability '+$capability);$f.SpecialistRequirement='NONESSENTIAL';$r=Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f;Equal 'CONTINUE' $r.next_action;Equal 'NONE' $r.blocking_scope;Equal 'REGISTER_LIMITATION_AND_TECHNICAL_DEBT' $r.residual_risk;True (Invoke-CmScenarioOracle Test-PfcContinuousTransition (TransitionFixture)).allowed;True ($f.Evidence[0] -cmatch $capability)}
        }});Negative=@(@{Name='unproven-evidence-and-missing-required-tier';Test={
            $f=New-CmIssueFixture;$f.SpecialistRequirement='NONESSENTIAL';$f.IndependentProductEvidence.observed=$false;$r=Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f;Equal 'BLOCK_VERIFICATION' $r.next_action
            $f=New-CmIssueFixture;$f.SpecialistRequirement='AVAILABLE';True ((Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f).next_action -cne 'CONTINUE')
            $t=TransitionFixture;$t.Context.validation_plan[0].result='NOT_RUN';True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $t).allowed)
        }})},
        @{ScenarioId='SC-57';Positive=@(@{Name='essential-block-is-scoped-and-unrelated-can-continue';Test={
            foreach ($affectedPhase in @('MILESTONE','PHASE')) {$f=New-CmIssueFixture;$f.SpecialistRequirement='ESSENTIAL';$f.Phase=$affectedPhase;$f.AffectedScope=@(if ($affectedPhase -eq 'PHASE') {'PHASE-1'} else {'M-1'});$r=Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f;Equal 'BLOCK_VERIFICATION' $r.next_action;Equal $(if ($affectedPhase -eq 'PHASE') {'WAVE'} else {'MILESTONE'}) $r.blocking_scope;Equal 'ESSENTIAL_SPECIALIST_UNAVAILABLE' $r.reason;Equal 1 $f.AffectedScope.Count}
            $f=New-CmIssueFixture;$f.AffectedScope=@('M-OTHER');$f.SpecialistRequirement='NONESSENTIAL';Equal 'CONTINUE' (Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f).next_action
        }});Negative=@(@{Name='unapproved-fallback-cannot-accept-affected-work';Test={
            $f=New-CmIssueFixture;$f.SpecialistRequirement='ESSENTIAL';$f.Fallback.approved=$false;Equal 'BLOCK_VERIFICATION' (Invoke-CmScenarioOracle Resolve-PfcIssueDisposition $f).next_action
            $t=TransitionFixture;$t.Context.essential_specialist_active=$true;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t;True (-not $r.allowed);True (-not $r.writes_allowed)
        }})},
        @{ScenarioId='SC-58';Positive=@(@{Name='pause-intent-persisted-by-fixture-caller';Test={
            $box=New-CmScenarioSandbox
            try {$f=RealRuntimeTransitionFixture;$f.Event='PAUSE';$before=Get-CmFixtureSnapshot $box.Root;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;Equal 'PAUSED' $r.authorization_status;Equal 'BLOCKED' $r.execution_state;Equal 'PERSIST_CHECKPOINT' $r.next_action;True (-not $r.writes_allowed);Equal $before (Get-CmFixtureSnapshot $box.Root)
                $state=@{authorization=(WriteFixture).Authorization;budget=(RepairFixture).RepairBudget;wave=$f.Context.frozen_wave;runtime=$f.Context.runtime;result=$r};$json=$state|ConvertTo-Json -Depth 40 -Compress;$path=Join-Path $box.State 'pause.json';[IO.File]::WriteAllText($path,$json);Equal $json ([IO.File]::ReadAllText($path))
                $f.AuthorizationStatus=$r.authorization_status;$f.ExecutionState=$r.execution_state;$f.Event='RESUME';True (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).writes_allowed
            } finally {Remove-CmScenarioSandbox $box}
        }});Negative=@(@{Name='intent-not-durable-without-copy-no-auto-resume';Test={
            $box=New-CmScenarioSandbox
            try {$f=RealRuntimeTransitionFixture;$f.Event='PAUSE';$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True (-not (Test-Path -LiteralPath (Join-Path $box.State 'pause.json')));$f.AuthorizationStatus=$r.authorization_status;$f.ExecutionState=$r.execution_state;$f.Event='RESUME';$f.Context.user_resume.observed=$false;True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).writes_allowed);$f.Context.user_resume.observed=$true;$f.Context.pre_write_gate.lease_epoch=1;True (-not (Invoke-CmScenarioOracle Test-PfcContinuousTransition $f).writes_allowed)} finally {Remove-CmScenarioSandbox $box}
        }})},
        @{ScenarioId='SC-59';Positive=@(@{Name='status-only-zero-files-lease-or-state-mutation';Test={
            $box=New-CmScenarioSandbox
            try {Initialize-CmFixtureGit $box;foreach ($pair in @(@('ACTIVE','ACTIVE'),@('PAUSED','BLOCKED'),@('INVALIDATED','BLOCKED'))) {$f=RealRuntimeTransitionFixture;$f.Event='STATUS_ONLY';$f.AuthorizationStatus=$pair[0];$f.ExecutionState=$pair[1];$before=Get-CmFixtureSnapshot $box.Root;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;Equal $pair[0] $r.authorization_status;Equal $pair[1] $r.execution_state;Equal 'NONE' $r.next_action;True (-not $r.writes_allowed);Equal $before (Get-CmFixtureSnapshot $box.Root)}} finally {Remove-CmScenarioSandbox $box}
        }});Negative=@(@{Name='unknown-dirty-missing-controls-never-bootstrap';Test={
            $box=New-CmScenarioSandbox
            try {[IO.File]::WriteAllText((Join-Path $box.Repo 'unknown.txt'),'preserve');$f=RealRuntimeTransitionFixture;$f.Event='STATUS_ONLY';$f.Context.unknown_dirty=$true;$f.Context.pre_write_gate=$null;$f.Context.runtime=$null;$before=Get-CmFixtureSnapshot $box.Root;$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $f;True $r.allowed;Equal 'NONE' $r.next_action;True (-not $r.writes_allowed);Equal $before (Get-CmFixtureSnapshot $box.Root)} finally {Remove-CmScenarioSandbox $box}
        }})},
        @{ScenarioId='SC-60';Positive=@(@{Name='observed-git-input-eligible';Test={
            $box=New-CmScenarioSandbox
            try {Initialize-CmFixtureGit $box;True (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate (New-CmPhysicalWriteFixture $box)).can_issue_builder_lease} finally {Remove-CmScenarioSandbox $box}
        }});Negative=@(@{Name='non-git-denied-without-init-or-candidate';Test={
            $box=New-CmScenarioSandbox
            try {$before=Get-CmFixtureSnapshot $box.Root;$t=TransitionFixture;$t.Context.is_git_repository=Test-Path -LiteralPath (Join-Path $box.Repo '.git');$r=Invoke-CmScenarioOracle Test-PfcContinuousTransition $t;True (-not $r.allowed);Equal 'BLOCKED' $r.readiness;True ($r.reasons -ccontains 'GIT_REQUIRED');True (-not $r.writes_allowed);$w=WriteFixture;$w.Observed.is_git_repository=$false;True (-not (Invoke-CmScenarioOracle Test-PfcPreWriteIdentityGate $w).can_issue_builder_lease);Equal $before (Get-CmFixtureSnapshot $box.Root)} finally {Remove-CmScenarioSandbox $box}
        }})}
    )
}
