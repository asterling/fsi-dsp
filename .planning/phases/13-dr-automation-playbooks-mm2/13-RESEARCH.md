# Phase 13: DR Automation Playbooks (MM2) - Research

**Researched:** 2026-04-09
**Domain:** Ansible DR automation for MirrorMaker 2 failover/failback on Confluent Platform
**Confidence:** HIGH

## Summary

Phase 13 translates the existing shell-based MM2 DR operations (implemented in `scripts/fsi-dr.sh` as the `mm2` backend) into Ansible playbooks with the `cp_dr_mm2` role. The existing shell implementation provides the complete 6-step failover/failback sequence with MM2 connector management via Connect REST API, Consul KV flipping, and state validation. The Ansible role must replicate this behavior while adding structured check mode (dry-run with audit-ready output), SLA-tier-aware mirror lag validation, and the established role patterns from Phases 11-12 (result counters, FQCN, `failed_when: false` error collection, molecule testing).

The key architectural difference between MM2 and Cluster Linking DR is that MM2 DR topics are standard Kafka topics -- they are already writable. Failover means "stop MM2 replication connectors + flip Consul to DR" (no mirror promotion needed). Failback means "delete existing MM2 connectors, create reversed ones with swapped source/target aliases, validate sync, then cut back." All MM2 connector management goes through the Connect REST API (pause, resume, delete, create) using `ansible.builtin.uri` -- the same REST API pattern used by the existing `cp_connect` role.

**Primary recommendation:** Build `cp_dr_mm2` as a standalone Ansible role following established patterns. The role's `main.yml` routes to check mode or action mode. Failover and failback are separate task files invoked based on a `cp_dr_mm2_operation` variable. Consul integration uses `ansible.builtin.uri` against the Consul HTTP API (not community.general.consul_kv) for consistency with the project's "uri for all REST" decision. State validation tasks check mirror lag via Connect REST API and topic writability via Admin REST v3 API.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None explicitly locked -- all implementation choices at Claude's discretion per CONTEXT.md.

### Claude's Discretion
All implementation choices are at Claude's discretion -- pure infrastructure phase. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions.

### Deferred Ideas (OUT OF SCOPE)
None -- discuss phase skipped.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ADR-01 | MM2 failover playbook orchestrates: pause connectors -> stop source MM2 -> promote topics -> update Consul -> validate -> resume on target | Existing `mm2_failover_mirrors()` in fsi-dr.sh provides complete sequence; Connect REST API pause/delete endpoints verified; Consul HTTP API KV PUT for region flip |
| ADR-02 | MM2 failback playbook reverses replication direction, re-establishes mirrors, validates data sync, and cuts back to primary | Existing `mm2_failback_mirrors()` provides delete-and-recreate-reversed pattern; Connect REST API POST for new connectors; polling for RUNNING state |
| ADR-03 | DR playbooks support `--check` mode (dry-run) generating audit-ready output showing every step without executing | Established check mode pattern from cp_connect role (GET-only operations, `changed_when: false`, `check_mode: false` on read tasks); `ansible_check_mode` routing in main.yml |
| ADR-04 | DR state validation tasks check mirror lag against SLA-tier thresholds, cluster health, and topic writability before and after failover | SLA tier thresholds in `ansible/vars/sla_tiers.yml` (no mirror_lag_threshold yet -- needs adding); Connect REST API status endpoints for connector health; Admin REST v3 for topic writability checks |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **`ansible.builtin.uri` for all REST API operations** -- no custom Python modules, no community.general.consul_kv
- **`failed_when: false` for error collection** (ansible-lint shared profile compliance)
- **Task names start with uppercase, Jinja at end only** (name[casing] and name[template] rules)
- **FQCN enforcement** -- all module references use full namespace
- **PUT for idempotent create-or-update** operations
- **Molecule default scenario** for each role with delegated driver
- **var_naming_pattern: `^[a-z_][a-z0-9_]*$`** for all variables
- **Profile: shared** in ansible-lint with FQCN enabled
- **Mock roles** for cp-ansible roles in lint config
- **CP version 7.7.0** in all inventory references
- **Confluent Platform only** -- no CC Ansible (CC stays Terraform-only)

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ansible-core | 2.15+ | Automation engine | cp-ansible 7.7.x requirement |
| confluent.platform | 7.7.8 | CP deployment roles (not directly used but establishes patterns) | Pinned in requirements.yml |
| community.general | >=8.0.0 | General-purpose modules (available but NOT used for REST -- uri preferred) | In requirements.yml |

