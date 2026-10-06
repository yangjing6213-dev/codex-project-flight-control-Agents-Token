# Message Contracts

## V2 control field semantics

The following are nested structures of existing messages, never new formal message families: `CONTINUOUS_AUTHORIZATION`, `PRE_WRITE_IDENTITY_GATE`, `PRE_REVIEW_IDENTITY_GATE`, `RISK_PROFILE`, `VALIDATION_PLAN`, `ISSUE_CLASSIFICATION`, `WAVE_SUMMARY`, `CONTINUATION_CHECKPOINT`. Goalkeeper remains the only control-file writer. `project.md` is the fixed `PROJECT_CONTROL_REPORT` renderer; its existing project metadata remains available. No seventh report template or project-control-report schema exists.

All five machine objects have strict roots and strict nested objects: every property is required and unknown properties are rejected. The root paths below are authoritative; schemas and templates project them. The additional nested spelling, ID grammar and sentinels below are V2 serialization choices for design sections 33–40, not new permission or workflow grants.

The V2 validation boundary recursively checks exact case-sensitive property and required names, including object array items, before using the frozen V1 value checker. Anchored identities use the local .NET engine's true end-of-input `\z`, so trailing LF or CRLF is never part of a valid SHA, hash, ID or sentinel. Git source branches, exact milestone branches and namespace prefixes must additionally pass read-only `git check-ref-format --branch`; a returned expansion is not the exact requested branch. Recovery correspondence compares canonical path elements and counts, never delimiter-joined text; commas remain legal path characters. Each Markdown machine-object renderer contains exactly one complete JSON fence.

- `schema_version` is exactly `pfc.<asset-name>.v1` for each named schema below. This is a control format version, not a package version.
- IDs (including authorization, goal, milestone, contract, run, wave, decision, evidence and recovery references) use uppercase alphanumeric segments separated by hyphens, e.g. `AUTH-20260920-001`, `A-015`. Versions and lease epochs are positive integers.
- Commit SHAs are exactly 40 lowercase hexadecimal characters; identities and path/file hashes are exactly 64 lowercase hexadecimal characters. All-zero examples are visibly synthetic and must be replaced with observed facts. Shape validity does not prove Git ancestry, identity computation, evidence existence, authorization, or file preservation.
- Reference text, evidence descriptions and check descriptions must contain non-whitespace text. UTC timestamps use valid calendar dates in `yyyy-MM-ddTHH:mm:ssZ`. Windows PowerShell's JSON decoder automatically materializes these as DateTime; asset checks restore the two known timestamp slots to UTC strings before invoking the unchanged schema shape validator, and check their original serialization explicitly.
- Relative manifest paths are normalized lowercase Unicode NFC repository/package-relative paths with slash-separated nonempty segments. Unicode names and spaces are supported; absolute paths, backslashes, control characters, colons and dot/traversal segments are rejected. Branches must be valid Git-style refs; milestone branches lie within the exact approved namespace.
- Lists stated as sets must contain no duplicates. Schema uses only the frozen validator's supported scalar types, enum, pattern, object and array subset. Bounds use integer enums when finite. Positive integers, calendar dates, cardinality, uniqueness, applicability and cross-field relations are checked by `Test-PfcV2ControlSemantics` in StaticChecks, not by unsupported anyOf/nullable/min/max/format behavior.

### Authorization meaning

`authorization_status`: ACTIVE, PAUSED, INVALIDATED, SUSPENDED_BY_RUNTIME_ROLLBACK, EXHAUSTED. Runtime states (DISABLED, ARMED, ACTIVE, BLOCKED, STOP_GATE_REACHED, COMPLETED) belong in STATUS/report summaries. `execution_policy` is CONTINUOUS, and `invocation_mode` is START or RESUME only. CONTINUOUS_MODE is not a fifth invocation mode.

`goal` binds goal_id and goal_version. `scope` binds type=MILESTONE_RANGE, inclusive from/to milestone IDs, and stop_gate. IDs are not lexically ordered; scope membership is checked against the approved roadmap.

`repository` binds identity_algorithm=PFC_GIT_COMMON_DIR_SHA256_V1, repository_identity, authorized_base_checkpoint_sha, source_branch, write_branch_policy=MILESTONE_WORKTREE_ONLY, write_branch_namespace=`codex/pfc/<authorization_id>/`, default_branch_write=false. Source branch describes the baseline only. `paths` binds hash_algorithm=PFC_REPO_PATH_SET_SHA256_V1 and writable_paths_hash/forbidden_paths_hash to the normalized approved path sets. Worktree identity uses PFC_WORKTREE_ROOT_SHA256_V1 and the Goalkeeper registry.

