# Modes and state machine

These are control-flow states, not task-complexity modes. Once the Skill is explicitly invoked, even a small task retains the same role isolation; implicit mode downgrade is forbidden.

## Run modes

```text
START        create a new Goal and baseline
RESUME       recover from persisted control sources
AUDIT        inspect a claimed or changed result
STATUS_ONLY  read status, blockers, and forecast without writes
```

When no mode is supplied, inspect facts in this order: `STATUS_ONLY`, `AUDIT`, `RESUME`, then `START`. A mode conflict is reported and paused; it is never silently changed.

## Milestone states

```text
PLANNED -> READY -> ACTIVE -> REVIEW -> ACCEPTED
                         |       |         |
                         v       v         v
                      BLOCKED  REPAIR    CHANGED
```

`CANCELLED` and `ACCEPTANCE_CHECKPOINT_INVALID` are terminal outcomes. `REPAIR` returns to `ACTIVE`; `CHANGED` requires an approved contract update and returns to `PLANNED` or `READY`. `ACCEPTED` requires a valid Verifier PASS and Goalkeeper persistence. An unaccepted Candidate cannot become the next milestone base; only the Accepted Checkpoint SHA can be inherited.

## Goal states

```text
PLANNED -> ACTIVE -> GOAL_REVIEW -> GOAL_ACCEPTED -> PROJECT_COMPLETE
                     |      |
                     v      v
                 GOAL_REPAIR BLOCKED
```

`CHANGED` records an approved Goal change and re-enters `ACTIVE`; `CANCELLED` ends the Goal. `GOAL_REVIEW` always uses a fresh Verifier and worktree. Verifier does not grant final Goal acceptance.

## Specialist substate

```text
NONE -> REQUESTED -> ACTIVE -> EVIDENCE_NEEDED -> ACTIVE
                              |                 |
                              v                 v
                           RESOLVED         UNRESOLVED
```

`UNAVAILABLE` records a missing capability. A Specialist is blocking only when the contract marks its question as necessary for acceptance. It never creates a fourth formal role.

## Valid transitions

- `START` creates `PLANNED`; an approved contract moves it to `READY` and then `ACTIVE`.
- Builder work under its lease produces a Candidate and moves the milestone to `REVIEW`.
- A frozen Candidate enables a Verifier Order; a valid PASS lets Goalkeeper move `REVIEW` to `ACCEPTED`.
- A finding moves `REVIEW` to `REPAIR` (or `BLOCKED` when progress is impossible); a changed contract moves to `CHANGED`.
- After `ACCEPTED`, the default is `PAUSE_AFTER_MILESTONE`; the next milestone starts only from the Accepted Checkpoint.

## Invalid transitions

- `PLANNED` or `READY` cannot skip the required activation and Candidate freeze.
- `ACTIVE` cannot become `ACCEPTED` from Builder self-acceptance or without independent Verifier evidence.
- A missing Verifier cannot be replaced by the main thread.
- A Candidate in `REVIEW`, `REPAIR`, `BLOCKED`, or `CHANGED` cannot seed a later milestone.
- `STATUS_ONLY` cannot write code, control files, or create formal agents.
