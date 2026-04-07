# Feature Landscape

**Domain:** Ansible-based Confluent Platform governance automation (v2.0 milestone)
**Researched:** 2026-04-07
**Confidence:** MEDIUM (verified via Confluent docs, cp-ansible GitHub, cp-ansible-admin community project, Ansible best practices docs; REST API patterns validated against official Confluent API docs)

## Scope

This feature landscape covers ONLY the new Ansible automation features for v2.0. It does not repeat v1.0 features (Terraform modules, shell-based DR CLI, schema validation, observability templates) which are documented in the v1.0 research. The focus is: what Ansible roles, playbooks, and CI/CD content must be built to achieve governance parity with the existing Terraform topic module for Confluent Platform (CP) and CFK deployments.

## Table Stakes

Features that any Ansible-based CP governance solution must have. Without these, teams continue using manual `confluent` CLI commands or ad-hoc scripts -- which defeats the purpose of the automation milestone.

### Topic Lifecycle Management Role

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Create topics via Kafka REST API v3 | Teams expect `ansible-playbook -i inventory topics.yml` to create all declared topics. Manual `kafka-topics.sh` is the status quo being replaced. | Medium | CP cluster deployed (via cp-ansible), REST Proxy or Confluent Server REST API enabled on broker (port 8090) | Use `ansible.builtin.uri` module against `/kafka/v3/clusters/{cluster_id}/topics` endpoint. Must be idempotent: GET first, POST only if absent. cp-ansible-admin community project validates this pattern works. |
| SLA-tier-derived defaults | Identical to Terraform module: `critical` = 12 partitions / FULL_TRANSITIVE / 7-day retention, `standard` = 6 / BACKWARD_TRANSITIVE / 3-day, `best-effort` = 3 / BACKWARD / 1-day, `compliance` = 12 / FULL_TRANSITIVE / N-year. | Low | None (pure Ansible variable logic) | Implement as `defaults/main.yml` lookup maps mirroring `modules/topic/main.tf` locals. Override variables available for documented exceptions. |
| Topic naming validation | Enforce `{domain}.{application}.{version}.{entity}` regex at Ansible runtime, identical to Terraform `variables.tf` regex. Rejects invalid names before API calls. | Low | None | Use `ansible.builtin.assert` with regex test. Fail fast with clear error message. Must match `^[a-z][a-z0-9-]{1,30}\.[a-z][a-z0-9-]{1,30}\.v[0-9]+\.[a-z][a-z0-9-]{1,60}$` pattern. |
| Topic config updates (retention, cleanup, min.insync.replicas) | Topics drift. Teams expect to declare desired state and have Ansible converge. Config-only changes must not recreate topics. | Medium | Existing topics on cluster | Use PUT against `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs/{config_name}`. Idempotent by nature (PUT is declarative). Report `changed` only when value differs. |
| CPTopic YAML format consumption | Existing `scenarios/cp-rhel/topics/*.yml` use CPTopic YAML format. The role must read these files directly, not require a new format. | Low | Existing CPTopic YAML files | Parse `metadata.labels` for governance fields (fsi.domain, fsi.sla-tier, fsi.owner, fsi.data-classification). Parse `spec.partitionCount` and `spec.configs`. The format already exists with 3 example files. |
| Dry-run / check mode support | `--check` must show what would change without changing anything. Required for FSI change management processes (CAB approval requires preview). | Medium | None | Ansible check mode requires the role to separate "gather current state" from "apply changes." GET-then-compare pattern. All `ansible.builtin.uri` calls gated on `when: not ansible_check_mode` for mutating operations. |
| Idempotent execution | Running the playbook twice produces the same result. No duplicate topics, no error on re-run. | Medium | None | GET before POST/PUT. Use `changed_when` to accurately report whether state changed. This is fundamental Ansible role quality. |
| Topic deletion with safety gate | Governed deletion: require explicit `state: absent` + confirmation variable. Accidental deletion of a production topic is catastrophic. | Low | None | Default `state: present`. When `state: absent`, require `confirm_deletion: true` variable. Log warning before deletion. Refuse to delete topics matching `critical` or `compliance` SLA tier without override. |

