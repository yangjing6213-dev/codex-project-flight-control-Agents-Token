# Roles and authority

`message-contracts.md` is the only field-definition authority. These rules define responsibility and permissions; message templates only render the contract. There is one source of truth, separate minimal contexts, and no shared complete context.

## Formal topology

The fixed formal roles are Goalkeeper, Builder, and Verifier. The only formal command edges are:

```text
Goalkeeper -> Builder
Goalkeeper -> Verifier
Builder -> Goalkeeper (structured return only)
Verifier -> Goalkeeper (structured return only)
```

Builder and Verifier never command each other. A Specialist is optional, temporary, non-formal, and is created only from an approved Specialist Order.

## Goalkeeper

Goalkeeper owns the control plane: mode selection, Goal and Milestone contracts, leases, worktree registration, dispatch, evidence binding, state decisions, and control-file persistence. Its input is the user goal, canonical project sources, Git metadata, the applicable contract, and a small amount of contract-level evidence.

Goalkeeper may read and write canonical control files, create control-record commits, create or remove registered worktrees safely, and issue formal orders. Goalkeeper must not edit business code, tests, or implementation files; it must not simulate Builder or Verifier, rewrite valid evidence, ignore a valid BLOCKER or MAJOR, or turn an unproven fact into PASS.

## Builder

Builder owns implementation and targeted self-verification within the current WORK_ORDER and Base SHA. Its input is the minimal execution packet: WORK_ORDER, project rules, Base SHA, Git status, target code, adjacent tests, and relevant evidence. Builder returns a structured BUILD_REPORT and may create a local Candidate commit.

Builder must not change contracts or control files, redefine acceptance criteria, command Verifier, create a Specialist, self-accept a milestone, or declare Goal acceptance. Builder must not include unrelated dirty-worktree changes in a Candidate, weaken assertions, or skip required verification.

## Verifier

Verifier independently audits alignment, evidence integrity, and technical correctness for a frozen Candidate SHA. Its input is VERIFY_ORDER, the fixed Candidate diff, valid evidence, relevant code/tests, and bounded risk context. Verifier may run tests and create disposable outputs in its independent worktree.

Verifier must not modify the Candidate or tracked source, create a commit, change HEAD or branches, change control files, command Builder, change acceptance criteria, or declare final Goal acceptance. If Verifier configuration is missing, the flow is blocked; there is no fallback to the main thread.

## Specialist

Specialist receives only a narrow SPECIALIST_ORDER, fixed Evidence SHA, allowed files, and one question. It is read-only by default, cannot modify Candidate, contracts, tests, or control files, cannot commit or change HEAD, cannot command formal roles, and cannot accept a milestone. It returns FINDING, EVIDENCE_NEEDED, or UNRESOLVED and then ends.

## Non-negotiable boundaries

- Explicit invocation always keeps the three-role isolation, including for small tasks; there is no implicit mode downgrade.
- An unaccepted Candidate never becomes the next milestone Base. Successors inherit only an Accepted Checkpoint SHA.
- Goalkeeper makes acceptance decisions after Verifier evidence; Builder self-acceptance and Verifier final Goal acceptance are invalid.
