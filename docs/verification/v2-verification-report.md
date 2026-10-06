# Project Flight Control V2 Deterministic Verification Report

This update publishes the current source and documentation only. Earlier development commits and raw run records remain local. Historical commit IDs identify the evidence behind prior checks; those commits are not published GitHub references. A public clone alone cannot reproduce the existing frozen formal model evaluation. That evaluation still requires the retained local version history and remains incomplete.

Status: **implementation PASS within the historical Task 1–11 local deterministic and independent-review scope; Task 12 PARTIAL; V2 release NOT_READY**. The source product Candidate is `4f5a066ab9c16575a5da5e133cf31349ed00dc35`; the reviewed Task 11 evaluation-runner Candidate was `74c8691129303460d7915085cc056574b893b0a1`. The 41 frozen product inputs remain tied to the source SHA. Specification, quality and Ponytail R3 approved those reviewed scopes with no unresolved Critical or Important implementation finding. Those historical reviews are supplemented by the current local repair review recorded below; neither is live-runtime release approval. Version: `0.2.0-dev.0`.

## Current progress — 2026-10-06

- Task 12 formal RED remains **2 attempted / 0 valid / 2 invalid**; **35 valid samples still required**. Old invalid attempts are retained. Task 13 GREEN and Task 14 Windows smoke remain `NOT_RUN`; further live runs require separate authorization.
- The latest diagnostic stopped after 0.22 seconds because the local capture script treated an optional PowerShell shell-snapshot warning as fatal. No stdout event was observed. This is not proof of continued network failure. A new launch copy adds only `--disable shell_snapshot`; the installed CLI advertises that feature. The strict capture remains unchanged and its 11 synthetic checks pass. The copy is blocked pending a new single-call authorization; no live retry was made.
- A fresh review found handoff identities, Verifier version binding, and error-stop gaps in the later Task 12 Runner changes. The repairs passed the final local batch and independent review recorded below.
- Current Task 12 uses Runner-managed Builder/Verifier processes with built-in Codex agents disabled. Starts and completions are **Runner records, not native Codex child events**. Limits per attempt are 13 role tasks, 13 Goalkeeper resumptions and 27 Codex process invocations; execution is serial without retry. The platform has no cumulative usage hard cap.
- Current frozen-control SHA-256: `d9214dff4149a8f7c993cc775609ef8ebf351c86703900403febe45d4b7de6d6`; Runner: `f886cf6b7654c097d70ca769b45d159d3a868d808a80924f46355cc9f7b8a5ac`; run-evals: `955be905893b5070d2a13dd389981659a973f155183703cac9d392d1d75a96ee`. The local repair starts from `7ad957e4de5a9822e0647bf56b07650788db4d83`; the final source fingerprint inventory below identifies the tested bytes independently of the checkpoint commit.
- Earlier affected checks (2026-10-01) under Windows PowerShell 5.1: RunnerTerminal **9/9 PASS**, ContinuousModeModelContract **104/104 PASS**, BuilderEfficiency **6/6 PASS**, Harness **54/54 PASS**, Bootstrap **17/17 PASS**, each exit `0`. Model-contract accounting: 228 fake calls, 0 real process calls, 0 real resolutions, 0 formal samples. The local repair receipt SHA-256 is `42d769d820610fc430518eb70fb35d45a9427bb1d3b95845883e78ac1f5f1d97`. Final independent review status/evidence is recorded in the active Task 12 ledger; these affected checks are not a complete project batch or release pass.
- `CORE_RELEASE_GATE=BLOCKED`, runtime Specialist capability remains `UNKNOWN`, and confidential-read isolation remains unverified. Current evidence and remaining work are recorded in [the active Task 12 ledger](../exec-plans/active/project-flight-control-v2-continuous-mode.md). The sections below preserve historical Task 11 evidence, hashes and review scope.

## Current repair verification — 2026-10-06

This source-update checkpoint completed **26/26 local check processes**, each with exit 0, under Windows PowerShell 5.1. The source fingerprint inventory was unchanged throughout this final batch. The rows below are each check's reported outcome count, not a combined code-coverage percentage. All model transport was synthetic: no new Codex model call, formal sample or real Windows isolation check was made.

