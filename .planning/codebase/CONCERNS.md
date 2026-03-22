# Codebase Concerns

**Analysis Date:** 2026-03-21

## Manual DR Failover Risk

**Area:** Disaster recovery process

- **Issue:** DR failover requires 6 manual scripted steps executed in sequence. No automation, no orchestration, only human-executable shell scripts.
  - Files: `scripts/mirror-failover.sh`, `scripts/mirror-failback.sh`, `scripts/consul-flip-region.sh`, `scripts/connect-pause-all.sh`
- **Impact:**
  - Failover is time-consuming and error-prone in high-stress incident scenarios
  - Operator fatigue during crisis increases risk of missed steps or incorrect parameter passing
  - RTO slips if operator is unavailable or makes mistakes
  - No rollback automation — failback must be manually orchestrated as well
- **Fix approach:**
  - Wrap the 6-step sequence in a single orchestration script with atomic transitions
  - Add state validation between steps (e.g., verify mirror topic promoted before proceeding to Consul flip)
  - Implement a `rollback` subcommand that undoes changes if an intermediate step fails
  - Add dry-run mode (`--dry-run`) to preview what will happen before committing to failover
  - Log all operations to a timestamp-based log file for audit trail and debugging

---

## Cluster Linking RPO > 0

**Area:** Disaster recovery and data loss tolerance

- **Issue:** Cluster Linking introduces replication lag between East (active) and West (DR) clusters. While typically seconds, this is unbounded—network issues could cause hours of lag.
  - Files: `docs/adr/005-cluster-linking-over-mrc.md`
- **Impact:**
  - In-flight transactions between producer and mirror commit may be lost on East region failure
  - FSI stated RPO target is "~2 hours (aspirationally lower)" — achievable by Cluster Linking but not guaranteed
  - No visibility into actual lag metrics in current Terraform setup — mirror lag is not monitored or exposed
  - If compliance auditors ask "what's our data loss window?", answer is "we don't know, possibly 0-minutes to hours"
- **Fix approach:**
  - Add Confluent Cloud Metrics API integration to expose mirror lag (follower lag) per topic
  - Set up alerts in Dynatrace if lag exceeds configurable SLA (e.g., >5 minutes for critical topics, >30 min for standard)
  - Document actual observed lag percentiles from production metrics in runbooks
  - If aspirational RPO tightens below 1 minute, escalate to architecture review — MRC or alternative DR pattern required

---

## Hardcoded Cluster IDs and Endpoints in Terraform

**Area:** Infrastructure configuration and maintainability

- **Issue:** Every environment file (`environments/prod/main.tf`) contains hardcoded Confluent Cloud cluster IDs, REST endpoints, and CRNs as locals. These must be manually synchronized across multiple files and cannot be centrally versioned or rotated.
  - Files: `environments/prod/main.tf` (lines 33-55)
- **Impact:**
  - When DR cluster is replaced, CRN values must be updated in multiple places
  - Inconsistent state between prod-east and potential prod-west branch leads to deployment errors
  - Onboarding new regions requires copying and editing many values — easy to miss one
  - No audit trail of when/why endpoint values changed
  - Scale limit: adding a third region requires manual duplication of all locals
- **Fix approach:**
  - Externalize cluster metadata to a single `clusters.tfvars` file (not committed, deployed by ops)
  - Use `terraform_remote_state` to read cluster metadata from a central admin Terraform module
  - Alternatively, fetch cluster details dynamically from Confluent Cloud API using `data` sources (requires broader API key permissions)
  - Version control the mapping logic but not the secrets

---

## Missing Terraform Output Validation

**Area:** Infrastructure provisioning reliability

- **Issue:** After `terraform apply` completes, there is no automated verification that the resulting infrastructure matches expectations. PR template mentions "Verify: topic exists, schema registered, mirror topic created, RBAC applied" but this is manual and human-subjective.
  - Files: `environments/prod/example-topics.tf`, `.github/pull_request_template.md`
- **Impact:**
  - Partial deployments go undetected (e.g., topic created but RBAC role bindings failed silently)
  - RBAC misconfigurations leave producers unable to write or consumers unable to read
  - Mirror topics might fail to create silently if cluster link is down at apply time
  - Onboarding teams discover permission errors only when their application tries to produce
- **Fix approach:**
  - Add Terraform `test` blocks (Terraform 1.6+) to validate post-apply state:
    - Verify topic exists and has expected partition count
    - Verify schema subject is registered with correct version
    - Verify mirror topic exists (if enabled)
    - Verify all RBAC role bindings are present
  - Add a post-apply smoke test shell script that:
    - Lists the topic via Confluent CLI
    - Queries Schema Registry for the subject
    - Attempts a test produce with a test service account (if credentials available)
  - Wire these checks into GitHub Actions as a final validation step before commenting "SUCCESS" on PR

