# Domain Pitfalls

**Domain:** Multi-deployment FSI Kafka/Flink platform (Confluent Cloud, CFK on OpenShift, CP on RHEL, multi-provider observability, DR automation)
**Researched:** 2026-03-21
**Confidence:** MEDIUM (based on training data and codebase analysis; web verification unavailable)

---

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or production outages in FSI environments.

---

### Pitfall 1: MRC Observer Promotion Is Not Automatic -- It Requires ISR Convergence First

**What goes wrong:** Teams implement the MRC 2.5-cluster pattern (2 sync replicas + 1 async observer) expecting that observer promotion is a one-command operation. In reality, the observer must first be caught up to ISR (in-sync replica set) before it can be promoted. If the observer has fallen behind -- which is the default state for async observers -- promotion either fails or results in data loss equal to the observer lag. The Confluent CLI `confluent kafka replica list` shows observer lag, but automation scripts often skip this check.

**Why it happens:** The ADR-005 states "MRC with RPO=0 is documented as a future-state option requiring migration to Confluent Platform." Teams conflate MRC's synchronous replication between the two main replicas (which is RPO=0) with observer behavior (which is async by default). The observer is RPO=0 only if `observer.promotion.policy` is set to `under-min-isr` AND the observer is already in the ISR -- a state that depends on `replica.selector.class` configuration and network conditions between regions.

**Consequences:**
- Observer promotion during a regional outage may take minutes to hours if the observer needs to catch up, defeating the purpose of the 2.5-cluster pattern
- If promoted while out of ISR, the observer has stale data -- violating the RPO=0 guarantee that justified the MRC investment
- Flink jobs reading from promoted observer topics see offset gaps or duplicate records during the catch-up window
- Compliance audit finds RPO was not actually zero during the last DR event

**Prevention:**
- Monitor observer lag continuously with `confluent kafka replica list --topic <topic>` and alert when observer lag exceeds 100ms
- Configure `confluent.tier.local.hotset.ms` and `replica.selector.class=org.apache.kafka.common.replica.RackAwareReplicaSelector` to keep observer warm
- In the DR automation script, add a pre-promotion gate: poll observer ISR membership until caught up (with a configurable timeout and abort threshold)
- Run quarterly DR drills that measure actual observer promotion time, not just theoretical
- Document clearly: "MRC observer is RPO=0 only when the observer is in-sync. Under normal async mode, RPO equals observer replication lag."

**Detection:** Observer lag metric exceeding alerting threshold; observer not in ISR at promotion time; DR drill revealing minutes of data loss

**Phase mapping:** DR Framework phase -- must be addressed when implementing MRC backend adapter

---

### Pitfall 2: CFK on OpenShift SecurityContextConstraint (SCC) Conflicts

**What goes wrong:** CFK (Confluent for Kubernetes) operator pods and Confluent component pods (Kafka, ZooKeeper/KRaft, Schema Registry, Connect, ksqlDB) ship with specific `securityContext` settings (runAsUser, fsGroup, capabilities) that conflict with OpenShift's default `restricted` SCC. Pods go into CrashLoopBackOff or fail to mount persistent volumes because OpenShift rejects the security context. Teams spend days debugging pod scheduling failures that are actually SCC policy violations.

**Why it happens:** CFK Helm charts are designed for vanilla Kubernetes. OpenShift enforces SCCs that restrict arbitrary UID/GID, privilege escalation, and volume mount permissions. The CFK documentation mentions OpenShift compatibility but the default chart values assume `restricted-v2` SCC or a custom SCC, which must be explicitly created and bound to the service accounts before deployment.

**Consequences:**
- Kafka broker pods fail to start, blocking the entire cluster deployment
- PersistentVolumeClaims mount with wrong ownership, causing data directory permission errors (`/var/lib/kafka/data` not writable)
- Repeated pod restarts trigger PodDisruptionBudget violations, potentially cascading to other workloads in the OCP cluster
- Security team rejects the deployment if the workaround is "just use `privileged` SCC"

