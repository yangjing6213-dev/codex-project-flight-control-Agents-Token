# Readiness and recovery

This reference owns Continuous readiness and dirty-worktree recovery. [message-contracts.md](message-contracts.md) defines Checkpoint and recovery-manifest semantics. V1 Evidence Records, convergence and lease fencing retain their authority in [evidence-and-recovery.md](evidence-and-recovery.md).

## Readiness

Readiness is exactly `READY_FOR_CONTINUOUS_EXECUTION`, `READY_WITH_PRECONDITIONS`, `RECOVERY_REQUIRED` or `BLOCKED`. Preconditions must be completed and applicable identity gates must pass before a Builder Lease; readiness is not product PASS or permission to bypass a gate.

Enter RECOVERY_REQUIRED for HEAD/governance-version mismatch, unknown tracked changes, unknown untracked material, Plan/Work Order/Backlog misalignment, old-SHA evidence, an unknown active Session, an in-progress Git operation or unexplained lockfile drift. Missing Git blocks identity proof. Unknown facts must fail closed: preserve the scene, stop before any business write or Lease, and reconcile evidence. An identity mismatch is `STOP_BEFORE_WRITE`, never a reason to adopt current HEAD silently.

## Recovery Sequence

Perform these actions in order:

1. Read-only inventory of Git, processes/leases, canonical sources and persisted evidence.
2. Create a repository-external recovery package containing actual preserved file byte copies, including untracked material and recoverable pre-deletion bytes; never overwrite existing unknown data.
3. Persist and verify file SHA-256/byte-size manifests against those copies and the observed Git status, including rename/copy origins and allowed paths.
4. Classify material as ACTIVE, HISTORICAL or UNKNOWN using evidence; a suggestive report filename is not proof of provenance.
5. Apply only authorized reversible isolation after preservation; retain UNKNOWN material for resolution rather than treating it as disposable.
6. Freeze a governance Continuation Checkpoint with the observed inventory and independent repair counters.
7. Run the complete pre-write identity gate under a new Control Run and Lease Epoch.
8. Resume only the current authorized task after readiness and the gate pass.

An inventory list without actual recovery copies is insufficient. Schema validity does not prove that a backup exists or that its bytes match. Keep unknown files intact, and do not copy dirty implementation into another worktree as an implicit continuation decision. Never automate `git reset --hard`, `git clean -fdx`, broad `git restore .`, stash, commit-all-dirty, deletion of unknown untracked files, or destructive overwrite as recovery.

Known dirty implementation is resumable only if exact Git porcelain status, every file hash and size, rename/copy origins, and allowed paths match the frozen recovery manifest and preserved copies. Any extra, missing or changed path is unknown drift and returns to RECOVERY_REQUIRED. Known dirty control files require the same proof; a control-like name grants no blanket exemption or automatic commit permission. HISTORICAL material is preserved and excluded only through an evidenced project decision, never a built-in filename exception.

## No-Candidate Resume

For first execution or ACTIVE RESUME without a Candidate, Expected Builder Start SHA equals Current Milestone Base SHA or a proven descendant containing only strictly allowlisted control-record changes. Actual Worktree HEAD must exactly equal Expected Start. Apply the known-dirty inventory check above before granting a lease; otherwise stop and reconcile.

The authorization-to-accepted-to-current-base chain and precise branch/worktree/path identity checks remain owned by [continuous-execution.md](continuous-execution.md). Existing recovery sources are read in V1 order: Git, canonical project sources, latest STATUS, then persisted Build/Review/Specialist/Decision/Acceptance evidence. Old leases and stale reports cannot survive the new run/epoch.

## Candidate Rework

For REWORK or RESUME with a Candidate, keep Milestone Base unchanged. Freeze Expected Builder Start SHA in the latest REWORK_ORDER / WORK_ORDER and Continuation Checkpoint. It must equal Current Candidate or a proven control-only descendant; Actual HEAD must exactly equal Expected Start. Prove ancestry and inspect every path in `git diff --name-only CurrentCandidate..ExpectedStart`. Every changed path must be in the registered control whitelist, and every intervening commit must be control-only; net-zero business edits do not qualify. The same descendant proof applies from Current Milestone Base in the no-Candidate case.

The whitelist is the contract's exact registered Canonical Project Sources for Build Report, Review Report, Specialist Order/Report, Decision, STATUS, compact Evidence Record/attachment index and governance/Acceptance records. Goalkeeper alone may append those control records. It excludes business source, tests, build/runtime configuration, lockfiles, database/migration code and all unregistered paths. Reports, documentation, templates or scripts outside this whitelist are ordinary non-governance changes and require a new Candidate. Control-record commits cannot be presented as newly verified implementation.

Repair attempts, formal rework rounds and Candidate Revision do not reset across RESUME or control-only descendants; apply [blocker-classification.md](blocker-classification.md). Candidate freeze and independent review remain intact: resume a pending Review on the same fixed Candidate, or use a bounded rework order; never accept stale evidence as the replacement review. Invalid Accepted Checkpoint contents remain `ACCEPTANCE_CHECKPOINT_INVALID`.

## Known Limitations and Fallbacks

Goalkeeper persists the existing known-limitations and blocker-fallback-matrix renderers at their registered canonical paths. Each limitation keeps evidence, blocking impact, approved fallback, review trigger and resolution condition; the matrix relates capability, primary path and failure signal to its approved fallback and milestone/phase impact. Refer to their IDs in later tasks and re-investigate only when a review trigger fires. A missing fallback cannot be invented at resume; record the actual blocked or unverified result. Neither registered limitations nor successful recovery erase required verification or the final Goal audit.