---

## Service Account Credential Management Complexity

**Area:** Security and operational overhead

- **Issue:** The Terraform module expects separate API keys for Kafka, Schema Registry, and (optionally) DR Kafka. Each is a separate managed credential with its own rotation schedule. No clear guidance on credential rotation timing or automation.
  - Files: `environments/prod/main.tf` (lines 23-30), `modules/topic/main.tf` (lines 107-110, 127-130)
- **Impact:**
  - Rotating a credential requires updating GitHub Secrets, redeploying, and restarting all consumers/producers in-flight
  - No way to do zero-downtime credential rotation (dual-write period unsupported by current design)
  - If a credential is leaked, attacker has same permissions as all topics on that cluster (overprivileged)
  - Onboarding new teams requires generating new service accounts — no pooling or role-based token issuing
- **Fix approach:**
  - Switch to OAUTHBEARER authentication where possible (Azure AD for Azure deployments, AWS IAM for AWS)
  - Use HashiCorp Vault or cloud-native secret manager to manage credential lifecycle with automatic rotation
  - For multi-topic scenarios, use Confluent Cloud RBAC with fine-grained role assignments instead of admin-level API keys
  - Document credential rotation SLA and add automation to rotate credentials on a cadence (e.g., 90 days)

---

## Schema Evolution Enforcement by Convention Only

**Area:** Data contract and schema governance

- **Issue:** The `FULL_TRANSITIVE` compatibility mode for critical topics is enforced by the Terraform module locals, but teams can override it with `compatibility_override`. No pre-commit or CI check prevents dangerous overrides.
  - Files: `modules/topic/main.tf` (lines 44-52), `modules/topic/variables.tf` (lines 118-130)
- **Impact:**
  - A team can declare `sla_tier = "critical"` but then override with `compatibility_override = "BACKWARD"`, defeating the entire purpose of the SLA tier
  - The PR template mentions the override in the module call is optional, but doesn't block it
  - Schema Registry's compatibility check is only enforced at registration time — old incompatible versions can still exist if not cleaned up
  - Teams don't understand the consequences of changing compatibility modes (impact on consuming applications, rollback complexity)
- **Fix approach:**
  - Add CI validation that blocks any `compatibility_override` unless paired with a documented exception (link to JIRA/ADR required)
  - Audit existing topics to identify any overrides and document the business justification
  - Add a new enforcement level: `immutable_compatibility` flag that disallows any override (for OFAC and other compliance-critical topics)
  - In schema-guide.md, add a "Breaking Change Runbook" section that walks through multi-topic migration (too many teams attempt breaking changes without this)

---

## Limited Error Handling in Reference Applications

**Area:** Producer/consumer robustness and fault tolerance

- **Issue:** Reference Java producer and consumer have placeholder error handling comments but lack actual DLQ (Dead Letter Queue) or retry logic for common failure modes.
  - Files: `reference/java-producer/src/main/java/org/fsi/kafka/producer/FsiProducer.java` (lines 138-141), `reference/java-consumer/src/main/java/org/fsi/kafka/consumer/FsiConsumer.java` (lines 154-160)
- **Impact:**
  - Teams copy reference implementations and encounter unhandled errors in production
  - Failed messages are only logged; no recovery mechanism available
  - Consumer error handling defaults to "log and continue" which can silently skip important business transactions
  - No guidance on when to use each strategy (skip vs. retry vs. circuit-break)
- **Fix approach:**
  - Add a real DLQ pattern to FsiProducer: catch serialization/auth errors and send to a `{topic}.dlq` topic with error metadata
  - Implement exponential backoff retry logic with jitter for transient errors (network, broker overload)
  - Add a companion "DLQ Consumer" reference implementation that demonstrates monitoring and alerting on DLQ
  - Document error categories: transient (retry), authentication (alert), validation (DLQ), and how each is handled
  - Add JMX metric `dlq.messages.sent` to track DLQ ingestion

---

## Connect Pause/Resume Complexity and Manual Coordination

**Area:** DR failover and operational runbooks

- **Issue:** The `connect-pause-all.sh` script pauses all connectors when failing over, but there's no state tracking or recovery logic. If pause operation is partially successful, resume becomes ambiguous (which connectors should resume?).
  - Files: `scripts/connect-pause-all.sh`, `scripts/mirror-failover.sh`