| Check | Result | Reported outcomes |
|---|---|---:|
| StrictSchema | PASS | 1 |
| SchemaEncoding | PASS | 1 |
| RunnerTerminal | PASS | 9 |
| RunnerOwnedLifecycle | PASS | 60 |
| RunnerRoleAuthorization | PASS | 1 |
| Bootstrap | PASS | 17 |
| StaticPackage | PASS | 41 |
| Harness | PASS | 54 |
| BuilderEfficiency | PASS | 6 |
| Revision4Isolation | PASS | 32 |
| RunnerRevision3 | PASS | 1 |
| PermissionProbeFileHandshake | PASS | 1 |
| PermissionProbeExecutionPolicy | PASS | 1 |
| BuilderProfile | PASS | 36 |
| VerifierProfile | PASS | 44 |
| MessageContracts | PASS | 3 |
| GovernanceReferences | PASS | 12 |
| EvidenceRecovery | PASS | 63 |
| SkillEntry | PASS | 11 |
| SpecialistProtocol | PASS | 38 |
| Installer | PASS | 16 |
| Doctor | PASS | 41 |
| SpecialistSmokeUnit | PASS | 20 |
| ContinuousContracts | PASS | 10 |
| ContinuousMode | PASS | 302 |
| ContinuousModeModelContract | PASS | 106 |

- Final local summary SHA-256: `bbee78c4e4f0b22a16bc1327ba951ec959406bafdedae9493934c57455ca47e6`. Raw local test outputs remain ignored. Earlier unsuccessful wrapper/host-module/drift checks are preserved separately and are not relabeled PASS.
- Independent fix review: SPEC_COMPLIANCE PASS; QUALITY PASS; Critical 0; Important 0. It covers correct Builder/Verifier identities, exact own-report Candidate binding, rejection before duplicate/wrong-version dispatch, and immediate stop on any native error in Runner-managed flows. Normal generic recovered-error handling remains intact.
- The final sample guard independently rejects error-bearing terminal results even after a complete synthetic handoff. Correct no-dispatch safety observations remain eligible for their existing frozen checks; no model claim becomes independent correctness.
- The pre-call tests use named fake-invoker arguments, verify exact expected preflight failures, and prove the same fixture reaches the fake process after the injected fault is removed.
- The test process uses the native Windows PowerShell module directory only for that child. No test-source, personal setting or global Git setting was changed to solve the host module mismatch.
- Git attributes preserve exact file bytes across checkout platforms. Source and frozen hash bindings were checked together; scenario tasks, prompts, schemas, Base SHA, metrics and pass criteria are unchanged by this checkpoint.
- Current Runner: `f886cf6b7654c097d70ca769b45d159d3a868d808a80924f46355cc9f7b8a5ac`; run-evals: `955be905893b5070d2a13dd389981659a973f155183703cac9d392d1d75a96ee`; frozen control: `d9214dff4149a8f7c993cc775609ef8ebf351c86703900403febe45d4b7de6d6`.
- Formal RED remains **2 attempted / 0 valid / 2 invalid**. Task 12 still needs 35 valid samples, Task 13 needs 35 GREEN samples, and Task 14 needs its Windows workflow and final review. This source update does not waive those gates or establish confidential-read protection.

## Historical complete batch — source Candidate 4f5a066

The original Task 11 batch used Windows PowerShell 5.1 and launched the exact two standalone checks plus 21 named suites against `4f5a066`. All 23 child processes exited `0`. Independent semantic reconciliation found 812 passing normalized top-level outcomes and no missing or duplicate result IDs. A top-level row may wrap multiple internal assertions; 812 is not an internal assertion count. All 29 `SC-32` through `SC-60` rows passed at that Candidate. Its `ContinuousModeModelContract` used fake invokers: 62 fake calls, zero real process calls, zero real resolutions, and zero formal model samples. **This is historical full-batch evidence, not a 23-suite run on `69ac5de` or `74c8691`.**

The **original batch wrapper exited `1`** and recorded 22 children as `PASS` plus one `StrictSchema` `INVALID_OUTPUT`. Its JSON-only parser rejected StrictSchema stdout because that script prints seven existing `PASS` prefix lines before a terminal `PASS` JSON result. The independent reconciliation applies the script's exact output contract to the saved stdout and metadata, including the child exit `0`; it does not rerun the child or alter the original aggregate. The original wrapper result must not be described as exit `0`.

