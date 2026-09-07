# Git and worktrees

Git identity and worktree state are evidence inputs. They are recorded in the applicable contract and reports; field names remain defined only by `message-contracts.md`.

## Original worktree and baseline

The original worktree is preserved: the Skill does not switch its branch, clean it, or copy uncommitted files. Before a milestone worktree is created, Goalkeeper records branch, HEAD, modified and untracked files, merge/rebase/cherry-pick/revert/bisect state, and the requested base. A clean committed baseline is preferred. If the worktree is dirty, Goalkeeper emits a baseline decision packet so the user chooses current HEAD, a prepared commit, or another explicit SHA.

## Worktree topology and leases

```text
original worktree       preserved and untouched
milestone worktree      Goalkeeper control writes, then Builder implementation
Verifier worktree       fixed Candidate SHA, detached HEAD, independent
Specialist worktree     fixed Evidence SHA, detached, temporary and read-only
```

The milestone worktree has one writer at a time. `GOALKEEPER_LEASE` and `BUILDER_LEASE` alternate; verification uses `VERIFICATION_IN_PROGRESS`. Specialist analysis never receives the milestone write lease.

When Builder needs specialist input, the affected implementation pauses, Builder returns the lease to Goalkeeper, and Goalkeeper records the Specialist Order before entering `SPECIALIST_IN_PROGRESS` in an independent Specialist worktree. Goalkeeper validates the report, re-enters `GOALKEEPER_LEASE`, and either resumes the existing WORK_ORDER or issues a bounded revised order. Builder then continues under a new Builder lease.

When Verifier needs specialist input, Candidate and Evidence SHA remain frozen and verification pauses. Verifier returns control to Goalkeeper, which starts `SPECIALIST_IN_PROGRESS` in a separate worktree at the fixed Evidence SHA. After Goalkeeper validates the report, Verifier re-enters verification on the same frozen Candidate; it resumes or receives a revised VERIFY_ORDER without any Candidate mutation.

## Candidate and verification

Builder creates a local Candidate commit from the approved Base SHA. Verifier's worktree is checked out at the fixed Candidate SHA with detached HEAD. Before and after verification, HEAD, index, tracked files, and status are checked. Any tracked mutation, commit, branch switch, or changed Candidate invalidates the review.

The concrete pre/post invariants are `git diff --exit-code` and `git diff --cached --exit-code`, together with the fixed Candidate SHA and `git status --porcelain`. A tracked-file change is `REVIEW_INVALID`; a changed HEAD, index, branch, or Candidate identity is `VERSION_INTEGRITY_FAIL`.

## Acceptance and control commits

An Accepted Checkpoint is a separately recorded SHA after Verifier PASS and Goalkeeper acceptance. A control-only acceptance commit may update canonical control files; it does not merge the Candidate or imply release. The next milestone starts from the last Accepted Checkpoint, never from an unaccepted Candidate.

## Specialist worktree

Each approved Specialist Order receives a separate disposable worktree at its fixed Evidence SHA, with no long-lived branch. Temporary writes are limited to ignored caches and operating-system temporary paths. Candidate, tracked source, index, HEAD, and acceptance state remain unchanged.

## Safe cleanup

Verifier and Specialist worktrees may be removed only after their reports and required evidence are persisted, the expected SHA and clean tracked state are confirmed, and no process or investigation remains. Use standard `git worktree remove` without force. On uncertainty report `CLEANUP_DEFERRED` or `SPECIALIST_CLEANUP_DEFERRED` and preserve the scene. Builder worktrees and local Candidate branches are retained by default; deletion requires separate authorization.

## Prohibited Git and delivery operations

Unless separately authorized, do not use `git push`, force push, merge, rebase, `git reset --hard`, branch or tag deletion, remote configuration changes, release, deployment, production mutation, or external-account actions. A commit permission never grants merge or push permission.
