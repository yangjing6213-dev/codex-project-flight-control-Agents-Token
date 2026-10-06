# Continuous execution

This reference owns the Continuous policy lifecycle and identity gates. [message-contracts.md](message-contracts.md) remains the only field-definition authority; the comparison lists below specify gate behavior, not a second schema. V1 role, worktree, evidence and final Goal audit rules remain in their existing references.

## Activation and Canonical Sources

Only explicit `$project-flight-control START CONTINUOUS_MODE` or `$project-flight-control RESUME CONTINUOUS_MODE` enables execution policy `CONTINUOUS`. `CONTINUOUS_MODE` is not a fifth top-level mode: START, RESUME, AUDIT and STATUS_ONLY remain the four modes. Without explicit activation, retain `PAUSE_AFTER_MILESTONE` and create no Authorization, Wave or Continuation files. STATUS_ONLY does not write or create agents.

Before creating control artifacts, Goalkeeper discovers and reuses an existing equivalent machine-readable Authorization or Wave source and registers its path in STATUS `Canonical Project Sources`. Only when no equivalent source exists, use `docs/project-control/CONTINUOUS-AUTHORIZATION.yaml` and `docs/project-control/WAVE-PLAN.yaml`; companion defaults are `KNOWN-LIMITATIONS.md`, `BLOCKER-FALLBACK-MATRIX.md` and `CONTINUATION-CHECKPOINT.md` in the same directory. Duplicate Authorization or Wave sources are `CONTROL_PLANE_DEFECT`: stop before any Builder Lease or write, reconcile the single authority, and do not select a convenient duplicate.

Goalkeeper is the only canonical control-file writer and formal dispatcher. Builder receives only the current milestone's minimal Work Order and must not start the next milestone. There is one business writer at a time. No policy grant permits default-branch writes, cross-project writes, Push, Merge, Rebase, force operations, release, deployment, production changes, external-account mutation, administrator changes or paid-service activation. Dependencies and migrations require actual approval; continuous execution never widens permission.

## Stable Authorization and Runtime Lease

Authorization cannot store Control Run ID and cannot store Lease Epoch.
Control Run ID belongs in STATUS or Continuation Checkpoint.
Lease Epoch belongs in STATUS or Continuation Checkpoint.

Every START or RESUME creates a new Control Run ID and Lease Epoch, fences old leases and rejects late reports. The current Wave, milestone and active lease are runtime state; stable Authorization retains only approved facts across sessions. Authorization, Control Run and Lease have separate lifetimes; a new runtime lease never renews user approval.

Authorized Base Checkpoint SHA is the authorization chain origin. The first Current Milestone Base SHA equals that origin; each later Current Milestone Base SHA equals Previous Accepted Checkpoint SHA. Prove `git merge-base --is-ancestor AuthorizedBase CurrentBase` before continuation. Expected Builder Start SHA identifies this lease's exact starting HEAD and does not change Milestone Base. An unprovable chain is `BASELINE_DRIFT` and stops execution. The control-only successor and dirty-state rules are in [readiness-and-recovery.md](readiness-and-recovery.md).

## Authorization and Runtime States

Keep Authorization states separate from execution states:

| Event | Authorization / execution outcome |
|---|---|
| New user approval | ACTIVE / ARMED |
| First identity gate passes | ACTIVE / ACTIVE |
| User pauses | PAUSED / BLOCKED; save Continuation Checkpoint and revoke the lease |
| Stop Gate reached | ACTIVE / STOP_GATE_REACHED; pause, then set Authorization EXHAUSTED |
| Scope completed | EXHAUSTED / COMPLETED |
| Contract, Goal, branch or Base change; unknown dirty worktree; hard blocker | INVALIDATED / BLOCKED |
| Runtime rollback | SUSPENDED_BY_RUNTIME_ROLLBACK / BLOCKED |
| Continuous policy absent | DISABLED execution; V1 default pause |

The original authorizing user may resume PAUSED authorization. INVALIDATED, EXHAUSTED and SUSPENDED_BY_RUNTIME_ROLLBACK require a new user decision; Goalkeeper cannot reactivate them. `RESUME CONTINUOUS_MODE ACTION=PAUSE` persists the safe pause instead of dispatching business work. On resume, readiness and both applicable identity gates still apply; no counter or evidence becomes fresh merely because the session changed.

## Pre-write Identity Gate

Before any business-file write, Builder returns its Builder Echo. Before issuing the single Builder Lease, Goalkeeper compares the authoritative message projections and observed Git facts:

- Authorization ID / Status / Scope; Goal ID / Version.
- Active Plan Milestone ID; Milestone Contract ID / Version; Work Order ID / Milestone ID; Builder Echo.
- Repository Identity; Milestone Worktree Identity; Milestone Worktree Exact Branch.
- Authorized Base Checkpoint SHA / Previous Accepted Checkpoint SHA; Current Milestone Base SHA.
- Expected Builder Start SHA / Actual Worktree HEAD; Writable Path Hash / Forbidden Path Hash.
- Control Run ID; Lease Epoch; Risk Level; Validation Plan.