**Prevention:**
- Create a dedicated SCC (`confluent-scc`) that allows the specific UID ranges CFK components need (typically 1000-1001 for Kafka, 1000 for ZooKeeper)
- Bind the SCC to CFK service accounts before installing the operator: `oc adm policy add-scc-to-user confluent-scc -z <service-account> -n confluent`
- In CFK Helm values, set `podSecurityContext` and `containerSecurityContext` to match the custom SCC
- Test CFK installation on a non-production OCP cluster first -- SCC errors only manifest at pod creation time, not at Helm install time
- Pin CFK operator version and test OCP version compatibility matrix (CFK 2.x supports OCP 4.10+, but SCC behavior changed in OCP 4.11+ with Pod Security Admission)

**Detection:** Pods in `CrashLoopBackOff` or `CreateContainerConfigError`; `oc describe pod` shows `unable to validate against any security context constraint`; PVC bound but data directory empty

**Phase mapping:** CFK on OpenShift scenario phase -- first thing to address before any component deployment

---

### Pitfall 3: Terraform State Divergence Across Multi-Cloud Scenarios

**What goes wrong:** The existing codebase uses a single `azurerm` backend for Terraform state. When extending to AWS and GCP scenarios, each cloud requires its own backend (S3, GCS). Teams attempt to share the topic module across clouds but end up with Terraform state that references resources from the wrong provider, or worse, `terraform destroy` in one scenario affects state referenced by another. The `environments/prod/main.tf` hardcodes `backend "azurerm"`, meaning switching to AWS requires changing the backend block -- which Terraform treats as a state migration.

**Why it happens:** Terraform backends are declared statically in the `terraform {}` block. You cannot parameterize them with variables. The common "solution" is to use `-backend-config` partial configuration files, but this still requires a single backend type per root module. The project structure uses one `environments/prod/` directory for everything, creating a single state file that mixes cloud-agnostic resources (Confluent topics) with cloud-specific resources (backend, networking, secrets).

**Consequences:**
- Running `terraform init` against a different backend requires `terraform init -migrate-state`, which can corrupt state if done incorrectly
- A topic module that works on Azure fails on AWS because the state file contains Azure-specific resource references
- Teams in different clouds step on each other's state because they share the same state key path
- DR failover automation that runs Terraform plan/apply may target the wrong cloud's state file
- CI/CD pipelines need separate workspace configurations per cloud, but the GitHub Actions workflow only handles one backend

**Prevention:**
- Separate root modules per deployment scenario: `scenarios/cc-aws/`, `scenarios/cc-azure/`, `scenarios/cc-gcp/`, `scenarios/cfk-ocp/`, `scenarios/cp-rhel/`
- Each scenario has its own `backend.tf` with the appropriate backend type
- Shared modules (`modules/topic/`, `modules/schema/`, `modules/rbac/`) are cloud-agnostic and consumed by each scenario
- Use Terraform workspaces only within a single cloud (e.g., `dev`/`staging`/`prod` within `scenarios/cc-azure/`), never across clouds
- CI/CD pipeline matrix: one pipeline per scenario with its own backend config, not one pipeline that switches backends
- Add a `terraform validate` step that checks no cloud-specific resources leak into shared modules

**Detection:** `terraform plan` shows unexpected changes to resources in the wrong cloud; state file size grows unexpectedly; `terraform state list` shows resources from multiple providers

**Phase mapping:** Multi-cloud IaC phase -- foundational directory structure decision that affects everything downstream

---

### Pitfall 4: Flink Exactly-Once Semantics Require Transactional Kafka Cluster Configuration

**What goes wrong:** Teams deploy Flink jobs with `exactly-once` sink semantics expecting zero duplicates, but the Kafka cluster (or Confluent Cloud environment) is not configured to support Kafka transactions. Flink's `KafkaSink` with `DeliveryGuarantee.EXACTLY_ONCE` requires transaction-capable brokers, adequate `transaction.max.timeout.ms`, and the Flink job's transaction timeout must be less than the broker's max. On Confluent Cloud, the default `transaction.max.timeout.ms` is 900000ms (15 min), but Flink checkpoints that take longer than this window cause transaction timeouts, duplicate records on recovery, and stuck consumers (reads are blocked by open transactions until `transaction.timeout.ms` expires).

**Why it happens:** Exactly-once in Flink-to-Kafka is implemented via Kafka transactions. Each Flink checkpoint commits a transaction. If checkpointing is slow (large state, slow state backend, network issues), the transaction stays open. Other consumers reading from the output topic with `isolation.level=read_committed` are blocked until the transaction commits or times out. The default Flink checkpoint interval (once per minute) combined with large state can easily exceed timeout windows.

