# Phase 11: Core Governance Roles - Research

**Researched:** 2026-04-08
**Domain:** Ansible roles for Confluent Platform topic lifecycle, schema registration, and RBAC provisioning via REST APIs
**Confidence:** HIGH

## Summary

Phase 11 builds three standalone Ansible roles (`cp_topic`, `cp_schema`, `cp_rbac`) that use `ansible.builtin.uri` to interact with Confluent Platform REST APIs for topic CRUD, schema registration, and MDS RBAC binding management. All three roles must enforce identical governance rules to the existing Terraform module (`modules/topic/main.tf`) using the filter plugins and governance constants established in Phase 10.

The research confirms three distinct REST APIs are involved: (1) the Kafka Admin REST v3 API embedded in Confluent Server brokers for topic operations, (2) the Schema Registry REST API for schema registration and compatibility checking, and (3) the Metadata Service (MDS) REST API for RBAC role binding management. Each API has different authentication mechanisms, idempotency characteristics, and check-mode implications that directly affect role design.

A critical finding is that `ansible.builtin.uri` does NOT support Ansible check mode natively -- it will be skipped entirely in check mode. All three roles must implement check mode manually using the `ansible_check_mode` magic variable: performing GET operations to gather current state, computing diffs, and reporting what would change without making mutations. Additionally, the MDS bearer token has a configurable TTL (default 1 hour via `confluent.metadata.server.token.max.lifetime.ms`, though deployments commonly set shorter values like 15-30 minutes). The RBAC role must handle token refresh for long-running playbooks.

**Primary recommendation:** Build each role as a self-contained unit following the established `scenarios/cp-rhel/roles/flink_standalone/` pattern (defaults/main.yml, tasks/main.yml, handlers/main.yml), with shared test fixtures in `tests/ansible/fixtures/`. Use the Phase 10 governance filter plugins (`fsi_topic_name`, `fsi_sla_lookup`, `fsi_validate_topic_name`) and governance constants (`ansible/vars/sla_tiers.yml`, `ansible/vars/naming_rules.yml`) as the canonical governance enforcement layer.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- When processing multiple topics/schemas/bindings, collect all errors and report at end with summary (do not fail fast on first error) -- matches Terraform's plan-all-then-apply pattern
- Transient API errors (503, connection timeout) get 3 retries with exponential backoff using uri module's native retry (`retries: 3, delay: 5, until: result.status == 200`)
- Check mode gathers current state via GET per resource individually (not bulk listing) -- compare declared vs actual config, report diff
- Molecule tests use delegated driver with Python HTTP mock server -- lightweight pytest fixture starts a mock CP API returning realistic responses (no Docker overhead, fast CI)
- Shared test fixtures in `tests/ansible/fixtures/` across all roles -- mock API responses, sample CPTopic YAMLs (aligns with existing `tests/ansible/` from Phase 10)
- Idempotency verification = second converge reports zero `changed` tasks via molecule's built-in idempotence test
- Roles register output variables with results (`cp_topic_results`, `cp_schema_results`, `cp_rbac_results`) containing created/updated/failed counts for downstream orchestration (Phase 12 needs this)
- Schema role reuses existing `ci/scripts/validate-schemas.py` via command module (ASCHEMA-04) -- avoids duplicating validation logic
- Roles accept both `cp_topics_dir` (YAML glob for CPTopic files, standard use per ATOPIC-03) and `cp_topics` list (inline variables for programmatic/orchestration use)

