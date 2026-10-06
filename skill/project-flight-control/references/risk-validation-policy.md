# Risk and validation policy

This reference owns Continuous risk selection and validation requirements. [message-contracts.md](message-contracts.md) defines the field semantics; use its existing nested risk and validation records without adding a message family. Apply this policy only under explicit Continuous execution.

## Risk Matrix

| Risk | Typical scope | Required verification | Wave cap |
|---|---|---|---|
| LOW | Documentation, styles, ordinary UI, read-only queries, CRUD without Schema changes, approved test corrections | Each item T1 + T2; Wave end T3 | One to five sequential items |
| MEDIUM | File writes, import/export, non-destructive migration, Snapshot, external processes, planned dependencies, workspace import | Each item T1 + T2 and contract-selected rollback or upgrade/downgrade; Wave end T3 | One to three sequential items |
| HIGH | State machines, permissions, audit, recovery switching, deletion, credentials, destructive migration, scheduling, external irreversible actions | Single item T1 + T2 + T3 + T4, fault injection and user Gate | One item in its own Wave; no automatic next item |

Choose the highest applicable risk; specific data, permission or recovery impact overrides a generic LOW example. A Wave containing any MEDIUM item has cap three; any HIGH item requires a single-item Wave. Apply the smaller of the risk cap and the approved authorization limit. There is no fourth risk level.

Escalate one level when risk is uncertain, data integrity/permissions/recovery/Accepted calculation is affected, writable paths expand, a major dependency is introduced, or Verifier cannot independently reproduce the result. At HIGH, retain HIGH and its user Gate; uncertainty never downgrades it. Contract or scope changes still stop continuation pending the required decision.

The matrix is a verification requirement, not an authorization grant. It cannot authorize dependency installation, migrations, deletion or irreversible actions. Existing permission and forbidden-action boundaries apply even to an otherwise testable HIGH task.

## Validation Tiers

| Tier | When | Minimum evidence |
|---|---|---|
| T1 | Every Builder delivery | Focused tests, changed-file lint/format, scope check, secret scan |
| T2 | Every Candidate | Affected-module regression, AST/type/build, Git integrity, staged whitelist |
| T3 | Every Wave | Full applicable test/lint/type/build, cross-module smoke, fresh Wave Verifier |
| T4 | Phase Gate | E2E, recovery, fault injection, real-project behavior, data integrity, safe security stop |

Results remain exactly `PASS / FAIL / PARTIAL / NOT_RUN`. Express non-applicability with `required: false` plus a non-empty `applicability_reason`, normally NOT_RUN. Never add N/A as a fifth state or turn an unexecuted check into PASS. An optional record cannot waive the matrix's required validation. Every `required: true` check must PASS before automatic advancement.

A PASS for an old SHA cannot verify a new Candidate. Verifier may reuse complete, redacted Builder Evidence bound to the current SHA, but must execute minimum independent re-verification. LOW permits proportionate independent checks; MEDIUM/HIGH expand them as above. Any testing tool that changes tracked or staged files invalidates the Review. Evidence timing and validity remain governed by [evidence-and-recovery.md](evidence-and-recovery.md).

Wave progression and Stop Gate ordering are owned by [continuous-execution.md](continuous-execution.md); issue disposition is owned by [blocker-classification.md](blocker-classification.md). Passing a validation tier does not bypass either policy.
