# ADR-003: Consul for service discovery over DNS-only

**Status:** Accepted
**Date:** 2026-03-21
**Author:** Jeremy Hogan

## Context
During DR failover, applications and Connect workers need to resolve three endpoints: Kafka bootstrap, Schema Registry, and Oracle JDBC. The options are: hardcoded URLs with manual rotation, DNS CNAME with TTL-based failover, or Consul-based service discovery.

## Decision
HashiCorp Consul is the service discovery mechanism for all DR-sensitive endpoints. A single Consul KV key (`fsi/kafka/active-region`) determines which region's endpoints are active. Kafka bootstrap, Schema Registry, and Oracle JDBC URLs are all resolved through Consul DNS or KV lookups.

**Rationale:**
- Single KV update flips all three endpoints atomically (vs. changing 3 DNS records)
- Consul health checks can auto-detect Oracle failover completion
- Consul integrates with HashiCorp Vault for credential rotation (already in FSI stack post-IBM acquisition)
- DNS TTL caching causes stale resolution; Consul DNS has configurable TTL down to 0
- The service discovery POC is already an approved Phase 2 deliverable

## Consequences
- Consul becomes a dependency for DR failover (must be HA itself)
- Connect workers and apps must resolve endpoints via Consul DNS (config change)
- Adds operational surface: Consul cluster health must be monitored
- Simplifies failover runbook from 17 steps to 6
- Same mechanism works for Oracle, Neo4j, and any future database endpoints
