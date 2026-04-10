# Phase 15: MRC Failover and DR Drill - Research

**Researched:** 2026-04-10
**Domain:** Ansible MRC observer promotion for RPO=0 DR and full-cycle DR drill playbook with compliance reporting
**Confidence:** HIGH

## Summary

Phase 15 delivers two capabilities that complete the v2.0 Ansible DR automation story: (1) a `cp_dr_mrc` role that performs Multi-Region Cluster observer promotion for RPO=0 disaster recovery scenarios, and (2) a DR drill playbook that orchestrates a full failover-validate-failback-validate cycle and generates a timestamped compliance evidence report for quarterly regulatory submission.

The MRC DR mechanism is fundamentally different from MM2. MM2 uses Connect REST API connector management (pause/resume/delete/create). MRC uses Kafka's native leader election mechanism via `kafka-leader-election.sh` CLI tool. In MRC with `observerPromotionPolicy: under-min-isr` (CP 6.1+), observers auto-promote to ISR when sync replicas go offline. The explicit failover step triggers UNCLEAN leader election to elect an observer as leader. Failback uses PREFERRED leader election after primary DC brokers recover and rejoin ISR.

The DR drill playbook is a higher-level orchestration playbook (not a role) that sequences: pre-drill state snapshot, failover via cp_dr_mrc or cp_dr_mm2 role, post-failover validation, failback, post-failback validation, and compliance report generation. The report captures timestamps, step results, pass/fail verdicts, and metadata required for regulatory audit (OCC/FDIC quarterly DR testing evidence).

**Primary recommendation:** Build `cp_dr_mrc` role mirroring the cp_dr_mm2 structure (defaults, meta, tasks, molecule). Use `ansible.builtin.command` for `kafka-leader-election.sh` invocations with `changed_when`/`failed_when` guards. Build the DR drill playbook as `ansible/playbooks/dr-drill.yml` that composes existing roles. Generate the compliance report via `ansible.builtin.template` rendering a Jinja2 template to a timestamped file.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None explicitly locked -- all implementation choices at Claude's discretion per CONTEXT.md.

### Claude's Discretion
All implementation choices are at Claude's discretion -- pure infrastructure phase. Key patterns to follow:
- Role structure matches cp_dr_mm2 patterns (defaults, meta, tasks, molecule, tests)
- MRC observer promotion uses Confluent CLI (`confluent kafka replica promote`) not REST API
- DR drill playbook composes existing MM2 failover/failback roles with MRC role
- Compliance report is a structured Markdown/YAML file with timestamps, step results, and pass/fail verdict
- Reuse sla_tiers.yml, consul_flip.yml patterns from Phase 13

### Deferred Ideas (OUT OF SCOPE)
None -- discuss phase skipped.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ADR-05 | MRC failover playbook promotes observer replica to leader for RPO=0 scenarios using Confluent CLI | `kafka-leader-election.sh` with `--election-type UNCLEAN` for failover and `--election-type PREFERRED` for failback; existing `mrc_failover_mirrors()` in fsi-dr.sh provides proven pattern; `kafka-replica-status.sh` for post-promotion validation |
| ADR-06 | DR drill playbook runs full cycle (failover -> validate -> failback -> validate -> generate compliance report) for quarterly regulatory requirements | Compose cp_dr_mrc (or cp_dr_mm2) roles in sequence; collect timestamped results from each phase; render Jinja2 compliance template with pass/fail verdict |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **`ansible.builtin.uri` for all REST API operations** -- no custom Python modules, no community.general.consul_kv
- **`ansible.builtin.command` for CLI invocations** -- with `changed_when`/`failed_when` guards per established pattern
- **`failed_when: false` for error collection** (ansible-lint shared profile compliance)
- **Task names start with uppercase, Jinja at end only** (name[casing] and name[template] rules)
- **FQCN enforcement** -- all module references use full namespace
- **Molecule default scenario** for each role with delegated driver
- **var_naming_pattern: `^[a-z_][a-z0-9_]*$`** for all variables
- **Profile: shared** in ansible-lint with FQCN enabled
- **CP version 7.7.0** in all inventory references
- **Confluent Platform only** -- no CC Ansible (CC stays Terraform-only)
- **TDD: tests first (RED), then implementation (GREEN)**
- **`noqa ignore-errors` on include_tasks** for locked error collection decision
- **Disjoint tag sets per play** in site.yml to prevent import_playbook tag inheritance leakage

