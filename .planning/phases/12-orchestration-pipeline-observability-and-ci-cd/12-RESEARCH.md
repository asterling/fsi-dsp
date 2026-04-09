# Phase 12: Orchestration Pipeline, Observability, and CI/CD - Research

**Researched:** 2026-04-09
**Domain:** Ansible orchestration playbooks, Kafka Connect REST API management, JMX/Prometheus/Grafana observability deployment, GitHub Actions CI for Ansible content
**Confidence:** HIGH

## Summary

Phase 12 composes the three governance roles built in Phase 11 (cp_topic, cp_schema, cp_rbac) into an end-to-end deployment pipeline orchestrated by `site.yml`. It adds two new roles: `cp_connect` for Kafka Connect connector lifecycle management via REST API, and `cp_observability` for deploying JMX exporter configs, generating Prometheus scrape targets from inventory, importing Grafana dashboards, and deploying SLA-tier-aware alert rules. Finally, it creates GitHub Actions CI workflows for ansible-lint, yamllint, molecule testing, and governance parity validation on every PR touching `ansible/`.

The Kafka Connect REST API (port 8083) provides a complete CRUD lifecycle for connectors via standard HTTP methods. The key pattern for idempotent connector management is `PUT /connectors/{name}/config` which creates or updates a connector in a single call (returns 201 for new, 200 for update). Connector health validation uses `GET /connectors/{name}/status` which returns connector and per-task state (RUNNING, FAILED, PAUSED, UNASSIGNED). The retry-with-backoff pattern for FAILED connectors uses `POST /connectors/{name}/restart?includeTasks=true&onlyFailed=true` which was added in Connect 3.x.

For observability, cp-ansible's JMX exporter defaults to specific ports per component: broker=8080, schema_registry=8078, kafka_connect=8077, zookeeper=8079. Prometheus file-based service discovery (`file_sd_configs`) is the correct mechanism for auto-generating scrape targets from Ansible inventory -- Prometheus watches JSON/YAML target files and automatically picks up changes without restart. The existing `observability/grafana/` directory contains 5 dashboard JSON files and an alerts.yaml that the cp_observability role will deploy.

**Primary recommendation:** Build `site.yml` as a multi-play orchestration playbook that imports `scenarios/cp-rhel/playbooks/deploy-cp.yml` for cluster deployment, then chains cp_topic, cp_schema, cp_rbac, cp_connect, and cp_observability roles in dependency order with comprehensive tag support. Use the established Phase 11 patterns (ansible.builtin.uri for REST calls, error collection with summary, delegated molecule driver with Python HTTP mock) for both new roles.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
All implementation choices are at Claude's discretion -- pure infrastructure phase. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions.

Key prior decisions that apply:
- ansible.builtin.uri over custom modules for all REST API operations (v2.0 decision)
- Standalone roles (not Galaxy collection) -- tightly coupled to repo governance data (v2.0 decision)
- Delegated driver with Python HTTP mock server for molecule tests (Phase 11 pattern)
- Roles register output variables (cp_topic_results, cp_schema_results, cp_rbac_results) for downstream orchestration (Phase 11 decision -- Phase 12 consumes these)
- Shared test fixtures in tests/ansible/fixtures/ across all roles (Phase 11 pattern)
- ansible-lint shared profile plus explicit FQCN enforcement (Phase 10 decision)
- conftest.py over __init__.py for tests/ansible/ (Phase 10 decision)

### Claude's Discretion
All implementation choices for this phase -- role internal structure, tag naming, CI workflow structure, observability role design.

