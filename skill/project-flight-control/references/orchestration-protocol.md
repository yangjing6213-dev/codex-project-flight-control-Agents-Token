# Orchestration protocol

Goalkeeper is the control-plane coordinator. It is the only formal command source and the only writer of canonical control files. All messages use the field definitions in `message-contracts.md`; this reference describes ordering and leases only.

## Preflight

Goalkeeper confirms explicit invocation, mode, repository identity, Base SHA, clean or deliberately bounded baseline, required Builder and Verifier profiles, and the current Goal/Milestone state. Missing Verifier configuration blocks execution; there is no fallback to the main thread. A status-only request performs no writes or agent creation.

## Contract lock

Goalkeeper records one Milestone Contract with scope, non-goals, constraints, acceptance criteria, required verification, baseline observations, and evidence references. It projects the minimum WORK_ORDER and VERIFY_ORDER. Until a contract change is approved, acceptance criteria and the Base SHA are locked.

## Builder lease

In the V1 default flow, after the milestone is `ACTIVE`, Goalkeeper grants a single Builder lease on the milestone worktree. Builder starts from the locked WORK_ORDER and Base SHA, performs the minimum implementation and targeted checks, and returns a BUILD_REPORT. Goalkeeper retains the lease boundary and persists the report; no second writer operates in that worktree concurrently.

## Candidate freeze and Verifier order

Builder creates a local Candidate commit and returns its SHA. Goalkeeper freezes that Candidate, records Changed Files and evidence, and issues a VERIFY_ORDER. Verifier receives a separate worktree checked out at the fixed Candidate SHA. Verifier executes Alignment Audit, Evidence Integrity Check, then Technical Verification, and returns only a REVIEW_REPORT. Candidate, Evidence SHA, and acceptance criteria remain frozen during review.

## Decision and targeted rework

Goalkeeper validates message identity, Epoch, Revision, and SHA before deciding. A valid PASS permits acceptance; a BLOCKER or MAJOR requires REPAIR or BLOCKED. Targeted rework uses a new Builder lease and a REWORK_ORDER limited to failed findings and affected regressions. Builder never self-accepts, and Verifier never commands Builder or makes the final Goal decision.

## Milestone checkpoint and pause

Goalkeeper persists the Accepted Checkpoint SHA only after Verifier PASS and evidence integrity. The default is `PAUSE_AFTER_MILESTONE`: update Status, Roadmap, Evidence, Convergence, and Forecast, close the active role threads, and wait for user approval. An unaccepted Candidate is never a successor base.

## Optional continuous mode

The following paragraph records the V1 optional continuous guard. For explicit V2 policy, the conditionally linked references own Authorization, identity gates, sequential Waves, Specialist continuation eligibility and hard stops; use their full gate in place of this optional guard. The default V1 pause above is unchanged.

`CONTINUOUS_MODE` is allowed only when pre-approved and every gate remains true: the current milestone is ACCEPTED, audits and required checks PASS, the next milestone is already approved, scope and route are unchanged, no decision or high-risk action is pending, no Specialist is active, and any acceptance-necessary Specialist is neither `UNRESOLVED` nor `UNAVAILABLE`. A non-necessary consultation may remain unresolved without blocking unrelated proven work. Any failed condition pauses immediately; Goalkeeper does not silently resume it.

Only when explicit START CONTINUOUS_MODE or RESUME CONTINUOUS_MODE: [continuous-execution.md](continuous-execution.md).

Only when explicit Continuous policy is active and risk or validation selection is needed: [risk-validation-policy.md](risk-validation-policy.md).

Only when explicit Continuous policy is active and issue classification is needed: [blocker-classification.md](blocker-classification.md).

## Final Goal audit

After all required milestones are accepted, Goalkeeper enters `GOAL_REVIEW` and creates a fresh Verifier thread and worktree. The final audit checks Goal alignment, cumulative version integrity, required end-to-end behavior, cross-milestone integration, safety, and residual risks. Only Goalkeeper may persist `GOAL_ACCEPTED`; Verifier's report is evidence, not the final acceptance decision.
