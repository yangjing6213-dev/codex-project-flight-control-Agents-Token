# Changelog

## Unreleased

### V2 Development Track

- V2 Continuous Mode `0.2.0-dev.0` remains a development track. The original product Candidate's 23-child/812-row batch has a passing saved-output reconciliation, while its wrapper exited `1` on a StrictSchema parse error. Later evaluation-runner fixes have separate affected and focused checks; specification, quality and Ponytail R3 reviews accepted their implementation scope with no unresolved Critical or Important finding. The old batch is not claimed as a full run on the current Candidate. Formal RED is `PARTIAL` (2 attempted / 0 valid / 2 invalid); GREEN remains `NOT_RUN`; the October 10 disposable Windows workflow smoke passed 8/8; `PFC-UPSTREAM-001` remains unresolved. See [the V2 verification report](docs/verification/v2-verification-report.md) and [release gates](docs/verification/v2-release-gate.json).
- Added explicit `START CONTINUOUS_MODE` and `RESUME CONTINUOUS_MODE` execution policy, bounded Authorization and sequential Waves, two task-identity gates, risk-tier validation, recovery and hard-stop contracts. The four top-level modes and default pause behavior remain.
- Formal scenario fixtures now pin 41 actual product inputs to the source Candidate and require independently started Runner-managed Builder/Verifier processes. The 35 attempts per phase count top-level runs only; separately started roles add usage without a platform-enforced cumulative cap and require explicit authorization. Invalid formal attempts remain invalid.

- Corrected Runner handoff identity, exact Verifier report SHA binding, pre-dispatch checks and fail-closed error handling. The October 7 diagnostic completed a model response with no transport-error events in that sample, but Windows restricted-command startup failed before role dispatch; the underlying cause remains unconfirmed. The installed CLI subsequently updated, requiring a new explicitly accepted executable for further live runs.
- Fixed the disposable Windows smoke recovery fixture overwriting its starting-version proof; the original failure is retained. The corrected eight-proof local workflow passed without model calls, product gate changes or frozen evaluation changes.

### Implemented

- Added the MIT license and public development snapshot documentation in the prior `0.1.0-dev.0` snapshot; stable-release and efficiency gates remain blocked.
- Goalkeeper, Builder, and Verifier package implementation, Builder Efficiency Protocol, deterministic evaluation harness, file-handshake Permission Probe, and strict result Schema.

### Deterministically Verified

- Bootstrap, package, Harness, Builder Efficiency, profiles, isolation, schema, runner, Doctor, Installer, Specialist protocol, and file-handshake suites pass under Windows PowerShell 5.1.
- Prior affected checks include ContinuousMode 301/301 and a separate focused 8/8, plus five regression suites totaling 89 PASS. The full model-contract v3 run was 84 PASS / 1 test-fixture FAIL; the original failed check and two safety/accounting checks separately passed 3/3 after a test-only correction. The historical Task 11 trace fix passed a separate 16/16 focused selection, including bounded CM-05 no-dispatch sample collection with independent correctness still `NOT_RUN`. Those historical receipts do not establish a single 85/85 run. The current October 6 local batch separately passed all 26 check groups, including ContinuousMode 302/302, ContinuousModeModelContract 106/106 and RunnerOwnedLifecycle 60/60; it used no live model calls. Installer update and rollback evidence uses disposable fixtures; fake contract checks made zero formal model calls.
- Approved V2 design SHA-256 is `fda8edc9b476e94f387ad553118a9d4982cfb11439d018d8595fecbfeeb259f6`.

### Runtime Blocked

- Blocker `PFC-UPSTREAM-001`: native Windows Codex deny-read permission enforcement was not verified. The valid local probe result reported readable Evidence and External roots despite the selected elevated profile. Related open reports are `openai/codex#42184` and `openai/codex#31265`; their similarity is recorded without claiming official confirmation.
- Controlled RED/GREEN, Core Efficiency, and Stable Release gates remain blocked. The current Permission Profile must not be used as a confidentiality boundary for sensitive files.

### Not Yet Proven

- Model-backed efficiency improvement, token reduction, Runtime Specialist capability, native Windows sandbox isolation, full live role cooperation, and a stable release remain unproven.
