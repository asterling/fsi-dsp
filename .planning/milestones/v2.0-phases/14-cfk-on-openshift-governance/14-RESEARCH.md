# Phase 14: CFK on OpenShift Governance - Research

**Researched:** 2026-04-10
**Domain:** Ansible roles for CFK operator deployment and KafkaTopic CRD generation on OpenShift
**Confidence:** HIGH

## Summary

Phase 14 bridges the existing CFK OpenShift manifests (v1.0 Phase 8) with the Ansible governance framework (v2.0 Phases 10-13) by creating two new Ansible roles: `cfk_operator` for deploying the CFK operator via Helm and applying platform CRs with readiness gates, and `cfk_topic` for generating KafkaTopic CRDs from the same CPTopic YAML definitions consumed by the `cp_topic` role. The pattern is well-established -- six roles already exist in `ansible/roles/` following identical structure (defaults, meta, tasks, molecule), and the governance constants (SLA tiers, naming rules, filter plugin) are fully reusable.

The core technical challenge is the CPTopic-to-KafkaTopic transformation: CPTopic YAML uses `kind: CPTopic` with `spec.configs` as native types (integers), while KafkaTopic CRDs use `kind: KafkaTopic` with `spec.configs` as string-typed values, require `metadata.namespace`, `spec.replicas`, and `spec.kafkaClusterRef`. SLA-tier defaults must produce identical governance outcomes (partitions, retention, min.insync.replicas) regardless of which role processes the CPTopic definition. The `kubernetes.core` collection provides `helm`, `helm_repository`, `k8s`, and `k8s_info` modules that map directly to each requirement.

**Primary recommendation:** Create two roles (`cfk_operator` and `cfk_topic`) following the exact cp_connect/cp_dr_mm2 structural pattern, using `kubernetes.core.helm` for operator install, `kubernetes.core.k8s` with `wait: true` for CR application, and Jinja2 templating with the existing `fsi_sla_lookup`/`fsi_validate_topic_name` filters for CPTopic-to-KafkaTopic CRD generation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all implementation choices are at Claude's discretion (infrastructure phase).

### Claude's Discretion
All implementation choices are at Claude's discretion -- pure infrastructure phase. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions. Key patterns to follow:
- Role structure matches cp_connect, cp_dr_mm2 patterns (defaults, meta, tasks, molecule, tests)
- kubernetes.core.helm for operator deployment, kubernetes.core.k8s for CR application
- Readiness gates use kubernetes.core.k8s_info to poll CRD status before proceeding
- CPTopic YAML consumption reuses the pattern from cp_topic role
- SLA-tier defaults derive from existing ansible/vars/sla_tiers.yml