### Deferred Ideas (OUT OF SCOPE)
None -- discuss phase skipped.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| APIPE-01 | Orchestration playbook (`site.yml`) chains cp-ansible cluster deployment with topic -> schema -> RBAC -> connectors -> observability in a single run | site.yml multi-play pattern; existing deploy-cp.yml as import target; role dependency chain documented |
| APIPE-02 | Ansible tags allow selective execution (e.g., `--tags topics`, `--tags rbac`, `--tags observability`) for Day-2 operations | Tag architecture section documents tag naming and play-level vs task-level tagging strategy |
| APIPE-03 | Connector deployment role creates/updates connectors via Connect REST API with idempotent create-if-absent, update-if-different pattern | Connect REST API section documents PUT /connectors/{name}/config for idempotent create-or-update |
| APIPE-04 | Connector health validation after deployment verifies all connectors and tasks in RUNNING state with retry and backoff | GET /connectors/{name}/status and POST restart endpoint documented with retry pattern |
| AOBS-01 | Observability role deploys JMX exporter configs from existing observability/ templates to CP cluster nodes | JMX exporter port defaults per component (8080/8078/8077/8079) and template file locations documented |
| AOBS-02 | Prometheus scrape config generated from inventory and auto-updates when nodes added | file_sd_configs mechanism documented; Jinja2 template generates JSON target files from inventory groups |
| AOBS-03 | Grafana dashboards imported via community.grafana.grafana_dashboard module or file provisioning | community.grafana collection documented; file provisioning alternative for Grafana < 9 |
| AOBS-04 | Alert rules with SLA-tier-aware thresholds deployed matching existing alerts.yaml definitions | Existing alerts.yaml structure analyzed; Grafana provisioning API format documented |
| ACI-01 | GitHub Actions workflow runs ansible-lint and yamllint on every PR touching ansible/ directory | Workflow pattern documented; existing terraform-scenario.yml reusable workflow as template |
| ACI-02 | Molecule test scenarios exist for each governance role with delegated driver | Existing molecule pattern from Phase 11 roles; new cp_connect and cp_observability need scenarios |
| ACI-03 | CI job validates governance constant parity between ansible/vars/ and Terraform modules/ | Existing test_governance_parity.py runs via pytest; CI workflow invokes it |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Deployment parity**: Core governance (topic naming, schema compat, RBAC) must work identically across deployment models
- **No custom Python modules**: `ansible.builtin.uri` for all REST API operations; filter plugins (Jinja2) are allowed
- **Standalone roles**: Not Galaxy collection -- roles tightly coupled to repo governance data
- **CP 7.7.x target**: cp-ansible 7.7.8 collection; all REST APIs available in CP 7.7
- **FQCN required**: All module references use fully qualified names (ansible.builtin.uri, etc.)
- **Commit messages**: conventional commit format
- **ansible-lint**: shared profile + FQCN enforcement; var_naming_pattern `^[a-z_][a-z0-9_]*$`
- **Task names**: Start with uppercase, Jinja at end only (name[casing] and name[template] rules)
- **Error collection**: Use `ignore_errors: true` with `# noqa: ignore-errors` for locked error collection pattern
- **Check mode**: GET-only with changed_when signals for planned changes

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ansible.builtin.uri | ansible-core 2.15 | All REST API interactions (Connect, Prometheus, Grafana) | Project decision: uri over custom modules |
| ansible.builtin.template | ansible-core 2.15 | Generate Prometheus scrape configs, JMX exporter configs from inventory | Standard Ansible templating for dynamic config generation |
| ansible.builtin.copy | ansible-core 2.15 | Deploy static config files (JMX exporter YAML, alert rules) | Standard for file deployment |
| community.grafana.grafana_dashboard | community.grafana >=1.7.0 | Import Grafana dashboard JSON files | Official Ansible module for Grafana dashboard management |
| pytest | 8.x | Unit tests for role structure and CI parity validation | Already installed, used by Phase 10/11 tests |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ansible.builtin.import_playbook | ansible-core 2.15 | Import deploy-cp.yml from site.yml | Chaining cp-ansible cluster deployment with governance |
| ansible.builtin.include_role | ansible-core 2.15 | Include governance roles within plays | Orchestration pipeline role composition |
| ansible.builtin.set_fact | ansible-core 2.15 | Register output variables (cp_connect_results, cp_observability_results) | Downstream orchestration and summary reporting |
| ansible.builtin.wait_for | ansible-core 2.15 | Wait for Connect REST API readiness after cluster deployment | Ensure Connect workers are ready before connector deployment |
| community.general | >=8.0.0 | General-purpose modules (json_query filter, etc.) | Already in requirements.yml |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| community.grafana.grafana_dashboard | File provisioning (copy to /etc/grafana/provisioning/) | File provisioning requires Grafana restart but no API key; module is more flexible but needs Grafana API access |
| file_sd_configs (Prometheus) | Static scrape_configs in prometheus.yml | Static requires Prometheus restart on node changes; file_sd_configs auto-reloads |
| ansible.builtin.uri for Connect | confluent.platform.kafka_connect role | cp-ansible manages worker deployment, not connector CRUD; our role manages connector configs via REST API |