## Critical Research Finding: CLI Command Correction

**CONTEXT.md states:** "MRC observer promotion uses Confluent CLI (`confluent kafka replica promote`) not REST API"

**Research finding:** The `confluent kafka replica promote` command does NOT exist in the Confluent CLI. The `confluent kafka replica` subcommand tree contains only `list` and `status` (with `status list` sub-subcommand). There is no `promote` subcommand.

The `confluent kafka mirror promote` command exists but is for Cluster Linking mirror topics, not MRC observer replicas. MRC observer promotion is handled by:
- **Automatic:** `observerPromotionPolicy: under-min-isr` (default in replica placement v2) -- observers auto-promote to ISR when sync replicas fail
- **Manual leader election:** `kafka-leader-election.sh --election-type UNCLEAN --path-to-json-file <file>` (promote specific observer partitions to leader)
- **Failback/rebalance:** `kafka-leader-election.sh --election-type PREFERRED --all-topic-partitions` (move leadership back to preferred replicas)

The existing `scripts/fsi-dr.sh` MRC backend already uses `kafka-leader-election.sh` correctly. The Ansible role should follow this same approach using `ansible.builtin.command`.

**Recommendation:** Use `kafka-leader-election.sh` via `ansible.builtin.command` (matching the proven fsi-dr.sh pattern). Use `confluent kafka replica status list` for post-promotion validation to check observer/ISR state.

**Confidence:** HIGH -- verified against official Confluent documentation and Confluent CLI command reference.

**Sources:**
- [confluent kafka replica](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/replica/index.html) -- only `list` and `status` subcommands
- [confluent kafka replica list](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/replica/confluent_kafka_replica_list.html) -- lists partition replicas
- [Configure Multi-Region Clusters](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region.html) -- `kafka-leader-election` usage

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ansible-core | 2.15+ | Automation engine | cp-ansible 7.7.x requirement |
| confluent.platform | 7.7.8 | CP deployment roles (pattern reference) | Pinned in requirements.yml |

### CLI Tools Used (on target host)
| Tool | Ships With | Purpose | Auth |
|------|-----------|---------|------|
| kafka-leader-election.sh | Confluent Platform 7.7.x | Trigger UNCLEAN/PREFERRED leader election for MRC failover/failback | `--command-config` properties file |
| kafka-replica-status.sh | Confluent Platform 7.7.x | Monitor observer replica lag and ISR membership | `--bootstrap-server` + optional `--command-config` |
| kafka-topics.sh | Confluent Platform 7.7.x | List topics for partition election JSON generation | `--bootstrap-server` + optional `--command-config` |
| confluent kafka replica list | Confluent CLI v4+ | List partition-replicas (alternative to kafka-replica-status.sh) | `--url` REST Proxy endpoint |
| confluent kafka replica status list | Confluent CLI v4+ | Check replica status (observer/ISR membership) | `--url` REST Proxy endpoint |

### APIs Used (for validation, not MRC-specific)
| API | Base URL | Purpose | Auth |
|-----|----------|---------|------|
| Consul HTTP API | `consul_url:8500` | KV store for active-region flip | Token or ACL |
| Admin REST v3 API | `admin_rest_url` | Topic writability validation | MDS bearer token |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| kafka-leader-election.sh via command | confluent kafka mirror promote | `mirror promote` is for Cluster Linking, NOT MRC; wrong tool |
| kafka-leader-election.sh via command | Admin REST API for leader election | No documented REST endpoint for leader election; CLI is the canonical approach |
| Jinja2 template for compliance report | Python callback plugin | Template is simpler, auditable, and follows existing Ansible patterns |
| Standalone dr-drill.yml playbook | DR drill as a role | Drill orchestrates multiple roles; playbook composition is the correct pattern |

## Architecture Patterns