### Deferred Ideas (OUT OF SCOPE)
None -- discuss phase skipped.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ACFK-01 | Operator can deploy CFK operator on OpenShift via Ansible using `kubernetes.core.helm` module | Standard Stack: kubernetes.core >= 5.0.0 provides helm, helm_repository modules. Architecture: cfk_operator role tasks/deploy.yml uses helm_repository + helm for install |
| ACFK-02 | CFK custom resources (KafkaCluster, SchemaRegistry, Connect) are applied via `kubernetes.core.k8s` with readiness gates before governance tasks | Architecture: cfk_operator role tasks/apply_crs.yml uses k8s module with wait: true + wait_condition for each CR kind. k8s_info fallback polling pattern documented |
| ACFK-03 | KafkaTopic CRDs are generated from CPTopic YAML definitions with governance parity (same SLA-tier defaults as CP REST API roles) | Architecture: cfk_topic role reuses cp_topic's CPTopic discovery + governance filter pattern, transforms to KafkaTopic CRD via Jinja2 template, applies via k8s module |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Deployment parity**: Core governance (topic naming, schema compat, RBAC) must work identically across all deployment models -- this phase's KafkaTopic CRDs MUST produce identical SLA-tier defaults as cp_topic role
- **OpenShift compatibility**: CFK scenario must target OCP 4.x with operator lifecycle management
- **ansible.builtin.uri over custom modules** for REST API operations (locked decision from STATE.md) -- CFK roles use kubernetes.core modules instead (not REST API), which is acceptable
- **Standalone roles (not Galaxy collection)** -- tightly coupled to repo governance data
- **FQCN enforcement** -- all task files must use fully qualified collection names
- **Task names start with uppercase** -- ansible-lint name[casing] rule
- **conftest.py** over __init__.py for tests/ansible/ (locked decision Phase 10)
- **ansible-lint shared profile** with explicit FQCN enforcement

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| kubernetes.core | >= 5.0.0 | Helm, k8s, k8s_info modules for CFK operator and CR management | Official Ansible collection for Kubernetes; Red Hat certified |
| confluent-for-kubernetes | 3.2.x (Helm chart) | CFK operator deployment | Current CFK release, supports OCP 4.14-4.21 and CP 7.4-8.2 |
| Confluent Platform images | 7.6.0 (in existing CRs) | Kafka, SR, Connect container images | Matches existing scenario manifests from Phase 8 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ansible-core | >= 2.15 | Ansible runtime | Already installed, matches min_ansible_version in all existing roles |
| community.general | >= 8.0.0 | json_query filter | Already in requirements.yml |
| Helm 3.x | 3.19.0 (installed) | Helm binary dependency for kubernetes.core.helm | Required on control node; already present |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| kubernetes.core.helm | ansible.builtin.shell + helm CLI | Loses idempotency, harder check-mode, no module return values |
| kubernetes.core.k8s_info wait | ansible.builtin.uri polling K8s API | Requires kubeconfig parsing, auth handling -- k8s_info does this natively |
| Jinja2 template for CRD | Python filter plugin | Over-engineering; Jinja2 template is sufficient and more transparent |

**Installation:**
```bash
ansible-galaxy collection install kubernetes.core
```

**Add to requirements.yml:**
```yaml
  - name: kubernetes.core
    version: ">=5.0.0"
```

## Architecture Patterns

### Recommended Project Structure
```
ansible/
  roles/
    cfk_operator/            # ACFK-01, ACFK-02: CFK operator + CR deployment
      defaults/main.yml      # Helm chart version, namespace, CR paths
      meta/main.yml          # Galaxy metadata, min_ansible_version: "2.15"
      tasks/
        main.yml             # Entry point: load vars, route check/normal
        deploy.yml           # Helm repo add + helm install/upgrade
        apply_crs.yml        # Apply Kafka, SR, Connect CRs with readiness gates
        check.yml            # Check-mode: report current state via k8s_info
      molecule/default/
        molecule.yml         # delegated driver
        converge.yml         # Mock converge (skip_when no kubeconfig)
        verify.yml           # Verify role ran without error
    cfk_topic/               # ACFK-03: KafkaTopic CRD generation from CPTopic
      defaults/main.yml      # Namespace, kafkaClusterRef, replication factor
      meta/main.yml          # Galaxy metadata
      tasks/
        main.yml             # Entry point: load governance, discover CPTopics
        validate.yml         # Governance validation (name, SLA tier)
        generate.yml         # Transform CPTopic -> KafkaTopic CRD via k8s
        check.yml            # Check-mode: show what would be applied
      molecule/default/
        molecule.yml
        converge.yml
        verify.yml
  playbooks/
    deploy-cfk.yml           # CFK deployment playbook (operator + CRs + topics)
tests/ansible/
  test_cfk_operator.py       # Role structure, FQCN, task names, helm patterns
  test_cfk_topic.py          # Governance parity, CRD generation, SLA defaults
```

### Pattern 1: CFK Operator Deployment (cfk_operator role)

**What:** Deploy CFK operator via Helm, then apply platform CRs with readiness gates.
**When to use:** Initial CFK deployment or operator upgrade on OpenShift.
**Example:**
```yaml
# tasks/deploy.yml
- name: Add Confluent Helm repository
  kubernetes.core.helm_repository:
    name: confluentinc
    repo_url: "{{ cfk_helm_repo_url }}"
    state: present

- name: Deploy CFK operator via Helm
  kubernetes.core.helm:
    name: "{{ cfk_helm_release_name }}"
    chart_ref: "{{ cfk_helm_chart_ref }}"
    chart_version: "{{ cfk_helm_chart_version }}"
    release_namespace: "{{ cfk_namespace }}"
    create_namespace: true
    wait: true
    wait_timeout: "{{ cfk_helm_wait_timeout }}"
  register: _cfk_helm_result
```

