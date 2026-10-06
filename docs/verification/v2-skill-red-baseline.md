# V2 Skill RED Baseline

Status: `RED_BASELINE_RECORDED`

## Frozen controls

- Base commit: `6fcc6e96702c99ba0f61a6347b5afc8a63d12007`
- Skill SHA-256: `5879f08badb4c9f314d55e7f49c623186beb1a73d2b2efc528c4fa50f6fbc679`
- Probe model: `gpt-5.6-terra`
- Probe reasoning effort: `medium`
- Probe execution: three fresh, isolated, read-only contexts with identical controls and no shared task context.
- Formal model samples: not run. These probes are implementation RED evidence and are excluded from the 70-run model gate.

## Frozen contract expectation

The approved V2 design and implementation plan require explicit `START` or `RESUME` with `CONTINUOUS_MODE`, four conditional V2 references, stable Authorization distinct from a Control Run and Lease Epoch, both identity gates, Waves of one to five milestones, LOW/MEDIUM/HIGH risk with T1 through T4 validation, fixed Stop Gate ordering, independent repair/Candidate limits, fail-closed recovery, and exactly the fixed Builder and Verifier Agent TOMLs.

`ContinuousContracts` was defined from those requirements. Its static assertions freeze Authorization/Control Run/Lease separation; minimum pre-write and pre-review identity bindings; the ordered T3 transition from persistence through Stop Gate and scope exhaustion to a successor Wave; independently parsed Builder-repair and automatic-REWORK caps exactly equal to two; Candidate revisions restricted to R1–R3 with R4 rejected; and per-reference `only when` predicates extracted separately from their route targets. The probe observations below did not relax, add, remove, or otherwise change its expected behavior.

## Normalized probe observations

| Scenario | Loaded references | User confirmations | Identity and Candidate handling | Verification, stop reason, final state |
|---|---|---|---|---|
| A — seven LOW milestones | Existing preflight/mode, Builder/Candidate, Verifier/review, checkpoint, evidence/recovery, and message-contract references. | `NOT_DETERMINABLE`; the current Skill has no approval provenance or count rule for continuous execution. | Existing Base, message, Candidate, and Verifier identity checks are present. No continuous authorization provenance, Wave, T3, or phase-boundary identity rule exists. | Existing Candidate freeze and independent verification remain required. The supplied facts do not establish a supported Wave/T3/UNTIL transition. Final state is `NOT_DETERMINABLE`; the normal path pauses after accepted milestones. |
| B — ACTIVE resume without Candidate | Existing preflight/mode, contract/message, Builder/Candidate, recovery, Git/worktree, and evidence references. | `NOT_DETERMINABLE`; no canonical authorization schema or counting rule exists. | A control-only descendant does not become a Candidate. No valid locked work order/state was supplied, and the dirty baseline requires a decision. | Recovery reads Git, canonical sources, STATUS, then persisted evidence. Continuous gates are not proven. Stop state: `PAUSED_PENDING_CANONICAL_STATE_AND_BASELINE_DECISION`. |
| C — failed R1 with urgent skip request | Existing preflight/mode, verifier/rework, Git/worktree, and message-contract references. | `NOT_DETERMINABLE`; no numeric confirmation rule exists. | R1 remains unaccepted; a control-only rework descendant cannot make it a successor. Existing identity checks remain present. | Required checks cannot be skipped. Failed review requires validated `REPAIR` or `BLOCKED`; continuous execution pauses. Final state: `PAUSED`. |

## Deterministic RED evidence

`ContinuousContracts` was run under Windows PowerShell 5.1 with `-Phase RED`. It failed with eight V2 omissions and no parser or V1-regression failure:

- explicit Skill entry policy and default pause route;
- conditional loading routes for the four V2 references;
- continuous execution and identity-gate reference;
- risk and validation reference;
- repair-limit reference;
- fail-closed recovery reference;
- Builder pre-write projection;
- Verifier pre-review projection.

The fixed-Agent-count assertion passed because the repository already has exactly the Builder and Verifier TOMLs. The deterministic in-memory negative self-check also passed: it rejects merged Authorization/runtime lease state, a reversed Stop Gate order, independently weakened `20`-attempt Builder or REWORK limits, R4, unconditional routes, and each non-continuous reference route whose predicate is replaced with unrelated text while its filename remains correct. These are test-harness assertions only; no repository runtime content was mutated. The fixed-Agent count is a pre-existing V1 invariant, not V2 implementation evidence.

## Regression check

`Bootstrap` was run under Windows PowerShell 5.1 with `-Phase GREEN`; all 17 checks passed. The approved design hash, V2 execution ledger, version, and the protected historical exclusion all remained valid.

## Scope and concerns

- This task changed no Skill runtime behavior, reference, Agent TOML, schema, installation, formal model evaluation, or remote state.
- The next tasks must satisfy the immutable checks without weakening them.
- `task-3-report.md` remains the protected historical exclusion and was not read into this report.