**Installation (additions to requirements.yml):**
```yaml
# Add to ansible/requirements.yml
- name: community.grafana
  version: ">=1.7.0"
```

## Architecture Patterns

### Recommended Project Structure
```
ansible/
  site.yml                              # Top-level orchestration playbook
  playbooks/
    deploy-governance.yml               # Governance-only playbook (topics, schemas, RBAC, connectors)
  roles/
    cp_topic/                           # Phase 11 (existing)
    cp_schema/                          # Phase 11 (existing)
    cp_rbac/                            # Phase 11 (existing)
    cp_connect/                         # NEW: Connector lifecycle via Connect REST API
      defaults/main.yml
      tasks/
        main.yml                        # Entry point: load connectors, create/update, validate health
        deploy.yml                      # PUT /connectors/{name}/config (idempotent)
        validate.yml                    # GET status, verify RUNNING, retry FAILED
        check.yml                       # Check-mode: report planned changes
      meta/main.yml
      molecule/default/
        molecule.yml
        converge.yml
        verify.yml
    cp_observability/                   # NEW: JMX exporter, Prometheus, Grafana, alerts
      defaults/main.yml
      tasks/
        main.yml                        # Entry point: dispatch to sub-tasks
        jmx_exporter.yml               # Deploy JMX exporter configs to broker/SR/Connect nodes
        prometheus.yml                  # Generate file_sd_configs target files from inventory
        grafana.yml                     # Import dashboards and alert rules
        check.yml                       # Check-mode report
      templates/
        prometheus_targets.json.j2      # Jinja2 template for file_sd_configs
        jmx_exporter_broker.yml.j2     # JMX exporter config for brokers (from observability/)
        jmx_exporter_connect.yml.j2    # JMX exporter config for Connect workers
      meta/main.yml
      molecule/default/
        molecule.yml
        converge.yml
        verify.yml
.github/workflows/
  ansible-lint.yml                      # NEW: ansible-lint + yamllint on PRs
  ansible-molecule.yml                  # NEW: molecule test on PRs (or combined)
  ansible-parity.yml                    # NEW: governance parity validation (or combined)
tests/ansible/
  fixtures/mock_responses/
    connect/                            # NEW: Mock Connect REST API responses
      connectors_list.json
      connector_status_running.json
      connector_status_failed.json
      connector_created.json
```

### Pattern 1: Multi-Play Orchestration (site.yml)
**What:** site.yml uses `ansible.builtin.import_playbook` to chain cluster deployment with governance roles in separate plays, each with appropriate tags.
**When to use:** Full environment standup (Day-0) or selective Day-2 operations.
**Example:**
```yaml
# ansible/site.yml
---
# Play 1: Deploy CP cluster infrastructure via cp-ansible
- name: Deploy Confluent Platform cluster
  ansible.builtin.import_playbook: ../scenarios/cp-rhel/playbooks/deploy-cp.yml
  tags: [cluster]

# Play 2: Deploy governance (topics, schemas, RBAC)
- name: Deploy governance resources
  hosts: kafka_broker[0]
  gather_facts: true
  tags: [governance]
  tasks:
    - name: Create topics
      ansible.builtin.include_role:
        name: cp_topic
      tags: [topics, governance]

    - name: Register schemas
      ansible.builtin.include_role:
        name: cp_schema
      tags: [schemas, governance]

    - name: Provision RBAC bindings
      ansible.builtin.include_role:
        name: cp_rbac
      tags: [rbac, governance]

# Play 3: Deploy connectors
- name: Deploy Kafka Connect connectors
  hosts: kafka_connect[0]
  gather_facts: true
  tags: [connectors]
  tasks:
    - name: Deploy and validate connectors
      ansible.builtin.include_role:
        name: cp_connect
      tags: [connectors]

# Play 4: Deploy observability
- name: Deploy observability stack
  hosts: all
  gather_facts: true
  tags: [observability]
  tasks:
    - name: Deploy observability components
      ansible.builtin.include_role:
        name: cp_observability
      tags: [observability]
```

