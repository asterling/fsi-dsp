# Phase 8: CFK on OpenShift - Research

**Researched:** 2026-03-27
**Domain:** Confluent for Kubernetes (CFK) operator on OpenShift, MirrorMaker 2 DR, Flink Kubernetes Operator
**Confidence:** MEDIUM-HIGH

## Summary

Phase 8 delivers a self-contained CFK-on-OpenShift scenario directory that provides governance parity with existing Confluent Cloud scenarios, integrates MirrorMaker 2 into the existing `fsi-dr` CLI backend dispatch, and deploys Flink Kubernetes Operator alongside CFK for stream processing parity. This is the first non-Terraform, non-CC scenario in the platform, so it establishes the pattern for Helm/YAML-based deployment models.

CFK 3.2 is the current operator version, supporting Confluent Platform 7.4.x-8.2.x on OpenShift 4.14-4.21. It provides CRDs for Kafka, SchemaRegistry, Connect, KafkaTopic, and Connector resources. MirrorMaker 2 runs as Connector CRDs on a Connect cluster (MirrorSourceConnector, MirrorCheckpointConnector, MirrorHeartbeatConnector) -- CFK does not have a dedicated KafkaMirrorMaker2 CRD like Strimzi. The Flink Kubernetes Operator 1.14.0 is the latest release, supporting FlinkDeployment CRDs with native Prometheus metrics and Avro-Confluent format connector for Schema Registry integration.

**Primary recommendation:** Structure the scenario as Helm values files for CFK operator + separate Flink Operator Helm install, with KafkaTopic/Connector CRDs for governance and MM2 replication, CI validation extending existing Python/shell validators to parse YAML/Helm values.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** CFK scenario uses Helm values files to configure the CFK operator. Infrastructure defined as values overrides, not raw YAML manifests.
- **D-02:** CFK operator installation documented with two paths: OLM (OperatorHub) as primary for standard OpenShift, Helm chart as alternative for air-gapped or restricted environments. Manifests work with either.
- **D-03:** Scenario directory at `scenarios/cfk-openshift/` following existing pattern. Internal structure is Claude's discretion.
- **D-04:** Topic governance parity via CI validation + Helm: Helm values define KafkaTopic CRDs with SLA-tier mappings, CI pipeline validates naming/SLA/schema parity before merge (reusing existing Python validators from Phase 1).
- **D-05:** MM2 uses default prefix-based topic naming (e.g., `east.corebanking.core.v1.account-transaction`). Consumers on DR cluster read from prefixed topics.
- **D-06:** MM2 failover sequence: stop MM2 connectors + flip Consul to DR. DR topics are already writable (no mirror promotion needed). Matches the spirit of the existing 6-step process.
- **D-07:** MM2 deployed via dedicated KafkaMirrorMaker2 CRD (CFK operator), not as connectors inside the Connect cluster. Independent lifecycle and dedicated resources.
- **D-08:** MM2 mirror lag monitoring approach is Claude's discretion. Must integrate with existing `fsi-dr status` command pattern and use the same SLA-tier thresholds from ADR-008.
- **D-09:** Flink Kubernetes Operator bundled in the CFK scenario directory as a separate Helm values file. Single scenario = complete platform (Kafka + SR + Connect + MM2 + Flink).
- **D-10:** Scenario includes example FlinkDeployment CRDs that match Phase 6 SQL templates (tumbling window, stream-table join, filter-route) with Avro format connector pointing to CFK Schema Registry.
- **D-11:** Flink job metrics exported via JMX exporter sidecar on Flink pods. Matches the JMX exporter stubs already in `observability/` directories from Phase 5.
- **D-12:** CFK scenario uses mTLS (certificates) for Kafka broker authentication. CFK operator manages cert generation via cert-manager integration.
- **D-13:** cert-manager is a documented prerequisite, not bundled in the scenario.
- **D-14:** RBAC authorization documented with two paths: Kafka ACLs as default (simpler, no MDS dependency), MDS (Confluent RBAC) as advanced option. README covers both.
- **D-15:** Governance parity for producer/consumer access control via ACL templates in Helm values. Templates map to the same producer=DeveloperWrite / consumer=DeveloperRead pattern from CC scenarios. CI validates ACL parity.