### Recommended Project Structure
```
ansible/
  roles/
    cp_dr_mrc/
      defaults/main.yml          # All configurable variables (bootstrap, racks, command-config)
      meta/main.yml              # Galaxy metadata (role_name, min_ansible_version)
      tasks/
        main.yml                 # Entry point: routes to check or action mode
        check.yml                # Dry-run: GET-only operations, audit output
        failover.yml             # UNCLEAN leader election for observer promotion
        failback.yml             # PREFERRED leader election for primary recovery
        validate_state.yml       # Pre/post validation: observer lag, ISR state, writability
        consul_flip.yml          # Consul KV active-region update (reuses cp_dr_mm2 pattern)
      templates/
        unclean_election.json.j2 # Partition election JSON for UNCLEAN election
      molecule/
        default/
          molecule.yml           # Delegated driver, localhost
          converge.yml           # Run role with mocked CLI commands
          verify.yml             # Assert results variables are correct
  playbooks/
    dr-failover-mrc.yml          # Operator-facing MRC failover playbook
    dr-failback-mrc.yml          # Operator-facing MRC failback playbook
    dr-drill.yml                 # Full-cycle DR drill with compliance report
  templates/
    dr-drill-report.md.j2        # Compliance report Jinja2 template
tests/ansible/
  test_cp_dr_mrc.py              # Unit tests for MRC role structure and tasks
  test_dr_drill.py               # Unit tests for DR drill playbook and report template
```

### Pattern 1: MRC Failover via ansible.builtin.command

**What:** Invoke `kafka-leader-election.sh` using `ansible.builtin.command` with structured `changed_when`/`failed_when` guards, matching the project convention for CLI tools.

**When to use:** All MRC leader election operations. MRC does not have a REST API for leader election -- CLI is the canonical approach.

**Example:**
```yaml
# Source: fsi-dr.sh mrc_failover_mirrors() translated to Ansible
- name: Trigger UNCLEAN leader election for observer promotion
  ansible.builtin.command:
    cmd: >-
      kafka-leader-election.sh
      --bootstrap-server {{ cp_dr_mrc_bootstrap }}
      {{ '--command-config ' ~ cp_dr_mrc_command_config if cp_dr_mrc_command_config | length > 0 else '' }}
      --election-type UNCLEAN
      --path-to-json-file {{ _election_json_path }}
  register: _election_result
  changed_when: _election_result.rc == 0
  failed_when: false
```

### Pattern 2: Consul Flip Reuse

**What:** Reuse the consul_flip.yml pattern from cp_dr_mm2 with variable name substitution.

**When to use:** Both MRC failover and MRC failback need Consul region flip. Copy the consul_flip.yml from cp_dr_mm2 and update variable names from `cp_dr_mm2_*` to `cp_dr_mrc_*`.

**Example:**
```yaml
# Same Consul HTTP API pattern as cp_dr_mm2
- name: Update Consul active-region to target
  ansible.builtin.uri:
    url: "{{ cp_dr_mrc_consul_url }}/v1/kv/{{ cp_dr_mrc_consul_kv_key }}"
    method: PUT
    body: "{{ cp_dr_mrc_target_region }}"
    status_code:
      - 200
  when: not (ansible_check_mode | bool)
```

### Pattern 3: DR Drill Playbook Orchestration

**What:** A multi-play playbook that sequences failover, validation, failback, validation, and report generation. Each step captures timestamps and results for compliance evidence.

**When to use:** Quarterly DR drill exercises for regulatory compliance.

**Example:**
```yaml
# dr-drill.yml -- orchestrates full DR exercise
- name: "DR drill -- Pre-drill state snapshot"
  hosts: kafka_broker[0]
  gather_facts: true
  tasks:
    - name: Record drill start timestamp
      ansible.builtin.set_fact:
        _drill_start: "{{ ansible_date_time.iso8601 }}"
        _drill_steps: []

- name: "DR drill -- Failover"
  hosts: kafka_broker[0]
  gather_facts: false
  tasks:
    - name: Execute failover via selected DR backend
      ansible.builtin.include_role:
        name: "{{ dr_drill_backend | default('cp_dr_mrc') }}"
      vars:
        # operation set to failover by default in role defaults
        cp_dr_mrc_operation: failover

- name: "DR drill -- Failback"
  hosts: kafka_broker[0]
  gather_facts: false
  tasks:
    - name: Execute failback via selected DR backend
      ansible.builtin.include_role:
        name: "{{ dr_drill_backend | default('cp_dr_mrc') }}"
      vars:
        cp_dr_mrc_operation: failback

- name: "DR drill -- Generate compliance report"
  hosts: kafka_broker[0]
  gather_facts: true
  tasks:
    - name: Render compliance report from template
      ansible.builtin.template:
        src: dr-drill-report.md.j2
        dest: "{{ dr_drill_report_dir }}/dr-drill-{{ ansible_date_time.date }}.md"
```

### Pattern 4: Compliance Report Template

