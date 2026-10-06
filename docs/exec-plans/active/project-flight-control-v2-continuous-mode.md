# Project Flight Control V2 Continuous Mode execution ledger

Status: `TASK_12_PARTIAL_LOCAL_REPAIR_AND_SOURCE_PUBLICATION_CHECKPOINT`

This is the active V2 execution ledger. Resume from this file, the approved implementation plan, and Git history. Report any missing evidence as a gap; do not infer a passed gate.

## Immutable inputs and baselines

- Approved design: `docs/project-flight-control-design.md`
- Approved design version: `PFC-DESIGN-v2.0-approved`
- Approved design state: `APPROVED_FOR_IMPLEMENTATION`
- Approved design SHA-256: `fda8edc9b476e94f387ad553118a9d4982cfb11439d018d8595fecbfeeb259f6`
- Implementation plan: `docs/superpowers/plans/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan.md`
- Documentation baseline commit: `8d2fe2df69b4167f4fb37df41ccd99fd29615395`
- Implementation baseline commit: `8d2fe2df69b4167f4fb37df41ccd99fd29615395`

## Current execution state

- Completed through: `Task 11 — deterministic regression, truthful V2 gates, whole-branch review`.
- Tasks 1–11: `COMPLETE` in the local deterministic implementation scope, with independent specification and quality review. This documentation checkpoint records Task 11 completion; no formal/live gate is promoted.
- Historical accepted checkpoint / full deterministic baseline: `4f5a066ab9c16575a5da5e133cf31349ed00dc35`.
- Accepted implementation Candidate: `74c8691129303460d7915085cc056574b893b0a1`. Initial final-fix commit `69ac5de5df5c2a94bd93197251ec38f42fb44f40` changed 39 evaluation paths; the trace correction changed five. Product instruction bytes remain unchanged from their frozen source.
- Branch: `codex/pfc-v1-implementation`.
- Task 11 batch: all 23 deterministic child processes exited 0 under Windows PowerShell `5.1.26100.9444`.
- Original wrapper: exit 1, with 22 PASS and one `StrictSchema INVALID_OUTPUT`. The original output and metadata remain unchanged. StrictSchema emits seven PASS markers before its final PASS JSON; an independent exact-envelope parser verified the saved output and rejected 15 malformed variants. No evaluation was repeated to obtain this reconciliation.
- Coverage: 812 top-level results after reconciliation; ContinuousMode includes all 29 scenarios `SC-32` through `SC-60` within 294 checks. ContinuousModeModelContract has 70 checks, 62 fake calls, zero real process/resolver calls, and zero formal samples.
- Final independent review: `SPEC_COMPLIANCE PASS`, `QUALITY PASS`, `PONYTAIL PASS`. R3 reports record Critical 0 / Important 0 / Minor 0 in their scoped closure reviews; no unresolved implementation Critical or Important finding remains.
- The original whole-branch reviews requested four unique Important corrections: immediate-predecessor acceptance, complete intervening control-commit history, native Git failures before model invocation, and actual V2 product/independent-acceptance binding. All are now closed through the original reviewers' scoped follow-ups.
- R2 exposed two remaining trace defects (replayed old receipts and incorrectly excluded safe stops); R3 closes both after the bounded correction. Historical FAIL reports and pure reproduction evidence remain available; no actual model execution or observed data loss was claimed.
- Affected checks: ContinuousMode 301 PASS plus a separate 8-row focused pass; ModelContract v3 retains 84 PASS / 1 FAIL, exit 1, followed by the repaired original failed check plus accounting/tripwire, 3 PASS with exit 0. Five compatibility groups contribute 89 PASS, all child exits 0. This is combined evidence, not a new full-batch PASS or one 85/85 ModelContract run. Interrupted v4 and earlier failures remain preserved.
- Trace correction checks: 16 focused PASS, child exit 0, including the original 35 serial fresh fake loop and five CM-05 no-dispatch safe stops retained as valid samples; independent correctness remains NOT_RUN. That run used 36 fake callbacks total (35 serial plus one missing-trace case), zero real process/resolver calls and zero formal samples. Quality independently ran four pure trace probes, all PASS. These focused results are not a full-suite rerun.
- Open blocker: Task 12 formal RED is `PARTIAL` (2 attempted, 0 valid, 2 invalid, 35 valid still required). Task 13 GREEN and Task 14 Windows smoke are `NOT_RUN`; Specialist runtime capability is `UNKNOWN`; Token Usage for formal RED is `NOT_AVAILABLE`. `PFC-UPSTREAM-001` remains unresolved.
- Core release: `BLOCKED`. Passing local deterministic checks does not establish a stable release or runtime permission isolation.
- Remote actions: current user authorized ordinary GitHub source and README updates; no force, merge, rebase, release or deployment.
- Next gate: `STOP_BEFORE_NEW_TASK_12_FORMAL_RED_AUTHORIZATION`. The prior RED authorization stopped on its first invalid attempt. Any further RED needs a fresh explicit grant for the remaining 35 valid samples, with the 35 top-level attempts and Runner-managed role-context budget stated separately. Canary runs do not count as formal samples. No GREEN or Windows Smoke is authorized by that RED grant.

## Task 12 progress (2026-09-27)

- The four diagnostic Canary runs are not formal samples. Canary 4 observed two successful native command events; the CLI version differed from the earlier runs, so it does not isolate the Windows backend argument as the sole cause.
- The Runner now adds the explicit Windows sandbox backend when user configuration is ignored on Windows. Current Runner SHA-256: `2ca18f432cb70e5d694c0e8cfcd1c77646df39afa5fa4173ab3a00e636e6d1d8`; deterministic regression coverage is in `evals/run-evals.ps1` (SHA-256 `330704786093814d8b0163b25e9b15922e92c009ceade6d234f1b902a728ef4d`).
- Frozen artifact and seven scenario hash bindings were reconciled without changing scenario, prompt, schema, Base SHA, metric, or pass-rule content. Current frozen-control SHA-256: `4abd1d648384d7091bf6a4e9439ff5d0132b62b39284721482a8424676e4628d`.
- Deterministic recheck on 2026-09-27: `ContinuousModeModelContract` exited 0; every reported row passed, including frozen-control/fixture checks, zero formal samples, and invocation accounting (`real_process_calls=0`, `real_resolutions=0`, `fake_calls=63`, `formal_samples=0`). `BuilderEfficiency` exited 0 with 6/6 PASS. `git diff --check` passed. No model evaluation was run.
- Hash-rebind independent review: `SPEC_COMPLIANCE PASS`, `QUALITY PARTIAL`, Critical 0, Important 0, Minor 1. The Minor finding is that a complete deterministic-result summary had not been persisted for independent verification; this recheck and its compact receipt are now recorded in the local Task 12 Ledger. The earlier Runner-fix review was SPEC/QUALITY PASS with no Critical or Important findings.
- The independent status audit found that the three final verification documents under `docs/verification/` still contain the pre-rebind Frozen Control SHA-256. Reconcile them with the final observed gate state during Task 14; do not treat those older release summaries as current hash evidence.
- Task 12 changes remain uncommitted. The pre-existing `task-3-report.md` is a protected historical exclusion and remains untouched and unstaged. Final release documentation remains for Task 14 so it reflects the completed gate state rather than an intermediate snapshot.

## Task 12 role-source alignment (2026-09-28)

