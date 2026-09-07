# Message Contracts

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