**Consequences:**
- End-to-end latency spikes to minutes during checkpointing, unacceptable for FSI real-time fraud detection
- Transaction timeout causes Flink job restart, producing duplicates on the output topic despite "exactly-once" configuration
- Downstream consumers blocked by open transactions see apparent data loss (records exist but are invisible until committed)
- In CC dedicated clusters, excessive open transactions can hit `max.transactions.per.partition` limits, causing producer errors

**Prevention:**
- Set Flink's `KafkaSink` transaction timeout to be significantly less than the broker's `transaction.max.timeout.ms` (e.g., Flink at 600000ms when broker allows 900000ms)
- Tune Flink checkpoint interval and timeout: `execution.checkpointing.interval: 60s`, `execution.checkpointing.timeout: 300s`
- Use incremental checkpointing with RocksDB state backend for stateful jobs to reduce checkpoint duration
- For latency-sensitive FSI jobs (fraud scoring), consider `at-least-once` with idempotent sinks rather than exactly-once transactions
- Monitor `currentCheckpointDuration` and `numberOfFailedCheckpoints` metrics -- alert if checkpoint duration exceeds 50% of transaction timeout
- Document the tradeoff matrix: exactly-once adds latency; at-least-once with idempotent writes is often better for FSI real-time use cases

**Detection:** Flink job metrics show increasing checkpoint duration; consumer lag spikes correlated with Flink checkpoint cycles; `TransactionTimeoutException` in Flink TaskManager logs

**Phase mapping:** Flink Runtime phase -- must be addressed in Flink SQL reference templates and operational runbooks

---

### Pitfall 5: Consul Becomes a Single Point of Failure for DR Failover

**What goes wrong:** ADR-003 chose Consul as the service discovery mechanism for DR failover (Kafka bootstrap, Schema Registry, Oracle JDBC all resolved through Consul). During an actual regional outage, if Consul itself is affected -- or if the Consul cluster is deployed only in the primary region -- the DR failover mechanism is unavailable precisely when it is needed most. The `consul-flip-region.sh` script connects to `CONSUL_HTTP_ADDR` which defaults to `localhost:8500`, implying a local Consul agent.

**Why it happens:** Consul is treated as infrastructure plumbing and deployed "somewhere" without the same HA rigor applied to the Kafka clusters themselves. The Consul cluster uses Raft consensus (typically 3 or 5 servers), but if all servers are in the primary region, a regional outage takes down Consul and Kafka simultaneously. Even with multi-DC Consul, WAN gossip between datacenters can fail during the exact network partitions that trigger DR.

**Consequences:**
- Regional outage takes down both Kafka and the mechanism to fail over from Kafka
- DR scripts fail at `consul kv put` with connection timeout, leaving operators stuck
- Manual DNS editing becomes the emergency fallback, but nobody has practiced it
- RTO extends by the time it takes to realize Consul is down and pivot to manual failover
- Connect workers that resolve bootstrap via Consul DNS lose their Kafka connection AND their ability to discover the DR cluster

**Prevention:**
- Deploy Consul in a multi-DC configuration with server nodes in BOTH primary and DR regions (minimum 3 servers per DC)
- The DR automation script must have a Consul fallback: if `consul kv put` fails after 3 retries, fall back to direct endpoint update (hardcoded DR endpoints or environment variables)
- Test DR failover with Consul intentionally unavailable -- the "break glass" path must not depend on Consul
- Add Consul health to the DR readiness dashboard: if Consul is degraded, DR readiness is degraded
- Consider a lightweight alternative for the critical path: a simple config file or environment variable that scripts can read without network dependency

**Detection:** `consul members` shows fewer servers than expected; WAN gossip between DCs shows unreachable nodes; DR readiness check includes Consul quorum health

**Phase mapping:** DR Framework phase -- must be addressed before the orchestrated failover CLI ships

---

### Pitfall 6: Multi-Provider Observability Template Drift and Alert Fatigue