### APIs Used
| API | Base URL | Purpose | Auth |
|-----|----------|---------|------|
| Connect REST API | `cp_connect_url:8083` | MM2 connector pause/resume/create/delete/status | None (mTLS at network level) |
| Consul HTTP API | `consul_http_addr:8500` | KV store for active-region flip | Token or ACL (if configured) |
| Admin REST v3 API | `cp_admin_rest_url` | Topic writability validation (produce test) | MDS bearer token or basic auth |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ansible.builtin.uri for Consul | community.general.consul_kv | Project convention mandates uri for all REST; consul_kv adds dependency |
| Standalone DR playbook | Integrated into site.yml | DR is an ad-hoc operation, not part of deployment pipeline; separate playbook is correct |
| ansible.builtin.command for confluent CLI | ansible.builtin.uri for REST APIs | CLI requires confluent binary on host; REST API is more portable and idempotent |

## Architecture Patterns

### Recommended Project Structure
```
ansible/
  roles/
    cp_dr_mm2/
      defaults/main.yml          # All configurable variables with safe defaults
      meta/main.yml              # Galaxy metadata (role_name, min_ansible_version)
      tasks/
        main.yml                 # Entry point: routes to check or action mode
        check.yml                # Dry-run: GET-only operations, audit output
        failover.yml             # 6-step failover sequence
        failback.yml             # Failback: reverse replication, cutover
        validate_state.yml       # Pre/post validation: lag, health, writability
        consul_flip.yml          # Consul KV active-region update
        connector_pause.yml      # Pause MM2 connectors with polling
        connector_resume.yml     # Resume connectors with polling
      molecule/
        default/
          molecule.yml           # Delegated driver, localhost
          converge.yml           # Run role with mock Connect/Consul APIs
          verify.yml             # Assert results variables are correct
  playbooks/
    dr-failover-mm2.yml          # Top-level playbook for operators
    dr-failback-mm2.yml          # Top-level playbook for operators
```

### Pattern 1: Operation Routing via Variable
**What:** `main.yml` reads `cp_dr_mm2_operation` (failover/failback) and routes to the appropriate task file.
**When to use:** When a single role handles multiple distinct workflows.
**Example:**
```yaml
# main.yml
---
- name: Load SLA tier governance constants
  ansible.builtin.include_vars:
    file: "{{ role_path }}/../../vars/sla_tiers.yml"

- name: Run check-mode DR audit report
  ansible.builtin.include_tasks:
    file: check.yml
  when: ansible_check_mode | bool

- name: Run pre-validation checks
  ansible.builtin.include_tasks:
    file: validate_state.yml
  vars:
    _validation_phase: "pre"
  when: not (ansible_check_mode | bool)

- name: Execute failover sequence
  ansible.builtin.include_tasks:
    file: failover.yml
  when:
    - not (ansible_check_mode | bool)
    - cp_dr_mm2_operation == 'failover'

- name: Execute failback sequence
  ansible.builtin.include_tasks:
    file: failback.yml
  when:
    - not (ansible_check_mode | bool)
    - cp_dr_mm2_operation == 'failback'

- name: Run post-validation checks
  ansible.builtin.include_tasks:
    file: validate_state.yml
  vars:
    _validation_phase: "post"
  when: not (ansible_check_mode | bool)

- name: Set cp_dr_mm2_results output variable
  ansible.builtin.set_fact:
    cp_dr_mm2_results:
      operation: "{{ cp_dr_mm2_operation }}"
      connectors_paused: "{{ _dr_connectors_paused | default(0) }}"
      connectors_resumed: "{{ _dr_connectors_resumed | default(0) }}"
      consul_flipped: "{{ _dr_consul_flipped | default(false) }}"
      validation_passed: "{{ _dr_validation_passed | default(false) }}"
      audit_log: "{{ _dr_audit_log | default([]) }}"
```