### Claude's Discretion
- Internal task ordering within roles (e.g., GET-before-POST sequence, token acquisition flow)
- Exact mock API response structures for molecule tests
- Variable naming within roles beyond the registered output variables

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ATOPIC-01 | Create topics on CP cluster via Ansible role using Admin REST v3 API with idempotent GET-before-POST pattern | Admin REST v3 API section documents GET `/clusters/{id}/topics/{name}` + POST `/clusters/{id}/topics` endpoints and request body format |
| ATOPIC-02 | Topic configuration automatically derived from SLA tier using shared governance constants | Phase 10 filter plugin `fsi_sla_lookup` provides O(1) lookups; `sla_tiers.yml` has partitions, retention_ms, min_insync_replicas, compatibility per tier |
| ATOPIC-03 | Role consumes existing CPTopic YAML format from `scenarios/cp-rhel/topics/*.yml` | CPTopic YAML format documented with apiVersion/kind/metadata/spec structure; existing files serve as both input spec and test fixtures |
| ATOPIC-04 | Role validates topic names against naming regex before API calls | Phase 10 filter plugin `fsi_validate_topic_name` provides validation; role uses it as pre-flight check |
| ATOPIC-05 | Topic config updates converge to declared state without recreating topics | Admin REST v3 POST `/clusters/{id}/topics/{name}/configs:alter` with SET operation updates individual configs idempotently |
| ATOPIC-06 | Running playbook in `--check` mode shows what would change without mutations | `ansible.builtin.uri` does NOT support check_mode natively; role must implement manually using `ansible_check_mode` variable |
| ATOPIC-07 | Topic deletion requires `state: absent` + `confirm_deletion: true`, blocks critical/compliance tier deletion | DELETE `/clusters/{id}/topics/{name}` endpoint; role adds safeguard logic with SLA tier check |
| ASCHEMA-01 | Register Avro schemas to CP Schema Registry via Ansible role | SR REST API POST `/subjects/{subject}/versions` with schema body, schemaType, metadata documented |
| ASCHEMA-02 | Compatibility pre-check before registration with two-pass pattern | SR REST API POST `/compatibility/subjects/{subject}/versions/latest` returns `{is_compatible, messages}` |
| ASCHEMA-03 | Schema compatibility mode per subject set from SLA tier | SR REST API PUT `/config/{subject}` with `{compatibility: "MODE"}` body; `fsi_sla_lookup` provides tier-to-mode mapping |
| ASCHEMA-04 | Reuse existing `ci/scripts/validate-schemas.py` for structural validation | Script validated -- accepts `--schemas-dir` argument, validates JSON structure, namespace, field requirements |
| ASCHEMA-05 | PII metadata properties applied to SR subjects matching Terraform metadata pattern | SR REST API accepts `metadata.properties` flat key-value map during registration; Terraform `schema_metadata` local provides the property names to mirror |
| ARBAC-01 | Provision per-topic RBAC bindings via MDS REST API | MDS POST `/security/1.0/principals/{principal}/roles/{role}/bindings` with scope and resourcePatterns documented |
| ARBAC-02 | MDS bearer token with automatic refresh handling | MDS GET `/security/1.0/authenticate` returns `{auth_token, token_type, expires_in}`; default TTL configurable via `confluent.metadata.server.token.max.lifetime.ms` |
| ARBAC-03 | Consumer group bindings created alongside topic bindings | MDS resourcePatterns support `{resourceType: "Group", name: "{principal}-*", patternType: "PREFIXED"}` pattern |
| ARBAC-04 | Schema Registry subject bindings created alongside topic bindings | MDS scope includes `schema-registry-cluster` in clusters object; resourcePatterns use `{resourceType: "Subject"}` |
| ARBAC-05 | LIST/DIFF/ADD/REMOVE reconciliation to prevent RBAC drift | MDS POST `/security/1.0/principals/{principal}/roles/{role}/resources` lists current bindings; DELETE `/security/1.0/principals/{principal}/roles/{role}/bindings` removes specific bindings |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Deployment parity**: Core governance (topic naming, schema compat, RBAC) must work identically across all deployment models -- Ansible roles MUST produce identical governance outcomes to Terraform module
- **No custom Python modules**: `ansible.builtin.uri` for all REST API operations (STATE.md decision); filter plugins are allowed (Jinja2 filters, not action modules)
- **Standalone roles**: Not Galaxy collection -- roles tightly coupled to repo governance data
- **CP 7.7.x target**: cp-ansible 7.7.x collection; Admin REST v3 API, SR REST API, MDS REST API are all available in CP 7.7
- **FQCN required**: All module references must use `ansible.builtin.uri`, `ansible.builtin.set_fact`, etc.
- **Commit messages**: conventional commit format
- **Python 3**: Standard for CI/CD validation scripts

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ansible.builtin.uri | ansible-core 2.15 | All REST API interactions (topic, schema, RBAC) | Project decision: uri over custom modules |
| ansible.builtin.include_vars | ansible-core 2.15 | Load governance constants from YAML | Standard Ansible pattern for shared vars |
| fsi_governance filter plugin | Phase 10 output | Topic name validation, SLA tier lookups | Centralized governance logic matching Terraform |
| pytest | 8.4.2 | Test framework for role unit tests and mock API | Already installed, used by Phase 10 tests |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ansible.builtin.command | ansible-core 2.15 | Invoke `ci/scripts/validate-schemas.py` for ASCHEMA-04 | Schema structural validation before SR API calls |
| ansible.builtin.find | ansible-core 2.15 | Glob CPTopic YAML files from directory | When `cp_topics_dir` is specified instead of `cp_topics` list |
| ansible.builtin.slurp / ansible.builtin.file | ansible-core 2.15 | Read CPTopic YAML and schema files | Loading file content for API payloads |
| ansible.builtin.set_fact | ansible-core 2.15 | Register output variables and intermediate state | Result aggregation for `cp_topic_results`, etc. |
| ansible.builtin.assert | ansible-core 2.15 | Pre-flight validation assertions | Fail-fast on governance violations before API calls |
| http.server (Python stdlib) | Python 3.9 | Mock HTTP server for molecule tests | Lightweight mock CP API for delegated driver tests |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ansible.builtin.uri | Custom Python action module | Project decision: uri for simplicity; custom modules add maintenance |
| Python http.server mock | Docker containers with real CP | Docker is heavy; delegated + mock is fast CI; user decision in CONTEXT.md |
| molecule test framework | Plain pytest with ansible-runner | Molecule provides idempotence testing natively; user decision |

## Architecture Patterns

### Recommended Project Structure
```
ansible/roles/
├── cp_topic/
│   ├── defaults/main.yml          # Default variable values
│   ├── tasks/
│   │   ├── main.yml               # Entry point: load vars, validate, loop topics
│   │   ├── validate.yml           # Pre-flight governance validation
│   │   ├── create.yml             # GET-before-POST topic creation
│   │   ├── update.yml             # Config convergence (alter configs)
│   │   ├── delete.yml             # Guarded deletion with confirmation
│   │   └── check.yml              # Check-mode state diff (GET-only)
│   ├── meta/main.yml              # Role metadata (Galaxy-style)
│   └── molecule/
│       └── default/
│           ├── molecule.yml        # Delegated driver config
│           ├── converge.yml        # Test playbook
│           └── verify.yml          # Verification playbook
├── cp_schema/
│   ├── defaults/main.yml
│   ├── tasks/
│   │   ├── main.yml               # Entry point: load vars, validate, register
│   │   ├── validate.yml           # Structural validation via validate-schemas.py
│   │   ├── compatibility.yml      # Compatibility pre-check pass
│   │   ├── register.yml           # Schema registration pass
│   │   └── check.yml              # Check-mode compatibility report
│   ├── meta/main.yml
│   └── molecule/
│       └── default/
│           ├── molecule.yml
│           ├── converge.yml
│           └── verify.yml
├── cp_rbac/
│   ├── defaults/main.yml
│   ├── tasks/
│   │   ├── main.yml               # Entry point: authenticate, reconcile bindings
│   │   ├── authenticate.yml       # MDS token acquisition and refresh
│   │   ├── topic_bindings.yml     # Per-topic producer/consumer bindings
│   │   ├── group_bindings.yml     # Consumer group prefix bindings
│   │   ├── sr_bindings.yml        # Schema Registry subject bindings
│   │   ├── reconcile.yml          # LIST/DIFF/ADD/REMOVE stale binding cleanup
│   │   └── check.yml              # Check-mode binding diff report
│   ├── meta/main.yml
│   └── molecule/
│       └── default/
│           ├── molecule.yml
│           ├── converge.yml
│           └── verify.yml

tests/ansible/
├── fixtures/                       # Shared test fixtures
│   ├── mock_responses/             # Mock CP API response JSON files
│   │   ├── admin_rest_v3/          # Topic API responses
│   │   ├── schema_registry/        # SR API responses
│   │   └── mds/                    # MDS API responses
│   └── cptopic_samples/            # Sample CPTopic YAML files for testing
├── conftest.py                     # Shared test configuration (existing)
├── test_fsi_governance_filter.py   # Existing Phase 10 tests
├── test_governance_parity.py       # Existing Phase 10 tests
└── test_requirements.py            # Existing Phase 10 tests
```