### Pattern 2: Connect REST API Idempotent Create-or-Update
**What:** Use `PUT /connectors/{name}/config` instead of POST+GET+compare. PUT is idempotent -- creates if absent, updates if config differs.
**When to use:** Every connector deployment.
**Example:**
```yaml
# PUT creates or updates in one call (201=created, 200=updated)
- name: "Deploy connector {{ connector_item.name }}"
  ansible.builtin.uri:
    url: "{{ cp_connect_url }}/connectors/{{ connector_item.name }}/config"
    method: PUT
    body_format: json
    body: "{{ connector_item.config }}"
    headers:
      Content-Type: application/json
    status_code: [200, 201]
    return_content: true
    timeout: 30
  register: _connect_deploy_result
  retries: 3
  delay: 5
  until: _connect_deploy_result.status in [200, 201]
```

### Pattern 3: Connector Health Validation with Retry
**What:** After deployment, poll connector status and restart failed tasks with exponential backoff.
**When to use:** Post-deployment health check (APIPE-04).
**Example:**
```yaml
- name: "Check connector status {{ connector_item.name }}"
  ansible.builtin.uri:
    url: "{{ cp_connect_url }}/connectors/{{ connector_item.name }}/status"
    method: GET
    return_content: true
    status_code: [200]
  register: _connect_status

- name: "Restart failed tasks for {{ connector_item.name }}"
  ansible.builtin.uri:
    url: "{{ cp_connect_url }}/connectors/{{ connector_item.name }}/restart?includeTasks=true&onlyFailed=true"
    method: POST
    status_code: [200, 202, 204]
  when: >-
    _connect_status.json.connector.state == 'FAILED'
    or (_connect_status.json.tasks | selectattr('state', 'equalto', 'FAILED') | list | length > 0)
  retries: 3
  delay: "{{ 10 * (2 ** (ansible_loop.index0 | default(0))) }}"
  until: >-
    _connect_recheck.json.connector.state == 'RUNNING'
    and (_connect_recheck.json.tasks | selectattr('state', 'equalto', 'FAILED') | list | length == 0)
```

### Pattern 4: Prometheus file_sd_configs from Inventory
**What:** Generate JSON target files from Ansible inventory groups so Prometheus auto-discovers new nodes.
**When to use:** AOBS-02 -- scrape config auto-updates when nodes added.
**Example template (prometheus_targets.json.j2):**
```jinja2
[
{% for group_name in ['kafka_broker', 'schema_registry', 'kafka_connect'] %}
{% set port_map = {'kafka_broker': cp_obs_broker_jmx_port, 'schema_registry': cp_obs_sr_jmx_port, 'kafka_connect': cp_obs_connect_jmx_port} %}
{% if groups[group_name] | default([]) | length > 0 %}
  {
    "targets": [
{% for host in groups[group_name] %}
      "{{ hostvars[host].ansible_host | default(host) }}:{{ port_map[group_name] }}"{{ '' if loop.last else ',' }}
{% endfor %}
    ],
    "labels": {
      "job": "{{ group_name }}",
      "cluster": "{{ cp_obs_cluster_name | default('fsi-kafka') }}",
      "environment": "{{ cp_obs_environment | default('prod') }}"
    }
  }{{ '' if loop.last else ',' }}
{% endif %}
{% endfor %}
]
```

### Pattern 5: Tag Architecture
**What:** Hierarchical tags enabling selective execution at multiple granularities.
**Tag mapping:**

| Tag | What It Runs |
|-----|-------------|
| `cluster` | cp-ansible cluster deployment only |
| `governance` | All governance roles (topics + schemas + RBAC) |
| `topics` | cp_topic role only |
| `schemas` | cp_schema role only |
| `rbac` | cp_rbac role only |
| `connectors` | cp_connect role only |
| `observability` | cp_observability role only |
| `jmx` | JMX exporter deployment only (sub-tag of observability) |
| `prometheus` | Prometheus scrape config only (sub-tag of observability) |
| `grafana` | Grafana dashboard import only (sub-tag of observability) |
| `alerts` | Alert rule deployment only (sub-tag of observability) |