### Pattern 2: Connector Polling with Retries
**What:** After sending a pause/resume/create command to Connect REST API, poll the status endpoint until the desired state is reached.
**When to use:** Any Connect REST API state-change operation (pause is async).
**Example:**
```yaml
# connector_pause.yml
---
- name: "Pause MM2 connector {{ _mm2_connector_name }}"
  ansible.builtin.uri:
    url: "{{ cp_dr_mm2_connect_url }}/connectors/{{ _mm2_connector_name }}/pause"
    method: PUT
    status_code:
      - 202
      - 200
  failed_when: false
  register: _pause_result

- name: "Wait for connector {{ _mm2_connector_name }} to reach PAUSED state"
  ansible.builtin.uri:
    url: "{{ cp_dr_mm2_connect_url }}/connectors/{{ _mm2_connector_name }}/status"
    method: GET
    return_content: true
    status_code:
      - 200
  register: _pause_status
  retries: "{{ cp_dr_mm2_pause_retries }}"
  delay: "{{ cp_dr_mm2_pause_delay }}"
  until: >-
    _pause_status.json is defined
    and _pause_status.json.connector.state == 'PAUSED'
  failed_when: false
```

### Pattern 3: Audit Log Collection for Dry-Run
**What:** In check mode, collect each planned step into a structured list that produces audit-ready output.
**When to use:** ADR-03 requires `--check` to generate audit output showing every step without mutations.
**Example:**
```yaml
# check.yml
---
- name: Initialize audit log
  ansible.builtin.set_fact:
    _dr_audit_log: []

- name: "Audit step 1 -- Check MM2 connector states"
  ansible.builtin.uri:
    url: "{{ cp_dr_mm2_connect_url }}/connectors/{{ item }}/status"
    method: GET
    return_content: true
    status_code:
      - 200
  loop: "{{ cp_dr_mm2_connectors }}"
  register: _audit_connector_states
  check_mode: false
  changed_when: false

- name: Record planned failover steps
  ansible.builtin.set_fact:
    _dr_audit_log: "{{ _dr_audit_log + [_step] }}"
  vars:
    _step:
      step: 1
      action: "Pause MM2 connectors"
      current_state: "{{ _audit_connector_states.results | map(attribute='json.connector.state') | list }}"
      expected_result: "All MM2 connectors PAUSED"
  changed_when: false
```

### Pattern 4: Consul KV via ansible.builtin.uri
**What:** Use the Consul HTTP API directly with `ansible.builtin.uri` rather than community.general.consul_kv module.
**When to use:** All Consul interactions in this project (project convention: uri for all REST).
**Example:**
```yaml
# consul_flip.yml
---
- name: Read current active region from Consul
  ansible.builtin.uri:
    url: "{{ cp_dr_mm2_consul_url }}/v1/kv/fsi/kafka/active-region?raw"
    method: GET
    return_content: true
    status_code:
      - 200
      - 404
  register: _consul_current_region
  check_mode: false
  changed_when: false

- name: Update Consul active-region to target
  ansible.builtin.uri:
    url: "{{ cp_dr_mm2_consul_url }}/v1/kv/fsi/kafka/active-region"
    method: PUT
    body: "{{ cp_dr_mm2_target_region }}"
    status_code:
      - 200
  register: _consul_flip_result
  when: not (ansible_check_mode | bool)

- name: Verify Consul active-region after flip
  ansible.builtin.uri:
    url: "{{ cp_dr_mm2_consul_url }}/v1/kv/fsi/kafka/active-region?raw"
    method: GET
    return_content: true
    status_code:
      - 200
  register: _consul_verify
  failed_when: _consul_verify.content != cp_dr_mm2_target_region
  when: not (ansible_check_mode | bool)
```