### Schema Registration Role

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Register Avro schemas via SR REST API | Push `.avsc` files to Schema Registry subjects. CP Schema Registry uses identical REST API to CC -- same endpoints, different auth. | Medium | CP Schema Registry deployed, network reachable from Ansible controller | POST to `/subjects/{subject}/versions` with schema JSON payload. Subject naming follows TopicNameStrategy: `{topic_name}-value`. Authentication via basic auth (SR credentials) or mTLS. |
| Compatibility mode configuration per subject | Set compatibility level (FULL_TRANSITIVE, BACKWARD_TRANSITIVE, BACKWARD) derived from SLA tier, matching Terraform module behavior. | Low | Schema registered first | PUT to `/config/{subject}` with `{"compatibility": "FULL_TRANSITIVE"}`. Must happen after initial schema registration. |
| Schema compatibility pre-check | Before registering, verify schema is compatible with existing versions. Fail with clear message if incompatible (prevents broken data contracts). | Medium | Existing schema versions in SR | POST to `/compatibility/subjects/{subject}/versions/latest` with proposed schema. If response `is_compatible: false`, fail the task with details. This catches breaking changes before they land. |
| Schema file discovery from CPTopic | Given a CPTopic YAML, locate the corresponding `.avsc` file by convention (`schemas/{domain}-{entity}.avsc`) or explicit `schema_file` field. | Low | Schema files in expected location | Convention-based discovery with override. If CPTopic declares `spec.schema_file`, use that. Otherwise, construct path from metadata labels. |
| PII metadata tagging | Schema metadata properties (owner, sla-tier, data-classification, pii, pii-fields) applied to SR subject, identical to Terraform module metadata. | Low | Schema registered | Use `/subjects/{subject}/versions` with `metadata.properties` in payload. Maps directly from CPTopic labels and `pii_fields` list. |
| Compatibility override governance | When `compatibility_override` is used, log a warning and require an `override_justification` field in CPTopic. Mirrors Terraform module's override pattern. | Low | None | Ansible `assert` task validates that override includes justification. Emit warning via `ansible.builtin.debug` with `msg` at verbosity 0. |

### RBAC Provisioning Role (via MDS REST API)

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| MDS token acquisition | Authenticate to MDS to get bearer token for subsequent RBAC API calls. MDS is the CP authorization service (no equivalent in vanilla Kafka). | Medium | MDS enabled on brokers (`rbac_enabled: true` in cp-ansible inventory), LDAP backend configured | POST to `/security/1.0/authenticate` with mTLS cert or LDAP credentials. Token used for all subsequent MDS API calls. Token has TTL; role must handle refresh. |
| Per-topic producer/consumer role bindings | Grant `DeveloperWrite` to producers and `DeveloperRead` to consumers on specific topic resources. Direct parity with Terraform `confluent_role_binding` resources. | Medium | MDS token, topic exists, principals exist in LDAP/AD | POST to `/security/1.0/principals/User:{principal}/roles/{role}/bindings` with resource pattern `{topic: {name: "topic_name", patternType: "LITERAL"}}`. Cluster scope from inventory. |
| Consumer group bindings | Consumers need `DeveloperRead` on their consumer group pattern (`{principal}-*`). Without this, consumers connect but get authorization errors. | Low | MDS token | Same MDS endpoint, resource type `Group` with `PREFIXED` pattern. Mirror Terraform module's `consumer_group` binding pattern. |
| Schema Registry subject bindings | Producers need `DeveloperWrite` on SR subjects; all need `DeveloperRead`. Without this, serialization fails with auth errors. | Low | MDS token, SR subject exists | Resource type `Subject` in MDS bindings. Same endpoint, different resource scope. |
| Binding state comparison (idempotent) | List existing bindings before creating. Do not duplicate bindings. Report accurate `changed` status. | Medium | None | GET `/security/1.0/principals/User:{principal}/roles/{role}/bindings` first. Compare with desired state. Only POST missing bindings. This is where most community implementations fall short. |
| Binding removal for deprovisioning | When a service account is removed from CPTopic, corresponding RBAC bindings should be removed. | Medium | None | DELETE via MDS API. Requires tracking "desired state" from CPTopic vs "current state" from MDS. Only remove bindings that were managed by this role (use tag/label convention). |