- **Impact:**
  - If Connect REST API times out mid-pause, some connectors remain active while ops thinks they're paused
  - Failback after DR incident may resume the wrong set of connectors
  - No metric tracking for how long pause-to-resume took or how many messages were backlogged during the pause
  - Teams don't understand the implications of pausing connectors without flushing in-flight transactions
- **Fix approach:**
  - Add state file (`/var/lib/fsi-connect/pause-state.json`) that tracks which connectors were paused and when
  - Implement `--status` command to report pause/resume state before failover
  - Add a pre-pause check: verify all connectors are healthy and caught up to lag before pausing
  - After resume, add a lag-catch-up monitor that alerts when connectors are >5min behind (indicates backlog processing)
  - Document: "Pausing connectors does NOT flush pending records — data may be buffered in Connect workers"

---

## Retention Settings May Be Too Short for Compliance

**Area:** Data governance and regulatory compliance

- **Issue:** The retention defaults are very short: best-effort topics only retain for 1 day, standard for 3 days, critical for 7 days. Financial audit/compliance requirements often mandate 7 years.
  - Files: `modules/topic/main.tf` (lines 65-74)
- **Impact:**
  - Compliance teams cannot retrieve transaction records for audits after topic retention expires
  - OFAC investigation records are lost after 7 days — violates AML/CFT regulations
  - Partition backups may not exist if Confluent Cloud snapshots weren't taken before retention purge
  - Migration/forensic analysis post-incident is impossible if data has been compacted
- **Fix approach:**
  - Add a new SLA tier `compliance` with 7-year retention (or configurable based on topic tagging)
  - For current deployments, add `retention_ms_override` for topics tagged with `data_classification = "confidential"` or containing PII
  - Document that compliance topics should use cloud-native backup (Azure Blob snapshots, S3 cross-region replication) rather than relying on Kafka retention
  - Add a post-apply check that flags topics with PII but short retention as warnings

---

## Testing Coverage Gaps

**Area:** Quality assurance and CI/CD pipeline

- **Issue:** The roundtrip integration test (`reference/integration-test/roundtrip-test.sh`) only covers the happy path: produce → consume with a valid schema. No tests for error scenarios, compatibility violations, or partial failures.
  - Files: `reference/integration-test/roundtrip-test.sh`
- **Impact:**
  - Developers cannot test schema evolution scenarios locally (e.g., adding optional fields, removing deprecated fields)
  - No test for RBAC: verifying that a producer without write permission is rejected
  - No test for serialization errors: what happens if a field is missing or of wrong type?
  - No regression test for Cluster Linking: mirror topics are created but never consumed in CI
- **Fix approach:**
  - Extend integration test suite with parameterized schema evolution tests (add field, deprecate field, change type)
  - Add RBAC test: create a test service account with read-only permissions and verify produce fails
  - Add serialization error test: produce a record with mismatched schema and verify Schema Registry rejects it
  - Add mirror topic verification: after roundtrip test, consume from the mirror topic in the DR cluster to verify replication
  - Wire these tests into the GitHub Actions plan workflow to block PRs that break any scenario

---

## DR Region Hardcoding and Zone Affinity

**Area:** Infrastructure flexibility and multi-region expansion

- **Issue:** The ADR explicitly chooses Azure East US 2 ↔ West US 2. If FSI needs to expand to GCP or AWS, the entire Terraform stack must be rewritten. Cloud-specific secrets and backends are hardcoded per provider choice.
  - Files: `environments/prod/main.tf` (lines 7-16), `docs/cloud-providers.md`
- **Impact:**
  - Adopting a second cloud provider requires parallel Terraform modules with duplicate logic
  - Cost optimization opportunities (e.g., using GCP for read replicas) are blocked
  - Terraform state is locked to Azure Blob — migration to multi-cloud requires state migration
  - If Azure experiences region-wide outage, FSI has no fallback to GCP/AWS (single cloud risk)
- **Fix approach:**
  - Refactor Terraform to parameterize cloud provider (variable `cloud_provider = "azure" | "aws" | "gcp"`)
  - Use conditional provider blocks and locals to swap cloud-specific resources (backend, secret manager, networking)
  - Maintain separate `.tfvars` files per cloud (e.g., `prod-azure.tfvars`, `prod-aws.tfvars`)
  - Document the trade-offs: multi-cloud introduces complexity; single-cloud is simpler but riskier
  - Plan Phase 2 work: evaluate GCP as a secondary DR target (separate Terraform module)

---

## Undocumented Disaster Recovery Runbook Gaps

**Area:** Operational procedures and incident response