### Pattern 1: GET-Before-POST Idempotent Topic Creation
**What:** Before creating any resource, GET its current state. If it exists and matches desired state, skip. If it exists with different config, update. If absent, create.
**When to use:** Every topic creation, schema registration, and RBAC binding operation.
**Example:**
```yaml
# 1. GET current topic state
- name: "Check if topic {{ topic_name }} exists"
  ansible.builtin.uri:
    url: "{{ cp_admin_rest_url }}/kafka/v3/clusters/{{ cp_cluster_id }}/topics/{{ topic_name }}"
    method: GET
    headers:
      Authorization: "Bearer {{ mds_token }}"
    status_code: [200, 404]
    return_content: true
  register: topic_check
  when: not ansible_check_mode

# 2. Create if absent
- name: "Create topic {{ topic_name }}"
  ansible.builtin.uri:
    url: "{{ cp_admin_rest_url }}/kafka/v3/clusters/{{ cp_cluster_id }}/topics"
    method: POST
    headers:
      Authorization: "Bearer {{ mds_token }}"
      Content-Type: "application/json"
    body_format: json
    body:
      topic_name: "{{ topic_name }}"
      partitions_count: "{{ topic_partitions }}"
      replication_factor: "{{ cp_replication_factor | default(3) }}"
      configs:
        - name: "retention.ms"
          value: "{{ topic_retention_ms | string }}"
        - name: "min.insync.replicas"
          value: "{{ topic_min_isr | string }}"
        - name: "cleanup.policy"
          value: "{{ topic_cleanup_policy | default('delete') }}"
    status_code: [200, 201]
  when:
    - not ansible_check_mode
    - topic_check.status == 404
  register: topic_create
```

### Pattern 2: Manual Check Mode Implementation
**What:** Since `ansible.builtin.uri` does not support check mode, the role must use `ansible_check_mode` to branch between read-only GET operations (check mode) and mutating POST/PUT/DELETE operations (normal mode).
**When to use:** All three roles for ATOPIC-06.
**Example:**
```yaml
# In main.yml entry point
- name: "Run check-mode state gathering"
  ansible.builtin.include_tasks: check.yml
  when: ansible_check_mode

- name: "Run normal-mode operations"
  ansible.builtin.include_tasks: create.yml
  when: not ansible_check_mode

# In check.yml
- name: "GET current topic state for diff"
  ansible.builtin.uri:
    url: "{{ cp_admin_rest_url }}/kafka/v3/clusters/{{ cp_cluster_id }}/topics/{{ topic_name }}"
    method: GET
    headers:
      Authorization: "Bearer {{ mds_token }}"
    status_code: [200, 404]
    return_content: true
  check_mode: false   # Force execution even in check mode (GET is safe)
  register: current_state

- name: "Report planned changes for {{ topic_name }}"
  ansible.builtin.debug:
    msg: >-
      WOULD {{ 'CREATE' if current_state.status == 404 else 'UPDATE' }}
      topic '{{ topic_name }}' with partitions={{ desired_partitions }},
      retention.ms={{ desired_retention }}
  changed_when: current_state.status == 404 or configs_differ
```

### Pattern 3: Error Collection and Summary Reporting
**What:** Process all items in a loop, collecting errors as you go, then report a summary at the end. Do not fail on the first error.
**When to use:** All three roles when processing multiple topics/schemas/bindings per the locked decision.
**Example:**
```yaml
- name: "Process topics"
  ansible.builtin.include_tasks: create.yml
  loop: "{{ topics_to_process }}"
  loop_control:
    loop_var: topic_item
  register: topic_results
  ignore_errors: true

- name: "Build results summary"
  ansible.builtin.set_fact:
    cp_topic_results:
      created: "{{ topic_results.results | selectattr('changed', 'equalto', true) | list | length }}"
      failed: "{{ topic_results.results | selectattr('failed', 'equalto', true) | list | length }}"
      unchanged: "{{ topic_results.results | rejectattr('changed') | rejectattr('failed') | list | length }}"
      errors: "{{ topic_results.results | selectattr('failed', 'equalto', true) | map(attribute='msg') | list }}"

- name: "Report failures"
  ansible.builtin.fail:
    msg: "{{ cp_topic_results.failed }} topic operations failed: {{ cp_topic_results.errors | join(', ') }}"
  when: cp_topic_results.failed | int > 0
```