`permissions` consists of the five explicit boolean approvals local_commit, existing_dependency_use, planned_dependency_install, non_destructive_migration and automatic_repair. A true value is meaningful only within actual user approval. `limits` uses max_wave_size=1..5, max_builder_code_repair_attempts=0..2, max_auto_rework_rounds=0..2, max_candidate_revisions=1..3, max_consecutive_blocked_milestones=1. Lower limits are conservative serialization choices; risk caps still apply.

Every `forbidden` property is true: push, merge, release, deploy, destructive_migration, administrator_action, paid_action, cross_project_write. `approval` has approved_by=USER, approved_at and source_decision_id. `invalidation_triggers` contains exactly once each CONTRACT_CHANGE, AUTHORIZED_SCOPE_EXHAUSTED, STOP_GATE_REACHED, BASELINE_DRIFT, BRANCH_CHANGE, UNKNOWN_DIRTY_WORKTREE, USER_PAUSE, HARD_BLOCKER, GOAL_CHANGE.

Authorization must not contain control_run_id, lease_epoch, current wave or current milestone. Every START/RESUME generates runtime Control Run ID and Lease Epoch in STATUS/Continuation Checkpoint; stable authorization is not regenerated as a runtime lease.

### Wave and validation meaning

Wave Plan freezes one ordered, nonempty list of distinct `milestones`; each entry binds milestone_id, contract_id/version, risk_level, dependencies, exact_branch, worktree_identity_algorithm/identity and validation_plan. Dependencies are milestone IDs; a same-Wave dependency must precede its consumer. External dependencies must already be accepted before selection. LOW cap is five, any MEDIUM cap is three, and HIGH requires a single item. `base_checkpoint_sha` is this Wave's accepted chain start; future milestone bases are determined only after the previous acceptance, never fabricated during planning.

A `VALIDATION_PLAN` is an array of validation records. `wave_validation` and `t3_result` use the same record with tier=T3. Each record has tier (T1, T2, T3, T4, ROLLBACK, UPGRADE_DOWNGRADE, FAULT_INJECTION, USER_GATE), required (boolean), applicability_reason (nonempty), checks (nonempty command/action strings when required), result (only PASS, FAIL, PARTIAL, NOT_RUN), evidence (array of evidence_id, candidate_sha, reference objects). Evidence binds the actual tested Candidate; PASS requires evidence. A non-applicable validation uses `required: false`, nonempty `applicability_reason`, and normally NOT_RUN; never use N/A as a fifth result.

Each milestone requires T1 and T2; MEDIUM additionally requires the contract-selected ROLLBACK or UPGRADE_DOWNGRADE; HIGH requires T1–T4, FAULT_INJECTION and USER_GATE. Every Wave requires T3. Tier checks retain the approved minimum evidence: T1 focused tests/lint/scope/secret scan; T2 affected regressions/type/build/Git/staged whitelist; T3 full applicable tests/lint/type/build, cross-module smoke and fresh Wave Verifier; T4 E2E/recovery/fault injection/real project/data integrity/security stop. A schema-valid optional record cannot waive required risk-policy validation. Automatic advance requires every required result PASS plus all approved gates.

### Checkpoint and recovery meaning

`previous_accepted_checkpoint_sha` is a SHA or FIRST_MILESTONE only when no previous milestone exists. `current_milestone_base_sha` equals the authorization chain start for the first item or the previous Accepted Checkpoint otherwise. `expected_builder_start_sha` is the precise lease HEAD and may differ from Base: no-Candidate resume allows Base or a permitted control-only successor; Candidate rework allows current Candidate or a permitted control-only successor. Actual HEAD must equal Expected Start; Git ancestry and control-only diffs remain runtime identity-gate proofs.

`repair_budget` persists builder_code_repair_attempts (0..2 for the current failure path), auto_rework_rounds (0..2) and candidate_revisions (0..3). These independent counters never reset on RESUME/control records. Zero Candidate revisions means none frozen; R1/R2/R3 are the only Candidates.

