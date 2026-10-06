# CONTINUATION_CHECKPOINT

Synthetic render example; replace all identities and evidence. Fields: message-contracts.md.

```json
{
  "schema_version": "pfc.continuation-checkpoint.v1",
  "authorization_id": "AUTH-20260920-001",
  "control_run_id": "RUN-001",
  "lease_epoch": 1,
  "wave_id": "WAVE-001",
  "milestone_id": "A-015",
  "previous_accepted_checkpoint_sha": "FIRST_MILESTONE",
  "current_milestone_base_sha": "0000000000000000000000000000000000000000",
  "expected_builder_start_sha": "0000000000000000000000000000000000000000",
  "repair_budget": {
    "builder_code_repair_attempts": 0,
    "auto_rework_rounds": 0,
    "candidate_revisions": 0
  },
  "recovery_manifest": {
    "recovery_package_reference": "RECOVERY-SYNTHETIC-001",
    "git_status": [
      {
        "path": "src/example.txt",
        "original_path": "NONE",
        "status": " M"
      }
    ],
    "files": [
      {
        "path": "src/example.txt",
        "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
        "size_bytes": 1,
        "recovery_copy": "files/example.txt",
        "classification": "ACTIVE"
      }
    ],
    "allowed_paths": [
      "src/example.txt"
    ]
  },
  "updated_at": "2026-09-20T00:00:00Z"
}
```