**What goes wrong:** The project plans separate observability templates for 6+ providers (Dynatrace, Datadog, Splunk, New Relic, Instana, Prometheus/Grafana). Teams build templates in parallel, but each provider's dashboard shows different metrics, uses different alert thresholds, and interprets the same data differently. When an FSI customer deploys with Datadog, their "cluster health" dashboard shows different information than the Dynatrace version that was tested internally. Alert rules that make sense in one provider (Dynatrace's automatic baselining) do not translate to another (Prometheus static thresholds).

**Why it happens:** Each observability vendor has different metric naming conventions, aggregation methods, and alerting paradigms. The Confluent Cloud Metrics API returns metrics in a standard format, but each provider's ingestion pipeline transforms them differently. Dynatrace auto-discovers services; Datadog requires explicit metric submission; Prometheus scrapes endpoints. Writing "the same dashboard" in 6 providers is writing 6 different dashboards.

**Consequences:**
- Customer using Splunk reports their dashboard is missing metrics that the Dynatrace version shows
- Alert thresholds tuned for one provider generate false positives in another (different aggregation windows)
- Maintenance burden grows linearly with each new provider -- a metric name change requires 6 template updates
- FSI customers lose trust when the "golden path" observability doesn't work with their provider
- Alert fatigue from poorly-tuned thresholds causes real alerts to be ignored

**Prevention:**
- Define a canonical metric catalog first (provider-agnostic): list every metric, its meaning, threshold logic, and expected range
- Build templates from the catalog, not ad-hoc -- each template is a projection of the same source of truth
- Start with 2 providers maximum (Dynatrace + Prometheus/Grafana are the most common FSI choices), ship those well, then expand
- Use Terraform or config-as-code for dashboard definitions where possible (Datadog, Grafana, Dynatrace all support this)
- Implement a template validation test: deploy a test cluster, ingest known data, verify each provider template shows the expected values
- Pin alert thresholds to SLA tiers from the topic module: critical topics get tighter thresholds than best-effort, regardless of provider

**Detection:** Customer reports dashboard gaps; template diff between providers shows different metric sets; alert frequency varies wildly between providers for the same cluster

**Phase mapping:** Observability phase -- start with canonical metric catalog before writing any provider-specific template

---

## Moderate Pitfalls

Mistakes that cause significant rework, delayed delivery, or degraded operations.

---

### Pitfall 7: CFK Operator Upgrade Causes Rolling Restart of All Confluent Components

**What goes wrong:** Upgrading the CFK operator version (e.g., from 2.7 to 2.8) triggers a rolling restart of all managed Confluent components (Kafka, Schema Registry, Connect, ksqlDB) even if the component versions haven't changed. In an FSI production environment, an unexpected rolling restart of a Kafka cluster causes producer/consumer disconnections, consumer group rebalances, and potential data loss if producers don't handle retries correctly.

**Why it happens:** The CFK operator uses Kubernetes controller-runtime reconciliation. When the operator binary changes, it re-reconciles all managed CustomResources, which may result in StatefulSet spec changes (even cosmetic ones like annotation updates) that trigger pod restarts. This is standard Kubernetes operator behavior but catches teams off guard.

**Prevention:**
- Always upgrade the CFK operator in a maintenance window, never during business hours
- Test operator upgrades in a staging OCP cluster with the same CR definitions before production
- Use `kubectl diff` to preview what the new operator version will change before applying
- Configure PodDisruptionBudgets (PDBs) on Kafka StatefulSets to limit concurrent restarts to 1 broker at a time
- Pin the CFK operator version in Helm values and upgrade deliberately, not via "latest" tag

**Detection:** Unexpected pod restarts visible in `kubectl get events`; consumer group rebalance storm in broker logs; producer retry spikes in metrics

**Phase mapping:** CFK on OpenShift scenario phase -- document in upgrade runbook

---

### Pitfall 8: Flink Job State Incompatibility After Schema Evolution

**What goes wrong:** A Flink SQL job reads from a Kafka topic using an Avro schema. When the schema evolves (new field added), the Flink job's internal state (keyed state, window state) was serialized with the old schema. Restarting the Flink job from a savepoint fails because the state serializer doesn't match the new schema. Teams are forced to discard state and restart from scratch, losing windowed aggregations and in-flight computations.