**What:** A Jinja2 template that renders a structured Markdown report with timestamps, step results, pass/fail verdicts, and regulatory metadata.

**When to use:** DR drill report generation as the final step of the drill playbook.

**Example report structure:**
```markdown
# DR Drill Compliance Report
**Date:** {{ drill_start_time }}
**Environment:** {{ inventory_hostname }}
**DR Backend:** {{ dr_drill_backend }}
**Overall Verdict:** {{ 'PASS' if all_steps_passed else 'FAIL' }}

## Drill Steps
| Step | Action | Start | End | Duration | Result |
|------|--------|-------|-----|----------|--------|
| 1 | Pre-drill snapshot | ... | ... | ...s | PASS |
| 2 | Failover execution | ... | ... | ...s | PASS |
| 3 | Post-failover validation | ... | ... | ...s | PASS |
| 4 | Failback execution | ... | ... | ...s | PASS |
| 5 | Post-failback validation | ... | ... | ...s | PASS |

## Regulatory Attestation
This report certifies that a full DR failover/failback cycle was executed
and validated on the above date per OCC/FDIC quarterly testing requirements.
```

### Pattern 5: MRC vs MM2 Operation Differences

**What:** The cp_dr_mrc role has a fundamentally different mechanism than cp_dr_mm2.

| Aspect | cp_dr_mm2 (Phase 13) | cp_dr_mrc (Phase 15) |
|--------|---------------------|---------------------|
| Replication mechanism | MM2 connectors (Connect REST API) | Observer replicas (Kafka native) |
| Failover action | Pause MM2 connectors | UNCLEAN leader election |
| Failback action | Delete+recreate reversed connectors | PREFERRED leader election |
| RPO | > 0 (async replication lag) | = 0 (synchronous replication to ISR) |
| No connector management | N/A | Correct -- MRC has no connectors |
| Consul flip | Yes (same pattern) | Yes (same pattern) |
| State validation | Connector health + writability | Observer ISR membership + writability |
| CLI dependency | None (REST only) | kafka-leader-election.sh required |

### Anti-Patterns to Avoid
- **Using `confluent kafka mirror promote` for MRC:** This command is for Cluster Linking mirror topics, not MRC observer replicas. Will silently do nothing or fail.
- **Using `ignore_errors: true`:** Use `failed_when: false` instead for ansible-lint shared profile compliance.
- **Skipping election JSON for UNCLEAN election:** UNCLEAN election requires `--path-to-json-file` with explicit partition list. `--all-topic-partitions` only works with PREFERRED.
- **Assuming observers are already leaders after auto-promotion:** Auto-promotion adds observers to ISR but does NOT make them leaders. Leader election is still needed.
- **Hardcoding topic list in election JSON:** Generate dynamically from `kafka-topics.sh --list` or accept as role variable.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Leader election | Custom REST API calls | kafka-leader-election.sh via command | No REST API exists for leader election |
| Observer lag monitoring | Manual offset comparison | kafka-replica-status.sh | Handles ISR/observer distinction, provides LastCaughtUpLagMs |
| Consul KV operations | community.general.consul_kv | ansible.builtin.uri against Consul HTTP API | Project convention -- uri for all REST |
| Report rendering | Inline debug/set_fact string assembly | ansible.builtin.template with Jinja2 | Cleaner, maintainable, auditable template file |
| Timestamp collection | Manual epoch arithmetic | ansible_date_time facts | Built-in, consistent formatting |

## Common Pitfalls

### Pitfall 1: UNCLEAN vs PREFERRED Election Type Confusion
**What goes wrong:** Using `--election-type PREFERRED` for failover when primary DC is down. PREFERRED election selects from the preferred replica list (which is in the failed DC), so no election occurs.
**Why it happens:** PREFERRED sounds like "the one I want" but actually means "revert to original preferred leader assignment."
**How to avoid:** Failover = UNCLEAN (elect any available replica, including observers). Failback = PREFERRED (revert to original preferred leaders after primary recovers).
**Warning signs:** Leader election command succeeds but leadership doesn't change.

### Pitfall 2: UNCLEAN Election Requires Partition JSON File
**What goes wrong:** Attempting `kafka-leader-election.sh --election-type UNCLEAN --all-topic-partitions` fails because `--all-topic-partitions` is only valid with PREFERRED election.
**Why it happens:** UNCLEAN election is dangerous (potential data loss) so Kafka requires explicit partition targeting.
**How to avoid:** Generate a JSON file listing all partitions for each topic, then pass via `--path-to-json-file`. The role should dynamically build this from `kafka-topics.sh --describe`.
**Warning signs:** CLI exits with error about incompatible flags.

