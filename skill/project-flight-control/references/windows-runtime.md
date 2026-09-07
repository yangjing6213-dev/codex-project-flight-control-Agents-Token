# Windows runtime rules

The supported runtime is Windows 10/11 with Windows PowerShell 5.1 and Git for Windows. All required evaluation commands run through `powershell.exe`; `pwsh.exe` may be used only for an explicitly available compatibility check and never replaces the PowerShell 5.1 gate.

## Paths and files

Path normalization is mandatory before path comparison or file access.

Normalize paths with the .NET or PowerShell path APIs, resolve them before comparing, and keep comparisons case-insensitive where Windows semantics require it. Never hard-code a drive letter, user profile, or machine-specific root; derive repository and temporary paths from the current invocation. Reject paths that escape the intended repository or temporary directory. Treat protected `.git`, `.codex`, and credential locations as protected paths and do not write through them without the host's explicit approval.

Write text as UTF-8 using an explicit encoding supported by Windows PowerShell 5.1. Consumers must not depend on a BOM; readers accept UTF-8 with or without BOM. Keep generated control files and evidence deterministic, newline-safe, and free of secrets.

## Shell, Git, and permissions

Use Windows PowerShell 5.1 syntax and cmdlets that parse under that host. Detect `powershell.exe` and, separately, optional `pwsh.exe`; report a missing executable as `NOT_RUN` or `BLOCKED`, never as PASS. Require Git for Windows and record its version in environment evidence. Detached HEAD is expected for fixed Candidate and Specialist worktrees; verify the actual HEAD SHA before and after checks.

Evaluation and runtime actions use the least sandbox and approval scope that completes the local deterministic task. Do not request or silently widen approvals. Never use a hard-coded drive path, network or remote operation, model execution, install, global setting, or production action as a substitute for local evidence.

All PowerShell scripts must parse under 5.1. Use `-LiteralPath` for resolved paths, avoid shell-specific quoting assumptions, and preserve non-ASCII text through explicit UTF-8 reads and writes. A path, encoding, or executable mismatch is an environment limitation and must be recorded with its actual status.