**Why it happens:** Flink serializes state using the schema in effect at checkpoint/savepoint time. Schema evolution in the Kafka source does not automatically evolve the Flink state serializer. Flink SQL jobs that use `CREATE TABLE` with an Avro schema embed that schema at job submission time. The Avro `BACKWARD_TRANSITIVE` compatibility in Schema Registry ensures consumers can read new data, but Flink's state serialization is a separate concern.

**Prevention:**
- Use Flink's state schema evolution support: declare state with Avro and enable `state.backend.rocksdb.enable-state-schema-evolution: true`
- For Flink SQL, use `LIKE` clause to version table definitions and implement explicit state migration
- When evolving schemas that Flink jobs consume, follow this sequence: (1) deploy new Flink job version that handles both old and new schema, (2) take savepoint, (3) stop old job, (4) start new job from savepoint
- Never add `NOT NULL` fields to schemas consumed by stateful Flink jobs -- always use optional fields with defaults
- Test schema evolution with savepoint compatibility in CI before deploying to production

**Detection:** Flink job fails to restore from savepoint with `StateMigrationException`; Flink TaskManager logs show `IncompatibleSchemaException`; job auto-restarts without state, producing incorrect windowed results

**Phase mapping:** Flink Runtime phase -- must be documented in Flink SQL reference templates

---

### Pitfall 9: Cluster Linking Mirror Topic Failover Promotes ALL Topics Atomically or None

**What goes wrong:** The existing `mirror-failover.sh` script promotes ALL active mirror topics on a cluster link in a single command. In practice, FSI teams may want to fail over only specific topics (e.g., CNCB topics but not OFAC topics) while keeping others mirrored. The `confluent kafka mirror failover` command accepts a list of topics, but the script uses a blanket `select(.status == "ACTIVE")` filter. Additionally, topic-level promotion is irreversible -- once promoted, a mirror topic becomes a regular topic and cannot be re-mirrored without `truncate-and-restore`.

**Why it happens:** The script was designed for a full-region failover scenario. Partial failover (some topics active in East, some in West) creates a split-brain topology that the current architecture doesn't handle -- Consul flips ALL endpoints, and Connect workers connect to a single cluster.

**Prevention:**
- Design the DR framework with topic-group granularity: topics are tagged by domain (CNCB, OFAC, RTFD) and failover can target a specific domain group
- Add a `--topics` flag to the orchestrated failover CLI that accepts a filter (domain prefix, SLA tier, or explicit list)
- Before promotion, validate that all downstream consumers and Connect jobs for the target topics are either paused or can handle the switch
- Document clearly: "Mirror topic promotion is irreversible. Test in DR drill before production failover."
- Implement a "partial failover" mode where Consul resolves different topics to different clusters (requires service mesh or topic-aware routing, which adds complexity)

**Detection:** Post-failover discovery that topics outside the intended scope were promoted; Connect jobs targeting non-failed-over topics lose their mirror source; failback requires full `truncate-and-restore` even for topics that didn't need failover

**Phase mapping:** DR Framework phase -- the pluggable DR abstraction must support topic-group granularity

---

### Pitfall 10: Terraform Provider Version Pinning Across Scenarios Creates Upgrade Deadlocks

**What goes wrong:** The Confluent Terraform provider (`confluentinc/confluent ~> 2.0`) is shared across all scenario directories. A new feature in the provider (e.g., Flink SQL pool support) requires upgrading to `2.5`, but the upgrade introduces a breaking change in the Schema Registry resource that breaks the existing CC-Azure scenario. Now neither scenario can be updated: the new scenario needs `2.5`, the old scenario can't handle it.

**Why it happens:** All scenarios share the same provider but have different resource usage patterns. Terraform doesn't support per-module provider version pinning -- the root module pins the version, and all modules consume it. The `~> 2.0` constraint in the existing codebase allows minor version upgrades, but Confluent's Terraform provider has historically introduced behavioral changes in minor versions.

**Prevention:**
- Pin exact provider versions per scenario (not `~> 2.0` but `= 2.4.0`) and upgrade deliberately
- Test provider upgrades against all scenarios in CI before merging -- add a matrix test that runs `terraform plan` for each scenario against the new provider version
- Maintain a CHANGELOG for provider version upgrades that documents which scenarios were tested
- If scenarios need different provider versions, accept that they are different root modules with independent version lifecycles
- Subscribe to the Confluent Terraform provider GitHub releases for breaking change notices