### Pitfall 3: Observer Auto-Promotion vs Leader Election
**What goes wrong:** Assuming observers automatically become leaders after auto-promotion.
**Why it happens:** With `observerPromotionPolicy: under-min-isr`, observers join the ISR automatically. But joining ISR != becoming leader. A separate leader election is needed.
**How to avoid:** After observers are in ISR (verify via replica-status), trigger explicit leader election to move leadership.
**Warning signs:** Producers can't write because no leader is available even though observers are in ISR.

### Pitfall 4: Molecule Testing CLI Commands
**What goes wrong:** Molecule converge fails because `kafka-leader-election.sh` is not installed on the test runner.
**Why it happens:** Unlike REST API calls (which can be mocked with http.server), CLI tools require the Confluent Platform binaries.
**How to avoid:** Create a mock `kafka-leader-election.sh` shell script in the molecule scenario that echoes expected output and exits 0. Place in PATH during molecule converge. Alternatively, use `check_mode: true` in molecule converge to skip CLI execution.
**Warning signs:** Molecule tests fail with "command not found."

### Pitfall 5: DR Drill Playbook Variable Scope
**What goes wrong:** Variables set in one play (like drill timestamps or step results) are not visible in subsequent plays.
**Why it happens:** Ansible plays have separate variable scopes. `set_fact` in Play 1 is not available in Play 2 unless using `cacheable: true` (requires fact caching) or the variable is set on the same host.
**How to avoid:** Use `set_fact` with the same host across plays (since all plays target `kafka_broker[0]`, facts persist). Or use `add_host` to pass variables via a dummy host group. Or collect results at playbook level using `run_once` and a shared fact name.
**Warning signs:** Jinja2 "undefined variable" errors in the report generation play.

### Pitfall 6: Check Mode for command Module
**What goes wrong:** `ansible.builtin.command` always shows "changed" in check mode because Ansible can't predict command outcomes.
**Why it happens:** The command module doesn't know what the shell command does. Unlike uri which can be made safe with `check_mode: false`, command needs explicit guards.
**How to avoid:** Gate command tasks with `when: not (ansible_check_mode | bool)`. In check mode, log the would-be command via debug instead.
**Warning signs:** Check mode reports all command tasks as "changed" even though nothing executed.

## Code Examples

### MRC Role defaults/main.yml
```yaml
# Source: Adapted from cp_dr_mm2 defaults and fsi-dr.sh MRC environment variables
---
cp_dr_mrc_operation: failover

# Kafka cluster (MRC stretch cluster)
cp_dr_mrc_bootstrap: "localhost:9092"
cp_dr_mrc_command_config: ""

# Rack IDs for multi-region placement
cp_dr_mrc_east_rack: "us-east"
cp_dr_mrc_west_rack: "us-west"
cp_dr_mrc_observer_rack: "us-central"
cp_dr_mrc_target_region: "west"

# Consul HTTP API
cp_dr_mrc_consul_url: "http://localhost:8500"
cp_dr_mrc_consul_kv_key: "fsi/kafka/active-region"

# Admin REST v3 (for topic writability validation)
cp_dr_mrc_admin_rest_url: ""
cp_dr_mrc_cluster_id: ""
cp_dr_mrc_admin_rest_token: ""

# Validation toggles
cp_dr_mrc_validate_observers: true
cp_dr_mrc_validate_writability: true

# Election configuration
cp_dr_mrc_election_json_dir: "/tmp"
cp_dr_mrc_election_wait_seconds: 5

# Output variable for downstream orchestration (same shape as cp_dr_mm2)
cp_dr_mrc_results:
  operation: ""
  election_type: ""
  election_triggered: false
  consul_flipped: false
  validation_passed: false
  audit_log: []
```

