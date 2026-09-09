# Project Flight Control

[简体中文](README.md) | [English](README.en.md)

When AI works on a complex project, one role keeps the goal clear, another does the work, and a third checks the results.

> Current version: `0.1.0-dev.0`. This is a development version for trying out and studying the workflow. It is not a stable release yet.

## 1. What is this repository?

Project Flight Control is a project management Skill for Codex.

When a task takes a long time, touches many files, or needs several sessions to finish, it divides the work among three roles:

- **Goalkeeper**: Confirms the goal, scope, and completion criteria, records progress, and decides what happens next.
- **Builder**: Implements the agreed task and provides evidence of the work.
- **Verifier**: Checks the results in a separate environment and identifies omissions, errors, and risks.

It is not a new AI model or a single “magic prompt.” It is a structured way of working that helps AI stay on track, makes the work easier to review, and lets you continue a complex project later.

## 2. Who is it for?

### A good fit for

- People using Codex to build websites, tools, automated workflows, or personal products.
- People who do not write much code but want AI to work in a more organized way.
- People whose tasks continue across multiple conversations or stages.
- People concerned that AI might change the wrong files, skip tests, or say a task is complete when it is not.
- Solo business owners, independent developers, product designers, and AI builders.
- People who want check results, reasons for failures, and suggested next steps at each stage.

### Not a good fit for

- Asking a simple question, changing a line of text, or making a small edit.
- Letting AI change production systems, publish products, or handle sensitive data without human oversight.
- Projects that need the current Windows sandbox to provide strict confidentiality.
- People who do not use Codex, or whose environment does not support the Skill and role configuration this project requires.

## 3. What will you get?

You will usually get:

- A clear goal, scope, and set of completion criteria.
- A plan divided into stages, with current progress recorded.
- Code or file changes made by Builder.
- Independent check results from Verifier.
- Tests, evidence, and an explanation of risks for each stage.
- A final report covering what was done, what passed, what still needs attention, and what comes next.

## 4. Why use it?

### Keep the work on track

The goal and boundaries are made clear before work begins. If you change direction along the way, that change is recorded first.

### Make completion verifiable

Builder implements the work, and Verifier checks it. Completion depends on actual files, tests, and check results, rather than only the AI's own summary.

### Continue long tasks later

Project state is saved in Git and project records. You can continue from the actual state of the work after switching conversations, pausing for a few days, or recovering from an interruption.

### Make failures easier to handle

When something goes wrong, the workflow records the reason, the affected scope, and the next step. Work that has not been verified is not reported as passed.

## 5. An example

Suppose you want Codex to build a small product with a page, data storage, and tests.

A typical request might be:

```text
Help me finish this feature.
```

With Project Flight Control, you can start like this:

```text
$project-flight-control

MODE: START
Goal: Add a user profile page to the current project and save the information users enter.
Constraints: Do not change production systems or publish anything.
Completion criteria: The page works, data can be saved, relevant tests pass, and an independent review is complete.
```

The work then follows this sequence: confirm the goal → implement → independently review → revise or accept. At the end, you will see a report similar to this:

```text
Current status: PARTIAL
Completed: Profile page and data storage
Check results: Page tests passed; permission checks still need attention
Blocker: Missing test environment configuration
Next step: Complete the configuration, then check permissions again
```

## 6. Installation

### Option 1: Download with Git

Run these commands in Windows PowerShell:

```powershell
git clone https://github.com/yangjing6213-dev/codex-project-flight-control-Agents-Token-.git
cd codex-project-flight-control-Agents-Token-
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Json
```

### Option 2: Download a ZIP

1. Open this repository and click **Code → Download ZIP**.
2. Extract the ZIP and open PowerShell in the extracted folder.
3. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Json
```

After installation, reopen Codex or create a new Codex task. You can check the installation with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -Json
```

If the installer reports a conflict with existing files, keep those files and give Codex the full output to investigate. Do not delete or overwrite them directly.

## 7. How to use it