**Detection:** `terraform plan` on one scenario shows unexpected resource recreation after provider upgrade; CI pipeline fails for one scenario but passes for another after shared provider bump

**Phase mapping:** Multi-cloud IaC phase -- establish provider pinning policy before creating scenario directories

---

### Pitfall 11: Connect Offset Topic Mismatch After DR Failover Causes Duplicate Processing

**What goes wrong:** Kafka Connect stores its source connector offsets in the `connect-offsets` internal topic on the primary cluster. After DR failover to the West cluster, Connect workers restart and either (a) create a new `connect-offsets` topic on West with no history, causing source connectors to re-read from the beginning, or (b) find a mirrored `connect-offsets` topic that contains offsets from the old cluster's perspective, which may not map correctly to the DR cluster's topic partitions.

**Why it happens:** Connect's offset tracking is tied to the cluster it's running against. The offset topic is an internal topic that gets mirrored if you mirror all topics, but the offsets reference partition leadership and epoch numbers specific to the primary cluster. After failover, the promoted topics on West have different leader epochs. Source connectors that track database binlog positions may resume from a position that no longer exists on the failover DB.

**Prevention:**
- Explicitly configure whether `connect-offsets`, `connect-configs`, and `connect-status` internal topics are mirrored or excluded from cluster linking
- For source connectors (JDBC), document that after DR failover, source offsets must be manually validated against the DR database state
- Implement a Connect offset validation script that compares stored offsets to actual topic high watermarks post-failover
- Consider running Connect workers against the DR cluster in standby mode (paused connectors) so internal topics exist natively
- The DR framework should include a "Connect recovery" step after failover that validates or resets connector offsets

**Detection:** Source connectors re-process entire tables after failover (massive duplicate records); Connect workers throw `OffsetOutOfRangeException` or `InvalidEpochException`; database load spikes from connector re-reading

**Phase mapping:** DR Framework phase -- must be addressed in the pluggable DR backend for each deployment model

---

### Pitfall 12: OpenShift Route vs Ingress for Schema Registry and Connect REST APIs

**What goes wrong:** CFK deploys Schema Registry and Connect with Kubernetes Services, but external access (from CI/CD pipelines, developer tooling, Terraform running outside the cluster) requires either an OpenShift Route or an Ingress. Teams configure a Route for Schema Registry but forget that Schema Registry uses HTTP/2 for gRPC-based APIs in newer versions, and OpenShift Routes default to HTTP/1.1 with HAProxy. The Confluent Terraform provider connecting to SR through the Route gets intermittent `connection reset` errors.

**Why it happens:** OpenShift Routes use HAProxy by default, which handles HTTP/1.1 well but requires explicit annotation for HTTP/2 or WebSocket passthrough. Schema Registry's REST API is HTTP/1.1, but if mTLS is configured (common in FSI), the Route needs TLS passthrough (`route.openshift.io/termination: passthrough`), which means the Route cannot inspect or modify traffic -- including health checks.

**Prevention:**
- Use `passthrough` TLS termination for all Confluent component Routes (SR, Connect, MDS) when mTLS is required
- If external access is not needed, use ClusterIP services and run Terraform from within the cluster (via CI runner pod)
- Test Route configuration with `curl -v` to SR from outside the cluster before wiring Terraform or CI pipelines
- For Connect REST API, consider a dedicated Route with re-encrypt termination if mTLS is not required
- Document the Route configuration for each Confluent component in the CFK scenario README

**Detection:** Intermittent 503 errors from Routes; Terraform `confluent_schema` resource times out; `curl` to Schema Registry Route succeeds sometimes but fails under load

**Phase mapping:** CFK on OpenShift scenario phase -- address during initial CFK deployment

---

## Minor Pitfalls

Mistakes that cause delays or friction but are recoverable.

---

### Pitfall 13: Flink SQL Job Naming Collisions in Multi-Tenant Confluent Cloud

**What goes wrong:** Confluent Cloud Flink uses environment-scoped compute pools and statement names. If two teams submit Flink SQL statements with the same name (e.g., `enrich-transactions`) in the same CC environment, the second submission silently overwrites the first or fails with a naming conflict. The current project plans shared CC environments per deployment scenario.