### MRC Failover Task (failover.yml)
```yaml
# Source: fsi-dr.sh mrc_failover_mirrors() + Confluent MRC docs
---
# --- Step 1: Build election JSON from topic list -------------------------
- name: "Step 1: List topics for election JSON"
  ansible.builtin.command:
    cmd: >-
      kafka-topics.sh
      --bootstrap-server {{ cp_dr_mrc_bootstrap }}
      {{ '--command-config ' ~ cp_dr_mrc_command_config if cp_dr_mrc_command_config | length > 0 else '' }}
      --list
  register: _topic_list
  changed_when: false
  failed_when: false
  when: not (ansible_check_mode | bool)

- name: "Step 1: Generate UNCLEAN election JSON for all partitions"
  ansible.builtin.template:
    src: unclean_election.json.j2
    dest: "{{ cp_dr_mrc_election_json_dir }}/unclean_election.json"
    mode: '0644'
  when: not (ansible_check_mode | bool)

# --- Step 2: Trigger UNCLEAN leader election for observer promotion ------
- name: "Step 2: Trigger UNCLEAN leader election for MRC failover"
  ansible.builtin.command:
    cmd: >-
      kafka-leader-election.sh
      --bootstrap-server {{ cp_dr_mrc_bootstrap }}
      {{ '--command-config ' ~ cp_dr_mrc_command_config if cp_dr_mrc_command_config | length > 0 else '' }}
      --election-type UNCLEAN
      --path-to-json-file {{ cp_dr_mrc_election_json_dir }}/unclean_election.json
  register: _election_result
  changed_when: _election_result.rc == 0
  failed_when: false
  when: not (ansible_check_mode | bool)

# --- Step 3: Wait for election to propagate ------------------------------
- name: "Step 3: Wait for leader election to propagate"
  ansible.builtin.pause:
    seconds: "{{ cp_dr_mrc_election_wait_seconds }}"
  when: not (ansible_check_mode | bool)

# --- Step 4: Flip Consul active-region to target DC ---------------------
- name: "Step 4: Flip Consul active-region to target"
  ansible.builtin.include_tasks:
    file: consul_flip.yml
```

