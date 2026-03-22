# ADR-004: Self-managed Connect on-prem over managed connectors

**Status:** Accepted
**Date:** 2026-03-21
**Author:** Jeremy Hogan

## Context
FSI's CNCB and OFAC applications use JDBC source and sink connectors to Oracle databases hosted on-premises. The options are: fully managed connectors on Confluent Cloud (via PrivateLink to on-prem Oracle) or self-managed Connect workers deployed on-prem next to Oracle.

## Decision
Self-managed Kafka Connect workers are deployed on-premises in FSI's data center, connecting to Confluent Cloud via PrivateLink.

**Rationale:**
- Co-location with Oracle minimizes JDBC latency (sub-ms vs. 5-20ms through PrivateLink)
- CNCB transaction throughput is sensitive to connector latency
- FSI already has an existing Connect deployment (Phase 2 scope: "Review self-managed connect platform")
- On-prem workers can use Consul for Oracle endpoint resolution during DR
- Managed connectors on CC do not support data contract rules execution

## Consequences
- FSI ops team manages Connect worker health, upgrades, and scaling
- Connect distributed properties must be maintained for both East and West bootstrap
- DR failover includes connector pause/resume steps (scripted)
- Connect worker JMX metrics must be exported to Dynatrace via OneAgent