Actual Worktree HEAD must exactly equal Expected Builder Start SHA. The exact branch is the current milestone's frozen WAVE-PLAN branch inside the approved namespace; source branch is only the baseline and the default branch is never a write target. Worktree Identity must equal the Goalkeeper registry. Apply the start-SHA and inventory checks in [readiness-and-recovery.md](readiness-and-recovery.md) before granting a lease.

Compute Repository Identity with `PFC_GIT_COMMON_DIR_SHA256_V1`: resolve Git common dir to an absolute path, lowercase on Windows, replace backslashes with `/`, remove the trailing `/`, and SHA-256 the normalized value prefixed by `pfc.repo.v1\n` (LF). Compute Worktree Identity with `PFC_WORKTREE_ROOT_SHA256_V1` using the resolved worktree root, the same normalization and `pfc.worktree.v1\n` prefix. A repository move or changed common dir invalidates authorization.

Compute both path hashes with `PFC_REPO_PATH_SET_SHA256_V1`: use repository-relative paths, slash separators, Unicode NFC, remove `.` segments, reject `..` escape, lowercase on Windows, deduplicate, sort and join with LF, then hash with `pfc.paths.v1\n` prefix. Authorization, Contract, Order and Echo must agree on the same normalized path sets and algorithm; do not substitute unchecked display strings for computed identities.

Every applicable comparison must pass for `PRE_WRITE_IDENTITY_GATE_PASS`; otherwise `STOP_BEFORE_WRITE`. This gate cannot depend on a Candidate or Verifier that does not yet exist. A mismatch never authorizes a partial lease.

## Pre-review Identity Gate

Only after Candidate freeze does Goalkeeper issue VERIFY_ORDER. Verifier independently compares:

- Authorization ID / Status; Goal / Milestone / Work Order / Verify Order.
- Repository Identity; Base SHA / Candidate SHA.
- Changed Files against Path Policy; Risk Level / Validation Tier.
- Builder Evidence SHA; Wave ID; Acceptance Record Target.

All applicable comparisons must agree for `PRE_REVIEW_IDENTITY_GATE_PASS`. A mismatch is `CONTROL_PLANE_DEFECT`; do not begin technical acceptance. Old-SHA evidence, a wrong task or Work Order, and Candidate drift produce the applicable `STALE_REPORT_REJECTED` or `VERSION_INTEGRITY_FAIL`. The fixed Candidate and independent worktree rules remain in [git-and-worktrees.md](git-and-worktrees.md).

## Wave Lifecycle

A Wave contains one to five pre-approved milestones, executed sequentially. Read valid Authorization, Backlog and Accepted Checkpoint; exclude completed, blocked, out-of-scope and dependency-unsatisfied work. Rank remaining work by P0, critical path, downstream blocking count, risk and code locality. Required fact sources precede dependent UI; optional visuals or release work do not block the core path. Freeze one active WAVE-PLAN. Apply risk caps and validation from [risk-validation-policy.md](risk-validation-policy.md), including lower approved limits.

Each milestone retains its own Work Order, Candidate, Review and Acceptance. Start the next item automatically only when the current item is ACCEPTED; Candidate, Evidence and Acceptance SHA agree; both applicable identity gates pass; all required validation is PASS; no BLOCKER or MAJOR remains; Contract, scope, paths and Goal are unchanged; no HIGH or irreversible action awaits decision; no acceptance-necessary Specialist is active or unresolved/unavailable; Convergence is neither STALLED nor REGRESSING; Authorization is ACTIVE; and the next item is inside the frozen Wave. Other Specialist authority remains in [specialist-protocol.md](specialist-protocol.md).

Failure handling and independent repair counters use [blocker-classification.md](blocker-classification.md). A T3 failure reopens only milestones linked by evidence; if the failure cannot be attributed, block the Wave instead of redoing all accepted work. Reaching the approved consecutive-blocked limit stops automatic progression. A completed Wave's wave-report is immutable evidence. Only Goalkeeper switches the unique active WAVE-PLAN in a control-record commit.

## T3 PASS Transition Order

1. Persist WAVE_SUMMARY, the last Accepted Checkpoint and the control-record commit.
2. Evaluate Stop Gate; if reached, enter STOP_GATE_REACHED and pause, then exhaust Authorization.
3. Evaluate authorization scope exhaustion; if exhausted, enter EXHAUSTED / COMPLETED.
4. Recheck Authorization, Git, Contract, Known Limitations and all hard-stop conditions.
5. Select next Wave from the remaining authorized scope, with one to five items subject to risk caps, and freeze its WAVE-PLAN from the previous Accepted Checkpoint.

Before automatically continuing, the first milestone of the new Wave MUST pass the complete Pre-write Identity Gate, including a fresh Builder Echo and lease. Valid authorization requires no per-milestone or per-Wave user reapproval. Stop Gate, scope exhaustion or any failed recheck prevents selection and dispatch. Scope completion does not replace the fresh final Goal audit required by [orchestration-protocol.md](orchestration-protocol.md).
