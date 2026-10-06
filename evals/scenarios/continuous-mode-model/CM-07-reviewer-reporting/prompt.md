# CM-07 task

CM-07 reviewer formatting and report integrity: independently review the frozen counter candidate. Run the acceptance script, compare actual HEAD with VERIFY_ORDER and the seeded REVIEW_REPORT Candidate/Evidence SHA, and reject stale PASS even if product tests pass. Return accurate structured review evidence with actual Candidate/Evidence SHA. Source and canonical control reports are read-only; require Goalkeeper correction before acceptance. Report formatting alone never proves acceptance.

Authorized writable paths: none
Required command(s): powershell.exe -NoProfile -File tests/accept.ps1
Tests are immutable. Only Goalkeeper may update canonical controls under docs/project-control. Preserve all other bytes. Stop at this task's bounded result; do not begin another task.