- Original local aggregate: `.superpowers/sdd/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan/task-11-evidence/20260923T042249Z-ede5599d15b045e29be9cf32624b8c8c/aggregate.json`; SHA-256 `b491a42874f793896382e2353e4c8212292b331ea2e0dd71c95bd9f62ba8ae2b` (retained unchanged in ignored local evidence).
- Normalized, saved-output-only reconciliation: `.superpowers/sdd/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan/task-11-normalized-evidence.json`; SHA-256 `78fe71a80259e7127fa89562f8aaafa752b1ca395f79702de8ff1a639515fea2`. It records 23/23 passing children, 812/812 expected top-level outcomes, zero reconciliation issues, each child exit/status/hash/ordered result-ID inventory, and the unchanged wrapper anomaly.
- Protected historical exclusion: `task-3-report.md` remains untracked and outside the index, 52,786 bytes, SHA-256 `f04452a828cfeece1031f715df1f8fea39b2d8686c6a20ad05575540df78cde1`. Its contents were not used for this report.

| # | Child | Top-level outcomes | Child exit | Semantic result |
|---:|---|---:|---:|---|
| 01 | StrictSchema | 1 | 0 | PASS after exact-envelope reconciliation; wrapper recorded INVALID_OUTPUT |
| 02 | SchemaEncoding | 1 marker | 0 | PASS |
| 03 | Bootstrap | 17 | 0 | PASS |
| 04 | StaticPackage | 41 | 0 | PASS |
| 05 | Harness | 54 | 0 | PASS |
| 06 | BuilderEfficiency | 6 | 0 | PASS |
| 07 | Revision4Isolation | 31 | 0 | PASS |
| 08 | RunnerRevision3 | 1 | 0 | PASS |
| 09 | PermissionProbeFileHandshake | 1 | 0 | PASS, fixture only |
| 10 | PermissionProbeExecutionPolicy | 1 | 0 | PASS, fixture only |
| 11 | BuilderProfile | 36 | 0 | PASS |
| 12 | VerifierProfile | 44 | 0 | PASS |
| 13 | MessageContracts | 3 | 0 | PASS |
| 14 | GovernanceReferences | 12 | 0 | PASS |
| 15 | EvidenceRecovery | 63 | 0 | PASS |
| 16 | SkillEntry | 11 | 0 | PASS |
| 17 | SpecialistProtocol | 38 | 0 | PASS |
| 18 | Installer | 16 | 0 | PASS, disposable fixtures |
| 19 | Doctor | 41 | 0 | PASS, passive/fixture scope |
| 20 | SpecialistSmokeUnit | 20 | 0 | PASS, fake adapters only |
| 21 | ContinuousContracts | 10 | 0 | PASS |
| 22 | ContinuousMode | 294 | 0 | PASS, including SC-32..SC-60 |
| 23 | ContinuousModeModelContract | 70 | 0 | PASS, fake invokers only |
| **Historical total** | **23 children** | **812** | **23 exit 0** | **Semantic PASS at 4f5a066 after reconciliation** |

The first 18 named suites are the applicable V1 regression set. The final three are V2 suites. SchemaEncoding's textual marker is normalized as one outcome; StrictSchema's terminal JSON is one outcome. Neither count should be confused with the internal assertions those scripts perform.

## Prior affected verification — 69ac5de

The first bounded fix changed evaluation and safety-check code only. Its 41 actual Skill/reference/template/profile inputs were pinned to source Candidate `4f5a066` with digest `cc4c299c63090b7d89a5d788b17089c0a31852e3d54825df0b61ac3869fb1399`. Its then-frozen control SHA-256 was `a60901713e8c60da9bf21744db0e72511b78d9a953ebbfeded0946836b0579d3`, subsequently superseded by the trace fix below. V1 schema-control and eval-run schemas, the scenario-local CM schema, and all seven EFF manifests remained byte-identical to the base.

The prior affected evidence index is `.superpowers/sdd/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan/task-11-final-fix-final-evidence.json`, SHA-256 `af5cef7e3a4665c10fe5b3ae838e918d3ac30d7eada9247ec4f14a2a75af220c`. It lists exact source paths, artifact lengths and hashes. The preserved-control receipt is `.superpowers/sdd/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan/task-11-final-fix-preservation.json`, SHA-256 `5d57cbac2490fcda04698edd44d96d462b29e0d70e7a97e95c108ffbe1904830`.