### Claude's Discretion
- Scenario directory internal structure (Helm chart organization, namespace layout)
- MM2 mirror lag data collection method (JMX via kubectl exec vs Prometheus endpoint vs other)
- MM2 failback sequence details (reverse of failover with appropriate modifications)
- FlinkDeployment CRD structure and Avro format connector configuration details
- How CI validators are extended to cover CFK YAML/Helm in addition to Terraform
- Whether to create a shared CFK topic template or inline topic definitions in values
- Consumer offset handling during MM2 failover (sync strategy)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IAC-03 | Operator can deploy CFK on OpenShift with Helm/operator manifests (KafkaCluster, SchemaRegistry, Connect, KafkaTopic CRDs) | CFK 3.2 Helm chart, KafkaTopic CRD spec, Connect CRD, mTLS auth, ACL authorization, SLA-tier topic config mappings |
| DR-05 | MirrorMaker 2 adapter handles CFK/CP failover/failback with topic replication | MM2 as Connector CRDs on Connect cluster, backend dispatch in fsi-dr.sh, MM2-specific failover/failback sequences, mirror lag via MM2 metrics |
| FLINK-02 | CFK Flink deployed via Flink Kubernetes Operator Helm chart on OpenShift | Flink K8s Operator 1.14.0 Helm chart, FlinkDeployment CRD, avro-confluent format connector, Prometheus metrics reporter, JMX sidecar pattern |
</phase_requirements>

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| CFK Operator | 3.2.x | Deploy/manage Confluent Platform on K8s/OpenShift | Official Confluent operator, supports OCP 4.14-4.21, CP 7.4.x-8.2.x |
| Confluent Platform | 7.6.x | Kafka, SR, Connect, ksqlDB runtime | Matches existing project Kafka 7.6.0 baseline |
| Flink Kubernetes Operator | 1.14.0 | Deploy/manage Flink on K8s/OpenShift | Latest stable (2026-02-13), Blue/Green support, FlinkDeployment CRD |
| Apache Flink | 1.20.x | Stream processing runtime | Compatible with Flink K8s Operator 1.14.0, latest stable Flink |
| cert-manager | 1.x | TLS certificate lifecycle management | Standard K8s cert management, CFK prerequisite for mTLS |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Helm | 3.x | Package management for CFK and Flink operators | All deployments |
| Prometheus JMX Exporter | 0.20.x | JMX metrics to Prometheus format | CFK broker and Flink pod metrics |
| flink-avro-confluent-registry | (bundled with Flink 1.20) | Avro format with SR integration | FlinkDeployment CRDs reading/writing Avro topics |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CFK Operator | Strimzi Operator | Strimzi has dedicated KafkaMirrorMaker2 CRD, but lacks Confluent Platform features (Schema Registry subject configs, RBAC bindings). CFK is the Confluent-supported path. |
| Flink K8s Operator | Confluent-managed Flink (CC only) | CC Flink auto-discovers SR subjects; CFK Flink requires explicit CREATE TABLE with avro-confluent format. K8s Operator is the only path for on-prem. |
| ACLs | MDS/Confluent RBAC | MDS requires LDAP/AD backend + MDS service deployment. ACLs are simpler for initial deployment. MDS documented as upgrade path per D-14. |

**Installation (CFK Operator):**
```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
helm upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --namespace confluent --create-namespace
```

**Installation (Flink Kubernetes Operator):**
```bash
helm repo add flink-kubernetes-operator-1.14.0 \
  https://archive.apache.org/dist/flink/flink-kubernetes-operator-1.14.0/
helm install flink-kubernetes-operator \
  flink-kubernetes-operator-1.14.0/flink-kubernetes-operator \
  --namespace flink --create-namespace
```

## Architecture Patterns

### Recommended Scenario Directory Structure

```
scenarios/cfk-openshift/
  README.md                          # Quickstart, prerequisites, two install paths (OLM/Helm)
  values/
    kafka.yaml                       # Kafka CR Helm values (brokers, listeners, mTLS, JMX)
    schemaregistry.yaml              # SchemaRegistry CR values
    connect.yaml                     # Connect CR values (plugin list, worker config)
    controlcenter.yaml               # ControlCenter CR (optional, for UI)
    kafka-rest-class.yaml            # KafkaRestClass for topic management
  topics/
    corebanking-account-txn.yaml     # KafkaTopic CRD for reference topic 1
    fraud-alert-signal.yaml          # KafkaTopic CRD for reference topic 2
    compliance-screening-result.yaml # KafkaTopic CRD for reference topic 3
  acls/
    acl-templates.yaml               # ACL definitions for producer/consumer patterns
    acl-mds-alternative.yaml         # MDS RBAC configuration (documented alternative)
  mm2/
    mm2-source-connector.yaml        # Connector CRD: MirrorSourceConnector
    mm2-checkpoint-connector.yaml    # Connector CRD: MirrorCheckpointConnector
    mm2-heartbeat-connector.yaml     # Connector CRD: MirrorHeartbeatConnector
  flink/
    flink-operator-values.yaml       # Helm values for Flink K8s Operator
    flink-session-cluster.yaml       # FlinkDeployment (session mode) for SQL
    examples/
      tumbling-window.yaml           # FlinkDeployment: tumbling window aggregation
      stream-table-join.yaml         # FlinkDeployment: stream-table join enrichment
      filter-and-route.yaml          # FlinkDeployment: filter-and-route pattern
  observability/
    jmx-exporter-kafka.yaml          # JMX exporter ConfigMap for Kafka brokers
    jmx-exporter-flink.yaml          # JMX exporter ConfigMap for Flink pods
    pod-monitor-kafka.yaml           # PodMonitor for Prometheus scraping (Kafka)
    pod-monitor-flink.yaml           # PodMonitor for Prometheus scraping (Flink)
```

### Pattern 1: KafkaTopic CRD with SLA-Tier Governance

