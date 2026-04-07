# Architecture Patterns: Ansible Integration for CP Governance

**Domain:** Ansible-native governance automation for Confluent Platform (v2.0 milestone)
**Researched:** 2026-04-07
**Overall Confidence:** MEDIUM-HIGH (cp-ansible docs + MDS REST API docs + existing codebase analysis + community patterns)

## Recommended Architecture

The `ansible/` directory sits alongside existing `modules/` (Terraform) and `scenarios/` as a **peer automation surface**. It does NOT replace any existing content. The architecture follows a **standalone roles with shared governance data** pattern: Ansible roles consume the same governance constants (SLA tier maps, naming regex, compatibility mappings) as the Terraform module but implement them natively using `ansible.builtin.uri` against Confluent REST APIs (Admin REST v3 for topics, Schema Registry REST for schemas, MDS REST for RBAC).

```
fsi-kafka-platform/
|
|-- ansible/                               # NEW: Ansible-native automation
|   |-- roles/                             # Reusable roles (not a collection)
|   |   |-- cp_topic/                      # Topic lifecycle via Admin REST API v3
|   |   |-- cp_schema/                     # Schema registration via SR REST API
|   |   |-- cp_rbac/                       # RBAC bindings via MDS REST API
|   |   |-- cp_service_account/            # SA provisioning via MDS
|   |   |-- cp_observability/              # JMX exporter + dashboard deployment
|   |   |-- cp_dr_mm2/                     # DR failover/failback via MM2
|   |   |-- cp_dr_mrc/                     # DR failover/failback via MRC
|   |   +-- cp_connect/                    # Connect connector deployment
|   |
|   |-- playbooks/                         # Orchestration playbooks
|   |   |-- deploy-governance.yml          # Topic + schema + RBAC pipeline
|   |   |-- deploy-observability.yml       # JMX + dashboards
|   |   |-- deploy-connectors.yml          # Connect configuration
|   |   |-- dr-failover.yml               # DR failover orchestration
|   |   |-- dr-failback.yml               # DR failback orchestration
|   |   |-- dr-drill.yml                  # Full DR drill cycle
|   |   +-- site.yml                       # Full CP deployment (wraps cp-ansible + governance)
|   |
|   |-- inventories/                       # Per-environment inventories
|   |   |-- dev/
|   |   |   |-- hosts.yml
|   |   |   +-- group_vars/
|   |   |       |-- all.yml               # Cluster endpoints, auth
|   |   |       +-- vault.yml             # Encrypted credentials
|   |   |-- staging/
|   |   |   |-- hosts.yml
|   |   |   +-- group_vars/
|   |   |-- prod/
|   |   |   |-- hosts.yml
|   |   |   +-- group_vars/
|   |   +-- dr/
|   |       |-- hosts.yml                 # DR cluster inventory
|   |       +-- group_vars/
|   |
|   |-- vars/                              # Shared governance constants
|   |   |-- sla_tiers.yml                 # SLA tier maps (mirrored from TF)
|   |   |-- naming_rules.yml              # Naming regex patterns
|   |   +-- defaults.yml                  # Platform-wide defaults
|   |
|   |-- filter_plugins/                    # Custom Jinja2 filters
|   |   +-- fsi_governance.py             # Topic name assembly, SLA tier lookups
|   |
|   |-- molecule/                          # Test framework
|   |   |-- default/
|   |   |   |-- molecule.yml
|   |   |   |-- converge.yml
|   |   |   +-- verify.yml
|   |   +-- integration/
|   |       |-- molecule.yml
|   |       +-- converge.yml
|   |
|   |-- requirements.yml                   # Collection dependencies
|   |-- ansible.cfg                        # Project ansible config
|   +-- Makefile                           # Common targets: lint, test, deploy
|
|-- scenarios/cp-rhel/                     # EXISTING: updated to delegate to ansible/
|   |-- playbooks/deploy-cp.yml           # Unchanged: cluster deployment
|   |-- topics/                            # EXISTING: CPTopic YAML definitions
|   +-- inventory/                         # EXISTING: cp-ansible inventory
|
|-- modules/topic/                         # EXISTING: Terraform (CC only, unchanged)
|-- ci/scripts/validate-schemas.py         # EXISTING: Python schema validation (reused)
|-- ci/scripts/c4e-precheck.py            # EXISTING: Python governance checks (reused)
|-- schemas/                               # EXISTING: Avro schema library (shared)
+-- observability/                         # EXISTING: Dashboard templates (consumed by role)
```

### Key Architectural Decision: Standalone Roles, Not a Collection

**Decision:** Use standalone Ansible roles in `ansible/roles/` rather than packaging as a formal Ansible Collection (`fsi.kafka_platform`).