### Pattern 2: CR Application with Readiness Gates (cfk_operator role)

**What:** Apply CFK custom resources and wait for operator to reconcile them to Ready.
**When to use:** After operator install, before governance tasks.
**Example:**
```yaml
# tasks/apply_crs.yml -- Apply Kafka CR and wait for readiness
- name: Apply Kafka custom resource
  kubernetes.core.k8s:
    state: present
    src: "{{ cfk_kafka_cr_path }}"
    namespace: "{{ cfk_namespace }}"
    wait: true
    wait_timeout: "{{ cfk_cr_wait_timeout }}"
    wait_condition:
      type: kafka.internal.confluent.io/Ready
      status: "True"

# Fallback pattern using k8s_info when wait_condition type is uncertain:
- name: Wait for Kafka pods to be ready
  kubernetes.core.k8s_info:
    kind: Kafka
    api_version: platform.confluent.io/v1beta1
    name: kafka
    namespace: "{{ cfk_namespace }}"
    wait: true
    wait_timeout: "{{ cfk_cr_wait_timeout }}"
  register: _kafka_status
  until:
    - _kafka_status.resources | length > 0
    - (_kafka_status.resources[0].status.phase | default('')) == 'RUNNING'
  retries: "{{ cfk_readiness_retries }}"
  delay: "{{ cfk_readiness_delay }}"
```

### Pattern 3: CPTopic-to-KafkaTopic CRD Generation (cfk_topic role)

**What:** Read CPTopic YAML, apply governance defaults from SLA tier, transform to KafkaTopic CRD.
**When to use:** Applying governed topics to CFK clusters.
**Key transformation:**
```yaml
# CPTopic input (kind: CPTopic):
apiVersion: platform.confluent.io/v1beta1
kind: CPTopic
metadata:
  name: corebanking.transactions.v1.account-transaction
  labels:
    fsi.sla-tier: critical
spec:
  partitionCount: 12
  configs:
    retention.ms: 604800000    # <-- integer in CPTopic

# KafkaTopic output (kind: KafkaTopic):
apiVersion: platform.confluent.io/v1beta1
kind: KafkaTopic
metadata:
  name: corebanking.transactions.v1.account-transaction
  namespace: confluent          # <-- added
  labels:
    fsi.sla-tier: critical
spec:
  replicas: 3                   # <-- added (from cfk_replication_factor)
  partitionCount: 12
  kafkaClusterRef:              # <-- added
    name: kafka
  configs:
    retention.ms: "604800000"   # <-- string-typed
    min.insync.replicas: "2"    # <-- string-typed, from SLA tier
    cleanup.policy: "delete"    # <-- string-typed
```

**Implementation approach:**
```yaml
# tasks/generate.yml
- name: "Apply KafkaTopic CRD for {{ _topic_name }}"
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: platform.confluent.io/v1beta1
      kind: KafkaTopic
      metadata:
        name: "{{ _topic_name }}"
        namespace: "{{ cfk_topic_namespace }}"
        labels: "{{ topic_item.metadata.labels }}"
      spec:
        replicas: "{{ cfk_replication_factor }}"
        partitionCount: "{{ _topic_partitions | int }}"
        kafkaClusterRef:
          name: "{{ cfk_kafka_cluster_name }}"
        configs:
          cleanup.policy: "{{ _topic_cleanup_policy }}"
          retention.ms: "{{ _topic_retention_ms | string }}"
          min.insync.replicas: "{{ _topic_min_isr | string }}"
  register: _cfk_topic_result
```

### Pattern 4: Playbook for CFK Deployment