### DR Automation Playbooks

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| MM2 failover playbook | Orchestrated failover: pause connectors, stop source MM2, promote topics on DR, update service discovery, validate. Replaces manual shell script steps. | High | MM2 deployed and replicating, Connect REST API accessible, Consul (optional) for service discovery | Translate existing `fsi-dr.sh mm2` backend logic into Ansible tasks. Advantage over shell: better error handling, check mode, retry logic, parallel task execution. Use `ansible.builtin.uri` for Connect and Kafka REST APIs. |
| MM2 failback playbook | Reverse replication direction, re-establish mirrors, verify data sync, cut back to primary. | High | Successful failover state, primary cluster recovered | Failback is operationally the inverse of failover but with additional data consistency validation. Must verify no data loss during failback window. |
| MRC failover playbook (observer promotion) | For RPO=0 scenarios: promote observer replica to leader. CP-specific feature using `kafka-replica-elections` or Confluent CLI. | High | MRC topology deployed (2 sync + 1 observer), `confluent` CLI available | Observer promotion via `confluent kafka partition reassign` or direct Admin API. Validate ISR state post-promotion. This is the most complex DR pattern. |
| DR state validation tasks | Pre-flight checks before failover: mirror lag within SLA threshold, all topics mirroring, target cluster healthy. Post-flight: topics writable, schema registry accessible, consumers can connect. | Medium | Monitoring endpoints accessible | Reusable task file imported by both failover and failback playbooks. SLA-tier thresholds from existing `fsi-dr.sh` constants (critical=30s warn/60s alert, standard=5m/15m, best-effort=1h/4h). |
| Dry-run mode | `--check` or `--extra-vars "dry_run=true"` shows every step that would execute without executing. Generates audit-ready output. | Medium | None | All mutating tasks wrapped in `when: not dry_run`. Print "WOULD DO: ..." messages. Output formatted as DR drill report for compliance evidence. |
| DR drill playbook | Full cycle: failover -> validate -> run integration tests -> failback -> validate -> generate report. Quarterly regulatory requirement. | Medium | All DR playbooks working, integration test suite | Orchestration playbook that calls failover, waits, runs validation, calls failback. Produces timestamped report. |

### Observability Deployment Role

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| JMX exporter agent deployment | Install/configure Prometheus JMX Exporter as Java agent on Kafka brokers, Schema Registry, Connect workers. | Medium | CP components deployed via cp-ansible, `jmxexporter_enabled: true` | cp-ansible already supports `jmxexporter_enabled` variable. This role extends with FSI-specific JMX exporter configs from `observability/grafana/jmx-exporter-stub.yaml` -- custom metric rules for cluster health, consumer lag, ISR. |
| Prometheus scrape config generation | Generate `prometheus.yml` scrape targets from inventory. When new brokers are added, scrape config updates automatically. | Low | Prometheus deployed (out of scope for this role to install) | Template `prometheus.yml` with `scrape_configs` entries for each host in `kafka_broker`, `schema_registry`, `kafka_connect` groups. Use inventory-driven Jinja2 template. |
| Grafana dashboard import | Deploy FSI dashboard JSON files from `observability/grafana/` to Grafana via API or file provisioning. | Medium | Grafana deployed (out of scope to install) | Two modes: API import via `community.grafana.grafana_dashboard` module, or file provisioning (copy JSON to `/var/lib/grafana/dashboards/`). API mode preferred for idempotency. |
| Per-provider template deployment | Support Dynatrace, Datadog, Splunk, New Relic, Instana alongside Grafana/Prometheus. Each provider has different import mechanism. | Medium | Provider agent/collector deployed | Variable-driven: `observability_provider: grafana` selects which templates to deploy. Each provider gets a task file. Start with Grafana/Prometheus (most common on-prem), add others incrementally. |
| Alert rule deployment | Import alert definitions (lag thresholds, broker down, ISR shrink) into monitoring provider. SLA-tier-aware thresholds. | Medium | Monitoring provider accessible | Grafana: import `alerts.yaml`. Datadog: POST monitors via API. Dynatrace: import `alerts.json`. Each provider has different alert API. |