### Pattern 4: MDS Token Acquisition and Refresh
**What:** Acquire MDS bearer token at role start, track expiry, refresh before it expires during long playbook runs.
**When to use:** cp_rbac role; also cp_topic and cp_schema if Admin REST/SR require MDS auth (depends on CP security config).
**Example:**
```yaml
# authenticate.yml
- name: "Acquire MDS bearer token"
  ansible.builtin.uri:
    url: "{{ cp_mds_url }}/security/1.0/authenticate"
    method: GET
    url_username: "{{ cp_mds_username }}"
    url_password: "{{ cp_mds_password }}"
    force_basic_auth: true
    return_content: true
    status_code: [200]
  register: mds_auth
  no_log: true

- name: "Store token and compute expiry"
  ansible.builtin.set_fact:
    mds_token: "{{ mds_auth.json.auth_token }}"
    mds_token_expires_at: "{{ ansible_date_time.epoch | int + mds_auth.json.expires_in | int - 60 }}"
  no_log: true

# Token refresh check (include before each API call block)
- name: "Refresh MDS token if near expiry"
  ansible.builtin.include_tasks: authenticate.yml
  when: ansible_date_time.epoch | int >= mds_token_expires_at | int
```

### Pattern 5: Two-Pass Schema Registration (ASCHEMA-02)
**What:** First pass validates compatibility for ALL schemas, collecting errors. Second pass registers only if all passed compatibility checks.
**When to use:** cp_schema role to prevent partial registration leaving the system in an inconsistent state.
**Example:**
```yaml
# Pass 1: Compatibility check all schemas
- name: "Check compatibility for all schemas"
  ansible.builtin.include_tasks: compatibility.yml
  loop: "{{ schemas_to_register }}"
  loop_control:
    loop_var: schema_item
  register: compat_results

# Fail if any incompatible
- name: "Fail if any schemas are incompatible"
  ansible.builtin.fail:
    msg: "Schema compatibility failures: {{ failures | join(', ') }}"
  vars:
    failures: "{{ compat_results.results | selectattr('failed', 'equalto', true) | map(attribute='msg') | list }}"
  when: failures | length > 0

# Pass 2: Register all schemas
- name: "Register all compatible schemas"
  ansible.builtin.include_tasks: register.yml
  loop: "{{ schemas_to_register }}"
  loop_control:
    loop_var: schema_item
```

### Anti-Patterns to Avoid
- **Hardcoding governance values in roles:** Always use `fsi_sla_lookup` filter or `include_vars` from `ansible/vars/sla_tiers.yml`. Never duplicate partition counts, retention values, or compatibility modes in role defaults.
- **Failing fast on first error:** The locked decision requires collecting all errors. Use `ignore_errors: true` on item-level tasks and aggregate results.
- **Skipping check mode:** `ansible.builtin.uri` does not support check mode natively -- the role must handle this explicitly or CAB approvals (ATOPIC-06) are impossible.
- **Hardcoding MDS token TTL:** The `expires_in` field in the authenticate response is the actual TTL. Do not assume 15 minutes or any fixed value -- read it from the response.
- **Using short module names:** ansible-lint enforces FQCN. Use `ansible.builtin.uri` not `uri`.
- **Putting secrets in role defaults:** All credentials should be referenced via variables passed at runtime (inventory group_vars, Vault, extra vars). Role defaults should use empty string defaults for credentials.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Topic name validation | Custom regex in each role task | `fsi_validate_topic_name` filter from Phase 10 | Central maintenance, tested, matches Terraform exactly |
| SLA tier property lookups | Nested `when:` conditionals per tier | `fsi_sla_lookup` filter from Phase 10 | Eliminates error-prone conditional chains |
| Schema structural validation | Inline Ansible tasks checking JSON | `ci/scripts/validate-schemas.py` via command module | Already proven in CI, validates namespace + fields + type |
| HTTP retry with backoff | Custom retry loops in YAML | Task-level `retries:`, `delay:`, `until:` directives | Built-in Ansible; user decision in CONTEXT.md |
| Topic name assembly | String concatenation in templates | `fsi_topic_name` filter from Phase 10 | Validates each component against regex during assembly |
| Token refresh timing | Fixed `pause:` tasks | Timestamp comparison using `ansible_date_time.epoch` vs `expires_in` | Adapts to actual token TTL from MDS response |

**Key insight:** Phase 10 built the governance layer precisely so Phase 11 roles can focus on API orchestration. The roles should be thin wrappers around REST API calls with governance enforcement delegated to the filter plugin and shared vars.

## Common Pitfalls

### Pitfall 1: ansible.builtin.uri Does Not Support Check Mode
**What goes wrong:** Role skips all uri tasks in `--check` mode, reporting no changes when it should report planned changes for CAB approval (ATOPIC-06).
**Why it happens:** The uri module's check_mode attribute is not supported -- Ansible skips the task entirely.
**How to avoid:** Implement dual-path task flow: `check.yml` for GET-only operations using `check_mode: false` to force execution, `create.yml`/`update.yml`/`delete.yml` for mutations gated by `when: not ansible_check_mode`. Report planned changes via `ansible.builtin.debug` with `changed_when` to signal diffs.
**Warning signs:** Running `ansible-playbook --check` produces zero output for topic/schema/RBAC tasks.

### Pitfall 2: Admin REST v3 Config Update Requires String Values
**What goes wrong:** Topic config update fails because `retention.ms` is sent as integer instead of string.
**Why it happens:** The Admin REST v3 `configs:alter` endpoint expects config values as strings in the JSON body, but Ansible's `body_format: json` will serialize integers as JSON numbers.
**How to avoid:** Always cast config values to string: `value: "{{ topic_retention_ms | string }}"`. The `sla_tiers.yml` stores retention_ms as integers for computation, but the API call must stringify them.
**Warning signs:** 400 Bad Request from Admin REST API with unhelpful error message about config value type.

### Pitfall 3: MDS Token Expiry During Long Playbook Runs
**What goes wrong:** RBAC operations fail with 401 midway through a playbook processing many topics.
**Why it happens:** MDS bearer token expires (default TTL configurable, commonly 15-60 minutes). A playbook creating bindings for 50+ topics may exceed this.
**How to avoid:** Store the `expires_in` value from the authenticate response, compute an absolute expiry timestamp (with 60-second safety margin), and re-authenticate before each operation block if the current time exceeds the threshold.
**Warning signs:** First N RBAC operations succeed, then sudden 401 errors.