**What:** Top-level playbook that chains operator deployment, CR application, and topic governance.
**Example:**
```yaml
# playbooks/deploy-cfk.yml
---
- name: Deploy CFK operator and platform components
  hosts: localhost
  connection: local
  gather_facts: false
  tags:
    - cfk-operator
  tasks:
    - name: Deploy CFK operator and CRs
      ansible.builtin.include_role:
        name: cfk_operator

- name: Apply governed KafkaTopic CRDs
  hosts: localhost
  connection: local
  gather_facts: false
  tags:
    - cfk-topics
  tasks:
    - name: Apply CFK topic governance
      ansible.builtin.include_role:
        name: cfk_topic
```

### Anti-Patterns to Avoid
- **Hardcoding SLA-tier values in CFK roles:** Always derive from `sla_tiers.yml` via `fsi_sla_lookup` filter -- never duplicate tier constants
- **Using shell/command modules for helm/kubectl:** Use `kubernetes.core.helm` and `kubernetes.core.k8s` for idempotency and check-mode support
- **Polling CRD status with ansible.builtin.uri:** Use `kubernetes.core.k8s_info` which handles kubeconfig auth natively
- **Mixing CP REST API patterns into CFK roles:** CFK roles talk to Kubernetes API (not Admin REST v3); cp_topic uses uri, cfk_topic uses k8s module
- **Integer config values in KafkaTopic CRDs:** CFK requires config values as strings; the CPTopic format uses integers -- transformation must stringify

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Helm chart install | Shell commands with `helm install` | `kubernetes.core.helm` module | Idempotent, check-mode aware, returns structured data |
| K8s CR application | `oc apply` via shell | `kubernetes.core.k8s` module | Native wait support, idempotent, diff in check mode |
| CRD readiness polling | Shell loops with `oc get` | `kubernetes.core.k8s_info` with `wait` / `until` | Handles auth, returns structured status, retry built-in |
| Topic name validation | Custom regex in task | `fsi_validate_topic_name` filter | Already exists, tested, parity-validated with Terraform |
| SLA tier property lookup | Inline `sla_tiers[tier].property` | `fsi_sla_lookup` filter | Provides error handling, unknown tier/property validation |
| Helm repo management | `helm repo add` via shell | `kubernetes.core.helm_repository` module | Idempotent, state management, no shell dependency |

**Key insight:** The existing governance filter plugin (`filter_plugins/fsi_governance.py`) and shared vars (`sla_tiers.yml`, `naming_rules.yml`) are the single source of truth. CFK roles MUST reuse them to guarantee governance parity rather than implementing parallel governance logic.

## Common Pitfalls

### Pitfall 1: CFK CRD Status Condition Type Mismatch
**What goes wrong:** Using `wait_condition.type: Ready` when CFK uses a custom condition type like `kafka.internal.confluent.io/Ready` or reports status via `status.phase: RUNNING`.
**Why it happens:** CFK CRDs do not follow standard Kubernetes `conditions[].type: Ready` pattern consistently.
**How to avoid:** Use `kubernetes.core.k8s_info` with `until` loop checking `status.phase == 'RUNNING'` instead of relying on `wait_condition`. This is more robust across CFK versions.
**Warning signs:** Task hangs at wait timeout, then fails with "condition not met."

### Pitfall 2: Integer vs String Config Values in KafkaTopic CRDs
**What goes wrong:** Applying `retention.ms: 604800000` (integer) instead of `retention.ms: "604800000"` (string) to KafkaTopic CRD causes CFK operator to reject or silently ignore configs.
**Why it happens:** CPTopic YAML stores configs as native integers. KafkaTopic CRDs require string-typed config values (Kafka API convention).
**How to avoid:** Use `| string` Jinja2 filter when setting config values: `retention.ms: "{{ _topic_retention_ms | string }}"`.
**Warning signs:** Topic created but configs not applied; `oc describe kafkatopic` shows empty/wrong config.

