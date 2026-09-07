# Conditional Runtime Specialist Protocol

The Runtime Specialist is a conditional, temporary consultation. It is not a fourth formal role and has no formal state-machine verdict authority.

## Admission and order

Goalkeeper-only approval and creation: only the Goalkeeper may approve and create a Specialist. `SPECIALIST_REQUEST` is an advisory application; it does not create a thread. `SPECIALIST_ORDER` is the only authorized input. An Order binds one fixed Evidence SHA, a narrow Context Packet, allowed files/symbols/evidence, one question, one evidence expansion, and Evidence Round `0` or `1`. The same Order ID is reused for round 1. There is one active Specialist, no nested agents, and no automatic report inheritance to a new Candidate.

Synchronous pause: affected Builder or Verifier work pauses while the Order is active. The Specialist receives an independent disposable worktree at the fixed Evidence SHA. The worktree is read-only by default; Candidate, tracked files, index, HEAD, contracts, and control files cannot be modified. Candidate modification is forbidden. The Specialist cannot create a commit, change the Candidate, command formal roles, or issue ACCEPT, REWORK, or BLOCKED authority.

## Analysis and evidence

Analysis is static-first and restricted to the Context Packet. A diagnostic command is permitted only when the Order names the minimum diagnostic command required; network access, dependency installation, automatic whole-repository scans, full-context inheritance, and unrelated commands are forbidden by default. Evidence is compact and must identify the Evidence SHA and source. After a Candidate changes, prior evidence is guidance only: Goalkeeper performs an explicit applicability check (`GUIDANCE_APPLICABLE`, `GUIDANCE_PARTIALLY_APPLICABLE`, or `REPORT_STALE`) before reuse. Specialist evidence never proves a new Candidate.

## Report and lifecycle

The only report statuses are `FINDING`, `EVIDENCE_NEEDED`, and `UNRESOLVED`. `EVIDENCE_NEEDED` may occur at most once and ends only after the single allowed expansion. `FINDING` supplies evidence and a recommendation; `UNRESOLVED` records known and unknown evidence and decision risk. Neither status is ACCEPT, REWORK, or BLOCKED, and no report changes formal state. A necessary-prerequisite question remains blocking for the affected acceptance decision until resolved; a non-necessary unresolved question is recorded as residual risk. Persist only the approved Order, final Report, and cited compact Evidence; discard full chat and unrelated output when cleanup is safe.
