# Changelog

## Unreleased

### Implemented

- Added the MIT license and public development snapshot documentation. Version remains `0.1.0-dev.0`; stable-release and efficiency gates remain blocked.
- Goalkeeper, Builder, and Verifier package implementation, Builder Efficiency Protocol, deterministic evaluation harness, file-handshake Permission Probe, and strict result Schema.

### Deterministically Verified

- Bootstrap, package, Harness, Builder Efficiency, profiles, isolation, schema, runner, Doctor, Installer, Specialist protocol, and file-handshake suites pass under Windows PowerShell 5.1.
- Approved design SHA-256 remains `e5c90a41c28ce8e7f9192102f14613adef5af93ee7ee5007b4f69df6ed57dedd`.

### Runtime Blocked

- Blocker `PFC-UPSTREAM-001`: native Windows Codex deny-read permission enforcement was not verified. The valid local probe result reported readable Evidence and External roots despite the selected elevated profile. Related open reports are `openai/codex#42184` and `openai/codex#31265`; their similarity is recorded without claiming official confirmation.
- Controlled RED/GREEN, Core Efficiency, and Stable Release gates remain blocked. The current Permission Profile must not be used as a confidentiality boundary for sensitive files.

### Not Yet Proven

- Model-backed efficiency improvement, token reduction, Runtime Specialist capability, and a stable release remain unproven.
