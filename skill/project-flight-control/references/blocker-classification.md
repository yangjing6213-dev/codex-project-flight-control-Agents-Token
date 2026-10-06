# Blocker classification

This reference owns Continuous issue disposition and independent repair budgets. [message-contracts.md](message-contracts.md) is the sole field-definition authority; record classifications using its existing nested contract.

## Issue Disposition

For every issue, record observed evidence, affected scope, blocking scope, the registered approved fallback reference (or none), and next action. Keep product verification results separate from test infrastructure results: successful infrastructure repair or fallback execution does not establish product PASS. Unavailable or incomplete product checks retain their actual result.

| Classification | Disposition |
|---|---|
| PRODUCT_DEFECT | Block the current milestone and perform the minimum authorized repair. |
| TEST_INFRASTRUCTURE_DEFECT | Continue with recorded technical debt only when independent product evidence and a registered approved fallback exist; otherwise block verification. Inspect the evidence rather than trusting its marker. |
| CONTROL_PLANE_DEFECT | Block globally before writing. If discovered after a write, freeze the scene and rebuild governance evidence before any further business work. |
| KNOWN_ENVIRONMENT_LIMITATION | Use only the registered approved fallback and review trigger; without a valid fallback, block affected verification. |
| DOCUMENTATION_ONLY | Candidate documentation or formatting can be repaired within authorization and budgets; any non-governance tracked edit still creates a new Candidate. |
| EXTERNAL_DEPENDENCY_FAILURE | Continue only using an approved registered fallback; otherwise block the affected scope. |
| SECURITY_OR_DATA_RISK | Global hard stop; preserve evidence and request the required decision. |
| UNCLASSIFIED | Pause affected work and collect the minimum evidence needed to classify it. |

Do not substitute one classification for another merely to continue. A limitation blocks only its demonstrated scope unless it is a global safety/control defect; record both affected and blocking scope. Preserve known limitations and fallback/review conditions through [readiness-and-recovery.md](readiness-and-recovery.md).

## Independent Repair Limits

Builder repair attempts: at most 2.
automatic REWORK rounds: at most 2.
The counters remain independent.
Candidate revisions: only R1, R2, R3.
R4 is forbidden.

Apply lower approved limits when present. Builder's cap counts code repairs on the same failure path; after two attempts it must return its Lease, not rename a third attempt as another approach. Goalkeeper's formal automatic REWORK budget is separate. Candidate Revision counts frozen versions independently of either repair counter. RESUME, runtime lease changes and control-record commits cannot reset or offset these counters.

Command spelling, temporary paths, cache cleanup and runtime environment recovery that do not modify tracked files do not consume a Candidate Revision; this is not an exemption from repair limits or permission checks. After Candidate freeze, any business implementation, test, Schema, template, runtime configuration or other non-governance tracked change requires a new Candidate and fresh independent verification. Only strictly allowlisted pure control-record commits preserve the Candidate, as specified by [readiness-and-recovery.md](readiness-and-recovery.md). R3 may be accepted with valid PASS; R3 failure cannot produce R4.

Any of these conditions is `REPAIR_LOOP_STOPPED`: the same core failure persists across two formal rework rounds; two consecutive rounds add no passing criterion; the root cause remains unconfirmed; Convergence is STALLED or REGRESSING; data corruption or permission bypass appears; or repair requires a contract/scope change. Stop writing, return the lease, preserve the counters and evidence, and escalate the blocking decision. Budget remains a ceiling, never a requirement to try more repairs despite a hard stop.