**What:** Map the existing Terraform topic module's SLA-tier defaults into KafkaTopic CRDs with equivalent configs.
**When to use:** Every topic definition in the CFK scenario.

```yaml
# Source: CFK docs - co-manage-topics.html
apiVersion: platform.confluent.io/v1beta1
kind: KafkaTopic
metadata:
  name: corebanking.transactions.v1.account-transaction
  namespace: confluent
  labels:
    fsi.sla-tier: critical
    fsi.domain: corebanking
    fsi.owner: cncb-team@fsi.org
    fsi.data-classification: confidential
spec:
  replicas: 3
  partitionCount: 12          # critical tier default from modules/topic
  kafkaClusterRef:
    name: kafka
  configs:
    cleanup.policy: "delete"
    retention.ms: "604800000"  # 7 days (critical tier default)
    # Compatibility mode is on Schema Registry side, not topic config
```

**Key mapping from Terraform topic module to KafkaTopic CRD:**

| Terraform Variable | KafkaTopic CRD Field | Notes |
|-------------------|---------------------|-------|
| `domain`, `application`, `schema_version`, `entity` | `metadata.name` (assembled) | Same `{domain}.{app}.{version}.{entity}` naming |
| `sla_tier` | `metadata.labels.fsi.sla-tier` + derived configs | Drives partitionCount, retention.ms |
| `partitions_override` | `spec.partitionCount` | Override or SLA-tier default |
| `retention_ms_override` | `spec.configs.retention.ms` | Override or SLA-tier default |
| `enable_dr_mirror` | N/A (separate MM2 connector topics pattern) | MM2 replicates all topics matching pattern |
| `owner`, `data_classification` | `metadata.labels` | K8s labels replace SR subject metadata |
| `schema_file` | Separate SchemaRegistry CR or kubectl registration | Not part of KafkaTopic CRD |

### Pattern 2: MM2 as Connector CRDs (per D-07)

**What:** Deploy MirrorMaker 2 as three Connector CRDs on the Connect cluster for independent lifecycle.

**IMPORTANT NOTE on D-07:** The user decision D-07 says "dedicated KafkaMirrorMaker2 CRD (CFK operator)." CFK does NOT have a dedicated KafkaMirrorMaker2 CRD (that is Strimzi-specific). CFK runs MM2 as Connector CRDs on a Connect cluster. The spirit of D-07 (independent lifecycle, dedicated resources) is achieved by deploying a dedicated Connect cluster for MM2 connectors, separate from the application Connect cluster.

```yaml
# MirrorSourceConnector -- replicates topics from East to West
apiVersion: platform.confluent.io/v1beta1
kind: Connector
metadata:
  name: mm2-source-east-west
  namespace: confluent
spec:
  class: org.apache.kafka.connect.mirror.MirrorSourceConnector
  taskMax: 4
  connectClusterRef:
    name: connect-mm2   # dedicated Connect cluster for MM2
  configs:
    source.cluster.alias: "east"
    target.cluster.alias: "west"
    source.cluster.bootstrap.servers: "kafka-east:9092"
    target.cluster.bootstrap.servers: "kafka-west:9092"
    topics: ".*"
    topics.exclude: ".*\\.internal,.*\\.replica,__.*"
    replication.factor: "3"
    sync.topic.configs.enabled: "true"
    sync.topic.acls.enabled: "true"
    # mTLS authentication
    source.cluster.security.protocol: "SSL"
    source.cluster.ssl.keystore.location: "/mnt/secrets/source/keystore.jks"
    source.cluster.ssl.keystore.password: "${file:/mnt/secrets/source/credentials:keystore.password}"
    source.cluster.ssl.truststore.location: "/mnt/secrets/source/truststore.jks"
    target.cluster.security.protocol: "SSL"
    target.cluster.ssl.keystore.location: "/mnt/secrets/target/keystore.jks"
    target.cluster.ssl.keystore.password: "${file:/mnt/secrets/target/credentials:keystore.password}"
    target.cluster.ssl.truststore.location: "/mnt/secrets/target/truststore.jks"
```

```yaml
# MirrorCheckpointConnector -- syncs consumer offsets for failover
apiVersion: platform.confluent.io/v1beta1
kind: Connector
metadata:
  name: mm2-checkpoint-east-west
  namespace: confluent
spec:
  class: org.apache.kafka.connect.mirror.MirrorCheckpointConnector
  taskMax: 1
  connectClusterRef:
    name: connect-mm2
  configs:
    source.cluster.alias: "east"
    target.cluster.alias: "west"
    source.cluster.bootstrap.servers: "kafka-east:9092"
    target.cluster.bootstrap.servers: "kafka-west:9092"
    emit.checkpoints.enabled: "true"
    emit.checkpoints.interval.seconds: "30"
    # mTLS config same as source connector
```

### Pattern 3: FlinkDeployment with Avro-Confluent Format

**What:** Deploy Flink SQL jobs that read/write Avro-serialized Kafka topics via CFK Schema Registry.
**When to use:** Each Flink example CRD (tumbling window, stream-table join, filter-route).

