# CM-03 task

CM-03 migration plus CRUD: implement the three src/task.ps1 functions. This is authorized local synthetic-data migration only; retain original v1 bytes, preserve IDs, make upgrade idempotent, support v2 create/read and exact downgrade of existing data. Required validation includes upgrade, rollback, idempotence and complete acceptance tests; do not replace data/v1.json.

Authorized writable paths: src/task.ps1
Required command(s): powershell.exe -NoProfile -File tests/accept.ps1
Tests are immutable. Only Goalkeeper may update canonical controls under docs/project-control. Preserve all other bytes. Stop at this task's bounded result; do not begin another task.
