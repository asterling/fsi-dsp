# ADR-005: Cluster Linking over MRC for current RPO targets

**Status:** Accepted
**Date:** 2026-03-21
**Author:** Jeremy Hogan

## Context
FSI's DR targets are RTO 2-6 hours by tier and RPO ~2 hours (aspirationally lower). Two DR patterns are available: Cluster Linking (two separate CC clusters, async replication, manual failover) and Multi-Region Clusters (single stretched cluster, sync replication, automatic failover, RPO=0). MRC with sync replication and observer promotion is a Confluent Platform feature, not available on Confluent Cloud.

## Decision
Use Cluster Linking between two Confluent Cloud dedicated clusters (East active, West passive DR). MRC with RPO=0 is documented as a future-state option requiring migration to Confluent Platform.

**Rationale:**
- FSI's ~2h RPO target is easily met by Cluster Linking (mirror lag is typically seconds)
- Cluster Linking is fully managed on CC with no infrastructure to operate
- MRC requires Confluent Platform (self-managed) which contradicts the CC adoption direction
- The Consul proxy pattern reduces Cluster Linking's manual failover to 6 scripted steps
- RTO bottleneck is Oracle DG (5-30 min), not Kafka failover

## Consequences
- RPO > 0 (bounded by mirror lag, typically seconds — well within the 2h target)
- Failover is not fully automatic (6 scripted steps vs. MRC's automatic promotion)
- If RPO requirements tighten to zero, architecture must change to CP + MRC
- Two separate clusters incur separate CC billing (mitigated by DR cluster being idle)
