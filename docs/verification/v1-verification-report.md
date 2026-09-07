# Project Flight Control V1 Verification Report

Status: `PARTIAL / BLOCKED / NOT_READY`

This report records the local checkpoint after the single authorized manual Windows Sandbox Setup and the subsequent zero-model permission probe. It does not claim a controlled RED/GREEN result, token reduction, release readiness, or runtime Specialist availability.

## Implementation and controlled runtime

- Branch: `codex/pfc-v1-implementation`
- Candidate HEAD: `3e1dbe0c8b973912d108646830b49df8d382e2ed`
- Initial final documentation checkpoint: `bf48a83` (`docs: record native Windows sandbox blocker`); this report also includes the follow-up verification clarification commit.
- Local CLI used for the final Permission Probe: `codex-cli 0.153.1`; the upstream comparison authorization references `0.152.1`.
- Controlled Permission Profile: `pfc-controlled`
- Official Setup: `PASS`, exit code `0`, one administrator attempt, one UAC approval, one elevated Setup invocation
- Windows Sandbox backend after Setup: `elevated`
- Legacy sandbox flags/configuration: absent
- Controlled profile configuration hash after Setup: `760a212828a589d45de27f490385fdf426fbdbe752f35e8cce8bba8cbdbba4b2`
- Residual Setup/helper processes after checks: `0`

The audited zero-model Permission Probe was invoked once through the file handshake. `probe-started.json` and `probe-result.json` were valid UTF-8 No-BOM files with matching nonce, request ID, protocol version, script hash and schema. The probe completed with exit code `0`, but Fixture, Evidence, External and several path-escape operations were reported `ALLOWED`; private-source checks were `ERROR` or `ALLOWED`. The sentinel remained unchanged and no unknown Fixture files appeared. This is a valid result that fails the controlled permission gate (`PERMISSION_PROFILE_ENFORCEMENT_FAILED`); runtime efficacy is not established. Raw JSONL and raw process output were not saved or copied.

## Deterministic verification

All commands were run locally with Windows PowerShell 5.1, without a model prompt or remote action. Each suite returned exit code `0`:

| Suite | Passing checks |
|---|---:|
| Bootstrap | 7 |
| StaticPackage | 33 |
| Harness | 54 |
| BuilderEfficiency | 6 |
| Revision4Isolation | 31 |
| RunnerRevision3 | 1 |
| PermissionProbeExecutionPolicy | 10 |
| PermissionProbeFileHandshake | 20 |
| BuilderProfile | 6 |
| VerifierProfile | 13 |
| MessageContracts | 2 |
| GovernanceReferences | 12 |
| EvidenceRecovery | 63 |
| SkillEntry | 11 |
| SpecialistProtocol | 38 |
| Installer | 10 |
| Doctor | 41 |
| SpecialistSmokeUnit | 20 |

Repository checks also passed: `git diff --check`, `git diff --cached --check`, `git write-tree`, approved design SHA-256 verification, secret/private-path/raw-evidence scans, and the current worktree/index reconciliation. The implementation worktree has no staged entries; the known untracked SDD `task-3-report.md` remains excluded from Git.

PowerShell AST parsing returned zero errors. No tracked `.pfc-eval-results` content, raw JSONL, Setup log, `auth.json`, `.sandbox-secrets`, SDD temporary report, fixed Specialist TOML, App Server Specialist adapter, or Runtime Token Telemetry was found.

## Evidence and release semantics

- Model calls during Setup and the permission probe: `0`
- Formal controlled RED/GREEN evaluation: not run under the failed permission gate branch
- Model-backed efficiency evidence: `NOT_ESTABLISHED`
- Token-reduction claim: not allowed
- Runtime Specialist capability: `UNKNOWN`
- License gate at the runtime closeout: `NOT_RUN`; subsequently resolved by the delegated MIT choice described below.
- Remote actions during the runtime closeout: not authorized and not performed; subsequent source publication has separate user authorization.

The file-handshake implementation and deterministic package checks are preserved as a local checkpoint. The controlled runtime gate remains closed because this authorized probe produced a valid but permissive result; the authorization forbids further probe attempts and any Controlled RED/GREEN run.

## Upstream blocker

- Blocker ID: `PFC-UPSTREAM-001`
- Title: Native Windows Codex deny-read permission enforcement not verified
- Affected environment: native Windows Codex with the elevated sandbox backend and named profile `pfc-controlled`
- Local evidence: the valid file-handshake Probe selected the profile and completed, but Evidence, External, and private profile sources remained readable in the observed environment.
- Related open reports: [openai/codex#42184](https://github.com/openai/codex/issues/42184), “Windows elevated sandbox: :root = deny permission profile still allows reads outside explicitly reopened roots”; [openai/codex#31265](https://github.com/openai/codex/issues/31265), “deny-read permission profile silently ineffective on native Windows (ACL state empty) — 0.142.5”. Both are recorded as open and similar reports only; neither is treated as an official confirmation or fix.
- Impact: the required hard isolation invariant is unavailable, so Controlled RED/GREEN and Core Efficiency remain blocked.
- Workaround: none approved for V1.
- Resume trigger: a future Codex version or upstream change that materially changes native Windows deny-read behavior.

## Public source preparation (2026-09-07)

The user requested public GitHub publication and explicitly delegated handling the license choice. MIT (SPDX `MIT`) was selected under that delegation; the root `LICENSE` contains the standard text with copyright `2026 yangjing6213-dev`. The license gate is `PASS`. This newer user instruction supersedes the earlier plan requirement that the user personally supply the identifier; the approved plan and design remain unchanged.

Publication targets `yangjing6213-dev/codex-project-flight-control-Agents-Token-` as development source version `0.1.0-dev.0`. It does not establish a stable release, runtime isolation, Specialist availability or token reduction. The final remote SHA and delivery receipt are recorded in the local execution ledger and ignored pre-publication report after the push is verified.

The source-history audit covered 43 commits and 651 reachable objects at `0fa91df`. It found no private-key, `ghp_` or `github_pat_` pattern matches. The 37 historical key-shaped matches were reviewed synthetic redaction-test data in `evals/run-evals.ps1`; user-path matches were test fixtures and plan examples. No reachable blob exceeded 10 MB. Pattern scanning is not an exhaustive guarantee, and no external secret-scanning service or entropy scanner was used. Ignored raw evaluation evidence, temporary files and the untracked `task-3-report.md` are excluded from publication.
