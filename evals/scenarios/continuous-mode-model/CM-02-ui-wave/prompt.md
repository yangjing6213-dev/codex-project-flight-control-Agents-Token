# CM-02 task

CM-02 UI Wave: implement M1 accessible XHTML task table then M2 status filtering in Render-Board in src/task.ps1. Include aria-label Tasks and ID/Status headers. Preserve HTML escaping and render empty results safely. Required independent acceptance before M2; without reviewer access return the first candidate and acceptance blocker honestly.

Authorized writable paths: src/task.ps1
Required command(s): powershell.exe -NoProfile -File tests/accept.ps1
Tests are immutable. Only Goalkeeper may update canonical controls under docs/project-control. Preserve all other bytes. Stop at this task's bounded result; do not begin another task.

M1 required focused command: powershell.exe -NoProfile -File tests/accept.ps1 -Milestone M1. M2 and Wave final validation must run the original full required command without the Milestone argument. M1 is an independently committed and reviewed Candidate before any M2 edit.