- Goal: make the frozen control and future authorization check accurately say that Runner separately launches Builder and Verifier, while preserving all evaluation limits and result schema.
- Scope: `frozen-control.json`, `run-evals.ps1`, the directly related deterministic authorization test, required hash bindings, and this Task 12 ledger only.
- Non-goals: no change to scenario tasks, prompts, fixture/Base SHA, metrics, pass rules, output schema, user settings, account/login state, Git identity, or remote state; no Codex/model/evaluation process and no Git commit.
- Acceptance: the frozen control identifies Runner-managed separate role sessions; the formal preflight binds the authorization to that exact control and rejects mismatches before dispatch; the deterministic fake test passes without creating fixtures, making Codex calls, or committing files; one independent read-only review finds no Critical/Important issue.
- Plan: focused regression test (verified: failed first on the old control key as expected) -> control and authorization guard alignment (verified: local control and auth helper test passes) -> deterministic verification and hashes (verified) -> independent read-only review (one stale comment was corrected; same reviewer's follow-up passed).
- Initial state: implementation worktree already contains prior Task 12 changes; preserve them and the protected `task-3-report.md`. Prior formal RED remains 2 attempted / 0 valid / 2 invalid.
- Deterministic verification on 2026-09-28, repeated after correcting the reviewer's stale comment: `RunnerRoleAuthorization.Tests.ps1` passed, including frozen artifact/manifest/effective-prompt hash checks, Runner source validation, authorization mismatch rejection, and rejection of native Codex events as Runner role evidence. `RunnerOwnedLifecycle.Tests.ps1` passed 14/14. Three related PowerShell scripts parsed under Windows PowerShell 5.1. `git diff --check` passed. The broader ModelContract suite was not run because it creates Git fixture commits, which this authorization forbids.
- Current hashes: `frozen-control.json` `b4e66147d01136cf21dd513a5d5f5d3cfa6e087446eb9dff04ee573701843a7b`; `run-evals.ps1` `33e4efe976e3493ea1d4364681d27fcc2d3727dbb8ff6ec3c2bf2466153699be`; `CodexRunner.psm1` `f76780e04b25641f920c70ea3df4c9c95b0a15aceec7f86ce27cd94e2f0e1bb3`; `RunnerRoleAuthorization.Tests.ps1` `9b56611f6382dc8e4d95abcb03538b8d6ec8299554c014999c7d6ff50deb6023`; `ContinuousModeModelContract.Tests.ps1` `a751c8c0f7ce66c88fe2e2c23c307c7c0e4c860db339a721ef22144ae24fa15d`.
- The previous 13-per-attempt / 455-per-phase values are retained as maximum authorized role-context ceilings, not expected usage. Formal RED remains 2 attempted / 0 valid / 2 invalid. The independent read-only review initially found one Minor stale comment; after correction, the same reviewer confirmed the wording and hash binding. No unresolved Critical or Important finding remains. No Codex/model process, evaluation, commit, or remote action was run.

## Accepted task checkpoints

| Task | Scope | Accepted checkpoint |
|---|---|---|
| 1 | Approved baseline and execution ledger | `6fcc6e96702c99ba0f61a6347b5afc8a63d12007` |
| 2 | Skill-level RED behavior and contract tests | `c8d6f1ffdf843a5c565962d600ddd67dff879d9b` |
| 3 | Strict control templates and schemas | `ecfc2df1e21a1f0288649df76ff15569fcd43710` |
| 4 | Single-authority references | `d94e3fe21c89e5eb8cb07078853a6402261bf7c6` |
| 5 | Explicit Skill entry | `5a3f8b2864e3b8e49d2e34679d717c9e8c08a080` |
| 6 | Builder and Verifier profiles | `724b6ef1f4659dd19023719465103901c65e5242` |
| 7 | Pure continuous-policy evaluator | `e75e028c8caec3ac9c9db34c08b0616bfe430611` |
| 8 | Deterministic scenarios and unexecuted smoke driver | `27eecd3322a16f18405ac4802f16740222e645b8` |
| 9 | Versioned installer lifecycle and rollback | `920a80499a3f29501338f57c61ae4c64202055bc` |
| 10 | Frozen model contract and evidence preservation | `4f5a066ab9c16575a5da5e133cf31349ed00dc35` |
| 11 | Deterministic evidence, whole-branch corrections and independent R3 closure | Code `74c8691129303460d7915085cc056574b893b0a1`; this documentation checkpoint |

## Evidence and recovery

- Detailed local recovery ledger: `.superpowers/sdd/2026-09-20-project-flight-control-v2-continuous-mode-implementation-plan/progress.md`.
- Original deterministic batch: that plan's `task-11-evidence/20260923T042249Z-ede5599d15b045e29be9cf32624b8c8c/aggregate.json`.
- Original aggregate SHA-256: `b491a42874f793896382e2353e4c8212292b331ea2e0dd71c95bd9f62ba8ae2b`; original wrapper outcome remains `FAIL`.
- Independent saved-output normalization: `task-11-normalized-evidence.json` in the same ignored plan workspace, SHA-256 `78fe71a80259e7127fa89562f8aaafa752b1ca395f79702de8ff1a639515fea2`; `PASS`, 23/23 children, 812/812 results, zero reconciliation issues.
- StrictSchema reconciliation: `task-11-strictschema-reconciliation.md` in the same ignored plan workspace. Original wrapper failure remains visible separately from the reconciled child result.
- Final fix report and index: `task-11-final-fix-report.md` and `task-11-final-fix-final-evidence.json` in the same ignored workspace. Index SHA-256 `af5cef7e3a4665c10fe5b3ae838e918d3ac30d7eada9247ec4f14a2a75af220c`; Goalkeeper verified 39 source hashes, 11 preserved-file hashes and 52 evidence hashes/lengths with zero mismatches.
- Actual product source remains `4f5a066ab9c16575a5da5e133cf31349ed00dc35`, with 41 inputs and digest `cc4c299c63090b7d89a5d788b17089c0a31852e3d54825df0b61ac3869fb1399`; the current Runner fix is an uncommitted Task 12 change on top of this accepted source.
- Trace correction report/index: `task-11-final-trace-fix-report.md` and `task-11-trace-fix-evidence.json`; index SHA-256 `df81f85a2442024fe48577d4da7bb19d35dd00aaeec65fa738445d015f056c4c`. Goalkeeper checked five source and 18 evidence hashes/lengths with zero mismatches. Unknown/incomplete child lifecycles retain original fixtures; only the narrowly frozen CM-05 complete-read/unchanged-physical-evidence branch can collect a no-dispatch safety result.
- Independent R3 closures: `task-11-final-spec-review-r3.md` SHA-256 `c9103fb30dbdd93a843096c3610815832ec4418ea83900aa6aff358f665cc310`; `task-11-final-quality-review-r3.md` SHA-256 `10bb65053f44ec43520237fd2669de7c9ed51ad69f48579a231d29e056fdeccc`. Earlier whole-branch/R2 reports retain their original FAIL conclusions; R3 closes the fixed findings without repeating whole-branch review.
- Public summaries: `docs/verification/v2-release-gate.json`, `docs/verification/v2-verification-report.md`, and `docs/verification/v2-known-risks.md`.
- Raw model output remains local and ignored. Formal RED is 2 attempted / 0 valid / 2 invalid; GREEN is 0. No canary raw output is treated as a formal sample.
- Deferred non-blocking observation: existing BuilderEfficiency Git line-ending warnings are retained in local stderr; they do not replace semantic result checks.

## Recorded rulings

1. A reversible local task commit may precede independent task review to provide a stable diff. If wrong, an unapproved local commit exists; no remote or integrated state changes.
2. Goalkeeper dispatched the Task 2 fresh read-only behavior probes because the implementer could not spawn subagents. If wrong, probe context differs from the implementer's context; no product mutation or formal evaluation sample resulted.
3. Freeze the complete future Windows smoke driver now, reusing installer APIs while keeping execution `NOT_RUN`. If wrong, later integration requires a new reviewed Candidate before formal controls freeze.
4. Prepare explicit authorization for native independent-role evaluation so GREEN can exercise the actual V2 product. Keep 35 top-level attempts separate from additional child-model contexts. The native platform exposes a concurrency limit, not a cumulative context hard cap; a planned context budget requires an explicit future acknowledgment and trace audit, and cannot silently expand an old 35-model-call grant. If wrong, the local contract needs refreezing or the user may decline the additional usage; no formal call or cost is authorized by this preparation.

## Remaining authorization gates

- Task 12: `PARTIAL_AWAITING_NEW_EXPLICIT_AUTHORIZATION`. The previous authorization stopped after one invalid formal attempt. A new grant is required before any remaining RED call; it must authorize the valid-run target, maximum new attempts, model/effort/sandbox/login, serial execution, retry policy, and the separate Runner-managed role-context budget. Preserve the invalid sample as invalid; do not count a diagnostic Canary as RED.
- Task 13: formal GREEN requires its own later authorization.
- Task 14: real Windows smoke requires its own later authorization. No Specialist, live permission probe, real-profile installation, or remote action is implied by the RED grant.
- Later release decisions remain subject to the approved plan and unresolved runtime gates.

## Disposable isolation diagnostic (2026-09-28)

- Status: `NOT_RUN`; top-level Codex calls: 0. Host policy rejected process creation before PowerShell or Codex started; no temporary fixture was created and no event stream exists. Event evidence SHA-256: `NOT_AVAILABLE`. No retry or alternate invocation was made.
- Authorization: `PFC-V2-UPSTREAM-001-DISPOSABLE-ISOLATION-PROBE-20260928-R1`. The rejected launch is not a completed diagnostic or a formal sample. The host returned only `blocked by policy`; the precise rejection reason is unknown. It is not evidence that PowerShell cannot start or that the user lacks administrator rights.

## Launch diagnosis and bounded completion route (2026-09-28)

- Scope of this follow-up: local diagnosis, synthetic checks, CLI help/version discovery, one independent read-only reviewer, and this ledger. No product, Runner, test, frozen control, credential, Git identity, or remote change; no user-setting change was requested. No Codex model invocation, dummy-file permission probe, or formal evaluation was performed. The unexpected native helper attempt during help discovery is recorded separately below.
- Confirmed shell result: explicitly invoking Windows PowerShell `5.1.26100.9444` with `-NoProfile -NonInteractive` succeeded, exit 0. An earlier check using the tool's `shell` selector stopped at the version guard before any check ran; the explicit executable invocation then verified the required version. Neither operation attaches to the user's existing administrator terminal or establishes that this process is elevated.
- Diagnostic-design correction: the rejected ad hoc launch selected legacy `--sandbox workspace-write` but did not define a deny-read rule for the external dummy file. It cannot establish whether the project's custom `pfc-controlled` deny-read requirement works. Current official documentation separates the legacy sandbox and named permission-profile paths; the existing Runner already keeps them separate at `evals/lib/CodexRunner.psm1:1106-1112`. The runtime blocker `PFC-UPSTREAM-001` remains open. Documentation is not a test of the installed CLI.
- Synthetic verification under PowerShell 5.1, exit 0: native command samples use `item.exit_code`, not `item.exitCode`; mixing an otherwise valid JSON event with synthetic stderr makes the event input invalid. Both checks passed. Four existing Runner/test scripts parsed without errors. These checks do not verify model execution, permission enforcement, or a full test suite.
- Independent static reviewer: `/root/launch_static_audit`, read-only, no file changes or derived agents. The ad hoc script also conflated nonzero exit with access denial, did not establish whole-turn completion, and discarded recoverable evidence. These are downstream design defects, not a proved cause of the host's pre-launch policy rejection. No corresponding new defect was established in the current project Runner, so no speculative source fix was made.
- Existing-probe scope check: `launch-probe.ps1` builds arguments only; the handshake module validates results, not sandbox enforcement. The full existing probe also tests writes, path variants, and private-source roots. It must not be invoked unchanged under a two-dummy-file authorization or represented as passed by a two-file result.
- Source checks: [official permissions](https://learn.chatgpt.com/docs/permissions), [Windows sandbox](https://learn.chatgpt.com/docs/windows/windows-sandbox), and [sandbox command reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli). Local help takes precedence over current website examples for command syntax.
- Installed-command discovery: `codex sandbox windows --help`, intended to print help, instead attempted a native sandbox child with argv `windows --help`; it failed before that child started, with `CreateProcessAsUserW failed: 2` (file not found). This is **one failed native helper invocation**, not a help-only success, model call, completed file probe, or formal sample. No dummy target files had been created. The helper was not retried. This new command-shape error does not establish the cause of the earlier host `blocked by policy` rejection.
- Safe help discovery then succeeded: `codex --help`, `codex help sandbox`, and `codex --version`, each exit 0. Installed version is `codex-cli 0.158.0-alpha.2.1`. The actual usage is `codex sandbox [OPTIONS] [COMMAND]...`, with `-P/--permission-profile`, `-C/--cd`, `-c/--config`, and `--include-managed-config`; there is **no `windows` subcommand** in this installed Windows build. A future diagnostic must use that verified syntax. No new sandbox child was started by these help/version commands.
- Current hashes rechecked unchanged: frozen control `b4e66147d01136cf21dd513a5d5f5d3cfa6e087446eb9dff04ee573701843a7b`; Runner `f76780e04b25641f920c70ea3df4c9c95b0a15aceec7f86ce27cd94e2f0e1bb3`; run-evals `33e4efe976e3493ea1d4364681d27fcc2d3727dbb8ff6ec3c2bf2466153699be`.
- Outcome: `PARTIAL`. PowerShell launch, bounded synthetic checks, and CLI syntax discovery passed; the original host-policy reason and runtime isolation remain unresolved. Formal RED remains **2 attempted / 0 valid / 2 invalid / 35 valid required**. GREEN and Windows smoke remain `NOT_RUN`; no release gate is promoted. The same independent read-only reviewer passed the initial diagnostic record's consistency and authorization boundaries; the later installed-CLI discovery is separately recorded here.

- Final same-reviewer follow-up: `PASS` for the supplied updated excerpts, including the failed native-helper accounting, verified local help syntax, and fresh authorization boundary. This was a text-only consistency review, not runtime verification or release approval.

### Next concrete proposal — not yet authorized or executed

Proposed authorization ID: `PFC-V2-UPSTREAM-001-ZERO-MODEL-DENY-READ-PROBE-20260928-R1`.

1. Prepare and review one standalone local diagnostic, separate from frozen scenarios. Installed version and help have now been verified; use `codex sandbox -P <unique-temporary-profile> -C <owned-temporary-workspace> --include-managed-config -c <process-only-rule> ... -- <absolute-Windows-PowerShell-5.1-path> -NoProfile -NonInteractive ...`, never the unsupported `windows` token. These placeholders describe the bounded generated command, not a command for the user to fill in. Bind the explicit permission profile and retain existing managed restrictions. Use mock results to check classification before the one authorized real probe. If those properties cannot be established without reading credentials, editing user configuration, or setup changes, stop.
2. Permit at most **one native sandbox invocation, zero model calls, no retry**. Create one unique owned temporary root with a workspace and two dummy target files: one readable inside the workspace, one outside it under an explicit deny-read rule. Support files belong to that same temporary root. Use a temporary/process-scoped named permission profile with the existing elevated backend and no network; do not combine it with legacy `--sandbox`, relax managed restrictions, change the formal frozen controls, copy credentials, install anything, or change system/user settings. A denied read is valid only with an actual access-denied result; missing files, command failure, missing markers, timeout, or ambiguous results are inconclusive. Never output file contents or personal absolute paths. Keep stdout/stderr separate and preserve ignored local evidence plus hashes; do not reattempt a host-policy rejection by another route.
3. Record the result and stop at the next authorization boundary. A two-file pass is only preliminary evidence, not closure of the full permission gate. If it fails or setup is required, preserve evidence and propose a separately approved supported environment or upstream fix; do not silently switch backends. If it passes, define the remaining full permission checks before separately authorizing Task 12 RED, Task 13 GREEN, and Task 14 Windows smoke and final review. Reconcile the older public release summaries during that final review. No model budget, commit, release, or remote action is granted by this proposal.

This proposal changes the earlier diagnostic from a model-driven legacy workspace mode to an explicit deny-read local-command check. It therefore needs a fresh bounded authorization; the earlier one-shot grant is not reused or expanded. Ordinary preparation and review stay local, with no request to reopen an administrator window.

## Approved zero-model two-file diagnostic (2026-09-28)

- Authorization: user approved the preceding zero-model proposal; ID `PFC-V2-UPSTREAM-001-ZERO-MODEL-DENY-READ-PROBE-20260928-R1`.
- Scope: standalone ignored local diagnostic and deterministic mock checks, then at most one real native sandbox invocation; zero model calls; two dummy read targets only; process-scoped permission rules; no personal settings, frozen evaluation inputs, commits or uploads.
- Acceptance: allowed dummy can be opened for reading; the exact denied dummy returns actual access denied. Missing files, startup failures, timeout, malformed output, extra output or stderr remain inconclusive; no retry. A narrow PASS does not close the whole permission or release gate.
- Files: `.pfc-eval-results/zero-model-deny-read-probe/20260928-r1/` for the diagnostic, mock tests and local evidence; one uniquely owned system-temp fixture for two dummy targets plus the read worker. Preserve evidence and fixture after any anomaly.
- Plan: prepare classifier/launcher and demonstrate mock checks -> validate scope and controls -> execute one native sandbox invocation and record the outcome. Current status: `STOPPED_PREPARATION_EXECUTION_POLICY`; new real probe attempts 0; new model calls 0; formal RED unchanged 2 attempted / 0 valid / 2 invalid.
- Review constraint: interpret the user's zero-AI-call instruction conservatively for this turn; do not dispatch a new reviewer/model. Perform a separate local self-review; independent runtime review remains unavailable rather than claimed PASS.
- Prepared: ignored `probe.Tests.ps1`, containing 18 planned mock assertions for outcome classification and argument controls. `probe.ps1` is not implemented yet. The first test command was meant to demonstrate the missing implementation; instead Windows PowerShell 5.1 refused to load the test script because running scripts is disabled (`PSSecurityException`, `UnauthorizedAccess`, exit 1). This is not the intended failing assertion and not a passed test; assertions executed: 0.
- Stop observed: no alternate invocation, execution-policy override, retry, sandbox process, dummy fixture, model, commit or remote action followed this refusal. No user or system setting was changed. The user's explicit stop-on-anomaly rule is the reason execution ended before the one permitted real probe.
- Preserved test-file SHA-256: `d6453c8f11a7921d48c63ef5bf37a228d43a6963539ca55b096fc8772fa27a4d`. `git check-ignore` confirmed it remains ignored; `git diff --check` passed. No other project source/control hashes were changed by this preparation.
- Remaining prerequisite: separately authorize read-only inspection of effective execution-policy scopes and, only if no managed policy forbids it, a process-only script-execution setting for this diagnostic. Do not alter persistent policy or override managed restrictions. Preserve this failed preparation receipt and do not count it as a real isolation attempt.
- Supplemental authorization received: the user approved reading execution-policy scopes and using a process-only local-script permission if no organizational rule is set. Both `MachinePolicy` and `UserPolicy`, plus all other scopes, were `Undefined`; the unmodified effective policy was `Restricted`. Only new Windows PowerShell processes use `-ExecutionPolicy RemoteSigned`; no persistent setting is changed. The initial preparation failure remains preserved.
- Preparation resumed: expected missing-implementation assertion confirmed under PowerShell 5.1; implemented the standalone diagnostic. Mock coverage caught and corrected a duplicate parameter declaration in the generated worker helper before any real invocation. Final deterministic result: **22 checks PASS**, exit 0, real sandbox calls 0, model calls 0. `preflight.json` binds the final script/test/policy evidence hashes. A separate local self-review verified the exact dummy-file scope, managed-config inclusion, one-attempt marker, separate output capture, no model command and no automatic cleanup/retry. No independent model reviewer was called.
- Ready for the one real invocation. The process-only named profile extends `:workspace` and explicitly denies the exact outside dummy file, with network disabled; this checks one deny-read carveout, not all outside paths or the complete historical `pfc-controlled` profile. No full permission or release acceptance can be inferred from it.
- Real invocation completed and stopped: **1 attempted native invocation, process started, exit 1, no timeout, 0 model calls, 0 formal samples**. The worker produced no startup marker or result; both read outcomes are `NOT_AVAILABLE`. Status: **INCONCLUSIVE / PROCESS_FAILED**, not a permission PASS or FAIL. The two dummy files remained unchanged. The consumed `attempt.used` marker prohibits another invocation; no retry, replacement, code correction or cleanup followed the real-run anomaly.
- Failure evidence: native stderr rejected the configured filesystem path as invalid (it must be absolute, home-relative or a special root). The error belongs to the just-created dummy-file rule; the dotted CLI key retained a quote and did not preserve the complete `.txt` path. This is a diagnostic argument/configuration failure before the read worker, not proof of an upstream isolation failure or the cause of the earlier host-policy rejection. The 22 mock checks did not exercise the installed CLI configuration parser; that gap is now explicit. Proposed correction for a later authorization: transmit the filesystem rule as one TOML table value rather than a quoted path embedded in a dotted CLI key, and validate that representation before a separately authorized real attempt. This correction has **not** been applied or run.
- Evidence kept locally and ignored: `preflight.json`, `launch.local.json`, `stdout.raw.txt`, `stderr.raw.txt`, `result.json`, `failure-summary.json`, the consumed marker, scripts, and the owned temporary fixture. Result SHA-256 `bef8108eb01e41625b14bc6fc6068cc3a2ed8ccdaa2087dfc13945442b5077cd`; stdout SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`; stderr SHA-256 `8f0bf29d398b3f40f138165fe5de491870a449639649af4ccac00af72e6db024`. Final diagnostic script SHA-256 `fe78e4546527f27c7cd3c07028d868363c463e9b4b03ab22a909e71d648c528c`; tests SHA-256 `8c791d47dbca001c54e182af940f35bc1896e5e44e1aa83b62bd97fc22bd79eb`.
- Post-process read-only policy check: all five scopes still `Undefined`; effective policy again `Restricted`. No persistent policy change was made. Final current status: `STOPPED_REAL_PROBE_INCONCLUSIVE_CONFIGURATION`; historical formal RED remains 2 attempted / 0 valid / 2 invalid, with 35 valid still required. GREEN, Windows smoke and the full permission gate remain unverified. No commit or remote action.

## Authorized zero-model argument correction, second probe (2026-09-28)

- Tracking ID `PFC-V2-UPSTREAM-001-ZERO-MODEL-DENY-READ-PROBE-20260928-R2` refers to the user's new approval to correct argument passing, add local verification and execute one additional real zero-model check. This is not a retry under the consumed R1 grant. No model calls, permanent settings, organizational-policy changes, frozen-input edits, commits or uploads are authorized.
- Old R1 files and fixture are preserved. New scripts and evidence are under ignored `.pfc-eval-results/zero-model-deny-read-probe/20260928-r2/`, with their own one-attempt marker. The diagnostic differs from R1 only in the filesystem override representation and the tracking ID: pass one TOML table as the `filesystem` value rather than putting the quoted file path in the dotted CLI key.
- Verification: the new regression assertion failed against the old representation as expected. After correction, 22 PowerShell 5.1 mock assertions passed. Another 12 checks used the Windows argument parser and Python's standard TOML parser across four synthetic paths (spaces, apostrophe, Unicode, and dotted filenames); all preserved the exact denied path and sandbox/network controls. This validates formatting, not the installed Codex configuration loader or actual enforcement. No new model reviewer was called; a separate local scope review confirmed the two-line diagnostic change.
- MachinePolicy and UserPolicy remain `Undefined`, as do the other scopes. Only process-specific `RemoteSigned` is used. The preflight receipt binds the script, tests, independent-format-check script, argument receipt and preserved R1 result hashes. State: `READY_FOR_ONE_REAL_PROBE`; this authorization has consumed 0 real invocations and 0 model calls so far.
- Final observed result: **PASS for this two-file diagnostic only**. Exactly one new native sandbox invocation started and exited 0; worker startup and matching receipt were present; inside dummy `ALLOWED`, explicitly denied outside dummy `DENIED`; stderr empty; no timeout, retry or model invocation; both dummy files unchanged. The corrected inline-table representation was accepted by the installed CLI in this actual run.
- Verified-state receipt: `20260928-r2/verified-state.json` under the ignored probe evidence directory binds the result, script, tests, argument validation, raw output/error and post-process policy hashes. The diagnostic script SHA-256 is `664e7f67558d06a03bafe800e91d579f07dc30327693f7d2ac0fcb78ecfccde0`; tests `f071c4c99a78d63fda39d2254e5d0228be59beb0323a26e7885f3040480b93cf`; argument verifier `fb983a9d893d065786e051abb7c310ad4b82bd812bdb6a404baff82e83665c41`. Original R1 result hash was rechecked unchanged. Evidence and the owned temporary fixture remain preserved locally; no cleanup or rerun was performed.
- Post-process policy verification: all five scopes still `Undefined`, effective policy `Restricted`. Final diagnostic state `COMPLETED_NARROW_PASS`; 34 local mock/format checks PASS, one real diagnostic PASS, new model calls 0. No independent model reviewer was invoked. The explicit single-file carveout result is not proof of every outside-path boundary, the complete historical `pfc-controlled` profile, or the full permission/release gate. `PFC-UPSTREAM-001` stays open pending the remaining specifically authorized permission checks. Formal RED remains 2 attempted / 0 valid / 2 invalid, 35 valid required; GREEN and Windows smoke are not run. No source/frozen-control edit, Git commit or remote action.

## Approved expanded zero-model file-protection check (2026-09-28)

- Tracking ID: `PFC-V2-UPSTREAM-001-ZERO-MODEL-PERMISSION-MATRIX-20260928-R1`; authorization is the user's current explicit expanded-check approval, not a retry under an old grant.
- Goal: test current `pfc-controlled` rule structure with owned dummy work files, denied evidence/profile roots, protected filename patterns, and alternate paths/junctions. All targets and link destinations remain inside a unique system-temp fixture. Only the temporary root/name bindings differ; no production configuration is edited.
- Scope: new standalone diagnostic and mock tests under ignored `.pfc-eval-results/zero-model-permission-matrix/20260928-r1/`, owned temporary files, and this ledger. No model/subagent, formal evaluation, source/frozen-input edit, user-setting/credential access, commit, or remote action.
- Acceptance: preserve managed restrictions and the elevated Windows backend; only process-specific RemoteSigned; inspect policy first; demonstrate deterministic fail-stop/receipt/argument checks before at most one real sandbox invocation. Any unexpected allow, missing target, error, timeout or ambiguous result stops further checks immediately, with no retry. Unsupported coverage remains unverified.
- Plan: prepare and verify mock tests -> validate temporary targets and exact rule/argument bindings -> invoke once, preserve and classify evidence. Current state: `PREPARING`; sandbox attempts 0, model calls 0. Independent model review is prohibited; perform a separate local self-review.
- Initial branch/HEAD: `codex/pfc-v1-implementation` / `7ad957e4de5a9822e0647bf56b07650788db4d83`. Prior dirty Task 12 files and protected historical exclusion remain untouched. Formal RED stays 2 attempted / 0 valid / 2 invalid / 35 required. Full release acceptance remains blocked until all required evidence exists.
- Preparation verified: expected missing-implementation failure observed before implementation; PowerShell 5.1 fail-stop/receipt checks 22 PASS; native Windows argument roundtrip and standard TOML parsing 9 PASS across three synthetic path forms. The template checker initially rejected a blank delimiter line; corrected that local diagnostic parser before the real invocation, then verified exact project pattern equivalence. No product rule changed.
- Fixture ready: 32 ordered checks (3 normal read/modify/verify; 5 denied evidence-directory operations; 6 simulated profile operations; 12 protected-filename read/write-open checks; 6 alternate-path/junction operations). Protected-file write tests request write access without changing content; normal-file modification is real and subsequently verified. The create-denied check only targets a new dummy name. All existing targets and the junction destination were verified under the owned temporary root.
- Managed execution policy scopes are Undefined under PowerShell 5.1; only this process uses RemoteSigned. Local self-review confirms strict first-anomaly stop, separate raw output, one-attempt marker, no model or subagent entry point, no cleanup or remote/config mutation. Symbolic links, 8.3 paths, actual user sources, real model runtime and full Windows smoke are explicitly not covered. Preflight binds the launch, worker, core, CLI binary and verification files. State: `READY_FOR_ONE_REAL_EXPANDED_CHECK`; actual attempts 0, model calls 0.
- Final observation: **FAIL_ISOLATION**, `PROTECTED_DUMMY_ACCESS_ALLOWED`, first failure `evidence_create`. Exactly one native sandbox process ran, exited 0, no timeout/stderr; the diagnostic wrapper exited 2 to report the failed protection requirement. The first 7 operations matched expectations: normal read/modify/content verification; denial of evidence-directory listing, existing-file reading, nested-file reading and existing-file write access. Operation 8 unexpectedly created `new-dummy.txt` inside the explicitly denied dummy evidence directory. Read-only post-check confirms that new file exists and is 0 bytes; original protected dummy contents are unchanged.
- Fail-stop observed: no operation after number 8 was executed. The remaining 24 simulated-profile, protected-filename and alternate-path/junction checks are `NOT_RUN`, not PASS. No retry, replacement, new model/subagent call or subsequent diagnostic invocation occurred. All temporary targets, scripts and raw evidence are retained. No real personal file or credential was accessed by the diagnostic.
- Evidence: ignored `zero-model-permission-matrix/20260928-r1/result.json` SHA-256 `2f762226a42b8d2b66d64472988732612935ad1dbba457a815e047cd280da1bd`; `verified-state.json` SHA-256 `2dcf5001c5ff282e5b230dbb18b7536aaca2acd3087b7e13aa633dba84804707`. The latter binds scripts, local checks, preflight, raw output/error and preserved-input hashes. Protected source/frozen inputs and the earlier R2 result hash remain unchanged. Post-process PowerShell 5.1 policy scopes are all Undefined, matching the pre-check baseline; no permanent settings changed. `git diff --check` passed; evidence is ignored.
- State: `STOPPED_REAL_EXPANDED_CHECK_FAIL_ISOLATION`. The denial of existing-file reads does not imply that creating new files is blocked. The cause of this read/create discrepancy is **not determined** by this one check. It does not establish whether the CLI's applied rule translation, Windows permissions or another implementation detail is responsible. No fix or speculative workaround was applied.
- Next proposal, not executed: separately authorize zero-model diagnosis of the existing temporary rule/launch receipts and this owned dummy directory's file-permission metadata, alongside directly relevant local code. Establish why file creation remained allowed before any conditional fix or new live check. Keep all evidence intact and do not loosen protection requirements. `PFC-UPSTREAM-001` and full permission/release acceptance remain open; formal RED is unchanged at 2 attempted / 0 valid / 2 invalid / 35 required. GREEN and complete Windows smoke remain unrun. No commit or remote operation.

### Read-only diagnosis of the create-denial gap (2026-09-28)

- Authorization: `PFC-V2-UPSTREAM-001-CREATE-DENIAL-READONLY-DIAGNOSIS-20260928-R1`. This phase was read-only except for this ledger entry; no Codex/model/subagent launch, rerun, permission edit, cleanup, or raw-evidence edit.
- Launch and rule binding checked: the saved command selected a fresh named profile and the owned temporary workspace, included managed configuration, used the elevated Windows backend, and supplied the exact intended filesystem rule. The serialized rule matches the project template: `extends = ":workspace"`, deny rules for `.env`, `*.env`, and `auth.json`, plus explicit deny roots for the temporary evidence and mock profile directories. The existing `ControlledProfile.psm1` source contains those project rules. Worker receipt had the expected two-line shape, ended at `evidence_create`, exit code 0, and stderr was empty. This rules out a missing or malformed launch argument as the observed cause.
- Permission-list evidence (all identity names withheld): the owned evidence directory has an explicit `Deny Read` entry, while an inherited `Allow Modify` entry remains. Windows' `Modify` right on a directory includes adding files (`CreateFiles`). Its ACL fingerprint is `de0c355eda64e6a9c55d39428ed9e911393b03920f1204d7fda681d56caa5a2d`; the workspace fingerprint is `acd273a3cdfa5e12d622a1115c20aa6fea95eff0ee90e179ce98b637b984a657`. The existing evidence file and the unexpectedly created zero-byte file have the same file ACL fingerprint `4fbce5a99a542c7d8decb19eb556d8401bc05b9a9f4af9fdb7a9339bd3a6d628`.
- Root cause established at the permission boundary: the directory's applied Windows permissions block reading but leave inherited file creation/modification rights in place. Reading/listing and opening an existing protected file for writing were denied, yet Windows accepted creation because the parent directory still grants `CreateFiles`. This explains the observed gap; it is not an authentication issue or a malformed serialized rule. The check does not establish why the installed sandbox translates that deny rule into this incomplete directory permission list.
- Evidence hashes: launch record `79bf44df44ad8ae2ad306d9e27875912d4b63a7be77349c09b59ff873043e325`; result `2f762226a42b8d2b66d64472988732612935ad1dbba457a815e047cd280da1bd`; captured output `100ad462041cd914c8e0ee4475fb82505a44014bfdd7337c4931a0c34d4bad49`; empty stderr `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`; diagnostic entry `23d2431e33251d2ba1ca9a67b3d0eb1be7cc6882f49ac80fd666aee8e54ce266`; diagnostic core `77122f5ede7f3878d87af736ec255122b38e2772408bef0a1ff76e620d9c97ed`; project rule source `9a945c35e875a3a68550afd985a930e8e0afb7c9e790ee2d033c178837c105e9`.
- Diagnosis state: `ROOT_CAUSE_CONFIRMED_DIRECTORY_CREATE_RIGHT_REMAINS_ALLOWED`. The 24 operations skipped after the first mismatch remain `NOT_RUN`. The empty synthetic file and all earlier records remain preserved. A code change or another live check needs separate authorization; do not count this diagnosis as resolving the runtime permission gate. `PFC-UPSTREAM-001` and release acceptance remain open. Formal RED remains 2 attempted / 0 valid / 2 invalid / 35 required. No commit or remote operation.

## Protected historical exclusion

- Path: `task-3-report.md`
- Classification: `HISTORICAL_EXCLUDED`
- Initial SHA-256: `f04452a828cfeece1031f715df1f8fea39b2d8686c6a20ad05575540df78cde1`
- Initial bytes: `52786`
- Commit action: `FORBIDDEN`
- Delete action: `FORBIDDEN`
- Candidate action: `FORBIDDEN`

`task-3-report.md` is retained in place as historical material. It must not be edited, staged, committed, deleted, copied into evidence, or included in a Candidate.

## 最小修复与一次性虚构文件检查（2026-09-28）

- 授权：PFC-V2-UPSTREAM-001-CREATE-DENIAL-MINIMAL-FIX-VERIFY-20260928-R1。没有调用模型或子智能体，没有修改个人设置、全局 Git 设置或旧证据，没有提交或执行远程操作。
- 本地修改：ControlledProfile.psm1 为每个明确禁止的目录增加了对其内部路径的禁止规则；Revision4Isolation.Tests.ps1 加入相应断言，并让测试只使用虚构的临时个人设置目录。本轮未改动冻结场景、评分条件或提示内容。
- 本地检查：Revision4Isolation.Tests.ps1 的 32 项全部通过；新检查脚本的模拟结果判断测试 25 项通过；Windows 命令参数和规则格式检查 9 项通过。系统自带的 Python 启动别名不可用，随后使用本机随 Codex 提供的 Python 完成同一项检查，结果通过。准备阶段确认 32 项检查、临时目录范围、组织规则加载、网络关闭和单次标记均符合计划。
- 唯一一次真实检查：启动 1 次本地 Windows 沙盒检查；模型调用 0、子智能体调用 0、正式评估样本 0。前 7 项符合预期：普通虚构文件可读、可修改、修改结果正确；受保护目录无法列出，已有文件和嵌套文件无法读取，已有文件无法打开写入。第 8 项 evidence_create 失败：程序仍能在受保护的虚构目录中新建文件。检查随即停止；其余 24 项为未执行，不得算作通过。
- 失败影响：真实检查不通过，不能确认该保护规则已经有效。新建的虚构文件为 0 字节，保留在本次专用临时目录中；未清理。结果没有证据证明真实用户文件受影响。
- 原因状态：这次结果证明当前最小修改仍未挡住“新建文件”；为什么实际沙盒没有执行该新增规则尚未查明。本授权规定异常后停止，所以没有重试，也没有继续改代码。
- 文件指纹（SHA-256）：
  - 修改后的权限代码 evals/lib/ControlledProfile.psm1：d739ae92dcdb7d111f26b59dd4aa1371c2cec7f805895db752f0f6b7a1e04b69
  - 修改后的确定性测试 evals/tests/Revision4Isolation.Tests.ps1：aca87ee806a1b376aa5d0b471abe59920a785e67d75d49f2388ec2cba16559a3
  - 本次结果 result.json：e11162f6c16618f5d37d09d9e3be6e0f0d1b1ff93f62a02750ef03027b5efd7c
  - 沙盒标准输出 stdout.raw.txt：f0ca10e54eea88eedefbf45a483a2cd2a5243ecc8455c6531d9633e36262c4a6
  - 沙盒错误输出 stderr.raw.txt：e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  - 单次检查脚本 probe.ps1：9ccb7abead9c92d748d4775740939102d6c829c0fdb6ed6d2d1a37a63f1a3cf8
  - 检查逻辑 probe-core.ps1：7f5f7a2bdb411a37d6cd5397974cbec4f72e1d08fc6408894398a80b70de1072
  - 模拟测试 probe.Tests.ps1：f10b7cd7efdc52377c6968c063c75b28f81f57f53bc4b04b4e22782fe9dcb1fc
  - 参数检查程序 verify_arguments.py：c951e190ac638561ec59c2da8053540c31f85e1f160ee6962ef9b45500bbcc5c
  - 准备记录 preflight.json：f1317d36cb4e73351aa700d3d78e923b159ec6c0683fd20fcde46dc693f2b2a2
  - 单次运行参数 launch.local.json：06f708b3e63be4cd73d72698b981edfd6cb0aa74e44831fa3d7e29f14d89ba96
  - 模拟测试结果 mock-validation.json：6b0bca31901bf22a600b2b3944d2c32ef16c48ed5ff69dfab4910b987d3bfea2
  - 参数检查结果 argument-validation.json：0d80d31d70e082e2aeb1505d6e7ce8cfbe7e275ca30f4277ea9ef4f7f61b65ed
- 当前状态：STOPPED_REAL_MATRIX_FAIL_ISOLATION。Task 12 正式评估累计仍为 2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。失败的权限检查不属于正式评估样本。
- 后续建议：另行授权只读分析本次受保护虚构目录中新建文件成功的原因；确认原因后，再单独授权最小修复和新的单次虚构文件验证。此次一次性检查额度已用完，不得在本授权下再次运行。
## 新建文件失败的只读取证（2026-09-28）

- 授权：PFC-V2-UPSTREAM-001-CREATE-DENIAL-POSTFIX-READONLY-DIAGNOSIS-20260928-R1。本阶段只读，没有运行检查、沙盒、Codex 或模型，没有改代码、权限、设置、临时文件或旧证据。
- 规则传递核对：准备记录状态为 READY。保存的启动参数中包含受保护目录本身及其所有子路径的拒绝规则、工作区规则、组织规则加载、网络关闭和 elevated Windows 沙盒设置。未展示或记录任何绝对路径。
- 失败位置：记录状态 FAIL_ISOLATION，第一处不符合预期的是 evidence_create：预期拒绝，实际允许。之前 7 项结果符合预期；总计划 32 项、实际观察 8 项、剩余 24 项未运行。运行过程无错误输出、无超时，子进程正常结束。虚构新文件大小为 0 字节。
- 权限清单：受保护虚构目录及已有、新建虚构文件的 Windows 权限指纹分别为 bd6457f88dabc9c46c09ef3f3875a4621e4725c13bdd886355fb8ece301fef5f、c4e7b615d9a8c4c74f6d803620dbbb7a47b1fc5cd94703ba5bd9a619a718ad21、b4c346f5fe5d6a24e4cf3386444c12b4f626e9cb4099314ed747de140eed5f89。权限列表中有拒绝读取的项目，但没有拒绝 CreateFiles（创建文件）权限的项目；同时存在继承的 Allow Modify 和 Allow FullControl 项目，这些权限包含创建文件的能力。新建文件成功与这份权限清单相符。未读取或记录账户名称、个人路径或文件内容。
- 代码对照：ControlledProfile.psm1 确实写入目录子路径拒绝规则；Revision4Isolation.Tests.ps1 确实检查该规则文字存在。但这只能证明规则被生成和测试检查到，不能证明 Windows 实际权限已经禁止新建文件。
- 结论：已确认直接原因在实际应用的 Windows 权限：创建文件所需的权限仍被允许。尚不能确认为什么沙盒把新增的子路径规则应用成当前这份权限清单，也不能确认需改哪一层才能阻止创建。按授权停止，不猜测、不修复、不重跑。
- 本次证据指纹（SHA-256）：launch.local.json 06f708b3e63be4cd73d72698b981edfd6cb0aa74e44831fa3d7e29f14d89ba96；preflight.json f1317d36cb4e73351aa700d3d78e923b159ec6c0683fd20fcde46dc693f2b2a2；result.json e11162f6c16618f5d37d09d9e3be6e0f0d1b1ff93f62a02750ef03027b5efd7c；stdout.raw.txt f0ca10e54eea88eedefbf45a483a2cd2a5243ecc8455c6531d9633e36262c4a6；stderr.raw.txt e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855；ControlledProfile.psm1 d739ae92dcdb7d111f26b59dd4aa1371c2cec7f805895db752f0f6b7a1e04b69；Revision4Isolation.Tests.ps1 aca87ee806a1b376aa5d0b471abe59920a785e67d75d49f2388ec2cba16559a3。
- 正式评估仍为 2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。当前结论不能作为权限检查通过的证据。后续如需定位沙盒为何未落实创建文件拒绝，须另行授权。
## 目录禁止规则映射只读诊断（2026-09-28）

- 授权：PFC-V2-UPSTREAM-001-CREATE-DENIAL-RULE-MAPPING-READONLY-20260928-R1。本阶段未运行沙盒、模型、评估或测试；未修改代码、权限、设置或临时文件；未提交或执行远程操作。
- 本机帮助：只运行了一次 codex sandbox --help，退出码为 0。它列出了命名权限配置、加载组织配置和沙盒状态参数，但没有说明 Windows 如何把目录子路径拒绝规则转换成创建权限，也没有展示可单独拒绝新建文件的设置。命令启动时报告无法创建 PATH 别名，因为未找到主目录；未读取个人设置，无法进一步核实设置状态。帮助输出未保存为文件，因此没有输出文件指纹。
- 启动记录：已有参数记录确认受保护目录和目录内路径的拒绝规则确实传入，同时启用了工作区规则、组织配置、网络关闭和 elevated Windows 沙盒。参数记录、准备记录和运行结果的指纹与上次记录一致；运行结果指纹为 e11162f6c16618f5d37d09d9e3be6e0f0d1b1ff93f62a02750ef03027b5efd7c，启动记录为 06f708b3e63be4cd73d72698b981edfd6cb0aa74e44831fa3d7e29f14d89ba96，准备记录为 f1317d36cb4e73351aa700d3d78e923b159ec6c0683fd20fcde46dc693f2b2a2。
- 规则与测试：ControlledProfile.psm1 会生成目录子路径拒绝文字；Revision4Isolation.Tests.ps1 的 R4-19 只检查这段文字是否出现在配置中，并不尝试真实创建文件。相关文件指纹分别为 d739ae92dcdb7d111f26b59dd4aa1371c2cec7f805895db752f0f6b7a1e04b69 和 aca87ee806a1b376aa5d0b471abe59920a785e67d75d49f2388ec2cba16559a3。当前相关代码没有直接设置 Windows 文件权限的做法。
- 权限证据：受保护目录的权限指纹为 bd6457f88dabc9c46c09ef3f3875a4621e4725c13bdd886355fb8ece301fef5f。其拒绝项没有覆盖创建文件所需权限，继承的 Modify 和 FullControl 项包含创建文件权限。已有虚构文件和新建虚构文件的权限指纹分别为 c4e7b615d9a8c4c74f6d803620dbbb7a47b1fc5cd94703ba5bd9a619a718ad21 和 b4c346f5fe5d6a24e4cf3386444c12b4f626e9cb4099314ed747de140eed5f89；新建虚构文件为 0 字节。
- 结论：已确认当前规则虽被传入，实际 Windows 权限仍允许新建文件，所以现有项目实现不能保证这项保护。仅凭本机帮助与已有记录，无法确定沙盒为何没有把子路径规则转成拒绝创建权限，也无法确认是否存在不改真实文件权限的可靠代码方案。按授权停止，不猜测、不修复、不重跑。
- 评估数字保持：2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。上述权限检查不属于正式评估，也不能报告通过。
## 用户裁定：放弃新建文件拦截要求（2026-09-28）

- 用户明确决定：只放弃“受保护目录内禁止新建文件”这一项要求；其他已有文件限制继续保留。这是接受该项能力不具备，不代表它已通过验证。
- 保留现有读取、已有文件写入、敏感文件名和其他路径限制；不删除现有规则，因为它们可能仍用于这些其他限制。
- R4-19 目前只检查规则文字是否生成，不证明真实 Windows 权限会阻止新建。实际运行中 evidence_create 仍为 ALLOWED；该项作为用户已放弃的要求记录，不再作为继续开发的阻塞条件。
- 扩大检查中未执行的 24 项仍未验证：模拟个人目录 6 项、敏感文件名 12 项、替代路径和链接 6 项。用户没有放弃这些限制；不得记为通过。权限总体状态仍为 PARTIAL。
- 该裁定不改变正式评估的样本标准，也不授权模型调用。Task 12 正式 RED 仍需单独明确授权；Task 13 GREEN 与 Task 14 Windows smoke 各自仍需单独授权。
- 本次只记录决定，没有修改代码或测试，没有运行检查、沙盒、Codex 或模型；没有清理临时文件或执行远程操作。
### 放弃“禁止新建文件”这一项（2026-09-28）

用户决定仅放弃“禁止新建文件”要求，保留其他文件访问限制。已把 R4-19 的说明改为：它只检查是否生成了后代路径拒绝规则，不能证明 Windows 实际阻止新建文件。此次只更正测试说明和本地记录，没有更改运行权限规则、冻结评估条件、个人设置、旧证据或 Windows 权限。上一次 32 项检查中，前 7 项达到预期，第 8 项新建文件保护未达到预期，后续 24 项未运行；这些未运行项目仍未验证，不能视为通过。Task 12 正式 RED、Task 13 GREEN 和 Task 14 Windows 检查仍分别需要新的明确授权。
### 新建文件要求调整后的确定性复核（2026-09-28）

- 使用 Windows PowerShell 5.1 运行 .\evals\tests\Revision4Isolation.Tests.ps1：32/32 PASS，退出码 0。R4-19 现在准确说明它只检查规则文字是否生成，不声称实际系统一定会阻止新建文件。该测试使用模拟运行器，没有调用 Codex 或模型。
- 针对本次涉及的测试与 Ledger 运行 git diff --check：PASS。测试文件 SHA-256：5c3921a21dc49622f49009e85ff575b817e2e7a1a09289a11923e2d064e259ca。
- 本结果只覆盖本地确定性检查。其他 24 项文件保护仍未验证；正式 RED、GREEN 和 Windows 实机检查仍未运行。
## R2 警告来源只读核对（2026-09-28）

- 授权：PFC-V2-T12-R2-WARNING-READONLY-20260928-R1。仅读取已列出的 Task 12 记录、R2 警告输出、启动摘要和事件摘要；没有运行 Codex、模型、子任务、沙盒或评估，没有改动代码、运行原始记录、设置或 Git。
- R2 两份错误输出摘要中，按角色解析提示匹配规则分别找到 8 条与 44 条警告行；44 条文件另有 52 个“warning”字样。44 条不能仅凭数量解释为 11 次启动。
- 对应事件摘要分别记录 15 条和 44 条事件。44 条事件中有 4 条 error、14 条 item.started、23 条 item.completed；没有明确的子任务开始、结束或交接事件。另一份有 4 条 error、8 条 item.completed，也没有明确子任务生命周期事件。启动摘要只保留任务结果字段，没有警告数量或时间。
- 时间无法可靠地建立因果关系：事件字段 received_at_utc 实际带东八区 +08:00，错误输出时间带 Z。按相同显示钟点比较，44 条警告中有 14 条靠近 item.started、6 条靠近 error；由于时间标记不一致，这不足以证明警告由任务启动造成。
- 结论：已确认 44 条角色解析警告存在，但现有获准证据不能确认它们为什么重复，也不能证明与 Runner 启动次数一一对应。按授权停止，不推测、不修复、不重跑。正式评估累计仍为 2 次尝试、0 个有效、2 个无效；仍需 35 个有效结果。
- 证据指纹：dispatcher 摘要 c4773257b21154f47762d044e53e0c0a5e6fa495ee14145eae67d30c18a907f5；run-07e7 事件摘要 035d5dbea57bb506e9316ac3542d6c8c0583393039f395797e6cdfe9bd881455；run-84d5 事件摘要 bcf99d0f706bdf54f500677b9e4502fe972241e8aafb31dca96f355f5e9938b6；run-07e7 错误输出 fa81fa6004a39f17c95cb105d9e4d8bbe4fedfc0a67b8b62b1231db76efe7b4e；run-84d5 错误输出 7e8241f7995f9ab6781e07732b4d0d3ac768fad9a4c8e13fab7e9e8faa4471d0。
### R2 角色警告本地诊断（2026-09-28）

- 授权：PFC-V2-T12-R2-WARNING-LOCAL-DIAGNOSIS-20260928-R1。
- 两项本地模拟测试均通过：Runner 角色授权测试；Runner 生命周期测试（14 项）。测试未模拟角色警告数量，因此不能复现 R2 的 44 条警告。
- 已有 R2 摘要：两次运行分别记录 8 条和 44 条角色解析警告；第二次的警告时间与事件时间格式带有不同 UTC 偏移，且事件记录没有明确的子任务开始、结束或交接事件。现有记录不足以证明警告由 Runner 启动子任务引起。
- 结论：44 条警告的确切来源尚未确认。未修改程序、测试或旧运行记录；未启动 Codex、模型、子任务、沙盒或评估。
- 正式评估计数保持：2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。
- 证据指纹：R2 stderr（8 条）run-07e7d74231544612b98dc74efee6512f.stderr.txt SHA-256 fa81fa6004a39f17c95cb105d9e4d8bbe4fedfc0a67b8b62b1231db76efe7b4e；R2 stderr（44 条）run-84d5b0792b0c4ca9860577a8572c026e.stderr.txt SHA-256 7e8241f7995f9ab6781e07732b4d0d3ac768fad9a4c8e13fab7e9e8faa4471d0；对应事件摘要 SHA-256 分别为 035d5dbea57bb506e9316ac3542d6c8c0583393039f395797e6cdfe9bd881455 和 bcf99d0f706bdf54f500677b9e4502fe972241e8aafb31dca96f355f5e9938b6；调度摘要 SHA-256 c4773257b21154f47762d044e53e0c0a5e6fa495ee14145eae67d30c18a907f5。

- 更正：本节授权编号为 PFC-V2-T12-R2-WARNING-RUNNER-LOCAL-DIAGNOSIS-20260928-R1。


## R2 角色警告续查（2026-09-28）

- 用户要求继续查明 R2 的 44 条警告。没有修改程序、测试、冻结条件或旧运行记录；没有运行 Codex、模型、子任务、沙盒或评估。
- 仅对获准的 R2 错误输出做本地脱敏指纹统计：8 条样本和 44 条样本的警告行，去掉时间后均为同一 SHA-256 指纹 8c43f630ca3072af37819ae82c61d869c2ba22c9d8f9002bfaf2ef834f6df924；分别出现 8 次和 44 次。没有展示或保存警告原文。
- 44 条记录分布在 17 个 UTC 秒位（16 个秒位各 2 条，1 个秒位 12 条），跨度约 5 分 13 秒；将时间按 UTC 偏移正确换算后，与已批准事件摘要中的任何事件都没有落在 2 秒以内。此前仅按钟面时间看到的接近不能作为因果证据。
- 该时间段的目录元数据共显示 5 个文件：一个运行 JSONL、一个事件索引、一个错误输出、一个最终结果和一个共享 Markdown。只读了文件名、大小和时间，没有打开 JSONL 或 Markdown 内容；这些元数据不能证明内部子任务与警告的对应关系。
- 当前 Runner SHA-256 为 f76780e04b25641f920c70ea3df4c9c95b0a15aceec7f86ce27cd94e2f0e1bb3。当前代码在 Runner 管理角色时关闭 Codex 自带 Agent，并让 Runner 分别启动角色；RunnerOwnedLifecycle.Tests.ps1 检查了隔离启动参数，先前本地模拟测试结果为 14/14 通过。该测试没有复现 CLI 对角色 TOML 文件的解析警告。
- R2 使用的 Runner SHA-256 为 2ca18f432cb70e5d694c0e8cfcd1c77646df39afa5fa4173ab3a00e636e6d1d8；在本地可见的 5 个已提交版本中未找到该文件哈希。故不能用当前代码证明 R2 当时的具体启动行为。
- 可能原因：R2 的 Codex 原生子任务反复解析同一份角色 TOML 文件，产生相同警告；当前 Runner 管理角色的做法可能避免这种重复。此结论仍未证实，原因是缺少 R2 对应源文件和能把警告与子任务启动对应起来的记录。不得据此把旧无效样本改为有效。
- 正式评估累计仍为 2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。若要验证当前 Runner 是否真正消除重复警告，需要另行授权一次受控的真实运行；本续查没有该授权。
## Task 12 诊断运行入口修复与审查（2026-09-29）

- 授权：PFC-V2-T12-DIAGNOSTIC-CANARY-GATE-FIX-20260928-R1。仅在当前实现工作区检查和修改 `evals/run-evals.ps1`、直接相关模拟测试及必要哈希记录；没有启动 Codex、模型、Canary 或正式评估，没有改用户或全局 Git 设置，没有提交或执行远程操作。
- 原因：原入口只接受固定的 7 个场景、每个 5 次的正式批次，缺少只运行 CM-01 一次的独立诊断通道。
- 修复：新增严格分开的诊断入口，只能为 ContinuousModeModel / CM-01 运行 1 次，必须明确阶段和授权文件，并使用一次性运行凭据防止重复启动。诊断最多启动 13 个角色任务、最多接续 Goalkeeper 13 次、最多启动 27 个 Codex 进程；顺序执行，不重试、不替补。正式 RED/GREEN 仍固定 7 个场景、每个 5 次、最多 35 次；没有改场景、提示、结果格式、起始版本、评分或通过标准。
- 哈希：`evals/run-evals.ps1` SHA-256 `a6b85b6ec366c64396463efd25f4e4354a9ae0f326c2ba53cb4777250e4c69c8`，与 `frozen-control.json` 对应绑定一致；控制文件 SHA-256 `f01027fdd0ccdf8c9af6488b6cfc149dc7fa94f8f685bd5de3789714042178fc`；模拟测试文件 SHA-256 `ce04a07a58638caf28fb2ba3464e6ac1e9754fbd9b8c4fc0fa6e26511b32e1c1`。
- Windows PowerShell 5.1 本地模拟契约测试：97/98 项通过，退出码 1。3 项新诊断入口测试全部通过；正式 35 次模拟边界测试通过；真实 Codex 调用数为 0。唯一失败为 `CM-fix.runner-owned-role-lifecycle-source-and-handoff`，它在本次修改前已存在，本次没有改动它。测试汇总为 228 次假进程调用、0 次真实进程调用、0 个正式评估样本。
- 只读复核：1 位独立审查者结论 PASS，没有发现阻止继续的问题；审查者未修改文件、未运行测试、未调用模型或评估。
- 本次目标代码、测试和冻结控制文件的 `git diff --check` 通过。完整工作区检查仍会报告本记录旧内容的历史空白字符（第 277、280、291 行）；它们不是本次新增，未按本次授权修改。
- 正式 RED 旧计数保持 2 次尝试、0 个有效、2 个无效。当前修复阶段没有真实模型运行；下一步真实诊断 Canary 需要另行授权。

## Task 12 单次诊断在启动前停止（2026-09-30）

- 授权：PFC-V2-T12-R2-WARNING-CURRENT-RUNNER-CANARY-20260929-R1。按用户“继续”恢复；启动前和结束后，Runner、run-evals.ps1 与冻结控制文件的三个哈希均与授权一致。授权文件生成于本地已忽略的目录，没有改动程序、场景、提示、Schema、评分、设置或旧证据。
- 仅启动一次诊断调度程序，使用 Windows PowerShell 5.1；退出码 1。其本次输出为 NOT_RUN，attempts=0、valid_samples=0、formal_samples=0、automatic_retries=0。没有产生原始运行 JSONL，也没有取得一次性运行凭据；实际 Codex / 模型调用为 0。
- 停止原因：本次启动前校验报告无法识别本地命令 Get-FileHash。该命令用于文件哈希校验；父进程在本次准备和结束核对时能够使用它。为何启动后的检查进程没有正确加载它尚未确认，不能据此断言 Runner 产品代码或账号异常。没有再次启动、补跑或修复。
- 本次警告数 0；由于模型没有启动，该数字不能用于判断此前 44 条警告是否消除。没有正式评估样本，既有正式 RED 累计保持 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。TOKEN_USAGE: NOT_AVAILABLE。
- 证据 SHA-256：授权文件 d5a61558d796877cced8fd8076dbfa1ff22f3d9ae50d119cb4cb64fcbc8f5596；本次启动记录 57b3239e14161ba189fb1fde4d9c9a239259ff7e1668d6f8074ee08a3bd6c05e；调度输出 a67961173b4fd95a6f919bcbc358ec24751d1a9ac9f9e327b8f052197643daac；空错误输出 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855；停止原因脱敏指纹 3982a3a9cc2f64f934cf82598ddff382680c5572ea9d9c76829bf804b7b47a33。记录全部保存在本地已忽略的 .pfc-eval-results/，没有展示提示、对话、命令内容或个人路径。
- 后续建议：另行批准零模型的本地启动方式检查，用虚构文件验证 Windows PowerShell 5.1 的校验命令是否可用；只有可重复确认原因后才决定必要的启动方式调整。该建议尚未执行。真实诊断或正式评估仍须独立明确授权；本次因异常已停止，不自动恢复或重试。

## Task 12 frozen-control run-evals 哈希更新（2026-09-30）

- Goalkeeper 仅将 evals/expected/continuous-mode-model/frozen-control.json 中 path == "evals/run-evals.ps1" 对应的 sha256 从 a6b85b6ec366c64396463efd25f4e4354a9ae0f326c2ba53cb4777250e4c69c8 更新为 fba0446fb5b26624547345c3afa0089ac0236148f101cb0aadf19efb928fafc3。
- 更新后的 frozen-control.json SHA-256：bf5ed30656a04af24d2793916b83a6b06064e47ebd591b792de34058285b7890。CodexRunner.psm1 与七个场景的 runner_sha256、manifest_sha256 绑定均与当前文件一致；其他冻结字段未改。
- 本次未运行 Codex、模型、评估或测试，未提交 Git。


Task 12 Runner hash rebind: CodexRunner SHA-256 updated to 3188d7756a6e52ef9d3cd91348210f2b33212dbd2926818f9d4cb7b24c63da7a; seven scenario runner_sha256 and manifest_sha256 bindings updated; run-evals SHA-256 unchanged at fba0446fb5b26624547345c3afa0089ac0236148f101cb0aadf19efb928fafc3; frozen-control SHA-256 153b5bb69bfd0b7ca4ba419a8fd361969116cb0aae08558aeadf11f4eac4c059. Evaluation criteria and scenario content unchanged.
## Task 12 安全修复与独立复核准备（2026-09-30）

- 第一次独立只读审查发现若干会影响路径边界、事件可信度、失败现场保留和临时目录读取范围的问题。修复已限于 Runner、受控权限配置、运行入口及直接相关的确定性测试；未更改冻结任务内容、提示、数据格式、评分、通过条件或基础版本。
- 修复内容：事件记录路径同时拦截两种斜线写法的越界；严格核对 `test_only` 必须是布尔值；运行前建立空的 Runner 生命周期记录以区别“确实没有派发”和“记录丢失”；CM-05 只在 Runner 记录完整且确认零角色进程时接受安全停止；只有 Runner 和 Goalkeeper 记录都完整终结后才清理夹具；移除对整个系统临时目录的读取放行。
- Windows PowerShell 5.1 确定性验证：Runner 生命周期测试 17 项通过；Revision 4 隔离测试通过；ContinuousModeModelContract 全部检查通过；Bootstrap、Harness、BuilderEfficiency 检查通过。合同模拟累计 228 次假进程调用、0 次真实进程调用、0 次真实命令解析、0 个正式样本。所有验证均未调用 AI 模型。
- 哈希绑定复核：`evals/run-evals.ps1` SHA-256 `c1f171ebb12758140f1ed5ae8e20d898386652aac144c03774281bca35198c7d`；`evals/lib/CodexRunner.psm1` SHA-256 `ecd38fdd9bd3619effef707fb75726a642670fa3bcfc152ef1a6b268a5779c85`；`evals/lib/ControlledProfile.psm1` SHA-256 `d739ae92dcdb7d111f26b59dd4aa1371c2cec7f805895db752f0f6b7a1e04b69`；`frozen-control.json` SHA-256 `4fa7f99679aaf950572fba5291084b609110dd35acd5b3473611cc5be5104917`。
- CM-01 至 CM-07 的冻结清单哈希依次为：`2e3b5ae9930c691ed1dfc54205d01f6c9d90acd80b2f80eebf660c01a686b8d2`、`eb79ad577d20813d7e0a26334f21e79fee8e83dea6fe1759d67affbe25025f02`、`93c8c0a21177705ebf76d0924e0eaa3c732b4cd76dae339f719b657e0645d8b1`、`84a956a335931b8507d6b45b691f47238161542604e41921c73933b2d4cc81cc`、`69bc7c37bfdcf70c4179c9a038363295b8fec50474ec2f89164eac82cbb0d3ab`、`a57e5c07c16e307ac9d884ac10323f3074a4cfb95a56aa867370ce5486d85760`、`f2da04655bcc0cd2cb89e8dc6280321c5b3b53aa0d5e5dbac9b994e1d5b81093`。七份清单中的 Runner 哈希均与当前 Runner 文件一致，且冻结控制文件中的清单哈希均与实际文件一致。
- `git diff --check` 与哈希绑定检查通过。未提交 Git，未执行远程操作；未打开或修改 `task-3-report.md`，也未把运行原始记录复制到聊天或计划文件。
- 正式 RED 计数保持 2 次尝试、0 个有效、2 个无效；仍需 35 个有效结果。本次本地修复和模拟检查不计为正式样本。
- 下一步：由此前同一位独立审查者只读复核本次修复及控制哈希；本阶段不启动 Codex、模型、Canary、正式 RED 或 GREEN。
## Task 12 修复复核与 PowerShell 启动检查（2026-09-30）

- 第二次独立只读复核：SPEC_COMPLIANCE PASS；QUALITY PARTIAL；Critical 0、Important 0、Minor 1。审查者确认首次提出的路径越界、字段类型、CM-05 事件证据、夹具清理、临时目录访问范围和哈希问题均已处理，且未发现冻结任务、原始提示、Schema、Base SHA、指标或门槛发生变化。唯一未验证项是 Windows 实际沙盒运行时的文件访问效果；不能把配置文字测试当作实机通过。
- 按用户授权，用虚构文件在独立 Windows PowerShell 子进程中检查 `Get-FileHash`。子进程版本为 5.1.26100.9444；使用 NoProfile、NonInteractive、临时执行许可及 `-File` 启动。命令启动前已存在、配套模块可用，虚构文件 SHA-256 计算成功，退出码 0。未修改临时启动脚本，因为本次没有复现“命令不可用”，因此没有可证实的修复原因。
- 该检查只说明普通 Windows PowerShell 5.1 子进程可使用 `Get-FileHash`，不能说明此前模型评估中的终端异常已解决；不得据此把既有无效运行改为有效。此次没有启动 Codex、模型、Canary 或评估。
- 正式 RED 仍为 2 次尝试、0 个有效、2 个无效；仍需 35 个有效结果。Task 12 及核心发布门槛仍为 PARTIAL/BLOCKED，须继续按计划完成后续验证；Windows 沙盒实际效果仍未验证。
## Task 12 单次继续诊断结果（2026-09-30）

- 在用户新的持续开发授权下，按原有参数上限执行了 1 次 CM-01 RED 诊断运行；最多 1 次，无重试。所用模型配置仍为 `gpt-5.6-terra` / `medium` / `workspace-write` / 既有登录；远程操作为 0。
- 本次状态：运行器退出码 1；尝试 1、有效 0、正式样本 0、自动重试 0。返回状态为 STOPPED；模型状态为 BLOCKED；原生命令事件轨迹为 NOT_AVAILABLE；Runner 轨迹为 NO_DISPATCH_OBSERVED，观测到的角色子任务 0，Codex 进程调用 1。没有可用事件证明命令曾执行，故按停止规则结束，不再重试。
- 本次错误输出文件大小为 0 字节，其中可见警告行 0 条、错误行 0 条；这不能证明原始事件记录里没有其他警告。本次 Token Usage: NOT_AVAILABLE。
- 证据指纹：本地调度摘要 `e6a95839469cc3d57a634ee1f5040b4d5d32efbdeb0bc5235f05d40caf7ca5fc`；空错误输出 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`；本地授权记录 SHA-256 `d1b407ceaad236486ba013417b91e072a8b36c4b42d55c4fb02426b35af37bb1`；本次冻结控制仍为 `4fa7f99679aaf950572fba5291084b609110dd35acd5b3473611cc5be5104917`。
- 原始 JSONL 保留在本地忽略目录，本次未打开、复制或展示。该诊断不计入正式 RED；正式累计仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。
- 停止结论：当前阻碍不是本机 Windows PowerShell 5.1 的 `Get-FileHash` 常规能力（虚构文件检查已通过），而是这次实际运行没有取得可读取的原生命令事件且 Runner 没有派发角色任务。具体原因尚未确认；需要先做零模型、本地、脱敏的事件与启动路径核对，再决定是否存在直接相关的最小修复。本次没有继续进行后续模型评估。
## Task 12 事件索引补充取证（2026-09-30）

- 更正说明：上一节记录了运行停止时尚未打开原始 JSONL；之后为定位失败，在本机对该次原始 JSONL 做了受限解析，只提取事件种类、顺序、可靠用量字段和文件指纹，没有展示、复制或保存对话、提示、命令或原始事件内容。文件仍只保存在已忽略目录。
- 原始 JSONL SHA-256 `89145345e84614aaead2c83b48fdf36ed4f464ab2d664d6561e4f0cec798fae1`；事件索引 SHA-256 `b323c45fab5b370e67769aed383a2b432799e717c7a8d9a98fa0cb08cca26dde`。原始记录 10 行；事件顺序为 thread.started、turn.started、4 条 error、item.completed(error)、2 条 item.completed(agent_message)、turn.completed。没有 command_execution 或 collab_tool_call 事件。
- 已确认“原生轨迹不可用”的直接代码原因：`Read-CmNativeTrace` 只接受已列明的线程、轮次和项目事件；遇到顶层 `error` 或 `item.type=error` 就按未知事件退回 `NOT_AVAILABLE`。这解释了为何虽有 turn.completed，归一化仍报告原生轨迹不可用。
- 另一个问题仍未查明：这次记录没有命令执行和角色交接事件，Runner 观察到未派发角色；4 条错误消息不能按安全分类归入登录、PowerShell 命令、角色配置、传输或配额问题，也不能据此认定为旧的 4 条角色警告基线。模型为何没有返回可用的角色派发请求仍未知。没有对错误消息作猜测或据此修改 Runner。
- 已从实际 `turn.completed.usage` 可靠字段取得本次诊断用量：输入 34,216 tokens，输出 1,273 tokens。该诊断仍不计入正式 RED。
- 处理结论：停止所有新的模型评估，不重试。正式 RED 仍保持 2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。下一步应先在零模型范围内确认 Runner 派发请求为何未产生，并让事件解析器以不丢失错误信息的方式报告错误轨迹；任何解析器调整都不得把无命令运行认定为有效样本。

## Task 12 错误事件解析修正与复核（2026-09-30）

- 在用户持续开发授权下完成本地零模型修正；本次没有启动 Codex、模型、Canary 或评估，没有修改用户设置、登录信息或全局 Git 设置，也没有提交或执行远程操作。
- 已重复确认的代码原因：事件解析器把真实出现的错误事件当成未知事件，因此丢弃了可用的终结状态并返回 `NOT_AVAILABLE`。现在会保留错误事件的数量和终结状态，但不保存错误原文；错误事件也不会被误报成“没有派发任务”。这解释了轨迹显示错误的原因，但没有解释模型为什么没有要求 Runner 派发 Builder / Verifier。
- 修改文件：`evals/run-evals.ps1`、`evals/tests/ContinuousModeModelContract.Tests.ps1`、`evals/expected/continuous-mode-model/frozen-control.json`。冻结任务、提示、数据格式、起始版本、评分和通过条件未改；冻结控制仅重绑运行脚本哈希。
- 哈希：`evals/run-evals.ps1` 为 `1a90b932d93b1e38f8a7e114b32b97a903130a1b3f0ec6944ff3c7c2438af7b8`；`evals/tests/ContinuousModeModelContract.Tests.ps1` 为 `0ccccb26070b48d138abfc5e05b3f7a5f6f7da7175419586b689b037ec0e60be`；`frozen-control.json` 为 `bbba3caf1d22579b367793f4a5291cf281ebb9b9ec327e868ca699a95dda4b49`。运行脚本哈希与冻结控制绑定一致。
- Windows PowerShell 5.1 模拟验证：错误事件专项检查 13/13 通过；Runner 生命周期检查 17 项通过；文件隔离检查 32 项通过；启动检查 17 项通过；Harness 53 项通过；冻结文件和七个场景清单的哈希绑定检查通过；目标文件的语法与 `git diff --check` 检查通过。
- 完整 ContinuousModeModelContract 测试曾尝试两次，但约 150 秒内没有输出，随后停止；因此完整套件状态为未取得结果，不能记为通过。其余所列专项检查已单独运行并通过。
- 一位独立审查者只读复核后确认 PASS，无 Critical 或 Important 问题。审查指出，现有冻结条件没有要求错误事件数必须为零，且已有规则明确允许恢复后完成的运行；因此不能临时新增“出现任何错误就判无效”的门槛。审查者没有修改文件或运行评估。
- 剩余问题：模型为何没有发出可由 Runner 执行的角色派发请求仍未确认；Windows 沙盒实机隔离效果也未验证。正式 RED 仍是 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本；单次诊断不计入正式样本。当前代码修正不代表 Task 12 或整个项目已达到可发布状态。

## Task 12 PowerShell 启动与确定性模拟补充（2026-09-30）

- 在用户持续开发授权下继续本地工作；本次没有调用 Codex 或模型，没有提交 Git，也没有执行远程操作。
- 已可重复确认启动故障：直接启动的 Windows PowerShell 5.1 使用自带 Utility 3.1.0.0 时能执行 Get-FileHash；同一电脑通过 Start-Process 启动并在 PSModulePath 前置虚构的 Utility 7.0.0.0 后，命令自动发现走错版本并失败。启动脚本显式导入当前 PowerShell 的 PSHOME\Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1 后，虚构文件 SHA-256 检查通过。该根因解释了本次受控启动检查的失败，但不能证明此前模型未派发角色的原因也是它。
- 确定性测试不再打开旧的模型运行记录；测试改用内嵌虚构事件。长路径证据检查按记录的实际保存位置核对，临时目录在清理前验证确属本次创建。没有改动场景任务、提示、评分或通过条件。
- Windows PowerShell 5.1 本地模拟：ContinuousModeModelContract 103 项通过、0 项失败；BuilderEfficiency 6/6 通过；虚构文件启动探针通过；两项证据保存检查通过。目标脚本语法检查、git diff --check、46/46 文件哈希和 7/7 场景清单哈希均通过。
- 独立只读审查：PARTIAL，Critical 0、Important 0、Minor 0。审查者确认本次合成事件、启动探针、长路径检查及运行器冻结哈希绑定；但未查看早前已修改的 7 组场景提示，因此不能把那些提示内容记为本次审查已核实。
- 当前指纹：evals/run-evals.ps1 SHA-256 0d5460f2d0a0e6068999f4271396ac9b90fa2a8f92208a7fbd396a178360d230；evals/tests/ContinuousModeModelContract.Tests.ps1 SHA-256 4a7bb4ac7c221d6c7fbcad4150655cd0ee50fa287327703b2b1f10402f903142；frozen-control.json SHA-256 0f8272b2a0b55475842ceef3cd398657d2339686363aecf5227eee0da18a98c4。冻结控制中的 46 个文件与 7 份场景清单均匹配当前内容。
- 本次没有运行模型评估。正式 RED 仍为 2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。此前确认的角色任务未派发问题、实际 Windows 沙盒访问效果及早前场景提示的独立复核仍未解决；Task 12 和项目整体不能标记完成。

## Task 12 CLI 登录目录预检（2026-09-30）

- 在正式评估前仅运行了 CLI 版本与登录状态检查，没有启动模型。当前版本为 codex-cli 0.159.0；版本命令提示找不到用户目录，登录状态命令退出码 1，错误类别为 HOME_DIRECTORY_UNAVAILABLE。原始报错内容未写入记录，未读取或修改登录资料、个人设置或凭据。
- 影响：当前这个自动化终端无法确认并使用既有登录，因此没有启动正式 RED。之前两次无效样本仍保留，正式数字仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。
- 后续：需要在能够找到现有用户目录的 PowerShell 会话中先运行只读命令 codex login status；只需确认它是否成功，不发送完整输出或凭据。通过后再从同一会话启动冻结的串行 RED 批次；若版本、登录或控制哈希仍不一致，立即停止。
## PowerShell 5.1 虚构文件检查补充（2026-09-30）

- 使用 Windows 自带 PowerShell 5.1.26100.9444，在独立子进程中对本次创建的虚构文件运行 Get-FileHash；检查通过，退出码为 0，临时测试目录按路径边界清理。
- 另一次手工构造的模块冲突模拟没有复现预期结果，因此不能据此确认当前启动方式仍有同一故障，也没有进行代码修改。只读确认 evals/run-evals.ps1 已在哈希检查前显式导入 PowerShell 安装目录中的 Utility 模块；本次没有改动该 Runner 或冻结条件。
- 本次未调用 Codex、模型或评估，未触碰账号、登录资料、个人设置、全局 Git 设置或远程。此检查只证明普通 PowerShell 5.1 可处理虚构文件；不代表正式 RED、GREEN 或 Windows Smoke 已恢复。
- 正式 RED 仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。

## Task 12 PowerShell 命令路径支持（2026-09-30）

- 用户在 Windows PowerShell 中确认：使用 Codex 程序完整路径执行登录状态检查成功；直接输入 codex 失败，原因是该窗口找不到这个短名称，并非账号未登录。
- 可重复根因：底层 Runner 已能接受完整程序路径，但启动前仍无条件检查 Get-Command codex；连续模式主任务、Builder、Verifier 和后续接续也没有把完整路径传到启动器。因此在短名称不可见的 PowerShell 中，即使提供完整路径仍会提前报错。
- 最小修复：新增 -CodexExecutablePath 可选参数，只接受存在的绝对 .exe、.cmd 或 .bat 文件；将其传递给连续模式主任务、角色任务及接续启动。未修改永久 PATH、用户设置、登录资料或评估条件。
- 修改文件：evals/lib/CodexRunner.psm1、evals/run-evals.ps1、evals/tests/RunnerTerminal.Tests.ps1、evals/tests/ContinuousModeModelContract.Tests.ps1、evals/expected/continuous-mode-model/frozen-control.json、七个场景清单，以及本记录。七个场景的任务、提示、指标、通过条件、Schema、Base SHA 均未改；只同步了 Runner/入口文件与清单哈希。
- 定向验证：虚构启动程序且移除 codex 的 PATH 后，完整路径专项测试 PASS；Runner 生命周期 17 项 PASS；Runner 角色授权 PASS；RunnerRevision3 17/17 PASS；BuilderEfficiency 6/6 PASS；Harness 53 项 PASS；Bootstrap 17 项 PASS，且传入可选完整路径时参数可正常接收；四个 PowerShell 文件语法检查 PASS；冻结控制和七个清单的哈希核对 PASS；git diff --check PASS。
- 完整 ContinuousModeModelContract 本次运行约 150 秒无输出，已停止；结果为 NOT_RUN/未完成，不计为通过。首次运行完整 RunnerTerminal.Tests.ps1 时，在旧的 TEST-1 计时断言处失败，路径专项尚未执行；修复后单项路径测试通过，完整 RunnerTerminal 套件未重新跑。
- 当前哈希：evals/lib/CodexRunner.psm1 7323880b069d6a224eec8866f4fbcdac6121f63f7532573633f0b1cf167a6a77；evals/run-evals.ps1 8304d56fc5fea09ace2ea18ba73e3745d663594044e065690e027d03f9b87f47；frozen-control.json 4870ad858381276d0e98cb9916abe62c41b58b7dec4112eac3a31b0d1703ae2a。
- 本次没有启动 Codex、模型或评估，没有更改 Git 身份/用户设置，没有 Commit 或远程操作。正式 RED 仍为 2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。TOKEN_USAGE: NOT_AVAILABLE。
- 状态：路径支持修复已通过定向验证；完整合同检查及独立复核尚未完成，不据此标记 Task 12 或项目完成。
- 补充核对：逐个比较七个场景清单与冻结记录，并实际重算 common.md、prompt.md、treatment.md 和 Schema 的哈希及 RED/GREEN 组合提示哈希，7/7 PASS；确认本次只更新运行器绑定，没有改场景内容。

## Task 12 程序路径复核修正（2026-09-30）

- 用户在 Windows PowerShell 用程序完整路径检查登录状态成功；短名称 `codex` 不可用是因为该窗口找不到命令，并非登录失败。
- 独立复核发现：此前的路径判断会把 `C:codex.cmd` 这种依赖当前目录的写法当作完整路径，且未实际覆盖旧的自动查找方式。已将直接传入的路径限制为完整本机盘符路径；相对盘符写法会被拒绝。未改变永久 PATH、账号、登录信息或用户设置。
- 先用本地虚构程序复现：新增的相对盘符测试在修复前失败，证明旧检查接受该写法；修复后，完整路径（短名称从 PATH 移除）、相对盘符拒绝、旧 PATH 自动查找三项测试均通过。RunnerRevision3 17/17、Runner 生命周期 17 项、角色授权、BuilderEfficiency 6/6、Harness 53 项、Bootstrap 17 项均通过；4 个 PowerShell 文件语法检查和 `git diff --check` 通过。
- 哈希绑定复核通过：`evals/lib/CodexRunner.psm1` SHA-256 `8efa60773cf9425904d71e1dc113cdda910c3bc954607efad3071318b544dc64`；`evals/run-evals.ps1` SHA-256 `8304d56fc5fea09ace2ea18ba73e3745d663594044e065690e027d03f9b87f47`；`frozen-control.json` SHA-256 `aa20dbf62e145a5ac1e1de34a7e3a0f226c7c14a31b4bce3cd9c38a3dc1a619f`；七个场景的 Runner 和清单哈希均匹配。独立只读复核 PASS，无发现。
- 完整 `ContinuousModeModelContract` 先前运行约 150 秒无输出后被停止，仍记为未完成；完整 `RunnerTerminal.Tests.ps1` 未重跑。不能据此宣称这两项通过。
- 本次没有启动 Codex、模型、Canary 或正式评估。正式 RED 仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本；没有提交 Git 或执行远程操作。TOKEN_USAGE: NOT_AVAILABLE。
- 补充的只读命令版本检查：用户提供的 Codex 程序完整路径返回 `codex-cli 0.159.2`；登录状态由用户在 PowerShell 中确认成功。本次版本检查没有启动模型。
## Task 12 路径诊断 Canary 在脚本启动前停止（2026-09-30）

- 授权：PFC-V2-T12-PATH-CANARY-20260930-R1。授权哈希、CM-01 场景、模型、推理强度、运行权限、程序完整路径及 Windows PowerShell 5.1 预检均匹配。
- 只启动了一次评估脚本；Windows PowerShell 5.1 返回退出码 1。系统在加载 evals/run-evals.ps1 前报告禁止运行脚本，错误类别为 UnauthorizedAccess。没有创建本次运行占用标记或原始 JSONL，因而 Codex 进程和模型调用均为 0。
- 本次诊断启动次数为 1，未重试。标准错误记录仅保存在本地忽略目录，大小 385 字节，SHA-256 3e96f367bb78a9aeaec10909d5449666c34e83ad4f5163a65377f7ef9cae5f7d；授权文件 SHA-256 1ad482b954e67b1b025d2ecc04cf8f7c330cfadc12591fe6095a68405314e0cd。没有把原始记录复制到聊天。
- 原因不是登录失败，也不是程序路径或冻结哈希不符；被拦截的是 PowerShell 脚本执行。未修改执行策略或其他用户设置。下一步需先只读确认是否有组织策略强制限制；若有，必须停止并使用组织批准的脚本运行方式。若没有，需新的单次授权才能考虑仅对该进程临时放行并重新做一次诊断。
- 正式 RED 保持 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。TOKEN_USAGE: NOT_AVAILABLE；未提交 Git，未执行远程操作。
## Task 12 单次路径诊断 Canary R2 结果（2026-09-30）

- 授权 PFC-V2-T12-PATH-CANARY-20260930-R2 已按上限执行 1 次顶层试跑，没有重试。Windows PowerShell 5.1 的 `Get-ExecutionPolicy -List` 显示 MachinePolicy、UserPolicy、Process、CurrentUser、LocalMachine 均为 Undefined；本次仅对启动进程使用 `-ExecutionPolicy Bypass`，没有修改永久设置。
- 运行前核对版本为 codex-cli 0.159.2，模型 gpt-5.6-terra、medium、workspace-write；冻结控制、Runner 和入口文件哈希与授权一致。内层共留下 2 个已完成调用记录，低于 27 次上限；Built-in Agents 未启用。
- 运行失败并停止：Runner 事件记录 Builder 任务启动后失败，没有后续角色生命周期记录。两份最终结果中，一份不是有效 JSON，另一份的 CM-01 RED 状态为 NOT_RUN。归一化状态为 STOPPED，失败类别为“缺少角色结果或候选版本标记”。证据能确认问题发生在 Builder 结果回传/识别阶段；但现有安全摘要不能区分究竟缺少结构化角色结果，还是候选版本 SHA，因此根因尚未完全确认。每条调用事件各有 4 条 error 事件；未读取或保存其正文。
- 从可靠的 `turn.completed.usage` 字段读取到：输入 162,957 tokens（其中缓存输入 110,848）、输出 5,175、推理输出 1,708。这里是本次诊断调用用量，不是正式评估样本。
- 本次没有产生有效 RED 样本；正式累计仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。原始 JSONL 留在本地忽略的 `.pfc-eval-results/`，没有复制到本记录或聊天。未修改程序、冻结条件、个人设置、登录信息或 Git，也未执行远程操作。
- 脱敏证据指纹：Runner 输出 `139580f0d545566e9032495158fec2d4153cb8c4846fc2140761ec7e643ca798`；归一化摘要 `d6b92dcfefbf4cde1cda365d4093fbf4e389dc7c68b90e62f665f73c14309d93`；Runner 生命周期摘要 `be660b693b2bda2bb754c8e455344f17e28266a5322d23557712ad786c7dd2cc`；最终输出异常文件 `c0ace3b2917ba1f5b929cef7911ccab6f556b083e8788a7d88df60d9672d1115`；NOT_RUN 结果 `595b6abfba5d9363485509a2353158e0ca1023d6df4654d429fd271aa543fd88`。原始 JSONL 哈希仅保存在本机评估目录中。
- 后续应先另行授权零模型、只读地查明 Builder 结果为什么不可识别；本次授权已用完，不据此修改冻结条件或再次启动模型。
## Task 12 Builder 结果跨行识别修复（2026-09-30）

- 零模型取证确认失败落在 Builder 返回内容识别处。Runner 要求 BUILD_REPORT 和 CANDIDATE_SHA=40位小写十六进制编号出现在同一行附近；Builder 将标记和编号分行时，旧规则会抛出“角色结果或候选版本编号缺失”。本次没有查看真实运行的提示或对话，因此只能确认这是与 R2 失败类别一致、且可用虚构结果重复复现的解析缺陷，不能断言 R2 的实际返回一定采用了这种分行格式。
- 回归测试先将假 Builder 结果改成两行；修复前 RunnerOwnedLifecycle.Tests.ps1 按预期失败并复现同一错误。最小修复只让 Builder 的识别规则可跨行查找，仍限制在标记后 300 字符内并要求有效编号；Verifier 识别规则未改。
- Windows PowerShell 5.1 下 RunnerOwnedLifecycle.Tests.ps1 最终 PASS，17 项检查通过。测试使用模拟进程和虚构结果；未运行 Codex、模型、Canary 或评估。执行前只读检查策略均为 Undefined；仅对本次测试进程使用临时 ExecutionPolicy Bypass，没有改永久设置。
- 只更新了 CodexRunner.psm1 对应的冻结哈希字段、七个场景清单的 runner_sha256、冻结控制中的七个清单哈希及本记录。场景任务、提示、Schema、Base SHA、指标和通过条件未改。七份清单与冻结控制逐一解析、比对及实算哈希，7/7 PASS；run-evals.ps1 哈希保持不变。
- 最终哈希：CodexRunner.psm1 SHA-256 5d98358cbde6f8f607dd6d1591dc2ed53d3dea3b9305be5d5a0e7196a964754d；run-evals.ps1 SHA-256 8304d56fc5fea09ace2ea18ba73e3745d663594044e065690e027d03f9b87f47；frozen-control.json SHA-256 4429b1bf91d16444f5be998c24a9ae8a54bcd5edd17b467ba13b6f53ad4b9191。
- 七个场景清单 SHA-256：CM-01 c6c6d82d8f374347412a6da5f65f234104b5ae2b1d124ca6617896b419f742ef；CM-02 e07508ddab51fb855a8ab2dbb497238b1721a6502e84f3949d8af821f332948d；CM-03 38c73f4c45d1940ee9cda4a5984bb6e1697ae5d2f27bd6f6e2fb0d30e0d734fb；CM-04 7b535a4053d21ed17abb74ab662cf759eadaf15261da20498b1fd9542bb51762；CM-05 314daf91af8789ee05530cb0cee1a1e07f0958f911768758d33608f10bf19e51；CM-06 cb7de83e3ad36e16707ae5aac63e2bb1826b913aab59a27bcb1981b3c75f9788；CM-07 b09da0ec3e6c50583b5a7110d057e794e6becfff5a59b13c7d655fcf279a1757。
- 同步哈希期间曾发生一次替换格式错误；在继续前已恢复相关哈希行，并确认冻结控制与七份清单均为有效 JSON，所有绑定最终一致。没有提交 Git 或执行远程操作。正式 RED 保持 2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。
- RunnerOwnedLifecycle.Tests.ps1 SHA-256 8a1f821919b5775aa808a54dd7bdee5ab0f7bf67c53083a03343dc873ec10c4f

## Task 12 Builder 候选编号精确边界复核（2026-09-30）

- 独立只读复核发现，Builder 识别规则虽然只捕获 40 位编号，但没有阻止后面紧跟更多字母或数字，因此可能把过长编号误认成有效。该问题在本地新增的虚构 41 位编号用例中可重复出现：修复前 `RunnerOwnedLifecycle.Tests.ps1` 失败，明确指出超长编号被接受。
- 最小修复只收紧 Builder 编号末尾边界，要求 40 位小写十六进制编号后不能继续跟字母、数字或下划线；跨行查找和 300 字符范围不变，Verifier 规则未改。原有 40 位两行虚构结果仍通过，新 41 位虚构结果被拒绝。
- Windows PowerShell 5.1 最终验证：`RunnerOwnedLifecycle.Tests.ps1` 18 项 PASS；`RunnerRoleAuthorization.Tests.ps1` PASS，重新核对冻结 Runner 与七个清单绑定；`git diff --check` PASS。只使用假进程和虚构结果，没有运行 Codex、模型、Canary 或评估。临时执行许可只作用于测试进程；策略检查显示各作用范围均为 Undefined，没有更改永久设置。
- 哈希仅同步本次修复必需字段：Runner `e1b77706e8bbfd7a098cc18a73badc6750ebe81e85ac9a0dbbd648f04abb4eda`；冻结控制 `748622eed7e089f5d2a5254cc0379ffc811163d1386a6e66374ab330eab3cc59`；运行入口 `8304d56fc5fea09ace2ea18ba73e3745d663594044e065690e027d03f9b87f47` 未变；新增/更新的回归测试 `fe8c34b3a192c8672ed08733035a1b8c9483ec4af3d7a61ce017b3a7c411223a`。
- 七份清单哈希：CM-01 `2ddcef47d61decf9bdd0560d3fbf60944426734d0016e3694beec6ccb2b3debe`；CM-02 `ab3566d7cb4397e2def06b3c77dc7a3284ca10483112e8c8968d2a0a258c3846`；CM-03 `8c533d83356fcdd7544ed30c7901aaaeca3a87302f78309e6fc4465d9a902494`；CM-04 `af00fc48631be4b1d23706947384e1590c3871e2e0905733c12258b717b52345`；CM-05 `62f2da35a88f6e267ff06adec44797f8fb618db43ee956e76fc0ba2ae4109506`；CM-06 `4aba96a499abc9e34df534aae9d7eb1a3456520c465f0c4cb3a2cde12c2b8d8c`；CM-07 `706e18d2cb6741c736b7d4922f4294ed5b7c0bdc466778cd34c83aac62ada5dc`。逐份核对后，所有清单的 Runner 哈希和冻结清单哈希均与实际文件匹配；其他冻结字段未变。
- 同一位独立审查者复核最终改动：可接受；Critical、Important、Minor 均为 0。没有提交 Git 或执行远程操作。
- 当前状态仍为 PARTIAL：本地修复及确定性验证完成，但新一轮单次 CM-01 诊断试跑尚未获授权，正式 RED 仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本；本次用量 `TOKEN_USAGE: NOT_AVAILABLE`。

## Task 12 精确指纹诊断试跑记录（2026-09-30）

- 启动前复核发现：授权文本里的 Runner 指纹长 65 位，在 `...18ba73...` 中比真实值多了一个 `b`；Runner 文件、冻结控制中的 Runner 绑定和既有 Task 12 记录均为同一个 64 位值 `e1b77706e8bbfd7a098cc18a73badc6750ebe81e85ac9a0dbbd648f04abb4eda`。冻结控制 `748622eed7e089f5d2a5254cc0379ffc811163d1386a6e66374ab330eab3cc59` 与运行入口 `8304d56fc5fea09ace2ea18ba73e3745d663594044e065690e027d03f9b87f47` 也与授权一致。最初的拒绝是授权文字多字造成的误报，不是代码或冻结文件漂移。
- 使用核实后的 64 位值按原单次范围运行了 1 次 CM-01 RED 诊断。启动器返回 `STOPPED`：1 次尝试、0 个有效诊断样本；只有顶层进程启动，Builder/Verifier 子任务 0 次，Goalkeeper 接续 0 次；记录了 5 条错误事件，Runner 没有观察到角色派发。没有重试。该诊断不计入正式 RED。
- 脱敏归一化摘要 SHA-256：`2e368c183187ca7ffe3105ae99be0045d91aacb76b646a05331fdb851a06ae36`。原始运行记录仅保留在本地忽略的 `.pfc-eval-results/`，没有复制到聊天或计划文本；没有读取提示或对话内容。摘要未提供可靠 Token 用量，记为 `TOKEN_USAGE: NOT_AVAILABLE`。
- 本轮另行复跑的本地模拟验证：`RunnerOwnedLifecycle.Tests.ps1` 18/18 PASS；`RunnerRoleAuthorization.Tests.ps1` PASS；`git diff --check` PASS。未改 Runner、场景或评分条件；本次只补记本地进度记录，没有提交或远程操作。
- 正式 RED 仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。Task 12 仍为 `PARTIAL`：Builder 结果识别修复已通过模拟测试，但本次没有发生 Builder 派发，无法验证该修复对真实派发结果的作用。由于本次诊断触发停止条件，后续不得用此授权重试；要继续调查 5 条错误事件或再次试跑，需单独明确授权。
### 2026-09-30 Canary 1 错误事件只读核对

- 授权：`PFC-V2-T12-CANARY1-ERROR-EVENT-READONLY-20260930-R1`。
- 脱敏摘要 SHA-256：`2e368c183187ca7ffe3105ae99be0045d91aacb76b646a05331fdb851a06ae36`。
- 原始事件记录 SHA-256：`c5345e5b888451e39f40d263af3f417f023b8dfcf5c3f100b9a5c05b69d10216`。
- 记录共 17 行；可确认的类别计数为：线程开始 1、回合开始 1、错误事件 4、错误结果完成事件 1。记录中没有可用时间。
- 4 条错误事件可安全归类为传输错误；额外的 1 条错误结果完成事件未读取其详细内容，因此类别未确认。按授权停止，未继续检查。
- 未展示或保存提示、对话、命令、个人路径或错误原文；未运行 Codex、模型、测试或评估；未修改代码或设置。
- 未能据此确认更具体的故障原因。正式评估累计仍为 2 次尝试、0 个有效、2 个无效；还需 35 个有效样本。
### 2026-09-30 错误类别单条事件授权检查结果

- 授权：`PFC-V2-T12-CANARY1-ERROR-CATEGORY-ONLY-20260930-R1`。
- 依照范围尝试定位此前核对的脱敏摘要和其指向的原始事件记录；按已知运行编号及摘要指纹进行的文件名查找未能定位这两份目标文件。只看到运行对应的标准输出、错误输出文件名，未打开或读取其内容。
- 未检查任何事件详细内容，因此没有对额外的错误结果完成事件作出类别判断；该类别继续标记为未确认。为避免查看授权范围外的文件，检查到此停止。
- 沿用此前记录的证据指纹（本次未重新读取或核验）：脱敏摘要 SHA-256 `2e368c183187ca7ffe3105ae99be0045d91aacb76b646a05331fdb851a06ae36`；原始记录 SHA-256 `c5345e5b888451e39f40d263af3f417f023b8dfcf5c3f100b9a5c05b69d10216`。
- 未运行 Codex、模型、测试或评估；未修改代码、设置或原始记录。正式评估累计仍为 2 次尝试、0 个有效、2 个无效。
### 2026-09-30 Canary 1 单条错误类别复核

- 授权：`PFC-V2-T12-CANARY1-RAW-REFERENCE-FINGERPRINT-20260930-R1`。
- 脱敏摘要唯一匹配；原始记录候选中唯一匹配已知指纹；目标错误结果完成事件唯一。
- 脱敏摘要 SHA-256：`2e368c183187ca7ffe3105ae99be0045d91aacb76b646a05331fdb851a06ae36`。
- 原始记录 SHA-256：`c5345e5b888451e39f40d263af3f417f023b8dfcf5c3f100b9a5c05b69d10216`。
- 目标事件没有可安全使用的错误类别或编号字段；其事件类型只能确认是错误，不能据此判断具体错误类别。依授权停止，未读取错误说明等文字。
- 未展示或保存文件名、路径、错误原文、提示、对话或命令；未运行 Codex、模型、测试或评估；未修改代码、设置或原始记录。
- 正式评估累计仍为 2 次尝试、0 个有效、2 个无效；该错误继续保持未分类。
### 2026-09-30 Canary 1 网络超时原因与处理判断

- 后续用户请求授权对目标错误事件做本机临时分类；只输出分类，不输出或保存错误原文。
- 目标摘要与原始记录的既有 SHA-256 指纹均唯一匹配，目标错误事件唯一。内存分类结果为 `NETWORK_TIMEOUT`；没有 HTTP 状态码或可用的独立错误编号。原文未输出、未写入记录。
- 证据表明本地 Codex 程序已启动并进入任务回合，但请求等待网络回应超时，未产生可供 Runner 继续处理的有效结果，因此没有启动 Builder/Verifier。具体是本地网络、代理/中间链路还是服务端瞬时问题，现有证据无法区分。
- 对照 Runner：其 600 秒上限是本地进程总等待保护，不会延长或修复 Codex 请求内部的网络超时；实现未自动重试。现有逻辑保留错误事件并避免把原文写进生命周期摘要。
- 处理判断：这是外部请求链路超时，未发现可由本地源代码修复的根因；本次不改 Runner、超时参数或冻结控制。自动重试会改变已冻结评估规则，单纯加长本地等待也不能修复连接问题。
- 备选方案：保持本次诊断为失败记录；待网络稳定后，另行授权一次新的诊断运行。也可先做零模型网络连通性检查，但它不能保证模型服务请求成功，且本次未执行。
- 本次未运行测试、Codex、模型或评估；未执行远程操作。正式评估累计仍为 2 次尝试、0 个有效、2 个无效；仍需 35 个有效样本。

## Task 12 本地检查修复与收尾准备（2026-10-01）

- 范围：在用户继续开发要求下，只修复直接相关的本地模拟检查，不启动 Codex、模型、Canary、正式 RED/GREEN 或 Windows smoke；不读取旧模型原始记录、用户配置或凭据，不提交或执行远程操作。
- 已确认的检查问题：终端测试创建了替身程序，但多数用例没有将其作为默认执行路径，可能查找真实 Codex；TEST-1 仍依赖旧诊断原始记录；模型合同测试的两处位置参数调用会把假进程回调绑定到新增的程序路径参数。后一问题可导致角色授权检查假通过及缺失记录用例失败，但还不能据此断言此前整套检查未结束的原因。
- 三步安排：用参数捕获和虚构数据证明检查问题；只修正直接相关测试并完成 Windows PowerShell 5.1 验证；核对差异、指纹和独立只读审查，记录未完成的真实运行门槛。实现者不得修改 Runner、冻结控制、场景或评分条件。
- 已执行基础检查：BuilderEfficiency 6/6 PASS；Harness 54/54 PASS；Bootstrap 17/17 PASS，三个子进程退出码均为 0。输出保存在本地忽略目录 `.pfc-eval-results/local-readiness-t12-20261001-7704dd39a38b4e60abff5fe9f7a0d9c6/`；输出 SHA-256 依次为 `d6294d7e969798d040507f0c42c02b5ae95b418ebc2355b5fe406febbbfde24e`、`d7dca78e043a695307b198852a9723c555b066b15b284996d1c4ff432aa653c4`、`dbc2b6c65bb4c24696934a20fdf72e013209c9d2e27bb643f14443d76a554794`。
- 冻结控制只读复核：46/46 执行文件和 7/7 场景清单绑定均匹配。当前冻结控制 `748622eed7e089f5d2a5254cc0379ffc811163d1386a6e66374ab330eab3cc59`；Runner `e1b77706e8bbfd7a098cc18a73badc6750ebe81e85ac9a0dbbd648f04abb4eda`；入口 `8304d56fc5fea09ace2ea18ba73e3745d663594044e065690e027d03f9b87f47`。
- 启动方式只读审查确认完整程序路径传入 Goalkeeper、Builder、Verifier 和对话接续；当前 CM 路线不覆盖 HOME，进程继承未覆盖的环境。传输失败会停止后续分派。未发现可重复证明的本地网络根因，因此不改等待参数或增加重试；这些静态结论不代替实际运行验证。
- 正式 RED 仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。Task 13 GREEN 和 Task 14 Windows smoke 仍为 NOT_RUN；本地检查修复不计入正式样本，也不改变发布状态。本轮本地修复验收已完成；Task 12 整体仍为 PARTIAL。
- 目标检查已实际完成：RunnerTerminal 9/9 PASS，ContinuousModeModelContract 104/104 PASS，退出码均为 0。根控制器读取本轮合成输出核验了 104 项 PASS、0 项 FAIL，以及 `real_process_calls=0; real_resolutions=0; fake_calls=228; formal_samples=0`。这不是当前项目所有套件的完整复跑，也不是实际模型效果证据。
- 修复内容仅两份测试：默认绑定本次替身程序；将两处假进程回调改为具名参数；用内嵌虚构事件替换旧原始记录读取；纠正相对结果路径；为虚构等待工具指定完整系统路径；清理前核实本次专用临时目录边界。等待工具的旧路径查找可重复失败，使虚构程序立刻退出；修复保留等待值和全部断言。没有修改生产 Runner、入口、冻结条件、场景或评分。
- 两份测试 SHA-256：RunnerTerminal `2c5565d580261e9d85517b1870bf3161d295e2d03424e199e43c4b0bf47567af`；ContinuousModeModelContract `d4e3550e67e772daa1bcf712ed90dea5a437dc53bbb5ac05017257b189995846`。两测试不在冻结 artifacts 清单内，故不需更新冻结哈希。
- 本轮合成回执 `.pfc-eval-results/test-repair-FAKE-20261001/repair-receipt.json`，SHA-256 `42d769d820610fc430518eb70fb35d45a9427bb1d3b95845883e78ac1f5f1d97`；只读参数捕获复现也保存在同一目录。未预存修复前完整文件快照；独立审查以本轮具体修改段、已读原片段、当前源代码及合成回执核对，不将全部历史未提交差异认作本轮差异。
- 五份当前状态文档已修正：中英文 README、V2 release gate、verification report、known risks。它们准确区分当前正式 2/0/2、Runner 记录来源与历史 Task 11 证据；当前仍 NOT_READY/BLOCKED，不把旧候选检查转记为新候选完整检查。JSON及 24 条本地链接静态检查通过。最终独立审查已完成。
- 下一次诊断授权草稿仅保存在本地忽略目录 `.pfc-eval-results/local-readiness-t12-20261001-7704dd39a38b4e60abff5fe9f7a0d9c6/next-canary-authorization.txt`，SHA-256 `cb7bf76afc6cf44d4d1faae5b6435576b2cf22a593956b3cdd1022da4cb78088`，状态 DRAFT_NOT_APPROVED。它仅建议一个 CM-01 小样本、最多 13 个角色任务/13 次接续/27 个 Codex 进程，不包含正式 RED/GREEN、Windows smoke、提交或远程操作；未据此运行。
- 最终独立只读审查（`t12_local_readiness_review`）：SPEC_COMPLIANCE PASS、QUALITY PASS、PONYTAIL PASS，Critical 0 / Important 0 / Minor 0。审查者独立核对本轮五组保存输出、退出码回执、代码与证据指纹，确认 Contract 104 条结果无重复、假进程 228 次、真实进程/程序解析/正式样本均为 0；没有复跑测试或启动模型。审查范围仅本轮两份测试修复、五份状态文档与新合成证据、未批准的下一次诊断草稿，不代表整体发布验收或全部历史未提交改动已通过。
- 最终文档 SHA-256：verification report `5448ef7467490ca9af536b2b5fd634c677ca787175c707f0a79cbabdb9a7ec41`；release gate `2e2de5fe45a15308c46adf428b8c006581f5aaec4b8f57173d07be124b1a6a9c`。审查状态文字指向本记录，不复制过期的待审查状态。
- 最终本地检查：两份变更测试语法错误 0；源文件哈希与验证回执一致；`git diff --check` 和 `git diff --cached --check` PASS。分支 `codex/pfc-v1-implementation`，HEAD `7ad957e4de5a9822e0647bf56b07650788db4d83` 未变；用户主工作区既有未跟踪文件未修改。没有项目提交、远程操作或新增模型评测调用；`TOKEN_USAGE: NOT_AVAILABLE`。
- 下一授权门槛：本轮本地问题已修复，真实网络请求的具体超时原因仍未确认。若继续模型验证，先需批准上述新的一次诊断草稿；成功后正式 RED、GREEN 和 Windows smoke 仍各需明确授权，不能复用已停止的授权或将旧无效样本转记为有效。当前 CORE_RELEASE_GATE BLOCKED，Specialist UNKNOWN；没有把“禁止新建文件”重新加入用户已放弃的要求，也没有据此宣称其他读取隔离已通过。
- 本轮本地收尾回执 `.pfc-eval-results/local-readiness-t12-20261001-7704dd39a38b4e60abff5fe9f7a0d9c6/closeout-receipt.json`，SHA-256 `2b2129b4a3689bc39935ea5837983bc2c7db3f738b922b9cbc26cb02fe009888`。最终差异格式与暂存区格式检查均通过；没有暂存、提交或上传本轮文件。

## Task 12 已批准的一次诊断启动准备（2026-10-01）

- 用户已明确批准 `PFC-V2-T12-LOCAL-READINESS-CANARY-20261001-R1`；仅 CM-01、RED 诊断、一个顶层尝试，角色任务最多 13、接续最多 13、评估进程最多 27，不重试或替补。不包含正式 RED/GREEN、Windows smoke、Git 提交或远程操作。
- Windows PowerShell 5.1 的 MachinePolicy 和 UserPolicy 均为 Undefined；仅本次进程使用临时 ExecutionPolicy Bypass。授权草稿及三份执行文件指纹均匹配；程序只读版本查询为 codex-cli 0.159.2。
- 受限环境中的版本查询提示无法找到用户目录；未据此启动模型。在正常本机环境只读执行一次 login status，返回 Logged in using ChatGPT，没有修改配置或凭据。两次查询不产生模型评估样本。
- 单次启动文件已准备在本地忽略目录 `.pfc-eval-results/local-readiness-canary-20261001-R1/`；运行前仍校验组织规则和三个文件指纹，独占启动预约与 Runner 授权预约防止重放。尚未据此启动模型。
- 正式累计仍为 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本。
## Task 12 本次已批准诊断的停止结果（2026-10-01）

- 授权 `PFC-V2-T12-LOCAL-READINESS-CANARY-20261001-R1` 已使用：1 次顶层诊断、0 个有效诊断样本、1 个无效诊断样本；不得重放或替补。模型请求参数 gpt-5.6-terra / medium / workspace-write，程序版本 codex-cli 0.159.2；由于没有完成回应，不宣称服务端模型身份已验证。评估进程 1 次、Builder/Verifier 角色任务 0 次、Goalkeeper 接续 0 次；另有版本和登录状态的只读 CLI 查询 2 次，已知 CLI 启动合计 3 次。
- 运行期间先观察到 2 条原生 error 事件，按异常停止条件请求终止。仅终止通过 PID、启动时间与授权命令标识核实属于本次诊断的进程树；终止成功，未重启模型。最终保存记录包含线程开始 1、回合开始 1、error 4、item.completed 1；没有 turn.completed、没有命令执行事件。4 条错误只在内存中分类为 NETWORK_TIMEOUT，未输出或保存原文；具体网络/代理/服务端原因尚未确认。
- 一个新原始记录的 7 行均可解析；SHA-256 `0ca40835b09c505492c82ec0e73cd2940351851b71a6f86f4798bc70c868fe15`。Runner 生命周期文件存在但记录为 0 行，尚未进入角色分工；没有最终 Schema 结果或可用 Token usage，记 NOT_AVAILABLE，正确性 NOT_RUN。这些结果不能算作正式或有效样本。
- 停止后临时启动器读取控制台指纹时遇到文件锁，未生成自动汇总回执；这不证明冻结 Runner 或 JSONL 解析代码有缺陷。本次未修改启动器、生产代码或冻结条件。控制台最终长度 0；在所有已验证进程停止后，用新独立回执只记录可以确认的事实。旧记录和本次原始记录均未修改；临时夹具没有擅自清理。
- 本次授权、启动器及原始记录仅保存在已忽略的本地 `.pfc-eval-results/`。规范化停止回执为 `.pfc-eval-results/local-readiness-canary-20261001-R1/normalized-stop-receipt.json`，SHA-256 a4ac0beb91b1f3d23e320625237c6cf92d2792f9ee7a84eb8e089dce1c10f701。
- 正式 RED 累计保持 2 次尝试、0 个有效、2 个无效，仍需 35 个有效样本；GREEN、Windows smoke 未运行。核心发布仍 BLOCKED，Task12 仍 PARTIAL。没有提交、上传、修改个人配置或登录凭据。
- 下一步建议为零模型只读网络检查，核对同一正常启动环境是否具备浏览器所使用的连接条件；尚未执行。新草稿 `.pfc-eval-results/local-readiness-canary-20261001-R1/next-network-readonly-authorization.txt`，SHA-256 b9fad442c0a1ff59f372e3cf174edc50f4f0524b971ebd72f8e8c1a9a6613e91，状态 DRAFT_NOT_APPROVED。它不恢复本次诊断、不授权下一次模型试跑或任何设置变更。
## Task 12 当前用户连接环境纠正与临时启动准备（2026-10-04）

- 零模型诊断确认：早先在隔离账号读取的“当前用户代理未启用”不能代表桌面用户；桌面实际用户已有本机代理。旧诊断程序路径现已失效，当前 codex-cli 0.160.0 可定位且 ChatGPT 登录状态正常。旧路径消失不能解释旧运行时的全部超时原因。
- 关闭 curl 默认配置后的受控对照：同一网站直接连接 10.05 秒超时，现有系统代理经子进程环境传入后 0.96 秒收到 HTTP403。只证明后一连接收到回应，不证明 Codex 模型服务已经恢复。用户配置未发现已确认的服务地址错误；不能断言它有误。当前 CLI 系统代理回退已启用，缺少环境变量也不能单独证明 CLI 完全不使用系统代理。
- 新临时辅助文件仅位于本地忽略的 .pfc-eval-results/connection-repair-20261004-R1/；准备启动时定位当前程序并核对指纹，只改变新子进程代理环境，拒绝冲突、未审查绕过清单及带凭据/非本机代理。Windows PowerShell5.1 本地模拟 7/7 PASS。此前未关闭 curl 默认配置的记录保持原样，新的隔离回执取代其作为受控结论证据。
- 独立只读复核发现并已关闭 1 项 Important（curl 默认配置自动读取）；最终临时辅助文件审查 PASS，Critical0/Important0。本轮没有启动任何模型、没有修改冻结 Runner/入口/控制，个人配置指纹不变。模型真实连接仍 NOT_TESTED。
- 已发现另一静态诊断缺口：Runner 错误输出退出时才保存，外部终止可能丢失；本轮没有修改冻结 Runner。下一次最小连接验证必须持续保存输出，正式评估前仍需处理记录完整性。
- 新最小连接验证草稿 PFC-V2-T12-PROXY-CONNECTION-CANARY-20261004-R1 尚未批准；它只建议一次简短响应检查，0 角色任务、0 接续，不复用任何已消耗授权，不启动整套 CM 评估。先确认模型通路，再回到 Task12；正式 RED/GREEN 及 Windows smoke 不在此次草稿范围。
- 正式累计保持 2 次尝试、0 个有效、2 个无效，仍需35个有效样本；Task12 PARTIAL、整体发布仍未通过。代码/证据指纹、配置纠正和下一授权均已追加本地 Task12 JSON 记录。无提交、远程 Git 或设置变更。
## Task 12 单次最小连接验证：启动前停止（2026-10-06）

- 用户已批准 PFC-V2-T12-PROXY-CONNECTION-CANARY-20261004-R1。初次正常账号只读预检：授权草稿、辅助文件、Codex 程序指纹符合；codex-cli 0.160.0、ChatGPT 登录正常，组织脚本策略未设置；没有旧运行预约。只读 CLI 查询 2 次，不是模型尝试。
- 为该次最小诊断准备新的临时采集/单次启动文件，全部位于本地已忽略目录。最终 Windows PowerShell5.1 虚构进程检查 11/11 PASS。独立复核的事件顺序和总等待 Important 已修正并复核 PASS，Critical0/Important0；采集按严格 UTF-8 文本保存，不宣称任意原始字节完全一致。没有修改冻结 Runner 或场景。
- 正式启动命令进入 Windows PowerShell5.1 后，在模型启动、预约文件创建及原始记录创建之前，所选 Codex 文件指纹检查不一致，脚本抛出停止。没有试用其他程序、重试或启动模型；不能把它归类为网络失败。初次预检与最终启动为何选择/得到不同程序，当前尚未确认，不能断言自动更新或路径设置导致。
- 可确认的结果：模型尝试0、模型进程0、角色任务0、接续0、重试0；预约、raw.jsonl 和 stderr.txt 均不存在。实际模型连接 NOT_TESTED，TOKEN_USAGE NOT_AVAILABLE。原授权触发停止条件，不自动重新启动。
- 本地预启动停止回执已保存于 .pfc-eval-results/proxy-connection-canary-20261004-R1/prelaunch-stop-receipt.json；代码和模拟回执哈希已补记 Task12 JSON。旧证据保持不变，冻结 Runner/入口/控制指纹与原批准版本一致。没有个人设置、凭据、Git 设置修改，没有提交或远程操作。
- 下一步建议只读比较两种 PowerShell 环境实际选中的程序及文件指纹，先确认不同的原因；不再次测试网络、不更换模型、不启动新的模型试跑。正式 RED 仍为2次尝试、0个有效、2个无效，仍需35个有效样本。
## Task 12 0.160.1 单次连接验证结果（2026-10-06）

- 已批准并新建本地独立启动副本；不覆盖 10-04 的旧记录，也保留启动前停止回执。程序版本/指纹符合新授权；Windows PowerShell5.1 脚本语法、11项虚构事件采集检查均通过，独立只读复核无 Critical/Important。
- 本次实际启动1个 gpt-5.6-terra / medium / read-only Codex进程，经本机现有系统代理传入子进程。进程在0.22秒出现 stderr 输出后被采集器停止；正常退出失败，没有原生运行事件或响应，未重试。
- 依授权只作安全错误类别判断，结果 UNCLASSIFIED_SAFE_TEXT；未复制/输出错误原文。原始 stderr 指纹 a7bf55410837cf2159544927ca03c9a99e8aa51a604c4b80fe6bc291efcdb761，stdout 指纹 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855，Token usage NOT_AVAILABLE。记录只保留在本地已忽略的 .pfc-eval-results/。
- 本次诊断1 attempted / 0 valid / 1 invalid；正式评估仍为2 attempted / 0 valid / 2 invalid，仍需35个有效样本。没有修改旧证据、个人设置、登录凭据或冻结评估代码；未提交/执行远程操作。
- 本次一次性授权已用完。下一步应先零模型查明这类启动错误的原因；不得复用本次授权再次启动。
## Consolidated repair and source publication checkpoint — 2026-10-06


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


Remote scope: the current human request authorizes normal GitHub project/README updates. Use one new ordinary commit on main based on the observed remote main, with GitHub noreply author/committer identity scoped to that process. Earlier development commits remain local; do not publish a development-history branch or change Git/account settings. Frozen formal evaluation still requires the retained local version history; a public clone alone is insufficient. No merge, rebase, force, tag, release or deployment. Old raw outputs and the protected task-3-report.md stay local and excluded. Earlier missing-draft notes resulted from checking the run folder rather than the preparation folder; no original authorization record was deleted.
