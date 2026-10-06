Set-StrictMode -Version 2.0

# Pure snapshot evaluators. Observed facts are supplied by the caller; these
# functions never discover facts, issue leases, run actions, or mutate records.
function Assert-Cm($Condition, [string]$Reason='MALFORMED_INPUT') {
    if ($Condition -isnot [bool] -or -not $Condition) { throw [ArgumentException]::new($Reason) }
}
function Test-CmText($Value) { return ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '[\x00-\x1f\x7f]') }
# PowerShell's case-sensitive string operators are linguistic, not ordinal.
# Both operands must be real nonblank strings before any identity comparison.
function Test-CmEqual($Left, $Right) {
    return ((Test-CmText $Left) -and (Test-CmText $Right) -and [StringComparer]::Ordinal.Equals($Left,$Right))
}
function Test-CmContains($Values, $Value) {
    if ($Values -isnot [Array] -or -not (Test-CmText $Value)) { return $false }
    foreach ($item in $Values) { if (-not (Test-CmText $item)) { return $false } }
    foreach ($item in $Values) { if ([StringComparer]::Ordinal.Equals($item,$Value)) { return $true } }
    return $false
}
function Get-CmOrdinalIndex($Values, $Value) {
    if (-not (Test-CmContains $Values $Value)) { return -1 }
    for ($i=0; $i -lt $Values.Count; $i++) { if ([StringComparer]::Ordinal.Equals($Values[$i],$Value)) { return $i } }
    return -1
}
function Test-CmUnique($Values) {
    if ($Values -isnot [Array]) { return $false }
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($value in $Values) { if (-not (Test-CmText $value) -or -not $seen.Add($value)) { return $false } }
    return $true
}
function Test-CmInteger($Value) { return ($Value -is [int] -or $Value -is [long]) }
function Test-CmSha($Value) { return ($Value -is [string] -and $Value -cmatch '\A[0-9a-f]{40}\z' -and (-not (Test-CmEqual ($Value) (('0'*40))))) }
function Test-CmHash($Value) { return ($Value -is [string] -and $Value -cmatch '\A[0-9a-f]{64}\z' -and (-not (Test-CmEqual ($Value) (('0'*64))))) }
function Test-CmId($Value) { return ($Value -is [string] -and $Value -cmatch '\A[A-Z0-9]+(?:-[A-Z0-9]+)*\z') }
function Assert-CmArray($Value) { Assert-Cm ($Value -is [Array]) }
function Assert-CmBool($Value, [bool]$Expected) { Assert-Cm ($Value -is [bool] -and $Value -eq $Expected) }
function Get-CmField($Record, [string]$Name) {
    Assert-Cm ($null -ne $Record)
    if ($Record -is [Collections.IDictionary]) {
        Assert-Cm ((Test-CmContains (@($Record.Keys)) ($Name)))
        return ,$Record[$Name]
    }
    Assert-Cm ($Record -is [pscustomobject] -and (Test-CmContains (@($Record.PSObject.Properties.Name)) ($Name)))
    return ,$Record.$Name
}
function Test-CmSame($Left, $Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    if ($Left -is [Array]) {
        if ($Right -isnot [Array] -or $Left.Count -ne $Right.Count) { return $false }
        for ($i=0; $i -lt $Left.Count; $i++) { if (-not (Test-CmSame $Left[$i] $Right[$i])) { return $false } }
        return $true
    }
    if ($Left -is [Collections.IDictionary] -or $Left -is [pscustomobject]) {
        if ($Right -isnot [Collections.IDictionary] -and $Right -isnot [pscustomobject]) { return $false }
        $keys=if ($Left -is [Collections.IDictionary]) { @($Left.Keys) } else { @($Left.PSObject.Properties.Name) }
        $other=if ($Right -is [Collections.IDictionary]) { @($Right.Keys) } else { @($Right.PSObject.Properties.Name) }
        if ($keys.Count -ne $other.Count) { return $false }
        foreach ($key in $keys) { if ((-not (Test-CmContains ($other) ($key))) -or -not (Test-CmSame (Get-CmField $Left $key) (Get-CmField $Right $key))) { return $false } }
        return $true
    }
    if ((Test-CmInteger $Left) -and (Test-CmInteger $Right)) { return ($Left -eq $Right) }
    if ($Left -is [string]) { return (Test-CmEqual $Left $Right) }
    return ($Left -is [bool] -and $Right -is [bool] -and $Left -eq $Right)
}
function Assert-CmFields($Left, $Right, [string[]]$Names, [string]$Reason='IDENTITY_MISMATCH') {
    foreach ($name in $Names) {
        $value=Get-CmField $Left $name
        Assert-Cm ($null -ne $value -and (Test-CmSame $value (Get-CmField $Right $name))) $Reason
    }
}
function Get-CmReason($ErrorRecord) {
    $reason=$ErrorRecord.Exception.Message
    if ($reason -cmatch '\A[A-Z][A-Z0-9_]+\z') { return $reason }
    return 'MALFORMED_INPUT'
}
function Get-CmHash([string]$Payload) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash(([Text.UTF8Encoding]::new($false,$true)).GetBytes($Payload))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Assert-CmPathSegment([string]$Segment) {
    Assert-Cm ($Segment.Length -gt 0 -and $Segment -notmatch '[\x00-\x1f\x7f<>:"|?*]' -and $Segment -notmatch '[ .]\z' -and $Segment -notmatch '^(?i:con|prn|aux|nul|com[1-9\u00b9\u00b2\u00b3]|lpt[1-9\u00b9\u00b2\u00b3])(?:\.|\z)') 'INVALID_PATH'
}
function ConvertTo-CmAbsolutePath($Path) {
    Assert-Cm (Test-CmText $Path) 'INVALID_PATH'
    $p=$Path.Replace('\','/').ToLowerInvariant()
    Assert-Cm ($p -cmatch '\A(?:[a-z]:/|//[^/]+/[^/]+(?:/|\z))' -and $p -notmatch '\A//[?.]/') 'ABSOLUTE_PATH_REQUIRED'
    $p=$p.TrimEnd('/')
    Assert-Cm ($p.Substring(2).IndexOf('//',[StringComparison]::Ordinal) -lt 0) 'INVALID_PATH'
    $segments=if ($p -cmatch '\A[a-z]:') { @($p.Substring(2).TrimStart('/').Split('/')) } else { @($p.Substring(2).Split('/')) }
    if ($p -cnotmatch '\A[a-z]:\z') {
        foreach ($segment in $segments) { Assert-Cm ((-not (Test-CmContains (@('.','..')) ($segment)))) 'UNRESOLVED_TRAVERSAL'; Assert-CmPathSegment $segment }
    }
    return $p
}
function ConvertTo-CmRelativePath($Path) {
    Assert-Cm (Test-CmText $Path) 'INVALID_PATH'
    $p=$Path.Replace('\','/').Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
    Assert-Cm (-not $p.StartsWith('/',[StringComparison]::Ordinal) -and $p -notmatch ':') 'RELATIVE_PATH_REQUIRED'
    $parts=New-Object 'System.Collections.Generic.List[string]'
    foreach ($segment in $p.Split('/')) {
        if ((Test-CmEqual ($segment) ('.'))) { continue }
        if ((Test-CmEqual ($segment) ('..'))) { Assert-Cm ($parts.Count -gt 0) 'PATH_ESCAPE'; $parts.RemoveAt($parts.Count-1); continue }
        Assert-CmPathSegment $segment
        $parts.Add($segment)
    }
    Assert-Cm ($parts.Count -gt 0) 'INVALID_PATH'
    return [string]::Join('/', $parts.ToArray())
}
function Get-PfcRepositoryIdentityV1 {
    param($GitCommonDirAbsolutePath)
    $path=ConvertTo-CmAbsolutePath $GitCommonDirAbsolutePath
    [pscustomobject]@{identity_algorithm='PFC_GIT_COMMON_DIR_SHA256_V1';normalized_path=$path;repository_identity=(Get-CmHash ("pfc.repo.v1`n"+$path))}
}
function Get-PfcWorktreeIdentityV1 {
    param($WorktreeRootAbsolutePath)
    $path=ConvertTo-CmAbsolutePath $WorktreeRootAbsolutePath
    [pscustomobject]@{identity_algorithm='PFC_WORKTREE_ROOT_SHA256_V1';normalized_path=$path;worktree_identity=(Get-CmHash ("pfc.worktree.v1`n"+$path))}
}
function Get-PfcRepoPathSetIdentityV1 {
    param($Paths)
    Assert-CmArray $Paths
    $set=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($path in $Paths) { [void]$set.Add((ConvertTo-CmRelativePath $path)) }
    [string[]]$normalized=@($set)
    [Array]::Sort($normalized,[StringComparer]::Ordinal)
    [pscustomobject]@{hash_algorithm='PFC_REPO_PATH_SET_SHA256_V1';normalized_paths=$normalized;paths_hash=(Get-CmHash ("pfc.paths.v1`n"+[string]::Join("`n",$normalized)))}
}
function Get-CmExactPaths($Paths, [bool]$Canonical=$true) {
    $identity=Get-PfcRepoPathSetIdentityV1 $Paths
    Assert-Cm ($identity.normalized_paths.Count -eq $Paths.Count) 'DUPLICATE_PATH'
    if ($Canonical) { foreach ($path in $Paths) { Assert-Cm ((Test-CmEqual ($path) ((ConvertTo-CmRelativePath $path)))) 'NONCANONICAL_PATH' } }
    return ,$identity.normalized_paths
}
function Test-CmPathAllowed([string]$Path, $Writable, $Forbidden) {
    foreach ($entry in $Forbidden) { if ((Test-CmEqual ($Path) ($entry)) -or $Path.StartsWith($entry+'/',[StringComparison]::Ordinal)) { return $false } }
    foreach ($entry in $Writable) { if ((Test-CmEqual ($Path) ($entry)) -or $Path.StartsWith($entry+'/',[StringComparison]::Ordinal)) { return $true } }
    return $false
}
function Assert-CmAncestry($Proofs, $From, $To) {
    Assert-Cm ((Test-CmSha $From) -and (Test-CmSha $To)) 'BASELINE_DRIFT'
    Assert-CmArray $Proofs
    foreach ($proof in $Proofs) { Assert-Cm ((Test-CmSha $proof.ancestor_sha) -and (Test-CmSha $proof.descendant_sha) -and $proof.proven -is [bool]) 'BASELINE_DRIFT' }
    $matches=@($Proofs | Where-Object { (Test-CmEqual ($_.ancestor_sha) ($From)) -and (Test-CmEqual ($_.descendant_sha) ($To)) })
    Assert-Cm ($matches.Count -eq 1 -and $matches[0].proven -is [bool] -and $matches[0].proven) 'BASELINE_DRIFT'
}
function Assert-CmControlDescendant($Proofs, $Diffs, $From, $To, $Allowlist) {
    Assert-Cm ((Test-CmSha $From) -and (Test-CmSha $To)) 'VERSION_INTEGRITY_FAIL'
    $paths=Get-CmExactPaths $Allowlist
    if ((Test-CmEqual ($From) ($To))) { return }
    Assert-CmAncestry $Proofs $From $To
    Assert-CmArray $Diffs
    foreach ($diff in $Diffs) { Assert-Cm ((Test-CmSha $diff.from_sha) -and (Test-CmSha $diff.to_sha) -and $diff.observed -is [bool]) 'UNOBSERVED_DIFF' }
    $matches=@($Diffs | Where-Object { (Test-CmEqual ($_.from_sha) ($From)) -and (Test-CmEqual ($_.to_sha) ($To)) })
    Assert-Cm ($matches.Count -eq 1) 'UNOBSERVED_DIFF'
    Assert-CmBool $matches[0].observed $true
    $changes=Get-CmExactPaths $matches[0].changed_paths
    foreach ($path in $changes) { Assert-Cm ((Test-CmContains ($paths) ($path))) 'NON_CONTROL_CHANGE' }
    # Caller supplies rev-list --reverse --parents From..To plus each commit's
    # diff-tree paths. Require a complete linear chain; merges need a new Candidate.
    $commits=Get-CmField $matches[0] commits
    Assert-CmArray $commits; Assert-Cm ($commits.Count -gt 0) 'UNOBSERVED_HISTORY'
    $cursor=$From
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    [void]$seen.Add($From)
    foreach($commit in $commits) {
        Assert-Cm ((Test-CmSha $commit.commit_sha) -and $seen.Add($commit.commit_sha)) 'UNOBSERVED_HISTORY'
        Assert-CmArray $commit.parent_shas
        Assert-Cm ($commit.parent_shas.Count -eq 1 -and (Test-CmEqual $commit.parent_shas[0] $cursor)) 'UNOBSERVED_HISTORY'
        foreach($path in (Get-CmExactPaths $commit.changed_paths)) { Assert-Cm (Test-CmContains $paths $path) 'NON_CONTROL_CHANGE' }
        $cursor=$commit.commit_sha
    }
    Assert-Cm (Test-CmEqual $cursor $To) 'UNOBSERVED_HISTORY'
}
function Resolve-PfcRiskValidationPlan {
    param($BaseRisk, $RiskFactors, $MediumValidation, $AuthorizationLimits)
    $out=[ordered]@{allowed=$false;risk_level='HIGH';required_milestone_tiers=@('T1','T2','T3','T4','FAULT_INJECTION','USER_GATE');required_wave_tiers=@('T3');max_wave_size=1;requires_user_gate=$true;reasons=@()}
    try {
        Assert-Cm ($BaseRisk -is [string] -and (Test-CmContains (@('LOW','MEDIUM','HIGH')) ($BaseRisk))) 'UNKNOWN_RISK'
        Assert-CmArray $RiskFactors
        $level=Get-CmOrdinalIndex @('LOW','MEDIUM','HIGH') $BaseRisk
        $escalate=$false
        foreach ($factor in $RiskFactors) {
            Assert-Cm (Test-CmText $factor) 'UNKNOWN_RISK_FACTOR'
            switch -CaseSensitive ($factor) {
                {(Test-CmContains (@('DOCUMENTATION','STYLE','UI','READ_ONLY','CRUD_NO_SCHEMA','APPROVED_TEST_FIX')) ($_))} { }
                {(Test-CmContains (@('FILE_WRITE','IMPORT_EXPORT','NONDESTRUCTIVE_MIGRATION','SNAPSHOT','EXTERNAL_PROCESS','PLANNED_DEPENDENCY','WORKSPACE_IMPORT')) ($_))} { $level=[Math]::Max($level,1) }
                {(Test-CmContains (@('STATE_MACHINE','PERMISSIONS','AUDIT','RECOVERY_SWITCH','DELETE','CREDENTIALS','DESTRUCTIVE_MIGRATION','SCHEDULING','EXTERNAL_IRREVERSIBLE')) ($_))} { $level=2 }
                {(Test-CmContains (@('UNCERTAINTY','DATA_INTEGRITY','PERMISSION_IMPACT','RECOVERY_IMPACT','ACCEPTED_CALCULATION','WRITABLE_PATH_EXPANSION','MAJOR_DEPENDENCY','NON_REPRODUCIBLE')) ($_))} { $escalate=$true }
                default { throw [ArgumentException]::new('UNKNOWN_RISK_FACTOR') }
            }
        }
        if ($escalate) { $level=[Math]::Min(2,$level+1) }
        $cap=Get-CmField $AuthorizationLimits max_wave_size
        Assert-Cm ((Test-CmInteger $cap) -and $cap -ge 1 -and $cap -le 5) 'INVALID_LIMIT'
        $out.risk_level=@('LOW','MEDIUM','HIGH')[$level]
        $out.required_milestone_tiers=@('T1','T2')
        if ($level -eq 1) { Assert-Cm ($MediumValidation -is [string] -and (Test-CmContains (@('ROLLBACK','UPGRADE_DOWNGRADE')) ($MediumValidation))) 'MEDIUM_VALIDATION_REQUIRED'; $out.required_milestone_tiers+=,$MediumValidation }
        if ($level -eq 2) { $out.required_milestone_tiers=@('T1','T2','T3','T4','FAULT_INJECTION','USER_GATE') }
        $out.max_wave_size=[Math]::Min(@(5,3,1)[$level],$cap)
        $out.requires_user_gate=($level -eq 2)
        $out.allowed=$true
    } catch { $out.reasons=@(Get-CmReason $_) }
    [pscustomobject]$out
}
function Assert-CmValidation($Plan, $RequiredTiers, [bool]$RequirePass=$false, $Sha=$null, $Observations=$null) {
    Assert-CmArray $Plan
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($record in $Plan) {
        Assert-Cm ((Test-CmContains (@('T1','T2','T3','T4','ROLLBACK','UPGRADE_DOWNGRADE','FAULT_INJECTION','USER_GATE')) ($record.tier)) -and $seen.Add($record.tier)) 'INVALID_VALIDATION_PLAN'
        Assert-Cm ($record.required -is [bool] -and (Test-CmText $record.applicability_reason) -and (Test-CmContains (@('PASS','FAIL','PARTIAL','NOT_RUN')) ($record.result))) 'INVALID_VALIDATION_PLAN'
        Assert-CmArray $record.checks; Assert-CmArray $record.evidence
        foreach ($check in $record.checks) { Assert-Cm (Test-CmText $check) 'INVALID_VALIDATION_PLAN' }
        if ($record.required) { Assert-Cm ($record.checks.Count -gt 0) 'INVALID_VALIDATION_PLAN' }
        if ((Test-CmContains ($RequiredTiers) ($record.tier))) { Assert-Cm $record.required 'REQUIRED_TIER_WAIVED' }
        if ($RequirePass -and $record.required) {
            Assert-Cm ((Test-CmEqual ($record.result) ('PASS')) -and $record.evidence.Count -gt 0) 'REQUIRED_VALIDATION_NOT_PASS'
            Assert-CmArray $Observations
            foreach ($evidence in $record.evidence) {
                Assert-Cm ((Test-CmId $evidence.evidence_id) -and (Test-CmEqual ($evidence.candidate_sha) ($Sha)) -and (Test-CmText $evidence.reference)) 'STALE_REPORT_REJECTED'
                $matches=@($Observations | Where-Object {(Test-CmEqual ($_.evidence_id) ($evidence.evidence_id)) -and (Test-CmEqual ($_.candidate_sha) ($Sha)) -and (Test-CmEqual ($_.reference) ($evidence.reference))})
                Assert-Cm ($matches.Count -eq 1) 'STALE_REPORT_REJECTED'
                Assert-CmBool $matches[0].observed $true; Assert-CmBool $matches[0].fresh $true
            }
        }
    }
    foreach ($tier in $RequiredTiers) { Assert-Cm $seen.Contains($tier) 'REQUIRED_TIER_MISSING' }
}
function Assert-CmApproval($Authorization, $Observed) {
    Assert-Cm ((Test-CmEqual ($Authorization.authorization_status) ('ACTIVE')) -and (Test-CmEqual ($Authorization.execution_policy) ('CONTINUOUS')) -and (Test-CmContains (@('START','RESUME')) ($Authorization.invocation_mode))) 'AUTHORIZATION_INACTIVE'
    Assert-Cm ((Test-CmId $Authorization.authorization_id) -and (Test-CmId $Authorization.approval.source_decision_id) -and (Test-CmEqual ($Authorization.approval.approved_by) ('USER'))) 'INVALID_APPROVAL'
    Assert-CmBool $Observed.observed $true
    Assert-Cm ((Test-CmEqual ($Observed.authorization_id) ($Authorization.authorization_id)) -and (Test-CmEqual ($Observed.source_decision_id) ($Authorization.approval.source_decision_id)) -and (Test-CmEqual ($Observed.approved_by) ($Authorization.approval.approved_by))) 'INVALID_APPROVAL'
    foreach ($forbidden in @('control_run_id','lease_epoch','wave_id','milestone_id')) {
        $keys=if ($Authorization -is [Collections.IDictionary]) { @($Authorization.Keys) } else { @($Authorization.PSObject.Properties.Name) }
        Assert-Cm ((-not (Test-CmContains ($keys) ($forbidden)))) 'UNSTABLE_AUTHORIZATION'
    }
}
function Assert-CmRecoveryInventory($Checkpoint, $Observed, $Writable, $Forbidden) {
    try {
        Assert-CmBool $Observed.git_operation_in_progress $false; Assert-CmBool $Observed.unknown_active_session $false
        Assert-CmArray $Observed.git_status; Assert-CmArray $Observed.files
        $manifest=$Checkpoint.recovery_manifest
        Assert-CmArray $manifest.git_status; Assert-CmArray $manifest.files
        Assert-Cm (Test-CmSame $Observed.git_status $manifest.git_status)
        if ($Observed.git_status.Count -eq 0) { Assert-Cm ($Observed.files.Count -eq 0 -and $manifest.files.Count -eq 0); return }
        Assert-Cm (Test-CmId $manifest.recovery_package_reference)
        Assert-Cm ((Test-CmEqual ($Observed.recovery_package.recovery_package_reference) ($manifest.recovery_package_reference)))
        Assert-CmBool $Observed.recovery_package.outside_repository $true; Assert-CmBool $Observed.recovery_package.verified $true
        Assert-CmArray $Observed.recovery_copies
        $allowed=Get-CmExactPaths $manifest.allowed_paths
        $needed=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        [void](Get-CmExactPaths @($Observed.git_status | ForEach-Object {$_.path}))
        foreach ($status in $Observed.git_status) {
            # Porcelain XY pairs for resolved tracked/untracked paths. Unmerged
            # and ignored entries require recovery instead of write permission.
            Assert-Cm ($status.status -is [string] -and $status.status -cmatch '\A(?:\?\?|[MTARC][ MTD]| [AMTDRC]|D )\z')
            [void]$needed.Add($status.path)
            if ($status.status -cmatch '[RC]') { [void](Get-CmExactPaths @($status.original_path)); [void]$needed.Add($status.original_path) } else { Assert-Cm ((Test-CmEqual ($status.original_path) ('NONE'))) }
        }
        $paths=Get-CmExactPaths @($manifest.files | ForEach-Object {$_.path})
        Assert-Cm ($paths.Count -eq $needed.Count -and $Observed.files.Count -eq $needed.Count -and $Observed.recovery_copies.Count -eq $needed.Count)
        $copies=Get-CmExactPaths @($manifest.files | ForEach-Object {$_.recovery_copy})
        foreach ($file in $manifest.files) {
            Assert-Cm ($needed.Contains($file.path) -and (Test-CmContains ($allowed) ($file.path)) -and (Test-CmPathAllowed $file.path $Writable $Forbidden))
            Assert-Cm ((Test-CmHash $file.sha256) -and (Test-CmInteger $file.size_bytes) -and $file.size_bytes -ge 0 -and (Test-CmContains (@('ACTIVE','HISTORICAL')) ($file.classification)))
            $current=@($Observed.files | Where-Object {(Test-CmEqual ($_.path) ($file.path))})
            $preserved=@($Observed.recovery_copies | Where-Object {(Test-CmEqual ($_.path) ($file.path)) -and (Test-CmEqual ($_.recovery_copy) ($file.recovery_copy)) -and (Test-CmEqual ($_.recovery_package_reference) ($manifest.recovery_package_reference))})
            Assert-Cm ($current.Count -eq 1 -and $preserved.Count -eq 1)
            Assert-CmFields $file $current[0] @('path','sha256','size_bytes','classification')
            Assert-CmFields $file $preserved[0] @('sha256','size_bytes')
            Assert-CmBool $preserved[0].verified $true
        }
    } catch { throw [ArgumentException]::new('RECOVERY_REQUIRED') }
}
function Test-PfcPreWriteIdentityGate {
    param($Authorization, $WavePlan, $MilestoneContract, $WorkOrder, $BuilderEcho, $Checkpoint, $Observed, $CanonicalSources, $ControlPathAllowlist)
    $out=[ordered]@{result='STOP_BEFORE_WRITE';reasons=@();can_issue_builder_lease=$false;canonical_source_action='NONE';authorization_id=$null;milestone_id=$null;work_order_id=$null;expected_builder_start_sha=$null;control_run_id=$null;lease_epoch=$null}
    try {
        foreach ($kind in @('authorization_sources','wave_sources')) {
            $sources=Get-CmField $CanonicalSources $kind; Assert-CmArray $sources
            if ($sources.Count -gt 1) { $out.result='CONTROL_PLANE_DEFECT'; throw [ArgumentException]::new('DUPLICATE_CANONICAL_SOURCE') }
            Assert-Cm ($sources.Count -eq 1) 'CANONICAL_SOURCE_REQUIRED'
            Assert-CmBool $sources[0].equivalent $true
            Assert-Cm ($sources[0].registered -is [bool])
            [void](Get-CmExactPaths @($sources[0].path))
        }
        Assert-Cm ((Test-CmEqual ($CanonicalSources.authorization_sources[0].authorization_id) ($Authorization.authorization_id)) -and (Test-CmEqual ($CanonicalSources.wave_sources[0].wave_id) ($WavePlan.wave_id))) 'CANONICAL_SOURCE_MISMATCH'
        $out.canonical_source_action='REUSE_AND_REGISTER'
        foreach ($kind in @('authorization_sources','wave_sources')) { Assert-CmBool (Get-CmField $CanonicalSources $kind)[0].registered $true }
        Assert-CmApproval $Authorization $Observed.approval
        Assert-CmBool $Observed.is_git_repository $true
        Assert-CmArray $Observed.ancestry; Assert-CmArray $Observed.diffs
        Assert-CmArray $Observed.invalidation_reasons; Assert-Cm ($Observed.invalidation_reasons.Count -eq 0) 'AUTHORIZATION_INVALIDATED'
        foreach ($id in @('authorization_id','goal_id','milestone_id','contract_id','work_order_id','control_run_id','wave_id')) { Assert-Cm (Test-CmId (Get-CmField $WorkOrder $id)) }
        foreach ($version in @('goal_version','contract_version','lease_epoch')) { $n=Get-CmField $WorkOrder $version; Assert-Cm ((Test-CmInteger $n) -and $n -gt 0) }
        $identityFields=@('authorization_id','authorization_status','goal_id','goal_version','scope','milestone_id','contract_id','contract_version','work_order_id','control_run_id','lease_epoch','wave_id','repository_identity','identity_algorithm','worktree_identity','worktree_identity_algorithm','exact_branch','authorized_base_checkpoint_sha','previous_accepted_checkpoint_sha','current_milestone_base_sha','expected_builder_start_sha','hash_algorithm','writable_paths_hash','forbidden_paths_hash','risk_level','validation_plan')
        Assert-CmFields $WorkOrder $MilestoneContract $identityFields
        Assert-CmFields $WorkOrder $BuilderEcho $identityFields
        Assert-CmFields $WorkOrder $Checkpoint @('authorization_id','control_run_id','lease_epoch','wave_id','milestone_id','previous_accepted_checkpoint_sha','current_milestone_base_sha','expected_builder_start_sha')
        Assert-CmFields $Authorization $WorkOrder @('authorization_id','authorization_status','scope')
        Assert-CmFields $Authorization.goal $WorkOrder @('goal_id','goal_version')
        Assert-CmFields $Authorization.repository $WorkOrder @('identity_algorithm','repository_identity','authorized_base_checkpoint_sha')
        Assert-CmFields $Authorization.paths $WorkOrder @('hash_algorithm','writable_paths_hash','forbidden_paths_hash')
        Assert-CmFields $WorkOrder $Observed @('identity_algorithm','repository_identity','worktree_identity_algorithm','worktree_identity','exact_branch')
        Assert-Cm ((Test-CmEqual ($WorkOrder.identity_algorithm) ('PFC_GIT_COMMON_DIR_SHA256_V1')) -and (Test-CmEqual ($WorkOrder.worktree_identity_algorithm) ('PFC_WORKTREE_ROOT_SHA256_V1')) -and (Test-CmEqual ($WorkOrder.hash_algorithm) ('PFC_REPO_PATH_SET_SHA256_V1'))) 'IDENTITY_ALGORITHM_MISMATCH'
        Assert-Cm ((Test-CmHash $WorkOrder.repository_identity) -and (Test-CmHash $WorkOrder.worktree_identity))
        $writable=Get-PfcRepoPathSetIdentityV1 $Observed.writable_paths; $forbidden=Get-PfcRepoPathSetIdentityV1 $Observed.forbidden_paths
        Assert-Cm ($writable.normalized_paths.Count -gt 0 -and (Test-CmEqual ($writable.paths_hash) ($WorkOrder.writable_paths_hash)) -and (Test-CmEqual ($forbidden.paths_hash) ($WorkOrder.forbidden_paths_hash))) 'PATH_SET_MISMATCH'
        Assert-Cm (Test-CmSame (Get-CmExactPaths $ControlPathAllowlist) (Get-CmExactPaths $Observed.canonical_control_paths)) 'CONTROL_ALLOWLIST_MISMATCH'
        Assert-CmArray $Observed.roadmap_ids
        foreach ($id in $Observed.roadmap_ids) { Assert-Cm (Test-CmId $id) }
        Assert-Cm (Test-CmUnique $Observed.roadmap_ids)
        foreach ($id in @('from','to','stop_gate')) { Assert-Cm (Test-CmId (Get-CmField $Authorization.scope $id)) 'OUTSIDE_AUTHORIZED_SCOPE' }
        $start=Get-CmOrdinalIndex $Observed.roadmap_ids $Authorization.scope.from; $end=Get-CmOrdinalIndex $Observed.roadmap_ids $Authorization.scope.to; $index=Get-CmOrdinalIndex $Observed.roadmap_ids $WorkOrder.milestone_id
        Assert-Cm ((Test-CmEqual ($Authorization.scope.type) ('MILESTONE_RANGE')) -and $start -ge 0 -and $end -ge $start -and $index -ge $start -and $index -le $end) 'OUTSIDE_AUTHORIZED_SCOPE'
        Assert-Cm ((Test-CmEqual ($Observed.active_plan_milestone_id) ($WorkOrder.milestone_id))) 'PLAN_MISMATCH'
        Assert-CmFields $WorkOrder $WavePlan @('authorization_id','goal_id','wave_id')
        Assert-Cm ((Test-CmEqual ($WavePlan.stop_gate) ($Authorization.scope.stop_gate))) 'STOP_GATE_MISMATCH'
        Assert-CmArray $WavePlan.milestones; Assert-Cm ($WavePlan.milestones.Count -gt 0)
        Assert-CmArray $Observed.accepted_milestone_ids
        $waveIds=@($WavePlan.milestones | ForEach-Object {$_.milestone_id})
        Assert-Cm (Test-CmUnique $waveIds) 'DUPLICATE_MILESTONE'
        $selected=@($WavePlan.milestones | Where-Object {(Test-CmEqual ($_.milestone_id) ($WorkOrder.milestone_id))})
        Assert-Cm ($selected.Count -eq 1) 'WAVE_MISMATCH'
        foreach ($prior in $waveIds) { if ((Test-CmEqual ($prior) ($WorkOrder.milestone_id))) { break }; Assert-Cm ((Test-CmContains ($Observed.accepted_milestone_ids) ($prior))) 'PREVIOUS_MILESTONE_NOT_ACCEPTED' }
        foreach ($entry in $WavePlan.milestones) {
            $n=Get-CmOrdinalIndex $Observed.roadmap_ids $entry.milestone_id
            Assert-Cm ($n -ge $start -and $n -le $end) 'OUTSIDE_AUTHORIZED_SCOPE'
            $medium=if (@($entry.validation_plan | Where-Object {(Test-CmEqual ($_.tier) ('ROLLBACK'))}).Count -gt 0) {'ROLLBACK'} else {'UPGRADE_DOWNGRADE'}
            $risk=Resolve-PfcRiskValidationPlan $entry.risk_level @() $medium $Authorization.limits
            Assert-Cm ($risk.allowed -and $WavePlan.milestones.Count -le $risk.max_wave_size) 'WAVE_RISK_LIMIT'
            Assert-CmValidation $entry.validation_plan $risk.required_milestone_tiers
            Assert-CmArray $entry.dependencies
            foreach ($dependency in $entry.dependencies) { Assert-Cm (Test-CmId $dependency); $position=Get-CmOrdinalIndex $waveIds $dependency; Assert-Cm ($position -lt (Get-CmOrdinalIndex $waveIds $entry.milestone_id)) 'DEPENDENCY_ORDER'; if ((Test-CmEqual ($entry.milestone_id) ($WorkOrder.milestone_id)) -or $position -lt 0) { Assert-Cm ((Test-CmContains ($Observed.accepted_milestone_ids) ($dependency))) 'DEPENDENCY_NOT_ACCEPTED' } }
        }
        Assert-CmFields $WorkOrder $selected[0] @('milestone_id','contract_id','contract_version','risk_level','exact_branch','worktree_identity_algorithm','worktree_identity','validation_plan')
        $risk=Resolve-PfcRiskValidationPlan $WorkOrder.risk_level $Observed.risk_factors $Observed.medium_validation $Authorization.limits
        Assert-Cm ($risk.allowed -and (Test-CmEqual ($risk.risk_level) ($WorkOrder.risk_level))) 'RISK_MISMATCH'
        Assert-CmValidation $WorkOrder.validation_plan $risk.required_milestone_tiers
        Assert-CmValidation @($WavePlan.wave_validation) @('T3')
        $branch=$WorkOrder.exact_branch; $namespace=$Authorization.repository.write_branch_namespace
        Assert-Cm ((Test-CmEqual ($namespace) (('codex/pfc/'+$Authorization.authorization_id+'/'))) -and (Test-CmText $branch) -and $branch.StartsWith($namespace,[StringComparison]::Ordinal) -and $branch.Length -gt $namespace.Length -and $branch -notmatch '(\s|\.\.|@\{|[~^:?*\[\\]|//|/\.|\.lock(?:/|\z)|[/.]\z)') 'BRANCH_MISMATCH'
        Assert-Cm ((Test-CmEqual ($Authorization.repository.write_branch_policy) ('MILESTONE_WORKTREE_ONLY')) -and (Test-CmText $Observed.default_branch) -and (-not (Test-CmEqual ($branch) ($Observed.default_branch)))) 'DEFAULT_BRANCH_WRITE_DENIED'
        Assert-CmBool $Authorization.repository.default_branch_write $false
        Assert-CmArray $Observed.registered_worktrees
        $registered=@($Observed.registered_worktrees | Where-Object {(Test-CmEqual ($_.milestone_id) ($WorkOrder.milestone_id))})
        Assert-Cm ($registered.Count -eq 1) 'WORKTREE_REGISTRY_MISMATCH'
        Assert-CmFields $WorkOrder $registered[0] @('worktree_identity','exact_branch')
        $base=$WorkOrder.current_milestone_base_sha
        Assert-Cm ((Test-CmSha $base) -and (Test-CmSha $WorkOrder.expected_builder_start_sha)) 'BASELINE_DRIFT'
        if ((Test-CmEqual ($Checkpoint.previous_accepted_checkpoint_sha) ('FIRST_MILESTONE'))) { Assert-Cm ((Test-CmEqual ($base) ($Authorization.repository.authorized_base_checkpoint_sha)) -and $index -eq $start) 'BASELINE_DRIFT' }
        else {
            Assert-Cm ((Test-CmEqual ($base) ($Checkpoint.previous_accepted_checkpoint_sha)) -and (Test-CmEqual ($Observed.previous_acceptance.result) ('ACCEPTED')) -and (Test-CmEqual ($Observed.previous_acceptance.accepted_checkpoint_sha) ($base))) 'BASELINE_DRIFT'
            $previousIndex=Get-CmOrdinalIndex $Observed.roadmap_ids $Observed.previous_acceptance.milestone_id
            Assert-Cm ($previousIndex -ge $start -and $previousIndex -lt $index -and (Test-CmContains ($Observed.accepted_milestone_ids) ($Observed.previous_acceptance.milestone_id))) 'BASELINE_DRIFT'
            $position=Get-CmOrdinalIndex $waveIds $WorkOrder.milestone_id
            $accepted=Get-CmField $Observed accepted_checkpoints
            Assert-CmArray $accepted
            $previous=@($accepted | Where-Object {Test-CmEqual $_.milestone_id $Observed.previous_acceptance.milestone_id})
            Assert-Cm ($previous.Count -eq 1) 'BASELINE_DRIFT'
            Assert-CmFields $Observed.previous_acceptance $previous[0] @('milestone_id','accepted_checkpoint_sha','result') 'BASELINE_DRIFT'
            Assert-CmBool $previous[0].observed $true
            if($position -gt 0) {
                Assert-Cm (Test-CmEqual $Observed.previous_acceptance.milestone_id $waveIds[$position-1]) 'BASELINE_DRIFT'
            } else {
                # Cross-Wave latestness is an explicit caller observation, never
                # guessed from roadmap names or their lexical order.
                $latest=Get-CmField $Observed latest_acceptance
                Assert-CmBool $latest.observed $true
                Assert-CmFields $Observed.previous_acceptance $latest @('milestone_id','accepted_checkpoint_sha','result') 'BASELINE_DRIFT'
                Assert-Cm ((Test-CmId $latest.wave_id) -and -not (Test-CmEqual $latest.wave_id $WavePlan.wave_id)) 'BASELINE_DRIFT'
            }
        }
        Assert-CmAncestry $Observed.ancestry $Authorization.repository.authorized_base_checkpoint_sha $base
        Assert-Cm (Test-CmSha $WavePlan.base_checkpoint_sha) 'BASELINE_DRIFT'
        if ((Test-CmEqual ($WavePlan.milestones[0].milestone_id) ($WorkOrder.milestone_id))) { Assert-Cm ((Test-CmEqual ($WavePlan.base_checkpoint_sha) ($base))) 'BASELINE_DRIFT' }
        $revisions=$Checkpoint.repair_budget.candidate_revisions
        Assert-Cm ((Test-CmInteger $revisions) -and $revisions -ge 0 -and $revisions -le 3)
        if ($revisions -eq 0) { Assert-Cm ((Test-CmEqual ($Observed.candidate_sha) ('NONE'))) 'CANDIDATE_MISMATCH'; $origin=$base }
        else { Assert-Cm (Test-CmSha $Observed.candidate_sha) 'CANDIDATE_MISMATCH'; $origin=$Observed.candidate_sha; Assert-CmAncestry $Observed.ancestry $base $origin }
        Assert-CmControlDescendant $Observed.ancestry $Observed.diffs $origin $WorkOrder.expected_builder_start_sha $ControlPathAllowlist
        Assert-Cm ((Test-CmEqual ($Observed.actual_worktree_head) ($WorkOrder.expected_builder_start_sha)) -and (Test-CmEqual ($BuilderEcho.actual_worktree_head) ($Observed.actual_worktree_head))) 'HEAD_MISMATCH'
        Assert-Cm ((Test-CmEqual ($Observed.governance_head_sha) ($Observed.actual_worktree_head))) 'RECOVERY_REQUIRED'
        Assert-CmRecoveryInventory $Checkpoint $Observed $writable.normalized_paths $forbidden.normalized_paths
        $out.result='PRE_WRITE_IDENTITY_GATE_PASS'; $out.can_issue_builder_lease=$true
        $out.authorization_id=$Authorization.authorization_id; $out.milestone_id=$WorkOrder.milestone_id; $out.work_order_id=$WorkOrder.work_order_id; $out.expected_builder_start_sha=$WorkOrder.expected_builder_start_sha
        $out.control_run_id=$WorkOrder.control_run_id; $out.lease_epoch=$WorkOrder.lease_epoch
    } catch { $out.reasons=@(Get-CmReason $_) }
    [pscustomobject]$out
}
function Assert-CmWaveImpact($VerifyOrder, $BuilderReport, $WaveEntry, $ChangedPaths) {
    # Local evaluator projections of VERIFY_ORDER Wave Impact Checks and
    # BUILD_REPORT Wave Impact; message-contracts.md remains their authority.
    Assert-CmArray $VerifyOrder.wave_impact_checks
    Assert-Cm ($VerifyOrder.wave_impact_checks.Count -gt 0) 'WAVE_IMPACT_REQUIRED'
    Assert-CmArray $WaveEntry.dependencies
    foreach ($dependency in $WaveEntry.dependencies) { Assert-Cm (Test-CmId $dependency) 'WAVE_IMPACT_MISMATCH' }
    $required=$false
    foreach ($check in $VerifyOrder.wave_impact_checks) {
        Assert-CmFields $VerifyOrder $check @('wave_id','milestone_id','candidate_sha') 'WAVE_IMPACT_MISMATCH'
        Assert-Cm (Test-CmSame $ChangedPaths (Get-CmExactPaths $check.paths)) 'WAVE_IMPACT_MISMATCH'
        Assert-Cm (Test-CmSame $WaveEntry.dependencies $check.dependencies) 'WAVE_IMPACT_MISMATCH'
        Assert-Cm ($check.required -is [bool]) 'WAVE_IMPACT_MISMATCH'
        if ($check.required) { $required=$true }
    }
    Assert-Cm $required 'WAVE_IMPACT_REQUIRED'
    $impact=$BuilderReport.wave_impact
    Assert-CmFields $VerifyOrder $impact @('wave_id','milestone_id','candidate_sha') 'WAVE_IMPACT_MISMATCH'
    Assert-Cm (Test-CmSame $ChangedPaths (Get-CmExactPaths $impact.paths)) 'WAVE_IMPACT_MISMATCH'
    Assert-Cm (Test-CmSame $WaveEntry.dependencies $impact.dependencies) 'WAVE_IMPACT_MISMATCH'
    Assert-Cm (Test-CmEqual $impact.result 'PASS') 'WAVE_IMPACT_NOT_PASS'
}
function Test-PfcPreReviewIdentityGate {
    param($Authorization, $MilestoneContract, $WorkOrder, $VerifyOrder, $BuilderReport, $Candidate, $Observed, $PathPolicy, $WavePlan)
    $out=[ordered]@{result='CONTROL_PLANE_DEFECT';reasons=@();can_start_review=$false;authorization_id=$null;milestone_id=$null;work_order_id=$null;candidate_sha=$null}
    try {
        Assert-Cm ((Test-CmEqual ($Authorization.authorization_status) ('ACTIVE')) -and (Test-CmId $Authorization.authorization_id)) 'AUTHORIZATION_INACTIVE'
        foreach ($id in @('authorization_id','goal_id','milestone_id','contract_id','work_order_id','control_run_id','wave_id')) { Assert-Cm (Test-CmId (Get-CmField $WorkOrder $id)) }
        foreach ($version in @('goal_version','contract_version','lease_epoch')) { $n=Get-CmField $WorkOrder $version; Assert-Cm ((Test-CmInteger $n) -and $n -gt 0) }
        Assert-Cm ((Test-CmEqual ($WorkOrder.identity_algorithm) ('PFC_GIT_COMMON_DIR_SHA256_V1')) -and (Test-CmHash $WorkOrder.repository_identity)) 'IDENTITY_ALGORITHM_MISMATCH'
        $common=@('authorization_id','authorization_status','goal_id','goal_version','milestone_id','contract_id','contract_version','work_order_id','control_run_id','lease_epoch','wave_id','repository_identity','identity_algorithm','current_milestone_base_sha','hash_algorithm','writable_paths_hash','forbidden_paths_hash','risk_level','validation_plan')
        foreach ($record in @($MilestoneContract,$VerifyOrder,$BuilderReport,$Candidate)) { Assert-CmFields $WorkOrder $record $common 'STALE_REPORT_REJECTED' }
        Assert-CmFields $Authorization $VerifyOrder @('authorization_id','authorization_status')
        Assert-CmFields $Authorization.goal $VerifyOrder @('goal_id','goal_version')
        Assert-CmFields $Authorization.repository $VerifyOrder @('repository_identity','identity_algorithm')
        Assert-CmFields $Authorization.paths $VerifyOrder @('hash_algorithm','writable_paths_hash','forbidden_paths_hash')
        Assert-CmFields $VerifyOrder $Observed @('verify_order_id','acceptance_record_target','repository_identity','candidate_sha') 'STALE_REPORT_REJECTED'
        Assert-Cm ((Test-CmId $VerifyOrder.verify_order_id) -and (Test-CmId $VerifyOrder.acceptance_record_target) -and (Test-CmSha $VerifyOrder.candidate_sha) -and (Test-CmSha $VerifyOrder.base_sha) -and (Test-CmEqual ($VerifyOrder.base_sha) ($WorkOrder.current_milestone_base_sha))) 'VERSION_INTEGRITY_FAIL'
        foreach ($record in @($BuilderReport,$Candidate)) { Assert-CmFields $VerifyOrder $record @('base_sha','candidate_sha','builder_evidence_sha','changed_files','validation_tier','acceptance_record_target') 'VERSION_INTEGRITY_FAIL' }
        Assert-Cm ((Test-CmEqual ($VerifyOrder.builder_evidence_sha) ($VerifyOrder.candidate_sha))) 'STALE_REPORT_REJECTED'
        Assert-CmAncestry $Observed.ancestry $VerifyOrder.base_sha $VerifyOrder.candidate_sha
        if ((-not (Test-CmEqual ($Observed.actual_head_sha) ($Candidate.candidate_sha)))) { Assert-CmControlDescendant $Observed.ancestry $Observed.diffs $Candidate.candidate_sha $Observed.actual_head_sha $Observed.canonical_control_paths }
        Assert-CmFields $WorkOrder $WavePlan @('wave_id','authorization_id','goal_id')
        Assert-CmArray $WavePlan.milestones
        $entry=@($WavePlan.milestones | Where-Object {(Test-CmEqual ($_.milestone_id) ($VerifyOrder.milestone_id))})
        Assert-Cm ($entry.Count -eq 1) 'WAVE_MISMATCH'
        Assert-CmFields $WorkOrder $entry[0] @('contract_id','contract_version','risk_level','validation_plan')
        $risk=Resolve-PfcRiskValidationPlan $WorkOrder.risk_level $Observed.risk_factors $Observed.medium_validation $Authorization.limits
        Assert-Cm ($risk.allowed -and (Test-CmEqual ($risk.risk_level) ($WorkOrder.risk_level))) 'RISK_MISMATCH'
        Assert-CmValidation $VerifyOrder.validation_plan $risk.required_milestone_tiers
        Assert-Cm (Test-CmSame $VerifyOrder.validation_tier $risk.required_milestone_tiers) 'TIER_MISMATCH'
        $writable=Get-PfcRepoPathSetIdentityV1 $PathPolicy.writable_paths; $forbidden=Get-PfcRepoPathSetIdentityV1 $PathPolicy.forbidden_paths
        Assert-CmFields $WorkOrder $PathPolicy @('hash_algorithm','writable_paths_hash','forbidden_paths_hash')
        Assert-Cm ((Test-CmEqual ($PathPolicy.hash_algorithm) ('PFC_REPO_PATH_SET_SHA256_V1')) -and (Test-CmEqual ($writable.paths_hash) ($PathPolicy.writable_paths_hash)) -and (Test-CmEqual ($forbidden.paths_hash) ($PathPolicy.forbidden_paths_hash))) 'PATH_SET_MISMATCH'
        Assert-CmBool $Observed.diff.observed $true
        Assert-Cm ((Test-CmEqual ($Observed.diff.from_sha) ($VerifyOrder.base_sha)) -and (Test-CmEqual ($Observed.diff.to_sha) ($VerifyOrder.candidate_sha))) 'VERSION_INTEGRITY_FAIL'
        $changes=Get-CmExactPaths $Observed.diff.changed_paths
        Assert-Cm (Test-CmSame $changes (Get-CmExactPaths $VerifyOrder.changed_files)) 'VERSION_INTEGRITY_FAIL'
        foreach ($path in $changes) { Assert-Cm (Test-CmPathAllowed $path $writable.normalized_paths $forbidden.normalized_paths) 'PATH_POLICY_VIOLATION' }
        Assert-CmWaveImpact $VerifyOrder $BuilderReport $entry[0] $changes
        Assert-CmArray $Observed.builder_evidence; Assert-Cm ($Observed.builder_evidence.Count -gt 0) 'STALE_REPORT_REJECTED'
        Assert-CmArray $VerifyOrder.builder_evidence_ids
        Assert-CmFields $VerifyOrder $BuilderReport @('builder_evidence_ids') 'STALE_REPORT_REJECTED'
        $evidenceIds=@($Observed.builder_evidence | ForEach-Object {$_.evidence_id})
        Assert-Cm ($evidenceIds.Count -eq $VerifyOrder.builder_evidence_ids.Count -and (Test-CmUnique $evidenceIds)) 'STALE_REPORT_REJECTED'
        foreach ($evidence in $Observed.builder_evidence) {
            Assert-Cm ((Test-CmContains ($VerifyOrder.builder_evidence_ids) ($evidence.evidence_id))) 'STALE_REPORT_REJECTED'
            Assert-Cm ((Test-CmId $evidence.evidence_id) -and (Test-CmEqual ($evidence.candidate_sha) ($VerifyOrder.candidate_sha)) -and (Test-CmEqual ($evidence.work_order_id) ($VerifyOrder.work_order_id)) -and (Test-CmText $evidence.reference)) 'STALE_REPORT_REJECTED'
            Assert-CmBool $evidence.observed $true; Assert-CmBool $evidence.fresh $true
        }
        Assert-CmArray $Observed.tracked_mutations; Assert-CmArray $Observed.staged_mutations
        Assert-Cm ($Observed.tracked_mutations.Count -eq 0 -and $Observed.staged_mutations.Count -eq 0) 'VERSION_INTEGRITY_FAIL'
        $out.result='PRE_REVIEW_IDENTITY_GATE_PASS'; $out.can_start_review=$true; $out.authorization_id=$Authorization.authorization_id; $out.milestone_id=$VerifyOrder.milestone_id; $out.work_order_id=$VerifyOrder.work_order_id; $out.candidate_sha=$VerifyOrder.candidate_sha
    } catch { $out.reasons=@(Get-CmReason $_) }
    [pscustomobject]$out
}
function Resolve-PfcIssueDisposition {
    param($Classification, $Evidence, $AffectedScope, $Phase, $Fallback, $IndependentProductEvidence, $Budget, $SpecialistRequirement='NONE')
    $out=[ordered]@{classification='UNCLASSIFIED';blocking_scope='MILESTONE';next_action='PAUSE_COLLECT_EVIDENCE';fallback_reference='NONE';reason='UNCLASSIFIED';requires_new_candidate=$false;residual_risk='NONE'}
    try {
        if ((Test-CmEqual ($Classification) ('SECURITY_OR_DATA_RISK'))) { $out.classification=$Classification; $out.blocking_scope='GLOBAL'; $out.next_action='STOP'; $out.reason='SECURITY_OR_DATA_RISK'; return [pscustomobject]$out }
        if ((Test-CmEqual ($Classification) ('CONTROL_PLANE_DEFECT'))) { $out.classification=$Classification; $out.blocking_scope='GLOBAL'; $out.next_action='FREEZE_CONTROL'; $out.reason='CONTROL_PLANE_DEFECT'; return [pscustomobject]$out }
        Assert-CmArray $Evidence; Assert-CmArray $AffectedScope
        Assert-Cm ($Evidence.Count -gt 0 -and $AffectedScope.Count -gt 0 -and (Test-CmContains (@('MILESTONE','WAVE','PHASE')) ($Phase))) 'EVIDENCE_REQUIRED'
        foreach ($e in $Evidence) { Assert-Cm (Test-CmText $e) 'EVIDENCE_REQUIRED' }; foreach ($id in $AffectedScope) { Assert-Cm (Test-CmId $id) }
        Assert-Cm ((Test-CmContains (@('PRODUCT_DEFECT','DOCUMENTATION_ONLY','TEST_INFRASTRUCTURE_DEFECT','KNOWN_ENVIRONMENT_LIMITATION','EXTERNAL_DEPENDENCY_FAILURE','UNCLASSIFIED')) ($Classification))) 'UNCLASSIFIED'
        $out.classification=$Classification
        if ((Test-CmEqual ($Classification) ('UNCLASSIFIED'))) { return [pscustomobject]$out }
        Assert-Cm ((Test-CmContains (@('NONE','NONESSENTIAL','ESSENTIAL')) ($SpecialistRequirement))) 'UNKNOWN_SPECIALIST_REQUIREMENT'
        if ((Test-CmContains (@('PRODUCT_DEFECT','DOCUMENTATION_ONLY')) ($Classification))) {
            Assert-CmBool $Budget.allowed $true
            Assert-Cm ($Budget.requires_new_candidate -is [bool])
            $out.next_action='REPAIR'; $out.requires_new_candidate=$Budget.requires_new_candidate; $out.reason='IN_SCOPE_REPAIR'; return [pscustomobject]$out
        }
        $out.blocking_scope=if ((Test-CmEqual ($Phase) ('MILESTONE'))) {'MILESTONE'} else {'WAVE'}
        $out.next_action='BLOCK_VERIFICATION'; $out.reason='FALLBACK_REQUIRED'
        if ((Test-CmEqual ($SpecialistRequirement) ('ESSENTIAL'))) { $out.reason='ESSENTIAL_SPECIALIST_UNAVAILABLE'; return [pscustomobject]$out }
        Assert-Cm ((Test-CmId $Fallback.fallback_id) -and (Test-CmText $Fallback.review_trigger) -and (Test-CmEqual ($Fallback.review_trigger) ($Fallback.observed_trigger))) 'FALLBACK_REQUIRED'
        foreach ($flag in @('registered','approved','applicable')) { Assert-CmBool (Get-CmField $Fallback $flag) $true }; Assert-CmBool $Fallback.trigger_fired $false
        if ((Test-CmEqual ($Classification) ('TEST_INFRASTRUCTURE_DEFECT'))) {
            foreach ($flag in @('observed','independent','fresh')) { Assert-CmBool (Get-CmField $IndependentProductEvidence $flag) $true }
            Assert-Cm ((Test-CmEqual ($IndependentProductEvidence.result) ('PASS')) -and (Test-CmSha $IndependentProductEvidence.candidate_sha) -and (Test-CmEqual ($IndependentProductEvidence.candidate_sha) ($IndependentProductEvidence.expected_candidate_sha)) -and (Test-CmText $IndependentProductEvidence.reference)) 'INDEPENDENT_EVIDENCE_REQUIRED'
            $out.next_action='CONTINUE'
        } else { $out.next_action='USE_APPROVED_FALLBACK' }
        $out.blocking_scope='NONE'; $out.fallback_reference=$Fallback.fallback_id; $out.reason='APPROVED_FALLBACK'; $out.residual_risk='REGISTER_LIMITATION_AND_TECHNICAL_DEBT'
    } catch { $out.reason=Get-CmReason $_ }
    [pscustomobject]$out
}
function Test-PfcRepairBudget {
    param($RepairBudget, $PreviousBudget, $Limits, $RequestedAction, $CandidateFrozen, $ChangedTrackedPaths, $ControlPathAllowlist, $FailureHistory, $Convergence, $CandidateResult)
    $out=[ordered]@{allowed=$false;reason='INVALID_REPAIR_INPUT';builder_attempts_remaining=0;auto_rework_remaining=0;candidate_revisions_remaining=0;requires_new_candidate=$false;next_candidate_revision=$null;return_lease=$false;hard_stop=$false}
    try {
        Assert-Cm (Test-CmContains @('START_BUILDER_REPAIR','START_AUTO_REWORK','FREEZE_CANDIDATE','ACCEPT_CURRENT_CANDIDATE','RESUME','CONTROL_RECORD','ENVIRONMENT_RECOVERY') $RequestedAction) 'UNKNOWN_REPAIR_ACTION'
        Assert-Cm (Test-CmContains @('PASS','FAIL','PARTIAL','NOT_RUN') $CandidateResult) 'INVALID_CANDIDATE_RESULT'
        foreach ($pair in @(@('builder_code_repair_attempts','max_builder_code_repair_attempts',2),@('auto_rework_rounds','max_auto_rework_rounds',2),@('candidate_revisions','max_candidate_revisions',3))) {
            $used=Get-CmField $RepairBudget $pair[0]; $previous=Get-CmField $PreviousBudget $pair[0]; $limit=Get-CmField $Limits $pair[1]
            Assert-Cm ((Test-CmInteger $used) -and (Test-CmInteger $previous) -and (Test-CmInteger $limit) -and $previous -ge 0 -and $used -ge $previous -and $used -le $limit -and $limit -ge 0 -and $limit -le $pair[2]) 'INVALID_REPAIR_COUNTER'
        }
        Assert-Cm ($Limits.max_candidate_revisions -ge 1 -and $CandidateFrozen -is [bool])
        $out.builder_attempts_remaining=$Limits.max_builder_code_repair_attempts-$RepairBudget.builder_code_repair_attempts
        $out.auto_rework_remaining=$Limits.max_auto_rework_rounds-$RepairBudget.auto_rework_rounds
        $out.candidate_revisions_remaining=$Limits.max_candidate_revisions-$RepairBudget.candidate_revisions
        foreach ($flag in @('root_cause_confirmed','data_corruption','permission_bypass','contract_change_required','scope_change_required')) { Assert-Cm ((Get-CmField $FailureHistory $flag) -is [bool]) }
        foreach ($count in @('same_core_failure_rounds','rounds_without_new_pass')) { $n=Get-CmField $FailureHistory $count; Assert-Cm ((Test-CmInteger $n) -and $n -ge 0) }
        Assert-Cm ((Test-CmContains (@('IMPROVING','STABLE','STALLED','REGRESSING')) ($Convergence)))
        if (-not $FailureHistory.root_cause_confirmed -or -not (Test-CmText $FailureHistory.root_cause) -or $FailureHistory.same_core_failure_rounds -ge 2 -or $FailureHistory.rounds_without_new_pass -ge 2 -or (Test-CmContains (@('STALLED','REGRESSING')) ($Convergence)) -or $FailureHistory.data_corruption -or $FailureHistory.permission_bypass -or $FailureHistory.contract_change_required -or $FailureHistory.scope_change_required) {
            $out.hard_stop=$true; $out.return_lease=$true; throw [ArgumentException]::new('REPAIR_LOOP_STOPPED')
        }
        $changes=Get-CmExactPaths $ChangedTrackedPaths $false; $controls=Get-CmExactPaths $ControlPathAllowlist
        $out.requires_new_candidate=($CandidateFrozen -and @($changes | Where-Object {(-not (Test-CmContains ($controls) ($_)))}).Count -gt 0)
        Assert-Cm ((-not $CandidateFrozen -and $RepairBudget.candidate_revisions -eq 0) -or ($CandidateFrozen -and $RepairBudget.candidate_revisions -ge 1)) 'CANDIDATE_COUNTER_MISMATCH'
        $out.next_candidate_revision=$RepairBudget.candidate_revisions
        if ($out.requires_new_candidate -or -not $CandidateFrozen) { $out.next_candidate_revision++ }
        if ($out.next_candidate_revision -gt $Limits.max_candidate_revisions) { $out.hard_stop=$true; $out.return_lease=$true; throw [ArgumentException]::new('REPAIR_LOOP_STOPPED') }
        switch -CaseSensitive ($RequestedAction) {
            {Test-CmEqual $_ 'START_BUILDER_REPAIR'} { if ($out.builder_attempts_remaining -eq 0) { $out.return_lease=$true; throw [ArgumentException]::new('BUILDER_REPAIR_LIMIT') } }
            {Test-CmEqual $_ 'START_AUTO_REWORK'} { Assert-Cm ($out.auto_rework_remaining -gt 0) 'AUTO_REWORK_LIMIT' }
            {Test-CmEqual $_ 'FREEZE_CANDIDATE'} { Assert-Cm (-not $CandidateFrozen -or $out.requires_new_candidate) 'NO_NEW_CANDIDATE_CHANGE' }
            {Test-CmEqual $_ 'ACCEPT_CURRENT_CANDIDATE'} { Assert-Cm ($CandidateFrozen -and -not $out.requires_new_candidate -and (Test-CmEqual ($CandidateResult) ('PASS'))) 'CANDIDATE_NOT_ACCEPTABLE' }
            {Test-CmEqual $_ 'RESUME'} { }
            {Test-CmEqual $_ 'CONTROL_RECORD'} { Assert-Cm (-not $out.requires_new_candidate) 'NON_CONTROL_CHANGE' }
            {Test-CmEqual $_ 'ENVIRONMENT_RECOVERY'} { Assert-Cm ($changes.Count -eq 0) 'TRACKED_RECOVERY_CHANGE' }
            default { throw [ArgumentException]::new('UNKNOWN_REPAIR_ACTION') }
        }
        $out.allowed=$true; $out.reason='WITHIN_BUDGET'
    } catch { $out.reason=Get-CmReason $_ }
    [pscustomobject]$out
}
function Assert-CmGate($Gate, $AuthorizationId, $MilestoneId, $Sha, [bool]$WriteGate, $WorkOrderId) {
    Assert-Cm ((Test-CmSha $Sha) -and (Test-CmId $AuthorizationId) -and (Test-CmId $MilestoneId) -and (Test-CmId $WorkOrderId) -and (Test-CmEqual ($Gate.work_order_id) ($WorkOrderId)) -and (Test-CmEqual ($Gate.authorization_id) ($AuthorizationId)) -and (Test-CmEqual ($Gate.milestone_id) ($MilestoneId))) 'IDENTITY_GATE_BINDING'
    if ($WriteGate) {
        Assert-Cm ((Test-CmEqual ($Gate.result) ('PRE_WRITE_IDENTITY_GATE_PASS')) -and (Test-CmEqual ($Gate.expected_builder_start_sha) ($Sha))) 'IDENTITY_GATE_BINDING'
        Assert-CmBool $Gate.can_issue_builder_lease $true
    } else {
        Assert-Cm ((Test-CmEqual ($Gate.result) ('PRE_REVIEW_IDENTITY_GATE_PASS')) -and (Test-CmEqual ($Gate.candidate_sha) ($Sha))) 'IDENTITY_GATE_BINDING'
        Assert-CmBool $Gate.can_start_review $true
    }
}
function Assert-CmFreshReview($Review, $Sha) {
    Assert-Cm (Test-CmSha $Sha) 'STALE_REPORT_REJECTED'
    Assert-Cm ((Test-CmEqual ($Review.candidate_sha) ($Sha)) -and (Test-CmEqual ($Review.result) ('PASS'))) 'STALE_REPORT_REJECTED'
    Assert-CmBool $Review.observed $true; Assert-CmBool $Review.fresh $true
}
function Assert-CmGateRuntime($Gate, $Runtime) {
    Assert-Cm ((Test-CmId $Runtime.control_run_id) -and (Test-CmEqual $Gate.control_run_id $Runtime.control_run_id) -and (Test-CmInteger $Runtime.lease_epoch) -and (Test-CmInteger $Gate.lease_epoch) -and $Runtime.lease_epoch -gt 0 -and $Gate.lease_epoch -eq $Runtime.lease_epoch) 'STALE_RUNTIME_LEASE'
}
function Test-PfcContinuousTransition {
    param($AuthorizationStatus='NONE', $ExecutionState='DISABLED', $Event='DEFAULT', $Context=@{explicit_continuous=$false})
    $out=[ordered]@{allowed=$false;authorization_status=$AuthorizationStatus;execution_state=$ExecutionState;readiness='BLOCKED';next_action='NONE';requires_user_decision=$false;writes_allowed=$false;reasons=@();reopen_milestone_ids=@()}
    try {
        Assert-Cm ($Event -is [string] -and $AuthorizationStatus -is [string] -and $ExecutionState -is [string]) 'UNKNOWN_STATE'
        Assert-Cm ((Test-CmContains (@('NONE','ACTIVE','PAUSED','INVALIDATED','SUSPENDED_BY_RUNTIME_ROLLBACK','EXHAUSTED')) ($AuthorizationStatus)) -and (Test-CmContains (@('DISABLED','ARMED','ACTIVE','BLOCKED','STOP_GATE_REACHED','COMPLETED')) ($ExecutionState))) 'UNKNOWN_STATE'
        if ((Test-CmEqual ($Event) ('STATUS_ONLY'))) { $out.allowed=$true; return [pscustomobject]$out }
        $requiresNewDecision=(Test-CmContains @('INVALIDATED','EXHAUSTED','SUSPENDED_BY_RUNTIME_ROLLBACK') $AuthorizationStatus) -or (Test-CmContains @('STOP_GATE_REACHED','COMPLETED') $ExecutionState)
        # A pause or disabled invocation cannot restore revoked/consumed authority.
        if ($requiresNewDecision -and (-not (Test-CmContains @('APPROVE','RECOVERY_COMPLETE','INVALIDATE','RUNTIME_ROLLBACK') $Event))) {
            $out.requires_user_decision=$true;$out.next_action='REQUEST_REAUTHORIZATION';$out.reasons=@('NEW_DECISION_REQUIRED');return [pscustomobject]$out
        }
        Assert-Cm ($Context.explicit_continuous -is [bool])
        if (-not $Context.explicit_continuous) { if ($requiresNewDecision) {$out.requires_user_decision=$true;$out.next_action='REQUEST_REAUTHORIZATION';$out.reasons=@('NEW_DECISION_REQUIRED')} else {$out.execution_state='DISABLED';$out.next_action='PAUSE_AFTER_MILESTONE';$out.reasons=@('CONTINUOUS_NOT_ENABLED')}; return [pscustomobject]$out }
        Assert-Cm ((Test-CmContains (@('START','RESUME')) ($Context.invocation_mode))) 'INVALID_INVOCATION'
        if ((Test-CmEqual ($Event) ('RUNTIME_ROLLBACK'))) { $out.allowed=$true; $out.authorization_status='SUSPENDED_BY_RUNTIME_ROLLBACK'; $out.execution_state='BLOCKED'; $out.next_action='REQUEST_REAUTHORIZATION'; $out.requires_user_decision=$true; return [pscustomobject]$out }
        if ((Test-CmEqual ($Event) ('INVALIDATE'))) { $out.allowed=$true; $out.authorization_status='INVALIDATED'; $out.execution_state='BLOCKED'; $out.next_action='REQUEST_REAUTHORIZATION'; $out.requires_user_decision=$true; return [pscustomobject]$out }
        Assert-Cm ((Test-CmContains (@('APPROVE','ACTIVATE','RESUME','PAUSE','NEXT_MILESTONE','WAVE_END','RECOVERY_COMPLETE')) ($Event))) 'UNKNOWN_EVENT'
        foreach ($flag in @('is_git_repository','git_operation_in_progress','unknown_active_session','unknown_dirty')) { Assert-Cm ((Get-CmField $Context $flag) -is [bool]) }
        if (-not $Context.is_git_repository) { throw [ArgumentException]::new('GIT_REQUIRED') }
        Assert-CmArray $Context.invalidation_reasons; Assert-CmArray $Context.changes
        if ($Context.invalidation_reasons.Count -gt 0 -or $Context.changes.Count -gt 0) { $out.authorization_status='INVALIDATED'; $out.requires_user_decision=$true; throw [ArgumentException]::new('AUTHORIZATION_INVALIDATED') }
        if ($Context.git_operation_in_progress -or $Context.unknown_active_session -or $Context.unknown_dirty -or -not (Test-CmSha $Context.actual_head_sha) -or (-not (Test-CmEqual ($Context.actual_head_sha) ($Context.governance_head_sha)))) {
            $out.authorization_status='INVALIDATED'; $out.readiness='RECOVERY_REQUIRED'; $out.requires_user_decision=$true; $out.next_action='READ_ONLY_INVENTORY'; throw [ArgumentException]::new('RECOVERY_REQUIRED')
        }
        if ((Test-CmEqual ($Event) ('RECOVERY_COMPLETE'))) {
            $out.authorization_status='INVALIDATED'; $out.requires_user_decision=$true; $out.readiness='RECOVERY_REQUIRED'
            $steps=@('READ_ONLY_INVENTORY','EXTERNAL_RECOVERY_PACKAGE','HASH_SIZE_MANIFEST','CLASSIFICATION','REVERSIBLE_ISOLATION','GOVERNANCE_CHECKPOINT','PRE_WRITE_IDENTITY_GATE')
            Assert-CmArray $Context.recovery_steps
            for ($i=0; $i -lt $steps.Count; $i++) {
                $out.next_action=$steps[$i]
                Assert-Cm ($Context.recovery_steps.Count -gt $i) 'RECOVERY_REQUIRED'
                $step=$Context.recovery_steps[$i]
                Assert-Cm ((Test-CmEqual ($step.name) ($steps[$i])) -and (Test-CmEqual ($step.checkpoint_sha) ($Context.actual_head_sha)) -and (Test-CmEqual ($step.recovery_package_reference) ($Context.recovery_checkpoint.recovery_manifest.recovery_package_reference))) 'RECOVERY_REQUIRED'
                Assert-CmBool $step.observed $true
            }
            Assert-Cm ((Test-CmEqual ($Context.recovery_checkpoint.authorization_id) ($Context.authorization_id)) -and (Test-CmEqual ($Context.recovery_checkpoint.expected_builder_start_sha) ($Context.actual_head_sha)) -and (Test-CmEqual ($Context.recovery_observed.actual_worktree_head) ($Context.actual_head_sha))) 'RECOVERY_REQUIRED'
            Assert-CmRecoveryInventory $Context.recovery_checkpoint $Context.recovery_observed (Get-CmExactPaths $Context.recovery_writable_paths) (Get-CmExactPaths $Context.recovery_forbidden_paths)
            Assert-CmGate $Context.pre_write_gate $Context.authorization_id $Context.next_milestone_id $Context.actual_head_sha $true $Context.next_work_order_id
            $out.readiness='READY_WITH_PRECONDITIONS'; $out.next_action='REQUEST_REAUTHORIZATION'; $out.reasons=@('RECOVERY_DOES_NOT_REAUTHORIZE'); return [pscustomobject]$out
        }
        Assert-Cm ((Test-CmContains (@('READY_FOR_CONTINUOUS_EXECUTION','READY_WITH_PRECONDITIONS')) ($Context.readiness))) 'RECOVERY_REQUIRED'
        $out.readiness=$Context.readiness
        Assert-CmArray $Context.preconditions
        foreach ($precondition in $Context.preconditions) { Assert-Cm (Test-CmText $precondition.reference); Assert-CmBool $precondition.observed $true; Assert-CmBool $precondition.satisfied $true }
        if ((Test-CmEqual ($Context.readiness) ('READY_WITH_PRECONDITIONS'))) { Assert-Cm ($Context.preconditions.Count -gt 0) 'PRECONDITIONS_REQUIRED' }
        Assert-Cm ($Context.stop_reason -is [string])
        if ((-not (Test-CmEqual ($Context.stop_reason) ('NONE')))) { $out.requires_user_decision=$true; throw [ArgumentException]::new('HARD_STOP_REQUIRES_USER') }
        # Pausing and reauthorization also retain current durable hard stops.
        Assert-CmArray $Context.findings
        foreach ($finding in $Context.findings) { Assert-Cm (Test-CmContains @('BLOCKER','MAJOR','MINOR','INFO') $finding.severity); Assert-Cm (-not (Test-CmContains @('BLOCKER','MAJOR') $finding.severity)) 'BLOCKING_FINDINGS' }
        Assert-Cm ($Context.irreversible_pending -is [bool] -and $Context.essential_specialist_active -is [bool])
        Assert-Cm (-not $Context.irreversible_pending) 'IRREVERSIBLE_ACTION_PENDING'
        Assert-Cm (-not $Context.essential_specialist_active) 'ESSENTIAL_SPECIALIST_ACTIVE'
        Assert-Cm (Test-CmContains @('IMPROVING','STABLE') $Context.convergence) 'REPAIR_LOOP_STOPPED'
        Assert-Cm ($Context.stop_gate_reached -is [bool] -and $Context.scope_exhausted -is [bool])
        Assert-Cm ((Test-CmId $Context.authorization_id) -and (Test-CmId $Context.source_decision_id) -and (Test-CmEqual ($Context.approved_by) ('USER'))) 'INVALID_APPROVAL'
        if ((Test-CmEqual ($Event) ('APPROVE'))) {
            Assert-CmBool $Context.approval.observed $true
            Assert-CmFields $Context $Context.approval @('authorization_id','source_decision_id','approved_by') 'INVALID_APPROVAL'
            if ((Test-CmContains (@('INVALIDATED','EXHAUSTED','SUSPENDED_BY_RUNTIME_ROLLBACK')) ($AuthorizationStatus)) -or (Test-CmContains (@('STOP_GATE_REACHED','COMPLETED')) ($ExecutionState))) { Assert-Cm ((Test-CmId $Context.previous_decision_id) -and (-not (Test-CmEqual ($Context.previous_decision_id) ($Context.source_decision_id)))) 'NEW_DECISION_REQUIRED' }
            $out.allowed=$true; $out.authorization_status='ACTIVE'; $out.execution_state='ARMED'; $out.next_action='CHECK_PRE_WRITE_IDENTITY'; return [pscustomobject]$out
        }
        if ((Test-CmContains (@('INVALIDATED','EXHAUSTED','SUSPENDED_BY_RUNTIME_ROLLBACK','NONE')) ($AuthorizationStatus)) -or (Test-CmContains (@('STOP_GATE_REACHED','COMPLETED')) ($ExecutionState))) { $out.requires_user_decision=$true; throw [ArgumentException]::new('NEW_DECISION_REQUIRED') }
        if ((Test-CmEqual ($Event) ('RESUME'))) {
            Assert-Cm ((Test-CmContains (@('ACTIVE','PAUSED')) ($AuthorizationStatus))) 'AUTHORIZATION_INACTIVE'
            Assert-CmBool $Context.user_resume.observed $true
            Assert-Cm ((Test-CmEqual ($Context.user_resume.approved_by) ($Context.approved_by)) -and (Test-CmEqual ($Context.user_resume.authorization_id) ($Context.authorization_id))) 'RESUME_NOT_AUTHORIZED'
            Assert-Cm ((Test-CmId $Context.runtime.control_run_id) -and (Test-CmId $Context.runtime.previous_control_run_id) -and (-not (Test-CmEqual ($Context.runtime.control_run_id) ($Context.runtime.previous_control_run_id))) -and (Test-CmInteger $Context.runtime.lease_epoch) -and (Test-CmInteger $Context.runtime.previous_lease_epoch) -and $Context.runtime.previous_lease_epoch -gt 0 -and $Context.runtime.lease_epoch -gt $Context.runtime.previous_lease_epoch) 'STALE_RUNTIME_LEASE'
        } elseif (Test-CmEqual $Event 'PAUSE') { Assert-Cm (Test-CmContains @('ACTIVE','PAUSED') $AuthorizationStatus) 'AUTHORIZATION_INACTIVE' }
        else { Assert-Cm ((Test-CmEqual ($AuthorizationStatus) ('ACTIVE'))) 'AUTHORIZATION_INACTIVE' }
        if ((Test-CmContains @('ACTIVATE','RESUME','PAUSE','NEXT_MILESTONE') $Event) -and ($Context.stop_gate_reached -or $Context.scope_exhausted)) {
            $out.next_action='PERSIST_WAVE_SUMMARY'; $out.requires_user_decision=$true
            throw [ArgumentException]::new('BOUNDARY_REQUIRES_WAVE_FINALIZATION')
        }
        if (Test-CmEqual $Event 'PAUSE') {
            Assert-Cm (Test-CmContains @('ARMED','ACTIVE','BLOCKED') $ExecutionState) 'INVALID_TRANSITION'
            $out.allowed=$true;$out.authorization_status='PAUSED';$out.execution_state='BLOCKED';$out.next_action='PERSIST_CHECKPOINT';return [pscustomobject]$out
        }
        if ((Test-CmContains (@('ACTIVATE','RESUME')) ($Event))) {
            if ((Test-CmEqual ($Event) ('ACTIVATE'))) { Assert-Cm ((Test-CmEqual ($ExecutionState) ('ARMED'))) 'INVALID_TRANSITION' }
            Assert-CmGate $Context.pre_write_gate $Context.authorization_id $Context.next_milestone_id $Context.actual_head_sha $true $Context.next_work_order_id
            Assert-CmGateRuntime $Context.pre_write_gate $Context.runtime
            $out.allowed=$true; $out.authorization_status='ACTIVE'; $out.execution_state='ACTIVE'; $out.next_action='ISSUE_BUILDER_LEASE'; $out.writes_allowed=$true; return [pscustomobject]$out
        }
        Assert-Cm ((Test-CmEqual $ExecutionState 'ACTIVE') -or ((Test-CmEqual $Event 'WAVE_END') -and (Test-CmEqual $ExecutionState 'BLOCKED') -and ($Context.stop_gate_reached -or $Context.scope_exhausted))) 'INVALID_TRANSITION'
        Assert-Cm ((Test-CmContains (@('LOW','MEDIUM','HIGH')) ($Context.risk_level))) 'UNKNOWN_RISK'
        $medium=if (@($Context.validation_plan | Where-Object {(Test-CmEqual ($_.tier) ('ROLLBACK'))}).Count -gt 0) {'ROLLBACK'} else {'UPGRADE_DOWNGRADE'}
        $risk=Resolve-PfcRiskValidationPlan $Context.risk_level @() $medium @{max_wave_size=5}
        Assert-Cm $risk.allowed 'UNKNOWN_RISK'
        Assert-CmValidation $Context.validation_plan $risk.required_milestone_tiers $true $Context.candidate_sha $Context.validation_observations
        Assert-Cm ((Test-CmEqual ($Context.milestone_state) ('ACCEPTED')) -and (Test-CmSha $Context.candidate_sha) -and (Test-CmEqual ($Context.candidate_sha) ($Context.evidence_sha)) -and (Test-CmEqual ($Context.candidate_sha) ($Context.acceptance_sha))) 'ACCEPTANCE_MISMATCH'
        Assert-CmFreshReview $Context.independent_review $Context.candidate_sha
        Assert-CmGate $Context.current_pre_write_gate $Context.authorization_id $Context.milestone_id $Context.current_builder_start_sha $true $Context.current_work_order_id
        Assert-CmGate $Context.pre_review_gate $Context.authorization_id $Context.milestone_id $Context.candidate_sha $false $Context.current_work_order_id
        Assert-CmControlDescendant $Context.ancestry $Context.diffs $Context.candidate_sha $Context.accepted_checkpoint_sha $Context.control_paths
        Assert-CmControlDescendant $Context.ancestry $Context.diffs $Context.accepted_checkpoint_sha $Context.actual_head_sha $Context.control_paths
        Assert-CmArray $Context.frozen_wave.milestone_ids; Assert-CmArray $Context.accepted_milestone_ids
        Assert-Cm ((Test-CmEqual ($Context.frozen_wave.authorization_id) ($Context.authorization_id)) -and (Test-CmEqual ($Context.frozen_wave.wave_id) ($Context.wave_id)) -and (Test-CmId $Context.wave_id)) 'WAVE_MISMATCH'
        $ids=$Context.frozen_wave.milestone_ids
        Assert-Cm ($ids.Count -gt 0 -and $ids.Count -le $risk.max_wave_size -and (Test-CmUnique $ids)) 'WAVE_MISMATCH'
        foreach ($id in $ids) { Assert-Cm (Test-CmId $id) }
        if ((Test-CmEqual ($Event) ('NEXT_MILESTONE'))) {
            Assert-Cm ((-not (Test-CmEqual ($Context.risk_level) ('HIGH'))) -and (Test-CmContains (@('LOW','MEDIUM')) ($Context.next_risk_level))) 'HIGH_REQUIRES_USER_GATE'
            Assert-Cm ((Test-CmEqual ($Context.next_base_sha) ($Context.accepted_checkpoint_sha))) 'BASELINE_DRIFT'
            $position=Get-CmOrdinalIndex $ids $Context.milestone_id
            Assert-Cm ($position -ge 0 -and $position+1 -lt $ids.Count -and (Test-CmEqual ($ids[$position+1]) ($Context.next_milestone_id))) 'NEXT_MILESTONE_OUTSIDE_WAVE'
            Assert-CmArray $Context.frozen_wave.dependencies
            foreach ($dependency in $Context.frozen_wave.dependencies) { Assert-Cm ((Test-CmId $dependency) -and (Test-CmContains ($Context.accepted_milestone_ids) ($dependency))) 'DEPENDENCY_NOT_ACCEPTED' }
            Assert-CmGate $Context.pre_write_gate $Context.authorization_id $Context.next_milestone_id $Context.actual_head_sha $true $Context.next_work_order_id
            Assert-CmGateRuntime $Context.pre_write_gate $Context.runtime
            $out.allowed=$true; $out.next_action='START_NEXT_MILESTONE'; $out.writes_allowed=$true; return [pscustomobject]$out
        }
        Assert-CmArray $Context.wave_milestones
        Assert-Cm ($Context.wave_milestones.Count -eq $ids.Count) 'WAVE_SUMMARY_INCOMPLETE'
        for ($i=0; $i -lt $ids.Count; $i++) {
            $item=$Context.wave_milestones[$i]
            Assert-Cm ((Test-CmEqual ($item.milestone_id) ($ids[$i])) -and (Test-CmEqual ($item.result) ('PASS')) -and (Test-CmSha $item.candidate_sha) -and (Test-CmEqual ($item.candidate_sha) ($item.evidence_sha)) -and (Test-CmEqual ($item.candidate_sha) ($item.acceptance_sha))) 'WAVE_SUMMARY_INCOMPLETE'
            Assert-CmControlDescendant $Context.ancestry $Context.diffs $item.candidate_sha $item.accepted_checkpoint_sha $Context.control_paths
        }
        Assert-Cm ((Test-CmEqual ($Context.wave_milestones[-1].accepted_checkpoint_sha) ($Context.accepted_checkpoint_sha))) 'WAVE_SUMMARY_INCOMPLETE'
        $out.next_action='BLOCK_WAVE'
        if ((Test-CmEqual ($Context.wave_t3.result) ('FAIL'))) {
            $links=Get-CmField $Context t3_failure_links; Assert-CmArray $links
            $linked=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($link in $links) { Assert-Cm ((Test-CmContains ($ids) ($link.milestone_id)) -and (Test-CmEqual ($link.checkpoint_sha) ($Context.accepted_checkpoint_sha)) -and (Test-CmText $link.evidence_reference)); Assert-CmBool $link.observed $true; [void]$linked.Add($link.milestone_id) }
            if ($linked.Count -gt 0) { $out.next_action='REOPEN_LINKED_MILESTONES'; $out.reopen_milestone_ids=@($ids | Where-Object {$linked.Contains($_)}) }
            throw [ArgumentException]::new('WAVE_T3_FAILED')
        }
        Assert-CmValidation @($Context.wave_t3) @('T3') $true $Context.accepted_checkpoint_sha $Context.validation_observations
        Assert-CmFreshReview $Context.wave_verifier $Context.accepted_checkpoint_sha
        $out.next_action='PERSIST_WAVE_SUMMARY'
        Assert-CmBool $Context.wave_persistence.observed $true
        Assert-Cm ((Test-CmEqual ($Context.wave_persistence.wave_id) ($Context.wave_id)) -and (Test-CmEqual ($Context.wave_persistence.final_checkpoint_sha) ($Context.accepted_checkpoint_sha)) -and (Test-CmEqual ($Context.wave_persistence.control_commit_sha) ($Context.actual_head_sha)) -and (Test-CmText $Context.wave_persistence.summary_reference)) 'WAVE_SUMMARY_NOT_PERSISTED'
        # Ordering is material: persisted T3 -> Stop Gate -> exhaustion -> recheck.
        Assert-Cm ($Context.stop_gate_reached -is [bool] -and $Context.scope_exhausted -is [bool])
        if ($Context.stop_gate_reached) { $out.allowed=$true; $out.authorization_status='EXHAUSTED'; $out.execution_state='STOP_GATE_REACHED'; $out.next_action='STOP_GATE_REACHED'; $out.requires_user_decision=$true; return [pscustomobject]$out }
        if ($Context.scope_exhausted) { $out.allowed=$true; $out.authorization_status='EXHAUSTED'; $out.execution_state='COMPLETED'; $out.next_action='COMPLETED'; return [pscustomobject]$out }
        foreach ($flag in @('authorization_rechecked','contract_rechecked','known_limitations_rechecked','hard_stop_rechecked')) { Assert-CmBool (Get-CmField $Context $flag) $true }
        Assert-Cm ((-not (Test-CmEqual ($Context.risk_level) ('HIGH')))) 'HIGH_REQUIRES_USER_GATE'
        $out.allowed=$true; $out.execution_state='ARMED'; $out.next_action='SELECT_NEXT_WAVE'
    } catch {
        $out.allowed=$false; $out.writes_allowed=$false; $out.execution_state='BLOCKED'; $out.reasons=@(Get-CmReason $_)
        if (Test-CmContains $out.reasons 'RECOVERY_REQUIRED') { $out.readiness='RECOVERY_REQUIRED'; $out.authorization_status='INVALIDATED'; $out.requires_user_decision=$true }
        if (Test-CmContains @('BLOCKING_FINDINGS','REPAIR_LOOP_STOPPED','HARD_STOP_REQUIRES_USER','IRREVERSIBLE_ACTION_PENDING','ESSENTIAL_SPECIALIST_ACTIVE') $out.reasons[0]) { $out.authorization_status='INVALIDATED'; $out.requires_user_decision=$true; $out.next_action='REQUEST_REAUTHORIZATION' }
        if ((Test-CmContains @('INVALIDATED','EXHAUSTED','SUSPENDED_BY_RUNTIME_ROLLBACK') $AuthorizationStatus) -or (Test-CmContains @('STOP_GATE_REACHED','COMPLETED') $ExecutionState)) { $out.authorization_status=$AuthorizationStatus;$out.execution_state=$ExecutionState;$out.requires_user_decision=$true }
    }
    [pscustomobject]$out
}
Export-ModuleMember -Function Get-PfcRepositoryIdentityV1, Get-PfcRepoPathSetIdentityV1, Get-PfcWorktreeIdentityV1, Test-PfcPreWriteIdentityGate, Test-PfcPreReviewIdentityGate, Resolve-PfcRiskValidationPlan, Resolve-PfcIssueDisposition, Test-PfcRepairBudget, Test-PfcContinuousTransition