**Prevention:**
- Enforce Flink statement naming convention matching topic naming: `{domain}.{application}.{job-name}` (e.g., `cncb.core.enrich-transactions`)
- Add CI validation that Flink statement names follow the naming convention
- Consider separate Flink compute pools per domain to provide resource isolation and avoid naming collisions

**Detection:** Flink job list shows fewer jobs than expected; one team's job stops unexpectedly when another team deploys

**Phase mapping:** Flink Runtime phase -- address in Flink SQL reference templates

---

### Pitfall 14: Schema Registry Subject Cleanup Across Deployment Models

**What goes wrong:** In Confluent Cloud, Schema Registry is a managed service with one instance per environment. In CFK and CP deployments, Schema Registry is a separate cluster that must be deployed, scaled, and backed up. Teams that build schema registration in Terraform for CC discover that the same Terraform code doesn't work for CFK (different authentication, different REST endpoint format) or CP (basic auth vs. bearer token, potentially HTTPS with self-signed certs).

**Prevention:**
- Abstract Schema Registry access in the shared module: accept `sr_type` variable that configures authentication (api-key, basic-auth, bearer-token, mtls)
- Test schema module against all SR deployment types in CI (Docker SR for local, CC SR for cloud, CFK SR for operator)
- Document the SR endpoint format differences: CC uses `https://psrc-XXXXX.<region>.confluent.cloud`, CFK uses `https://schemaregistry.<namespace>.svc.cluster.local:8081`, CP uses `https://<hostname>:8081`

**Detection:** Terraform apply works on CC but fails on CFK with authentication errors; schema registration times out against CFK due to incorrect URL format

**Phase mapping:** Shared module library phase -- must abstract SR auth before creating per-scenario directories

---

### Pitfall 15: Ansible Playbook Idempotency for CP on RHEL

**What goes wrong:** The Confluent Platform on RHEL scenario uses Ansible for deployment. Teams write Ansible playbooks that configure brokers, ZooKeeper/KRaft, Schema Registry, and Connect. Non-idempotent tasks (restarting services, modifying config files with `lineinfile`) cause unintended service disruptions when playbooks are re-run. In FSI environments where change management requires documented runs, a non-idempotent playbook that restarts production brokers on re-run is a compliance violation.

**Prevention:**
- Use Confluent's official `cp-ansible` collection (maintained by Confluent) rather than writing custom playbooks
- For custom extensions, always use `notify`/`handler` patterns so services only restart when config actually changes
- Add `--check` (dry-run) mode to all playbooks and require it in change management approval workflows
- Test idempotency in CI: run the playbook twice and verify no changed tasks on the second run
- Use molecule for Ansible testing with a RHEL-based container image

**Detection:** Service restarts visible in `journalctl` after a playbook run that should have been a no-op; Ansible reports "changed" tasks on a repeat run; broker goes offline during a config-only update

**Phase mapping:** CP on RHEL scenario phase

---

### Pitfall 16: GitHub Actions Workflow Per-Scenario Branching Complexity

**What goes wrong:** The existing CI/CD (`terraform-plan.yml`, `terraform-apply.yml`) assumes a single Terraform root module. With 5+ scenario directories, the workflow must determine which scenario changed and run plan/apply only for that scenario. Teams implement this with path-based triggers (`paths: scenarios/cc-aws/**`) but forget that shared module changes (`modules/topic/**`) must trigger plan for ALL scenarios. The result is a shared module change that breaks one scenario but CI only validates the scenario whose files changed.

**Prevention:**
- Implement a workflow matrix that always runs `terraform validate` and `terraform plan` for ALL scenarios on any change to `modules/`
- Use path-based triggers for scenario-specific changes, but add a "shared module" trigger that runs the full matrix
- Pin Terraform version in CI to match what each scenario expects
- Add a `terraform fmt -check` step that runs across all scenarios to catch formatting drift

**Detection:** Shared module PR merges without testing all scenarios; one scenario breaks in production but CI was green because it only tested the modified scenario