### Connector Deployment Role

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Deploy/update connectors via Connect REST API | Push connector configs to Connect cluster. Idempotent: create if absent, update if config differs. | Medium | Kafka Connect deployed and healthy | cp-ansible already has `kafka_connectors` module. Evaluate whether to use it or build custom `ansible.builtin.uri` tasks. The cp-ansible module requires `connect_url` and `active_connectors` list. |
| Connector health validation | After deployment, verify all connectors and tasks are in `RUNNING` state. Alert/fail on `FAILED` or `PAUSED` (unless intentional). | Low | Connectors deployed | GET `/connectors/{name}/status` and check `connector.state` and `tasks[*].state`. Retry with backoff for connectors still initializing. |
| Connector pause/resume for DR | During failover, pause all connectors (prevent dual-write). Resume on target cluster after promotion. | Low | Connect REST API accessible | PUT `/connectors/{name}/pause` and `/connectors/{name}/resume`. Critical for DR playbooks. Already exists as steps in `fsi-dr.sh`. |

### End-to-End Deployment Pipeline

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Orchestration playbook (full pipeline) | Single command: deploy CP -> create topics -> register schemas -> configure RBAC -> deploy connectors -> deploy observability. New cluster to production-ready in one run. | Low (orchestration only) | All individual roles working | `site.yml` that imports role playbooks in dependency order. Tags allow running subsets. This is the "single automation run" promise from PROJECT.md Core Value. |
| Selective execution via tags | Run only topics (`--tags topics`), only RBAC (`--tags rbac`), only DR (`--tags dr`). Day-2 operations do not require full pipeline re-run. | Low | None | Ansible tags on each role include block. Standard Ansible pattern. |
| Environment separation | Same roles, different inventories: `inventory/dev/`, `inventory/staging/`, `inventory/prod/`. Environment-specific variables (endpoints, credentials, topic lists). | Low | None | Standard Ansible inventory pattern. Credentials via Ansible Vault. |

### CI/CD for Ansible Content

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| ansible-lint on all roles | Static analysis catches YAML syntax errors, deprecated module usage, missing metadata, security anti-patterns. | Low | None | GitHub Actions workflow: `ansible-lint ansible/roles/`. Use `.ansible-lint` config to set rules. Runs on every PR touching `ansible/`. |
| yamllint on YAML files | Catches indentation errors, duplicate keys, trailing whitespace. Complements ansible-lint. | Low | None | Standard CI step. Config in `.yamllint`. |
| Molecule test framework for roles | Integration tests: run role in Docker container, verify outcomes. Catches real failures that lint misses. | High | Docker or Podman for Molecule driver | Each role gets `molecule/default/` scenario. Challenge: Kafka/SR/MDS are complex to mock in containers. Use `molecule-docker` driver with pre-built CP containers for integration, or mock REST API responses for unit-level tests. |
| GitHub Actions workflows | PR validation (lint + molecule) and deployment (run playbooks against target environment). | Medium | GitHub Actions runners, Ansible installed | Two workflows: `ansible-lint.yml` (on PR), `ansible-deploy.yml` (on merge to main, targets staging/prod). Environment protection rules for prod. |

## Differentiators

Features that go beyond what cp-ansible-admin and community Ansible Kafka tools provide. These justify building custom roles rather than adopting off-the-shelf community tools.