Unlike CC Flink which auto-discovers SR subjects as tables, CFK Flink requires explicit `CREATE TABLE` statements with the `avro-confluent` format connector.

```yaml
# Source: Flink K8s Operator docs + Flink avro-confluent docs
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: fsi-tumbling-window
  namespace: flink
spec:
  image: flink:1.20
  flinkVersion: v1_20
  serviceAccount: flink
  flinkConfiguration:
    taskmanager.numberOfTaskSlots: "2"
    # Prometheus metrics
    metrics.reporter.prom.factory.class: org.apache.flink.metrics.prometheus.PrometheusReporterFactory
    metrics.reporter.prom.port: "9249"
    # State backend for checkpointing
    state.backend: hashmap
    state.checkpoints.dir: file:///flink-data/checkpoints
  jobManager:
    resource:
      memory: "2048m"
      cpu: 1
  taskManager:
    resource:
      memory: "4096m"
      cpu: 2
  job:
    jarURI: local:///opt/flink/usrlib/fsi-flink-jobs.jar
    entryClass: org.fsi.flink.TumblingWindowAggregation
    parallelism: 2
    upgradeMode: savepoint
    state: running
  podTemplate:
    spec:
      containers:
        - name: flink-main-container
          # JMX exporter sidecar config mounted as ConfigMap
          volumeMounts:
            - name: jmx-exporter-config
              mountPath: /opt/jmx-exporter
      volumes:
        - name: jmx-exporter-config
          configMap:
            name: flink-jmx-exporter-config
```

**Flink SQL CREATE TABLE with avro-confluent format (embedded in job or SQL file):**
```sql
-- CFK Flink requires explicit CREATE TABLE (unlike CC Flink auto-discovery)
-- Source: nightlies.apache.org/flink/flink-docs-master/docs/connectors/table/formats/avro-confluent/
CREATE TABLE account_transaction (
  transaction_id STRING,
  account_number STRING,
  amount DECIMAL(15, 2),
  transaction_type STRING,
  `timestamp` TIMESTAMP(3),
  WATERMARK FOR `timestamp` AS `timestamp` - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'corebanking.transactions.v1.account-transaction',
  'properties.bootstrap.servers' = 'kafka.confluent.svc.cluster.local:9092',
  'value.format' = 'avro-confluent',
  'value.avro-confluent.url' = 'http://schemaregistry.confluent.svc.cluster.local:8081',
  'properties.security.protocol' = 'SSL',
  'properties.ssl.keystore.location' = '/opt/certs/keystore.jks',
  'properties.ssl.keystore.password' = '${KEYSTORE_PASSWORD}',
  'properties.ssl.truststore.location' = '/opt/certs/truststore.jks',
  'scan.startup.mode' = 'latest-offset'
);
```

### Pattern 4: CFK Kafka CR with mTLS + ACL Authorization

**What:** Kafka cluster CR with mTLS listener authentication and ACL authorization.

```yaml
# Source: docs.confluent.io/operator/current/co-authenticate-kafka.html
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: confluent
spec:
  replicas: 3
  image:
    application: confluentinc/cp-server:7.6.0
  dataVolumeCapacity: 100Gi
  listeners:
    internal:
      authentication:
        type: mtls
        principalMappingRules:
          - "RULE:.*CN[\\s]?=[\\s]?([a-zA-Z0-9.]*)?.*/$1/"
      tls:
        enabled: true
    external:
      authentication:
        type: mtls
      tls:
        enabled: true
  authorization:
    type: simple   # Kafka ACLs (D-14 default)
    superUsers:
      - User:kafka
      - User:connect
  tls:
    autoGeneratedCerts: true   # CFK auto-generates certs; or use cert-manager
  metrics:
    prometheus:
      rules:
        - pattern: "kafka.server<type=ReplicaManager, name=UnderReplicatedPartitions><>Value"
          name: kafka_server_under_replicated_partitions
          type: GAUGE
        - pattern: "kafka.server<type=BrokerTopicMetrics, name=MessagesInPerSec><>OneMinuteRate"
          name: kafka_server_messages_in_per_sec
          type: GAUGE
  configOverrides:
    server:
      - auto.create.topics.enable=false
      - default.replication.factor=3
      - min.insync.replicas=2
```

### Anti-Patterns to Avoid