**Phase mapping:** Multi-cloud IaC phase -- address when setting up per-scenario CI/CD

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation | Severity |
|-------------|---------------|------------|----------|
| Multi-cloud IaC structure | Terraform state divergence across clouds (Pitfall 3) | Separate root modules per scenario, never share state backends across clouds | Critical |
| Multi-cloud IaC structure | Provider version pinning deadlocks (Pitfall 10) | Exact version pins per scenario, matrix CI testing | Moderate |
| Multi-cloud IaC structure | CI/CD branching for shared modules (Pitfall 16) | Full matrix validation on shared module changes | Minor |
| CFK on OpenShift | SCC conflicts (Pitfall 2) | Dedicated SCC bound to CFK service accounts before operator install | Critical |
| CFK on OpenShift | Operator upgrade rolling restarts (Pitfall 7) | Maintenance windows, PDBs, staging cluster testing | Moderate |
| CFK on OpenShift | Route/Ingress configuration for SR and Connect (Pitfall 12) | Passthrough TLS termination, test with external curl | Moderate |
| Flink Runtime | Exactly-once transaction timeouts (Pitfall 4) | Tune checkpoint interval relative to transaction timeout, prefer idempotent at-least-once for real-time jobs | Critical |
| Flink Runtime | State incompatibility on schema evolution (Pitfall 8) | Avro state evolution support, optional-only field additions, savepoint compatibility testing | Moderate |
| Flink Runtime | SQL job naming collisions (Pitfall 13) | Domain-prefixed naming convention enforcement | Minor |
| DR Framework | MRC observer promotion ISR requirement (Pitfall 1) | Pre-promotion ISR validation gate, observer lag monitoring | Critical |
| DR Framework | Consul SPOF during regional outage (Pitfall 5) | Multi-DC Consul, break-glass fallback without Consul | Critical |
| DR Framework | All-or-nothing mirror topic failover (Pitfall 9) | Topic-group granularity in failover CLI | Moderate |
| DR Framework | Connect offset mismatch after failover (Pitfall 11) | Offset validation script, standby Connect workers in DR | Moderate |
| Observability | Template drift across providers (Pitfall 6) | Canonical metric catalog first, start with 2 providers | Critical |
| Shared Modules | Schema Registry auth abstraction across deployment models (Pitfall 14) | Parameterized SR type in shared module | Minor |
| CP on RHEL | Ansible idempotency failures (Pitfall 15) | Use cp-ansible, handler patterns, molecule testing | Minor |

---

## Cross-Cutting Concerns (from CONCERNS.md Already Identified)

The following concerns from `.planning/codebase/CONCERNS.md` intersect with pitfalls above and should be prioritized accordingly:

| Existing Concern | Related Pitfall | Priority Escalation |
|-----------------|----------------|---------------------|
| Manual DR Failover Risk | Pitfall 1 (MRC observer), Pitfall 5 (Consul SPOF), Pitfall 9 (all-or-nothing failover) | These pitfalls make the existing manual DR even riskier -- fix before production MRC deployment |
| Hardcoded Cluster IDs | Pitfall 3 (Terraform state divergence) | Multi-cloud makes this worse by 5x -- must centralize before adding scenarios |
| Service Account Credentials | Pitfall 2 (CFK SCC requires careful SA management), Pitfall 12 (Route auth) | Credential management complexity multiplies across deployment models |
| Missing Terraform Validation | Pitfall 10 (provider version breaks) | Validation gap is amplified when multiple scenarios share modules |
| Connect Pause/Resume | Pitfall 11 (offset mismatch after failover) | Connect state tracking is prerequisite to DR failover automation |

---

## Sources

- Codebase analysis: `/Users/jhogan/fsi-kafka-platform/` (all files read directly)
- ADR-003, ADR-004, ADR-005 from `docs/adr/`
- CONCERNS.md from `.planning/codebase/CONCERNS.md`
- PROJECT.md from `.planning/PROJECT.md`
- Domain knowledge of Confluent Platform, CFK operator, Apache Flink, MRC, OpenShift SCC model, Terraform provider architecture (training data, MEDIUM confidence -- web verification was unavailable)

**Confidence note:** All pitfalls are grounded in the specific codebase and architecture decisions documented in this repository. Domain-specific details (CFK SCC behavior, MRC observer promotion mechanics, Flink transaction semantics) are from training data and should be verified against current Confluent and Apache Flink documentation during implementation phases.
