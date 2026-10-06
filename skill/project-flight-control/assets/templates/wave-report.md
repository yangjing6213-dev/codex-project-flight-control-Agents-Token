# WAVE_REPORT

Synthetic render example; replace all identities and evidence. Fields: message-contracts.md.

```json
{
  "schema_version": "pfc.wave-report.v1",
  "wave_id": "WAVE-001",
  "authorization_id": "AUTH-20260920-001",
  "base_checkpoint_sha": "0000000000000000000000000000000000000000",
  "final_checkpoint_sha": "0000000000000000000000000000000000000000",
  "milestones": [
    {
      "milestone_id": "A-015",
      "candidate_sha": "0000000000000000000000000000000000000000",
      "evidence_sha": "0000000000000000000000000000000000000000",
      "acceptance_sha": "0000000000000000000000000000000000000000",
      "accepted_checkpoint_sha": "0000000000000000000000000000000000000000",
      "result": "PASS"
    }
  ],
  "t3_result": {
    "tier": "T3",
    "required": true,
    "applicability_reason": "Required by approved risk policy",
    "checks": [
      "SYNTHETIC check; replace with approved command"
    ],
    "result": "PASS",
    "evidence": [
      {
        "evidence_id": "EVID-001",
        "candidate_sha": "0000000000000000000000000000000000000000",
        "reference": "SYNTHETIC evidence; replace with actual record"
      }
    ]
  },
  "stop_gate_result": {
    "stop_gate": "A-030",
    "reached": false
  },
  "next_action": "PAUSE"
}
```