- **Raw YAML manifests instead of Helm values:** D-01 locks Helm values as the configuration method. Raw manifests are harder to parameterize across environments.
- **Deploying MM2 connectors inside the application Connect cluster:** D-07 specifies independent lifecycle. Use a dedicated Connect cluster (or what CFK can provide) for MM2 to prevent MM2 restarts from disrupting application connectors.
- **Assuming CC Flink auto-discovery works with CFK:** CFK Flink does NOT auto-discover SR subjects. Every source/sink table needs an explicit `CREATE TABLE` with `avro-confluent` format.
- **Skipping ACL templates:** Without ACL parity, CFK topics would lack the producer/consumer access control that CC scenarios enforce via Confluent RBAC.
- **Using OLM for full customization:** OLM installation has limited configuration options. For production-grade configuration, Helm is the recommended path per Confluent docs. OLM is documented as the "easy entry" path.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Certificate management for mTLS | Custom cert generation scripts | cert-manager + CFK autoGeneratedCerts | CFK has built-in cert lifecycle; cert-manager handles rotation |
| JMX metric collection | Custom metric scrapers | CFK built-in JMX (ports 7203/7777/7778) + Prometheus JMX Exporter | CFK exposes metrics by default on port 7778 |
| Connector lifecycle management | kubectl + curl to Connect REST API | CFK Connector CRD with restartPolicy | Declarative, auto-reconciled, pause/restart via annotations |
| Flink metrics aggregation | Custom metric sidecar | Flink native PrometheusReporterFactory | Built-in reporter, just configure flinkConfiguration |
| Schema validation for CFK YAML | New validation framework | Extend existing c4e-precheck.py with YAML parsing | Maintains single validation tool, reuses naming/SLA regex patterns |
| Topic config derivation from SLA tier | Inline in each CRD | Python/shell template generator or shared values template | Prevents config drift between topic CRDs |

**Key insight:** CFK provides most infrastructure abstractions via CRDs. The main custom work is: (1) mapping SLA-tier governance to CFK CRD configs, (2) implementing MM2 backend functions in `fsi-dr.sh`, and (3) porting Flink SQL from CC auto-discovery to explicit CREATE TABLE statements.

## Common Pitfalls

### Pitfall 1: CFK Does NOT Have a KafkaMirrorMaker2 CRD
**What goes wrong:** Developer expects a Strimzi-like `KafkaMirrorMaker2` CRD in CFK and cannot find it.
**Why it happens:** Strimzi has a dedicated MM2 CRD; CFK uses Connector CRDs on a Connect cluster instead.
**How to avoid:** Deploy MM2 as three Connector CRDs (MirrorSourceConnector, MirrorCheckpointConnector, MirrorHeartbeatConnector) on a dedicated Connect cluster. D-07's intent (independent lifecycle) is achieved via a dedicated Connect cluster.
**Warning signs:** Looking for `kind: KafkaMirrorMaker2` in CFK docs and finding nothing.

### Pitfall 2: OpenShift SecurityContextConstraints (SCC) Blocking CFK Pods
**What goes wrong:** CFK pods fail to start because OpenShift's default SCC blocks the required security context.
**Why it happens:** OpenShift applies `restricted` SCC by default which may conflict with CFK container requirements.
**How to avoid:** Document SCC requirements in README prerequisites. CFK 3.2 supports OpenShift 4.14-4.21 but may need `anyuid` or custom SCC for specific components.
**Warning signs:** Pods in `CrashLoopBackOff` with permission denied errors in logs.

### Pitfall 3: MM2 Prefix-Based Topic Naming Breaks Consumers
**What goes wrong:** Consumers hardcoded to `corebanking.transactions.v1.account-transaction` cannot find the topic on DR because MM2 prefixes it as `east.corebanking.transactions.v1.account-transaction`.
**Why it happens:** D-05 locks prefix-based naming. Consumers must be aware of the prefix when reading from DR.
**How to avoid:** Document clearly that DR consumers read from prefixed topics. MirrorCheckpointConnector handles offset translation so consumers can resume from the correct position.
**Warning signs:** Consumer groups showing zero consumption on DR cluster after failover.

### Pitfall 4: CFK Topic Reconciliation vs External Modifications
**What goes wrong:** Topics modified via CLI or Control Center get reverted by CFK reconciliation loop.
**Why it happens:** CFK continuously reconciles KafkaTopic CRDs against the actual Kafka topic state.
**How to avoid:** All topic changes must go through the KafkaTopic CRD (GitOps workflow). Document this as a constraint in the README.
**Warning signs:** Topic configs reverting unexpectedly after manual changes.

### Pitfall 5: CC Flink SQL Templates Don't Work Directly with CFK Flink
**What goes wrong:** Copying CC Flink SQL templates verbatim fails because CFK Flink cannot auto-discover SR subjects as tables.
**Why it happens:** CC Flink has a built-in integration with Confluent Cloud Schema Registry. Open-source Flink requires explicit table definitions with `avro-confluent` format.
**How to avoid:** Port each CC SQL template to include `CREATE TABLE` statements with full connector configuration (bootstrap servers, SR URL, format, auth).
**Warning signs:** "Table not found" errors when running CC Flink SQL templates on CFK Flink.

### Pitfall 6: MM2 Mirror Lag Measurement Differs from Cluster Linking
**What goes wrong:** The `fsi-dr status` command returns incorrect or missing mirror lag data for MM2 backend.
**Why it happens:** Cluster Linking reports lag via `confluent kafka mirror list`. MM2 exposes lag through MirrorSourceConnector JMX metrics (`replication-latency-ms`) or Kafka consumer lag on internal topics.
**How to avoid:** MM2 backend's `mm2_get_mirror_lag` should query MM2 metrics via Connect REST API or kubectl exec to read JMX from MM2 pods. Use `source-record-poll-total` and replication latency metrics.
**Warning signs:** `fsi-dr status` showing blank or zero lag for all topics.