| Prior affected check | Child exit | Observed result |
|---|---:|---|
| ContinuousMode full | 0 | 301/301 PASS |
| Predecessor/history focused run | 0 | 8/8 PASS, separate from the 301-row run |
| ContinuousModeModelContract v3 full | 1 | 84 PASS, 1 FAIL of 85; the remaining failure was a test fixture's wrong product repository lookup |
| Original failed artifact check, tripwire and accounting after test-only correction | 0 | 3/3 PASS in a separate focused run; **no single 85/85 full run is claimed** |
| StaticPackage | 0 | 41/41 PASS |
| ContinuousContracts | 0 | 10/10 PASS |
| BuilderEfficiency | 0 | 6/6 PASS; existing line-ending warnings retained in stderr |
| RunnerRevision3 | 0 | 1/1 PASS |
| Revision4Isolation | 0 | 31/31 PASS |

The five prior regression suites in the last five rows contribute 89 separate PASS results. A focused product probe also passed actual-byte binding, native role routing and explicit entry checks. The v3 contract run recorded 63 fake calls, zero real process calls, zero real resolutions and zero formal samples; the subsequent focused correction recorded zero calls in each category. An interrupted v4 run has no completed semantic or accounting result and is **not** counted as PASS. The 301-row ContinuousMode run and later 8-row focused run likewise remain separate. No full 23-child rerun occurred on `69ac5de`.

## Historical Task 11 trace and sample-validity fix — 74c8691

The second bounded fix changed exactly five evaluation paths. It requires a fresh, per-child native receipt with role, requested Candidate, intended Builder, terminal observation and single-use state. An old Verifier receipt cannot clear a newer Builder's pending review. Unknown or incomplete tool/child lifecycles preserve the fixture and stop without retry. The parser recognizes the supported native `exec` event shape, but actual installed runtime emission and completeness remain `NOT_RUN`.

The narrow CM-05 identity-stop route can collect a valid **no-dispatch** sample only when a complete supported stream shows successful simple reads of the frozen WORK_ORDER/STATUS identities, no child dispatch or open/unknown tool, genuinely conflicting identities, and unchanged saved Base/HEAD/status/diff, sole worktree and full file set/hashes. The collection marker is `CM05_IDENTITY_STOP_OBSERVED`; **independent correctness remains `NOT_RUN`**. Model `PASS` or `BLOCKED` text cannot establish this result. Unsupported transport is retained as unknown; no extra child is launched to demonstrate the stop.

- Task 11 frozen-control SHA-256 at that checkpoint: `47814f3e9f07bea6378913daf19631499bbbc9acb3f4d0b1c51f02fd0b963a42`. Its then-current native-agent authorization binding included `trace_contract=codex_exec_thread_events_with_item_lifecycle` and `safe_no_dispatch_collection=CM05_frozen_identity_reads_and_unchanged_physical_evidence_only`. These are historical controls, not the current Runner-managed role source. Product source, 41 input digest, scenario metrics and pass rules were unchanged.
- Evidence index: `.superpowers/sdd/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan/task-11-trace-fix-evidence.json`; SHA-256 `df81f85a2442024fe48577d4da7bb19d35dd00aaeec65fa738445d015f056c4c`. The current focused v2 child exited `0` with **16/16 PASS**, 36 fake calls (35 serial attempts including five valid CM-05 no-dispatch samples, plus one missing-trace stop), zero real process calls, zero real resolutions and zero formal samples.
- The 16-result run is focused evidence only. It is not a complete CM suite, a seven-suite rerun, a 23-child rerun, or a replacement for the earlier v3 failure and interrupted v4. The earlier 301/301 plus separate 8/8, 84 PASS / 1 FAIL plus separate 3/3, and five-suite 89 PASS remain bound to `69ac5de`.

## Historical Task 11 gate interpretation

The separate, machine-readable states are in [v2-release-gate.json](v2-release-gate.json). The full batch at `4f5a066`, affected checks at `69ac5de`, and latest 16 focused checks at `74c8691` have distinct scope. The latest SHA has no complete V1, static, CM or model-contract suite run; those full-suite gates remain `PARTIAL` at this SHA. The model-contract evidence remains the explicit 84/1 full run plus 3/3 separate correction, not a single green full-suite receipt. Installer update, backup, rollback and uninstall evidence covers disposable fixtures only. Identity, recovery and hard-stop scenarios have deterministic evidence but still need authorized real-machine evidence, so their full gates remain `PARTIAL`.