### Pattern 5: SLA-Tier-Aware Validation
**What:** Load SLA tier thresholds from governance constants, check MM2 connector lag against per-tier thresholds.
**When to use:** ADR-04 requires lag validation against SLA-tier thresholds.
**Key consideration:** MM2 does NOT expose per-topic lag via Connect REST API. The validation must check connector-level health (RUNNING/PAUSED/FAILED) and optionally reference Prometheus/JMX for per-topic granularity. The existing `fsi-dr.sh` documents this limitation with `mirror_lag_ms=-1` sentinel.

### Anti-Patterns to Avoid
- **Using community.general.consul_kv:** Breaks project convention of `ansible.builtin.uri` for all REST operations
- **Using ansible.builtin.command with curl:** The uri module is purpose-built for HTTP; command+curl loses error handling
- **Combining failover and failback in one task file:** These are distinct operations with different step sequences; separate files are cleaner and match the shell script structure
- **Hardcoding MM2 connector names:** Must be configurable variables matching the existing `FSI_MM2_SOURCE_CONNECTOR`, `FSI_MM2_CHECKPOINT_CONNECTOR`, `FSI_MM2_HEARTBEAT_CONNECTOR` pattern
- **Skipping polling after pause/resume:** The Connect REST API pause/resume calls are asynchronous; tasks must poll for the expected state transition

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Connector state polling | Custom retry loop with shell | `retries:` + `delay:` + `until:` on `ansible.builtin.uri` | Ansible native retry handles backoff, timeout, and idempotency |
| SLA tier lookups | Inline tier mapping in tasks | Load `ansible/vars/sla_tiers.yml` via `include_vars` | Single source of truth, parity-tested with Terraform |
| JSON response parsing | `ansible.builtin.command` + jq | `register:` + `.json` attribute on uri response | Ansible natively parses JSON responses from uri module |
| Audit report formatting | Complex Jinja2 templates inline | `ansible.builtin.debug` with structured `msg` + `_dr_audit_log` fact list | Debug output is captured by Ansible's callback plugins for logging |
| MM2 connector config for reversed direction | Hardcoded JSON in tasks | Variables with swapped `source_alias`/`target_alias` and bootstrap servers | Matches existing fsi-dr.sh pattern of deriving reversed config from original |

## Common Pitfalls

### Pitfall 1: Connect REST API Pause is Asynchronous
**What goes wrong:** Task sends PUT /connectors/{name}/pause and immediately proceeds, but connector is still in RUNNING state.
**Why it happens:** The Connect REST API pause call returns 202 Accepted immediately; actual state transition happens asynchronously.
**How to avoid:** Always follow pause/resume with a polling loop using `retries:` + `until:` that checks `/connectors/{name}/status` for the expected state.
**Warning signs:** Subsequent steps fail because connector is still RUNNING when they expect PAUSED.

### Pitfall 2: MM2 Has No Per-Topic Lag via REST API
**What goes wrong:** Attempting to validate per-topic mirror lag against SLA-tier thresholds via Connect REST API returns no useful data.
**Why it happens:** MirrorMaker 2 exposes lag metrics via JMX/Prometheus, not via the Connect REST API. Unlike Cluster Linking which has `confluent kafka mirror list` with per-topic lag, MM2's lag monitoring requires metrics infrastructure.
**How to avoid:** Validate at connector level (RUNNING/PAUSED/FAILED state) via REST API. For per-topic lag, document that Prometheus/JMX integration is required (OBS phase already deployed JMX exporters). Use connector task count and state as health proxies. The SLA-tier check validates connector health, not per-topic lag granularity.
**Warning signs:** Tasks trying to fetch lag_ms from Connect REST API and getting empty or -1 values.

### Pitfall 3: Consul KV PUT Returns Boolean in JSON Body
**What goes wrong:** `ansible.builtin.uri` with `return_content: true` gets `true` or `false` as the response body, which may confuse JSON parsing.
**Why it happens:** The Consul HTTP API PUT endpoint for KV returns `true`/`false` to indicate success, not a JSON object.
**How to avoid:** Check `status_code: [200]` for success confirmation. For reads, use the `?raw` query parameter to get the plain value instead of base64-encoded JSON.
**Warning signs:** Tasks parsing Consul KV response as JSON and failing.