**Rationale:**
1. The roles are tightly coupled to this repository's governance constants, schemas, and Python validation scripts. Distributing them independently via Galaxy would create a maintenance burden of keeping two sources of truth synchronized.
2. Collections require plugins to live at the collection level, not inside roles. This complicates the `filter_plugins/` structure unnecessarily for internal use.
3. The primary consumer is this repository's own CI/CD and scenario playbooks, not external teams installing from Galaxy.
4. If Galaxy distribution becomes needed later, migrating standalone roles to a collection is straightforward (rename, move plugins up, add FQCN references).

**Confidence:** HIGH -- based on Ansible documentation guidance that collections are best for distribution, standalone roles for project-internal use.

### Key Architectural Decision: `uri` Module Over Custom Ansible Modules

**Decision:** Implement governance roles using `ansible.builtin.uri` for REST API calls, not custom Ansible modules.

**Rationale:**
1. The Confluent Platform exposes three stable REST APIs that cover all governance operations: Admin REST v3 (topics), Schema Registry REST (schemas), MDS REST 1.0 (RBAC). All are well-documented with stable endpoints.
2. Custom modules add Python packaging complexity (must work across Ansible control node Python versions) and a testing surface that `uri`-based tasks avoid.
3. The cp-ansible-admin community project validates this pattern -- it uses `uri` + `command` for all day-2 operations across topics, schemas, RBAC, ACLs, and quotas.
4. Complex logic (SLA tier derivation, naming validation) lives in filter plugins and `vars/` files, not in task YAML. The `uri` tasks stay simple: assemble URL, set headers, send body, check response.
5. One exception: `ansible.builtin.command` is needed for partition count increases (no REST API support yet) and for Confluent CLI operations not exposed via REST.

**Confidence:** HIGH -- based on Ansible best practices documentation, cp-ansible-admin project evidence, and Confluent REST API stability.

### Key Architectural Decision: Governance Data as Shared YAML

**Decision:** Extract governance constants (SLA tier maps, naming patterns, compatibility mappings) into `ansible/vars/sla_tiers.yml` and `ansible/vars/naming_rules.yml`, mirroring the Terraform `locals` blocks in `modules/topic/main.tf`.

**Rationale:**
1. Governance parity is a hard constraint -- Ansible must enforce identical rules as Terraform.
2. Extracting to YAML vars makes constants testable, auditable, and diffable against the Terraform source.
3. A CI job can validate that `ansible/vars/sla_tiers.yml` matches the maps in `modules/topic/main.tf` to prevent drift.

**Confidence:** HIGH -- this is the only approach that satisfies the governance parity constraint.

## Component Boundaries

### New Components

| Component | Responsibility | Communicates With | API Surface |
|-----------|---------------|-------------------|-------------|
| **cp_topic role** | Create/configure/validate Kafka topics on CP clusters | Admin REST v3 on broker:8090/kafka/v3 | POST/GET/PUT topics endpoint |
| **cp_schema role** | Register Avro schemas, set compatibility level, validate structure | SR REST on sr-host:8081 | POST /subjects/{subject}/versions, PUT /config/{subject} |
| **cp_rbac role** | Create/manage RBAC role bindings via MDS | MDS REST on broker:8090/security/1.0 | POST role bindings with bearer token |
| **cp_service_account role** | Provision LDAP/OIDC principals for MDS | MDS REST or LDAP admin API | Varies by auth_mode |
| **cp_observability role** | Deploy JMX exporter configs, import dashboards | Local file templating + dashboard API | File copy + provider REST APIs |
| **cp_dr_mm2 role** | Orchestrate MM2-based failover/failback | Connect REST on connect-host:8083 | POST/PUT connector configs |
| **cp_dr_mrc role** | Orchestrate MRC observer promotion | Confluent CLI (command module) | `confluent kafka replica` commands |
| **cp_connect role** | Deploy/configure connectors | Connect REST on connect-host:8083 | POST/PUT/DELETE connector configs |
| **filter_plugins/fsi_governance.py** | Jinja2 filters: topic name assembly, SLA tier lookup, naming validation | Used by all roles via `{{ var \| filter }}` | Python filter functions |
| **vars/sla_tiers.yml** | SLA tier governance constants | Consumed by cp_topic, cp_schema, cp_rbac | YAML data |

### Modified Components