`recovery_manifest` has recovery_package_reference (ID of an actual repository-external recovery package), git_status (ordered records of path, original_path and exact two-character Git porcelain status), files (path, sha256, size_bytes, recovery_copy, classification) and allowed_paths. `original_path` is NONE except rename/copy records, where it records the original relative path. `recovery_copy` is the package-relative preserved byte copy; size_bytes is a nonnegative integer. Classification is ACTIVE, HISTORICAL or UNKNOWN. Changed paths must have exactly one file entry and be within allowed_paths; rename/copy original paths must also be allowed and preserved. Duplicate path/copy entries are rejected. Clean inventories may have empty arrays but still reference their recovery package. Deletions must refer to preserved pre-deletion bytes; a manifest without copies is insufficient. UNKNOWN materials stay preserved and require RECOVERY_REQUIRED; schema validity never authorizes mutation or removal.

### Issue and immutable Wave outcome meaning

Issue Classification binds classification (the eight approved design classes), evidence (nonempty observed descriptions/references), affected_scope (nonempty IDs), blocking_scope (NONE, MILESTONE, WAVE, GLOBAL), fallback_reference (approved registered ID or NONE) and next_action (REPAIR, BLOCK_VERIFICATION, FREEZE_CONTROL, USE_APPROVED_FALLBACK, CONTINUE, STOP, PAUSE_COLLECT_EVIDENCE). These last two enums are serialization choices. PRODUCT_DEFECT requires MILESTONE/REPAIR; CONTROL_PLANE_DEFECT requires GLOBAL/FREEZE_CONTROL; SECURITY_OR_DATA_RISK requires GLOBAL/STOP; UNCLASSIFIED requires blocking and PAUSE_COLLECT_EVIDENCE. TEST_INFRASTRUCTURE_DEFECT may CONTINUE only with explicit independent product evidence and a registered fallback; otherwise BLOCK_VERIFICATION. KNOWN_ENVIRONMENT_LIMITATION and EXTERNAL_DEPENDENCY_FAILURE may use only a registered approved fallback and its review trigger; without one they block. DOCUMENTATION_ONLY may repair within budget; after Candidate freeze any non-governance tracked edit requires a new Candidate.

Wave Report renders immutable WAVE_SUMMARY: each milestone records milestone_id, candidate_sha, evidence_sha, acceptance_sha, accepted_checkpoint_sha and result. On PASS, Candidate/Evidence/Acceptance SHA must agree; the accepted checkpoint may be a later governance commit. `final_checkpoint_sha` is the last PASS milestone's accepted checkpoint, or base_checkpoint_sha when no item was accepted. `t3_result` binds evidence to final_checkpoint_sha. `stop_gate_result` binds stop_gate and reached. `next_action` is STOP_GATE_REACHED, COMPLETED, SELECT_NEXT_WAVE, BLOCKED or PAUSE. SELECT_NEXT_WAVE/COMPLETED require all milestone results and T3 PASS and no reached Stop Gate; STOP_GATE_REACHED requires reached=true and T3 PASS. These are outcome records, not authority to bypass authorization/identity/convergence/Specialist/user gates. Ending a Wave does not rewrite its frozen outcome or retrospectively alter its plan.

### Human-readable projections

For TEST_INFRASTRUCTURE_DEFECT continuation, an evidence entry begins with `INDEPENDENT_PRODUCT_EVIDENCE: ` followed by the independent evidence reference. This explicit serialization marker does not prove independence; Verifier must inspect the referenced evidence and the registered fallback. No result string can substitute for that check.

The binding table below lists only additional top-level fields for existing templates and exact roots for new templates. Existing formal envelopes remain mandatory. V1/default rendering uses NOT_APPLICABLE for continuous-only fields, Execution Policy=PAUSE_AFTER_MILESTONE and Continuous Execution State=DISABLED; it creates no continuous control files.

STATUS references Canonical Project Sources instead of copying Authorization. Authorized Scope, Stop Gate, Current Wave ID / State / Progress, Current Risk Level, Validation Tier, Known Limitation IDs, Repair Budget Used / Remaining, Consecutive Blocked Count, Continuation Checkpoint and Next Automatic Action summarize the canonical facts. PROJECT_CONTROL_REPORT renders the same categories as the fixed end receipt; summaries never become duplicate fact authorities.

WORK_ORDER binds Authorization ID, Wave ID, Risk (RISK_PROFILE risk_level and evidence basis), Validation Plan, repository/worktree/branch identities, the three runtime SHA slots and authorized base, both path hashes, Pre-write Identity Gate, Repair Budget, Stop Conditions and Known Limitation / Fallback ID. Pre-write gate summary records PASS or STOP_BEFORE_WRITE plus compared identity fields/evidence; PASS is PRE_WRITE_IDENTITY_GATE_PASS. It cannot depend on a nonexistent Candidate or Verifier.