### Anti-Patterns to Avoid
- **Monolithic single-play site.yml:** Don't put all roles in one play -- different roles target different host groups (governance runs on broker[0], connectors on connect[0], observability on all)
- **Hardcoded Prometheus targets:** Don't write static IPs in prometheus.yml -- use file_sd_configs for dynamic inventory-driven discovery
- **Missing wait_for between cluster deploy and governance:** Connect workers need time to stabilize after cp-ansible deployment; add a readiness wait before connector operations
- **POST instead of PUT for connectors:** POST /connectors fails if connector already exists (409 Conflict); PUT /connectors/{name}/config is idempotent
- **Grafana dashboard import without overwrite:** Always set `overwrite: true` when importing dashboards to handle updates cleanly

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Grafana dashboard management | Custom curl-based dashboard import | community.grafana.grafana_dashboard module | Handles auth, folder creation, overwrite, idempotency |
| Prometheus target discovery | Custom script scraping inventory | file_sd_configs with Jinja2 template | Prometheus native mechanism; auto-reloads; standard pattern |
| Connect connector diffing | Custom Python module to compare configs | PUT /connectors/{name}/config | PUT is inherently idempotent -- creates or updates as needed |
| Connector restart logic | Shell script with sleep/retry | ansible.builtin.uri with retries/until | Native Ansible retry mechanism with exponential backoff |
| YAML/JSON linting in CI | Custom validation scripts | yamllint + ansible-lint GitHub Actions | Industry-standard tools; community-maintained rules |

**Key insight:** The Kafka Connect REST API was designed for idempotent management -- PUT creates or updates, GET status provides full health picture. Don't build state comparison logic that the API already handles.

## Common Pitfalls

### Pitfall 1: Tag Inheritance with import_playbook
**What goes wrong:** When using `ansible.builtin.import_playbook`, tags on the import statement propagate to ALL tasks in the imported playbook. Running `--tags connectors` might unexpectedly trigger cluster deployment tasks.
**Why it happens:** `import_playbook` is static -- it merges the imported content into the parent at parse time, inheriting parent tags.
**How to avoid:** Use explicit tag filtering at the play level. Each play in site.yml should have its own tag(s). The `import_playbook` for cluster deployment should be wrapped with its own tag (`cluster`) that is NOT a sub-tag of other plays.
**Warning signs:** Running `--tags topics` triggers cp-ansible broker deployment.

### Pitfall 2: Connect REST API Not Ready After Cluster Deploy
**What goes wrong:** cp_connect role fails with connection refused because Connect workers haven't finished starting.
**Why it happens:** cp-ansible completes the role before the Connect REST API is fully initialized (JMX, internal topics creation, group rebalance).
**How to avoid:** Add `ansible.builtin.wait_for` on Connect REST API port (8083) with a reasonable timeout (120s) before any connector operations.
**Warning signs:** Intermittent 503 or connection refused on first playbook run.

### Pitfall 3: Connector Status Race Condition
**What goes wrong:** Status check immediately after PUT returns UNASSIGNED because rebalance is in progress.
**Why it happens:** PUT /connectors/{name}/config triggers a Connect group rebalance; tasks are assigned asynchronously.
**How to avoid:** Add a brief pause (5-10s) between PUT and status check, or use a retries/until loop that tolerates UNASSIGNED as a transient state.
**Warning signs:** Connector shows UNASSIGNED then transitions to RUNNING on retry.

### Pitfall 4: Grafana Dashboard Import Without API Key
**What goes wrong:** community.grafana.grafana_dashboard fails with 401 Unauthorized.
**Why it happens:** Grafana requires authentication; API key or username/password must be provided.
**How to avoid:** Either use `grafana_api_key` parameter (preferred for automation) or `url_username`/`url_password` for basic auth. Alternatively, use file provisioning (copy JSON to `/etc/grafana/provisioning/dashboards/`) which requires no API key but needs Grafana restart.
**Warning signs:** 401 errors on dashboard import tasks.

### Pitfall 5: ansible-lint FQCN in CI vs Local
**What goes wrong:** ansible-lint passes locally but fails in CI (or vice versa) for FQCN violations.
**Why it happens:** Different ansible-lint versions have different FQCN rule strictness. The project uses `profile: shared` with `enable_list: [fqcn]`.
**How to avoid:** Pin ansible-lint version in CI to match local development. Use the project `.ansible-lint` config file (already exists at `ansible/.ansible-lint`).
**Warning signs:** CI fails on FQCN rules that pass locally.

