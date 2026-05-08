# Sprint Execution Map

## Sprint to Milestone Mapping

| Sprint | Milestone | Focus |
|---|---|---|
| 0 | foundation | DoR/DoD, ADR freeze, risk register, harness |
| 1 | M1 | storage and identity base |
| 2 | M1/M2 | M1 hardening + security/atomic boundary start |
| 3 | M2 | locks, fencing, reservation complete |
| 4 | M3 | saga lifecycle core |
| 5 | M3/M4 | recovery hardening + planner boundary start |
| 6 | M4 | escalation + re-entry complete |
| 7 | M5 | topology compiler |
| 8 | M6 | synthesis + runtime bridge |
| 9 | release | stabilization and rollout |

## Quality Gates by Sprint

- S1-S3: deterministic replay + mutation safety
- S4-S5: recovery integrity + validator isolation
- S6: escalation breaker and post-state reconciliation
- S7-S8: compiler determinism + synthesis parity
- S9: regression burn-down and release sign-off