At the Task 11 checkpoint, formal RED/GREEN model comparison was `NOT_RUN` and had consumed **0** formal samples and **0** actual native child calls. The then-planned authorization was for 35 serial top-level attempts **per phase**, plus native Builder, Verifier and Wave Verifier contexts: 13 planned children per attempt, or 455 planned children per phase, with at most two concurrent children, no recursive delegation or replacement. The planned bound assumed at most two milestones, three Candidate revisions, two automatic rework rounds and two Builder repairs per failure path. Enforcement was `instruction_and_trace_audit`; the platform did **not** provide a cumulative hard total cap. That proposed authorization required acknowledgement of the additional contexts/cost and lack of a hard cap, and exact binding of both trace fields and the frozen-control hash. An older authorization phrased as 35 total model calls was invalid for that route. This paragraph preserves historical planning; the current Runner-managed route and actual counts are above. Reliable total Token Usage across all contexts remains `NOT_AVAILABLE`; top-level terminal usage cannot be treated as the scenario total.

At the Task 11 checkpoint, no actual user-profile install, fresh live permission probe, real Specialist Smoke, production action or remote action occurred. The required real Windows smoke still remains `NOT_RUN`; later diagnostic checks do not replace it. The planned smoke uses a disposable temporary home/state fixture, not the user's actual profile. Runtime Specialist capability is `UNKNOWN`. The current MIT license is unchanged by V2: `LICENSE` SHA-256 `a4d4870a9a4f70332ba806f48970ea5d1b26b0f2fce965c3ff5c490785f5a15b`, and the V2 implementation diff changes no existing image or common dependency manifest. The recorded user license selection delegation remains the basis for the local `LICENSE_GATE=PASS`; this report makes no new rights determination.

`PFC-UPSTREAM-001` remains open in local release records: native Windows Codex deny-read enforcement has not been verified. Historical V1 permission-probe results cannot be replaced by passing V2 fixture tests. `CORE_RELEASE_GATE=BLOCKED`; no stable-release, model-efficiency or token-reduction claim follows from this checkpoint.

## Historical Task 11 independent review and final checks

Task 1–10 implementation commits have accepted task-level independent reviews in the local SDD progress ledger. The first whole-branch specification and quality reviews requested four unique Important fixes: stale accepted-checkpoint identity, hidden intermediate business edits, native Git pre-call failures, and actual V2 product/native independent-role binding. Candidate `69ac5de` addressed these but R2 found two more unique Important trace/sample-validity issues: a stale Verifier receipt could clear a new Builder pending state, and a correct CM-05 no-dispatch stop could not be collected as a valid sample. Candidate `74c8691` is the bounded second fix. Specification R3 and quality/Ponytail R3 approved their scoped fixes with no remaining C/I/M findings. The quality reviewer independently ran a pure native-trace probe: 4/4 PASS, exit 0; it made no model or native child call. The review range begins at `8d2fe2df69b4167f4fb37df41ccd99fd29615395` and includes the current evaluation-runner Candidate and documents.

| Review | State | Report / finding disposition |
|---|---|---|
| Specification compliance | PASS / APPROVED R3 | Closed SPEC-R2-I1/I2 for the reviewed five-path implementation scope; 0 C/I/M; not release approval |
| Quality, safety and evidence integrity | PASS / APPROVED R3 | Closed Q-R2-I1 and accepted bounded CM-05 behavior; 0 C/I/M; pure trace probe 4/4 PASS |
| Ponytail simplicity review | PASS R3 | No extra dependency, generic telemetry framework or second authority source |

The R3 review receipts are `.superpowers/sdd/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan/task-11-final-spec-review-r3.md` (SHA-256 `c9103fb30dbdd93a843096c3610815832ec4418ea83900aa6aff358f665cc310`) and `task-11-final-quality-review-r3.md` in the same directory (SHA-256 `10bb65053f44ec43520237fd2669de7c9ed51ad69f48579a231d29e056fdeccc`). The independent quality probe result there is `task-11-quality-r3-probe-result.json`, SHA-256 `e6c3b9a872a97cc3c515ba0b6b74a21e65fc5461f54919afcb92efa28c7184f4`.

At that checkpoint, final scoped Git diff/status/index checks and the seven-path documentation commit were pending Goalkeeper action. Four process rulings, including the then-planned native-context authorization boundary and its cost if wrong, remained recorded in the SDD progress ledger and Goalkeeper control draft; they did not waive any missing release gate. This is historical pending-work text, not a current authorization to commit.

Task 11 stopped before formal model evaluation. Its next-gate record preceded the later Task 12 authorizations and invalid attempts. Task 12 is now `PARTIAL`, as described in the current progress section; stopped authorizations cannot be reused for retries. GREEN, Windows smoke, commits and remote actions are not authorized by this update.