### Pitfall 6: Molecule Tests Fail Due to Mock Server Port Collision
**What goes wrong:** Running molecule tests for multiple roles concurrently fails because mock servers share the same port.
**Why it happens:** Phase 11 roles use ports 18090 (admin REST), 18081 (SR), 18082 (MDS). New roles need distinct ports.
**How to avoid:** Assign unique mock ports: cp_connect uses 18083 (matching real Connect port convention), cp_observability uses 18084 (Prometheus) and 18085 (Grafana).
**Warning signs:** Address already in use errors in molecule test output.

## Code Examples

### Connect REST API Response Structures

**GET /connectors/{name}/status response:**
```json
{
  "name": "jdbc-source-oracle-east",
  "connector": {
    "state": "RUNNING",
    "worker_id": "connect-prod-1:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "connect-prod-1:8083"
    }
  ],
  "type": "source"
}
```

**PUT /connectors/{name}/config request body:**
```json
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
  "connection.url": "jdbc:oracle:thin:@oracle-east.fsi.internal:1521/KAFKA",
  "connection.user": "${vault:secret/kafka-connect/oracle-east#username}",
  "connection.password": "${vault:secret/kafka-connect/oracle-east#password}",
  "topic.prefix": "corebanking.transactions.v1.",
  "mode": "timestamp+incrementing",
  "timestamp.column.name": "last_modified",
  "incrementing.column.name": "id",
  "poll.interval.ms": "5000",
  "tasks.max": "2"
}
```

### Connector Input YAML Format (cp_connect role)
```yaml
# ansible/vars/connectors.yml or passed via extra-vars
cp_connectors:
  - name: jdbc-source-oracle-east
    config:
      connector.class: io.confluent.connect.jdbc.JdbcSourceConnector
      connection.url: "jdbc:oracle:thin:@oracle-east.fsi.internal:1521/KAFKA"
      connection.user: "{{ vault_oracle_user }}"
      connection.password: "{{ vault_oracle_password }}"
      topic.prefix: "corebanking.transactions.v1."
      mode: "timestamp+incrementing"
      timestamp.column.name: "last_modified"
      incrementing.column.name: "id"
      poll.interval.ms: "5000"
      tasks.max: "2"
  - name: jdbc-sink-postgres-reporting
    config:
      connector.class: io.confluent.connect.jdbc.JdbcSinkConnector
      connection.url: "jdbc:postgresql://pg-reporting.fsi.internal:5432/reporting"
      topics: "corebanking.transactions.v1.account-transaction"
      auto.create: "true"
      insert.mode: "upsert"
      pk.mode: "record_key"
      pk.fields: "transaction_id"
```

### JMX Exporter Config Template (broker)
```yaml
# Based on existing observability/grafana/jmx-exporter-stub.yaml
# Enriched with per-component defaults from cp-ansible
hostPort: "localhost:{{ cp_obs_broker_jmx_port | default(8080) }}"
lowercaseOutputName: true
lowercaseOutputLabelNames: true

rules:
  - pattern: "kafka.server<type=ReplicaManager, name=UnderReplicatedPartitions><>Value"
    name: kafka_server_replica_manager_under_replicated_partitions
    type: GAUGE
  - pattern: "kafka.server<type=BrokerTopicMetrics, name=MessagesInPerSec><>OneMinuteRate"
    name: kafka_server_broker_topic_metrics_messages_in_per_sec
    type: GAUGE
  # ... (full config from observability/grafana/jmx-exporter-stub.yaml)
```

### GitHub Actions Workflow Pattern (ansible-lint)
```yaml
name: Ansible Lint & Test
on:
  pull_request:
    paths:
      - 'ansible/**'
      - 'tests/ansible/**'

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          pip install ansible-core ansible-lint yamllint
      - name: Run yamllint
        run: yamllint -c ansible/.yamllint ansible/
      - name: Run ansible-lint
        run: ansible-lint -c ansible/.ansible-lint ansible/

  molecule:
    name: Molecule Tests
    runs-on: ubuntu-latest
    strategy:
      matrix:
        role: [cp_topic, cp_schema, cp_rbac, cp_connect, cp_observability]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          pip install ansible-core molecule pytest pyyaml
          ansible-galaxy collection install -r ansible/requirements.yml
      - name: Run molecule test
        run: molecule test
        working-directory: ansible/roles/${{ matrix.role }}

  parity:
    name: Governance Parity
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: pip install pytest pyyaml
      - name: Run governance parity tests
        run: pytest tests/ansible/test_governance_parity.py -v
```