### Pitfall 7: Flink Avro-Confluent Connector Requires JARs Not in Default Flink Image
**What goes wrong:** FlinkDeployment fails with ClassNotFoundException for `org.apache.flink.avro.confluent.*`.
**Why it happens:** The `flink-avro-confluent-registry` dependency is not included in the base Flink Docker image. It must be added via custom image or init container.
**How to avoid:** Build a custom Flink Docker image that includes `flink-avro-confluent-registry` and `flink-sql-connector-kafka` JARs, or use an init container to download them.
**Warning signs:** ClassNotFoundException at job startup.

### Pitfall 8: OLM Installation Limits Custom Configuration
**What goes wrong:** Production team installs CFK via OLM (OperatorHub) and cannot configure advanced settings.
**Why it happens:** Per Confluent docs, "Configuration options are limited when installed via OperatorHub." Changes to ClusterServiceVersion are temporary.
**How to avoid:** D-02 documents both paths. README should clearly state that Helm is recommended for production deployments with custom configuration. OLM is the "easy entry" path for evaluation.
**Warning signs:** Helm values being ignored after OLM installation.

## Code Examples

### MM2 Backend Functions for fsi-dr.sh

The existing `fsi-dr.sh` has a stub at line 534 for the MM2 backend. These five functions must be implemented:

```bash
# Source: Pattern from existing cl_* functions in fsi-dr.sh

# mm2_preflight -- Verify MM2 connector health and DR cluster readiness
mm2_preflight() {
  # 1. Check Connect REST API for MM2 connectors
  # 2. Verify MirrorSourceConnector is RUNNING
  # 3. Verify DR cluster is reachable (kubectl exec to broker)
  # 4. Check MM2 replication latency via Connect REST API
  local connect_url="${FSI_CONNECT_URL}"
  local connectors
  connectors=$(curl -s "${connect_url}/connectors" | jq -r '.[]' | grep -i mirror)
  # Verify each connector is RUNNING
}

# mm2_failover_mirrors -- Stop MM2 connectors (DR topics already writable)
mm2_failover_mirrors() {
  # D-06: MM2 failover is simpler than Cluster Linking
  # 1. Pause MirrorSourceConnector (stop replication)
  # 2. Pause MirrorCheckpointConnector
  # 3. Pause MirrorHeartbeatConnector
  # NOTE: No mirror promotion needed -- DR topics are already writable
}

# mm2_failback_mirrors -- Reverse MM2 direction (DR -> Primary)
mm2_failback_mirrors() {
  # 1. Stop existing MM2 connectors
  # 2. Reconfigure MirrorSourceConnector with reversed source/target
  # 3. Start reversed MM2 connectors
  # 4. Wait for sync (mirror lag below tier threshold)
  # 5. Stop reversed connectors
  # 6. Reconfigure back to original direction
  # 7. Start original MM2 connectors
}

# mm2_get_mirror_lag -- Report per-topic replication lag
mm2_get_mirror_lag() {
  # Query MM2 MirrorSourceConnector metrics
  # Option A: Connect REST API -> connector status -> task metrics
  # Option B: kubectl exec into MM2 pod -> JMX query for replication-latency-ms
  # Option C: Read from __consumer_offsets lag on DR cluster
  # Return JSON: [{topic, lag_ms, tier, status}]
}

# mm2_get_mirror_status -- Report MM2 connector states
mm2_get_mirror_status() {
  # Query Connect REST API for all mirror-related connectors
  # Return: connector name, state, tasks running/failed
}
```

### CI Validator Extension for CFK YAML

```python
# Extend c4e-precheck.py to validate CFK KafkaTopic CRDs
# Source: Based on existing parse_tf_modules pattern

import yaml  # NOTE: PyYAML needed, or use json if YAML files also valid JSON

def parse_cfk_topics(scenario_dir):
    """Parse KafkaTopic YAML files for governance validation.

    Returns a list of dicts with extracted topic metadata.
    """
    topics = []
    topics_dir = os.path.join(scenario_dir, 'topics')
    if not os.path.isdir(topics_dir):
        return topics

    for filename in sorted(os.listdir(topics_dir)):
        if not filename.endswith(('.yaml', '.yml')):
            continue
        filepath = os.path.join(topics_dir, filename)
        with open(filepath) as f:
            doc = yaml.safe_load(f)

        if doc.get('kind') != 'KafkaTopic':
            continue

        name = doc['metadata']['name']
        labels = doc['metadata'].get('labels', {})
        spec = doc.get('spec', {})
        configs = spec.get('configs', {})

        topics.append({
            'name': name,
            'file': filename,
            'sla_tier': labels.get('fsi.sla-tier', ''),
            'domain': labels.get('fsi.domain', ''),
            'owner': labels.get('fsi.owner', ''),
            'data_classification': labels.get('fsi.data-classification', 'internal'),
            'partitions': spec.get('partitionCount'),
            'replicas': spec.get('replicas'),
            'retention_ms': configs.get('retention.ms'),
            'cleanup_policy': configs.get('cleanup.policy', 'delete'),
        })

    return topics
```

