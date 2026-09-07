# Project Flight Control

IMPLEMENTATION: PARTIAL

CORE_IMPLEMENTATION: COMPLETE_DETERMINISTICALLY

TOKEN_EFFECT: NOT_PROVEN

CORE_RELEASE_GATE: BLOCKED

CONTROLLED_EFFICACY: BLOCKED_UPSTREAM_NATIVE_WINDOWS_READ_DENY

V1_RELEASE: NOT_READY

This repository contains the approved Project Flight Control V1 design and its local development snapshot.

The fixed core roles are Goalkeeper, Builder, and Verifier. The Builder Efficiency Protocol is implemented and deterministically tested. Runtime Specialist capability remains `UNKNOWN`; it is not a fixed fourth role or a core release dependency.

The single authorized controlled Windows permission probe produced a valid file-handshake result showing permissive access where denial was required. Native Windows Codex deny-read behavior is therefore not a trustworthy confidentiality boundary in the verified environment. Model-driven RED/GREEN comparison is incomplete, and token reduction has not been proven.

Version `0.1.0-dev.0` is a development snapshot for review and experimentation. It is not a stable release.

## Project contents

- `skill/project-flight-control/`: the skill, governance references and report templates.
- `codex-agents/`: Builder and Verifier profiles.
- `scripts/`: install, update, uninstall and passive Doctor commands.
- `evals/`: deterministic checks, evaluation contracts and runner implementation.
- [Verification report](docs/verification/v1-verification-report.md) and [known risks](docs/verification/v1-known-risks.md): verified behavior and remaining limitations.

## License

Licensed under the [MIT License](LICENSE), SPDX identifier `MIT`.
Reuse, modification, distribution and commercial use are permitted subject to preserving the copyright and license notice. The software is provided without warranty.