## Kafka Connect REST API Reference

| Operation | Method | Endpoint | Status Codes | Notes |
|-----------|--------|----------|-------------|-------|
| List connectors | GET | /connectors | 200 | Optional ?expand=status for inline status |
| Create connector | POST | /connectors | 201, 409 | 409 if rebalance in progress |
| Get connector | GET | /connectors/{name} | 200 | Returns config + task info |
| Get config | GET | /connectors/{name}/config | 200 | Config only |
| Create/Update config | PUT | /connectors/{name}/config | 200, 201 | **Preferred: idempotent** |
| Delete connector | DELETE | /connectors/{name} | 204 | Halts all tasks |
| Get status | GET | /connectors/{name}/status | 200 | Connector + per-task state |
| Restart connector | POST | /connectors/{name}/restart | 200, 202 | ?includeTasks=true&onlyFailed=true |
| Pause connector | PUT | /connectors/{name}/pause | 202 | Async |
| Resume connector | PUT | /connectors/{name}/resume | 202 | Async |

Source: [Confluent Platform Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html)

## JMX Exporter Default Ports (cp-ansible)

| Component | Default Port | Variable Name |
|-----------|-------------|---------------|
| Kafka Broker | 8080 | kafka_broker_jmxexporter_port |
| Schema Registry | 8078 | schema_registry_jmxexporter_port |
| Kafka Connect | 8077 | kafka_connect_jmxexporter_port |
| ZooKeeper | 8079 | zookeeper_jmxexporter_port |