**NOTE on PyYAML dependency:** The existing CI pipeline uses only Python stdlib (no pip deps). For CFK YAML validation, there are two approaches:
1. Add PyYAML as the single CI dependency (cleanest for YAML parsing)
2. Parse only the subset of YAML that is also valid JSON (limited)
3. Use a simple YAML-to-dict parser for the limited subset used in KafkaTopic CRDs

Recommendation: Add PyYAML. CFK scenarios require YAML parsing; this is a necessary tool dependency for the validation pipeline.

### CFK JMX Metrics Configuration

CFK Kafka brokers expose metrics on three ports by default:

```yaml
# Built-in to CFK -- no additional configuration needed:
# Port 7203: JMX direct access
# Port 7777: Jolokia REST interface
# Port 7778: Prometheus JMX exporter (no auth)

# Custom Prometheus rules can be added to the Kafka CR:
spec:
  metrics:
    prometheus:
      rules:
        # Reuse patterns from observability/grafana/jmx-exporter-stub.yaml
        - pattern: "kafka.server<type=ReplicaManager, name=UnderReplicatedPartitions><>Value"
          name: kafka_server_under_replicated_partitions
          type: GAUGE
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CFK 2.x with ZooKeeper | CFK 3.2 with KRaft support | 2024-2025 | KRaft removes ZooKeeper dependency |
| Strimzi KafkaMirrorMaker2 CRD | CFK uses Connector CRDs for MM2 | N/A (different ecosystems) | CFK has no dedicated MM2 CRD |
| Flink K8s Operator 1.10 | Flink K8s Operator 1.14.0 | 2026-02-13 | Blue/Green deployments, FlinkStateSnapshot CRD |
| Manual connector management | CFK Connector CRD (since CFK 2.1) | 2022 | Declarative connector lifecycle |
| OLM-only for OpenShift | OLM + Helm both supported | CFK 3.x | Helm recommended for full customization |

**Deprecated/outdated:**
- CFK 1.x Operator (Confluent Operator, pre-CFK): Completely replaced by CFK 2.x/3.x with different CRD API
- Standalone MirrorMaker (1.0): Replaced by MirrorMaker 2 (connect-based)
- ZooKeeper mode for CFK Kafka: KRaft mode preferred for new deployments

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Shell (bash) + Python 3 |
| Config file | `ci/scripts/validate-schemas.py`, `ci/scripts/c4e-precheck.py`, `ci/scripts/check-overrides.sh` |
| Quick run command | `python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cfk-openshift/ --schemas-dir schemas/ --verbose` |
| Full suite command | `python3 ci/scripts/validate-schemas.py --schemas-dir schemas/ && python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cfk-openshift/ --schemas-dir schemas/ --verbose && bash ci/scripts/check-overrides.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IAC-03 | KafkaTopic CRDs have valid naming, SLA tier, partitions, retention | unit | `python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cfk-openshift/` | Needs extension (Wave 0) |
| IAC-03 | Kafka/SR/Connect CRs have valid Helm values | unit | `helm template scenarios/cfk-openshift/values/ --dry-run` (concept) | Wave 0 |
| DR-05 | MM2 backend functions pass unit tests | unit | `bash -c 'source scripts/fsi-dr.sh && mm2_preflight'` (with mocks) | Wave 0 |
| DR-05 | MM2 failover sequence matches 6-step process | unit | `FSI_DR_BACKEND=mm2 bash scripts/fsi-dr.sh failover --dry-run` | Wave 0 |
| FLINK-02 | FlinkDeployment CRDs are valid YAML with required fields | unit | `python3 ci/scripts/validate-flink-crds.py scenarios/cfk-openshift/flink/` | Wave 0 |
| FLINK-02 | Flink SQL CREATE TABLE has avro-confluent format | unit | Inline validation in Flink CRD checker | Wave 0 |

### Sampling Rate

- **Per task commit:** `python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cfk-openshift/ --verbose`
- **Per wave merge:** Full suite (schema + c4e-precheck + overrides + MM2 dry-run)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] Extend `c4e-precheck.py` to parse KafkaTopic YAML files (not just .tf modules)
- [ ] Add MM2 backend unit test stubs in existing DR test pattern
- [ ] FlinkDeployment CRD validator (new Python script or extension)
- [ ] PyYAML dependency for CI pipeline (if chosen over JSON-subset approach)
- [ ] `helm template --dry-run` validation step for CFK values files

## Open Questions

1. **MM2 Mirror Lag Collection Method**
   - What we know: MM2 exposes `replication-latency-ms` via JMX on MirrorSourceConnector tasks. CFK Connect pods expose JMX on port 7203.
   - What's unclear: Whether to use `kubectl exec` + JMX query, Connect REST API task metrics, or read from MM2 internal topics (`__consumer_offsets` lag).
   - Recommendation: Use Connect REST API (`GET /connectors/mm2-source/status`) for connector state and parse task-level metrics. For per-topic lag, query MM2's internal checkpoint topic (`mm2-offset-syncs.east.internal`). This avoids needing JMX access and works through the same Connect REST API already used by `fsi-dr.sh`.

