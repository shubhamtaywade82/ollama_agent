# Runtime Kernel Risk Register

## High Risks

| ID | Risk | Impact | Mitigation | Owner |
|---|---|---|---|---|
| RK-001 | Replay determinism drift | invalid recovery outcomes | golden fixture replay checks in CI | runtime |
| RK-002 | Duplicate recovery execution | data corruption | exclusive recovery lease + terminal sealing | runtime |
| RK-003 | Path/ownership bypass | unauthorized mutation | realpath/inode + LPM deny-by-default guards | security |
| RK-004 | Escalation recursion | runaway cost/time | hard circuit breakers and escalation depth cap | llm |
| RK-005 | Feature-flag regression | production instability | kernel-off parity suite on every PR | integration |

## Medium Risks

| ID | Risk | Impact | Mitigation | Owner |
|---|---|---|---|---|
| RK-006 | Lock starvation under contention | throughput drops | lease tuning + contention tests | runtime |
| RK-007 | Blob growth from compensation snapshots | disk pressure | retention policy + reachability garbage collection | runtime |
| RK-008 | Topology invalidation over-broad scope | slow incremental runs | reverse dependency closure tests | topology |

## Monitoring Signals

- replay_mismatch_count
- duplicate_recovery_attempt_count
- ownership_denial_count
- escalation_breaker_trigger_count
- kernel_flag_off_regression_failures