### Governance Parity with Terraform Module

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| SLA-tier abstraction (single input, derived config) | Teams declare `sla_tier: critical` and get correct partitions, compatibility, retention, alert thresholds automatically. No other Ansible Kafka tool does this. cp-ansible-admin requires explicit config per topic. | Low | None | Direct port of Terraform module's `locals` block. The existing 3 CPTopic YAMLs already use `fsi.sla-tier` label. The role reads this and derives everything else. |
| Unified CPTopic YAML format across Ansible and Terraform | Same topic definition format works for both Ansible roles (CP/CFK) and informs Terraform module (CC). Teams define once, deploy anywhere. | Medium | CPTopic format spec finalized | The CPTopic YAML already exists. Ansible roles consume it natively. Add a thin converter for Terraform module calls if teams want to maintain one source of truth. This is the cross-deployment parity differentiator. |
| Compliance-tier with year-based retention | `sla_tier: compliance` + `retention_years: 7` auto-calculates retention in ms. No other tool handles regulatory retention periods as a first-class concept. | Low | None | Direct port from Terraform module: `retention_years * 31557600000 ms/year`. Validation: must be >= 7 years per FSI regulatory requirement. |
| Full-stack atomic provisioning | One playbook creates topic + registers schema + sets compatibility + binds RBAC + configures DR mirror + deploys alerts. No other tool combines all six. | High | All roles working | The Terraform module does this in one `module` call. The Ansible equivalent is a `governance.yml` playbook that chains all roles. The atomic unit of governance is the topic, not the individual resource. |
| Confidential topic enforcement | When `data_classification: confidential`, automatically require PII fields, restrict consumer list, and add encryption metadata. Mirrors Terraform module's CSFLE preconditions. | Medium | Schema registration role | Port of Terraform module's `precondition` blocks. For CP (no CSFLE), enforce via RBAC restrictions and PII metadata tagging. Document that CSFLE field-level encryption requires Confluent Enterprise license. |

### DR Orchestration Superiority Over Shell

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| Parallel task execution during DR | Ansible can pause all connectors simultaneously (parallel loop), verify all topics simultaneously, etc. Shell script does them sequentially. | Low | None | Use `async` + `poll` or `loop` with `async` for parallel REST API calls. Reduces DR execution time significantly for clusters with many topics/connectors. |
| Structured DR audit report | Generate YAML/JSON report with timestamps, before/after states, lag measurements, validation results. Shell script output is unstructured text. | Medium | None | Ansible `set_fact` to accumulate results, `template` module to render report. Machine-parseable for compliance systems. |
| Retry and error recovery | Ansible's retry mechanism (`retries`, `delay`, `until`) handles transient failures gracefully. Shell `set -e` exits on first failure. | Low | None | Critical for DR where API calls may fail due to cluster state transitions. Configurable retry counts per step. |

### Observability-as-Code

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| Inventory-driven monitoring | Add a broker to inventory, re-run observability role, monitoring auto-updates. No manual Prometheus/Grafana config changes. | Low | Inventory reflects actual infrastructure | Jinja2 templates for `prometheus.yml` and Grafana datasources driven by inventory groups. This is standard Ansible pattern but uniquely valuable for Kafka where broker counts change during scaling. |
| SLA-tier-aware alert thresholds | Alert thresholds derived from `sla_tier` label on each topic. `critical` topics get tighter lag alerts than `best-effort`. Deployed automatically per topic. | Medium | Topics created with SLA-tier labels | Generate per-topic alert rules based on SLA tier constants (matching `fsi-dr.sh` thresholds). Deploy to monitoring provider. No other tool auto-generates topic-level alerts from governance metadata. |

## Anti-Features

