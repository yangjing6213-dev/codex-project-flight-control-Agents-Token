---
name: project-flight-control
description: Explicitly control complex Codex development through Goalkeeper, Builder, and Verifier roles.
---

# Project Flight Control

Activate this skill explicitly with `$project-flight-control`. It does not implicitly invoke, install, configure, deploy, or release anything, and it does not replace project instructions.

## Goalkeeper

Goalkeeper is the sole control-file writer and owns scope, acceptance, leases, decisions, and the final receipt. Begin with a read-only preflight, identify the project baseline, and select exactly one mode: `START`, `RESUME`, `AUDIT`, or `STATUS_ONLY`.

## Canonical preflight

Map each fact to its canonical source before acting. Run `SUBAGENT_PREFLIGHT` for every delegated role: provide only the bounded contract, fixed SHA, constraints, and required evidence. Apply the no-role-simulation gate; do not simulate roles in one thread or let a subagent create another role. Lock the contract before dispatch.

Load only the references needed for the current phase:

- Preflight and mode selection → `references/roles-and-authority.md`, `references/modes-and-state-machine.md`
- Contract lock and message projection → `references/message-contracts.md`, `references/roles-and-authority.md`
- Builder dispatch and Candidate freeze → `references/orchestration-protocol.md`, `references/git-and-worktrees.md`
- Builder routine efficiency → installed `.codex/agents/project-flight-builder.toml` (package source `codex-agents/project-flight-builder.toml`); failure-only debugging → `references/builder-debugging.md`
- Verifier review and rework → installed `.codex/agents/project-flight-verifier.toml` (package source `codex-agents/project-flight-verifier.toml`), `references/orchestration-protocol.md`, `references/git-and-worktrees.md`, `references/message-contracts.md`
- Evidence, recovery, decision, checkpoint, and final receipt → `references/evidence-and-recovery.md`, `references/modes-and-state-machine.md`, `references/message-contracts.md`, `references/git-and-worktrees.md`
- Approved Specialist request and Windows preflight/runtime → `references/specialist-protocol.md`, `references/windows-runtime.md`

## Execution flow

Dispatch Builder with the minimum `WORK_ORDER`; Builder follows its TOML authority and returns implementation evidence. Freeze the resulting Candidate SHA before dispatching Verifier. Dispatch Verifier with a fixed Candidate and `VERIFY_ORDER`; Verifier follows its TOML authority, independently checks the acceptance criteria, and returns a structured review.

Use evidence to decide `REWORK`, `BLOCKED`, `CHANGED`, or `ACCEPTED`. Rework is bounded to the review findings. Checkpoint after each milestone and pause whenever an authorization, dependency, evidence, version, or safety condition is unresolved. A Specialist requires a separate approved request, fixed Evidence SHA, and a narrow question; it cannot change state or files.

## Project Control Report

End every run with the fixed Project Control Report route: status, mode, goal and milestone state, Base/Candidate SHA, evidence IDs and locations, verification status (`PASS`, `FAIL`, `PARTIAL`, or `NOT_RUN`), blockers, residual risks, and the next authorized action. If a required gate is missing, report the pause condition and stop.
