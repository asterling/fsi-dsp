# ADR-001: Avro as the default schema format

**Status:** Accepted
**Date:** 2026-03-21
**Author:** Jeremy Hogan

## Context
FSI needs a standard serialization format for all Kafka topics. The three options supported by Confluent Schema Registry are Avro, Protobuf, and JSON Schema. The choice affects message size, evolution semantics, tooling compatibility, and developer experience.

## Decision
Apache Avro is the default schema format for all new FSI topics. Protobuf is an acceptable alternative for teams with existing Protobuf infrastructure (requires C4E approval). JSON Schema is not permitted for production topics.

**Rationale:**
- Compact binary serialization reduces CC storage and network costs
- Strong typing with logical types (decimal, timestamp-millis, date) maps well to financial data
- FULL_TRANSITIVE compatibility is well-defined and enforced by SR
- First-class support across Confluent Connect, Flink SQL, and TableFlow
- Avro is the dominant format in FSI Kafka deployments (industry alignment)

## Consequences
- All teams must learn Avro schema authoring (mitigated by reference schemas in /schemas)
- Schema evolution must follow Avro compatibility rules (documented in schema-guide.md)
- Teams with existing Protobuf services need an adapter or approved exception
- Avro's lack of native RPC definition is irrelevant (Kafka is the transport, not gRPC)