BUILD_REPORT's Builder Echo repeats the Work Order identity projection plus Work Order/Milestone/Contract/Goal IDs and versions, Control Run ID, Lease Epoch, Actual Worktree HEAD, Risk and Validation Plan before any business write. Issue Classification uses the nested object above; Repair Attempts uses the independent budget; Tier Results uses validation records; Wave Impact and Automatic Continuation Eligibility record evidence and blockers. The Builder cannot self-authorize the next milestone.

VERIFY_ORDER binds Authorization ID/Status, Wave ID, Work Order ID, Risk, Validation Plan, Repository Identity, Path Policy (actual Changed Files against approved paths/hashes), Builder Evidence SHA, Acceptance Record Target and Wave Impact Checks. Pre-review gate verifies these plus Goal/Milestone, Verify Order ID, Base/Candidate SHA and Validation Tier. Its success is PRE_REVIEW_IDENTITY_GATE_PASS; mismatch is CONTROL_PLANE_DEFECT and no technical acceptance starts.

REVIEW_REPORT records both identity gate results, Classification Confirmation, Evidence Freshness (current Candidate binding), Milestone Continuation Eligibility, Wave Impact and Stop Gate Impact. DECISION's Continue Automatically is a boolean decision after all gates; Pause Reason is evidence or NOT_APPLICABLE, Authorization Status uses the stable enum, Next Milestone is an approved ID or NOT_APPLICABLE, and Next Wave Action references the ordered T3/Stop Gate/exhaustion/recheck/selection transition.

KNOWN-LIMITATIONS entries use ID, Classification (approved issue enum), Evidence, Fallback (registered ID or NONE), Blocking (boolean), Review Trigger and Resolution Condition. BLOCKER-FALLBACK-MATRIX entries use Capability (stable reference ID), Primary Path, Failure Signal, Approved Fallback (registered ID or NONE), Blocks Milestone/Blocks Phase (booleans) and Review Trigger. Repeated tasks reference IDs and only re-investigate when the trigger fires.

### continuous-authorization

Required root fields: `schema_version`, `authorization_id`, `authorization_status`, `execution_policy`, `invocation_mode`, `goal`, `scope`, `repository`, `paths`, `permissions`, `limits`, `forbidden`, `approval`, `invalidation_triggers`.

Exact property paths (all object properties required): `schema_version`, `authorization_id`, `authorization_status`, `execution_policy`, `invocation_mode`, `goal`, `goal.goal_id`, `goal.goal_version`, `scope`, `scope.type`, `scope.from`, `scope.to`, `scope.stop_gate`, `repository`, `repository.identity_algorithm`, `repository.repository_identity`, `repository.authorized_base_checkpoint_sha`, `repository.source_branch`, `repository.write_branch_policy`, `repository.write_branch_namespace`, `repository.default_branch_write`, `paths`, `paths.hash_algorithm`, `paths.writable_paths_hash`, `paths.forbidden_paths_hash`, `permissions`, `permissions.local_commit`, `permissions.existing_dependency_use`, `permissions.planned_dependency_install`, `permissions.non_destructive_migration`, `permissions.automatic_repair`, `limits`, `limits.max_wave_size`, `limits.max_builder_code_repair_attempts`, `limits.max_auto_rework_rounds`, `limits.max_candidate_revisions`, `limits.max_consecutive_blocked_milestones`, `forbidden`, `forbidden.push`, `forbidden.merge`, `forbidden.release`, `forbidden.deploy`, `forbidden.destructive_migration`, `forbidden.administrator_action`, `forbidden.paid_action`, `forbidden.cross_project_write`, `approval`, `approval.approved_by`, `approval.approved_at`, `approval.source_decision_id`, `invalidation_triggers`.

### wave-plan

Required root fields: `schema_version`, `wave_id`, `authorization_id`, `base_checkpoint_sha`, `goal_id`, `stop_gate`, `milestones`, `wave_validation`.

