# Evidence, convergence, and recovery

This is the single authority for Evidence Records, convergence snapshots, and interrupted-run recovery. Message field names remain defined by `message-contracts.md`; this reference defines when facts are valid and how they are resumed.

## Compact Evidence Record

Every command or human verification that matters to acceptance produces one compact record with:

```text
Evidence ID: <id>
Candidate SHA: <40-char sha>
Candidate Timing: BEFORE_CANDIDATE | ON_CANDIDATE
Source: AGENT_EXECUTED | USER_EXECUTED | EXTERNAL_SYSTEM
Command / Verification Action: <command or action>
Working Directory: <resolved repository path>
Environment: <runtime and version>
Exit Code / Result Claimed: <exit code and claimed result>
Observed Result: <bounded summary>
Covered Criteria: <criterion IDs>
Created At: <timestamp>
Evidence Location: <optional attachment index>
```

Successful verification stores the command or action, exit code, a short observed-result summary, covered criteria, the Candidate SHA, and `Candidate Timing` stating whether the command ran `BEFORE_CANDIDATE` or `ON_CANDIDATE`. Full terminal logs are not copied into work orders, reports, or handoff messages. Raw logs are temporary and can never be the sole recovery fact.

Evidence is valid only when its Candidate SHA, Control Run ID, Lease Epoch, environment, and command result match the current contract. A later Candidate change invalidates affected evidence; old records are retained and marked `STALE` or `REVERIFY_REQUIRED`, never rewritten.

## Restricted attachments and redaction

An attachment is saved only for a failure, a BLOCKER or MAJOR finding that needs output, an intermittent or non-repeatable result, human or external verification, a summary that cannot prove a required criterion, or a recovery-critical output. Each attachment is bounded to no more than 200 relevant lines and 64 KiB, contains only relevant lines and environment facts, remains bound to Evidence ID and Candidate SHA, and never overwrites earlier evidence.

Before persistence, redact tokens, cookies, keys, passwords, account and customer data, and sensitive or user-specific paths. A successful command does not require an attachment. Unredacted raw logs are never committed or used as the only proof.

## Convergence

After each Revision, Goalkeeper extracts the latest `CONVERGENCE_SNAPSHOT` from BUILD_REPORT and REVIEW_REPORT:

```text
Revision
Candidate SHA
Blocking Findings
Passed Criteria
Remaining Failed Criteria
Failure Signature
New Evidence Since Previous Revision
Trend: IMPROVING | STALLED | REGRESSING | UNKNOWN
Next Authorized Action
```

`STATUS.md` contains the latest snapshot only. Historical facts remain in the corresponding BUILD_REPORT, REVIEW_REPORT, and Evidence Records; no separate convergence log is created. Existing evidence is never silently reused after a Candidate change. A control-only Goalkeeper acceptance commit does not create a new verified Candidate.

## Recovery sources and lease fencing

Recovery reads, in order, Git state, canonical project sources, the latest STATUS, and persisted Build, Review, Specialist, Decision, and Acceptance evidence. Thread IDs are trace metadata only; old chat, model reasoning, and temporary logs are not recovery dependencies.

Every start or resume creates a new `Control Run ID` and `Lease Epoch`. New work orders and reports carry both. Reports from an old epoch, an old Candidate, a replaced Specialist Order, or a late thread are rejected as `STALE_REPORT_REJECTED`; they cannot advance state or establish PASS.

Recovery actions are deterministic:

* `ACTIVE` with no Candidate: create a new Builder from the valid WORK_ORDER, Base SHA, current worktree facts, latest BUILD_REPORT, required verification, and next authorized action.
* Candidate present without a valid Review: create a new Verifier for the same frozen Candidate SHA using VERIFY_ORDER, fixed diff, valid Evidence, and risks.
* `REPAIR`: create a new Builder from the valid WORK_ORDER, Current Candidate SHA, latest REVIEW_REPORT, REWORK_ORDER, latest convergence snapshot, and required verification; change only failed findings and affected regressions.
* Review PASS before acceptance persistence: Goalkeeper checks Candidate, contract, reports, Specialist dependencies, and version integrity; persist only when all agree, otherwise reverify.
* `Specialist ACTIVE` or `EVIDENCE_NEEDED`: logically revoke the old thread but preserve the same Specialist Order ID, Evidence SHA, Evidence Round, and Allowed Scope. A replacement uses the same order and fixed SHA worktree; it is not a second consultation.
* `ACCEPTED`: do not recreate old roles; calibrate persisted state and prepare the next milestone from the Accepted Checkpoint SHA.

An accepted checkpoint may register only the canonical control files allowed by the contract. Any other checkpoint content is `ACCEPTANCE_CHECKPOINT_INVALID`. Candidate SHA and Accepted Checkpoint SHA remain distinct.

Specialist observations are bound to the Specialist Order's Evidence SHA. After a Candidate change, guidance may be retained only after explicit applicability review (`GUIDANCE_APPLICABLE`, `GUIDANCE_PARTIALLY_APPLICABLE`, or `REPORT_STALE`); it never proves the new Candidate. A necessary unresolved Specialist question blocks acceptance, while a non-necessary unresolved question is recorded as residual risk with its evidence basis.