### Pitfall 4: Schema Metadata Properties Require Confluent Enterprise
**What goes wrong:** Schema registration with `metadata.properties` fails on Schema Registry.
**Why it happens:** The Data Contracts feature (metadata properties, tags, rulesets) requires Confluent Enterprise edition. Community edition SR does not support metadata.
**How to avoid:** Make metadata properties optional in the role -- skip the metadata field if `cp_schema_metadata_enabled` is false (default: true for CP Enterprise). Include a pre-flight check that tests SR for Data Contracts support.
**Warning signs:** HTTP 422 or unexpected error when registering schema with metadata field.

### Pitfall 5: RBAC Drift from Stale Bindings
**What goes wrong:** Service accounts that have been removed from CPTopic YAML still retain their RBAC bindings, violating least-privilege.
**Why it happens:** The role only adds new bindings without checking for stale ones.
**How to avoid:** Implement the LIST/DIFF/ADD/REMOVE reconciliation pattern (ARBAC-05). GET existing bindings for the principal+role, compute the diff with desired state, add missing bindings, and remove stale ones. This is the most complex part of the RBAC role.
**Warning signs:** Removed service accounts can still produce/consume topics.

### Pitfall 6: Consumer Group Binding Pattern Type
**What goes wrong:** Consumer cannot join any consumer group because the binding uses LITERAL pattern instead of PREFIXED.
**Why it happens:** The Terraform module uses wildcard CRN patterns (`{sa}-*`), but the MDS REST API uses a different mechanism: `patternType: "PREFIXED"` in the resourcePatterns.
**How to avoid:** For consumer group bindings, use `patternType: "PREFIXED"` with `name: "{principal}-"` (not `{principal}-*`). The MDS API handles the prefix matching -- the `*` is implicit in the PREFIXED pattern type.
**Warning signs:** Consumer group binding created but consumer gets authorization failure when joining group.

### Pitfall 7: Schema Subject Naming Strategy Mismatch
**What goes wrong:** Schema registered under wrong subject name, so serializer/deserializer cannot find it.
**Why it happens:** The Terraform module uses TopicNameStrategy: `{topic_name}-value` and `{topic_name}-key`. If the role derives the subject name differently, it breaks schema lookup.
**How to avoid:** The role must derive subject names identically to `modules/topic/main.tf` lines 40-41: `value_subject = "{topic_name}-value"`, `key_subject = "{topic_name}-key"`. Use the same `fsi_topic_name` filter to assemble the topic name, then append `-value`/`-key`.
**Warning signs:** Schema registered successfully but producers/consumers get "subject not found" errors.