Source: [Confluent JMX Monitoring Stacks](https://github.com/confluentinc/jmx-monitoring-stacks)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| POST + GET for connector creation | PUT /connectors/{name}/config (idempotent) | Kafka Connect 2.x+ | Simplifies idempotency; no need for existence check |
| Static prometheus.yml scrape targets | file_sd_configs with auto-reload | Prometheus 2.x+ | No Prometheus restart needed when nodes change |
| Manual Grafana dashboard import | community.grafana collection | community.grafana 1.0+ | Ansible-native idempotent dashboard management |
| Individual connector restart | POST restart?includeTasks=true&onlyFailed=true | Connect 3.x (CP 7.x) | Single call restarts only failed tasks, not all |

## Open Questions

1. **Grafana deployment method**
   - What we know: community.grafana.grafana_dashboard requires API access; file provisioning requires filesystem access to Grafana server
   - What's unclear: Whether target environments have Grafana API access from the Ansible control node
   - Recommendation: Support both methods via a `cp_obs_grafana_method` variable (api or file_provisioning). Default to file_provisioning as it requires no API key and works in air-gapped environments.

2. **Connector config file format**
   - What we know: Existing reference configs are .properties files (connect-distributed-east.properties) for Connect worker config
   - What's unclear: Whether customers have existing connector definitions in a standard format
   - Recommendation: Accept YAML list (cp_connectors) matching the pattern used by other roles. Include example connector definitions in `ansible/vars/connectors-example.yml`.

3. **Prometheus server deployment**
   - What we know: AOBS-02 requires scrape config generation; the role generates config but may not deploy Prometheus itself
   - What's unclear: Whether Prometheus is already deployed or needs to be managed by this role
   - Recommendation: Generate scrape config files only. Prometheus server deployment is out of scope -- the role produces the config that an existing Prometheus instance consumes.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.x + molecule (delegated driver) |
| Config file | ansible/.ansible-lint, ansible/roles/*/molecule/default/molecule.yml |
| Quick run command | `pytest tests/ansible/ -x -q` |
| Full suite command | `pytest tests/ansible/ -v && cd ansible/roles/cp_connect && molecule test && cd ../cp_observability && molecule test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| APIPE-01 | site.yml chains all roles in order | unit | `pytest tests/ansible/test_orchestration.py::TestSiteYml -x` | Wave 0 |
| APIPE-02 | Tags enable selective execution | unit | `pytest tests/ansible/test_orchestration.py::TestTagArchitecture -x` | Wave 0 |
| APIPE-03 | cp_connect creates/updates via PUT | unit + molecule | `pytest tests/ansible/test_cp_connect.py -x && cd ansible/roles/cp_connect && molecule test` | Wave 0 |
| APIPE-04 | Connector health validation with retry | unit | `pytest tests/ansible/test_cp_connect.py::TestConnectHealthValidation -x` | Wave 0 |
| AOBS-01 | JMX exporter config deployment | unit | `pytest tests/ansible/test_cp_observability.py::TestJmxExporter -x` | Wave 0 |
| AOBS-02 | Prometheus scrape config from inventory | unit | `pytest tests/ansible/test_cp_observability.py::TestPrometheusScrapeGen -x` | Wave 0 |
| AOBS-03 | Grafana dashboard import | unit + molecule | `pytest tests/ansible/test_cp_observability.py::TestGrafanaDashboards -x` | Wave 0 |
| AOBS-04 | SLA-tier alert deployment | unit | `pytest tests/ansible/test_cp_observability.py::TestAlertRules -x` | Wave 0 |
| ACI-01 | ansible-lint + yamllint CI workflow | unit | `pytest tests/ansible/test_ci_workflows.py::TestAnsibleLintWorkflow -x` | Wave 0 |
| ACI-02 | Molecule scenarios for all roles | unit | `pytest tests/ansible/test_ci_workflows.py::TestMoleculeScenarios -x` | Wave 0 |
| ACI-03 | Governance parity CI validation | unit | `pytest tests/ansible/test_governance_parity.py -x` | Exists |

### Sampling Rate
- **Per task commit:** `pytest tests/ansible/ -x -q`
- **Per wave merge:** `pytest tests/ansible/ -v`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/ansible/test_orchestration.py` -- covers APIPE-01, APIPE-02 (site.yml structure, tag validation)
- [ ] `tests/ansible/test_cp_connect.py` -- covers APIPE-03, APIPE-04 (role structure, REST API patterns, health validation)
- [ ] `tests/ansible/test_cp_observability.py` -- covers AOBS-01 through AOBS-04 (JMX, Prometheus, Grafana, alerts)
- [ ] `tests/ansible/test_ci_workflows.py` -- covers ACI-01, ACI-02 (workflow file structure, molecule scenario existence)
- [ ] `tests/ansible/fixtures/mock_responses/connect/` -- Connect REST API mock responses
- [ ] `ansible/roles/cp_connect/molecule/default/` -- molecule scenario for cp_connect
- [ ] `ansible/roles/cp_observability/molecule/default/` -- molecule scenario for cp_observability

## Sources

### Primary (HIGH confidence)
- [Confluent Platform Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html) -- Full endpoint reference
- [Confluent JMX Monitoring Stacks](https://github.com/confluentinc/jmx-monitoring-stacks) -- Default JMX exporter ports per component
- [Prometheus file_sd_configs guide](https://prometheus.io/docs/guides/file-sd/) -- File-based service discovery format and auto-reload behavior
- Existing codebase: ansible/roles/cp_topic/, cp_schema/, cp_rbac/ -- Established role patterns from Phase 11
- Existing codebase: observability/grafana/ -- Dashboard JSON files, alerts.yaml, JMX exporter stub

### Secondary (MEDIUM confidence)
- [community.grafana.grafana_dashboard module docs](https://docs.ansible.com/projects/ansible/latest/collections/community/grafana/grafana_dashboard_module.html) -- Module parameters and usage
- [cp-ansible 7.3.0 VARIABLES.md](https://github.com/confluentinc/cp-ansible/blob/7.3.0-post/docs/VARIABLES.md) -- JMX exporter variable naming (verified against jmx-monitoring-stacks)
- [GitHub Actions Ansible Molecule pattern](https://github.com/marketplace/actions/ansible-molecule) -- CI workflow structure

### Tertiary (LOW confidence)
- None -- all findings verified against official documentation or codebase inspection

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all components are either established project patterns (uri, molecule, pytest) or well-documented official tools (community.grafana, file_sd_configs)
- Architecture: HIGH -- site.yml multi-play pattern follows existing deploy-cp.yml precedent; new roles follow Phase 11 patterns exactly
- Pitfalls: HIGH -- Connect REST API behavior verified against Confluent docs; tag inheritance is well-documented Ansible behavior
- CI/CD: HIGH -- GitHub Actions patterns verified against existing terraform-scenario.yml and community practices

**Research date:** 2026-04-09
**Valid until:** 2026-05-09 (stable domain -- Ansible, Connect REST API, Prometheus are mature)