### Pitfall 4: Failback Requires Original Connector Config Before Delete
**What goes wrong:** Failback deletes MM2 connectors and creates reversed ones, but loses the original bootstrap server configuration.
**Why it happens:** The `mm2_failback_mirrors()` function in fsi-dr.sh reads original config BEFORE deleting connectors. If the Ansible task deletes first, the config is gone.
**How to avoid:** In failback.yml, fetch original connector config (GET /connectors/{name}/config) and store in a fact BEFORE deleting connectors. Use the stored config to derive reversed source/target bootstrap servers.
**Warning signs:** Reversed connectors created with wrong or default bootstrap servers.

### Pitfall 5: Dry-Run Must Not Call PUT/POST/DELETE
**What goes wrong:** Check mode accidentally mutates state because `ansible.builtin.uri` with `check_mode: false` bypasses Ansible's check mode protection.
**Why it happens:** The uri module does not inherently know which HTTP methods are safe. `check_mode: false` on a task means "always run this task even in check mode."
**How to avoid:** ONLY use `check_mode: false` on GET requests. For check mode, route entirely to `check.yml` which uses only GET operations (same pattern as cp_connect/tasks/check.yml). Never put `check_mode: false` on PUT/POST/DELETE tasks.
**Warning signs:** Audit says "would do X" but actually does X.

### Pitfall 6: Tag Isolation for DR Playbooks
**What goes wrong:** DR playbook tags leak into site.yml if DR is integrated via import_playbook.
**Why it happens:** `import_playbook` inherits parent tags (Phase 12 lesson, disjoint tag sets).
**How to avoid:** DR playbooks are STANDALONE files (`ansible/playbooks/dr-failover-mm2.yml`), not integrated into site.yml. They are ad-hoc operations, not part of the deployment pipeline. Use disjoint tags if DR playbooks are later added to a combined orchestration.
**Warning signs:** Running `ansible-playbook site.yml --tags governance` accidentally triggers DR operations.

## Code Examples

### Failover Playbook Entry Point
```yaml
# ansible/playbooks/dr-failover-mm2.yml
---
- name: MM2 DR Failover
  hosts: kafka_connect[0]
  gather_facts: false
  vars:
    cp_dr_mm2_operation: failover
  tasks:
    - name: Execute MM2 DR failover
      ansible.builtin.include_role:
        name: cp_dr_mm2
```

### Failback Playbook Entry Point
```yaml
# ansible/playbooks/dr-failback-mm2.yml
---
- name: MM2 DR Failback
  hosts: kafka_connect[0]
  gather_facts: false
  vars:
    cp_dr_mm2_operation: failback
  tasks:
    - name: Execute MM2 DR failback
      ansible.builtin.include_role:
        name: cp_dr_mm2
```

### Default Variables
```yaml
# ansible/roles/cp_dr_mm2/defaults/main.yml
---
# Operation: failover or failback
cp_dr_mm2_operation: failover

# Connect REST API (MM2 dedicated cluster)
cp_dr_mm2_connect_url: "http://localhost:8083"

# MM2 connector names (must match deployed connector names)
cp_dr_mm2_source_connector: "mm2-source-east-west"
cp_dr_mm2_checkpoint_connector: "mm2-checkpoint-east-west"
cp_dr_mm2_heartbeat_connector: "mm2-heartbeat-east-west"

# Cluster aliases (used for reversed connector naming during failback)
cp_dr_mm2_source_alias: "east"
cp_dr_mm2_target_alias: "west"

# Consul HTTP API
cp_dr_mm2_consul_url: "http://localhost:8500"
cp_dr_mm2_consul_kv_key: "fsi/kafka/active-region"
cp_dr_mm2_target_region: "west"

# Admin REST v3 (for topic writability validation)
cp_dr_mm2_admin_rest_url: ""
cp_dr_mm2_cluster_id: ""
cp_dr_mm2_admin_rest_token: ""

# Application connectors -- Connect REST URL for business connectors (may differ from MM2 cluster)
cp_dr_mm2_app_connect_url: "http://localhost:8083"

# Polling configuration
cp_dr_mm2_pause_retries: 15
cp_dr_mm2_pause_delay: 2
cp_dr_mm2_resume_retries: 15
cp_dr_mm2_resume_delay: 2

# Validation toggles
cp_dr_mm2_validate_health: true
cp_dr_mm2_validate_writability: true

# SLA tier mirror lag thresholds (seconds) -- used for pre-failover warning
# NOTE: Loaded from sla_tiers.yml at runtime; these are fallback defaults
cp_dr_mm2_lag_warn_default: 300
cp_dr_mm2_lag_alert_default: 900

# Output variable for downstream orchestration
cp_dr_mm2_results:
  operation: ""
  connectors_paused: 0
  connectors_resumed: 0
  connectors_deleted: 0
  connectors_created: 0
  consul_flipped: false
  validation_passed: false
  audit_log: []
```