This Skill only starts when you explicitly invoke it. Enter the following on the first line of your Codex message:

```text
$project-flight-control
```

Use this format:

```text
$project-flight-control

MODE: START
Goal: Implement user login for the current repository.
Constraints: Do not change production systems or push to a remote repository.
Completion criteria: Implementation, tests, and independent review all pass.
```

There are four modes:

- `START`: Begin a new complex task.
- `RESUME`: Continue from existing Git history and project records.
- `AUDIT`: Check an existing implementation, its results, or its release status.
- `STATUS_ONLY`: View progress without changing files.

To continue an existing task:

```text
$project-flight-control

MODE: RESUME
Recover the current state from Git and project records, then continue the remaining work.
```

To review only:

```text
$project-flight-control

MODE: AUDIT
Check whether the current implementation meets the design, testing, and safety requirements. Do not change code.
```

To view progress only:

```text
$project-flight-control

MODE: STATUS_ONLY
Read the current project state and report completed tasks, blockers, and the next step.
```

## 8. How the workflow works

1. **You set the goal**: Explain what you want to do and what must not be done.
2. **Goalkeeper organizes the task**: Confirms the scope, completion criteria, current project state, and risks.
3. **Builder implements the work**: Handles only the agreed work and runs the relevant checks.
4. **Verifier reviews independently**: Checks whether the results meet the goal, whether the tests are trustworthy, and whether anything is missing.
5. **Goalkeeper decides what happens next**: Accepts the work, sends it back for revision, pauses, or waits for your decision, and leaves a clear project report.

By default, each stage stops at a clear checkpoint. Results that have not passed are not used directly as the basis for the next stage.

## 9. Repository structure

```text
├─ skill/project-flight-control/   Main Skill file, rules, and report templates
├─ codex-agents/                   Builder and Verifier configuration
├─ scripts/                        Installation, update, removal, and status-check scripts
├─ evals/                          Tests, checking tools, and evaluation scenarios
├─ docs/                           Design, plans, verification reports, and known risks
├─ assets/                         Images used in the README
├─ VERSION                         Current version number
└─ LICENSE                         MIT open-source license
```

## 10. Things to know

- You must enter `$project-flight-control` to activate it. Ordinary conversations do not trigger it automatically.
- The current version is `0.1.0-dev.0`. It is for trying out and studying the workflow and has not met the requirements for a stable release.
- Strict read isolation on Windows has not been reliably verified. Do not rely on this workflow to protect passwords, keys, customer information, or other sensitive files.
- Builder Efficiency has passed deterministic checks, but comparisons using real models are not complete. The project therefore does not promise to save tokens or time.
- Specialist remains an optional capability. Do not assume it is a fixed role available in every environment.
- The Skill uses Git, commits, and separate workspaces to preserve progress. Back up important projects first, and carefully review what you are authorizing before any push, publication, or production operation.
- AI check results still need your final judgment, especially when accounts, costs, permissions, privacy, or live business operations are involved.
- This project uses the [MIT License](LICENSE). You can use, modify, and share the code, but you must keep the original copyright and license notices.

## 11. Related projects

None.

## 12. About the author

![About Enhe (恩禾)](assets/author-enhe.png)

### Enhe (恩禾)

Product designer · Solo business practitioner · AI Builder

**Building a one-person company with AI.**

- GitHub: [yangjing6213-dev](https://github.com/yangjing6213-dev)
- X / Twitter: [@Amenenhe_ai](https://x.com/Amenenhe_ai)
- Website: [www.enhe-tech.com.cn](https://www.enhe-tech.com.cn/)
- WeChat: `Hu-Amen`
- Email: **amen.enhe@gmail.com**

[ENHE AI | AI tools, news, account services, and skills courses](https://www.enhe-tech.com.cn/)

## 13. Explore more

This project is one tool in the personal creation system I am building with AI. If you also use AI for content, knowledge bases, workflows, or turning ideas into products, visit [www.enhe-tech.com.cn](https://www.enhe-tech.com.cn/) for more resources.