Features to explicitly NOT build in the Ansible automation milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Custom Ansible modules (Python) for Kafka admin | Writing Python modules adds maintenance burden, testing complexity, and Python dependency management. The `ansible.builtin.uri` module against REST APIs is simpler, more transparent, and easier to debug. | Use `ansible.builtin.uri` for all REST API calls (Kafka REST v3, Schema Registry, MDS, Connect). This is the pattern validated by cp-ansible-admin and community tools. |
| Replacing cp-ansible for cluster deployment | cp-ansible is Confluent-certified, well-tested, and maintained. Rewriting cluster deployment roles is scope creep and maintenance folly. | Depend on `confluent.platform` collection for Day 1 (deploy). Build governance roles for Day 2 (configure). Clear boundary: cp-ansible owns systemd services, our roles own logical resources (topics, schemas, RBAC). |
| Ansible for Confluent Cloud | No native Ansible provider for CC API. The Terraform Confluent provider is mature and purpose-built. Wrapping CC REST APIs in Ansible adds complexity with no benefit. | CC stays Terraform-only (per PROJECT.md Out of Scope). Ansible roles target CP and CFK only. |
| Interactive UI or wizard for playbook configuration | Ansible is CLI-first. Building a web UI to generate inventory/playbooks adds massive scope. | Provide well-documented `inventory/*.yml.example` files and `group_vars/` templates. Teams copy and fill in values. Same pattern as existing cp-rhel scenario. |
| Full CP lifecycle management (upgrades, scaling, patching) | cp-ansible handles rolling upgrades and scaling. Duplicating this adds maintenance burden with no governance value. | Document how to use cp-ansible for upgrades alongside governance roles. Governance roles are re-entrant: re-run after upgrade to verify/restore governance state. |
| Apache Kafka (non-Confluent) support | MDS RBAC, Confluent REST API v3, and cp-ansible are Confluent-specific. Supporting vanilla Apache Kafka doubles the API surface. | Per PROJECT.md constraint: roles target CP with MDS/Confluent CLI only. Teams on vanilla Kafka use other tools (Strimzi, ansible-kafka-admin). |
| Event-Driven Ansible (EDA) integration | EDA with Kafka as event source is interesting but orthogonal to governance automation. It solves "react to Kafka events" not "govern Kafka resources." | Document as future enhancement. EDA could trigger governance playbooks on topic creation events, but this is optimization, not MVP. |

## Feature Dependencies

```
cp-ansible cluster deployment (EXISTING -- prerequisite, not built by us)
  |
  v
Topic Lifecycle Role
  |-> Reads CPTopic YAML files
  |-> Calls Kafka REST API v3
  |-> Enforces SLA-tier defaults
  |-> Validates naming convention
  |
  +-> Schema Registration Role (depends on topics existing)
  |     |-> Calls Schema Registry REST API
  |     |-> Sets compatibility per SLA tier
  |     |-> Pre-checks compatibility before register
  |     |-> Applies PII metadata
  |
  +-> RBAC Provisioning Role (depends on topics + schemas existing)
  |     |-> Acquires MDS token
  |     |-> Creates per-topic producer/consumer bindings
  |     |-> Creates consumer group bindings
  |     |-> Creates SR subject bindings
  |
  +-> Connector Deployment Role (depends on topics + schemas + RBAC)
        |-> Deploys connector configs via Connect REST API
        |-> Validates connector health

DR Automation Playbooks (independent of above, but uses topic inventory)
  |-> MM2 Failover Playbook
  |     |-> Pauses connectors (uses Connector role tasks)
  |     |-> Promotes mirror topics
  |     |-> Updates service discovery
  |     |-> Validates state
  |-> MM2 Failback Playbook (depends on failover)
  |-> MRC Failover Playbook (independent MM2 alternative)
  |-> DR Drill Playbook (orchestrates failover + validate + failback)

Observability Deployment Role (independent, can run anytime after CP deploy)
  |-> JMX exporter config deployment
  |-> Prometheus scrape config generation
  |-> Dashboard import (per provider)
  |-> Alert rule deployment (SLA-tier-aware)

CI/CD (independent, runs in GitHub Actions)
  |-> ansible-lint + yamllint (no dependencies)
  |-> Molecule tests (requires Docker/Podman)
  |-> Integration tests (requires CP test cluster)
  |-> GitHub Actions workflows
```

## MVP Recommendation

### Must Ship (Table Stakes -- required for governance parity)

1. **Topic Lifecycle Role** -- The foundation. Without topics-as-code via Ansible, there is no v2.0 milestone value. Consume existing CPTopic YAML format, enforce SLA-tier defaults, idempotent REST API calls, check mode support.

2. **Schema Registration Role** -- Schemas are part of the governed topic contract. Register Avro schemas, set compatibility per SLA tier, pre-check compatibility, apply metadata. Depends on topic role.

