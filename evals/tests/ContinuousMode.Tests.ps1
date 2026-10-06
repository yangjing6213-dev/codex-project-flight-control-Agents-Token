function Invoke-PfcContinuousModeTests {
    param([string]$RepositoryRoot)
    $results = New-Object 'System.Collections.Generic.List[object]'
    function Check([string]$Id, [scriptblock]$Test) {
        try { & $Test; $results.Add((New-PfcResult -ScenarioId ('continuous.' + $Id) -Status PASS -Message verified)) }
        catch { $results.Add((New-PfcResult -ScenarioId ('continuous.' + $Id) -Status FAIL -Message $_.Exception.Message)) }
    }
    . (Get-PfcContinuousFixtureSetup)
    . (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1')
    Check 'final-fix.immediate-predecessor-and-cross-wave' {
        $f=New-CmSequenceWriteFixture 3 @(1,2,3)
        True (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease
        $old=Get-CmCheckpointSha 1
        foreach($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.Checkpoint)){$o.previous_accepted_checkpoint_sha=$old;$o.current_milestone_base_sha=$old;$o.expected_builder_start_sha=$old}
        $f.Observed.previous_acceptance.milestone_id='M-1';$f.Observed.previous_acceptance.accepted_checkpoint_sha=$old
        $f.Observed.actual_worktree_head=$old;$f.Observed.governance_head_sha=$old;$f.BuilderEcho.actual_worktree_head=$old;$f.Observed.ancestry=@(@{ancestor_sha=$a;descendant_sha=$old;proven=$true})
        True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
        $f=New-CmSequenceWriteFixture 6 @(6,7)
        True (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease
        $old=Get-CmCheckpointSha 4
        foreach($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.Checkpoint)){$o.previous_accepted_checkpoint_sha=$old;$o.current_milestone_base_sha=$old;$o.expected_builder_start_sha=$old}
        $f.Observed.previous_acceptance.milestone_id='M-4';$f.Observed.previous_acceptance.accepted_checkpoint_sha=$old
        $f.Observed.actual_worktree_head=$old;$f.Observed.governance_head_sha=$old;$f.BuilderEcho.actual_worktree_head=$old;$f.WavePlan.base_checkpoint_sha=$old;$f.Observed.ancestry=@(@{ancestor_sha=$a;descendant_sha=$old;proven=$true})
        True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
        $f=New-CmSequenceWriteFixture 6 @(6,7)
        $f.Observed.latest_acceptance=$null
        True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
    }
    Check 'final-fix.history-required-at-review-and-acceptance' {
        $f=ReviewFixture;$f.Observed.actual_head_sha=$d;$f.Observed.canonical_control_paths=$controls
        $f.Observed.ancestry+=@{ancestor_sha=$c;descendant_sha=$d;proven=$true}
        $f.Observed.diffs=@(@{from_sha=$c;to_sha=$d;observed=$true;changed_paths=@();commits=@()})
        True (-not (Test-PfcPreReviewIdentityGate @f).can_start_review)
        $t=TransitionFixture;True (Test-PfcContinuousTransition @t).allowed
        $t.Context.diffs[0].commits=@()
        True (-not (Test-PfcContinuousTransition @t).allowed)
    }
    foreach($mutation in @('missing-history','gap','wrong-end','business-revert','mixed-business','duplicate-commit')) {
        Check ('final-fix.control-history.'+$mutation) {
            $diff=@{from_sha=$a;to_sha=$c;observed=$true;changed_paths=@($controls[0]);commits=@(@{commit_sha=$b;parent_shas=@($a);changed_paths=@($controls[0])},@{commit_sha=$c;parent_shas=@($b);changed_paths=@($controls[0])})}
            $proof=@(@{ancestor_sha=$a;descendant_sha=$c;proven=$true})
            & (Get-Module ContinuousMode) {param($p,$d,$a,$c,$paths) Assert-CmControlDescendant $p @($d) $a $c $paths} $proof $diff $a $c $controls
            switch($mutation){
                'missing-history' {$diff.Remove('commits')}
                'gap' {$diff.commits=@($diff.commits[1])}
                'wrong-end' {$diff.commits[1].commit_sha=$d}
                'business-revert' {$diff.changed_paths=@();$diff.commits[0].changed_paths=@('src/a.ps1');$diff.commits[1].changed_paths=@('src/a.ps1')}
                'mixed-business' {$diff.commits[0].changed_paths+=@('src/a.ps1')}
                'duplicate-commit' {$diff.commits[1].commit_sha=$b}
            }
            Reject { & (Get-Module ContinuousMode) {param($p,$d,$a,$c,$paths) Assert-CmControlDescendant $p @($d) $a $c $paths} $proof $diff $a $c $controls }
        }
    }
    Check 'public-api' {
        $exports = @((Get-Module ContinuousMode).ExportedFunctions.Keys)
        Equal 9 $exports.Count
        foreach ($name in @('Get-PfcRepositoryIdentityV1','Get-PfcRepoPathSetIdentityV1','Get-PfcWorktreeIdentityV1','Test-PfcPreWriteIdentityGate','Test-PfcPreReviewIdentityGate','Resolve-PfcRiskValidationPlan','Resolve-PfcIssueDisposition','Test-PfcRepairBudget','Test-PfcContinuousTransition')) { True ($exports -ccontains $name) }
    }
    # Fixed UTF-8 payload digests computed before implementation, independently of these normalizers.
    Check 'identity.drive-vectors' {
        foreach ($path in @('C:\Repos\Demo\.git\','c:/repos/demo/.git','C:/REPOS/DEMO/.git///')) {
            $r=Get-PfcRepositoryIdentityV1 -GitCommonDirAbsolutePath $path; Present $r; Equal $repo $r.repository_identity; Equal 'c:/repos/demo/.git' $r.normalized_path; Equal 'PFC_GIT_COMMON_DIR_SHA256_V1' $r.identity_algorithm
        }
        $r=Get-PfcWorktreeIdentityV1 -WorktreeRootAbsolutePath 'C:\WORK\Demo\'; Present $r; Equal $wt $r.worktree_identity
        Equal '1591e7653658fb761314757a1ac2b5d392ef1fa874e9f1cadd935bc222927ffd' (Get-PfcRepositoryIdentityV1 'C:\').repository_identity
    }
    Check 'identity.unc-domain-separation' {
        $r=Get-PfcRepositoryIdentityV1 '\\Server\Share\Repo.git\'; Present $r; Equal '01882a3e12c5e19b228af1514a9597b6d64525f38a2b8970c1c375aa07b8f43a' $r.repository_identity
        Equal 'd93f4ec17cffe6b79e866255fbaee38d8844d7b740047596d2a22dde5ad87851' (Get-PfcWorktreeIdentityV1 '//SERVER/share/Work').worktree_identity
        True ((Get-PfcWorktreeIdentityV1 'C:/repos/demo/.git').worktree_identity -cne $repo)
        True ((Get-PfcWorktreeIdentityV1 'C:/work/demo2').worktree_identity -cne $wt)
    }
    foreach ($bad in @('', 'relative/path', 'C:relative', '../repo', 'C:/a/../b', 'C:/a/./b', '\\?\C:\repo', '\\server', 'C:/a//b', "C:/a`n", "C:/a`r", ('C:/a'+[char]0), 'C:/a.')) {
        Check ('identity.reject.' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bad))) { Reject { Get-PfcRepositoryIdentityV1 $bad }; Reject { Get-PfcWorktreeIdentityV1 $bad } }
    }
    Check 'paths.nfc-sort-dedupe-bounded-parent' {
        $r=Get-PfcRepoPathSetIdentityV1 @('SRC\Z.ps1',('src/cafe'+[char]0x301+'.ps1'),'./A.txt','src/tmp/../z.ps1'); Present $r
        Equal '79740fc6e5799d713ec68b1c2ad58d6ec9b52364d37a5bd19aa7e20640350b06' $r.paths_hash
        Equal ("a.txt`nsrc/caf"+[char]0xe9+".ps1`nsrc/z.ps1") ($r.normalized_paths -join "`n")
        Equal '5aa4131bf00dc0d24d8cd44e66bf4dfa68e6d586c2715ec5dea48dc62465beac' (Get-PfcRepoPathSetIdentityV1 @()).paths_hash
        Equal 'fc4628eaecd7833573e6a1bcde6f0580c80e154b6cb5649f0c46fb89a2204c15' (Get-PfcRepoPathSetIdentityV1 @('src/A.ps1')).paths_hash
    }
    foreach ($bad in @('', '.', 'a/..', '../outside', 'a/../../b', '/root', 'C:/x', 'C:foo', '\\server\share', "a`nfile", "a`rfile", ('a'+[char]0), 'a//b', 'a./b', 'a:b')) {
        Check ('paths.reject.' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bad))) { Reject { Get-PfcRepoPathSetIdentityV1 @($bad) } }
    }
    Check 'write.first-no-candidate-and-source-reuse' {
        $f=WriteFixture; $r=Test-PfcPreWriteIdentityGate @f; Present $r; Equal 'PRE_WRITE_IDENTITY_GATE_PASS' $r.result; True $r.can_issue_builder_lease; Equal 'REUSE_AND_REGISTER' $r.canonical_source_action; True ($null -eq $r.PSObject.Properties['lease'])
    }
    foreach ($path in @('Authorization.authorization_id','Authorization.goal.goal_id','Authorization.goal.goal_version','Authorization.scope.from','Authorization.paths.writable_paths_hash','Authorization.repository.authorized_base_checkpoint_sha','Authorization.repository.write_branch_namespace','WorkOrder.work_order_id','WorkOrder.current_milestone_base_sha','WorkOrder.expected_builder_start_sha','BuilderEcho.lease_epoch','BuilderEcho.repository_identity','BuilderEcho.worktree_identity','BuilderEcho.contract_version','BuilderEcho.authorization_status','BuilderEcho.actual_worktree_head','Checkpoint.control_run_id','Checkpoint.milestone_id','Observed.actual_worktree_head','Observed.governance_head_sha','Observed.active_plan_milestone_id','Observed.exact_branch','WavePlan.wave_id')) {
        Check ('write.mismatch.'+$path) { $f=WriteFixture; Change $f $path 'MISMATCH'; $r=Test-PfcPreWriteIdentityGate @f; Present $r; Equal 'STOP_BEFORE_WRITE' $r.result; True (-not $r.can_issue_builder_lease) }
    }
    foreach ($which in @('authorization_sources','wave_sources')) {
        Check ('write.duplicate.'+$which) { $f=WriteFixture; $f.CanonicalSources.$which=@($f.CanonicalSources.$which[0],$f.CanonicalSources.$which[0]); $r=Test-PfcPreWriteIdentityGate @f; Present $r; Equal 'CONTROL_PLANE_DEFECT' $r.result; True (-not $r.can_issue_builder_lease) }
    }
    Check 'write.branch-exact-not-prefix-lookalike' {
        foreach ($branch in @('main','codex/pfc/AUTH-10/m-1','Codex/pfc/AUTH-1/m-1','codex/pfc/AUTH-1/')) {
            $f=WriteFixture; foreach ($obj in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.Observed,$f.WavePlan.milestones[0],$f.Observed.registered_worktrees[0])) { $obj.exact_branch=$branch }
            $r=Test-PfcPreWriteIdentityGate @f; Present $r; True (-not $r.can_issue_builder_lease)
        }
    }
    Check 'write.later-accepted-base-bound-ancestry' {
        $f=WriteFixture
        foreach ($obj in @($f.MilestoneContract,$f.WorkOrder,$f.BuilderEcho,$f.Checkpoint)) { $obj.previous_accepted_checkpoint_sha=$b; $obj.current_milestone_base_sha=$b; $obj.expected_builder_start_sha=$b }
        foreach ($obj in @($f.MilestoneContract,$f.WorkOrder,$f.BuilderEcho,$f.Checkpoint,$f.WavePlan.milestones[0],$f.Observed.registered_worktrees[0])) { $obj.milestone_id='M-2' }
        $f.Observed.active_plan_milestone_id='M-2'; $f.Observed.accepted_milestone_ids=@('M-1')
        $f.Observed | Add-Member NoteProperty previous_acceptance @{result='ACCEPTED';accepted_checkpoint_sha=$b;milestone_id='M-1'}
        $f.Observed | Add-Member NoteProperty accepted_checkpoints @(@{result='ACCEPTED';accepted_checkpoint_sha=$b;milestone_id='M-1';observed=$true})
        $f.Observed | Add-Member NoteProperty latest_acceptance @{result='ACCEPTED';accepted_checkpoint_sha=$b;milestone_id='M-1';wave_id='WAVE-0';observed=$true}
        $f.Observed.actual_worktree_head=$b; $f.Observed.governance_head_sha=$b; $f.BuilderEcho.actual_worktree_head=$b; $f.WavePlan.base_checkpoint_sha=$b; $f.Observed.ancestry=@(@{ancestor_sha=$a;descendant_sha=$b;proven=$true})
        $r=Test-PfcPreWriteIdentityGate @f; Present $r; True $r.can_issue_builder_lease
        $f.Observed.ancestry[0].descendant_sha=$c; True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
    }
    Check 'write.control-descendant-bound-and-exact-allowlist' {
        $f=WriteFixture; foreach ($obj in @($f.MilestoneContract,$f.WorkOrder,$f.BuilderEcho,$f.Checkpoint)) { $obj.expected_builder_start_sha=$b }; $f.BuilderEcho.actual_worktree_head=$b; $f.Observed.actual_worktree_head=$b; $f.Observed.governance_head_sha=$b
        $f.Observed.ancestry+=@{ancestor_sha=$a;descendant_sha=$b;proven=$true}; $f.Observed.diffs=@(@{from_sha=$a;to_sha=$b;observed=$true;changed_paths=@($controls[0]);commits=@(@{commit_sha=$b;parent_shas=@($a);changed_paths=@($controls[0])})})
        $r=Test-PfcPreWriteIdentityGate @f; Present $r; True $r.can_issue_builder_lease
        foreach ($bad in @('docs/project-control/status.md.evil','src/a.ps1','skill/assets/templates/status.md')) { $f.Observed.diffs[0].changed_paths=@($controls[0],$bad); True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease) }
        $f.Observed.diffs[0].observed=$false; True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
    }
    Check 'write.candidate-rework-keeps-base' {
        $f=WriteFixture; $f.Observed.candidate_sha=$c; $f.Checkpoint.repair_budget.candidate_revisions=1
        $f.Observed.ancestry+=@{ancestor_sha=$a;descendant_sha=$c;proven=$true}
        foreach ($obj in @($f.MilestoneContract,$f.WorkOrder,$f.BuilderEcho,$f.Checkpoint)) { $obj.expected_builder_start_sha=$c }; $f.BuilderEcho.actual_worktree_head=$c; $f.Observed.actual_worktree_head=$c; $f.Observed.governance_head_sha=$c
        $r=Test-PfcPreWriteIdentityGate @f; Present $r; True $r.can_issue_builder_lease
        $f.Checkpoint.current_milestone_base_sha=$c; True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
    }
    Check 'write.unknown-and-malformed-deny' {
        foreach ($value in @($null,'false',0)) { $f=WriteFixture; $f.Observed.is_git_repository=$value; $r=Test-PfcPreWriteIdentityGate @f; Present $r; True (-not $r.can_issue_builder_lease) }
        $f=WriteFixture; $f.Observed.git_status=@(@{path='unknown.txt';original_path='NONE';status='??'}); $r=Test-PfcPreWriteIdentityGate @f; True (-not $r.can_issue_builder_lease); True ($r.reasons -contains 'RECOVERY_REQUIRED')
    }
    Check 'review.fresh-builder-no-verifier-required' { $f=ReviewFixture; $r=Test-PfcPreReviewIdentityGate @f; Present $r; True $r.can_start_review; Equal 'PRE_REVIEW_IDENTITY_GATE_PASS' $r.result }
    foreach ($path in @('VerifyOrder.verify_order_id','VerifyOrder.work_order_id','VerifyOrder.wave_id','VerifyOrder.acceptance_record_target','VerifyOrder.base_sha','VerifyOrder.candidate_sha','BuilderReport.builder_evidence_sha','Candidate.candidate_sha','Observed.candidate_sha','PathPolicy.writable_paths_hash')) {
        Check ('review.binding.'+$path) { $f=ReviewFixture; Change $f $path 'OTHER'; $r=Test-PfcPreReviewIdentityGate @f; Present $r; Equal 'CONTROL_PLANE_DEFECT' $r.result; True (-not $r.can_start_review) }
    }
    Check 'review.stale-outside-and-mutation' {
        foreach ($case in @('stale','wrong-sha','outside','tracked','staged','unobserved')) {
            $f=ReviewFixture
            switch ($case) { stale {$f.Observed.builder_evidence[0].fresh=$false} wrong-sha {$f.Observed.builder_evidence[0].candidate_sha=$a} outside {$f.Observed.diff.changed_paths=@('secrets/key')} tracked {$f.Observed.tracked_mutations=@('src/a.ps1')} staged {$f.Observed.staged_mutations=@('src/a.ps1')} unobserved {$f.Observed.diff.observed=$false} }
            $r=Test-PfcPreReviewIdentityGate @f; Present $r; True (-not $r.can_start_review)
        }
    }
    foreach ($risk in @('LOW','MEDIUM','HIGH')) {
        Check ('risk.'+$risk) { $r=Resolve-PfcRiskValidationPlan -BaseRisk $risk -RiskFactors @() -MediumValidation ROLLBACK -AuthorizationLimits $limits; Present $r; True $r.allowed; Equal (@{LOW=5;MEDIUM=3;HIGH=1}[$risk]) $r.max_wave_size; Equal 'T3' ($r.required_wave_tiers -join ','); True ($r.required_milestone_tiers -contains 'T1'); True ($r.required_milestone_tiers -contains 'T2'); Equal ($risk -eq 'HIGH') $r.requires_user_gate }
    }
    Check 'risk.escalation-choice-and-limits' {
        Equal 'MEDIUM' (Resolve-PfcRiskValidationPlan LOW @('UNCERTAINTY') ROLLBACK $limits).risk_level
        Equal 'HIGH' (Resolve-PfcRiskValidationPlan MEDIUM @('DATA_INTEGRITY') ROLLBACK $limits).risk_level
        Equal 'HIGH' (Resolve-PfcRiskValidationPlan LOW @('PERMISSIONS') ROLLBACK $limits).risk_level
        True (-not (Resolve-PfcRiskValidationPlan UNKNOWN @() NONE $limits).allowed)
        True (-not (Resolve-PfcRiskValidationPlan MEDIUM @() NONE $limits).allowed)
        $l=Clone-CmFixture $limits; $l.max_wave_size=2; Equal 2 (Resolve-PfcRiskValidationPlan LOW @() NONE $l).max_wave_size
        True (-not (Resolve-PfcRiskValidationPlan LOW @('UNRECOGNIZED') NONE $limits).allowed)
    }
    Check 'write.minimum-tiers-cannot-be-waived' { $f=WriteFixture; foreach ($o in @($f.MilestoneContract,$f.WorkOrder,$f.BuilderEcho,$f.WavePlan.milestones[0])) { $o.validation_plan=@() }; $r=Test-PfcPreWriteIdentityGate @f; Present $r; True (-not $r.can_issue_builder_lease) }
    foreach ($class in @('PRODUCT_DEFECT','DOCUMENTATION_ONLY','CONTROL_PLANE_DEFECT','SECURITY_OR_DATA_RISK','UNCLASSIFIED','UNKNOWN','TEST_INFRASTRUCTURE_DEFECT','KNOWN_ENVIRONMENT_LIMITATION','EXTERNAL_DEPENDENCY_FAILURE')) {
        Check ('issue.'+$class) {
            $r=Resolve-PfcIssueDisposition -Classification $class -Evidence @('observed failure') -AffectedScope @('M-1') -Phase MILESTONE -Fallback $null -IndependentProductEvidence $null -Budget @{allowed=$true;requires_new_candidate=$true} -SpecialistRequirement NONE; Present $r
            $actions=@{PRODUCT_DEFECT='REPAIR';DOCUMENTATION_ONLY='REPAIR';CONTROL_PLANE_DEFECT='FREEZE_CONTROL';SECURITY_OR_DATA_RISK='STOP';UNCLASSIFIED='PAUSE_COLLECT_EVIDENCE';UNKNOWN='PAUSE_COLLECT_EVIDENCE';TEST_INFRASTRUCTURE_DEFECT='BLOCK_VERIFICATION';KNOWN_ENVIRONMENT_LIMITATION='BLOCK_VERIFICATION';EXTERNAL_DEPENDENCY_FAILURE='BLOCK_VERIFICATION'}
            Equal $actions[$class] $r.next_action
        }
    }
    Check 'issue.fallback-plus-independent-and-specialist' {
        $args=@{Classification='TEST_INFRASTRUCTURE_DEFECT';Evidence=@('observed');AffectedScope=@('M-1');Phase='MILESTONE';Fallback=@{fallback_id='FALLBACK-1';registered=$true;approved=$true;applicable=$true;review_trigger='ENV-1';observed_trigger='ENV-1';trigger_fired=$false};IndependentProductEvidence=@{observed=$true;independent=$true;fresh=$true;result='PASS';candidate_sha=$c;expected_candidate_sha=$c;reference='independent/evidence'};Budget=@{allowed=$true;requires_new_candidate=$false};SpecialistRequirement='NONE'}
        $r=Resolve-PfcIssueDisposition @args; Present $r; Equal 'CONTINUE' $r.next_action
        $args.IndependentProductEvidence.fresh=$false; Equal 'BLOCK_VERIFICATION' (Resolve-PfcIssueDisposition @args).next_action
        $args.IndependentProductEvidence.fresh=$true; $args.Fallback.trigger_fired=$true; Equal 'BLOCK_VERIFICATION' (Resolve-PfcIssueDisposition @args).next_action
        $args.Fallback.trigger_fired=$false; $args.SpecialistRequirement='ESSENTIAL'; Equal 'BLOCK_VERIFICATION' (Resolve-PfcIssueDisposition @args).next_action
        $args.SpecialistRequirement='NONESSENTIAL'; Equal 'CONTINUE' (Resolve-PfcIssueDisposition @args).next_action
    }
    Check 'repair.independent-limits-r3-accept' {
        $f=RepairFixture; $r=Test-PfcRepairBudget @f; Present $r; True $r.allowed; Equal 2 $r.auto_rework_remaining
        $f.RepairBudget.builder_code_repair_attempts=2; $r=Test-PfcRepairBudget @f; True (-not $r.allowed); True $r.return_lease
        $f.RequestedAction='START_AUTO_REWORK'; True (Test-PfcRepairBudget @f).allowed
        $f.RepairBudget.auto_rework_rounds=2; True (-not (Test-PfcRepairBudget @f).allowed)
        $f.RepairBudget.candidate_revisions=3; $f.RequestedAction='ACCEPT_CURRENT_CANDIDATE'; $f.CandidateResult='PASS'; True (Test-PfcRepairBudget @f).allowed
        $f.RequestedAction='FREEZE_CANDIDATE'; $f.ChangedTrackedPaths=@('src/a.ps1'); True (-not (Test-PfcRepairBudget @f).allowed)
    }
    foreach ($path in @('src/a.ps1','tests/a.Tests.ps1','schema.json','templates/report.md','config.ps1','deps.lock','migration.sql','docs/readme.md')) {
        Check ('repair.new-candidate.'+$path) { $f=RepairFixture; $f.ChangedTrackedPaths=@($path); $r=Test-PfcRepairBudget @f; Present $r; True $r.requires_new_candidate; Equal 2 $r.next_candidate_revision }
    }
    Check 'repair.control-only-resume-no-reset' { $f=RepairFixture; $f.RequestedAction='RESUME'; $f.RepairBudget.builder_code_repair_attempts=2; $f.ChangedTrackedPaths=@($controls[0]); $r=Test-PfcRepairBudget @f; Present $r; True $r.allowed; True (-not $r.requires_new_candidate); Equal 0 $r.builder_attempts_remaining; $f.PreviousBudget.builder_code_repair_attempts=2; $f.RepairBudget.builder_code_repair_attempts=0; True (-not (Test-PfcRepairBudget @f).allowed) }
    Check 'repair.r1-through-r3-and-environment-recovery' {
        $f=RepairFixture; $f.CandidateFrozen=$false; $f.RepairBudget.candidate_revisions=0; $f.PreviousBudget.candidate_revisions=0; $f.RequestedAction='FREEZE_CANDIDATE'; Equal 1 (Test-PfcRepairBudget @f).next_candidate_revision
        $f=RepairFixture; $f.RepairBudget.candidate_revisions=2; $f.RequestedAction='FREEZE_CANDIDATE'; $f.ChangedTrackedPaths=@('src/a.ps1'); $r=Test-PfcRepairBudget @f; True $r.allowed; Equal 3 $r.next_candidate_revision
        $f.RequestedAction='ENVIRONMENT_RECOVERY'; $f.ChangedTrackedPaths=@(); $r=Test-PfcRepairBudget @f; True $r.allowed; Equal 2 $r.next_candidate_revision
        $f.RequestedAction='ACCEPT_CURRENT_CANDIDATE'; $f.CandidateResult='PARTIAL'; True (-not (Test-PfcRepairBudget @f).allowed)
    }
    Check 'risk.high-complete-minimum-and-stricter-authorization' {
        $r=Resolve-PfcRiskValidationPlan HIGH @() NONE $limits; Equal 'T1,T2,T3,T4,FAULT_INJECTION,USER_GATE' ($r.required_milestone_tiers -join ',')
        $l=Clone-CmFixture $limits; $l.max_wave_size=1; Equal 1 (Resolve-PfcRiskValidationPlan MEDIUM @() UPGRADE_DOWNGRADE $l).max_wave_size
        $l.max_wave_size='1'; True (-not (Resolve-PfcRiskValidationPlan LOW @() NONE $l).allowed)
    }
    foreach ($counter in @('builder_code_repair_attempts','auto_rework_rounds','candidate_revisions')) {
        Check ('repair.bad-count.'+$counter) { foreach ($bad in @(-1,2.5,'1',$null,4)) { $f=RepairFixture; $f.RepairBudget.$counter=$bad; $r=Test-PfcRepairBudget @f; Present $r; True (-not $r.allowed) } }
    }
    foreach ($stop in @('same_core_failure_rounds','rounds_without_new_pass','root_cause_confirmed','data_corruption','permission_bypass','contract_change_required','scope_change_required','STALLED','REGRESSING')) {
        Check ('repair.hard-stop.'+$stop) { $f=RepairFixture; switch ($stop) { {$_ -in @('STALLED','REGRESSING')} {$f.Convergence=$stop} 'root_cause_confirmed' {$f.FailureHistory.$stop=$false} {$_ -in @('same_core_failure_rounds','rounds_without_new_pass')} {$f.FailureHistory.$stop=2} default {$f.FailureHistory.$stop=$true} }; $r=Test-PfcRepairBudget @f; Present $r; True (-not $r.allowed); True $r.hard_stop; Equal 'REPAIR_LOOP_STOPPED' $r.reason }
    }
    Check 'transition.default-and-status-read-only' {
        Equal 'DISABLED' (Test-PfcContinuousTransition).execution_state
        $f=TransitionFixture; $f.Context.explicit_continuous=$false; $r=Test-PfcContinuousTransition @f; Present $r; Equal 'DISABLED' $r.execution_state; True (-not $r.writes_allowed)
        $f=TransitionFixture; $f.Event='STATUS_ONLY'; $before=$f|ConvertTo-Json -Depth 70; $r=Test-PfcContinuousTransition @f; Present $r; Equal 'ACTIVE' $r.execution_state; Equal 'NONE' $r.next_action; True (-not $r.writes_allowed); Equal $before ($f|ConvertTo-Json -Depth 70)
    }
    Check 'transition.approve-activate-pause-resume' {
        $f=TransitionFixture; $f.Event='APPROVE'; $f.AuthorizationStatus='PAUSED'; $f.ExecutionState='DISABLED'; $r=Test-PfcContinuousTransition @f; Present $r; True $r.allowed; Equal 'ARMED' $r.execution_state
        $f.Event='ACTIVATE'; $f.AuthorizationStatus='ACTIVE'; $f.ExecutionState='ARMED'; Equal 'ACTIVE' (Test-PfcContinuousTransition @f).execution_state
        $f.Event='PAUSE'; Equal 'PAUSED' (Test-PfcContinuousTransition @f).authorization_status
        $f.AuthorizationStatus='PAUSED'; $f.ExecutionState='BLOCKED'; $f.Event='RESUME'; True (Test-PfcContinuousTransition @f).allowed
        $f.Context.user_resume.approved_by='OTHER'; True (-not (Test-PfcContinuousTransition @f).allowed)
    }
    Check 'transition.next-milestone-full-gates' { $f=TransitionFixture; $r=Test-PfcContinuousTransition @f; Present $r; True $r.allowed; Equal 'START_NEXT_MILESTONE' $r.next_action }
    foreach ($path in @('milestone_state','candidate_sha','evidence_sha','acceptance_sha','accepted_checkpoint_sha','next_milestone_id','wave_id','pre_write_gate.expected_builder_start_sha','pre_review_gate.candidate_sha','independent_review.candidate_sha','convergence')) {
        Check ('transition.binding.'+$path) { $f=TransitionFixture; Change $f.Context $path 'BAD'; $r=Test-PfcContinuousTransition @f; Present $r; True (-not $r.allowed) }
    }
    foreach ($status in @('FAIL','PARTIAL','NOT_RUN','REPORTED_ONLY')) {
        Check ('transition.required.'+$status) { $f=TransitionFixture; $f.Context.validation_plan[0].result=$status; $r=Test-PfcContinuousTransition @f; Present $r; True (-not $r.allowed) }
    }
    Check 'transition.pending-and-missing-facts-deny' {
        foreach ($field in @('irreversible_pending','essential_specialist_active','unknown_dirty','git_operation_in_progress','unknown_active_session')) { $f=TransitionFixture; $f.Context.$field=$true; $r=Test-PfcContinuousTransition @f; Present $r; True (-not $r.allowed) }
        foreach ($field in @('findings','changes','accepted_milestone_ids','pre_review_gate')) { $f=TransitionFixture; $f.Context.$field=$null; True (-not (Test-PfcContinuousTransition @f).allowed) }
        $f=TransitionFixture; $f.Context.frozen_wave.dependencies=@('M-0'); True (-not (Test-PfcContinuousTransition @f).allowed)
    }
    Check 'transition.wave-order-stop-before-exhaustion' {
        $f=TransitionFixture; $f.Event='WAVE_END'; $f.Context.frozen_wave.milestone_ids=@('M-1'); $f.Context.stop_gate_reached=$true; $f.Context.scope_exhausted=$true
        $r=Test-PfcContinuousTransition @f; Present $r; True $r.allowed; Equal 'STOP_GATE_REACHED' $r.execution_state; Equal 'EXHAUSTED' $r.authorization_status
        $f.Context.wave_persistence.observed=$false; $r=Test-PfcContinuousTransition @f; True (-not $r.allowed); Equal 'PERSIST_WAVE_SUMMARY' $r.next_action
        $f.Context.wave_persistence.observed=$true; $f.Context.stop_gate_reached=$false; Equal 'COMPLETED' (Test-PfcContinuousTransition @f).execution_state
        $f.Context.scope_exhausted=$false; Equal 'SELECT_NEXT_WAVE' (Test-PfcContinuousTransition @f).next_action
        $f.Context.wave_t3.result='PARTIAL'; True (-not (Test-PfcContinuousTransition @f).allowed)
    }
    Check 'transition.no-auto-resume-or-remote-actions' {
        foreach ($status in @('INVALIDATED','EXHAUSTED','SUSPENDED_BY_RUNTIME_ROLLBACK')) { $f=TransitionFixture; $f.AuthorizationStatus=$status; $f.Event='RESUME'; $r=Test-PfcContinuousTransition @f; Present $r; True (-not $r.allowed); True $r.requires_user_decision }
        foreach ($stop in @('RECOVERY_REQUIRED','REPAIR_LOOP_STOPPED')) { $f=TransitionFixture; $f.Context.stop_reason=$stop; True (-not (Test-PfcContinuousTransition @f).allowed) }
        $f=TransitionFixture; $f.ExecutionState='STOP_GATE_REACHED'; True (-not (Test-PfcContinuousTransition @f).allowed)
        foreach ($event in @('PUSH','MERGE','DEPLOY','UNKNOWN')) { $f=TransitionFixture; $f.Event=$event; True (-not (Test-PfcContinuousTransition @f).allowed) }
        $f=TransitionFixture; $f.Event='INVALIDATE'; Equal 'INVALIDATED' (Test-PfcContinuousTransition @f).authorization_status
        $f.Event='RUNTIME_ROLLBACK'; Equal 'SUSPENDED_BY_RUNTIME_ROLLBACK' (Test-PfcContinuousTransition @f).authorization_status
    }
    Check 'identity.non-string-and-absolute-unicode-contract' {
        foreach ($bad in @($null,17,@('C:/repo'))) { Reject {Get-PfcRepositoryIdentityV1 $bad}; Reject {Get-PfcWorktreeIdentityV1 $bad} }
        Reject {Get-PfcRepoPathSetIdentityV1 'src/a.ps1'}; Reject {Get-PfcRepoPathSetIdentityV1 @($null)}
        Reject {Get-PfcRepoPathSetIdentityV1 @('src/')}
        $composed='C:/caf'+[char]0xe9; $decomposed='C:/cafe'+[char]0x301
        True ((Get-PfcRepositoryIdentityV1 $composed).repository_identity -cne (Get-PfcRepositoryIdentityV1 $decomposed).repository_identity)
    }
    Check 'paths.ordinal-sort-independent-of-culture' {
        $saved=[Threading.Thread]::CurrentThread.CurrentCulture
        try { [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('tr-TR'); $r=Get-PfcRepoPathSetIdentityV1 @('z',([string][char]0xe4),'I'); Equal ('i,z,'+[char]0xe4) ($r.normalized_paths -join ',') }
        finally { [Threading.Thread]::CurrentThread.CurrentCulture=$saved }
    }
    Check 'write.source-registration-before-lease' {
        $f=WriteFixture; $f.CanonicalSources.authorization_sources[0].registered=$false
        $r=Test-PfcPreWriteIdentityGate @f; Equal 'REUSE_AND_REGISTER' $r.canonical_source_action; True (-not $r.can_issue_builder_lease)
    }
    Check 'write.candidate-ancestry-cannot-be-unbound' {
        $f=WriteFixture; $f.Observed.candidate_sha=$c; $f.Checkpoint.repair_budget.candidate_revisions=1
        foreach ($obj in @($f.MilestoneContract,$f.WorkOrder,$f.BuilderEcho,$f.Checkpoint)) {$obj.expected_builder_start_sha=$c}; $f.Observed.actual_worktree_head=$c; $f.Observed.governance_head_sha=$c; $f.BuilderEcho.actual_worktree_head=$c
        True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
    }
    Check 'write.strict-absent-observations' {
        foreach ($field in @('ancestry','diffs','files','git_status','risk_factors','roadmap_ids','canonical_control_paths','registered_worktrees')) { $f=WriteFixture; $f.Observed.$field=$null; True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease) }
        $f=WriteFixture; $f.Observed.ancestry[0].proven='true'; True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
        $f=WriteFixture; $f.ControlPathAllowlist=@('docs/**'); True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
    }
    function DirtyFixture {
        $f=WriteFixture
        $status=@(@{path='src/a.ps1';original_path='NONE';status=' M'})
        $files=@(@{path='src/a.ps1';sha256=('e'*64);size_bytes=42;recovery_copy='copies/a.ps1';classification='ACTIVE'})
        $f.Checkpoint.recovery_manifest.git_status=Clone-CmFixture $status; $f.Checkpoint.recovery_manifest.files=Clone-CmFixture $files
        $f.Observed.git_status=Clone-CmFixture $status; $f.Observed.files=Clone-CmFixture $files
        # Preserve array shape across PowerShell pipeline unrolling.
        $f.Checkpoint.recovery_manifest.git_status=@($f.Checkpoint.recovery_manifest.git_status); $f.Checkpoint.recovery_manifest.files=@($f.Checkpoint.recovery_manifest.files)
        $f.Observed.git_status=@($f.Observed.git_status); $f.Observed.files=@($f.Observed.files)
        $f.Observed | Add-Member NoteProperty recovery_package @{recovery_package_reference='RECOVERY-1';outside_repository=$true;verified=$true}
        $f.Observed | Add-Member NoteProperty recovery_copies @(@{path='src/a.ps1';recovery_copy='copies/a.ps1';sha256=('e'*64);size_bytes=42;recovery_package_reference='RECOVERY-1';verified=$true})
        return $f
    }
    Check 'recovery.known-dirty-and-deletion-copies' {
        $f=DirtyFixture; $r=Test-PfcPreWriteIdentityGate @f; True $r.can_issue_builder_lease
        $f.Observed.git_status[0].status=' D'; $f.Checkpoint.recovery_manifest.git_status[0].status=' D'; True (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease
        $f.Observed.recovery_copies=@(); $r=Test-PfcPreWriteIdentityGate @f; True (-not $r.can_issue_builder_lease); True ($r.reasons -contains 'RECOVERY_REQUIRED')
    }
    foreach ($case in @('hash','size','unknown','extra','duplicate-status','missing-original','wrong-copy','unverified','inside-repo','bad-status')) {
        Check ('recovery.reject.'+$case) {
            $f=DirtyFixture
            switch ($case) {
                hash {$f.Observed.files[0].sha256='f'*64} size {$f.Observed.files[0].size_bytes=43}
                unknown {$f.Observed.files[0].classification='UNKNOWN';$f.Checkpoint.recovery_manifest.files[0].classification='UNKNOWN'}
                extra {$f.Observed.git_status+=@{path='new.txt';original_path='NONE';status='??'}}
                duplicate-status {$f.Observed.git_status+=($f.Observed.git_status[0]);$f.Checkpoint.recovery_manifest.git_status+=($f.Checkpoint.recovery_manifest.git_status[0])}
                missing-original {$f.Observed.git_status[0].status='R ';$f.Checkpoint.recovery_manifest.git_status[0].status='R ';$f.Observed.git_status[0].original_path='src/old.ps1';$f.Checkpoint.recovery_manifest.git_status[0].original_path='src/old.ps1'}
                wrong-copy {$f.Observed.recovery_copies[0].recovery_package_reference='OTHER'}
                unverified {$f.Observed.recovery_copies[0].verified='true'} inside-repo {$f.Observed.recovery_package.outside_repository=$false}
                bad-status {$f.Observed.git_status[0].status='??junk';$f.Checkpoint.recovery_manifest.git_status[0].status='??junk'}
            }
            $r=Test-PfcPreWriteIdentityGate @f; True (-not $r.can_issue_builder_lease); True ($r.reasons -contains 'RECOVERY_REQUIRED')
        }
    }
    Check 'review.evidence-ids-and-ancestry-bound' {
        $f=ReviewFixture; $f.Observed.builder_evidence[0].evidence_id='OTHER-1'; True (-not (Test-PfcPreReviewIdentityGate @f).can_start_review)
        $f=ReviewFixture; $f.Observed.ancestry[0].ancestor_sha=$b; True (-not (Test-PfcPreReviewIdentityGate @f).can_start_review)
    }
    Check 'review.no-stringly-contract-version' {
        $f=ReviewFixture; foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.VerifyOrder,$f.BuilderReport,$f.Candidate,$f.WavePlan.milestones[0])) {$o.contract_version='1'}
        True (-not (Test-PfcPreReviewIdentityGate @f).can_start_review)
    }
    Check 'transition.wave-t3-attribution-and-freshness' {
        $f=TransitionFixture; $f.Event='WAVE_END'; $f.Context.frozen_wave.milestone_ids=@('M-1'); $f.Context.wave_t3.result='FAIL'; $f.Context.t3_failure_links=@()
        $r=Test-PfcContinuousTransition @f; True (-not $r.allowed); Equal 'BLOCK_WAVE' $r.next_action
        $f.Context.t3_failure_links=@(@{milestone_id='M-1';checkpoint_sha=$b;evidence_reference='failure/reference';observed=$true})
        $r=Test-PfcContinuousTransition @f; True (-not $r.allowed); Equal 'REOPEN_LINKED_MILESTONES' $r.next_action; Equal 'M-1' ($r.reopen_milestone_ids -join ',')
        $f.Context.wave_t3.result='PASS'; $f.Context.wave_verifier.fresh=$false; True (-not (Test-PfcContinuousTransition @f).allowed)
    }
    Check 'transition.fresh-evidence-required-and-no-optional-waiver' {
        $f=TransitionFixture; $f.Context.validation_observations[0].fresh=$false; True (-not (Test-PfcContinuousTransition @f).allowed)
        $f=TransitionFixture; $f.Context.validation_plan[0].required=$false; True (-not (Test-PfcContinuousTransition @f).allowed)
        $f=TransitionFixture; $f.Context.independent_review.observed='true'; True (-not (Test-PfcContinuousTransition @f).allowed)
        $f=TransitionFixture; $f.Event=@('STATUS_ONLY'); True (-not (Test-PfcContinuousTransition @f).allowed)
    }
    Check 'transition.current-gate-and-next-risk' {
        $f=TransitionFixture; $f.Context.current_pre_write_gate=$null; True (-not (Test-PfcContinuousTransition @f).allowed)
        $f=TransitionFixture; $f.Context.next_risk_level='HIGH'; True (-not (Test-PfcContinuousTransition @f).allowed)
        $f=TransitionFixture; $f.Context.pre_write_gate.work_order_id='OLD-ORDER'; True (-not (Test-PfcContinuousTransition @f).allowed)
    }
    Check 'transition.control-record-descendant-keeps-accepted-base' {
        $f=TransitionFixture; $f.Context.actual_head_sha=$d; $f.Context.governance_head_sha=$d; $f.Context.pre_write_gate.expected_builder_start_sha=$d
        $f.Context.ancestry+=@{ancestor_sha=$b;descendant_sha=$d;proven=$true}; $f.Context.diffs+=@{from_sha=$b;to_sha=$d;observed=$true;changed_paths=@($controls[0]);commits=@(@{commit_sha=$d;parent_shas=@($b);changed_paths=@($controls[0])})}
        $r=Test-PfcContinuousTransition @f; True $r.allowed; Equal 'START_NEXT_MILESTONE' $r.next_action
        $f.Context.diffs[1].changed_paths=@('src/a.ps1'); True (-not (Test-PfcContinuousTransition @f).allowed)
    }
    Check 'transition.recovery-steps-do-not-renew-authorization' {
        $f=TransitionFixture; $dirty=DirtyFixture; $f.Event='RECOVERY_COMPLETE'; $f.AuthorizationStatus='INVALIDATED'; $f.ExecutionState='BLOCKED'
        $f.Context.recovery_steps=@(@('READ_ONLY_INVENTORY','EXTERNAL_RECOVERY_PACKAGE','HASH_SIZE_MANIFEST','CLASSIFICATION','REVERSIBLE_ISOLATION','GOVERNANCE_CHECKPOINT','PRE_WRITE_IDENTITY_GATE') | ForEach-Object {@{name=$_;checkpoint_sha=$b;recovery_package_reference='RECOVERY-1';observed=$true}})
        $f.Context.recovery_checkpoint=$dirty.Checkpoint; $f.Context.recovery_observed=$dirty.Observed; $f.Context.recovery_writable_paths=@('src/a.ps1'); $f.Context.recovery_forbidden_paths=@('secrets')
        $f.Context.recovery_checkpoint.expected_builder_start_sha=$b; $f.Context.recovery_observed.actual_worktree_head=$b
        $r=Test-PfcContinuousTransition @f; True (-not $r.allowed); Equal 'REQUEST_REAUTHORIZATION' $r.next_action; True $r.requires_user_decision
        $f.Context.recovery_checkpoint.expected_builder_start_sha=$a; Equal 'RECOVERY_REQUIRED' (Test-PfcContinuousTransition @f).readiness; $f.Context.recovery_checkpoint.expected_builder_start_sha=$b
        $f.Context.recovery_steps[2].observed=$false; $r=Test-PfcContinuousTransition @f; Equal 'RECOVERY_REQUIRED' $r.readiness; Equal 'HASH_SIZE_MANIFEST' $r.next_action
    }
    Check 'pure.no-environment-or-external-api' {
        $module=Get-Module ContinuousMode
        $tokens=$null;$errors=$null; $ast=[Management.Automation.Language.Parser]::ParseFile($module.Path,[ref]$tokens,[ref]$errors)
        Equal 0 @($errors).Count
        $declared=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true) | ForEach-Object {$_.Name})
        $allowed=@('Set-StrictMode','New-Object','Where-Object','ForEach-Object','Select-Object','Export-ModuleMember')+$declared
        foreach ($command in $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)) { True ($allowed -ccontains $command.GetCommandName()) }
        foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.TypeExpressionAst]},$true)) { True ($node.TypeName.FullName -notmatch '(?i)(\.IO\.|Environment|DateTime|Guid|Random|Process|Net\.|Thread)') }
        foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.VariableExpressionAst]},$true)) { True ($node.VariablePath.UserPath -notmatch '^(?i:env|global):') }
    }
    # Independent-review counterexamples: expectations describe denied authority,
    # not a particular implementation path or a parser failure.
    foreach ($kind in @('write-control','review-control','writable-path','branch','source-id','repair-control','event')) {
        Check ('r1.ordinal.'+$kind) {
            $odd='docs/project-control/sta'+[char]0xad+'tus.md'
            switch ($kind) {
                write-control {
                    $f=WriteFixture; foreach ($o in @($f.MilestoneContract,$f.WorkOrder,$f.BuilderEcho,$f.Checkpoint)) {$o.expected_builder_start_sha=$b}; $f.Observed.actual_worktree_head=$b;$f.Observed.governance_head_sha=$b;$f.BuilderEcho.actual_worktree_head=$b
                    $f.Observed.ancestry+=@{ancestor_sha=$a;descendant_sha=$b;proven=$true};$f.Observed.diffs=@(@{from_sha=$a;to_sha=$b;observed=$true;changed_paths=@($odd);commits=@(@{commit_sha=$b;parent_shas=@($a);changed_paths=@($odd)})})
                    True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
                }
                review-control {
                    $f=ReviewFixture;$f.Observed.actual_head_sha=$d;$f.Observed.ancestry+=@{ancestor_sha=$c;descendant_sha=$d;proven=$true};$f.Observed.diffs=@(@{from_sha=$c;to_sha=$d;observed=$true;changed_paths=@($odd);commits=@(@{commit_sha=$d;parent_shas=@($c);changed_paths=@($odd)})});$f.Observed.canonical_control_paths=$controls
                    True (-not (Test-PfcPreReviewIdentityGate @f).can_start_review)
                }
                writable-path {
                    $f=ReviewFixture;$path='src/a'+[char]0xad+'.ps1';foreach ($o in @($f.VerifyOrder,$f.BuilderReport,$f.Candidate)) {$o.changed_files=@($path)};$f.Observed.diff.changed_paths=@($path)
                    $f.VerifyOrder.wave_impact_checks[0].paths=@($path);$f.BuilderReport.wave_impact.paths=@($path)
                    True (-not (Test-PfcPreReviewIdentityGate @f).can_start_review)
                }
                branch {$f=WriteFixture;$f.Observed.exact_branch='codex/pfc/AUTH-1/m'+[char]0xad+'-1';True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)}
                source-id {$f=WriteFixture;$f.CanonicalSources.authorization_sources[0].authorization_id='AU'+[char]0xad+'TH-1';True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)}
                repair-control {$f=RepairFixture;$f.RequestedAction='CONTROL_RECORD';$f.ChangedTrackedPaths=@($odd);$r=Test-PfcRepairBudget @f;True (-not $r.allowed);True $r.requires_new_candidate}
                event {$f=TransitionFixture;$f.Event='RESU'+[char]0xad+'ME';True (-not (Test-PfcContinuousTransition @f).allowed)}
            }
        }
    }
    $nestedCases=@(
        @{id='ancestor-array';kind='write';mutate={param($f) $f.Observed.ancestry[0].ancestor_sha=@($a,$b)}},
        @{id='approval-array';kind='write';mutate={param($f) $f.Observed.approval.approved_by=@('USER','OTHER')}},
        @{id='evidence-sha-array';kind='review';mutate={param($f) $f.Observed.builder_evidence[0].candidate_sha=@($c,$a)}},
        @{id='evidence-order-array';kind='review';mutate={param($f) $f.Observed.builder_evidence[0].work_order_id=@('ORDER-1','OLD-ORDER')}},
        @{id='diff-origin-array';kind='review';mutate={param($f) $f.Observed.actual_head_sha=$d;$f.Observed.ancestry+=@{ancestor_sha=$c;descendant_sha=$d;proven=$true};$f.Observed.diffs=@(@{from_sha=@($a,$c);to_sha=$d;observed=$true;changed_paths=@($controls[0]);commits=@(@{commit_sha=$d;parent_shas=@(@($a,$c));changed_paths=@($controls[0])})});$f.Observed.canonical_control_paths=$controls}},
        @{id='gate-sha-array';kind='transition';mutate={param($f) $f.Context.pre_write_gate.expected_builder_start_sha=@($b,$a)}},
        @{id='review-result-array';kind='transition';mutate={param($f) $f.Context.independent_review.result=@('PASS','FAIL')}},
        @{id='candidate-result-array';kind='repair';mutate={param($f) $f.RequestedAction='ACCEPT_CURRENT_CANDIDATE';$f.CandidateResult=@('PASS','FAIL')}},
        @{id='single-action-array';kind='repair';mutate={param($f) $f.RequestedAction=@('RESUME')}},
        @{id='multiple-action-array';kind='repair';mutate={param($f) $f.RequestedAction=@('START_BUILDER_REPAIR','RESUME')}},
        @{id='status-invalid-pair';kind='dirty';mutate={param($f) $f.Observed.git_status[0].status='?M';$f.Checkpoint.recovery_manifest.git_status[0].status='?M'}}
    )
    foreach ($case in $nestedCases) {
        Check ('r1.scalar.'+$case.id) {
            $f=switch ($case.kind) {write {WriteFixture} review {ReviewFixture} transition {TransitionFixture} repair {RepairFixture} dirty {DirtyFixture}}
            & $case.mutate $f
            $r=switch ($case.kind) {write {Test-PfcPreWriteIdentityGate @f} review {Test-PfcPreReviewIdentityGate @f} transition {Test-PfcContinuousTransition @f} repair {Test-PfcRepairBudget @f} dirty {Test-PfcPreWriteIdentityGate @f}}
            if ($case.kind -in @('write','dirty')) {True (-not $r.can_issue_builder_lease)} elseif ($case.kind -eq 'review') {True (-not $r.can_start_review)} else {True (-not $r.allowed)}
        }
    }
    foreach ($bad in @($null,'',@('GATE-1','OTHER'),'bad_gate')) {
        Check ('r1.scalar.stop-gate.'+($bad|ConvertTo-Json -Compress)) {
            $f=WriteFixture;foreach ($o in @($f.Authorization,$f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho)) {$o.scope.stop_gate=$bad};$f.WavePlan.stop_gate=$bad
            True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)
        }
    }
    Check 'r1.scalar.infrastructure-result' {
        $f=@{Classification='TEST_INFRASTRUCTURE_DEFECT';Evidence=@('observed');AffectedScope=@('M-1');Phase='MILESTONE';Fallback=@{fallback_id='FALLBACK-1';registered=$true;approved=$true;applicable=$true;review_trigger='ENV-1';observed_trigger='ENV-1';trigger_fired=$false};IndependentProductEvidence=@{observed=$true;independent=$true;fresh=$true;result=@('PASS','FAIL');candidate_sha=$c;expected_candidate_sha=$c;reference='independent/evidence'};SpecialistRequirement='NONE'}
        Equal 'BLOCK_VERIFICATION' (Resolve-PfcIssueDisposition @f).next_action
    }
    Check 'r1.recovery.legal-rename-and-copy-status' {
        $f=DirtyFixture; $original=@{path='src/old.ps1';sha256=('f'*64);size_bytes=41;recovery_copy='copies/old.ps1';classification='ACTIVE'}
        $f.Observed.writable_paths=@('src/a.ps1','src/old.ps1'); $hash=(Get-PfcRepoPathSetIdentityV1 $f.Observed.writable_paths).paths_hash
        foreach ($o in @($f.WorkOrder,$f.MilestoneContract,$f.BuilderEcho,$f.Authorization.paths)) {$o.writable_paths_hash=$hash}
        $f.Checkpoint.recovery_manifest.allowed_paths=@('src/a.ps1','src/old.ps1')
        $f.Checkpoint.recovery_manifest.files+=Clone-CmFixture $original; $f.Observed.files+=Clone-CmFixture $original
        $f.Observed.recovery_copies+=@{path='src/old.ps1';sha256=('f'*64);size_bytes=41;recovery_copy='copies/old.ps1';recovery_package_reference='RECOVERY-1';verified=$true}
        foreach ($status in @('R ','RM',' R','C ')) {
            foreach ($o in @($f.Observed.git_status[0],$f.Checkpoint.recovery_manifest.git_status[0])) {$o.status=$status;$o.original_path='src/old.ps1'}
            True (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease
        }
    }
    foreach ($kind in @('write','review')) {
        $fixture=if ($kind -eq 'write') {WriteFixture} else {ReviewFixture}
        foreach ($key in @($fixture.Keys)) {
            Check ('r1.top-level-null.'+$kind+'.'+$key) {
                $f=if ($kind -eq 'write') {WriteFixture} else {ReviewFixture};$f[$key]=$null
                if ($kind -eq 'write') {True (-not (Test-PfcPreWriteIdentityGate @f).can_issue_builder_lease)} else {True (-not (Test-PfcPreReviewIdentityGate @f).can_start_review)}
            }
        }
    }
    Check 'r1.runtime.real-gate-replay' {
        $write=WriteFixture;$old=Test-PfcPreWriteIdentityGate @write;True $old.can_issue_builder_lease
        $f=TransitionFixture;$f.Event='RESUME';$f.AuthorizationStatus='PAUSED';$f.ExecutionState='BLOCKED';$f.Context.next_milestone_id='M-1';$f.Context.next_work_order_id='ORDER-1';$f.Context.actual_head_sha=$a;$f.Context.governance_head_sha=$a;$f.Context.pre_write_gate=$old
        $r=Test-PfcContinuousTransition @f;True (-not $r.writes_allowed);True (-not $r.allowed)
        foreach ($o in @($write.WorkOrder,$write.MilestoneContract,$write.BuilderEcho,$write.Checkpoint)) {$o.control_run_id='RUN-2';$o.lease_epoch=2}
        $fresh=Test-PfcPreWriteIdentityGate @write;True $fresh.can_issue_builder_lease;Equal 'RUN-2' $fresh.control_run_id;Equal 2 $fresh.lease_epoch
        $f.Context.pre_write_gate=$fresh;True (Test-PfcContinuousTransition @f).writes_allowed
    }
    foreach ($event in @('ACTIVATE','RESUME','NEXT_MILESTONE')) {
        Check ('r1.runtime.binding.'+$event) {$f=TransitionFixture;$f.Event=$event;if ($event -eq 'ACTIVATE') {$f.ExecutionState='ARMED'};$f.Context.pre_write_gate.control_run_id='RUN-OLD';$f.Context.pre_write_gate.lease_epoch=1;True (-not (Test-PfcContinuousTransition @f).writes_allowed)}
    }
    foreach ($stop in @('STALLED','BLOCKER')) {
        Check ('r1.stop.chained-resume.'+$stop) {
            $f=TransitionFixture;if ($stop -eq 'STALLED') {$f.Context.convergence=$stop} else {$f.Context.findings=@(@{severity=$stop})}
            $first=Test-PfcContinuousTransition @f;True (-not $first.allowed);True ($first.requires_user_decision -or $first.authorization_status -eq 'INVALIDATED')
            $f.AuthorizationStatus=$first.authorization_status;$f.ExecutionState=$first.execution_state;$f.Event='RESUME';$second=Test-PfcContinuousTransition @f;True (-not $second.allowed);True (-not $second.writes_allowed)
        }
    }
    Check 'r1.stop.boundary-finalization-order' {
        $f=TransitionFixture;$f.Context.stop_gate_reached=$true;$f.Context.scope_exhausted=$true
        $blocked=Test-PfcContinuousTransition @f;True (-not $blocked.writes_allowed);True $blocked.requires_user_decision;Equal 'PERSIST_WAVE_SUMMARY' $blocked.next_action
        $f.AuthorizationStatus=$blocked.authorization_status;$f.ExecutionState=$blocked.execution_state;$f.Event='WAVE_END';$f.Context.frozen_wave.milestone_ids=@('M-1')
        $f.Context.wave_t3.result='NOT_RUN';True (-not (Test-PfcContinuousTransition @f).allowed)
        $f.Context.wave_t3.result='PASS';$f.Context.wave_persistence.observed=$false;$pending=Test-PfcContinuousTransition @f;True (-not $pending.allowed);Equal 'PERSIST_WAVE_SUMMARY' $pending.next_action
        $f.Context.wave_persistence.observed=$true;$stopped=Test-PfcContinuousTransition @f;True $stopped.allowed;True (-not $stopped.writes_allowed);Equal 'STOP_GATE_REACHED' $stopped.execution_state;Equal 'EXHAUSTED' $stopped.authorization_status
        $f.AuthorizationStatus=$stopped.authorization_status;$f.ExecutionState=$stopped.execution_state;$f.Event='RESUME';True (-not (Test-PfcContinuousTransition @f).writes_allowed)
    }
    foreach ($event in @('ACTIVATE','RESUME','NEXT_MILESTONE')) {
        foreach ($stop in @('irreversible_pending','essential_specialist_active','stop_gate_reached','scope_exhausted')) {
            Check ('r1.stop.before-permission.'+$event+'.'+$stop) {$f=TransitionFixture;$f.Event=$event;if ($event -eq 'ACTIVATE') {$f.ExecutionState='ARMED'};$f.Context.$stop=$true;$r=Test-PfcContinuousTransition @f;True (-not $r.allowed);True (-not $r.writes_allowed)}
        }
    }
    foreach ($case in @('missing-order','missing-report','wrong-wave','wrong-milestone','wrong-candidate','wrong-path','wrong-dependency','failed','not-run')) {
        Check ('r1.wave-impact.'+$case) {
            $f=ReviewFixture
            switch ($case) {
                missing-order {$f.VerifyOrder.wave_impact_checks=$null} missing-report {$f.BuilderReport.wave_impact=$null}
                wrong-wave {$f.VerifyOrder.wave_impact_checks[0].wave_id='WRONG-WAVE';$f.BuilderReport.wave_impact.wave_id='OLD-WAVE'}
                wrong-milestone {$f.VerifyOrder.wave_impact_checks[0].milestone_id='OTHER'} wrong-candidate {$f.BuilderReport.wave_impact.candidate_sha=$a}
                wrong-path {$f.BuilderReport.wave_impact.paths=@('src/other.ps1')} wrong-dependency {$f.VerifyOrder.wave_impact_checks[0].dependencies=@('M-OLD')}
                failed {$f.BuilderReport.wave_impact.result='FAIL'} not-run {$f.BuilderReport.wave_impact.result='NOT_RUN'}
            }
            True (-not (Test-PfcPreReviewIdentityGate @f).can_start_review)
        }
    }
    foreach ($name in @('COM','LPT')) {
        foreach ($digit in @(0xb9,0xb2,0xb3)) {
            Check ('r1.device.'+$name+'.'+$digit) {foreach ($suffix in @('','.txt')) {$segment=$name+[char]$digit+$suffix;Reject {Get-PfcRepoPathSetIdentityV1 @('src/'+$segment)};Reject {Get-PfcRepositoryIdentityV1 ('C:/src/'+$segment)};Reject {Get-PfcWorktreeIdentityV1 ('//server/share/'+$segment)}}}
        }
    }
    Check 'r1.path.repeated-separators' {foreach ($path in @('C:////repo/.git','C://repo/.git','C:/repo//.git','//server//share/repo','//server/share//repo')) {Reject {Get-PfcRepositoryIdentityV1 $path};Reject {Get-PfcWorktreeIdentityV1 $path}}}
    function RealRuntimeTransitionFixture {
        $write=WriteFixture
        foreach ($o in @($write.WorkOrder,$write.MilestoneContract,$write.BuilderEcho,$write.Checkpoint)) {$o.control_run_id='RUN-2';$o.lease_epoch=2}
        $gate=Test-PfcPreWriteIdentityGate @write;True $gate.can_issue_builder_lease
        $f=TransitionFixture;$f.Context.pre_write_gate=$gate;$f.Context.next_milestone_id='M-1';$f.Context.next_work_order_id='ORDER-1';$f.Context.actual_head_sha=$a;$f.Context.governance_head_sha=$a
        return $f
    }
    function PauseThenResume($Fixture) {
        $Fixture.Event='PAUSE';$paused=Test-PfcContinuousTransition @Fixture
        $Fixture.AuthorizationStatus=$paused.authorization_status;$Fixture.ExecutionState=$paused.execution_state;$Fixture.Event='RESUME'
        $Fixture.Context.convergence='IMPROVING';$Fixture.Context.stop_reason='NONE'
        @{paused=$paused;resumed=(Test-PfcContinuousTransition @Fixture)}
    }
    foreach ($state in @('INVALIDATED','EXHAUSTED','SUSPENDED_BY_RUNTIME_ROLLBACK')) {
        Check ('r2.pause.authorization.'+$state) {
            $f=RealRuntimeTransitionFixture;$f.AuthorizationStatus=$state;$f.ExecutionState='BLOCKED';$chain=PauseThenResume $f
            True (-not $chain.resumed.writes_allowed);True (-not $chain.resumed.allowed);True $chain.paused.requires_user_decision
            Equal $state $chain.paused.authorization_status;Equal 'BLOCKED' $chain.paused.execution_state
        }
    }
    Check 'r2.pause.stalled-real-gate' {
        $f=RealRuntimeTransitionFixture;$f.Context.convergence='STALLED';$stopped=Test-PfcContinuousTransition @f
        Equal 'INVALIDATED' $stopped.authorization_status;True $stopped.requires_user_decision
        $f.AuthorizationStatus=$stopped.authorization_status;$f.ExecutionState=$stopped.execution_state;$chain=PauseThenResume $f
        True (-not $chain.resumed.writes_allowed);True (-not $chain.resumed.allowed);Equal 'INVALIDATED' $chain.paused.authorization_status;True $chain.paused.requires_user_decision
    }
    foreach ($state in @('STOP_GATE_REACHED','COMPLETED')) {
        Check ('r2.pause.execution.'+$state) {
            $f=RealRuntimeTransitionFixture;$f.ExecutionState=$state;$chain=PauseThenResume $f
            True (-not $chain.resumed.writes_allowed);True $chain.paused.requires_user_decision;Equal 'ACTIVE' $chain.paused.authorization_status;Equal $state $chain.paused.execution_state
        }
    }
    Check 'r2.pause.durable-stop-reason' {
        foreach ($reason in @('REPAIR_LOOP_STOPPED','RECOVERY_REQUIRED')) {
            $f=RealRuntimeTransitionFixture;$f.ExecutionState='BLOCKED';$f.Context.stop_reason=$reason;$chain=PauseThenResume $f
            True (-not $chain.resumed.writes_allowed);Equal 'INVALIDATED' $chain.paused.authorization_status;True $chain.paused.requires_user_decision
        }
        $f=RealRuntimeTransitionFixture;$f.Context.convergence='STALLED';$chain=PauseThenResume $f
        True (-not $chain.resumed.writes_allowed);Equal 'INVALIDATED' $chain.paused.authorization_status
    }
    Check 'r2.pause.only-active-states' {
        foreach ($pair in @(@('NONE','DISABLED'),@('ACTIVE','DISABLED'),@('PAUSED','DISABLED'))) {
            $f=RealRuntimeTransitionFixture;$f.AuthorizationStatus=$pair[0];$f.ExecutionState=$pair[1];$f.Event='PAUSE';$r=Test-PfcContinuousTransition @f
            True (-not $r.allowed);True (-not $r.writes_allowed)
        }
    }
    Check 'r2.pause.normal-resume-and-new-approval' {
        $f=RealRuntimeTransitionFixture;$chain=PauseThenResume $f;True $chain.paused.allowed;Equal 'PAUSED' $chain.paused.authorization_status;True $chain.resumed.writes_allowed
        foreach ($pair in @(@('INVALIDATED','BLOCKED'),@('EXHAUSTED','BLOCKED'),@('SUSPENDED_BY_RUNTIME_ROLLBACK','BLOCKED'),@('ACTIVE','STOP_GATE_REACHED'),@('EXHAUSTED','COMPLETED'))) {
            $f=RealRuntimeTransitionFixture;$f.AuthorizationStatus=$pair[0];$f.ExecutionState=$pair[1];$f.Event='APPROVE';$f.Context.previous_decision_id='DEC-1'
            $denied=Test-PfcContinuousTransition @f;True (-not $denied.allowed);True $denied.requires_user_decision
            $f.AuthorizationStatus=$denied.authorization_status;$f.ExecutionState=$denied.execution_state;$f.Event='RESUME';True (-not (Test-PfcContinuousTransition @f).writes_allowed);$f.Event='APPROVE'
            $f.Context.source_decision_id='DEC-2';$f.Context.approval.source_decision_id='DEC-2';$f.Context.approval.observed=$false;True (-not (Test-PfcContinuousTransition @f).allowed)
            $f.Context.approval.observed=$true;$f.Context.convergence='STALLED';True (-not (Test-PfcContinuousTransition @f).allowed)
            $f.Context.convergence='IMPROVING';$r=Test-PfcContinuousTransition @f;True $r.allowed;Equal 'ACTIVE' $r.authorization_status;Equal 'ARMED' $r.execution_state;True (-not $r.writes_allowed)
        }
    }
    Check 'pure.deterministic-and-inputs-unchanged' {
        foreach ($name in @('Test-PfcPreWriteIdentityGate','Test-PfcPreReviewIdentityGate','Test-PfcRepairBudget','Test-PfcContinuousTransition')) {
            $f=switch ($name) {'Test-PfcPreWriteIdentityGate' {WriteFixture} 'Test-PfcPreReviewIdentityGate' {ReviewFixture} 'Test-PfcRepairBudget' {RepairFixture} 'Test-PfcContinuousTransition' {TransitionFixture}}
            $before=$f|ConvertTo-Json -Depth 70; $r=& $name @f; Present $r; $again=& $name @f; Equal ($r|ConvertTo-Json -Depth 70) ($again|ConvertTo-Json -Depth 70); Equal $before ($f|ConvertTo-Json -Depth 70)
        }
        $riskArgs=@{BaseRisk='MEDIUM';RiskFactors=@();MediumValidation='UPGRADE_DOWNGRADE';AuthorizationLimits=$limits}; $before=$riskArgs|ConvertTo-Json -Depth 20; $risk=Resolve-PfcRiskValidationPlan @riskArgs; Equal 'T1,T2,UPGRADE_DOWNGRADE' ($risk.required_milestone_tiers -join ','); Equal $before ($riskArgs|ConvertTo-Json -Depth 20)
        $issueArgs=@{Classification='KNOWN_ENVIRONMENT_LIMITATION';Evidence=@('observed');AffectedScope=@('M-1');Phase='MILESTONE';Fallback=@{fallback_id='FALLBACK-1';registered=$true;approved=$true;applicable=$true;review_trigger='ENV-1';observed_trigger='ENV-1';trigger_fired=$false};SpecialistRequirement='NONESSENTIAL'}; $before=$issueArgs|ConvertTo-Json -Depth 20; $issue=Resolve-PfcIssueDisposition @issueArgs; Equal 'USE_APPROVED_FALLBACK' $issue.next_action; Equal $before ($issueArgs|ConvertTo-Json -Depth 20)
        $paths=@('src/Z.ps1','src/a.ps1'); $before=$paths -join '|'; [void](Get-PfcRepoPathSetIdentityV1 $paths); Equal $before ($paths -join '|')
    }
    foreach ($result in @(Invoke-PfcContinuousScenarioTests -RepositoryRoot $RepositoryRoot)) { $results.Add($result) }
    Check 'scenario.inventory-negative-contract' {
        . (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1')
        $table=@(Get-PfcContinuousModeScenarios);True (Test-PfcContinuousScenarioInventory $table)
        True (-not (Test-PfcContinuousScenarioInventory $table[0..27]))
        $table[1].ScenarioId='SC-32';True (-not (Test-PfcContinuousScenarioInventory $table))
        $table=@(Get-PfcContinuousModeScenarios);$table[0].Negative=@();True (-not (Test-PfcContinuousScenarioInventory $table))
        $aggregate=@(32..60|ForEach-Object {New-PfcResult -ScenarioId ('SC-'+$_) -Status PASS})
        True (Test-PfcContinuousScenarioInventory $aggregate -Results)
        foreach ($bad in @($null,'','REPORTED_ONLY','N/A','UNKNOWN')) {$aggregate[0].Status=$bad;True (-not (Test-PfcContinuousScenarioInventory $aggregate -Results))}
    }
    Check 'scenario.failed-subcase-is-retained' {
        # Inject a failing assertion into the loaded table, not a Phase branch.
        . (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1')
        $entry=@(Get-PfcContinuousModeScenarios)[0]
        $entry.Negative=@(@{Name='deliberate-oracle-denial-failure';Test={Assert-PfcTrue -Actual $false -ScenarioId 'SC-32.adversarial-evidence' -Expected True}})
        $r=Invoke-PfcContinuousScenarioEntry $entry
        Equal 'FAIL' $r.Status;True ($r.Message -match 'SC-32.adversarial-evidence');True ($r.Message -match 'Positive.*PASS')
    }
    Check 'scenario.static-source-contract-negatives' {
        $texts=@{}
        foreach ($pair in @(@('Scenarios','evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1'),@('Smoke','evals/scenarios/continuous-mode/WindowsSmoke/scenario.ps1'),@('Runner','evals/run-evals.ps1'),@('Tests','evals/tests/ContinuousMode.Tests.ps1'))) {$texts[$pair[0]]=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot $pair[1])}
        True (Test-PfcContinuousSourceContract -Texts $texts).Passed
        foreach ($kind in @('missing-script','duplicate-id','missing-id','negative-absent','smoke-registration','smoke-dot-source','unsafe-cleanup','unsafe-global','unsafe-model','unsafe-specialist')) {
            $bad=$texts.Clone()
            switch ($kind) {
                missing-script {$bad.Scenarios=''}
                duplicate-id {$bad.Scenarios=$bad.Scenarios.Replace("ScenarioId='SC-33'","ScenarioId='SC-32'")}
                missing-id {$bad.Scenarios=$bad.Scenarios.Replace("ScenarioId='SC-33'","ScenarioId='SC-99'")}
                negative-absent {$bad.Scenarios=$bad.Scenarios.Replace('Negative=@(', 'Missing=@(')}
                smoke-registration {$bad.Runner=$bad.Runner.Replace(",'ContinuousModeWindowsSmoke'",'')}
                smoke-dot-source {$bad.Runner += "`n. '.\evals\scenarios\continuous-mode\WindowsSmoke\scenario.ps1'"}
                unsafe-cleanup {$bad.Scenarios=$bad.Scenarios.Replace('Remove-Item -LiteralPath $root -Recurse -Force','Remove-Item -Path $root -Recurse -Force')}
                unsafe-global {$bad.Smoke += "`ngit config --global user.name unsafe"}
                unsafe-model {$bad.Smoke += "`ncodex exec unsafe"}
                unsafe-specialist {$bad.Smoke += "`nInvoke-PfcSpecialistSmoke"}
            }
            Assert-PfcTrue -Actual (-not (Test-PfcContinuousSourceContract -Texts $bad).Passed) -ScenarioId ('static-negative.'+$kind) -Expected rejected
        }
        # Prove StaticPackage reads its target tree rather than this module's root.
        . (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1')
        $box=New-CmScenarioSandbox
        try {
            $target=Join-Path $box.Repo 'evals/scenarios/continuous-mode';[void](New-Item -ItemType Directory -Path $target -Force)
            [IO.File]::WriteAllText((Join-Path $target 'ContinuousMode.Scenarios.ps1'),$texts.Scenarios)
            $r=@(Invoke-PfcStaticChecks -RepositoryRoot (Get-Item -LiteralPath $box.Repo) -Phase GREEN | Where-Object ScenarioId -eq 'package.continuous.source-contract');Equal 1 $r.Count;Equal 'FAIL' $r[0].Status
        } finally {Remove-CmScenarioSandbox $box}
    }
    Check 'scenario.cleanup-boundary-pure-cases' {
        . (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1')
        $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/');$name='pfc-continuous-smoke-'+('a'*32);$root=Join-Path $temp $name
        True (Test-CmFixtureBoundary $root $temp 'pfc-continuous-smoke-')
        foreach ($bad in @($temp,(Join-Path $temp 'pfc-continuous-smoke-fixed'),(Join-Path $root 'child'),(Join-Path $temp ('..\'+$name)),($root+'-extra'))) {True (-not (Test-CmFixtureBoundary $bad $temp 'pfc-continuous-smoke-'))}
        True (-not (Test-CmFixtureBoundary $root $temp 'pfc-continuous-smoke-' @(@{FullName=$root;Attributes=[IO.FileAttributes]::ReparsePoint})))
        True (-not (Test-CmFixtureBoundary $root $temp 'pfc-continuous-smoke-' @(@{FullName=$root+'-escape';Attributes=[IO.FileAttributes]::Directory})))
    }
    foreach ($result in @(Invoke-PfcContinuousRevisionChecks -RepositoryRoot $RepositoryRoot)) { $results.Add($result) }
    return $results.ToArray()
}

function Test-PfcContinuousScenarioInventory {
    param([object[]]$Items, [switch]$Results)
    $expected = @(32..60 | ForEach-Object { 'SC-' + $_ })
    if ($Items.Count -ne $expected.Count) { return $false }
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($null -eq $Items[$i] -or $Items[$i].ScenarioId -cne $expected[$i]) { return $false }
        if ($Results) {
            if (@('PASS','FAIL','PARTIAL','NOT_RUN') -cnotcontains $Items[$i].Status) { return $false }
        } else {
            foreach ($kind in @('Positive','Negative')) {
                if (@($Items[$i].$kind).Count -eq 0) { return $false }
                foreach ($case in @($Items[$i].$kind)) {
                    if ([string]::IsNullOrWhiteSpace($case.Name) -or $case.Test -isnot [scriptblock]) { return $false }
                }
            }
        }
    }
    return $true
}

function Invoke-PfcContinuousScenarioTests {
    param([string]$RepositoryRoot)
    $expected = @(32..60 | ForEach-Object { 'SC-' + $_ })
    $scenarioPath = Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1'
    $inventoryError = 'Missing scenario implementation'
    $table = @()
    if (Test-Path -LiteralPath $scenarioPath -PathType Leaf) {
        try {
            . $scenarioPath
            $table = @(Get-PfcContinuousModeScenarios)
            if (Test-PfcContinuousScenarioInventory -Items $table) { $inventoryError = '' }
            else { $inventoryError = 'Invalid scenario inventory: exact ordered IDs and positive/negative cases required' }
        } catch { $inventoryError = 'Scenario load failed: ' + $_.Exception.Message }
    }
    $aggregates = @(foreach ($id in $expected) {
        if ($inventoryError) { New-PfcResult -ScenarioId $id -Status FAIL -Message ($id + ': ' + $inventoryError); continue }
        $entry = @($table | Where-Object { $_.ScenarioId -ceq $id })[0]
        Invoke-PfcContinuousScenarioEntry $entry
    })
    if (-not (Test-PfcContinuousScenarioInventory -Items $aggregates -Results)) { throw 'Invalid scenario aggregates' }
    return $aggregates
}

function Invoke-PfcContinuousScenarioEntry {
    param($Entry)
    $evidence = New-Object 'System.Collections.Generic.List[string]'
    $failed = $false
    foreach ($kind in @('Positive','Negative')) {
        foreach ($case in @($Entry.$kind)) {
            $subcaseId = $Entry.ScenarioId + '.' + $kind + '.' + $case.Name
            try { & $case.Test $evidence | Out-Null; $evidence.Add($subcaseId + ': PASS') }
            catch { $failed = $true; $evidence.Add($subcaseId + ': FAIL: ' + $_.Exception.Message) }
        }
    }
    $status = if ($failed) { 'FAIL' } else { 'PASS' }
    New-PfcResult -ScenarioId $Entry.ScenarioId -Status $status -Message ($evidence -join '; ')
}

function Invoke-PfcContinuousRevisionChecks {
    param([string]$RepositoryRoot)
    $results=New-Object 'System.Collections.Generic.List[object]'
    function Check([string]$Id,[scriptblock]$Test) {
        try {$details=@(& $Test);$results.Add((New-PfcResult -ScenarioId ('continuous.fix.'+$Id) -Status PASS -Message ('verified; '+($details -join '; '))))}
        catch {$results.Add((New-PfcResult -ScenarioId ('continuous.fix.'+$Id) -Status FAIL -Message $_.Exception.Message))}
    }
    . (Get-PfcContinuousFixtureSetup)
    . (Join-Path $RepositoryRoot 'evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1')
    $texts=@{}
    foreach($pair in @(@('Scenarios','evals/scenarios/continuous-mode/ContinuousMode.Scenarios.ps1'),@('Smoke','evals/scenarios/continuous-mode/WindowsSmoke/scenario.ps1'),@('Runner','evals/run-evals.ps1'),@('Tests','evals/tests/ContinuousMode.Tests.ps1'))) {$texts[$pair[0]]=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot $pair[1])}
    Check 'git-environment-cross-root' {
        function GlobalConfigDigest {
            $values=@(& git --no-pager config --global --null --get-regexp '.');$code=$LASTEXITCODE
            True ($code -in @(0,1));$sha=[Security.Cryptography.SHA256]::Create()
            try {$digest=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($values -join "`n")))).Replace('-','')} finally {$sha.Dispose()}
            return ([string]$code+':'+$digest)
        }
        $globalBefore=GlobalConfigDigest;$sourceBox=New-CmScenarioSandbox;$targetBox=New-CmScenarioSandbox
        $saved=@{};foreach($name in @('GIT_DIR','GIT_WORK_TREE')) {$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
        try {
            Initialize-CmFixtureGit $sourceBox;Initialize-CmFixtureGit $targetBox
            True ($sourceBox.Root -cne $targetBox.Root)
            $before=@(foreach($box in @($sourceBox,$targetBox)) {@{Config=(Get-FileHash -LiteralPath (Join-Path $box.Repo '.git/config') -Algorithm SHA256).Hash;Head=(Invoke-CmFixtureGit $box @('rev-parse','HEAD'))}})
            $rejected=0
            try {
                [Environment]::SetEnvironmentVariable('GIT_DIR',(Join-Path $targetBox.Repo '.git'),'Process')
                [Environment]::SetEnvironmentVariable('GIT_WORK_TREE',$targetBox.Repo,'Process')
                foreach($argsList in @(@('init','--quiet'),@('config','--local','user.name','fixture redirect probe'),@('add','--','src/a.ps1'),@('commit','--quiet','--allow-empty','-m','fixture redirect probe'))) {
                    try {[void](Invoke-CmFixtureGit $sourceBox $argsList)} catch {if($_.Exception.Message -ceq 'INHERITED_GIT_ENVIRONMENT') {$rejected++}}
                }
            } finally {foreach($name in $saved.Keys) {[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
            Equal 4 $rejected
            $i=0;foreach($box in @($sourceBox,$targetBox)) {Equal $before[$i].Config (Get-FileHash -LiteralPath (Join-Path $box.Repo '.git/config') -Algorithm SHA256).Hash;Equal $before[$i].Head (Invoke-CmFixtureGit $box @('rev-parse','HEAD'));$i++}
            foreach($name in @('GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_CONFIG','GIT_CONFIG_GLOBAL','GIT_CONFIG_SYSTEM','GIT_CONFIG_PARAMETERS','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_TEMPLATE_DIR','GIT_EXEC_PATH','GIT_CEILING_DIRECTORIES','GIT_DISCOVERY_ACROSS_FILESYSTEM','GIT_CONFIG_NOSYSTEM')) {
                $prior=[Environment]::GetEnvironmentVariable($name,'Process');$reason=''
                try {[Environment]::SetEnvironmentVariable($name,'fixture-probe','Process');try {[void](Invoke-CmFixtureGit $sourceBox @('config','--local','--list'))} catch {$reason=$_.Exception.Message}}
                finally {[Environment]::SetEnvironmentVariable($name,$prior,'Process')}
                Equal 'INHERITED_GIT_ENVIRONMENT' $reason
            }
            'separate fixture roots; init/config/add/commit rejected=4; both local config hashes and HEADs unchanged; 16 additional Git environment keys rejected'
            'global config digest before/after='+$globalBefore
        } finally {
            foreach($name in $saved.Keys) {[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
            Remove-CmScenarioSandbox $targetBox;Remove-CmScenarioSandbox $sourceBox
            Equal $globalBefore (GlobalConfigDigest)
        }
    }
    foreach($kind in @('direct-parent','early-success','cleanup-rebind','git-push','installer-home','installer-state','dispatch-call','dispatch-phase','dispatch-root')) {
        Check ('source-'+$kind) {
            $bad=$texts.Clone()
            switch($kind) {
                direct-parent {$bad.Scenarios=$bad.Scenarios.Replace('if (-not [StringComparer]::OrdinalIgnoreCase.Equals((Split-Path -Parent $full), $temp)) { return $false }','')}
                early-success {$bad.Scenarios=$bad.Scenarios.Replace('$temp = [IO.Path]::GetFullPath($TempRoot)', 'return $true; $temp = [IO.Path]::GetFullPath($TempRoot)')}
                cleanup-rebind {$bad.Scenarios=$bad.Scenarios.Replace('Remove-Item -LiteralPath $root -Recurse -Force', '$root = ''C:\Users\Public''; Remove-Item -LiteralPath $root -Recurse -Force')}
                git-push {$bad.Scenarios=$bad.Scenarios.Replace("@('init','config','add','commit','rev-parse','rev-list','diff-tree','diff','merge-base','status','worktree')", "@('init','config','add','commit','rev-parse','rev-list','diff-tree','diff','merge-base','status','worktree','push')")}
                installer-home {$bad.Smoke=$bad.Smoke.Replace('-UserHome $box.Home', '-UserHome ''C:\Users\Public''')}
                installer-state {$bad.Smoke=$bad.Smoke.Replace('-StateRoot $installState', '-StateRoot ''C:\Users\Public''')}
                dispatch-call {$bad.Runner=$bad.Runner.Replace("& (Join-Path `$PSScriptRoot 'scenarios\continuous-mode\WindowsSmoke\scenario.ps1') -Phase `$Phase -RepositoryRoot (Split-Path -Parent `$PSScriptRoot)","(Join-Path `$PSScriptRoot 'scenarios\continuous-mode\WindowsSmoke\scenario.ps1')")}
                dispatch-phase {$bad.Runner=$bad.Runner.Replace("scenario.ps1') -Phase `$Phase -RepositoryRoot", "scenario.ps1') -RepositoryRoot")}
                dispatch-root {$bad.Runner=$bad.Runner.Replace("scenario.ps1') -Phase `$Phase -RepositoryRoot (Split-Path -Parent `$PSScriptRoot)", "scenario.ps1') -Phase `$Phase")}
            }
            True (($bad.Scenarios -cne $texts.Scenarios) -or ($bad.Smoke -cne $texts.Smoke) -or ($bad.Runner -cne $texts.Runner))
            $contract=Test-PfcContinuousSourceContract $bad;True (-not $contract.Passed)
            'mutation hit; rejected: '+($contract.Missing -join ',')
        }
    }
    Check 'smoke-result-contract' {
        $ids=@('activation-default','worktree-identity','resume-lease','prewrite-prereview','low-wave','pause-recovery','installer-update-rollback','no-remote-mutation')
        $rows=@($ids|ForEach-Object {New-PfcResult -ScenarioId ('windows.'+$_) -Status PASS})
        True (Test-PfcContinuousSmokeResults $rows)
        True (-not (Test-PfcContinuousSmokeResults @()))
        True (-not (Test-PfcContinuousSmokeResults $rows[0..6]))
        $rows[1].ScenarioId=$rows[0].ScenarioId;True (-not (Test-PfcContinuousSmokeResults $rows));$rows[1].ScenarioId='windows.'+$ids[1]
        foreach($status in @($null,'','UNKNOWN','REPORTED_ONLY')) {$rows[0].Status=$status;True (-not (Test-PfcContinuousSmokeResults $rows))}
        foreach($status in @('PASS','FAIL','PARTIAL','NOT_RUN')) {$rows[0].Status=$status;True (Test-PfcContinuousSmokeResults $rows)}
        'eight exact unique proof IDs; empty/missing/duplicate/invalid statuses rejected; four normalized statuses recognized'
    }
    Check 'sc39-validation-mutant' {
        $source=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'evals/lib/ContinuousMode.psm1')
        $guard='Assert-CmValidation $Context.validation_plan $risk.required_milestone_tiers $true $Context.candidate_sha $Context.validation_observations'
        Equal 1 ([regex]::Matches($source,[regex]::Escape($guard))).Count
        $changed=$source.Replace($guard,'');True ($changed -cne $source)
        $mutant=New-Module -Name PfcTask8ValidationMutant -ScriptBlock ([scriptblock]::Create($changed))
        function Test-PfcContinuousTransition {param($AuthorizationStatus,$ExecutionState,$Event,$Context) & $mutant {param($p) Test-PfcContinuousTransition @p} $PSBoundParameters}
        $entry=@(Get-PfcContinuousModeScenarios|Where-Object ScenarioId -ceq 'SC-39')[0]
        $result=Invoke-PfcContinuousScenarioEntry $entry
        Equal 'FAIL' $result.Status
        foreach($tier in @('T4','FAULT_INJECTION','USER_GATE')) {True ($result.Message -match ([regex]::Escape($tier)+'.*FAIL'))}
        'memory-only validation mutant: '+$result.Message
    }
    Check 'sc36-valid-array-path-mismatch' {
        $originalOracle=Get-Command Invoke-CmScenarioOracle;$checked=New-Object 'System.Collections.Generic.List[string]'
        function Invoke-CmScenarioOracle {
            param([string]$Name,[hashtable]$Inputs)
            $result=& $originalOracle @PSBoundParameters
            if($Name -ceq 'Test-PfcPreWriteIdentityGate') {
                foreach($property in @('writable_paths','forbidden_paths')) {
                    if(@($Inputs.Observed.$property) -ccontains 'other/path') {True ($Inputs.Observed.$property -is [array]);True ($result.reasons -ccontains 'PATH_SET_MISMATCH');True ($result.reasons -cnotcontains 'MALFORMED_INPUT');$checked.Add($property+':'+$Inputs.Observed.$property.GetType().FullName+':'+($result.reasons -join ','))}
                }
            }
            return $result
        }
        $entry=@(Get-PfcContinuousModeScenarios|Where-Object ScenarioId -ceq 'SC-36')[0]
        Equal 'PASS' (Invoke-PfcContinuousScenarioEntry $entry).Status;Equal 2 $checked.Count
        $checked -join '; '
    }
    Check 'smoke-distinct-update-proof' {
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($texts.Smoke,[ref]$tokens,[ref]$errors)
        $proof=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-CmSmokeInstallerProof'},$true))
        Equal 1 $proof.Count
        $marker='[IO.File]::WriteAllBytes($managedSource,$secondBytes)'
        $bad=$texts.Clone();$bad.Smoke=$bad.Smoke.Replace($marker,'');True ($bad.Smoke -cne $texts.Smoke)
        True (-not (Test-PfcContinuousSourceContract $bad).Passed)
    }
    Check 'boundary-other-parent' {
        True (-not (Test-CmFixtureBoundary 'F:\outside-fixture-root\pfc-continuous-case-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'C:\fixture-temp' 'pfc-continuous-case-'))
    }
    return $results.ToArray()
}

function Get-PfcContinuousFixtureSetup {
    return {
    function Equal($Expected, $Actual) { Assert-PfcEqual -Expected $Expected -Actual $Actual -ScenarioId continuous }
    function True($Actual) { Assert-PfcTrue -Actual ([bool]$Actual) -ScenarioId continuous -Expected True }
    function Present($Value) { True ($null -ne $Value) }
    function Reject([scriptblock]$Action) { $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; True $threw }
    function Clone-CmFixture($Value) { $Value | ConvertTo-Json -Depth 70 | ConvertFrom-Json }
    function Change($Value, [string]$Path, $Replacement) {
        $parts = $Path.Split('.'); $target = $Value
        for ($i=0; $i -lt $parts.Length-1; $i++) { $target = $target.($parts[$i]) }
        $target.($parts[-1]) = $Replacement
    }
    $a = 'a' * 40; $b = 'b' * 40; $c = 'c' * 40; $d = 'd' * 40
    $repo = 'df4eba3a1be335d69dff72e974ba9c0a274fc927eccef630cba6d5d64f1cad69'
    $wt = '9812d24ddbb0833fc6b44fe481e6e3e3f08b7ba0c988a3df8f8732ba30ad110e'
    $controls = @('docs/project-control/status.md','docs/project-control/acceptance.md')
    $limits = @{ max_wave_size=5; max_builder_code_repair_attempts=2; max_auto_rework_rounds=2; max_candidate_revisions=3; max_consecutive_blocked_milestones=1 }
    function Plan([string[]]$Tiers=@('T1','T2'), [string]$Sha=$c, [string]$Result='NOT_RUN') {
        @($Tiers | ForEach-Object { @{ tier=$_; required=$true; applicability_reason='required by approved contract'; checks=@('observed command'); result=$Result; evidence=@(@{evidence_id=('E-'+$_);candidate_sha=$Sha;reference='evidence/reference'}) } })
    }
    function WriteFixture {
        $projection = @{ authorization_id='AUTH-1'; authorization_status='ACTIVE'; goal_id='GOAL-1'; goal_version=1; milestone_id='M-1'; contract_id='CONTRACT-1'; contract_version=1; work_order_id='ORDER-1'; control_run_id='RUN-1'; lease_epoch=1; wave_id='WAVE-1'; repository_identity=$repo; identity_algorithm='PFC_GIT_COMMON_DIR_SHA256_V1'; worktree_identity=$wt; worktree_identity_algorithm='PFC_WORKTREE_ROOT_SHA256_V1'; exact_branch='codex/pfc/AUTH-1/m-1'; authorized_base_checkpoint_sha=$a; previous_accepted_checkpoint_sha='FIRST_MILESTONE'; current_milestone_base_sha=$a; expected_builder_start_sha=$a; hash_algorithm='PFC_REPO_PATH_SET_SHA256_V1'; writable_paths_hash='fc4628eaecd7833573e6a1bcde6f0580c80e154b6cb5649f0c46fb89a2204c15'; forbidden_paths_hash='b9258d4fdf8f9159dcb296e1bfebb7dcf3be16e0831f87f78689d6f47c1c5095'; risk_level='LOW'; validation_plan=@(Plan); scope=@{type='MILESTONE_RANGE';from='M-1';to='M-2';stop_gate='GATE-1'} }
        $auth = @{authorization_id='AUTH-1';authorization_status='ACTIVE';execution_policy='CONTINUOUS';invocation_mode='START';goal=@{goal_id='GOAL-1';goal_version=1};scope=$projection.scope;repository=@{identity_algorithm=$projection.identity_algorithm;repository_identity=$repo;authorized_base_checkpoint_sha=$a;source_branch='main';write_branch_policy='MILESTONE_WORKTREE_ONLY';write_branch_namespace='codex/pfc/AUTH-1/';default_branch_write=$false}; paths=@{hash_algorithm=$projection.hash_algorithm;writable_paths_hash=$projection.writable_paths_hash;forbidden_paths_hash=$projection.forbidden_paths_hash};limits=$limits;approval=@{approved_by='USER';source_decision_id='DEC-1'}}
        $entry = @{milestone_id='M-1';contract_id='CONTRACT-1';contract_version=1;risk_level='LOW';dependencies=@();exact_branch=$projection.exact_branch;worktree_identity_algorithm=$projection.worktree_identity_algorithm;worktree_identity=$wt;validation_plan=$projection.validation_plan}
        $checkpoint = @{authorization_id='AUTH-1';control_run_id='RUN-1';lease_epoch=1;wave_id='WAVE-1';milestone_id='M-1';previous_accepted_checkpoint_sha='FIRST_MILESTONE';current_milestone_base_sha=$a;expected_builder_start_sha=$a;repair_budget=@{builder_code_repair_attempts=0;auto_rework_rounds=0;candidate_revisions=0};recovery_manifest=@{recovery_package_reference='RECOVERY-1';git_status=@();files=@();allowed_paths=@('src/a.ps1')}}
        $observed = @{is_git_repository=$true;repository_identity=$repo;identity_algorithm=$projection.identity_algorithm;worktree_identity=$wt;worktree_identity_algorithm=$projection.worktree_identity_algorithm;exact_branch=$projection.exact_branch;default_branch='main';actual_worktree_head=$a;active_plan_milestone_id='M-1';roadmap_ids=@('M-1','M-2');accepted_milestone_ids=@();registered_worktrees=@(@{milestone_id='M-1';worktree_identity=$wt;exact_branch=$projection.exact_branch});approval=@{authorization_id='AUTH-1';source_decision_id='DEC-1';approved_by='USER';observed=$true};ancestry=@(@{ancestor_sha=$a;descendant_sha=$a;proven=$true});diffs=@();candidate_sha='NONE';git_status=@();files=@();git_operation_in_progress=$false;unknown_active_session=$false;invalidation_reasons=@();risk_factors=@();medium_validation='NONE';writable_paths=@('src/a.ps1');forbidden_paths=@('secrets');canonical_control_paths=$controls;governance_head_sha=$a}
        $echo = Clone-CmFixture $projection; $echo | Add-Member NoteProperty actual_worktree_head $a
        @{Authorization=(Clone-CmFixture $auth);WavePlan=(Clone-CmFixture @{wave_id='WAVE-1';authorization_id='AUTH-1';goal_id='GOAL-1';stop_gate='GATE-1';base_checkpoint_sha=$a;milestones=@($entry);wave_validation=@(Plan @('T3'))[0]});MilestoneContract=(Clone-CmFixture $projection);WorkOrder=(Clone-CmFixture $projection);BuilderEcho=$echo;Checkpoint=(Clone-CmFixture $checkpoint);Observed=(Clone-CmFixture $observed);CanonicalSources=(Clone-CmFixture @{authorization_sources=@(@{path='docs/project-control/auth.yaml';authorization_id='AUTH-1';equivalent=$true;registered=$true});wave_sources=@(@{path='docs/project-control/wave.yaml';wave_id='WAVE-1';equivalent=$true;registered=$true})});ControlPathAllowlist=$controls}
    }
    function ReviewFixture {
        $w = WriteFixture
        $review = Clone-CmFixture $w.WorkOrder
        foreach ($p in @{verify_order_id='VERIFY-1';base_sha=$a;candidate_sha=$c;builder_evidence_sha=$c;builder_evidence_ids=@('E-1');wave_impact_checks=@(@{wave_id='WAVE-1';milestone_id='M-1';candidate_sha=$c;paths=@('src/a.ps1');dependencies=@();required=$true});wave_impact=@{wave_id='WAVE-1';milestone_id='M-1';candidate_sha=$c;paths=@('src/a.ps1');dependencies=@();result='PASS'};acceptance_record_target='ACCEPT-1';changed_files=@('src/a.ps1');validation_tier=@('T1','T2')}.GetEnumerator()) { $review | Add-Member NoteProperty $p.Key $p.Value }
        @{Authorization=$w.Authorization;MilestoneContract=$w.MilestoneContract;WorkOrder=$w.WorkOrder;VerifyOrder=$review;BuilderReport=(Clone-CmFixture $review);Candidate=(Clone-CmFixture $review);WavePlan=$w.WavePlan;PathPolicy=@{writable_paths=@('src/a.ps1');forbidden_paths=@('secrets');writable_paths_hash=$w.WorkOrder.writable_paths_hash;forbidden_paths_hash=$w.WorkOrder.forbidden_paths_hash;hash_algorithm='PFC_REPO_PATH_SET_SHA256_V1'};Observed=@{ancestry=@(@{ancestor_sha=$a;descendant_sha=$c;proven=$true});candidate_sha=$c;actual_head_sha=$c;repository_identity=$repo;verify_order_id='VERIFY-1';acceptance_record_target='ACCEPT-1';diff=@{from_sha=$a;to_sha=$c;observed=$true;changed_paths=@('src/a.ps1');commits=@(@{commit_sha=$c;parent_shas=@($a);changed_paths=@('src/a.ps1')})};builder_evidence=@(@{evidence_id='E-1';candidate_sha=$c;work_order_id='ORDER-1';observed=$true;fresh=$true;reference='evidence/build'});tracked_mutations=@();staged_mutations=@();risk_factors=@();medium_validation='NONE'}}
    }
    function RepairFixture {
        @{RepairBudget=@{builder_code_repair_attempts=0;auto_rework_rounds=0;candidate_revisions=1};PreviousBudget=@{builder_code_repair_attempts=0;auto_rework_rounds=0;candidate_revisions=1};Limits=$limits;RequestedAction='START_BUILDER_REPAIR';CandidateFrozen=$true;ChangedTrackedPaths=@();ControlPathAllowlist=$controls;FailureHistory=@{root_cause_confirmed=$true;root_cause='identified fault';same_core_failure_rounds=0;rounds_without_new_pass=0;data_corruption=$false;permission_bypass=$false;contract_change_required=$false;scope_change_required=$false};Convergence='IMPROVING';CandidateResult='FAIL'}
    }
    function TransitionFixture {
        $w = WriteFixture
        @{AuthorizationStatus='ACTIVE';ExecutionState='ACTIVE';Event='NEXT_MILESTONE';Context=@{explicit_continuous=$true;invocation_mode='RESUME';authorization_id='AUTH-1';source_decision_id='DEC-1';approved_by='USER';approval=@{observed=$true;authorization_id='AUTH-1';source_decision_id='DEC-1';approved_by='USER'};readiness='READY_FOR_CONTINUOUS_EXECUTION';invalidation_reasons=@();stop_reason='NONE';is_git_repository=$true;git_operation_in_progress=$false;unknown_active_session=$false;unknown_dirty=$false;governance_head_sha=$b;actual_head_sha=$b;preconditions=@();next_risk_level='LOW';current_work_order_id='ORDER-1';next_work_order_id='ORDER-2';current_builder_start_sha=$a;next_base_sha=$b;current_pre_write_gate=@{result='PRE_WRITE_IDENTITY_GATE_PASS';can_issue_builder_lease=$true;authorization_id='AUTH-1';milestone_id='M-1';expected_builder_start_sha=$a;work_order_id='ORDER-1'};pre_write_gate=@{result='PRE_WRITE_IDENTITY_GATE_PASS';can_issue_builder_lease=$true;authorization_id='AUTH-1';milestone_id='M-2';expected_builder_start_sha=$b;work_order_id='ORDER-2';control_run_id='RUN-2';lease_epoch=2};pre_review_gate=@{result='PRE_REVIEW_IDENTITY_GATE_PASS';can_start_review=$true;authorization_id='AUTH-1';milestone_id='M-1';candidate_sha=$c;work_order_id='ORDER-1'};milestone_state='ACCEPTED';milestone_id='M-1';next_milestone_id='M-2';candidate_sha=$c;evidence_sha=$c;acceptance_sha=$c;accepted_checkpoint_sha=$b;control_paths=$controls;ancestry=@(@{ancestor_sha=$c;descendant_sha=$b;proven=$true});diffs=@(@{from_sha=$c;to_sha=$b;observed=$true;changed_paths=@('docs/project-control/acceptance.md');commits=@(@{commit_sha=$b;parent_shas=@($c);changed_paths=@('docs/project-control/acceptance.md')})});validation_plan=@(Plan @('T1','T2') $c 'PASS');validation_observations=@(@{evidence_id='E-T1';candidate_sha=$c;reference='evidence/reference';observed=$true;fresh=$true},@{evidence_id='E-T2';candidate_sha=$c;reference='evidence/reference';observed=$true;fresh=$true},@{evidence_id='E-T3';candidate_sha=$b;reference='evidence/reference';observed=$true;fresh=$true});independent_review=@{candidate_sha=$c;observed=$true;fresh=$true;result='PASS'};findings=@();changes=@();risk_level='LOW';irreversible_pending=$false;essential_specialist_active=$false;convergence='IMPROVING';frozen_wave=@{wave_id='WAVE-1';authorization_id='AUTH-1';milestone_ids=@('M-1','M-2');dependencies=@()};accepted_milestone_ids=@('M-1');wave_id='WAVE-1';wave_t3=@(Plan @('T3') $b 'PASS')[0];wave_verifier=@{candidate_sha=$b;observed=$true;fresh=$true;result='PASS'};wave_persistence=@{observed=$true;wave_id='WAVE-1';final_checkpoint_sha=$b;summary_reference='wave/report';control_commit_sha=$b};wave_milestones=@(@{milestone_id='M-1';candidate_sha=$c;evidence_sha=$c;acceptance_sha=$c;accepted_checkpoint_sha=$b;result='PASS'});stop_gate_reached=$false;scope_exhausted=$false;authorization_rechecked=$true;contract_rechecked=$true;known_limitations_rechecked=$true;hard_stop_rechecked=$true;user_resume=@{approved_by='USER';authorization_id='AUTH-1';observed=$true};runtime=@{previous_control_run_id='RUN-1';previous_lease_epoch=1;control_run_id='RUN-2';lease_epoch=2}}}
    }
    }
}
