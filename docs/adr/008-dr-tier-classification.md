# ADR-008: DR Tier Classification

**Status:** Accepted
**Date:** 2026-03-21
**Author:** FSI C4E

## Context

The FSI Kafka Platform operates across multiple SLA tiers (critical, standard, best-effort, compliance). Each tier represents different business criticality and regulatory requirements. Disaster Recovery (DR) capabilities must be proportional to tier criticality:

- **Critical** topics (core banking transactions, fraud alerts) require near-zero data loss and rapid recovery
- **Standard** topics (internal events, batch feeds) tolerate moderate data loss and recovery time
- **Best-effort** topics (logs, metrics, dev/test data) tolerate significant data loss and recovery time
- **Compliance** topics (OFAC screening, AML alerts, CFT reporting) require zero data loss for regulatory audit trails

Different DR backends provide different RPO/RTO characteristics:
- **Cluster Linking** (CC): Asynchronous replication, RPO bounded by mirror lag (typically seconds), manual promotion
- **MirrorMaker 2** (CFK/CP): Asynchronous replication, similar RPO characteristics, more operational overhead
- **Multi-Region Clusters (MRC)** with observer promotion (CP): Synchronous replication, RPO=0, higher latency cost

The platform must define clear RPO/RTO targets per tier and map them to appropriate DR backends per deployment model.

## Decision

### RPO/RTO Targets by SLA Tier

| SLA Tier | RPO Target | RTO Target | DR Priority | Mirror Lag Alert |
|----------|-----------|-----------|-------------|------------------|
| critical | < 5 minutes | < 15 minutes | P1 -- immediate failover | Warn at 30s, alert at 60s |
| standard | < 2 hours | < 1 hour | P2 -- business hours failover | Warn at 5m, alert at 15m |
| best-effort | < 24 hours | < 4 hours | P3 -- next business day | Warn at 1h, alert at 4h |
| compliance | RPO = 0 (zero data loss) | < 15 minutes | P1 -- immediate failover | Warn at 10s, alert at 30s |

### DR Backend Selection by Deployment Model

| Deployment Model | DR Backend | RPO Achievable | Notes |
|------------------|-----------|----------------|-------|
| CC (any cloud) | Cluster Linking | seconds (async) | Bidirectional link, mirror topic promotion. See ADR-005. |
| CFK on OpenShift | MirrorMaker 2 | seconds (async) | MM2 connector-based replication, topic renaming configurable. |
| CP on RHEL | Cluster Linking or MRC | seconds (CL) or 0 (MRC) | MRC with observer promotion for compliance tier RPO=0. |

### Compliance Tier: RPO=0 Strategy

For compliance-tier topics requiring RPO=0:
- **CP on RHEL:** Use Multi-Region Clusters (MRC) with automatic observer promotion (2.5-cluster pattern). The observer replica in the DR region is synchronously replicated and can be promoted to leader with zero data loss.
- **CC (any cloud):** Cluster Linking provides near-zero RPO (bounded by mirror lag, typically <1s). True RPO=0 is not available on CC without MRC. Compliance topics on CC should use critical-tier DR with enhanced mirror lag monitoring (alert at 30s).
- **CFK on OpenShift:** Same as CC -- MM2 provides async replication. Compliance topics should use critical-tier DR with enhanced monitoring.

### Mirror Lag Monitoring Integration

Mirror lag thresholds defined above feed into the observability templates (Phase 5). The `fsi-dr` CLI (Phase 4) uses these thresholds for pre-failover health checks:
- If mirror lag exceeds alert threshold, `fsi-dr failover` warns the operator about potential data loss
- `fsi-dr failover --dry-run` reports current mirror lag per topic with tier-specific assessment

## Consequences

**Easier:**
- Clear SLA expectations for each topic tier
- Mirror lag alert thresholds are derived, not manually configured per topic
- DR backend selection is deterministic per deployment model
- Compliance teams have documented RPO=0 strategy for regulatory audits
- Failover priority ordering (P1 before P2 before P3) enables triage during multi-topic outages

**Harder:**
- Compliance tier RPO=0 on CC requires accepting near-zero (not absolute zero) -- may need regulatory approval
- MRC for compliance tier on CP adds latency to produce calls (synchronous replication)
- Different DR backends per deployment model means the `fsi-dr` CLI must abstract backend differences (see DR-03)
- Mirror lag alerting requires observability platform integration per provider (Phase 5)
- Teams must correctly classify their topics -- under-classification (standard instead of critical) risks inadequate DR

**References:**
- ADR-002: Compatibility by SLA tier (defines the tier enum)
- ADR-005: Cluster Linking over MRC for CC deployments (DR backend for CC)
- Phase 4: DR Automation Framework (implements `fsi-dr` CLI)
- Phase 5: Observability Templates (implements mirror lag dashboards and alerts)