3. **RBAC Provisioning Role** -- Without RBAC, topics exist but nobody can use them (or everybody can, which is worse for FSI). MDS token management, per-topic bindings for producers/consumers/consumer-groups/SR-subjects. Depends on topic + schema roles.

4. **End-to-End Orchestration Playbook** -- The "single automation run" promise. `site.yml` chains: topics -> schemas -> RBAC -> connectors -> observability. Tags for selective execution.

5. **CI/CD for Ansible Content** -- ansible-lint + yamllint in GitHub Actions. Without this, Ansible content quality degrades from PR #1. Molecule tests are higher complexity but should ship in initial milestone.

### Should Ship (high value, parallelizable)

6. **DR Automation Playbooks (MM2)** -- Translate existing `fsi-dr.sh mm2` backend to Ansible. Higher value than shell because of check mode, parallel execution, structured reporting. Can be built in parallel with governance roles.

7. **Observability Deployment Role** -- JMX exporter config + Prometheus scrape config + Grafana dashboard import. Leverages existing `observability/` templates. Can be built in parallel with governance roles.

8. **Connector Deployment Role** -- Deploy and validate connectors via Connect REST API. Lower priority than topics/schemas/RBAC but needed for full pipeline. cp-ansible's `kafka_connectors` module may cover this.

### Defer to Later Phase

- **MRC Failover Playbook** -- Highest complexity DR pattern. Ship MM2 first, MRC after validation.
- **DR Drill Playbook** -- Orchestration on top of failover/failback. Ship after individual DR playbooks are proven.
- **Per-provider observability (non-Grafana)** -- Start with Grafana/Prometheus. Add Dynatrace, Datadog, Splunk as incremental additions.
- **CFK governance via Ansible** -- CFK uses Kubernetes CRDs, not REST APIs. The `kubernetes.core.k8s` module is the path, but it is a different pattern than CP REST API governance. Separate from CP roles.

## Sources

- [Confluent cp-ansible GitHub](https://github.com/confluentinc/cp-ansible) -- Certified collection for CP deployment (Day 1), does NOT handle topics, schemas, or per-topic RBAC (Day 2)
- [cp-ansible-admin community tool](https://github.com/thecrazymonkey/cp-ansible-admin) -- Community Day 2 admin using REST APIs for topics, schemas, RBAC, quotas, ACLs. Validates the REST API approach. Does not have SLA-tier abstraction or governance parity features.
- [Confluent Ansible RBAC docs](https://docs.confluent.io/ansible/current/ansible-authorize.html) -- Component-level RBAC configuration; does not manage per-topic bindings
- [Confluent Schema Registry API Reference](https://docs.confluent.io/platform/current/schema-registry/develop/api.html) -- REST API endpoints for schema registration, compatibility checking, config management
- [Confluent MDS RBAC REST API](https://docs.confluent.io/platform/current/security/authorization/rbac/rbac-config-using-rest-api.html) -- Endpoints for role binding CRUD via MDS
- [Confluent Kafka REST API v3](https://docs.confluent.io/platform/current/kafka-rest/api.html) -- Topic CRUD, config management via REST
- [Confluent Ansible overview](https://docs.confluent.io/ansible/current/overview.html) -- cp-ansible scope: install, configure, upgrade. Not topic/schema/RBAC lifecycle.
- [Ansible Molecule testing](https://www.endpointdev.com/blog/2025/03/testing-ansible-with-molecule/) -- Best practices for role testing with Docker driver
- [Ansible best practices for idempotency](https://redhat-cop.github.io/automation-good-practices/) -- Role design patterns: check mode, changed_when, assert
- [community.grafana.grafana_dashboard module](https://docs.ansible.com/projects/ansible/latest/collections/community/grafana/grafana_dashboard_module.html) -- Dashboard import/export via Grafana API
- Existing codebase: `modules/topic/main.tf` (governance logic to port), `modules/topic/variables.tf` (validation rules to port), `scenarios/cp-rhel/` (CPTopic YAML format, cp-ansible integration), `scripts/fsi-dr.sh` (DR logic to port), `observability/` (templates to deploy)