| Component | Modification | Impact |
|-----------|-------------|--------|
| **scenarios/cp-rhel/** | Add reference to `ansible/` roles in README; optionally add an `ansible-governance.yml` playbook that imports governance roles | Low -- additive only |
| **ci/scripts/validate-schemas.py** | No code changes; called from `cp_schema` role via `ansible.builtin.command` for pre-registration validation | None -- reuse as-is |
| **ci/scripts/c4e-precheck.py** | No code changes; already parses CPTopic YAML from `scenarios/cp-rhel/topics/` | None -- reuse as-is |
| **.github/workflows/** | New workflow `ansible-lint.yml` for Ansible content; extends existing CI matrix | Low -- additive only |
| **observability/** | Dashboard JSON/YAML files consumed by `cp_observability` role via `ansible.builtin.copy`/`ansible.builtin.template` | None -- read-only consumption |
| **schemas/examples/** | Avro `.avsc` files consumed by `cp_schema` role for registration | None -- read-only consumption |

### Unchanged Components

| Component | Why Unchanged |
|-----------|---------------|
| **modules/topic/** | Terraform module stays for CC scenarios; CC has no Ansible path |
| **scripts/fsi-dr.sh** | Bash DR CLI continues to work for CC Cluster Linking; Ansible DR roles are CP-specific |
| **scenarios/cc-aws, cc-azure, cc-gcp** | Terraform-only scenarios |
| **scenarios/cfk-openshift/** | Gets its own Ansible governance playbook later (Phase 3 of milestone), but structure is planned now |
| **reference/** | Language-specific reference implementations are IaC-tool-agnostic |

## Data Flow

### Governance Pipeline (Primary Flow)

```
[CPTopic YAML definitions]     [Avro .avsc schemas]     [RBAC definitions]
  (scenarios/cp-rhel/topics/)    (schemas/examples/)      (inventory group_vars)
         |                              |                         |
         v                              v                         v
+-------------------+  +-------------------+  +-------------------+
| cp_topic role     |  | cp_schema role    |  | cp_rbac role      |
| 1. Load CPTopic   |  | 1. Run validate-  |  | 1. Auth to MDS    |
|    YAML           |  |    schemas.py     |  |    (bearer token) |
| 2. Apply SLA tier |  | 2. Register via   |  | 2. Create role    |
|    defaults       |  |    SR REST API    |  |    bindings per   |
| 3. Validate name  |  | 3. Set compat     |  |    topic          |
| 4. Create topic   |  |    level          |  | 3. Set consumer   |
|    via REST v3    |  | 4. Set metadata   |  |    group bindings  |
| 5. Verify config  |  |    properties     |  | 4. Set SR subject  |
+-------------------+  +-------------------+  |    bindings       |
         |                      |              +-------------------+
         v                      v                       |
  Admin REST v3         SR REST API (:8081)              v
  (:8090/kafka/v3)                                MDS REST API
                                                  (:8090/security/1.0)
```

### Full Deployment Pipeline (site.yml)

```
Phase 1: Cluster Deploy (cp-ansible)
  |-- confluent.platform roles: kafka_broker, schema_registry, kafka_connect
  |-- Already exists in scenarios/cp-rhel/playbooks/deploy-cp.yml
  v
Phase 2: Governance Apply (ansible/ roles)
  |-- cp_topic: create all topics from CPTopic YAML definitions
  |-- cp_schema: register schemas from schemas/examples/*.avsc
  |-- cp_rbac: apply RBAC bindings from inventory variables
  v
Phase 3: Observability Deploy
  |-- cp_observability: JMX exporter configs, dashboard imports
  v
Phase 4: Connect Deploy
  |-- cp_connect: deploy JDBC + custom connectors
  v
Phase 5: DR Setup (if multi-region)
  |-- cp_dr_mm2 or cp_dr_mrc: configure replication + validate
```

### Schema Validation Flow (Reusing Existing Python Scripts)

```
cp_schema role task sequence:
  1. ansible.builtin.command:
       cmd: "python3 {{ playbook_dir }}/../../ci/scripts/validate-schemas.py
              --schemas-dir {{ playbook_dir }}/../../schemas/"
     register: validation_result
     delegate_to: localhost
     -- Runs existing Python validation locally (no schema changes needed)

  2. ansible.builtin.uri:
       url: "{{ schema_registry_url }}/subjects/{{ subject_name }}/versions"
       method: POST
       body_format: json
       body:
         schema: "{{ lookup('file', schema_file) }}"
         schemaType: AVRO
       headers:
         Content-Type: "application/vnd.schemaregistry.v1+json"
       status_code: [200]
     -- Registers schema via SR REST API

  3. ansible.builtin.uri:
       url: "{{ schema_registry_url }}/config/{{ subject_name }}"
       method: PUT
       body_format: json
       body:
         compatibility: "{{ sla_tier_compatibility[sla_tier] }}"
       headers:
         Content-Type: "application/vnd.schemaregistry.v1+json"
     -- Sets compatibility level derived from SLA tier
```

## Patterns to Follow

### Pattern 1: SLA Tier Derivation via Shared Variables

Governance constants are extracted to `ansible/vars/sla_tiers.yml`, loaded by all governance roles via `include_vars`. This mirrors the Terraform `locals` block pattern.

**What:** Centralized SLA tier-to-config mapping consumed by all roles.
**When:** Any role that needs to derive topic config (partitions, retention, compatibility) from an SLA tier.
**Example:**

```yaml
# ansible/vars/sla_tiers.yml
# Source of truth for Ansible roles -- must stay in sync with modules/topic/main.tf locals
sla_tier_compatibility:
  critical: FULL_TRANSITIVE
  standard: BACKWARD_TRANSITIVE
  best-effort: BACKWARD
  compliance: FULL_TRANSITIVE

sla_tier_partitions:
  critical: 12
  standard: 6
  best-effort: 3
  compliance: 12

sla_tier_retention_ms:
  critical: 604800000      # 7 days
  standard: 259200000      # 3 days
  best-effort: 86400000    # 1 day
  # compliance: computed from retention_years variable
```

```yaml
# In cp_topic role tasks/main.yml
- name: Load governance constants
  ansible.builtin.include_vars:
    file: "{{ role_path }}/../../vars/sla_tiers.yml"

- name: Derive effective partition count
  ansible.builtin.set_fact:
    effective_partitions: >-
      {{ topic.partitions_override | default(sla_tier_partitions[topic.sla_tier], true) }}
    effective_retention_ms: >-
      {{ topic.retention_ms_override | default(sla_tier_retention_ms[topic.sla_tier], true) }}
    effective_compatibility: >-
      {{ topic.compatibility_override | default(sla_tier_compatibility[topic.sla_tier], true) }}
```

**Confidence:** HIGH -- directly mirrors existing Terraform logic with identical maps.

### Pattern 2: CPTopic YAML as Role Input

Topic definitions already exist as `CPTopic` YAML files in `scenarios/cp-rhel/topics/`. The `cp_topic` role reads these directly, extracting governance metadata from labels and spec fields.

**What:** Role consumes existing CPTopic YAML files instead of requiring a new input format.
**When:** All topic lifecycle operations.
**Example:**

```yaml
# In playbooks/deploy-governance.yml
- name: Discover CPTopic definitions
  ansible.builtin.find:
    paths: "{{ topics_dir | default('../../scenarios/cp-rhel/topics') }}"
    patterns: "*.yml,*.yaml"
  register: topic_files
  delegate_to: localhost

- name: Load topic definitions
  ansible.builtin.include_vars:
    file: "{{ item.path }}"
    name: "topic_def_{{ item.path | basename | regex_replace('[^a-zA-Z0-9]', '_') }}"
  loop: "{{ topic_files.files }}"

- name: Apply topic governance
  ansible.builtin.include_role:
    name: cp_topic
  vars:
    topic:
      name: "{{ item.metadata.name }}"
      sla_tier: "{{ item.metadata.labels['fsi.sla-tier'] }}"
      domain: "{{ item.metadata.labels['fsi.domain'] }}"
      owner: "{{ item.metadata.labels['fsi.owner'] }}"
      partitions: "{{ item.spec.partitionCount }}"
      configs: "{{ item.spec.configs }}"
  loop: "{{ discovered_topics }}"
```

**Confidence:** HIGH -- builds on the existing CPTopic format already used in the repository.

### Pattern 3: MDS Authentication with Token Caching

MDS requires bearer token authentication obtained via Basic Auth. The token should be obtained once per playbook run and cached as a fact.

**What:** Authenticate to MDS once, reuse token across all RBAC operations.
**When:** Any playbook that needs MDS (RBAC, SA management).
**Example:**

```yaml
# In cp_rbac role tasks/authenticate.yml
- name: Authenticate to MDS
  ansible.builtin.uri:
    url: "{{ mds_url }}/security/1.0/authenticate"
    method: POST
    user: "{{ mds_user }}"
    password: "{{ mds_password }}"
    force_basic_auth: true
    validate_certs: "{{ mds_validate_certs | default(true) }}"
    client_cert: "{{ mds_client_cert | default(omit) }}"
    client_key: "{{ mds_client_key | default(omit) }}"
    ca_path: "{{ mds_ca_cert | default(omit) }}"
    status_code: [200]
    return_content: true
  register: mds_auth_response
  no_log: true
  run_once: true

- name: Cache MDS bearer token
  ansible.builtin.set_fact:
    mds_bearer_token: "{{ mds_auth_response.json.auth_token }}"
  run_once: true
  no_log: true
```

**Confidence:** HIGH -- directly from Confluent MDS REST API documentation.

### Pattern 4: Idempotent Topic Creation

Topics should be checked before creation to ensure idempotency. The Admin REST v3 API returns 200 for existing topics, 409 for duplicate creation attempts.

**What:** Check topic existence before creating; update config if topic exists with different settings.
**When:** Topic lifecycle management.
**Example:**

```yaml
# In cp_topic role tasks/create.yml
- name: Check if topic exists
  ansible.builtin.uri:
    url: "{{ kafka_rest_url }}/kafka/v3/clusters/{{ cluster_id }}/topics/{{ topic.name }}"
    method: GET
    headers:
      Authorization: "Bearer {{ mds_bearer_token }}"
    status_code: [200, 404]
    validate_certs: "{{ validate_certs | default(true) }}"
  register: topic_check

- name: Create topic
  ansible.builtin.uri:
    url: "{{ kafka_rest_url }}/kafka/v3/clusters/{{ cluster_id }}/topics"
    method: POST
    headers:
      Authorization: "Bearer {{ mds_bearer_token }}"
      Content-Type: "application/json"
    body_format: json
    body:
      topic_name: "{{ topic.name }}"
      partitions_count: "{{ effective_partitions | int }}"
      replication_factor: "{{ replication_factor | default(3) }}"
      configs:
        - name: "retention.ms"
          value: "{{ effective_retention_ms }}"
        - name: "cleanup.policy"
          value: "{{ topic.cleanup_policy | default('delete') }}"
        - name: "compression.type"
          value: "zstd"
    status_code: [201]
  when: topic_check.status == 404

- name: Update topic config (if exists with different settings)
  ansible.builtin.uri:
    url: "{{ kafka_rest_url }}/kafka/v3/clusters/{{ cluster_id }}/topics/{{ topic.name }}/configs:alter"
    method: POST
    headers:
      Authorization: "Bearer {{ mds_bearer_token }}"
      Content-Type: "application/json"
    body_format: json
    body:
      data:
        - name: "retention.ms"
          value: "{{ effective_retention_ms }}"
        - name: "cleanup.policy"
          value: "{{ topic.cleanup_policy | default('delete') }}"
    status_code: [204]
  when: topic_check.status == 200
```

**Confidence:** MEDIUM -- Admin REST v3 topic endpoints confirmed; exact request body format for config alter needs validation against running CP instance.

### Pattern 5: Multi-Environment Inventory Separation

Each environment (dev, staging, prod, dr) gets its own inventory directory with environment-specific endpoints and credentials. Playbooks are shared across all environments.

**What:** Environment-specific configuration isolated to inventory directories.
**When:** All deployments -- dev through production.
**Example:**

```yaml
# ansible/inventories/prod/hosts.yml
all:
  vars:
    ansible_connection: local  # governance roles run from control node
  children:
    cp_cluster:
      hosts:
        prod-cp:
          kafka_rest_url: "https://kafka-broker-1.prod.fsi.org:8090"
          schema_registry_url: "https://sr-1.prod.fsi.org:8081"
          mds_url: "https://kafka-broker-1.prod.fsi.org:8090"
          cluster_id: "prod-cluster-abc123"
          validate_certs: true
```

```yaml
# ansible/inventories/prod/group_vars/vault.yml (encrypted)
mds_user: mds
mds_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...
schema_registry_user: sr-admin
schema_registry_password: !vault |
  ...
```

```bash
# Usage: target specific environment
ansible-playbook -i ansible/inventories/prod/ ansible/playbooks/deploy-governance.yml
ansible-playbook -i ansible/inventories/dev/ ansible/playbooks/deploy-governance.yml
```

**Confidence:** HIGH -- standard Ansible multi-environment pattern, well-documented.

### Pattern 6: Calling Existing Python Validation Scripts

Existing Python scripts (`ci/scripts/validate-schemas.py`, `ci/scripts/c4e-precheck.py`) are invoked from Ansible roles using `ansible.builtin.command` with `delegate_to: localhost`. No modification to the Python scripts is required.

**What:** Reuse existing validation logic without duplication.
**When:** Pre-registration schema validation, pre-deployment governance checks.
**Example:**

```yaml
# In cp_schema role tasks/validate.yml
- name: Run schema structure validation
  ansible.builtin.command:
    cmd: >-
      python3 {{ playbook_dir }}/../../ci/scripts/validate-schemas.py
      --schemas-dir {{ schemas_dir | default(playbook_dir + '/../../schemas/') }}
  delegate_to: localhost
  register: schema_validation
  changed_when: false
  failed_when: schema_validation.rc != 0

- name: Run C4E governance pre-checks
  ansible.builtin.command:
    cmd: >-
      python3 {{ playbook_dir }}/../../ci/scripts/c4e-precheck.py
      --scenario-dir {{ scenario_dir | default(playbook_dir + '/../../scenarios/cp-rhel/') }}
      --schemas-dir {{ schemas_dir | default(playbook_dir + '/../../schemas/') }}
  delegate_to: localhost
  register: c4e_precheck
  changed_when: false
  failed_when: c4e_precheck.rc != 0
```

**Confidence:** HIGH -- both scripts use stdlib-only Python and accept CLI arguments. No modifications needed.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Duplicating Governance Logic in Task YAML

**What:** Writing SLA tier derivation, naming validation, and compatibility mapping directly in Ansible tasks using complex `when` conditions and nested Jinja2.

**Why bad:** Creates a second source of truth. Governance rules in Terraform (`modules/topic/main.tf` locals) and Ansible tasks would drift independently. Changes require updates in two places with no automated cross-check.

**Instead:** Extract constants to `ansible/vars/sla_tiers.yml`. Use filter plugins for complex transformations. CI validates parity between YAML vars and Terraform locals.

### Anti-Pattern 2: Custom Ansible Modules for REST API Calls

**What:** Writing Python modules in `ansible/library/` that wrap Confluent REST APIs (e.g., `confluent_topic`, `confluent_schema`, `confluent_rbac`).

**Why bad:** Adds Python packaging complexity, version compatibility concerns, and a large testing surface. The REST APIs are stable and well-documented. Custom modules would be thin wrappers adding overhead without functionality.

**Instead:** Use `ansible.builtin.uri` for all REST calls. Put business logic in filter plugins and variable files.

### Anti-Pattern 3: Using confluent CLI for Everything

**What:** Implementing all operations via `ansible.builtin.command` calling `confluent` CLI.

**Why bad:** The CLI requires interactive login state, outputs human-readable text (fragile to parse), and adds a binary dependency to every control node. REST APIs return structured JSON and support proper authentication headers.

**Instead:** Use REST APIs via `uri` for topics, schemas, RBAC. Reserve CLI for the narrow cases where no REST API exists (partition count increase, MRC replica placement operations).

### Anti-Pattern 4: Combining cp-ansible Inventory with Governance Inventory

**What:** Merging governance role variables into `scenarios/cp-rhel/inventory/group_vars/` alongside cp-ansible deployment variables.

**Why bad:** cp-ansible inventory is designed for cluster deployment (package installation, service management, TLS config). Governance inventory is for API endpoints, credentials, and topic definitions. Mixing them creates confusion about which variables belong to which purpose and makes it hard to run governance roles independently of cluster deployment.

**Instead:** Separate inventory directories: `scenarios/cp-rhel/inventory/` for cp-ansible deployment, `ansible/inventories/{env}/` for governance operations. The `site.yml` playbook chains both using `--inventory` stacking.

### Anti-Pattern 5: Monolithic Playbook

**What:** A single playbook that does cluster deployment, topic creation, schema registration, RBAC, observability, and DR setup in one run.

**Why bad:** Teams often need to run governance changes (new topic, schema update) without redeploying the cluster. A monolithic playbook forces them to use `--tags` or `--skip-tags` extensively, which is error-prone.

**Instead:** Separate playbooks per concern (deploy-governance.yml, deploy-observability.yml, dr-failover.yml). A `site.yml` orchestration playbook imports them all for full deployments.

## Role Internal Structure

Each governance role follows the standard Ansible role layout with specific additions for this project.

### cp_topic Role Structure

```
ansible/roles/cp_topic/
|-- defaults/main.yml          # Default values (replication_factor: 3, etc.)
|-- tasks/
|   |-- main.yml               # Entry point: validate -> create -> verify
|   |-- validate.yml           # Naming validation using filter plugins
|   |-- create.yml             # Topic creation via Admin REST v3
|   |-- configure.yml          # Topic config update if exists
|   +-- verify.yml             # Post-creation verification
|-- meta/main.yml              # Role metadata and dependencies
|-- vars/main.yml              # Role-internal variables
+-- molecule/
    +-- default/
        |-- molecule.yml
        |-- converge.yml
        +-- verify.yml
```

### cp_schema Role Structure

```
ansible/roles/cp_schema/
|-- defaults/main.yml          # Default SR URL, content type
|-- tasks/
|   |-- main.yml               # Entry point: validate -> register -> set-compat
|   |-- validate.yml           # Calls ci/scripts/validate-schemas.py
|   |-- register.yml           # POST schema to SR REST API
|   |-- set_compatibility.yml  # PUT compatibility level from SLA tier
|   +-- verify.yml             # GET registered schema, confirm version
|-- meta/main.yml
+-- molecule/
    +-- default/
```

### cp_rbac Role Structure

```
ansible/roles/cp_rbac/
|-- defaults/main.yml          # Default MDS URL, role names
|-- tasks/
|   |-- main.yml               # Entry point: auth -> bindings -> verify
|   |-- authenticate.yml       # MDS bearer token acquisition
|   |-- topic_bindings.yml     # DeveloperWrite/DeveloperRead on topics
|   |-- group_bindings.yml     # DeveloperRead on consumer groups
|   |-- sr_bindings.yml        # Read/Write on SR subjects
|   +-- verify.yml             # List bindings and confirm
|-- meta/main.yml
+-- molecule/
    +-- default/
```

## Integration with cp-ansible Collection

The `ansible/` directory depends on `confluent.platform` (cp-ansible) but does NOT extend or modify it. The integration is strictly by composition:

```yaml
# ansible/requirements.yml
collections:
  - name: confluent.platform
    version: ">=7.6.0"
  - name: kubernetes.core
    version: ">=3.0.0"
  - name: community.general
    version: ">=8.0.0"
```

**Integration pattern:** The `site.yml` playbook chains cp-ansible cluster deployment with governance roles:

```yaml
# ansible/playbooks/site.yml
---
# Phase 1: Deploy CP cluster via cp-ansible roles
- name: Deploy Confluent Platform
  ansible.builtin.import_playbook: "../../scenarios/cp-rhel/playbooks/deploy-cp.yml"

# Phase 2: Apply governance (topics, schemas, RBAC)
- name: Apply governance
  ansible.builtin.import_playbook: deploy-governance.yml

# Phase 3: Deploy observability
- name: Deploy observability
  ansible.builtin.import_playbook: deploy-observability.yml

# Phase 4: Deploy connectors
- name: Deploy connectors
  ansible.builtin.import_playbook: deploy-connectors.yml
```

This approach means:
- cp-ansible handles cluster lifecycle (install, configure, start services)
- Our roles handle day-2 operations (topics, schemas, RBAC, connectors, DR)
- Each can be run independently (`deploy-cp.yml` alone for cluster-only, `deploy-governance.yml` alone for topic changes)

## REST API Endpoints Summary

These are the three Confluent Platform REST APIs consumed by the governance roles.

### Admin REST v3 (Topics) -- Port 8090 on Confluent Server

| Operation | Method | Endpoint | Auth |
|-----------|--------|----------|------|
| List topics | GET | `/kafka/v3/clusters/{cluster_id}/topics` | Bearer token or mTLS |
| Get topic | GET | `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}` | Bearer token or mTLS |
| Create topic | POST | `/kafka/v3/clusters/{cluster_id}/topics` | Bearer token or mTLS |
| Delete topic | DELETE | `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}` | Bearer token or mTLS |
| Get topic config | GET | `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs` | Bearer token or mTLS |
| Update topic config | POST | `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs:alter` | Bearer token or mTLS |

**Note:** The `/kafka` prefix is required for embedded REST API on Confluent Server (vs standalone REST Proxy which omits it).

### Schema Registry REST API -- Port 8081

| Operation | Method | Endpoint | Auth |
|-----------|--------|----------|------|
| Register schema | POST | `/subjects/{subject}/versions` | Basic auth or mTLS |
| Get latest schema | GET | `/subjects/{subject}/versions/latest` | Basic auth or mTLS |
| Check compatibility | POST | `/compatibility/subjects/{subject}/versions?verbose=true` | Basic auth or mTLS |
| Set subject compat | PUT | `/config/{subject}` | Basic auth or mTLS |
| Get subject compat | GET | `/config/{subject}` | Basic auth or mTLS |
| List subjects | GET | `/subjects` | Basic auth or mTLS |

**Content-Type:** `application/vnd.schemaregistry.v1+json`

### MDS REST API (RBAC) -- Port 8090

| Operation | Method | Endpoint | Auth |
|-----------|--------|----------|------|
| Authenticate | POST | `/security/1.0/authenticate` | Basic auth |
| Grant cluster role | POST | `/security/1.0/principals/User:{principal}/roles/{role}` | Bearer token |
| Grant resource binding | POST | `/security/1.0/principals/User:{principal}/roles/{role}/bindings` | Bearer token |
| Delete binding | DELETE | `/security/1.0/principals/User:{principal}/roles/{role}/bindings` | Bearer token |
| List bindings | POST | `/security/1.0/lookup/role/{role}/principal/User:{principal}` | Bearer token |

**Confidence:** MEDIUM-HIGH -- endpoints confirmed from Confluent documentation. Exact request body schemas should be validated against a running CP 7.6+ instance.

## Scalability Considerations

| Concern | dev (1 cluster, <10 topics) | staging (2 clusters, ~50 topics) | prod (multi-region, 200+ topics) |
|---------|---------------------------|----------------------------------|----------------------------------|
| Topic creation latency | Sequential tasks, < 1 min | Batch with `loop` + `async`, < 5 min | Batch with `throttle` to avoid API rate limits, < 15 min |
| Schema registration | Sequential, < 30 sec | Sequential with validation cache, < 2 min | Parallel with `async`/`poll`, < 5 min |
| RBAC bindings | Sequential, < 1 min | Sequential, < 3 min | Batched per principal, < 10 min |
| DR failover | N/A | Manual playbook, < 10 min | Automated with pre-validation, < 15 min |
| Inventory complexity | Single hosts.yml | Per-environment directory | Per-environment + per-region inventory stacking |

## Suggested Build Order

The roles have dependencies that dictate build order:

```
Phase 1: Foundation
  |-- ansible/vars/sla_tiers.yml          (governance constants)
  |-- ansible/vars/naming_rules.yml       (naming patterns)
  |-- ansible/filter_plugins/fsi_governance.py  (filter plugins)
  |-- ansible/ansible.cfg                 (project config)
  |-- ansible/requirements.yml            (collection deps)
  |-- ansible/inventories/dev/            (dev environment)

Phase 2: Core Governance Roles (build in order, each depends on prior)
  |-- ansible/roles/cp_topic/             (topics first -- everything else targets topics)
  |-- ansible/roles/cp_schema/            (schemas reference topics by subject)
  |-- ansible/roles/cp_rbac/              (RBAC binds principals to topics + subjects)

Phase 3: Orchestration
  |-- ansible/playbooks/deploy-governance.yml  (chains topic + schema + RBAC)
  |-- ansible/playbooks/site.yml              (full pipeline with cp-ansible)

Phase 4: DR Automation
  |-- ansible/roles/cp_dr_mm2/            (MM2 failover/failback)
  |-- ansible/roles/cp_dr_mrc/            (MRC observer promotion)
  |-- ansible/playbooks/dr-failover.yml
  |-- ansible/playbooks/dr-failback.yml

Phase 5: Supporting Roles
  |-- ansible/roles/cp_observability/     (JMX + dashboards)
  |-- ansible/roles/cp_connect/           (connector deployment)
  |-- ansible/roles/cp_service_account/   (SA provisioning)

Phase 6: Testing & CI
  |-- ansible/molecule/                   (molecule test configs)
  |-- .github/workflows/ansible-lint.yml  (CI integration)
```

## Sources

- [Confluent cp-ansible Collection Overview](https://docs.confluent.io/ansible/current/overview.html) -- HIGH confidence
- [Confluent MDS REST API RBAC Configuration](https://docs.confluent.io/platform/current/security/authorization/rbac/rbac-config-using-rest-api.html) -- HIGH confidence
- [Confluent Schema Registry API Reference](https://docs.confluent.io/platform/current/schema-registry/develop/api.html) -- HIGH confidence
- [Confluent Admin REST API Config](https://docs.confluent.io/platform/current/kafka-rest/production-deployment/confluent-server/config.html) -- HIGH confidence
- [Confluent Ansible RBAC Authorization](https://docs.confluent.io/ansible/current/ansible-authorize.html) -- HIGH confidence
- [cp-ansible-admin Community Project](https://github.com/thecrazymonkey/cp-ansible-admin) -- MEDIUM confidence (community, validates uri-based pattern)
- [Ansible URI Module Documentation](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/uri_module.html) -- HIGH confidence
- [Ansible Collection Structure Documentation](https://docs.ansible.com/projects/ansible/latest/dev_guide/developing_collections_structure.html) -- HIGH confidence
- [Ansible Multi-Environment Inventory Patterns](https://www.digitalocean.com/community/tutorials/how-to-manage-multistage-environments-with-ansible) -- MEDIUM confidence
- [Ansible Molecule Testing with Podman](https://www.ansible.com/blog/developing-and-testing-ansible-roles-with-molecule-and-podman-part-1/) -- MEDIUM confidence
- Existing codebase analysis: `modules/topic/main.tf`, `ci/scripts/validate-schemas.py`, `ci/scripts/c4e-precheck.py`, `scenarios/cp-rhel/` -- HIGH confidence