Exact property paths (all object properties required): `schema_version`, `wave_id`, `authorization_id`, `base_checkpoint_sha`, `goal_id`, `stop_gate`, `milestones`, `milestones[].milestone_id`, `milestones[].contract_id`, `milestones[].contract_version`, `milestones[].risk_level`, `milestones[].dependencies`, `milestones[].exact_branch`, `milestones[].worktree_identity_algorithm`, `milestones[].worktree_identity`, `milestones[].validation_plan`, `milestones[].validation_plan[].tier`, `milestones[].validation_plan[].required`, `milestones[].validation_plan[].applicability_reason`, `milestones[].validation_plan[].checks`, `milestones[].validation_plan[].result`, `milestones[].validation_plan[].evidence`, `milestones[].validation_plan[].evidence[].evidence_id`, `milestones[].validation_plan[].evidence[].candidate_sha`, `milestones[].validation_plan[].evidence[].reference`, `wave_validation`, `wave_validation.tier`, `wave_validation.required`, `wave_validation.applicability_reason`, `wave_validation.checks`, `wave_validation.result`, `wave_validation.evidence`, `wave_validation.evidence[].evidence_id`, `wave_validation.evidence[].candidate_sha`, `wave_validation.evidence[].reference`.

### continuation-checkpoint

Required root fields: `schema_version`, `authorization_id`, `control_run_id`, `lease_epoch`, `wave_id`, `milestone_id`, `previous_accepted_checkpoint_sha`, `current_milestone_base_sha`, `expected_builder_start_sha`, `repair_budget`, `recovery_manifest`, `updated_at`.

Exact property paths (all object properties required): `schema_version`, `authorization_id`, `control_run_id`, `lease_epoch`, `wave_id`, `milestone_id`, `previous_accepted_checkpoint_sha`, `current_milestone_base_sha`, `expected_builder_start_sha`, `repair_budget`, `repair_budget.builder_code_repair_attempts`, `repair_budget.auto_rework_rounds`, `repair_budget.candidate_revisions`, `recovery_manifest`, `recovery_manifest.recovery_package_reference`, `recovery_manifest.git_status`, `recovery_manifest.git_status[].path`, `recovery_manifest.git_status[].original_path`, `recovery_manifest.git_status[].status`, `recovery_manifest.files`, `recovery_manifest.files[].path`, `recovery_manifest.files[].sha256`, `recovery_manifest.files[].size_bytes`, `recovery_manifest.files[].recovery_copy`, `recovery_manifest.files[].classification`, `recovery_manifest.allowed_paths`, `updated_at`.

### issue-classification

Required root fields: `schema_version`, `classification`, `evidence`, `affected_scope`, `blocking_scope`, `fallback_reference`, `next_action`.

Exact property paths (all object properties required): `schema_version`, `classification`, `evidence`, `affected_scope`, `blocking_scope`, `fallback_reference`, `next_action`.

### wave-report

Required root fields: `schema_version`, `wave_id`, `authorization_id`, `base_checkpoint_sha`, `final_checkpoint_sha`, `milestones`, `t3_result`, `stop_gate_result`, `next_action`.

Exact property paths (all object properties required): `schema_version`, `wave_id`, `authorization_id`, `base_checkpoint_sha`, `final_checkpoint_sha`, `milestones`, `milestones[].milestone_id`, `milestones[].candidate_sha`, `milestones[].evidence_sha`, `milestones[].acceptance_sha`, `milestones[].accepted_checkpoint_sha`, `milestones[].result`, `t3_result`, `t3_result.tier`, `t3_result.required`, `t3_result.applicability_reason`, `t3_result.checks`, `t3_result.result`, `t3_result.evidence`, `t3_result.evidence[].evidence_id`, `t3_result.evidence[].candidate_sha`, `t3_result.evidence[].reference`, `stop_gate_result`, `stop_gate_result.stop_gate`, `stop_gate_result.reached`, `next_action`.

## V2 Template Bindings

This single JSON table is the field projection authority consumed by static checks. YAML templates use JSON-compatible YAML 1.2 syntax; Markdown control objects use one JSON fence. Examples are synthetic, not executable approvals.

