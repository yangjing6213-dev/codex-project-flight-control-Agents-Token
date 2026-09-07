# Project Flight Control V1 Known Risks

## PFC-UPSTREAM-001 — Native Windows deny-read permission enforcement not verified

The verified local environment selected `pfc-controlled` with the elevated backend, but the valid file-handshake Permission Probe reported readable Evidence, External, and private profile sources where denial was required. This is recorded as an upstream runtime blocker, not as proof that the Project Flight Control profile syntax or Elevated Setup failed.

Related open reports:

- `openai/codex#42184` — “Windows elevated sandbox: :root = deny permission profile still allows reads outside explicitly reopened roots”. Similarity: elevated native Windows sandbox, named permission profile, and reads outside the approved root succeed.
- `openai/codex#31265` — “deny-read permission profile silently ineffective on native Windows (ACL state empty) — 0.142.5”. Similarity: native Windows elevated backend and deny-read rules fail to prevent reads. The local environment used Codex CLI 0.153.1; the authorization references 0.152.1 for the upstream comparison, so the versions are recorded separately.

Neither report is treated as an official root-cause confirmation or fix. The current profile must not be used to protect secrets, customer code, personal documents, commercial-sensitive files, authentication configuration, or other content requiring enforced refusal.

Resume trigger: a future Codex version or credible upstream change that materially alters native Windows deny-read behavior.

Resume prerequisites:

1. The Codex version differs from 0.152.1.
2. The relevant upstream report has a credible behavior change.
3. The user explicitly authorizes one new Permission Probe.
4. The new version is tested from a fresh probe; historical results are not reused.
5. The sequence is passive Doctor, one zero-model Probe, required DENIED results, deterministic gates, independent review, one RED, one matching GREEN, then a decision on remaining repetitions.

The following risks remain open for the current `PARTIAL / NOT_READY` checkpoint:

1. **Runtime permission enforcement failed.** The elevated backend is configured and the audited file-handshake probe completed with a valid result, but Fixture, Evidence, External and several path-escape operations were `ALLOWED`. The sentinel was unchanged; the required deny behavior was not observed.
2. **Controlled efficacy is blocked.** No valid controlled RED or GREEN model sample can be compared, so no efficiency or token-reduction claim is permitted.
3. **Specialist runtime capability is unknown.** Deterministic Specialist checks pass, but no real runtime capability claim is made.
4. **Stable release gate remains closed.** Core release is `NOT_RUN_BLOCKED`; V1 is `NOT_READY`. MIT licensing resolves only the license gate; it does not resolve the runtime or efficacy gates.
5. **Public source is a development snapshot.** The user authorized GitHub source publication and delegated the MIT license choice on 2026-09-07. Publication does not establish production readiness or upgrade version `0.1.0-dev.0` to a stable release.

The runtime closeout restrictions still prohibit a second Setup/UAC, execution-policy workaround, probe retry, manual Windows security change, fallback sandbox mode, Revision 5, and Controlled RED/GREEN. The subsequent source-publication authorization does not reopen these runtime actions. These risks remain unresolved.