### DR Drill Report Template (dr-drill-report.md.j2)
```jinja2
# DR Drill Compliance Report

**Drill ID:** {{ _drill_id }}
**Date:** {{ _drill_start }}
**Completed:** {{ _drill_end }}
**Duration:** {{ _drill_duration_seconds }}s
**Environment:** {{ inventory_hostname }}
**DR Backend:** {{ dr_drill_backend | default('cp_dr_mrc') }}
**Overall Verdict:** {{ 'PASS' if _drill_all_passed else 'FAIL' }}

---

## Executive Summary

A full disaster recovery drill was executed on {{ _drill_start | regex_replace('T.*', '') }}.
The drill exercised {{ dr_drill_backend | default('MRC observer promotion') }} failover
and failback with state validation at each step.

**Result: {{ 'ALL STEPS PASSED' if _drill_all_passed else 'ONE OR MORE STEPS FAILED' }}**

## Drill Steps

| # | Step | Start | End | Duration | Result |
|---|------|-------|-----|----------|--------|
{% for step in _drill_steps %}
| {{ step.number }} | {{ step.name }} | {{ step.start }} | {{ step.end }} | {{ step.duration }}s | {{ step.result }} |
{% endfor %}

## Validation Details

### Post-Failover
- Observer promotion: {{ _failover_results.election_triggered | default('N/A') }}
- Consul region: {{ _failover_results.consul_flipped | default('N/A') }}
- Validation passed: {{ _failover_results.validation_passed | default('N/A') }}

### Post-Failback
- Leader rebalance: {{ _failback_results.election_triggered | default('N/A') }}
- Consul region: {{ _failback_results.consul_flipped | default('N/A') }}
- Validation passed: {{ _failback_results.validation_passed | default('N/A') }}

## Regulatory Attestation

This report certifies that a full DR failover/failback cycle was executed
and validated on the above date. This evidence supports quarterly DR
testing requirements per OCC SR 20-13, FDIC FIL-67-2006, and internal
BCM policy.

**Prepared by:** Automated DR Drill Playbook (ansible)
**Report generated:** {{ ansible_date_time.iso8601 }}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual kafka-leader-election.sh invocation | Ansible role with structured check mode + audit | Phase 15 (new) | Repeatable, auditable, operator-friendly |
| Manual DR drill with spreadsheet evidence | Automated drill playbook with generated compliance report | Phase 15 (new) | Quarterly compliance effort reduced from hours to minutes |
| observerPromotionPolicy: leader-is-observer (v1) | observerPromotionPolicy: under-min-isr (v2, default) | CP 6.1 (2021) | Auto-promotion to ISR without manual intervention |
| No observer status monitoring | kafka-replica-status.sh with --observers flag | CP 5.4+ | Per-partition observer lag visibility |

## Open Questions

1. **UNCLEAN election partition list generation**
   - What we know: UNCLEAN election requires `--path-to-json-file` with explicit partition list. `kafka-topics.sh --describe` can provide topic/partition info.
   - What's unclear: Whether to include all topics or only user topics (exclude internal `__*` topics). The fsi-dr.sh uses `--all-topic-partitions` with PREFERRED but UNCLEAN needs explicit JSON.
   - Recommendation: Generate JSON from `kafka-topics.sh --describe`, filtering out internal topics (`__consumer_offsets`, `__transaction_state`, `_confluent*`). Accept an override list via `cp_dr_mrc_topics` variable.

2. **DR drill backend selection**
   - What we know: The drill playbook should support both cp_dr_mrc and cp_dr_mm2 backends.
   - What's unclear: Whether to use a single `dr_drill_backend` variable or separate playbooks per backend.
   - Recommendation: Use `dr_drill_backend` variable defaulting to `cp_dr_mrc`. The role's results variable naming (`cp_dr_mrc_results` vs `cp_dr_mm2_results`) needs abstraction in the drill playbook.

3. **Molecule testing without Confluent Platform binaries**
   - What we know: kafka-leader-election.sh is a CP binary not available in CI.
   - What's unclear: Best approach for mocking CLI tools in molecule.
   - Recommendation: Run molecule converge in check mode (like CFK roles in Phase 14). This avoids CLI execution while still validating task structure, variable handling, and check mode audit output.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest + pyyaml |
| Config file | None -- uses conftest.py in tests/ansible/ |
| Quick run command | `pytest tests/ansible/test_cp_dr_mrc.py -x` |
| Full suite command | `pytest tests/ansible/ -v` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ADR-05 | MRC role structure, defaults, task files, failover/failback sequences, check mode, FQCN, molecule | unit | `pytest tests/ansible/test_cp_dr_mrc.py -x` | Wave 0 |
| ADR-06 | DR drill playbook structure, backend selection, report template, step composition | unit | `pytest tests/ansible/test_dr_drill.py -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `pytest tests/ansible/test_cp_dr_mrc.py tests/ansible/test_dr_drill.py -x`
- **Per wave merge:** `pytest tests/ansible/ -v`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/ansible/test_cp_dr_mrc.py` -- covers ADR-05 (MRC role structure, tasks, defaults, FQCN, molecule)
- [ ] `tests/ansible/test_dr_drill.py` -- covers ADR-06 (drill playbook, report template, step sequencing)

## Sources

### Primary (HIGH confidence)
- [Configure Multi-Region Clusters](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region.html) -- observer promotion policies, kafka-leader-election usage, kafka-replica-status.sh
- [confluent kafka replica CLI](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/replica/index.html) -- confirmed no `promote` subcommand exists
- [confluent kafka replica list](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/replica/confluent_kafka_replica_list.html) -- list replica assignments
- [confluent kafka replica status list](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/replica/status/confluent_kafka_replica_status_list.html) -- replica status check
- Existing codebase: `scripts/fsi-dr.sh` MRC backend (lines 871-1101) -- proven failover/failback pattern
- Existing codebase: `ansible/roles/cp_dr_mm2/` -- complete role structure to mirror

### Secondary (MEDIUM confidence)
- [Automatic Observer Promotion blog](https://www.confluent.io/blog/automatic-observer-promotion-for-safe-multi-datacenter-failover-in-confluent-6-1/) -- observerPromotionPolicy details
- [Multi-Region Tutorial](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region-tutorial.html) -- JMX metrics for observer monitoring

### Tertiary (LOW confidence)
- Compliance report format is based on OCC/FDIC DR testing evidence patterns -- actual regulatory template format varies by institution

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- kafka-leader-election.sh is the canonical MRC tool, verified against Confluent docs and existing fsi-dr.sh
- Architecture: HIGH -- directly mirrors proven cp_dr_mm2 patterns with MRC-specific adaptations
- Pitfalls: HIGH -- UNCLEAN vs PREFERRED distinction verified in Confluent docs; molecule CLI mocking based on Phase 14 CFK check-mode pattern
- Compliance report: MEDIUM -- template structure is reasonable but actual regulatory format varies by institution

**Research date:** 2026-04-10
**Valid until:** 2026-05-10 (30 days -- stable Confluent Platform features)
