# Project Flight Control V1 Implementation Plan

- **Plan version:** `PFC-PLAN-v1.0-draft`
- **Date:** `2026-09-03`
- **Status:** `READY_FOR_EXECUTION_REVIEW`
- **Recommended Windows checkout:** `F:\Projects\codex-project-flight-control`

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` when independent subagents are available; otherwise use `superpowers:executing-plans`. Execute one task at a time, run the stated RED/GREEN checks, and review the diff before each commit.

**Goal:** Build and verify the Windows-first `project-flight-control` Codex Skill, its Builder and Verifier custom agents, safe installation tooling, compact evidence/recovery protocol, conditional Runtime Specialist protocol, and RED–GREEN evaluation suite defined by the approved design.

**Architecture:** The installed runtime is instruction-first: one compact Skill entry point, two narrow custom-agent TOML files, progressively loaded references, and exact message templates. Deterministic PowerShell code is limited to installation, update, uninstall, doctor, fixture creation, static validation, and evaluation collection. The three-role control loop remains Goalkeeper → Builder → Verifier; Runtime Specialist is an optional, capability-gated temporary thread and is never a fourth installed role.

**Tech Stack:** Markdown, YAML, TOML, JSON/JSON Schema, Windows PowerShell 5.1-compatible PowerShell, Git for Windows, Codex CLI/App behavior tests through `codex exec --json` and `--output-schema` when supported.

**Spec:** `docs/project-flight-control-design.md`, copied byte-for-byte from `PFC-DESIGN-v1.0-approved` before implementation. Approved source SHA-256: `e5c90a41c28ce8e7f9192102f14613adef5af93ee7ee5007b4f69df6ed57dedd`.

## Current official interface baseline

Re-check these official OpenAI documents immediately before implementation and record the observed Codex version in the first verification report:

```text
https://learn.chatgpt.com/docs/build-skills
https://learn.chatgpt.com/docs/agent-configuration/subagents
https://learn.chatgpt.com/docs/environments/git-worktrees
https://learn.chatgpt.com/docs/config-file/config-reference
https://learn.chatgpt.com/docs/non-interactive-mode
```

As of 2026-09-03, the relevant official behavior is:

- user Skills are discoverable under `$HOME/.agents/skills`, and `agents/openai.yaml` can set `policy.allow_implicit_invocation: false`;
- standalone custom agents live under `~/.codex/agents/` and require `name`, `description`, and `developer_instructions`;
- custom agents may set or inherit normal session settings such as model, reasoning effort, and sandbox mode;
- Codex-managed worktrees normally begin in detached HEAD state;
- `codex exec --json` emits JSONL events including usage when available, and `--output-schema` constrains the final response;
- `codex exec` defaults to a read-only sandbox; workspace writes must be explicitly requested.

If implementation-time documentation or the installed client materially contradicts the approved semantics, stop with `BLOCKED_BY_PLATFORM_CHANGE`; do not silently redesign the product.

## Global Constraints

- V1 supports Windows 10/11 and **must run under Windows PowerShell 5.1**. PowerShell 7 compatibility is tested when available but is not allowed to replace the 5.1 gate.
- The fixed formal roles are Goalkeeper, Builder, and Verifier. Install exactly two custom-agent TOML files: Builder and Verifier.
- The Skill is explicit-only. Do not add implicit invocation, FAST/STANDARD/DEEP routing, Company OS integration, Repo Map, semantic index, long-term memory, runtime token telemetry, or fixed Specialist profiles.
- Goalkeeper is the only control-file writer. Builder, Verifier, and Specialist never modify canonical control files.
- Builder owns implementation and targeted self-verification and must load the approved **Builder Efficiency Protocol**. Verifier independently evaluates a frozen Candidate SHA. Goalkeeper owns acceptance decisions but cannot rewrite valid evidence.
- Correctness, data safety, permission safety, version integrity, and required verification outrank efficiency.
- No `git push`, merge, rebase, force operation, release, deployment, production change, external-account mutation, or paid-service activation is authorized by this plan.
- Never use `danger-full-access` in evaluation automation. Use the least sandbox that can complete the isolated fixture task.
- Never persist API keys, Codex auth files, cookies, model reasoning text, or unredacted sensitive logs in the repository.
- Model-backed RED/GREEN runs consume Codex allowance. Before the first such run in an implementation session, show the fixed scenario count and obtain current-task authorization; deterministic checks do not need that authorization.
- Raw Codex JSONL belongs in a local ignored results directory. Commit only normalized, redacted evidence summaries.
- Every verification status is one of `PASS`, `FAIL`, `PARTIAL`, or `NOT_RUN`. Token data unavailable from the client is `NOT_AVAILABLE`, never estimated as a saving percentage.
- Start development at `0.1.0-dev.0`. Promotion to `1.0.0` is a separate final gate after all core release conditions pass and the user approves release preparation.

---

# File Responsibility Map

## Runtime package

| File | Single responsibility |
|---|---|
| `skill/project-flight-control/SKILL.md` | Explicit entry point, Goalkeeper preflight, top-level modes, state flow, reference routing, pause conditions, fixed receipt. |
| `skill/project-flight-control/agents/openai.yaml` | Display metadata and explicit-only invocation policy. |
| `skill/project-flight-control/references/orchestration-protocol.md` | Phase ordering, role handoff, lease ownership, acceptance loop. |
| `skill/project-flight-control/references/roles-and-authority.md` | Formal authority, prohibitions, minimal-context boundaries. |
| `skill/project-flight-control/references/modes-and-state-machine.md` | START/RESUME/AUDIT/STATUS_ONLY and Goal/Milestone/Specialist state transitions. |
| `skill/project-flight-control/references/git-and-worktrees.md` | Baseline selection, Candidate/Checkpoint semantics, worktree topology, safe cleanup. |
| `skill/project-flight-control/references/evidence-and-recovery.md` | Compact evidence, attachments, convergence snapshot, lease epoch, interruption recovery. |
| `skill/project-flight-control/references/message-contracts.md` | One authoritative definition of every formal message field. |
| `skill/project-flight-control/references/builder-debugging.md` | Failure-only root-cause workflow and two-attempt stop rule. |
| `skill/project-flight-control/references/specialist-protocol.md` | Optional temporary Specialist request, order, evidence round, report, capability gate, cleanup. |
| `skill/project-flight-control/references/windows-runtime.md` | Windows path, shell, sandbox, permission, and command compatibility notes. |
| `skill/project-flight-control/assets/templates/*.md` | Exact output shapes only; no duplicated workflow prose. |
| `codex-agents/project-flight-builder.toml` | Builder role plus always-on execution-efficiency discipline. |
| `codex-agents/project-flight-verifier.toml` | Verifier role, evidence integrity, minimum independent rerun, no Candidate mutation. |

## Deterministic tooling

| File | Single responsibility |
|---|---|
| `scripts/lib/ProjectFlightControl.Core.psm1` | Paths, hashes, JSON IO, environment fingerprints, safe process helpers. |
| `scripts/lib/ProjectFlightControl.Install.psm1` | Target classification, staging, manifest, backup, install, update, rollback, uninstall. |
| `scripts/lib/ProjectFlightControl.Doctor.psm1` | Passive checks and Specialist capability-state calculation. |
| `scripts/install.ps1` | Public install entry point. |
| `scripts/update.ps1` | Public update entry point. |
| `scripts/uninstall.ps1` | Public uninstall entry point. |
| `scripts/doctor.ps1` | Passive doctor by default; explicit `-SpecialistSmoke` entry. |

## Evaluation tooling

| File | Single responsibility |
|---|---|
| `evals/lib/TestHarness.psm1` | Assertions, scenario result normalization, PASS/FAIL aggregation. |
| `evals/lib/StaticChecks.psm1` | Package shape, metadata, references, dangerous-command, forbidden-scope checks. |
| `evals/lib/FixtureRepository.psm1` | Deterministic one-use Git fixture repositories and expected graphs. |
| `evals/lib/CodexRunner.psm1` | Safe `codex exec` invocation, JSONL capture, final-schema output, usage extraction. |
| `evals/lib/PromptBudget.psm1` | Conservative prompt-size report; never claims tokenizer-exact counts. |
| `evals/run-evals.ps1` | Suite dispatcher; no scenario-specific logic. |
| `evals/schemas/*.schema.json` | Stable structured final outputs for Builder, Verifier, Specialist, and eval summaries. |
| `evals/scenarios/**/scenario.json` | Predeclared controls, metric, expected improvement, forbidden regression, repetition count. |
| `evals/scenarios/**/prompt.md` | Exact scenario prompt. |
| `evals/expected/**` | Expected deterministic results and committed normalized RED baselines. |

## Repository documentation

| File | Single responsibility |
|---|---|
| `AGENTS.md` | Short implementation map pointing to the approved spec and this plan; no duplicated product manual. |
| `README.md` | Installation, invocation, capability-state meaning, safety boundaries, verification status. |
| `docs/project-flight-control-design.md` | Approved design specification. |
| `docs/superpowers/plans/2026-09-03-project-flight-control-v1-implementation-plan.md` | This plan. |
| `VERSION` | Current development/release version. |
| `CHANGELOG.md` | User-visible changes and verification state. |

---

### Task 1: Bootstrap the repository, approved design, and native test harness

**Files:**
- Create: `.gitignore`
- Create: `AGENTS.md`
- Create: `README.md`
- Create later: `LICENSE` only after an explicit user-approved SPDX license choice
- Create: `VERSION`
- Create: `CHANGELOG.md`
- Create: `docs/project-flight-control-design.md`
- Create: `docs/superpowers/plans/2026-09-03-project-flight-control-v1-implementation-plan.md`
- Create: `evals/lib/TestHarness.psm1`
- Create: `evals/run-evals.ps1`

**Interfaces:**
- Produces `Assert-PfcTrue`, `Assert-PfcEqual`, `New-PfcResult`, and `Write-PfcSummary` for every later deterministic test.
- `evals/run-evals.ps1 -Suite Bootstrap -Json` returns process exit code `0` only when required root artifacts exist and the approved spec hash matches.

- [ ] **Step 1: Initialize the repository and main branch**

```powershell
git init
git branch -M main
git config core.autocrlf false
```

Expected: an empty Git repository on `main`; do not add a remote.

- [ ] **Step 2: Write the failing bootstrap test first**

Create `evals/lib/TestHarness.psm1` with assertion functions that throw a terminating error containing the scenario ID, expected value, and actual value. Create `evals/run-evals.ps1` with a `Bootstrap` suite that checks these exact files:

```text
AGENTS.md
README.md
VERSION
CHANGELOG.md
docs/project-flight-control-design.md
docs/superpowers/plans/2026-09-03-project-flight-control-v1-implementation-plan.md
```

It must also compute SHA-256 for `docs/project-flight-control-design.md` and require:

```text
e5c90a41c28ce8e7f9192102f14613adef5af93ee7ee5007b4f69df6ed57dedd
```

- [ ] **Step 3: Run the test and verify RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite Bootstrap -Json
```

Expected: `FAIL`; the missing root files are named. Record no model output.

- [ ] **Step 4: Create the minimal repository artifacts**

Requirements:

```text
VERSION = 0.1.0-dev.0
Do not create `LICENSE` during bootstrap; public release remains blocked until the user explicitly selects an SPDX license.
AGENTS.md <= 80 lines and only maps implementers to spec, plan, eval command, and safety constraints
README.md states IMPLEMENTATION: NOT_RUN and TOKEN_EFFECT: NOT_RUN
CHANGELOG.md contains an Unreleased section only
.gitignore excludes .pfc-eval-results/, evals/results/, temporary worktrees, staging, backups, coverage, build output, and secret files
```

Copy the approved specification and this plan without semantic edits.

- [ ] **Step 5: Run bootstrap GREEN under Windows PowerShell 5.1**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite Bootstrap -Json
```

Expected: `PASS` and spec hash match.

- [ ] **Step 6: Commit the approved baseline**

```powershell
git add .gitignore AGENTS.md README.md VERSION CHANGELOG.md docs evals
git commit -m "chore: bootstrap project flight control"
```

- [ ] **Step 7: Create the isolated implementation worktree**

From the main checkout:

```powershell
git worktree add ..\codex-project-flight-control-impl -b codex/pfc-v1-implementation
Set-Location ..\codex-project-flight-control-impl
```

Expected: all later tasks run in the implementation worktree, not the main checkout.

---

### Task 2: Build static package checks and record the package RED baseline

**Files:**
- Create: `evals/lib/StaticChecks.psm1`
- Create: `evals/lib/PromptBudget.psm1`
- Create: `evals/expected/static-package.json`
- Modify: `evals/run-evals.ps1`

**Interfaces:**
- `Invoke-PfcStaticChecks -RepositoryRoot <DirectoryInfo> -Phase RED|GREEN` returns a list of named check results.
- `Measure-PfcPromptBudget -Path <FileInfo> -Budget <int>` returns `{ chars, utf8_bytes, conservative_estimated_tokens, budget, status }`.
- Prompt estimates are labeled `CONSERVATIVE_ESTIMATE`, not actual model-token counts.

- [ ] **Step 1: Define all static checks before runtime files exist**

`evals/expected/static-package.json` must enumerate at least:

```text
required skill/reference/template paths
LICENSE is release-required only after an explicit user-approved SPDX choice; it is not a bootstrap requirement
SKILL.md frontmatter name and description
agents/openai.yaml explicit-only policy
two and only two formal agent TOMLs
required custom-agent fields
absence of fixed Specialist TOML
Builder efficiency terms
Verifier evidence-integrity terms
reference and template link integrity
PowerShell parseability
forbidden destructive Git commands
forbidden hard-coded drive letters
version consistency
install-state schema presence
absence of Company OS, Repo Map, long-term Memory, and runtime telemetry implementation
passive Doctor must not invoke Codex or create agents
prompt budget report generation
```

- [ ] **Step 2: Implement the checker and prompt estimator**

PowerShell parsing rules:

```text
Markdown/YAML/TOML checks are limited deterministic key/section checks; do not add a YAML or TOML dependency.
PowerShell syntax uses [System.Management.Automation.Language.Parser]::ParseFile().
Reference links resolve relative to the Skill directory.
Dangerous-command scan rejects reset --hard, clean -fd, force push, automatic push/merge/rebase/deploy patterns in production scripts.
```

- [ ] **Step 3: Run static package RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite StaticPackage -Phase RED -Json
```

Expected: `FAIL` because Skill, agents, references, templates, and scripts do not exist. Save the normalized result as the committed RED baseline; do not weaken checks to make it pass.

- [ ] **Step 4: Verify the harness itself passes**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite Harness -Json
```

Expected: `PASS` for assertion behavior, JSON output, PowerShell parser usage, and deterministic ordering.

- [ ] **Step 5: Commit the static RED framework**

```powershell
git add evals
git commit -m "test: add static package red baseline"
```

---

### Task 3: Create deterministic fixture repositories and record model-backed RED baselines

**Files:**
- Create: `evals/lib/FixtureRepository.psm1`
- Create: `evals/lib/CodexRunner.psm1`
- Create: `evals/schemas/eval-run.schema.json`
- Create: `evals/schemas/builder-report.schema.json`
- Create: `evals/scenarios/builder-efficiency/EFF-01-targeted-context/**`
- Create: `evals/scenarios/builder-efficiency/EFF-02-reuse-before-create/**`
- Create: `evals/scenarios/builder-efficiency/EFF-03-minimal-diff/**`
- Create: `evals/scenarios/builder-efficiency/EFF-04-delta-rework/**`
- Create: `evals/scenarios/builder-efficiency/EFF-05-incremental-verification/**`
- Create: `evals/scenarios/builder-efficiency/EFF-06-debugging-convergence/**`
- Create: `evals/scenarios/builder-efficiency/EFF-07-structured-recovery/**`
- Create: `evals/expected/builder-efficiency/red/**`
- Modify: `evals/run-evals.ps1`

**Interfaces:**
- `New-PfcFixtureRepository -ScenarioId -DestinationRoot` creates a fresh Git repo with deterministic commits and returns `{ root, base_sha, expected_files, expected_graph }`.
- `Invoke-PfcCodexRun -WorkingDirectory -PromptPath -OutputSchemaPath -SandboxMode -ResultDirectory -Phase` runs `codex exec`, captures JSONL, extracts non-sensitive metrics, and returns normalized evidence.
- `Read-PfcCodexJsonlMetrics` extracts only event types, tool/command counts, file-change paths, turn result, and usage fields; it never persists reasoning text.

- [ ] **Step 1: Define each scenario contract before running Codex**

Every `scenario.json` must include exact values for:

```json
{
  "scenario_id": "EFF-01",
  "primary_efficiency_metric": "files_read_before_first_relevant_edit",
  "expected_improvement": "GREEN starts from named target and adjacent test before repository-wide search",
  "allowed_trade_offs": ["one precise symbol search"],
  "forbidden_regressions": ["missing required behavior", "reduced verification", "unrelated edits"],
  "required_evidence": ["jsonl metrics", "git diff", "target test result"],
  "repetition_count": 5
}
```

Use scenario-specific metrics for EFF-02 through EFF-07; do not reuse a generic “looks efficient” judgment.

- [ ] **Step 2: Implement deterministic fixtures**

Fixture requirements:

```text
EFF-01: target implementation and adjacent test are sufficient; repository contains distracting unrelated modules.
EFF-02: an existing reusable helper is discoverable through a targeted search.
EFF-03: the task can be completed in one module without formatting or refactoring neighbors.
EFF-04: an R1 Candidate and one narrow Verifier finding exist; accepted portions must remain unchanged.
EFF-05: one target test is sufficient initially; a broader module test is required only after a seeded dependency signal.
EFF-06: a seeded failure supports two falsifiable hypotheses; the third speculative patch is forbidden.
EFF-07: persisted contract, SHA, BUILD_REPORT, REVIEW_REPORT, and STATUS allow resumption without old chat.
```

Each fixture creates its own branchless temporary repo and exposes the exact base SHA.

- [ ] **Step 3: Implement safe Codex runner behavior**

The runner must invoke a fresh context per repetition using:

```powershell
codex exec --json --sandbox workspace-write --output-schema <schema> -o <final-output> <prompt>
```

It must:

```text
fail closed when codex is absent or unauthenticated
never pass danger-full-access
never read or copy ~/.codex/auth.json
place raw JSONL under .pfc-eval-results/ outside committed evidence
redact absolute user paths and secret-like values from normalized summaries
record usage exactly when turn.completed.usage exists, otherwise TOKEN_USAGE = NOT_AVAILABLE
```

- [ ] **Step 4: Obtain current-task authorization for model-backed RED runs**

Before execution, report the fixed count:

```text
7 scenarios × 5 fresh repetitions = 35 Codex runs
```

Do not run until the user authorizes that implementation-session allowance use.

- [ ] **Step 5: Record RED baselines**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite BuilderEfficiency -Phase RED -Repeat 5 -Json
```

Expected: a baseline record, not necessarily a test failure. Preserve natural single-agent behavior and normalize the metrics before any Builder efficiency prompt exists.

- [ ] **Step 6: Review RED evidence manually**

For each scenario, inspect the actual diff and final correctness. Reject a baseline run if it is corrupted, unauthenticated, or not comparable; never discard a valid unfavorable run because it weakens the desired claim.

- [ ] **Step 7: Commit scenario definitions and normalized RED evidence**

```powershell
git add evals
git commit -m "test: record builder efficiency red baselines"
```

Raw JSONL remains ignored.

---

### Task 4: Define the authoritative message contracts and core templates

**Files:**
- Create: `skill/project-flight-control/references/message-contracts.md`
- Create: `skill/project-flight-control/assets/templates/project.md`
- Create: `skill/project-flight-control/assets/templates/roadmap.md`
- Create: `skill/project-flight-control/assets/templates/status.md`
- Create: `skill/project-flight-control/assets/templates/decisions.md`
- Create: `skill/project-flight-control/assets/templates/work-order.md`
- Create: `skill/project-flight-control/assets/templates/build-report.md`
- Create: `skill/project-flight-control/assets/templates/verify-order.md`
- Create: `skill/project-flight-control/assets/templates/review-report.md`
- Create: `skill/project-flight-control/assets/templates/rework-order.md`
- Create: `skill/project-flight-control/assets/templates/evidence-record.md`
- Create: `skill/project-flight-control/assets/templates/decision-packet.md`
- Create: `skill/project-flight-control/assets/templates/human-verification-request.md`
- Create: `skill/project-flight-control/assets/templates/human-verification-response.md`
- Create: `skill/project-flight-control/assets/templates/acceptance-report.md`
- Create: `skill/project-flight-control/assets/templates/final-review-report.md`
- Modify: `evals/expected/static-package.json`

**Interfaces:**
- `message-contracts.md` is the only field-definition authority.
- Templates are render shapes and must not redefine role or state behavior.
- Every formal message carries `Control Run ID`, `Lease Epoch`, Goal/Milestone versions, Revision, role direction, timestamp, and the relevant Base/Candidate SHA.

- [ ] **Step 1: Add failing field-contract assertions**

Extend static checks so each template fails unless it contains exactly the required identity and message-specific fields from approved spec sections 12 and 26. Add a duplicate-authority check that rejects prose such as “this template defines the state transition.”

- [ ] **Step 2: Run the contract checks RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite MessageContracts -Phase RED -Json
```

Expected: `FAIL` with missing contract/template names.

- [ ] **Step 3: Implement `message-contracts.md`**

Define these formal message types and no extra runtime message family:

```text
WORK_ORDER
BUILD_REPORT
VERIFY_ORDER
REVIEW_REPORT
REWORK_ORDER
CHANGE_REQUEST
STATE_CORRECTION_REQUEST
ROADMAP_CHANGE_REQUEST
HUMAN_VERIFICATION_REQUEST
HUMAN_VERIFICATION_RESPONSE
DECISION_PACKET
DECISION
ACCEPTANCE_REPORT
FINAL_REVIEW_REPORT
PROJECT_CONTROL_REPORT
SPECIALIST_REQUEST
SPECIALIST_ORDER
SPECIALIST_REPORT
```

Define `EFFICIENCY_EXCEPTION`, `DEBUGGING_SUMMARY`, `CONVERGENCE_SNAPSHOT`, `RESIDUAL_RISK`, and `EVIDENCE_RECORD` as nested structures, not additional role states.

- [ ] **Step 4: Implement the core templates**

Rules:

```text
Every field has a label and an allowed empty-state value: NOT_APPLICABLE, UNKNOWN, or NOT_RUN.
No template includes sample secrets, real usernames, drive letters, or full-log placeholders.
BUILD_REPORT contains actual commands, exit codes/results, limitations, scope deviations, evidence locations, optional efficiency exception, and optional debugging summary.
REVIEW_REPORT contains alignment, technical result, version integrity, findings, residual risks, and verdict.
STATUS contains only the latest convergence snapshot, not a duplicate history.
```

- [ ] **Step 5: Run contract GREEN**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite MessageContracts -Phase GREEN -Json
```

Expected: `PASS`.

- [ ] **Step 6: Commit**

```powershell
git add skill evals
git commit -m "feat: define project flight message contracts"
```

---

### Task 5: Implement role authority, state machine, orchestration, and Git/worktree references

**Files:**
- Create: `skill/project-flight-control/references/roles-and-authority.md`
- Create: `skill/project-flight-control/references/modes-and-state-machine.md`
- Create: `skill/project-flight-control/references/orchestration-protocol.md`
- Create: `skill/project-flight-control/references/git-and-worktrees.md`
- Modify: `evals/expected/static-package.json`

**Interfaces:**
- Goalkeeper → Builder and Goalkeeper → Verifier are the only formal command edges.
- Builder and Verifier return only to Goalkeeper; they do not command each other.
- Worktree state and lease state are consumed by evidence/recovery in Task 9.

- [ ] **Step 1: Add failing authority and transition tests**

Tests must reject:

```text
Goalkeeper editing business code
Builder changing contracts/control files
Verifier modifying Candidate or committing
Builder self-acceptance
Verifier final Goal acceptance
missing Verifier fallback to main thread
implicit mode downgrade for small tasks
unaccepted Candidate becoming the next milestone base
```

- [ ] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite GovernanceReferences -Phase RED -Json
```

Expected: `FAIL`.

- [ ] **Step 3: Write `roles-and-authority.md`**

Include exact formal authority, allowed actions, prohibited actions, and minimal-context input for Goalkeeper, Builder, Verifier, and non-formal Specialist. State “one source of truth, separate minimal contexts,” not “one shared complete context.”

- [ ] **Step 4: Write `modes-and-state-machine.md`**

Define:

```text
START / RESUME / AUDIT / STATUS_ONLY
Milestone states from planned through accepted/blocked/changed
Goal states including GOAL_REVIEW and GOAL_ACCEPTED
Specialist substate ACTIVE / EVIDENCE_NEEDED / RESOLVED / UNRESOLVED
valid and invalid transitions
```

Do not add task-complexity modes.

- [ ] **Step 5: Write `orchestration-protocol.md`**

Define preflight, contract lock, Builder lease, Candidate freeze, Verifier order, decision, targeted rework, milestone checkpoint, default pause, optional pre-approved continuous mode, and final Goal audit.

- [ ] **Step 6: Write `git-and-worktrees.md`**

Define original-worktree preservation, clean committed baseline choice, dirty-worktree decision packet, milestone worktree, fixed-SHA Verifier worktree, temporary Specialist worktree, Candidate commit, control-only acceptance commit, safe cleanup, and prohibited Git operations.

- [ ] **Step 7: Run GREEN and commit**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite GovernanceReferences -Phase GREEN -Json
git add skill evals
git commit -m "feat: add governance and worktree protocols"
```

---

### Task 6: Implement the compact Skill entry point and explicit invocation metadata

**Files:**
- Create: `skill/project-flight-control/SKILL.md`
- Create: `skill/project-flight-control/agents/openai.yaml`
- Modify: `evals/lib/PromptBudget.psm1`
- Modify: `evals/expected/static-package.json`

**Interfaces:**
- `SKILL.md` routes to references by phase and never duplicates their detailed rules.
- `openai.yaml` sets display metadata and `policy.allow_implicit_invocation: false`.

- [ ] **Step 1: Add failing Skill-entry tests**

Checks:

```text
frontmatter name = project-flight-control
concise explicit-only description
openai.yaml policy false
contains START / RESUME / AUDIT / STATUS_ONLY
contains SUBAGENT_PREFLIGHT and no-role-simulation gate
references every required authority file
contains fixed final receipt route
contains no full Builder efficiency checklist, debugging algorithm, or Specialist field catalog
conservative prompt estimate is within approved target or produces an explicit justified warning
```

- [ ] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite SkillEntry -Phase RED -Json
```

Expected: `FAIL`.

- [ ] **Step 3: Write the minimum `SKILL.md`**

Required sequence:

```text
explicit activation and non-goals
Goalkeeper identity
read-only preflight and mode selection
canonical source mapping
subagent preflight
contract lock
phase-specific reference loading
Builder dispatch
Candidate freeze
Verifier dispatch
decision/rework/checkpoint
Specialist request gate only
pause conditions
Project Control Report
```

Do not include implementation examples longer than one message skeleton.

- [ ] **Step 4: Write `openai.yaml`**

Use:

```yaml
interface:
  display_name: "Project Flight Control"
  short_description: "Control complex Codex development with isolated Builder and Verifier roles."
  default_prompt: "$project-flight-control"
policy:
  allow_implicit_invocation: false
```

Do not declare unimplemented MCP dependencies.

- [ ] **Step 5: Run GREEN and inspect the prompt report**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite SkillEntry -Phase GREEN -Json
```

Expected: `PASS`; budget report labels estimates honestly.

- [ ] **Step 6: Commit**

```powershell
git add skill evals
git commit -m "feat: add explicit project flight control skill"
```

---

### Task 7: Implement Builder custom agent and failure-only debugging protocol

**Files:**
- Create: `codex-agents/project-flight-builder.toml`
- Create: `skill/project-flight-control/references/builder-debugging.md`
- Modify: `evals/expected/static-package.json`
- Modify: `evals/schemas/builder-report.schema.json`

**Interfaces:**
- Agent name source of truth: `project_flight_builder`.
- Builder input: one valid `WORK_ORDER`, project rules, Base/Candidate SHA, worktree path.
- Builder output: one `BUILD_REPORT` conforming to the message contract.

- [ ] **Step 1: Add failing Builder-agent tests**

Require these exact behavioral concepts in `developer_instructions`:

```text
Start From Evidence
Targeted Context with three expansion levels
Reuse Before Create when duplication is plausible
Minimal Diff
Incremental Verification
Delta Rework
Accurate PASS / FAIL / PARTIAL / NOT_RUN
EFFICIENCY_EXCEPTION only for deviations
no control-file writes
no acceptance declaration
```

Reject a hard-coded model or global `high` reasoning requirement.

- [ ] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite BuilderProfile -Phase RED -Json
```

Expected: `FAIL`.

- [ ] **Step 3: Write Builder TOML**

Use required fields only plus `sandbox_mode = "workspace-write"`. Omit model and reasoning effort so spawn or parent settings can control them. Keep the role narrow: implement, test, commit Candidate, report.

- [ ] **Step 4: Write `builder-debugging.md`**

Define:

```text
read error fully
reproduce
inspect current Revision/diff
form one hypothesis
make the smallest test of that hypothesis
apply one root-cause fix
rerun affected verification
allow at most two code-changing attempts on the same failure path
return DEBUGGING_SUMMARY and stop when not converging
```

Explicitly prohibit stacked speculative patches, deleting tests, weakening assertions, and relabeling the same failure as a new issue.

- [ ] **Step 5: Run GREEN and commit**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite BuilderProfile -Phase GREEN -Json
git add codex-agents skill evals
git commit -m "feat: add efficient builder agent"
```

---

### Task 8: Implement Verifier custom agent and independent evidence review

**Files:**
- Create: `codex-agents/project-flight-verifier.toml`
- Create: `evals/schemas/verifier-report.schema.json`
- Modify: `evals/expected/static-package.json`

**Interfaces:**
- Agent name source of truth: `project_flight_verifier`.
- Verifier input: `VERIFY_ORDER`, frozen Candidate SHA, isolated worktree, compact Builder evidence.
- Verifier output: `REVIEW_REPORT` with Alignment Result, Technical Result, Version Integrity, Findings, Residual Risks, and Verdict.

- [ ] **Step 1: Add failing Verifier-profile tests**

Require:

```text
Alignment Audit before Technical Verification
Candidate SHA and evidence-integrity check
Builder evidence may be reused, Builder conclusions may not
minimum independent rerun
risk-triggered verification expansion
tracked-file immutability
no commit, no contract change, no direct Builder command
BLOCKER/MAJOR objective evidence
MINOR non-blocking behavior
```

- [ ] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite VerifierProfile -Phase RED -Json
```

Expected: `FAIL`.

- [ ] **Step 3: Write Verifier TOML**

Set `sandbox_mode = "workspace-write"` only because build/test tools may need disposable caches. Instructions must require before-and-after `git status --porcelain` and fail version integrity when tracked files change. Omit model and reasoning effort.

- [ ] **Step 4: Define minimum independent rerun logic in the instructions**

At minimum rerun:

```text
Candidate integrity check
core target behavior
any previously failing check claimed fixed
any high-risk boundary identified from the diff
```

Allow valid low-risk Builder lint/type/build evidence to be reused when SHA-bound and complete.

- [ ] **Step 5: Run GREEN and commit**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite VerifierProfile -Phase GREEN -Json
git add codex-agents evals
git commit -m "feat: add independent verifier agent"
```

---

### Task 9: Implement evidence, convergence, recovery, and Windows runtime references

**Files:**
- Create: `skill/project-flight-control/references/evidence-and-recovery.md`
- Create: `skill/project-flight-control/references/windows-runtime.md`
- Modify: `skill/project-flight-control/assets/templates/status.md`
- Modify: `skill/project-flight-control/assets/templates/build-report.md`
- Modify: `skill/project-flight-control/assets/templates/review-report.md`
- Modify: `evals/expected/static-package.json`

**Interfaces:**
- Recovery source order: Git → canonical project sources → persisted reports/evidence; thread IDs are trace metadata only.
- `CONVERGENCE_SNAPSHOT` is latest-state only in STATUS; historical detail remains in BUILD/REVIEW reports.

- [ ] **Step 1: Add failing recovery/evidence tests**

Test for:

```text
compact evidence required fields
successful command summary without full-log requirement
attachment only for failure/high-risk/non-repeatable proof
redaction requirements
Candidate change invalidates affected evidence
new Control Run ID and Lease Epoch on resume
old report rejection
accepted checkpoint inheritance
same Specialist Order recovery rule
```

- [ ] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite EvidenceRecovery -Phase RED -Json
```

- [ ] **Step 3: Write evidence and recovery rules**

Include exact handling for ACTIVE with no Candidate, Candidate without Review, REPAIR, Review PASS before persistence, Specialist ACTIVE/EVIDENCE_NEEDED, and ACCEPTED.

- [ ] **Step 4: Write Windows runtime rules**

Cover path normalization, Windows PowerShell 5.1 syntax, `powershell.exe`/`pwsh.exe`, Git for Windows, detached HEAD, sandbox approvals, protected `.git` paths, UTF-8 file writing without BOM dependence, and no hard-coded drive.

- [ ] **Step 5: Update templates and run GREEN**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite EvidenceRecovery -Phase GREEN -Json
```

- [ ] **Step 6: Commit**

```powershell
git add skill evals
git commit -m "feat: add evidence convergence and recovery"
```

---

### Task 10: Implement conditional Runtime Specialist protocol and static artifacts

**Files:**
- Create: `skill/project-flight-control/references/specialist-protocol.md`
- Create: `skill/project-flight-control/assets/templates/specialist-request.md`
- Create: `skill/project-flight-control/assets/templates/specialist-order.md`
- Create: `skill/project-flight-control/assets/templates/specialist-report.md`
- Create: `evals/schemas/specialist-report.schema.json`
- Modify: `skill/project-flight-control/references/message-contracts.md`
- Modify: `evals/expected/static-package.json`

**Interfaces:**
- No installed Specialist TOML.
- `SPECIALIST_REQUEST` is advisory request; `SPECIALIST_ORDER` is the only authorized input; `SPECIALIST_REPORT` status is `FINDING`, `EVIDENCE_NEEDED`, or `UNRESOLVED`.
- One active Specialist, one question, one evidence expansion, no nested agents.

- [ ] **Step 1: Add failing Specialist static tests**

Checks must reject:

```text
fixed specialist TOML
Specialist ACCEPT/REWORK/BLOCKED authority
more than one evidence round
Candidate modification or commit
full-context inheritance
automatic whole-repository scan
network or dependency installation by default
automatic report inheritance to a new Candidate
```

- [ ] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite SpecialistProtocol -Phase RED -Json
```

- [ ] **Step 3: Write the protocol and templates**

Implement:

```text
Goalkeeper-only approval and creation
narrow Context Packet
fixed Evidence SHA
independent disposable worktree
static-first analysis
minimum diagnostic command only when required
synchronous pause of affected work
FINDING / EVIDENCE_NEEDED / UNRESOLVED
Evidence vs Guidance applicability after Candidate changes
necessary-prerequisite blocking semantics
no formal state-machine verdict from Specialist
```

- [ ] **Step 4: Run GREEN and commit**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite SpecialistProtocol -Phase GREEN -Json
git add skill evals
git commit -m "feat: add conditional specialist protocol"
```

---

### Task 11: Implement transactional Windows install, update, rollback, and uninstall

**Files:**
- Create: `scripts/lib/ProjectFlightControl.Core.psm1`
- Create: `scripts/lib/ProjectFlightControl.Install.psm1`
- Create: `scripts/install.ps1`
- Create: `scripts/update.ps1`
- Create: `scripts/uninstall.ps1`
- Create: `evals/scenarios/core-governance/SC-15-installer-round-trip/scenario.ps1`
- Modify: `evals/run-evals.ps1`

**Interfaces:**

Public script parameters:

```powershell
install.ps1   [-SourceRoot <path>] [-UserHome <path>] [-StateRoot <path>] [-Json]
update.ps1    [-SourceRoot <path>] [-UserHome <path>] [-StateRoot <path>] [-Json]
uninstall.ps1 [-UserHome <path>] [-StateRoot <path>] [-Json]
```

The defaults resolve to the repository source, `$HOME`, and `%LOCALAPPDATA%\ProjectFlightControl`. Test-only temporary roots are supplied through the same parameters; no hidden global path rewriting.

The installer module must accept an injected passive-Doctor scriptblock for unit tests; Task 12 replaces the test double with the production Doctor module.

Core return objects:

```text
Get-PfcTargetState → ABSENT | MANAGED_UNCHANGED | MANAGED_MODIFIED | UNMANAGED_CONFLICT
Get-PfcInstallPlan → source/destination/hash/action list
Invoke-PfcInstallPlan → status, installed files, backup reference, rollback result
Invoke-PfcUninstall → removed, retained_modified, retained_unknown
```

- [ ] **Step 1: Write failing installer-round-trip tests**

Use temporary user/state roots. Cover:

```text
clean install
idempotent reinstall
managed file locally modified → stop without overwrite
unmanaged conflicting file → stop without overwrite
update creates timestamped backup
injected copy failure triggers rollback
rollback failure returns PARTIAL + MANUAL_RECOVERY_REQUIRED
uninstall removes only hash-matching managed files
modified managed file retained
unknown sibling file and directory retained
```

- [ ] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite Installer -Phase RED -Json
```

- [ ] **Step 3: Implement core safe-file functions**

Requirements:

```text
all destination paths normalized before comparison
all source and staged files hashed SHA-256
JSON writes go through temp-file + replace with backup
no recursive delete of unknown directories
no Force overwrite flag
all errors carry operation, path, and recovery state without secrets
```

- [ ] **Step 4: Implement transaction flow**

Exact order:

```text
VALIDATE_SOURCE
INSPECT_TARGETS
STAGE_FILES
VERIFY_STAGED_HASHES
INSTALL
WRITE_MANIFEST
RUN_PASSIVE_DOCTOR
PASS
```

Update must restore the prior known-good files and manifest on failure. Until Task 12 exists, installer GREEN uses the injected deterministic passive-Doctor test double; integration with the real passive Doctor is verified in Task 12 and Task 17.

- [ ] **Step 5: Implement uninstall**

Delete only manifest-listed files whose current hash equals the managed hash. Preserve backups by default.

- [ ] **Step 6: Run GREEN in both shells when available**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite Installer -Phase GREEN -Json
if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    pwsh.exe -NoProfile -File .\evals\run-evals.ps1 -Suite Installer -Phase GREEN -Json
}
```

Windows PowerShell 5.1 is mandatory; PowerShell 7 result is recorded separately.

- [ ] **Step 7: Commit**

```powershell
git add scripts evals
git commit -m "feat: add transactional windows installer"
```

---

### Task 12: Implement passive Doctor and Specialist capability-state storage

**Files:**
- Create: `scripts/lib/ProjectFlightControl.Doctor.psm1`
- Create: `scripts/doctor.ps1`
- Create: `evals/schemas/install-state.schema.json`
- Create: `evals/scenarios/core-governance/SC-28-passive-doctor/scenario.ps1`
- Create: `evals/scenarios/core-governance/SC-31-specialist-core-boundary/scenario.ps1`
- Modify: `scripts/lib/ProjectFlightControl.Install.psm1`
- Modify: `evals/run-evals.ps1`

**Interfaces:**

```powershell
 doctor.ps1 [-UserHome <path>] [-StateRoot <path>] [-SpecialistSmoke] [-Json]
```

`Invoke-PfcPassiveDoctor` returns checks plus `specialist_capability = AVAILABLE|UNKNOWN|UNAVAILABLE` without invoking Codex.

`install-state.json` records product/version, managed files/hashes, backup, last doctor, and Specialist capability record/fingerprint.

- [ ] **Step 1: Write failing passive-Doctor tests**

Tests use a process-invocation spy and must prove default Doctor does **not** call:

```text
codex exec
codex app-server
spawn_agent
any model endpoint
```

State cases:

```text
missing formal agent → core BLOCKED
missing Specialist runtime evidence with prerequisites present → UNKNOWN
explicit missing capability prerequisite → UNAVAILABLE
valid unexpired active record with matching fingerprint → AVAILABLE
client/Skill-major/agent/sandbox fingerprint change → UNKNOWN
previous isolation/SHA/report/cleanup failure → UNKNOWN or UNAVAILABLE according to evidence
```

- [ ] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite Doctor -Phase RED -Json
```

- [ ] **Step 3: Implement passive checks**

Check formal installed files, hashes, Git/worktree availability, Codex executable/version when discoverable, multi-agent configuration when observable, temp/staging access, and capability-record validity. Unknown client interfaces remain `UNKNOWN`; do not infer `AVAILABLE` from file presence.

- [ ] **Step 4: Implement deterministic environment fingerprinting**

Fingerprint components:

```text
Codex version string
Skill major version
Builder/Verifier agent file hashes
relevant sandbox/permission configuration hash when readable
Git worktree capability result
```

Do not hash or persist auth files.

- [ ] **Step 5: Run GREEN and commit**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite Doctor -Phase GREEN -Json
git add scripts evals
git commit -m "feat: add passive doctor and capability state"
```

---

### Task 13: Implement explicit Specialist Smoke adapter without making it a core dependency

**Files:**
- Create: `evals/scenarios/specialist-capability/SC-21-fixed-sha-worktree/**`
- Create: `evals/scenarios/specialist-capability/SC-22-no-formal-verdict/**`
- Create: `evals/scenarios/specialist-capability/SC-23-unresolved-prerequisite/**`
- Create: `evals/scenarios/specialist-capability/SC-25-stale-evidence/**`
- Create: `evals/scenarios/specialist-capability/SC-26-resume-same-order/**`
- Create: `evals/scenarios/specialist-capability/SC-29-explicit-smoke/**`
- Create: `evals/scenarios/specialist-capability/SC-30-capability-invalidation/**`
- Modify: `scripts/lib/ProjectFlightControl.Doctor.psm1`
- Modify: `scripts/doctor.ps1`
- Modify: `evals/lib/CodexRunner.psm1`

**Interfaces:**
- `Invoke-PfcSpecialistSmoke` either returns a fully evidenced success record or a truthful `UNKNOWN/UNAVAILABLE`; it never fabricates runtime capability.
- No fixed Specialist agent is installed. Any temporary config or runtime instruction material lives inside the disposable smoke environment and is deleted.

- [ ] **Step 1: Write deterministic RED tests for smoke orchestration**

Use injected fake process and worktree adapters to verify:

```text
-SpecialistSmoke is required
fixture repo and fixed SHA created
independent worktree created
read-only request and output schema supplied
tracked/staged changes checked before and after
structured report SHA verified
thread/process closed
worktree removed with standard git worktree remove
failure invalidates AVAILABLE record
```

- [ ] **Step 2: Run orchestration RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite SpecialistSmokeUnit -Phase RED -Json
```

- [ ] **Step 3: Implement a capability adapter, not a guessed platform API**

The adapter must choose only from mechanisms confirmed by the current installed Codex version. If no supported way can prove “Goalkeeper creates a temporary subagent with fixed worktree, read-only boundary, and structured report,” return `UNKNOWN` or `UNAVAILABLE`. A plain single-agent `codex exec` run is not sufficient proof of subagent capability.

- [ ] **Step 4: Run unit GREEN**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite SpecialistSmokeUnit -Phase GREEN -Json
```

- [ ] **Step 5: Run the real smoke only with explicit user authorization**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -SpecialistSmoke -Json
```

Expected outcomes:

```text
PASS + AVAILABLE only when every invariant is proven
PARTIAL/FAIL + UNKNOWN when platform behavior is inconclusive
FAIL + UNAVAILABLE when a required capability is definitively absent
```

A failed Specialist smoke does not undo a passing core installation.

- [ ] **Step 6: Commit the adapter and conditional scenarios**

```powershell
git add scripts evals
git commit -m "feat: add conditional specialist smoke adapter"
```

---

### Task 14: Run Builder GREEN evaluations and implement missing efficiency corrections

**Files:**
- Modify only when RED→GREEN evidence exposes a precise deficiency:
  - `codex-agents/project-flight-builder.toml`
  - `skill/project-flight-control/references/builder-debugging.md`
  - affected scenario manifests/expected evidence only when the predeclared contract was objectively malformed
- Create: `evals/expected/builder-efficiency/green/**`

**Interfaces:**
- Same fixtures, Base SHAs, prompts, model, effort, sandbox, and repetition count as Task 3.
- RED and GREEN normalization schema must be identical.

- [ ] **Step 1: Confirm comparison controls have not drifted**

Run a deterministic hash comparison of all scenario fixtures, prompts, schemas, and control variables against the committed RED manifest. Any drift blocks comparison until reverted or separately approved.

- [ ] **Step 2: Obtain current-task authorization for 35 GREEN runs**

Report:

```text
7 scenarios × 5 fresh repetitions = 35 Codex runs
```

- [ ] **Step 3: Run GREEN**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite BuilderEfficiency -Phase GREEN -Repeat 5 -Json
```

- [ ] **Step 4: Evaluate the hard gates**

Require:

```text
quality/safety baseline not worse than RED
EFF-01 through EFF-07 each meet its predeclared primary behavioral target
no reduction of necessary verification
no new unrelated changes
no hidden FAIL/PARTIAL/NOT_RUN
actual usage recorded when available, otherwise NOT_AVAILABLE
```

- [ ] **Step 5: Refactor only the failed rule, then rerun the same scenario**

Do not globally lengthen Builder instructions to solve one scenario. Every prompt change must identify the failed invariant and its prompt-budget delta.

- [ ] **Step 6: Commit GREEN evidence**

```powershell
git add codex-agents skill evals/expected
git commit -m "test: pass builder efficiency green gates"
```

---

### Task 15: Implement and run the core three-role integration scenarios

**Files:**
- Create scenario files for:
  - `SC-01` through `SC-14`
  - `SC-16` through `SC-20`
  - `SC-24`, `SC-27`, `SC-28`, `SC-31`
- Create: `evals/schemas/project-control-report.schema.json`
- Create: `evals/expected/core-governance/**`
- Create: `evals/expected/full-workflow/**`
- Modify: `evals/run-evals.ps1`

**Interfaces:**
- Each scenario records Initial State, Prompt, Controls, Expected/Forbidden actions, Files, Git graph, Status, metric, actual normalized evidence, usage/NOT_AVAILABLE, and Verdict.
- Multi-agent runs require observable Builder and Verifier thread identities. Main-thread role simulation fails the scenario.

- [ ] **Step 1: Implement deterministic scenario setup and assertions**

At minimum assert:

```text
clean original worktree
separate milestone and verifier worktrees
Candidate SHA frozen before verification
control-only acceptance commit
wrong SHA/report rejected
old Lease Epoch rejected
verification-induced tracked-file change fails integrity
uncommitted original-worktree decision gate
non-Git implementation blocked
human verbal confirmation not accepted alone
Goal final audit uses fresh Verifier context
Company OS/Repo Map/Memory/telemetry absent
passive Doctor produces no model invocation
Specialist unavailable does not fail core release but blocks a Specialist-required task
```

- [ ] **Step 2: Record plain-Codex full-workflow RED comparison**

Use a fixed smaller representative subset chosen **before** results, with the same task contract and success criteria. Record total model turns, tool calls, revisions, incorrect completions, scope deviations, and final correctness.

- [ ] **Step 3: Run Project Flight Control GREEN scenarios**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite CoreGovernance -Phase GREEN -Json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite FullWorkflow -Phase GREEN -Json
```

Model-backed counts must be shown to the user before execution. High-cost scenarios may use fewer repetitions only when the repetition count was fixed in each scenario manifest before the first run.

- [ ] **Step 4: Manually inspect every core result**

Keyword presence is insufficient. Confirm actual Git graphs, diffs, worktree state, test evidence, and role separation.

- [ ] **Step 5: Enforce core release gates**

Require:

```text
QUALITY_AND_SAFETY_GATE = PASS
CORE_EFFICIENCY_GATE = PASS
Role Isolation = PASS
Explicit-Only Invocation = PASS
Git/Worktree Integration = PASS
Required Core GREEN Scenarios = PASS
Open BLOCKER = 0
Open MAJOR = 0
```

- [ ] **Step 6: Commit normalized evidence**

```powershell
git add evals
git commit -m "test: pass core three role integration gates"
```

---

### Task 16: Run conditional Specialist scenarios when capability is AVAILABLE

**Files:**
- Modify: `evals/expected/specialist-capability/**`
- Modify only if a proven protocol defect exists:
  - `skill/project-flight-control/references/specialist-protocol.md`
  - Specialist templates
  - Doctor capability adapter

**Interfaces:**
- If published capability is `UNKNOWN` or `UNAVAILABLE`, scenarios are `NOT_APPLICABLE`, not faked as PASS.
- If capability is `AVAILABLE`, SC-21/22/23/25/26/29/30 become hard gates for that capability claim.

- [ ] **Step 1: Read the current capability record**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -Json
```

- [ ] **Step 2: Branch only on evidenced status**

```text
AVAILABLE → run conditional suite
UNKNOWN/UNAVAILABLE → record NOT_APPLICABLE and confirm documentation does not claim support
```

- [ ] **Step 3: Run conditional suite when applicable**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite SpecialistCapability -Phase GREEN -Json
```

- [ ] **Step 4: Invalidate the capability claim on any invariant failure**

A failure in SHA binding, read-only behavior, structured report, single evidence round, no-verdict authority, resume identity, or cleanup updates capability to `UNKNOWN`/`UNAVAILABLE` and removes `AVAILABLE` from release text.

- [ ] **Step 5: Commit evidence/status only**

```powershell
git add evals README.md CHANGELOG.md
git commit -m "test: record specialist capability status"
```

---

### Task 17: Final documentation, package verification, and release-candidate handoff

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `VERSION`
- Create conditionally: `LICENSE` after explicit user-approved SPDX license selection
- Do not modify: `docs/project-flight-control-design.md`; preserve the approved SHA-256 exactly
- Create: `docs/verification/v1-verification-report.md`
- Create: `docs/verification/v1-known-risks.md`
- Create: `docs/verification/v1-release-gate.json`

**Interfaces:**
- Verification report is evidence-backed and references committed normalized results.
- Version remains `0.1.0-dev.0` unless the user separately authorizes release promotion after all gates pass.

- [ ] **Step 1: Resolve the public-license gate without guessing**

Before creating `LICENSE` or public release artifacts, obtain an explicit SPDX identifier from the user. Record the exact choice in `docs/verification/v1-release-gate.json`. If no choice has been provided, set `LICENSE_GATE = NOT_RUN`, keep `LICENSE` absent, and continue only with non-release verification.

- [ ] **Step 2: Run the complete deterministic suite**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite AllDeterministic -Json
```

Expected: all static, schema, installer, doctor, fixture, and safety checks `PASS`.

- [ ] **Step 3: Run package and repository integrity checks**

```powershell
git diff --check
git status --short
git ls-files
git grep -n -E "OPENAI_API_KEY|CODEX_API_KEY|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|password[[:space:]]*=" -- . ':!docs/project-flight-control-design.md'
```

Expected: no accidental secrets; only intended tracked files; no whitespace errors. Recompute `docs/project-flight-control-design.md` SHA-256 and require `e5c90a41c28ce8e7f9192102f14613adef5af93ee7ee5007b4f69df6ed57dedd`.

- [ ] **Step 4: Run install/update/uninstall round trip in a clean temporary profile**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\evals\run-evals.ps1 -Suite InstallerRoundTrip -Phase GREEN -Json
```

Expected: `PASS`; original user locations remain untouched because the test supplies temporary roots.

- [ ] **Step 5: Perform Windows real-machine smoke**

Verify:

```text
Skill appears and only explicit $project-flight-control activates it
Builder and Verifier profiles are visible and separately spawnable
formal role isolation is observable
Candidate and Verifier worktrees bind correct SHAs
passive Doctor makes zero model calls
Specialist status is reported truthfully
```

Record actual Codex version, Windows version, PowerShell version, Git version, permission mode, and results.

- [ ] **Step 6: Produce the release-gate file**

`v1-release-gate.json` must include every approved gate and one of `PASS/FAIL/PARTIAL/NOT_RUN`. It must separately report core V1, Runtime Specialist capability, and `LICENSE_GATE`.

- [ ] **Step 7: Review the plan/spec traceability**

Confirm every AC-SKILL-001 through AC-SKILL-023 has at least one test/evidence location. List gaps as BLOCKER; do not write “covered” without a path.

- [ ] **Step 8: Review final diff and status**

```powershell
git diff main...HEAD --stat
git diff main...HEAD --check
git status --short
git log --oneline --decorate main..HEAD
```

- [ ] **Step 9: Commit verification documents**

```powershell
$releaseFiles = @("README.md", "CHANGELOG.md", "VERSION", "docs")
if (Test-Path -LiteralPath ".\LICENSE") { $releaseFiles += "LICENSE" }
git add -- $releaseFiles
git commit -m "docs: record project flight control verification"
```

- [ ] **Step 10: Stop before merge, push, publication, or version promotion**

Return the exact status:

```text
IMPLEMENTATION: PASS / FAIL / PARTIAL
CORE_RELEASE_GATE: PASS / FAIL / PARTIAL / NOT_RUN
SPECIALIST_CAPABILITY: AVAILABLE / UNKNOWN / UNAVAILABLE
TOKEN_USAGE: RECORDED / NOT_AVAILABLE
REMOTE_ACTIONS: NOT_AUTHORIZED
```

Do not merge, push, publish, deploy, or change `VERSION` to `1.0.0` without a new explicit user instruction.

---

# Acceptance-Criteria Traceability

| Approved criterion | Primary tasks |
|---|---|
| AC-SKILL-001 Explicit trigger | 2, 6, 15, 17 |
| AC-SKILL-002 Real role isolation | 5, 7, 8, 15, 17 |
| AC-SKILL-003 Staged creation | 5, 6, 10, 15 |
| AC-SKILL-004 Git and worktrees | 5, 9, 13, 15, 17 |
| AC-SKILL-005 Evidence version binding | 4, 8, 9, 10, 15 |
| AC-SKILL-006 Single control writer | 4, 5, 9, 15 |
| AC-SKILL-007 Independent verification | 8, 14, 15 |
| AC-SKILL-008 Finding authority | 4, 8, 10, 15 |
| AC-SKILL-009 Debug/rework convergence | 7, 9, 14, 15 |
| AC-SKILL-010 Contract change | 4, 5, 15 |
| AC-SKILL-011 Human verification | 4, 9, 15 |
| AC-SKILL-012 Recovery | 3, 9, 14, 15 |
| AC-SKILL-013 Milestone inheritance | 5, 9, 15 |
| AC-SKILL-014 Goal final audit | 5, 8, 15 |
| AC-SKILL-015 Installation safety | 11, 12, 17 |
| AC-SKILL-016 Truthful verification | all tasks; final gate in 17 |
| AC-SKILL-017 Builder efficiency | 3, 7, 14 |
| AC-SKILL-018 Minimal role context | 5, 6, 7, 8, 10, 15 |
| AC-SKILL-019 Incremental verification/evidence | 4, 8, 9, 14, 15 |
| AC-SKILL-020 Controlled Specialist | 10, 12, 13, 16 |
| AC-SKILL-021 Efficiency eval/release gates | 2, 3, 14, 15, 17 |
| AC-SKILL-022 Lightweight V1 boundary | 2, 6, 7, 10, 17 |
| AC-SKILL-023 Specialist detection/release semantics | 12, 13, 16, 17 |

# Plan Self-Review

## Spec coverage

- Repository/package layout: covered by Tasks 1–2.
- Message contracts and templates: Task 4.
- Roles, modes, state, orchestration, Git/worktrees: Tasks 5–6.
- Builder efficiency/debugging: Tasks 3, 7, 14.
- Verifier evidence reuse/independent rerun: Tasks 8, 15.
- Compact evidence/convergence/recovery: Task 9.
- Runtime Specialist protocol and capability gate: Tasks 10, 12, 13, 16.
- Transactional Windows lifecycle: Tasks 11–12.
- RED–GREEN, EFF-01 through EFF-07, core and conditional scenarios: Tasks 2–3, 14–16.
- Final release/verification boundary: Task 17.

## Scope and dependency check

- No production dependency is added.
- The plan does not choose an open-source license on the user's behalf; license selection is a separate release gate.
- PowerShell helper modules are implementation support, not installed runtime roles or services.
- Runtime Specialist remains optional and cannot block a qualified three-role core release.
- Company OS, Repo Map, Memory, telemetry, fixed extra roles, and task-complexity modes remain excluded.
- Model-backed evals are isolated from deterministic package checks and require explicit current-task authorization.

## Execution sequence

1. Task 1 establishes the approved evidence baseline and isolated development worktree.
2. Tasks 2–3 create RED evidence before behavioral implementation.
3. Tasks 4–10 implement the instruction/runtime package with deterministic checks after every unit.
4. Tasks 11–13 implement safe Windows lifecycle and optional capability probing.
5. Tasks 14–16 run GREEN and integration gates without changing predeclared controls after results.
6. Task 17 creates evidence-backed final status and stops before any remote or release action.