- **Issue:** The 6-step failover sequence is documented in individual scripts but not as a unified runbook. Success/failure criteria for each step are implicit.
  - Files: `scripts/mirror-failover.sh`, `docs/onboarding.md`
- **Impact:**
  - During an incident, operators must piece together the sequence from comments in shell scripts
  - No decision tree: what if step 3 (Consul flip) fails? How long to wait before retrying?
  - No rollback guidance: if failover succeeds but applications can't connect, how do we revert?
  - Post-incident: no runbook for returning to primary region (failback assumes everything stayed healthy)
- **Fix approach:**
  - Write a unified `RUNBOOK-DR-FAILOVER.md` documenting:
    - Prerequisites (cluster link health, no in-flight migrations)
    - 6 steps with expected output for each
    - Success criteria (e.g., "mirror topic count matches primary topic count")
    - Abort criteria and rollback procedure for each step
    - Post-failover validation checklist (can producers write, can consumers read, lag healthy)
  - Add a `RUNBOOK-DR-FAILBACK.md` for returning to primary after incident resolves
  - Link runbooks from the main README
  - Conduct quarterly DR drill using the runbook to identify gaps

---

## Self-Managed Connect Operational Burden

**Area:** Infrastructure operations and complexity

- **Issue:** ADR-004 chooses self-managed Connect workers on-premises. This creates an operational surface: worker health monitoring, connector restart procedures, version upgrades, and plugin dependency management.
  - Files: `docs/adr/004-onprem-connect.md`
- **Impact:**
  - Connect worker outages are not automatically resolved — ops team must manually restart
  - Plugin versions (JDBC connector, custom serializers) are not versioned or tested in CI
  - Connector restarts can cause duplicate writes (exactly-once semantics rely on transactions, not always available)
  - If a custom plugin has a memory leak, entire Connect cluster slowly degrades
  - Scaling: adding more connectors or topics requires capacity planning for on-prem infrastructure
- **Fix approach:**
  - Document Connect worker deployment and upgrade procedures (Terraform or Helm)
  - Add health checks to the Consul service catalog for Connect cluster (exposes to Dynatrace alerts)
  - Version-pin all connector plugins in `reference/connect-configs/` with test matrix
  - Implement connector resource quotas (max memory, max threads) to prevent runaway plugins
  - Plan evaluation: compare TCO of self-managed Connect vs. Confluent Cloud managed connectors + PrivateLink (Phase 3 optimization)

---

## Schema Namespace Collisions

**Area:** Schema governance and data contracts

- **Issue:** The TopicNameStrategy (`{topic}-value`) is used for all topics, but there's no enforcement that schema namespaces match domain/application hierarchy. Multiple teams could accidentally use the same namespace, causing silent overwrites.
  - Files: `modules/topic/main.tf` (lines 39-41), `docs/schema-guide.md`
- **Impact:**
  - If two teams register schemas with the same subject name (e.g., both use `account.transaction-value` without domain prefix), the second write overwrites the first in Schema Registry
  - Producers from Team A start reading wrong schema registered by Team B
  - No audit trail in Schema Registry of who owns which schema (metadata tags not visible in all contexts)
  - Schema Registry UI searches don't show data ownership
- **Fix approach:**
  - Enforce schema namespace to match topic structure: `org.fsi.{domain}.{application}.{entity}` not just the topic name
  - Add a pre-commit hook that validates `.avsc` namespace matches the topic declaration in Terraform
  - Add CI check that schema subject doesn't already exist in Schema Registry (unless it's a version bump)
  - Document: "Never reuse a schema subject name for a different business entity; versions of the same schema only"

---

## No Metrics Export for Kafka Topic Health

**Area:** Observability and monitoring

- **Issue:** The Terraform modules create topics and set retention/partition policies, but there's no Terraform output or monitoring setup for cluster health metrics (broker lag, partition replicas, controller election events).
  - Files: `modules/topic/outputs.tf`
- **Impact:**
  - Teams deploy topics but don't know how to observe them post-deployment
  - Partition leadership changes go unnoticed (could indicate broker/disk issues)
  - Rebalancing storms are invisible until producers slow down
  - No baseline metrics for capacity planning (e.g., "partition size growing 1GB/hour")
- **Fix approach:**
  - Export Confluent Cloud Metrics API queries for critical topics (lag, ingestion rate, ISR changes)
  - Add Dynatrace dashboard template that teams can import for their topics
  - Create a post-apply Terraform resource that registers the topic in monitoring system (e.g., Dynatrace service definition)
  - Document: "After topic creation, verify metrics are flowing in Dynatrace within 5 minutes"