2. **Consumer Offset Translation During MM2 Failover**
   - What we know: MirrorCheckpointConnector periodically emits translated offsets to `{source-alias}.checkpoints.internal` topic. Consumers can use `RemoteClusterUtils` to translate offsets.
   - What's unclear: Whether to automate offset translation in the failover script or document it as a manual consumer step.
   - Recommendation: Document in DR runbook. Automated translation requires consumer-side tooling that varies per application. The failover script should verify checkpoint connector was running (ensuring offsets are available for manual translation).

3. **CFK ACL Provisioning Mechanism**
   - What we know: CFK supports `authorization.type: simple` for ACLs. No dedicated ACL CRD exists in CFK.
   - What's unclear: ACLs must be created via `kafka-acls` CLI or admin API. How to declaratively manage ACLs in GitOps.
   - Recommendation: Create shell scripts or Helm hooks that apply ACLs via `kafka-acls` CLI on deployment. Template the ACL commands from topic definitions. CI validates that ACL templates cover all declared topics.

4. **Flink Job Deployment: JAR vs SQL Client Mode**
   - What we know: FlinkDeployment supports Application mode (with JAR) and Session mode (with FlinkSessionJob). CC Flink uses pure SQL statements.
   - What's unclear: Whether to build a custom Flink JAR with embedded SQL or use Flink SQL Client in session mode.
   - Recommendation: Use Application mode with a lightweight JAR wrapper that executes SQL from mounted ConfigMaps. This matches the FlinkDeployment CRD pattern and allows individual job lifecycle management. Each example (tumbling window, join, filter-route) is a separate FlinkDeployment.

## Sources

### Primary (HIGH confidence)
- [Confluent CFK docs - overview](https://docs.confluent.io/operator/current/overview.html) - CFK 3.2 version, supported components, K8s/OCP versions
- [Confluent CFK docs - plan](https://docs.confluent.io/operator/current/co-plan.html) - Prerequisites, resource requirements, OpenShift compatibility (4.14-4.21)
- [Confluent CFK docs - deploy](https://docs.confluent.io/operator/current/co-deploy-cfk.html) - Helm installation, OLM path, CRD management
- [Confluent CFK docs - topics](https://docs.confluent.io/operator/current/co-manage-topics.html) - KafkaTopic CRD spec, configs, kafkaClusterRef
- [Confluent CFK docs - connectors](https://docs.confluent.io/operator/current/co-manage-connectors.html) - Connector CRD spec, lifecycle management
- [Confluent CFK docs - monitoring](https://docs.confluent.io/operator/current/co-monitor-cp.html) - JMX ports 7203/7777/7778, Prometheus rules
- [Confluent CFK docs - Kafka auth](https://docs.confluent.io/operator/current/co-authenticate-kafka.html) - mTLS listener config, principal mapping
- [Confluent CFK docs - ACLs](https://docs.confluent.io/operator/current/co-simple-acls.html) - Simple ACL authorization type
- [Flink K8s Operator docs](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/) - FlinkDeployment CRD, metrics, Helm
- [Flink avro-confluent format](https://nightlies.apache.org/flink/flink-docs-master/docs/connectors/table/formats/avro-confluent/) - CREATE TABLE syntax, SR config, auth options
- [Flink K8s Operator 1.14.0 release](https://flink.apache.org/2026/02/15/apache-flink-kubernetes-operator-1.14.0-release-announcement/) - Latest version, Blue/Green support

### Secondary (MEDIUM confidence)
- [Flink K8s Operator GitHub - CRD overview](https://github.com/apache/flink-kubernetes-operator/blob/main/docs/content/docs/custom-resource/overview.md) - FlinkDeployment spec fields
- [Flink K8s Operator metrics docs](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-main/docs/operations/metrics-logging/) - Prometheus reporter config, PodMonitor
- [Confluent K8s examples](https://github.com/confluentinc/confluent-kubernetes-examples) - Referenced for practical CRD implementations

### Tertiary (LOW confidence)
- MM2 failover sequence specifics: Based on general MM2 operational knowledge and D-06 decision. The exact failover steps for CFK context need validation during implementation.
- ACL provisioning via Helm hooks: Not verified with official CFK docs. May need alternative approach if Helm hooks don't have kubectl access in the CFK context.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - CFK 3.2 and Flink K8s Operator 1.14.0 verified via official docs and release announcements
- Architecture: MEDIUM-HIGH - CRD structures verified, but MM2-as-Connector-CRD pattern needs practical validation (CFK has no MM2 example in docs)
- Pitfalls: MEDIUM - Based on official docs (SCC, OLM limitations, metrics ports) and domain knowledge (MM2 prefix naming, Flink SR integration)
- DR backend: MEDIUM - MM2 failover is simpler than CL (per D-06), but exact fsi-dr.sh integration patterns need testing
- Flink integration: MEDIUM - avro-confluent format verified, but FlinkDeployment + JMX sidecar + custom JAR packaging is a multi-step pattern

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (30 days -- CFK and Flink Operator are stable releases)