```json
{
  "existing": {
    "project": [
      "Mode",
      "Overall Result",
      "Goal",
      "Goal Alignment",
      "Goal State",
      "Current Milestone",
      "Milestone State",
      "Completed",
      "Changed",
      "Evidence",
      "Verification",
      "Scope Change",
      "Roadmap Change",
      "Efficiency Exception",
      "Convergence",
      "Specialist Capability",
      "Specialist Task",
      "Specialist Order / Report",
      "Blockers",
      "Residual Risks",
      "Pending Decisions",
      "Next Recommended Action",
      "Accepted Milestones",
      "Remaining Known Milestones",
      "Remaining Work Forecast",
      "Forecast Confidence",
      "Latest Candidate SHA",
      "Goal Code SHA",
      "Goal Checkpoint SHA",
      "Last Accepted Checkpoint SHA",
      "Project Control Files Updated",
      "Builder Thread",
      "Verifier Thread",
      "Specialist Thread",
      "Builder Worktree",
      "Verifier Worktree",
      "Specialist Worktree",
      "Cleanup Result",
      "Execution Policy",
      "Continuous Authorization ID / Status",
      "Continuous Execution State",
      "Current Wave ID / State / Progress",
      "Validation Tier",
      "Current Risk Level",
      "Pre-write Identity Gate",
      "Pre-review Identity Gate",
      "Known Limitation IDs",
      "Repair Budget Used / Remaining",
      "Stop Gate",
      "Next Automatic Action"
    ],
    "status": [
      "Canonical Project Sources",
      "Execution Policy",
      "Continuous Authorization ID / Status",
      "Continuous Execution State",
      "Authorized Scope",
      "Stop Gate",
      "Current Wave ID / State / Progress",
      "Current Risk Level",
      "Validation Tier",
      "Pre-write Identity Gate",
      "Pre-review Identity Gate",
      "Known Limitation IDs",
      "Repair Budget Used / Remaining",
      "Consecutive Blocked Count",
      "Continuation Checkpoint",
      "Next Automatic Action"
    ],
    "work-order": [
      "Authorization ID",
      "Wave ID",
      "Risk",
      "Validation Plan",
      "Repository Identity",
      "Worktree Identity",
      "Exact Branch",
      "Authorized Base Checkpoint SHA",
      "Previous Accepted Checkpoint SHA",
      "Current Milestone Base SHA",
      "Expected Builder Start SHA",
      "Writable Path Hash",
      "Forbidden Path Hash",
      "Pre-write Identity Gate",
      "Repair Budget",
      "Stop Conditions",
      "Known Limitation / Fallback ID"
    ],
    "build-report": [
      "Builder Echo",
      "Issue Classification",
      "Repair Attempts",
      "Tier Results",
      "Wave Impact",
      "Automatic Continuation Eligibility"
    ],
    "verify-order": [
      "Authorization ID",
      "Authorization Status",
      "Wave ID",
      "Work Order ID",
      "Risk",
      "Validation Plan",
      "Repository Identity",
      "Path Policy",
      "Builder Evidence SHA",
      "Acceptance Record Target",
      "Pre-review Identity Gate",
      "Wave Impact Checks"
    ],
    "review-report": [
      "Pre-write Identity Gate",
      "Pre-review Identity Gate",
      "Classification Confirmation",
      "Evidence Freshness",
      "Milestone Continuation Eligibility",
      "Wave Impact",
      "Stop Gate Impact"
    ],
    "decisions": [
      "Continue Automatically",
      "Pause Reason",
      "Authorization Status",
      "Next Milestone",
      "Next Wave Action"
    ]
  },
  "created": {
    "continuous-authorization.yaml": [
      "schema_version",
      "authorization_id",
      "authorization_status",
      "execution_policy",
      "invocation_mode",
      "goal",
      "scope",
      "repository",
      "paths",
      "permissions",
      "limits",
      "forbidden",
      "approval",
      "invalidation_triggers"
    ],
    "wave-plan.yaml": [
      "schema_version",
      "wave_id",
      "authorization_id",
      "base_checkpoint_sha",
      "goal_id",
      "stop_gate",
      "milestones",
      "wave_validation"
    ],
    "continuation-checkpoint.md": [
      "schema_version",
      "authorization_id",
      "control_run_id",
      "lease_epoch",
      "wave_id",
      "milestone_id",
      "previous_accepted_checkpoint_sha",
      "current_milestone_base_sha",
      "expected_builder_start_sha",
      "repair_budget",
      "recovery_manifest",
      "updated_at"
    ],
    "wave-report.md": [
      "schema_version",
      "wave_id",
      "authorization_id",
      "base_checkpoint_sha",
      "final_checkpoint_sha",
      "milestones",
      "t3_result",
      "stop_gate_result",
      "next_action"
    ],
    "known-limitations.md": [
      "ID",
      "Classification",
      "Evidence",
      "Fallback",
      "Blocking",
      "Review Trigger",
      "Resolution Condition"
    ],
    "blocker-fallback-matrix.md": [
      "Capability",
      "Primary Path",
      "Failure Signal",
      "Approved Fallback",
      "Blocks Milestone",
      "Blocks Phase",
      "Review Trigger"
    ]
  }
}
```