### Pitfall 3: Namespace Not Set on KafkaTopic CRDs
**What goes wrong:** KafkaTopic CRD applied without `metadata.namespace` field, lands in default namespace instead of the CFK namespace.
**Why it happens:** CPTopic format does not include namespace (it's a CP concept, not K8s). The transformation must inject it.
**How to avoid:** Always set `namespace: "{{ cfk_topic_namespace }}"` in the generated KafkaTopic definition.
**Warning signs:** Topics not visible in CFK-managed cluster; operator logs show no reconciliation.

### Pitfall 4: Governance Parity Drift Between cp_topic and cfk_topic
**What goes wrong:** cfk_topic role produces different partition counts, retention, or min.insync.replicas than cp_topic for the same CPTopic YAML input.
**Why it happens:** Duplicating governance logic instead of reusing `fsi_sla_lookup` filter. Or forgetting to apply override logic (spec.partitionCount override, spec.configs override).
**How to avoid:** Both roles must follow identical governance derivation: extract SLA tier from labels -> derive defaults via fsi_sla_lookup -> apply spec overrides. Copy the validate.yml pattern from cp_topic.
**Warning signs:** Parity test fails; different topic configs on CP vs CFK clusters.

### Pitfall 5: Helm Release Idempotency with `chart_version` Pin
**What goes wrong:** Running playbook twice causes Helm "already exists" errors or unnecessary upgrades.
**Why it happens:** Not using `kubernetes.core.helm` with proper state management.
**How to avoid:** The `kubernetes.core.helm` module is idempotent by default -- if the release exists at the specified version, it reports `changed: false`. Always pin `chart_version` in defaults.
**Warning signs:** Every playbook run reports changed; unnecessary operator restarts.

### Pitfall 6: kubernetes.core.k8s Wait on Non-Existent Resource
**What goes wrong:** `k8s_info` with `wait: true` returns immediately if the resource does not yet exist (known issue #13 in kubernetes.core).
**Why it happens:** The wait feature only blocks if the initial query returns results.
**How to avoid:** Use `until` + `retries` + `delay` pattern around `k8s_info` instead of native `wait`. This handles the race where the CR hasn't been created yet.
**Warning signs:** Readiness gate passes instantly but pods aren't running.

### Pitfall 7: CFK Playbook Targets localhost, Not Remote Hosts
**What goes wrong:** Running CFK playbook against remote hosts when kubectl/helm must run locally.
**Why it happens:** Existing cp_* roles target broker/connect hosts via SSH. CFK roles target the Kubernetes API from the control node.
**How to avoid:** CFK playbook uses `hosts: localhost` with `connection: local`. The kubeconfig on the control node determines which cluster is targeted.
**Warning signs:** "helm not found" or "kubectl not found" errors when running against remote hosts.

## Code Examples

Verified patterns from the existing codebase:

### CPTopic Discovery (reuse from cp_topic main.yml)
```yaml
# Source: ansible/roles/cp_topic/tasks/main.yml lines 20-47
- name: Discover CPTopic YAML files from directory
  ansible.builtin.find:
    paths: "{{ cfk_topics_dir }}"
    patterns: "*.yml"
    file_type: file
  register: _cfk_topic_files
  when: cfk_topics_dir | length > 0

- name: Load CPTopic YAML files
  ansible.builtin.slurp:
    src: "{{ item.path }}"
  loop: "{{ _cfk_topic_files.files | default([]) }}"
  loop_control:
    label: "{{ item.path | basename }}"
  register: _cfk_topic_slurped
  when: cfk_topics_dir | length > 0

- name: Parse CPTopic YAML content
  ansible.builtin.set_fact:
    _cfk_topics_from_dir: >-
      {{ _cfk_topics_from_dir | default([]) +
         [item.content | b64decode | from_yaml] }}
  loop: "{{ _cfk_topic_slurped.results | default([]) }}"
  loop_control:
    label: "{{ item.item.path | default('inline') | basename }}"
  when:
    - cfk_topics_dir | length > 0
    - (item.content | b64decode | from_yaml).kind | default('') == 'CPTopic'
```

### Governance Validation (reuse from cp_topic validate.yml)
```yaml
# Source: ansible/roles/cp_topic/tasks/validate.yml lines 10-28
- name: "Extract SLA tier for {{ topic_item.metadata.name }}"
  ansible.builtin.set_fact:
    _topic_sla_tier: "{{ topic_item.metadata.labels['fsi.sla-tier'] | default('standard') }}"

- name: "Validate topic name governance for {{ topic_item.metadata.name }}"
  ansible.builtin.assert:
    that:
      - topic_item.metadata.name | fsi_validate_topic_name
    fail_msg: "Topic name '{{ topic_item.metadata.name }}' fails governance naming validation"
    quiet: true

- name: "Derive config from SLA tier for {{ topic_item.metadata.name }}"
  ansible.builtin.set_fact:
    _topic_partitions: "{{ _topic_sla_tier | fsi_sla_lookup('partitions') }}"
    _topic_retention_ms: "{{ _topic_sla_tier | fsi_sla_lookup('retention_ms') }}"
    _topic_min_isr: "{{ sla_tiers[_topic_sla_tier].min_insync_replicas }}"
    _topic_cleanup_policy: "delete"
```

### Molecule Configuration (reuse from cp_dr_mm2)
```yaml
# Source: ansible/roles/cp_dr_mm2/molecule/default/molecule.yml
---
dependency:
  name: galaxy
driver:
  name: delegated
platforms:
  - name: instance
provisioner:
  name: ansible
  inventory:
    hosts:
      all:
        hosts:
          localhost:
            ansible_connection: local
verifier:
  name: ansible
```

### Role Meta (pattern from cp_connect)
```yaml
# Source: ansible/roles/cp_connect/meta/main.yml
---
galaxy_info:
  role_name: cfk_operator  # or cfk_topic
  author: fsi-c4e
  description: Deploy CFK operator and platform CRs on OpenShift
  license: Apache-2.0
  min_ansible_version: "2.15"
  platforms:
    - name: EL
      versions:
        - "8"
        - "9"
  galaxy_tags:
    - kafka
    - cfk
    - openshift
    - confluent
dependencies: []
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CFK 2.x operator | CFK 3.2.x operator | 2025 | OCP 4.14-4.21 support, CP 7.4-8.2 support |
| Manual oc apply of CRD manifests | Ansible kubernetes.core.k8s | Established | Idempotent, check-mode, wait support |
| Hand-written KafkaTopic YAMLs | Generated from CPTopic YAML via governance | Phase 14 (new) | Parity with CP REST API governance |

**Deprecated/outdated:**
- CFK 2.x series: superseded by 3.x; scenario README already references 3.2
- `kubernetes.core` < 5.0.0: older versions lacked k8s_info wait improvements

## Open Questions

1. **CFK CR Status.Phase Values**
   - What we know: CFK CRs report `status.phase` field. README references "Ready" pods.
   - What's unclear: Exact `status.phase` values for Kafka, SchemaRegistry, Connect CRs (likely `RUNNING` but may vary by CFK version).
   - Recommendation: Use `until` loop with defensive check `status.phase | default('') == 'RUNNING'` and document that the exact value should be validated against the target CFK version. The `check.yml` task can query and report current status.

2. **kubernetes.core Collection in requirements.yml**
   - What we know: The collection is not currently in `ansible/requirements.yml`. It needs to be added.
   - What's unclear: Whether the CI runner has it pre-installed or needs explicit install.
   - Recommendation: Add `kubernetes.core >= 5.0.0` to `requirements.yml`. CI already runs `ansible-galaxy collection install -r ansible/requirements.yml`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Helm 3.x | kubernetes.core.helm module | Yes | 3.19.0 | -- |
| kubectl | kubernetes.core.k8s module | Yes | v1.34.1 | -- |
| ansible-core | Playbook runtime | Yes | 2.15.13 | -- |
| ansible-lint | CI lint job | Yes | 6.22.2 | -- |
| pytest | Unit tests | Yes | 8.4.2 | -- |
| PyYAML | Test assertions | Yes | 6.0.3 | -- |
| Python 3.x | CI and tests | Yes | 3.9.6 | -- |
| OpenShift cluster | Runtime target | N/A | N/A | Not needed for role/test creation |
| kubernetes.core collection | k8s/helm modules | Not in requirements.yml | -- | Must add to requirements.yml |

**Missing dependencies with no fallback:**
- kubernetes.core collection must be added to `ansible/requirements.yml`

**Missing dependencies with fallback:**
- None

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.4.2 |
| Config file | None (uses conftest.py in tests/ansible/) |
| Quick run command | `python3 -m pytest tests/ansible/test_cfk_operator.py tests/ansible/test_cfk_topic.py -v` |
| Full suite command | `python3 -m pytest tests/ansible/ -v` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ACFK-01 | CFK operator deployed via kubernetes.core.helm | unit | `python3 -m pytest tests/ansible/test_cfk_operator.py -x` | No -- Wave 0 |
| ACFK-02 | CRs applied with readiness gates | unit | `python3 -m pytest tests/ansible/test_cfk_operator.py::TestReadinessGates -x` | No -- Wave 0 |
| ACFK-03 | KafkaTopic CRDs from CPTopic with governance parity | unit | `python3 -m pytest tests/ansible/test_cfk_topic.py -x` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `python3 -m pytest tests/ansible/test_cfk_operator.py tests/ansible/test_cfk_topic.py -v`
- **Per wave merge:** `python3 -m pytest tests/ansible/ -v`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/ansible/test_cfk_operator.py` -- covers ACFK-01 and ACFK-02 (role structure, FQCN, helm patterns, readiness gate patterns)
- [ ] `tests/ansible/test_cfk_topic.py` -- covers ACFK-03 (role structure, FQCN, governance wiring, SLA-tier parity, CRD generation patterns)
- [ ] Add `kubernetes.core >= 5.0.0` to `ansible/requirements.yml`
- [ ] Add `cfk_operator` and `cfk_topic` to CI molecule matrix in `.github/workflows/ansible-ci.yml`

## Sources

### Primary (HIGH confidence)
- Existing codebase: `ansible/roles/cp_topic/`, `ansible/roles/cp_connect/`, `ansible/roles/cp_dr_mm2/` -- structural patterns, governance wiring, test patterns
- Existing codebase: `scenarios/cfk-openshift/` -- CFK CRDs, Helm values, KafkaTopic CRD format
- Existing codebase: `ansible/filter_plugins/fsi_governance.py` -- governance filter functions
- Existing codebase: `ansible/vars/sla_tiers.yml`, `ansible/vars/naming_rules.yml` -- governance constants
- Existing codebase: `scenarios/cp-rhel/topics/*.yml` -- CPTopic YAML format (source of truth)
- [kubernetes.core.helm module documentation](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/helm_module.html) -- module parameters
- [kubernetes.core.k8s_info module documentation](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/k8s_info_module.html) -- wait condition parameters
- [kubernetes.core.helm_repository module documentation](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/helm_repository_module.html) -- repo management

### Secondary (MEDIUM confidence)
- [CFK Release Notes](https://docs.confluent.io/operator/current/release-notes.html) -- CFK 3.2.x version and OCP compatibility
- [CFK Topic Management](https://docs.confluent.io/operator/current/co-manage-topics.html) -- KafkaTopic CRD spec fields
- [CFK Deployment](https://docs.confluent.io/operator/current/co-deploy-cfk.html) -- Helm chart installation reference
- [kubernetes.core GitHub repo](https://github.com/ansible-collections/kubernetes.core/) -- collection version 6.3.0 current

### Tertiary (LOW confidence)
- [kubernetes.core k8s_info wait issue #13](https://github.com/ansible-collections/kubernetes.core/issues/13) -- wait on non-existent resource behavior (informed Pitfall 6)
- CFK `status.phase` exact values -- not verified against live CFK 3.2 instance; defensive coding recommended

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - kubernetes.core is the canonical collection; CFK Helm chart is well-documented; all patterns exist in codebase
- Architecture: HIGH - direct replication of established cp_topic/cp_connect/cp_dr_mm2 role patterns; governance filter reuse is proven
- Pitfalls: HIGH - based on actual codebase inspection (integer vs string types in CRDs) and documented kubernetes.core issues

**Research date:** 2026-04-10
**Valid until:** 2026-05-10 (stable patterns; CFK minor version bumps may change status.phase)