### SLA Tier Extension for Mirror Lag Thresholds
The existing `ansible/vars/sla_tiers.yml` needs mirror lag thresholds added to match the shell script's `_tier_warn_threshold` and `_tier_alert_threshold` functions:
```yaml
# Added to ansible/vars/sla_tiers.yml
sla_tier_mirror_lag:
  critical:
    warn_seconds: 30
    alert_seconds: 60
  standard:
    warn_seconds: 300
    alert_seconds: 900
  best-effort:
    warn_seconds: 3600
    alert_seconds: 14400
  compliance:
    warn_seconds: 10
    alert_seconds: 30
```

### Failover Sequence (6 Steps -- Matching fsi-dr.sh)
```
Step 1: Pause application connectors (on app Connect cluster)
Step 2: Stop MM2 connectors (pause source + checkpoint + heartbeat on MM2 Connect cluster)
Step 3: Flip Consul active-region to target (west)
Step 4: Verify Consul update propagated
Step 5: Resume application connectors on target cluster
Step 6: Final validation (connector health, topic writability)
```

### Failback Sequence
```
Step 1: Fetch original MM2 connector configs (GET before delete)
Step 2: Delete existing MM2 connectors
Step 3: Create reversed MM2 connectors (swapped source/target)
Step 4: Wait for reversed connectors to reach RUNNING
Step 5: Validate data sync (connector health check)
Step 6: Flip Consul active-region back to primary (east)
Step 7: Verify Consul update and final validation
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual 6-step shell execution | `fsi-dr.sh failover --backend mm2` | Phase 8 (v1.0) | Single-command DR |
| Shell-only DR | Ansible playbook + role | Phase 13 (v2.0) | Audit-ready, check mode, structured output |
| Hardcoded lag thresholds | SLA-tier-aware thresholds from governance constants | Phase 10 (sla_tiers.yml) | Consistent governance across deployment models |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest + PyYAML |
| Config file | none explicit (uses default pytest discovery) |
| Quick run command | `pytest tests/ansible/test_cp_dr_mm2.py -x` |
| Full suite command | `pytest tests/ansible/ -x` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ADR-01 | Failover task sequence: pause -> stop MM2 -> consul flip -> validate -> resume | unit | `pytest tests/ansible/test_cp_dr_mm2.py::TestFailoverTasks -x` | Wave 0 |
| ADR-02 | Failback tasks: reverse replication, re-establish mirrors, cutback | unit | `pytest tests/ansible/test_cp_dr_mm2.py::TestFailbackTasks -x` | Wave 0 |
| ADR-03 | Check mode generates audit output, no PUT/POST/DELETE | unit | `pytest tests/ansible/test_cp_dr_mm2.py::TestCheckMode -x` | Wave 0 |
| ADR-04 | Validation checks connector health, SLA-tier thresholds, writability | unit | `pytest tests/ansible/test_cp_dr_mm2.py::TestValidation -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `pytest tests/ansible/test_cp_dr_mm2.py -x`
- **Per wave merge:** `pytest tests/ansible/ -x`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/ansible/test_cp_dr_mm2.py` -- covers ADR-01 through ADR-04
- [ ] `tests/ansible/fixtures/mock_responses/connect/mm2_connector_status_running.json` -- MM2 source connector status
- [ ] `tests/ansible/fixtures/mock_responses/connect/mm2_connector_status_paused.json` -- MM2 source connector paused
- [ ] `tests/ansible/fixtures/mock_responses/connect/mm2_connector_config.json` -- MM2 source connector config with bootstrap servers
- [ ] `tests/ansible/fixtures/mock_responses/consul/kv_active_region.txt` -- Consul KV response

## Open Questions

1. **Per-topic lag granularity in Ansible**
   - What we know: MM2 does NOT expose per-topic lag via Connect REST API; only connector-level state is available
   - What's unclear: Whether Prometheus/JMX metrics should be queried from within the Ansible role or if connector-level validation is sufficient
   - Recommendation: Validate at connector level (RUNNING/PAUSED/FAILED) for automated DR. Document that per-topic lag requires external monitoring (Prometheus/Grafana dashboards deployed in Phase 12). This matches the existing fsi-dr.sh approach.

2. **Separate Connect clusters for MM2 vs application connectors**
   - What we know: fsi-dr.sh has separate `FSI_MM2_CONNECT_URL` and `FSI_CONNECT_URL` variables, suggesting MM2 may run on a dedicated Connect cluster
   - What's unclear: Whether the target environment always has separate clusters
   - Recommendation: Support both patterns with two configurable URLs (`cp_dr_mm2_connect_url` for MM2 connectors, `cp_dr_mm2_app_connect_url` for application connectors). Default both to the same URL.

3. **SLA tier mirror lag thresholds in sla_tiers.yml**
   - What we know: Shell script has thresholds hardcoded as functions; `sla_tiers.yml` has topic config but no mirror lag thresholds
   - What's unclear: Whether adding mirror lag thresholds to sla_tiers.yml breaks the CI parity test with Terraform
   - Recommendation: Add `sla_tier_mirror_lag` as a separate top-level key in sla_tiers.yml. The parity test validates `sla_tiers` key specifically, not the whole file. Verify parity test does not fail.

## Environment Availability

Step 2.6: SKIPPED (no external dependencies identified). This phase creates Ansible YAML files and Python test files only. No external tools are needed beyond the development environment already validated in Phases 10-12.

## Sources

### Primary (HIGH confidence)
- Codebase: `scripts/fsi-dr.sh` -- complete MM2 backend implementation (lines 548-868)
- Codebase: `scripts/mirror-failover.sh`, `mirror-failback.sh`, `connect-pause-all.sh`, `consul-flip-region.sh` -- original shell scripts
- Codebase: `ansible/roles/cp_connect/` -- established Ansible role patterns for Connect REST API
- Codebase: `ansible/roles/cp_topic/` -- established main.yml routing, check mode, result counter patterns
- Codebase: `ansible/vars/sla_tiers.yml` -- SLA tier governance constants
- Codebase: `tests/ansible/test_cp_connect.py` -- established test patterns for Ansible roles
- [Confluent Platform REST Interface](https://docs.confluent.io/platform/current/connect/references/restapi.html) -- Connect REST API reference
- [Consul KV HTTP API](https://developer.hashicorp.com/consul/api-docs/kv) -- Consul KV store operations

### Secondary (MEDIUM confidence)
- [Confluent Monitor Kafka Connect](https://docs.confluent.io/platform/current/connect/monitoring.html) -- Connector monitoring and pause/resume behavior
- [Confluent Kafka Mirror Maker 2 and Connect REST API](https://forum.confluent.io/t/kafka-mirror-maker-2-0-and-kafka-connect-rest-api/1831) -- Community confirmation that MM2 connectors are managed via standard Connect REST API

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all APIs and libraries are already used in the codebase; no new dependencies
- Architecture: HIGH -- directly mirrors existing fsi-dr.sh MM2 backend and established Ansible role patterns
- Pitfalls: HIGH -- pitfalls derived from actual codebase behavior and documented limitations in fsi-dr.sh

**Research date:** 2026-04-09
**Valid until:** 2026-05-09 (stable domain -- Ansible patterns and Connect REST API are well-established)