`message-contracts.md` is the only field-definition authority. Templates are render shapes; they do not define state transitions or role authority.

## Common envelope

Every formal message includes these labels: `Control Run ID`, `Lease Epoch`, `Goal ID`, `Goal Version`, `Milestone ID`, `Milestone Contract Version`, `Revision`, `Sender Role`, `Recipient Role`, `Created At`, and the applicable `Base SHA`, `Candidate SHA`, or `Evidence SHA`. Empty values are `NOT_APPLICABLE`, `UNKNOWN`, or `NOT_RUN`.

## Formal message types

`WORK_ORDER`, `BUILD_REPORT`, `VERIFY_ORDER`, `REVIEW_REPORT`, `REWORK_ORDER`, `CHANGE_REQUEST`, `STATE_CORRECTION_REQUEST`, `ROADMAP_CHANGE_REQUEST`, `HUMAN_VERIFICATION_REQUEST`, `HUMAN_VERIFICATION_RESPONSE`, `DECISION_PACKET`, `DECISION`, `ACCEPTANCE_REPORT`, `FINAL_REVIEW_REPORT`, `PROJECT_CONTROL_REPORT`, `SPECIALIST_REQUEST`, `SPECIALIST_ORDER`, and `SPECIALIST_REPORT`.

`EFFICIENCY_EXCEPTION`, `DEBUGGING_SUMMARY`, `CONVERGENCE_SNAPSHOT`, `RESIDUAL_RISK`, and `EVIDENCE_RECORD` are nested structures, never additional message families.

Nested structures are rendered only when applicable; otherwise the field is `NOT_APPLICABLE`.

`EFFICIENCY_EXCEPTION`: `Trigger`, `Action`, `Reason`, `Affected Scope`.

`DEBUGGING_SUMMARY`: `Failure Signature`, `Reproduction`, `Evidence`, `Hypotheses Tested`, `Repair Attempts`, `Current Understanding`, `Remaining Unknown`, `Recommended Next Action`.

`CONVERGENCE_SNAPSHOT`: `Revision`, `Candidate SHA`, `Blocking Findings`, `Passed Criteria`, `Remaining Failed Criteria`, `Failure Signature`, `New Evidence Since Previous Revision`, `Trend`, `Next Authorized Action`.

`RESIDUAL_RISK`: `Risk`, `Why Non-blocking`, `Evidence Basis`, `Accepted By`, `Affected Scope`, `Future Action`.

## Required fields by message

### WORK_ORDER

`Work Order ID`, `Goal / Target Result`, `Authorized Scope`, `Non-goals / Forbidden Scope`, `Constraints`, `Dependencies`, `Acceptance Criteria`, `Base SHA`, `Required Verification`, `Relevant Baseline Observations`, `Relevant Evidence References`, `Known Risks`, `Expected Evidence`, `Revision`.

### BUILD_REPORT

`Work Order ID`, `Base SHA`, `Candidate SHA`, `Changed Files`, `Implemented Criteria`, `Commands Run`, `Observed Results`, `Verification Status`, `NOT_RUN Items`, `Known Limitations`, `Scope Deviations`, `Open Risks`, `Evidence IDs / Locations`, `Efficiency Exception`, `Debugging Summary`, `Convergence Inputs`. Each command records `Command`, `Working Directory`, `Candidate SHA`, `Exit Code`, `Observed Result`, `Covered Criteria`, `NOT_RUN Reason`, and `Evidence ID`.

### VERIFY_ORDER

`Verify Order ID`, `Acceptance Criteria`, `Constraints`, `Base SHA`, `Candidate SHA`, `Changed Files`, `Required Verification`, `Builder Evidence IDs`, `Known Risks`, `Relevant Specialist Order / Report IDs`, `Required Independent Checks`, `Revision`.

### REVIEW_REPORT

`Candidate SHA`, `Alignment Result`, `Evidence Integrity Result`, `Technical Result`, `Environment`, `Builder Evidence Reused`, `Independent Commands Run`, `Observed Results`, `Version Integrity`, `Findings`, `Residual Risks`, `Specialist Dependency Status`, `Verdict`.

### REWORK_ORDER

`Rework Order ID`, `Source Review Report ID`, `Candidate SHA`, `Required Repairs`, `Acceptance Criteria`, `Scope`, `Constraints`, `Verification After Repair`, `Revision`, `Repair Round`.

### SPECIALIST messages