### Pitfall 8: CPTopic YAML spec.partitionCount vs SLA Tier Derivation
**What goes wrong:** Topic created with partitions from CPTopic YAML `spec.partitionCount` when it should be derived from SLA tier.
**Why it happens:** CPTopic YAML files include `partitionCount` for documentation, but governance rules say partitions come from SLA tier unless overridden.
**How to avoid:** SLA tier derivation takes precedence. If `spec.partitionCount` differs from SLA tier default, treat it as an explicit override (like Terraform's `partitions_override`). Document this precedence clearly in role README.
**Warning signs:** Topic created with wrong partition count relative to its SLA tier.

## Code Examples

Verified patterns from project codebase and official API documentation:

### CPTopic YAML Format (Input to cp_topic Role)
```yaml
# Source: scenarios/cp-rhel/topics/corebanking-account-txn.yml
apiVersion: platform.confluent.io/v1beta1
kind: CPTopic
metadata:
  name: corebanking.transactions.v1.account-transaction
  labels:
    fsi.domain: corebanking
    fsi.application: transactions
    fsi.version: v1
    fsi.entity: account-transaction
    fsi.sla-tier: critical
    fsi.owner: core-banking-team@company.com
    fsi.data-classification: internal
spec:
  partitionCount: 12
  configs:
    retention.ms: 604800000
    min.insync.replicas: 2
    cleanup.policy: delete
```

### Admin REST v3: Create Topic Request
```json
// POST /kafka/v3/clusters/{cluster_id}/topics
// Source: Confluent REST Proxy OpenAPI spec (GitHub)
{
  "topic_name": "corebanking.transactions.v1.account-transaction",
  "partitions_count": 12,
  "replication_factor": 3,
  "configs": [
    {"name": "retention.ms", "value": "604800000"},
    {"name": "min.insync.replicas", "value": "2"},
    {"name": "cleanup.policy", "value": "delete"},
    {"name": "compression.type", "value": "zstd"}
  ]
}
```

### Admin REST v3: Update Topic Configs
```json
// POST /kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs:alter
// Source: Confluent REST Proxy OpenAPI spec (GitHub)
{
  "data": [
    {"name": "retention.ms", "value": "604800000", "operation": "SET"},
    {"name": "min.insync.replicas", "value": "2", "operation": "SET"}
  ]
}
```

### Schema Registry: Register Schema with Metadata
```json
// POST /subjects/{subject}/versions
// Source: Confluent SR API Reference + Data Contracts docs
{
  "schema": "{\"type\":\"record\",\"name\":\"AccountTransaction\",\"namespace\":\"org.fsi.cncb.core.v1\",\"fields\":[...]}",
  "schemaType": "AVRO",
  "metadata": {
    "properties": {
      "owner": "core-banking-team@company.com",
      "sla-tier": "critical",
      "data-classification": "internal",
      "domain": "corebanking",
      "application": "transactions",
      "pii": "true",
      "pii-fields": "account_number,member_name,ssn_last4"
    }
  }
}
```

### Schema Registry: Compatibility Check
```json
// POST /compatibility/subjects/{subject}/versions/latest?verbose=true
// Source: Confluent SR API Usage Examples
// Request:
{
  "schema": "{\"type\":\"record\",...}",
  "schemaType": "AVRO"
}
// Response (compatible):
{"is_compatible": true, "messages": []}
// Response (incompatible):
{"is_compatible": false, "messages": ["Schemas are incompatible"]}
```

### Schema Registry: Set Subject Compatibility
```json
// PUT /config/{subject}
// Source: Confluent SR API Usage Examples
// Request:
{"compatibility": "FULL_TRANSITIVE"}
// Response:
{"compatibility": "FULL_TRANSITIVE"}
```

### MDS: Authenticate and Get Token
```bash
# GET /security/1.0/authenticate with Basic Auth
# Source: Confluent MDS API Reference
curl -u admin:password https://mds-host:8090/security/1.0/authenticate
# Response:
# {"auth_token": "eyJ...", "token_type": "BEARER", "expires_in": 3600}
```

### MDS: Create Resource-Level Role Binding
```json
// POST /security/1.0/principals/User:sa-producer/roles/DeveloperWrite/bindings
// Source: Confluent RBAC Config REST API docs
{
  "scope": {
    "clusters": {
      "kafka-cluster": "cluster-id-here"
    }
  },
  "resourcePatterns": [
    {
      "resourceType": "Topic",
      "name": "corebanking.transactions.v1.account-transaction",
      "patternType": "LITERAL"
    }
  ]
}
```

### MDS: Consumer Group Binding (PREFIXED Pattern)
```json
// POST /security/1.0/principals/User:sa-consumer/roles/DeveloperRead/bindings
{
  "scope": {
    "clusters": {
      "kafka-cluster": "cluster-id-here"
    }
  },
  "resourcePatterns": [
    {
      "resourceType": "Group",
      "name": "sa-consumer-",
      "patternType": "PREFIXED"
    }
  ]
}
```

### MDS: Schema Registry Subject Binding
```json
// POST /security/1.0/principals/User:sa-producer/roles/DeveloperWrite/bindings
{
  "scope": {
    "clusters": {
      "kafka-cluster": "cluster-id-here",
      "schema-registry-cluster": "schema-registry"
    }
  },
  "resourcePatterns": [
    {
      "resourceType": "Subject",
      "name": "corebanking.transactions.v1.account-transaction-value",
      "patternType": "LITERAL"
    }
  ]
}
```

### MDS: Delete Resource Bindings
```json
// DELETE /security/1.0/principals/User:sa-old-consumer/roles/DeveloperRead/bindings
// Same body format as POST -- specifies which bindings to remove
{
  "scope": {
    "clusters": {
      "kafka-cluster": "cluster-id-here"
    }
  },
  "resourcePatterns": [
    {
      "resourceType": "Topic",
      "name": "corebanking.transactions.v1.account-transaction",
      "patternType": "LITERAL"
    }
  ]
}
```

### Governance Filter Usage in Role Tasks
```yaml
# Using Phase 10 filters in role tasks
# Source: ansible/filter_plugins/fsi_governance.py (verified)

# Validate topic name from CPTopic metadata
- name: "Validate topic name governance"
  ansible.builtin.assert:
    that:
      - topic_item.metadata.name | fsi_validate_topic_name
    fail_msg: "Topic name '{{ topic_item.metadata.name }}' fails governance validation"
    quiet: true

# Look up SLA tier defaults
- name: "Derive partitions from SLA tier"
  ansible.builtin.set_fact:
    topic_partitions: "{{ topic_sla_tier | fsi_sla_lookup('partitions') }}"
    topic_retention_ms: "{{ topic_sla_tier | fsi_sla_lookup('retention_ms') }}"
    topic_compatibility: "{{ topic_sla_tier | fsi_sla_lookup('compatibility') }}"

# Assemble topic name from components
- name: "Assemble topic name"
  ansible.builtin.set_fact:
    topic_name: >-
      {{ {'domain': topic_item.metadata.labels['fsi.domain'],
          'application': topic_item.metadata.labels['fsi.application'],
          'version': topic_item.metadata.labels['fsi.version'],
          'entity': topic_item.metadata.labels['fsi.entity']}
         | fsi_topic_name }}
```

## REST API Reference Summary

### Admin REST v3 (Topic CRUD) -- Embedded in Confluent Server Brokers
| Operation | Method | Path | Auth | Status Codes |
|-----------|--------|------|------|-------------|
| List topics | GET | `/kafka/v3/clusters/{cluster_id}/topics` | Bearer/mTLS | 200 |
| Get topic | GET | `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}` | Bearer/mTLS | 200, 404 |
| Create topic | POST | `/kafka/v3/clusters/{cluster_id}/topics` | Bearer/mTLS | 200, 201 |
| Delete topic | DELETE | `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}` | Bearer/mTLS | 200, 204 |
| List topic configs | GET | `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs` | Bearer/mTLS | 200 |
| Alter topic configs | POST | `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs:alter` | Bearer/mTLS | 200, 204 |

**Base URL:** `https://{broker-host}:8090` (default Admin REST port on Confluent Server)
**Request body field names:** `topic_name`, `partitions_count`, `replication_factor`, `configs` (array of `{name, value}`)
**Config alter body:** `data` (array of `{name, value, operation}` where operation is SET or DELETE)

### Schema Registry REST API
| Operation | Method | Path | Auth | Status Codes |
|-----------|--------|------|------|-------------|
| Register schema | POST | `/subjects/{subject}/versions` | Basic/Bearer | 200 |
| Get latest schema | GET | `/subjects/{subject}/versions/latest` | Basic/Bearer | 200, 404 |
| Check compatibility | POST | `/compatibility/subjects/{subject}/versions/latest` | Basic/Bearer | 200, 404 |
| Get subject config | GET | `/config/{subject}` | Basic/Bearer | 200, 404 |
| Set subject config | PUT | `/config/{subject}` | Basic/Bearer | 200 |
| List subjects | GET | `/subjects` | Basic/Bearer | 200 |
| List versions | GET | `/subjects/{subject}/versions` | Basic/Bearer | 200, 404 |

**Base URL:** `https://{sr-host}:8081`
**Content-Type:** `application/vnd.schemaregistry.v1+json`
**Registration body:** `{schema (JSON-escaped string), schemaType, metadata: {properties: {}}, ruleSet: {}}`

### MDS REST API (RBAC Bindings)
| Operation | Method | Path | Auth | Status Codes |
|-----------|--------|------|------|-------------|
| Authenticate | GET | `/security/1.0/authenticate` | Basic | 200 |
| Create resource binding | POST | `/security/1.0/principals/{principal}/roles/{role}/bindings` | Bearer | 204 |
| Delete resource binding | DELETE | `/security/1.0/principals/{principal}/roles/{role}/bindings` | Bearer | 204 |
| Overwrite bindings | PUT | `/security/1.0/principals/{principal}/roles/{role}/bindings` | Bearer | 204 |
| List principal's resources | POST | `/security/1.0/principals/{principal}/roles/{role}/resources` | Bearer | 200 |
| List principal's roles | POST | `/security/1.0/lookup/principals/{principal}/roleNames` | Bearer | 200 |

**Base URL:** `https://{mds-host}:8090`
**Binding body:** `{scope: {clusters: {kafka-cluster: "id"}}, resourcePatterns: [{resourceType, name, patternType}]}`
**ResourceTypes:** Topic, Group, Subject, Cluster, TransactionalId, DelegationToken
**PatternTypes:** LITERAL, PREFIXED

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| kafka-topics.sh CLI for topic management | Admin REST v3 embedded in Confluent Server | CP 5.5+ | REST API enables programmatic management from Ansible without CLI installation on controller |
| Separate REST Proxy deployment for v3 API | Embedded Admin REST in broker (Confluent Server) | CP 6.0+ | No separate REST Proxy needed; API available on broker ports |
| ACLs-only access control | MDS RBAC with role bindings | CP 5.4+ | Role-based model matches organizational structure better; MDS REST API enables automation |
| Manual schema registration via CLI | SR REST API with metadata and Data Contracts | CP 7.0+ (metadata) | Metadata properties enable governance tagging at registration time |
| ansible-lint without profiles | ansible-lint profiles (shared, production) | ansible-lint 6.x+ | Profile-based enforcement is the current standard |

**Deprecated/outdated:**
- `kafka-topics.sh` for programmatic topic management: Use Admin REST v3 instead (no CLI needed on controller)
- ACLs for CP deployments with MDS: RBAC supersedes ACLs when MDS is enabled
- Schema Registry v1 content type without metadata: v1 still works but metadata requires full body with `metadata` field

## Open Questions

1. **Admin REST v3 port and authentication on CP 7.7**
   - What we know: Admin REST v3 is embedded in Confluent Server, typically on port 8090. Authentication can be mTLS or MDS bearer token.
   - What's unclear: Whether the Admin REST uses the same port/auth as MDS, or a separate listener. The STATE.md notes "Admin REST v3 config:alter request body needs confirmation" as a concern.
   - Recommendation: The role should accept separate `cp_admin_rest_url` and `cp_mds_url` variables (may be the same host/port, but allow separate configuration). The config:alter body format has been confirmed via OpenAPI spec: `{data: [{name, value, operation}]}`.

2. **MDS resource listing endpoint for reconciliation (ARBAC-05)**
   - What we know: `POST /security/1.0/principals/{principal}/roles/{role}/resources` lists resource bindings for a given principal and role.
   - What's unclear: Whether the response format includes `resourcePatterns` matching the request format, or a different structure. STATE.md notes "MDS REST API binding enumeration pattern needs validation against running CP 7.7 instance."
   - Recommendation: Build the reconciliation logic against the documented API. If the response format differs at runtime, the molecule mock tests will need adjustment. Flag this as a validation point during first integration test.

3. **Schema metadata property support on CP 7.7 Enterprise**
   - What we know: Data Contracts (metadata properties) require Confluent Enterprise. The feature was introduced around CP 7.0.
   - What's unclear: Whether all CP 7.7.x Enterprise installations have this enabled by default or if it requires additional license/configuration.
   - Recommendation: Make metadata a conditional feature in the schema role with `cp_schema_metadata_enabled: true` default. Include a pre-flight check.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Python 3 | Test framework, schema validation | Yes | 3.9.6 | -- |
| ansible-core | Role execution (not needed for implementation) | Yes | 2.15.13 | -- |
| pytest | Test execution | Yes | 8.4.2 | -- |
| ansible-lint | Lint validation | Yes | 6.22.2 | -- |
| PyYAML | YAML parsing in tests | Yes | 6.0.3 | -- |
| molecule | Role testing with delegated driver | No | -- | `pip install molecule` |

**Missing dependencies with no fallback:**
- None that block implementation. Roles are YAML/Jinja2 files; implementation does not require a running CP cluster.

**Missing dependencies with fallback:**
- `molecule`: Not installed locally. Required for running molecule test scenarios. Install via `pip install molecule` when executing tests. The role tests can also run as pure pytest tests against mock HTTP servers without molecule if needed.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.4.2 + molecule (delegated driver) |
| Config file | `tests/ansible/conftest.py` (existing from Phase 10) |
| Quick run command | `python3 -m pytest tests/ansible/ -x --tb=short` |
| Full suite command | `python3 -m pytest tests/ansible/ -v` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ATOPIC-01 | Idempotent topic creation via Admin REST v3 | unit + molecule | `python3 -m pytest tests/ansible/test_cp_topic.py -x` | Wave 0 |
| ATOPIC-02 | SLA tier derivation for topic config | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_sla_tier_derivation -x` | Wave 0 |
| ATOPIC-03 | CPTopic YAML consumption | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_cptopic_yaml_parsing -x` | Wave 0 |
| ATOPIC-04 | Topic name validation before API calls | unit | Covered by existing `test_fsi_governance_filter.py` (Phase 10) | Existing |
| ATOPIC-05 | Config convergence without recreation | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_config_update -x` | Wave 0 |
| ATOPIC-06 | Check mode shows planned changes | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_check_mode -x` | Wave 0 |
| ATOPIC-07 | Guarded deletion with tier protection | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_deletion_guards -x` | Wave 0 |
| ASCHEMA-01 | Schema registration via SR REST API | unit + molecule | `python3 -m pytest tests/ansible/test_cp_schema.py -x` | Wave 0 |
| ASCHEMA-02 | Two-pass compatibility pre-check | unit | `python3 -m pytest tests/ansible/test_cp_schema.py::test_compatibility_check -x` | Wave 0 |
| ASCHEMA-03 | Subject compatibility from SLA tier | unit | `python3 -m pytest tests/ansible/test_cp_schema.py::test_compatibility_mode -x` | Wave 0 |
| ASCHEMA-04 | Reuse validate-schemas.py | unit | `python3 -m pytest tests/ansible/test_cp_schema.py::test_schema_validation -x` | Wave 0 |
| ASCHEMA-05 | PII metadata properties on subjects | unit | `python3 -m pytest tests/ansible/test_cp_schema.py::test_metadata_properties -x` | Wave 0 |
| ARBAC-01 | Per-topic RBAC bindings via MDS | unit + molecule | `python3 -m pytest tests/ansible/test_cp_rbac.py -x` | Wave 0 |
| ARBAC-02 | MDS token refresh | unit | `python3 -m pytest tests/ansible/test_cp_rbac.py::test_token_refresh -x` | Wave 0 |
| ARBAC-03 | Consumer group bindings (PREFIXED) | unit | `python3 -m pytest tests/ansible/test_cp_rbac.py::test_group_bindings -x` | Wave 0 |
| ARBAC-04 | SR subject bindings | unit | `python3 -m pytest tests/ansible/test_cp_rbac.py::test_sr_bindings -x` | Wave 0 |
| ARBAC-05 | Reconciliation (remove stale bindings) | unit | `python3 -m pytest tests/ansible/test_cp_rbac.py::test_reconciliation -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `python3 -m pytest tests/ansible/ -x --tb=short`
- **Per wave merge:** `python3 -m pytest tests/ansible/ -v`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/ansible/test_cp_topic.py` -- unit tests for cp_topic role logic
- [ ] `tests/ansible/test_cp_schema.py` -- unit tests for cp_schema role logic
- [ ] `tests/ansible/test_cp_rbac.py` -- unit tests for cp_rbac role logic
- [ ] `tests/ansible/fixtures/mock_responses/` -- mock CP API response JSON files
- [ ] `tests/ansible/fixtures/cptopic_samples/` -- sample CPTopic YAML for testing (can copy from `scenarios/cp-rhel/topics/`)
- [ ] molecule installation: `pip install molecule` (for running molecule test scenarios)

## Sources

### Primary (HIGH confidence)
- `modules/topic/main.tf` -- SLA tier maps, topic config, RBAC binding patterns (read directly)
- `modules/topic/variables.tf` -- Topic naming regex, SLA tier enum, cleanup policy (read directly)
- `ansible/filter_plugins/fsi_governance.py` -- Phase 10 governance filters (read directly)
- `ansible/vars/sla_tiers.yml` -- Governance constants with min_insync_replicas (read directly)
- `ansible/vars/naming_rules.yml` -- Topic naming regex patterns (read directly)
- `scenarios/cp-rhel/topics/*.yml` -- CPTopic YAML format (3 files read directly)
- `ci/scripts/validate-schemas.py` -- Schema validation script interface (read directly)
- [Confluent REST Proxy OpenAPI spec](https://github.com/confluentinc/kafka-rest/blob/master/api/v3/openapi.yaml) -- Admin REST v3 topic endpoints confirmed
- [Confluent SR API Reference](https://docs.confluent.io/platform/current/schema-registry/develop/api.html) -- SR REST endpoints and body formats
- [Confluent MDS API Reference](https://docs.confluent.io/platform/current/security/authorization/rbac/mds-api.html) -- MDS REST endpoints for RBAC
- [ansible.builtin.uri module docs](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html) -- Module parameters and check_mode status

### Secondary (MEDIUM confidence)
- [Confluent RBAC REST API config guide](https://docs.confluent.io/platform/current/security/authorization/rbac/rbac-config-using-rest-api.html) -- MDS authentication curl examples
- [Confluent SR Usage Examples](https://docs.confluent.io/platform/current/schema-registry/develop/using.html) -- Schema registration and compatibility check examples
- [Confluent Data Contracts docs](https://docs.confluent.io/platform/current/schema-registry/fundamentals/data-contracts.html) -- metadata.properties format confirmed as flat key-value map
- [Confluent MDS Configuration](https://docs.confluent.io/platform/current/kafka/configure-mds/mds-configuration.html) -- `token.max.lifetime.ms` default 3600000ms (1 hour)

### Tertiary (LOW confidence)
- MDS token TTL "15 minutes" from CONTEXT.md -- the CONTEXT.md states 15 minutes but official docs show configurable default of 1 hour. Actual value depends on deployment configuration. Role must read `expires_in` from authenticate response rather than assuming any fixed value.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- ansible.builtin.uri is the project decision; Phase 10 governance filters verified with 48 passing tests
- Architecture: HIGH -- role structure follows established `flink_standalone` pattern; REST API endpoints confirmed via OpenAPI spec and official docs
- Pitfalls: HIGH -- check_mode limitation verified against official module docs; config value stringification is a known REST API pattern; MDS token expiry documented in MDS configuration reference

**Research date:** 2026-04-08
**Valid until:** 2026-05-08 (30 days -- stable domain; CP 7.7.x REST APIs are mature and unlikely to change)
