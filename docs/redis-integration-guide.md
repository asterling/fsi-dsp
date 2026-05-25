# Redis Integration Guide

One supported path: **Kafka → Redis sink** via the Confluent Redis Sink
Connector. Redis is treated as a hot cache, not a source of truth — the
platform does not ship a Redis source connector. See
[ADR-012](adr/012-database-connector-patterns.md).

| Path | Source cluster | Mechanism | Latency | Operational model |
|---|---|---|---|---|
| **Kafka → Redis** | CC / CP / CFK / LinuxONE | `RedisSinkConnector` | sub-second to seconds | CC-managed *or* self-managed |

Connector class: `io.confluent.connect.redis.RedisSinkConnector`

---

## What it does

Reads a Kafka topic and writes each record into Redis as a key / value
pair. The Kafka record key becomes the Redis key (with optional prefix);
the record value becomes the Redis value. Supports `SET`, `HSET`, `SADD`,
`ZADD`, and `STREAM` write modes.

The canonical FSI pattern is **hot-cache rebuild from an event topic**:
core systems publish to a governed Kafka topic; the Redis cache that
member-facing apps query is rebuilt from that topic in near-real-time.

## When to use

- Member-facing apps need sub-millisecond reads of values that change
  via Kafka events (e.g., account balance, fraud-score lookup, OFAC
  sanctions hit cache).
- You want a deterministic rebuild path: replay the Kafka topic →
  recreate Redis state.
- You can tolerate eventual consistency between the Kafka topic and the
  Redis cache (typically sub-second).

## When NOT to use

- Redis as a source of truth — Redis state is ephemeral; the Kafka topic
  must be the source of record.
- Pub/sub fan-out — use Kafka consumer groups, not Redis pub/sub.

---

## CC-managed

```hcl
module "compliance_to_redis_cache" {
  source = "../../modules/db_connector"

  db_type           = "redis"
  direction         = "sink"
  source_topic_name = module.compliance_screening_result.topic_name
  target_db_url     = "rediss://redis-prod.fsi.internal:6380"
  credentials_secret_ref = "secret/fsi/redis#password"
  sla_tier          = "best-effort"

  redis_key_prefix  = "compliance:screening:"
  redis_client_mode = "Standalone"

  environment_id                = local.infra.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}
```

## Self-managed (CP, CFK, LinuxONE)

JSON template: [`reference/connect-configs/redis-sink-example.json`](../reference/connect-configs/redis-sink-example.json)

Deploy via Ansible on CP / CP-on-RHEL-on-L1:

```bash
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/deploy-database-connectors.yml \
  --tags redis
```

Deploy as a `Connector` CR on CFK on OpenShift:

```bash
oc apply -f scenarios/cfk-openshift/connectors/redis-sink.yaml
```

---

## Key projection

The Kafka record key becomes the Redis key, optionally prefixed by
`redis.key.prefix`. For records where the Kafka key is not the desired
Redis key, use the `ExtractField$Key` SMT to project from a value field:

```json
"transforms": "extractKey",
"transforms.extractKey.type": "org.apache.kafka.connect.transforms.ExtractField$Value",
"transforms.extractKey.field": "member_id"
```

## TTL strategy by SLA tier

| Tier | Default TTL | Rationale |
|---|---|---|
| critical | none (persistent) | Hot cache for live trading / fraud paths |
| standard | 24h | Member profile lookups; rebuild daily from topic |
| best-effort | 1h | Compliance match results; cheap rebuild |
| compliance | none + AOF persistence | Regulatory replay requirement |

Set TTL via `redis.expiration.time` (seconds) on the connector.

## Authentication

The platform standard is **TLS + Redis ACL user/password** (not the
legacy `AUTH <password>` global). Store the ACL password in Vault:

```
secret/fsi/redis#password
secret/fsi/redis#username   # optional; default user often suffices
```

For LinuxONE deployments where Vault is unreachable from z/IRD, use the
JCEKS keystore — see `scenarios/cp-rhel-linuxone/group_vars/databases.yml`.

## Client mode: Standalone vs Cluster

- `Standalone` — single Redis instance (FSI default for cache use cases).
- `Cluster` — hash-slot-partitioned Redis Cluster. Set
  `redis.cluster.bootstrap.servers` instead of `redis.uri`. The connector
  handles slot redirection automatically.

## DLQ

Per-connector DLQ named `database.dlq.<connector-name>` (e.g.
`database.dlq.redis-compliance-screening`). Best-effort tier by default
(3 partitions, 7-day retention).

## Observability

Grafana dashboard:
[`observability/grafana/dashboard-redis-sink.json`](../observability/grafana/dashboard-redis-sink.json)

Panels: connector task state, Redis commands/sec per task, ACL auth
failures (a non-zero rate indicates credential rotation issues), write
latency p95, DLQ rate.

## Operational notes

- The Confluent Redis Sink Connector JAR is pure Java; runs on s390x
  without modification. Connect base image must be s390x for LinuxONE.
- Redis password rotation: rotating the ACL password requires either a
  connector restart (drops in-flight retries) or a Redis-side gradual
  rollout via `ACL SETUSER <user> >oldpw >newpw` (both passwords valid
  during transition).
- Do not enable Redis pub/sub on the same instance as the sink target —
  pub/sub commands consume CPU that competes with the connector's
  pipelined writes.