`SPECIALIST_REQUEST` uses `Request ID`, `Requester`, `Question`, `Why Specialist Is Required`, `Decision Affected`, `Evidence SHA`, `Relevant Acceptance Criteria`, `Relevant Scope`, and `Known Evidence`.

`SPECIALIST_ORDER` uses `Specialist Order ID`, `Request ID`, `Specialist Perspective`, `Question`, `Decision Affected`, `Evidence SHA`, `Allowed Files / Symbols / Evidence`, `Known Evidence`, `Allowed Diagnostic Action`, `Evidence Round`, and `Required Output`.

`SPECIALIST_REPORT` uses the common envelope plus `Specialist Report ID`, `Specialist Order ID`, `Question`, and `Evidence SHA`. `FINDING` requires `Finding`, `Evidence`, `Risk`, `Recommendation`, `Confidence`, and `Diagnostics Run`. `EVIDENCE_NEEDED` requires `Missing Evidence`, `Why Required`, `Requested Scope`, `Requested Diagnostic`, and `Risk`; it may occur at most once. `UNRESOLVED` requires `Known`, `Unknown`, `Evidence Reviewed`, `Why Unresolved`, `Decision Risk`, and `Recommended Next Action`. Status is exactly `FINDING`, `EVIDENCE_NEEDED`, or `UNRESOLVED`; `ACCEPT`, `REWORK`, and `BLOCKED` are invalid and Specialist reports never carry formal verdict authority. An Order's Evidence SHA, Order ID, allowed scope, and Evidence Round `0`/`1` remain bound across the single supplementation.

### Human verification

`HUMAN_VERIFICATION_REQUEST`: `Verification ID`, `Related Acceptance Criterion`, `Candidate SHA`, `验证目的`, `前置条件`, `操作步骤`, `预期结果`, `失败表现`, `需要的证据`, `脱敏要求`, `证据有效期`.

`HUMAN_VERIFICATION_RESPONSE`: `Verification ID`, `Candidate SHA`, `Environment`, `Observed Result`, `Evidence`, `Unexpected Behavior`, `Result Claimed`.

### Decisions and reports

`DECISION_PACKET` carries `Decision Context`, `Options`, `Recommendation`, `Evidence Basis`, `Scope Impact`, `Roadmap Impact`, `Forecast Impact`, and `Next Authorized Action`.

`DECISION` carries `Decision`, `Evidence Basis`, `Required Repairs`, `Non-blocking Backlog Items`, `Residual Risk`, `Contract Change`, `Scope Impact`, `Roadmap Impact`, `Forecast Impact`, and `Next Authorized Action`.

`ACCEPTANCE_REPORT` and `FINAL_REVIEW_REPORT` carry `Overall Result`, `Goal Alignment`, `Milestone State`, `Verification`, `Blockers`, `Residual Risks`, `Base SHA`, `Candidate SHA`, `Goal Code SHA`, and `Goal Checkpoint SHA`.

`PROJECT_CONTROL_REPORT` is the fixed end receipt and carries `Mode`, `Overall Result`, `Control Run ID`, `Lease Epoch`, `Goal`, `Goal Version`, `Goal Alignment`, `Goal State`, `Current Milestone`, `Milestone Contract Version`, `Milestone State`, `Completed`, `Changed`, `Evidence`, `Verification`, `Scope Change`, `Roadmap Change`, `Efficiency Exception`, `Convergence`, `Specialist Capability`, `Specialist Task`, `Specialist Order / Report`, `Blockers`, `Residual Risks`, `Pending Decisions`, `Next Recommended Action`, `Accepted Milestones`, `Remaining Known Milestones`, `Remaining Work Forecast`, `Forecast Confidence`, `Base SHA`, `Latest Candidate SHA`, `Goal Code SHA`, `Goal Checkpoint SHA`, `Last Accepted Checkpoint SHA`, `Project Control Files Updated`, `Builder Thread`, `Verifier Thread`, `Specialist Thread`, `Builder Worktree`, `Verifier Worktree`, `Specialist Worktree`, and `Cleanup Result`.

## Evidence record

`EVIDENCE_RECORD` contains `Evidence ID`, `Candidate SHA`, `Candidate Timing` (`BEFORE_CANDIDATE` or `ON_CANDIDATE`), `Source`, `Command / Verification Action`, `Working Directory`, `Environment`, `Exit Code / Result Claimed`, `Observed Result`, `Covered Criteria`, `Created At`, and optional `Evidence Location`.
