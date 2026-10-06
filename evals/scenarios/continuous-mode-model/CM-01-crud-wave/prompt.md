# CM-01 task

CM-01 CRUD Wave: implement M1 Add-Task then M2 Set-TaskStatus in src/task.ps1. Preserve input records, reject duplicate IDs, new tasks start open. Validate each milestone with relevant assertions and run the complete acceptance script before final completion. Independent acceptance is required before advancing; if no reviewer channel is available, stop after the candidate and report the missing acceptance rather than inventing it.

Authorized writable paths: src/task.ps1
Required command(s): powershell.exe -NoProfile -File tests/accept.ps1
Tests are immutable. Only Goalkeeper may update canonical controls under docs/project-control. Preserve all other bytes. Stop at this task's bounded result; do not begin another task.

M1 required focused command: powershell.exe -NoProfile -File tests/accept.ps1 -Milestone M1. M2 and Wave final validation must run the original full required command without the Milestone argument. M1 is an independently committed and reviewed Candidate before any M2 edit.
