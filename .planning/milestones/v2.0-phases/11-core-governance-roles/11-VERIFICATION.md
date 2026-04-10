---
phase: 11-core-governance-roles
verified: 2026-04-09T02:15:00Z
status: human_needed
score: 17/17 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Run molecule test scenario for cp_topic"
    expected: "molecule test --scenario-name default in ansible/roles/cp_topic/ completes with zero failures including idempotency step"
    why_human: "Molecule test execution requires a live Ansible environment with molecule installed; cannot run programmatically in this context"
  - test: "Run molecule test scenarios for cp_schema and cp_rbac"
    expected: "Both complete with zero failures including idempotency steps"
    why_human: "Same reason as above"
  - test: "Run ansible-playbook with --check flag against cp_topic, cp_schema, cp_rbac roles"
    expected: "Playbook reports WOULD CREATE / WOULD UPDATE / WOULD DELETE / NO CHANGE correctly without making API mutations"
    why_human: "Requires a running CP cluster or mock that correctly handles GET requests in check mode"
---

# Phase 11: Core Governance Roles Verification Report

**Phase Goal:** Operators can create topics, register schemas, and provision RBAC bindings on a Confluent Platform cluster using Ansible roles -- with identical governance rules to Terraform and full idempotency

**Verified:** 2026-04-09T02:15:00Z
**Status:** human_needed (lint gap resolved by orchestrator — 3 human verification items remain)
**Re-verification:** No -- initial verification, lint gap auto-fixed

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | Operator can create topics on CP cluster via Ansible role using Admin REST v3 with idempotent GET-before-POST | VERIFIED | `create.yml`: GET /kafka/v3/clusters/{id}/topics/{name} -> 404=CREATE, 200=update; `retries: 3, delay: 5, until` pattern implemented |
| 2 | Topic config (partitions, retention, min.insync.replicas) is derived from SLA tier via fsi_sla_lookup filter | VERIFIED | `validate.yml`: `_topic_sla_tier | fsi_sla_lookup('partitions')`, `fsi_sla_lookup('retention_ms')`, `sla_tiers[_topic_sla_tier].min_insync_replicas` |
| 3 | Role consumes CPTopic YAML files from a directory path without requiring a new input format | VERIFIED | `main.yml`: `ansible.builtin.find + slurp + from_yaml` with `kind == 'CPTopic'` filter; `cp_topics_dir` and `cp_topics` inputs both supported |
| 4 | Topic names are validated against governance regex before any API call | VERIFIED | `validate.yml`: `ansible.builtin.assert` with `topic_item.metadata.name | fsi_validate_topic_name`; `process_one.yml` routes validate before create/update/delete |
| 5 | Existing topic configs converge to declared state without topic recreation | VERIFIED | `update.yml`: builds `_configs_to_alter` diff list, POSTs only changed configs to `/kafka/v3/clusters/{id}/topics/{name}/configs:alter` with `operation: SET` |
| 6 | Running with --check mode shows planned changes without mutations | VERIFIED | `check.yml`: all uri tasks have `check_mode: false` (forces GET execution); reports WOULD CREATE / WOULD UPDATE / NO CHANGE / WOULD DELETE; main.yml routes via `ansible_check_mode | bool` |
| 7 | Topic deletion requires state: absent + confirm_deletion: true, and blocks critical/compliance tier deletion | VERIFIED | `delete.yml`: `assert confirm_deletion | bool`, `assert _topic_sla_tier not in ['critical', 'compliance'] or force_delete_override | bool`; 404 is idempotent |
| 8 | Operator can register Avro schemas to CP Schema Registry via Ansible role using SR REST API | VERIFIED | `register.yml`: POST /subjects/{subject}/versions with `body_format: json`, `schemaType: AVRO`, `retries: 3` |
| 9 | Role runs compatibility pre-check on ALL schemas before any registration (two-pass pattern) | VERIFIED | `main.yml`: Pass 1 loops `compatibility.yml` for ALL schemas, collects `_compat_failures`, fails if any incompatible BEFORE running Pass 2 (`register.yml`) |
| 10 | Schema compatibility mode per subject is set from SLA tier via fsi_sla_lookup | VERIFIED | `compatibility.yml`: PUT /config/{subject} with body `compatibility: schema_item.sla_tier | fsi_sla_lookup('compatibility')` |
| 11 | Role invokes ci/scripts/validate-schemas.py for structural validation before SR API calls | VERIFIED | `validate.yml`: `ansible.builtin.command: python3 {{ cp_schema_validate_script }} --schemas-dir {{ cp_schemas_dir }}`; default `cp_schema_validate_script` points to `playbook_dir/../ci/scripts/validate-schemas.py`; script exists at `ci/scripts/validate-schemas.py` |
| 12 | PII metadata properties are applied to SR subjects matching Terraform metadata pattern | VERIFIED | `register.yml`: `metadata.properties` includes all 7 keys matching `modules/topic/main.tf` schema_metadata local: owner, sla-tier, data-classification, domain, application, pii, pii-fields |
| 13 | Operator can provision per-topic RBAC bindings (DeveloperWrite, DeveloperRead) via MDS REST API | VERIFIED | `topic_bindings.yml`: POST /security/1.0/principals/{p}/roles/DeveloperWrite/bindings and DeveloperRead/bindings with LITERAL resourcePatterns |
| 14 | MDS bearer token is acquired with automatic refresh before expiry for long playbook runs | VERIFIED | `authenticate.yml`: reads `_mds_auth_response.json.expires_in`, computes `_mds_token_expires_at = epoch + expires_in - margin`; `main.yml`: conditional `include_tasks: authenticate.yml` when `epoch >= _mds_token_expires_at` |
| 15 | Consumer group bindings with PREFIXED pattern are created alongside topic bindings | VERIFIED | `group_bindings.yml`: `resourceType: Group`, `name: "{{ item | regex_replace('^User:', '') }}-"`, `patternType: PREFIXED`; no asterisk (correct per MDS implicit prefix matching) |
| 16 | Schema Registry subject bindings (DeveloperWrite for producers, DeveloperRead for all) are created alongside topic bindings | VERIFIED | `sr_bindings.yml`: DeveloperWrite for producers and DeveloperRead for consumers on both `-value` and `-key` subjects; scope includes `schema-registry-cluster` |
| 17 | Role uses LIST/DIFF/ADD/REMOVE reconciliation to remove stale bindings | VERIFIED | `reconcile.yml`: POST resources per principal/role to list current, builds desired binding set tuples, DELETEs stale bindings (resourceType in Topic/Group/Subject only) |

**Score: 17/17 truths verified. All lint gaps resolved.**

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `ansible/roles/cp_topic/tasks/main.yml` | Role entry point: loads vars, validates, routes | VERIFIED | include_vars sla_tiers + naming_rules; find+slurp+parse CPTopic; ignore_errors loop; cp_topic_results output |
| `ansible/roles/cp_topic/tasks/create.yml` | GET-before-POST idempotent creation | VERIFIED | GET 200/404, POST on 404, configs GET+update on 200; | string filter on all config values |
| `ansible/roles/cp_topic/tasks/update.yml` | Config convergence via configs:alter | VERIFIED | Extracts current values, builds diff list, POSTs to configs:alter with operation: SET |
| `ansible/roles/cp_topic/tasks/delete.yml` | Guarded deletion with SLA tier protection | VERIFIED | confirm_deletion + force_delete_override guards; status_code includes 404 (idempotent) |
| `ansible/roles/cp_topic/tasks/check.yml` | Check-mode GET-only state diff reporting | VERIFIED | check_mode: false on all uri tasks; reports WOULD CREATE/UPDATE/DELETE/NO CHANGE |
| `ansible/roles/cp_topic/defaults/main.yml` | Default variables for cp_topic role | VERIFIED | cp_admin_rest_url, cp_cluster_id, credentials, cp_topics_dir, cp_topics, cp_topic_results |
| `ansible/roles/cp_topic/molecule/default/molecule.yml` | Delegated driver config | VERIFIED | driver.name: delegated; ansible_connection: local in inventory |
| `ansible/roles/cp_topic/molecule/default/converge.yml` | Test playbook with mock API | VERIFIED | Contains cp_topic role with correct vars; changed_when added by orchestrator fix (commit 768bcff) |
| `ansible/roles/cp_topic/molecule/default/verify.yml` | Idempotency assertion | VERIFIED | Runs role second time, asserts `second_run is not changed` |
| `tests/ansible/test_cp_topic.py` | Unit tests for cp_topic role | VERIFIED | 40 tests across 9 classes; all pass including test_sla_tier_derivation, TestCpTopicMolecule |
| `ansible/roles/cp_schema/defaults/main.yml` | Default variables for cp_schema role | VERIFIED | cp_sr_url, cp_schema_metadata_enabled, cp_schema_validate_structural, cp_schema_validate_script, cp_schema_results |
| `ansible/roles/cp_schema/tasks/main.yml` | Role entry point with two-pass flow | VERIFIED | ansible_check_mode routing; Pass 1 compat loop; fail if _compat_failures; Pass 2 register loop |
| `ansible/roles/cp_schema/tasks/validate.yml` | Structural validation via validate-schemas.py | VERIFIED | ansible.builtin.command with validate-schemas.py --schemas-dir; failed_when: false; fails on rc != 0 |
| `ansible/roles/cp_schema/tasks/compatibility.yml` | Compatibility pre-check per schema | VERIFIED | fsi_sla_lookup('compatibility') via PUT /config/{subject}; POST /compatibility/subjects/{s}/versions/latest?verbose=true; records _compat_failures |
| `ansible/roles/cp_schema/tasks/register.yml` | Schema registration with metadata | VERIFIED | POST /subjects/{s}/versions; schemaType: AVRO; 7-field metadata.properties; to_json; retries |
| `ansible/roles/cp_schema/tasks/check.yml` | Check-mode compatibility report | VERIFIED | check_mode: false on uri tasks; debug reporting |
| `ansible/roles/cp_schema/molecule/default/molecule.yml` | Delegated driver config | VERIFIED | driver: delegated |
| `ansible/roles/cp_schema/molecule/default/converge.yml` | Test playbook with mock SR API | VERIFIED | cp_schema role; changed_when: true on shell start task (lint-compliant) |
| `ansible/roles/cp_schema/molecule/default/verify.yml` | Idempotency assertion | VERIFIED | second_run is not changed assertion |
| `tests/ansible/test_cp_schema.py` | Unit tests for cp_schema role | VERIFIED | 44 tests across 11 classes; all pass |
| `ansible/roles/cp_rbac/tasks/main.yml` | cp_rbac entry point | VERIFIED | authenticate include; check_mode routing; binding loops with ignore_errors + noqa; token refresh; reconcile; cp_rbac_results |
| `ansible/roles/cp_rbac/tasks/authenticate.yml` | MDS token acquisition | VERIFIED | GET /security/1.0/authenticate; force_basic_auth; no_log; retries; dynamic _mds_token_expires_at from expires_in |
| `ansible/roles/cp_rbac/tasks/topic_bindings.yml` | DeveloperWrite/DeveloperRead topic bindings | VERIFIED | POST to /security/1.0/principals/{p}/roles/DeveloperWrite/bindings and DeveloperRead; LITERAL patternType; kafka-cluster scope |
| `ansible/roles/cp_rbac/tasks/group_bindings.yml` | Consumer group PREFIXED bindings | VERIFIED | PREFIXED patternType; regex_replace strips User: prefix; appends dash; NO asterisk |
| `ansible/roles/cp_rbac/tasks/sr_bindings.yml` | SR subject bindings | VERIFIED | DeveloperWrite+DeveloperRead for -value and -key subjects; schema-registry-cluster scope |
| `ansible/roles/cp_rbac/tasks/reconcile.yml` | LIST/DIFF/ADD/REMOVE stale cleanup | VERIFIED | POST /resources per principal/role; builds desired binding tuples; DELETE stale (resourceType filter) |
| `ansible/roles/cp_rbac/tasks/check.yml` | Check-mode binding diff | VERIFIED | check_mode: false on uri tasks |
| `ansible/roles/cp_rbac/molecule/default/molecule.yml` | Delegated driver config | VERIFIED | driver: delegated |
| `ansible/roles/cp_rbac/molecule/default/converge.yml` | Test playbook with mock MDS API | VERIFIED | cp_rbac role; changed_when: true on start, false on stop (lint-compliant) |
| `ansible/roles/cp_rbac/molecule/default/verify.yml` | Idempotency assertion | VERIFIED | second_run is not changed assertion |
| `tests/ansible/test_cp_rbac.py` | Unit tests for cp_rbac role | VERIFIED | 54 tests across 11 classes; all pass |
| `tests/ansible/fixtures/mock_responses/admin_rest_v3/` | Admin REST v3 mock fixtures | VERIFIED | 4 JSON files: topic_exists, topic_not_found, topic_configs, topic_created |
| `tests/ansible/fixtures/mock_responses/schema_registry/` | SR mock fixtures | VERIFIED | 5 JSON files: registered, compatible, incompatible, subject_config, subject_not_found |
| `tests/ansible/fixtures/mock_responses/mds/` | MDS mock fixtures | VERIFIED | 4 JSON files: authenticate, binding_created, list_resources, role_names |
| `tests/ansible/fixtures/cptopic_samples/` | CPTopic YAML samples | VERIFIED | corebanking-account-txn.yml, compliance-screening-result.yml |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `cp_topic/tasks/validate.yml` | `ansible/filter_plugins/fsi_governance.py` | `fsi_validate_topic_name` and `fsi_sla_lookup` Jinja2 filters | WIRED | Both filters used in validate.yml lines 18, 25-26 |
| `cp_topic/tasks/main.yml` | `ansible/vars/sla_tiers.yml` | `ansible.builtin.include_vars` | WIRED | Line 13: `file: "{{ role_path }}/../../vars/sla_tiers.yml"` |
| `cp_topic/tasks/create.yml` | Admin REST v3 API | POST to /kafka/v3/clusters/{id}/topics | WIRED | Lines 23, 43, 81 contain `kafka/v3/clusters` |
| `cp_topic/molecule/default/converge.yml` | `tests/ansible/fixtures/mock_responses/admin_rest_v3/` | Python HTTP mock server on port 18090 | WIRED | Mock server starts with changed_when: true (fixed by orchestrator) |
| `cp_schema/tasks/validate.yml` | `ci/scripts/validate-schemas.py` | `ansible.builtin.command` invocation | WIRED | `cmd: "python3 {{ cp_schema_validate_script }} --schemas-dir {{ cp_schemas_dir }}"` |
| `cp_schema/tasks/register.yml` | SR REST API | POST to /subjects/{subject}/versions | WIRED | `url: "{{ cp_sr_url }}/subjects/{{ schema_item.subject }}/versions"` |
| `cp_schema/tasks/compatibility.yml` | SR REST API | POST to /compatibility/subjects/{subject}/versions/latest | WIRED | `url: "{{ cp_sr_url }}/compatibility/subjects/{{ schema_item.subject }}/versions/latest?verbose=true"` |
| `cp_schema/molecule/default/converge.yml` | `tests/ansible/fixtures/mock_responses/schema_registry/` | Python HTTP mock server on port 18081 | WIRED | `changed_when: true` on start task (lint-compliant, auto-fixed in 11-02) |
| `cp_rbac/tasks/authenticate.yml` | MDS REST API | GET /security/1.0/authenticate with Basic Auth | WIRED | `url: "{{ cp_mds_url }}/security/1.0/authenticate"` with `force_basic_auth: true` |
| `cp_rbac/tasks/topic_bindings.yml` | MDS REST API | POST /security/1.0/principals/{p}/roles/{r}/bindings | WIRED | Lines 15, 45 |
| `cp_rbac/tasks/reconcile.yml` | MDS REST API | POST resources (list) then DELETE bindings | WIRED | `method: POST` resources endpoints; `method: DELETE` bindings endpoint (lines 134, 175) |
| `cp_rbac/molecule/default/converge.yml` | `tests/ansible/fixtures/mock_responses/mds/` | Python HTTP mock server on port 18092 | WIRED | `changed_when: true/false` correctly applied (lint-compliant) |

### Data-Flow Trace (Level 4)

No Level 4 data-flow check is applicable here. All three roles are Ansible automation (not web components rendering data). They produce side effects (API calls, binding creation) rather than rendering data fetched from stores. The unit tests validate role structure and governance wiring statically; actual API data flow requires a live CP cluster (flagged for human verification).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All 186 unit tests pass | `python3 -m pytest tests/ansible/ -v` | `186 passed in 0.16s` | PASS |
| cp_topic role task files pass ansible-lint | `ansible-lint ansible/roles/cp_topic/tasks/ --offline` | `0 failures, production profile` | PASS |
| cp_schema role passes ansible-lint | `ansible-lint ansible/roles/cp_schema/ --offline` | `0 failures, production profile` | PASS |
| cp_rbac role passes ansible-lint | `ansible-lint ansible/roles/cp_rbac/ --offline` | `0 failures, production profile` | PASS |
| cp_topic full role passes ansible-lint | `ansible-lint ansible/roles/cp_topic/ --offline` | `0 failures (changed_when added by orchestrator fix)` | PASS |
| SLA tier values match Terraform | Grep retention_map in main.tf vs sla_tiers.yml | critical=604800000, standard=259200000, best-effort=86400000 -- identical | PASS |
| Mock response fixtures are valid JSON | Python json.load on 6 fixture files | All loaded with expected keys | PASS |
| Module exports (filter_plugins) | test_fsi_governance_filter.py::TestFilterModule | PASSED | PASS |
| molecule.yml uses delegated driver (all 3 roles) | Grep driver.name in molecule.yml | All 3 contain `delegated` | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| ATOPIC-01 | 11-01-PLAN | Operator can create topics on CP cluster via Ansible role using Admin REST v3 API with idempotent GET-before-POST | SATISFIED | `create.yml` implements full GET-before-POST; retries; REQUIREMENTS.md shows `[x]` |
| ATOPIC-02 | 11-01-PLAN | Topic configuration derived from SLA tier using shared governance constants | SATISFIED | `validate.yml`: fsi_sla_lookup('partitions'), fsi_sla_lookup('retention_ms'); same SLA values as Terraform |
| ATOPIC-03 | 11-01-PLAN | Role consumes existing CPTopic YAML format from scenarios/cp-rhel/topics/*.yml | SATISFIED | `main.yml`: find+slurp+from_yaml filtering kind==CPTopic; cp_topics_dir supported |
| ATOPIC-04 | 11-01-PLAN | Validates topic names against regex before API calls | SATISFIED | `validate.yml`: `assert that: topic_item.metadata.name | fsi_validate_topic_name` |
| ATOPIC-05 | 11-01-PLAN | Topic config updates converge to declared state without recreating topics | SATISFIED | `update.yml`: configs:alter with diff-based SET operations |
| ATOPIC-06 | 11-01-PLAN | --check mode shows what would change without mutations | SATISFIED | `check.yml`: check_mode: false on uri; changed_when signals planned changes |
| ATOPIC-07 | 11-01-PLAN | Deletion requires explicit state:absent + confirm_deletion:true; blocks critical/compliance | SATISFIED | `delete.yml`: two assert gates + force_delete_override escape hatch |
| ASCHEMA-01 | 11-02-PLAN | Operator can register Avro schemas to CP Schema Registry via Ansible role | SATISFIED | `register.yml`: POST /subjects/{s}/versions; schemaType: AVRO |
| ASCHEMA-02 | 11-02-PLAN | Role runs compatibility pre-check before registration (two-pass) | SATISFIED | `main.yml`: compat loop for ALL schemas before any registration; fails entire run if any incompatible |
| ASCHEMA-03 | 11-02-PLAN | Schema compatibility mode set from SLA tier (FULL_TRANSITIVE/BACKWARD_TRANSITIVE/BACKWARD) | SATISFIED | `compatibility.yml`: fsi_sla_lookup('compatibility') via PUT /config/{subject} |
| ASCHEMA-04 | 11-02-PLAN | Role reuses ci/scripts/validate-schemas.py for structural validation | SATISFIED | `validate.yml`: ansible.builtin.command with validate-schemas.py; script exists on disk |
| ASCHEMA-05 | 11-02-PLAN | PII metadata properties applied matching Terraform module metadata pattern | SATISFIED | `register.yml`: 7-field metadata.properties: owner, sla-tier, data-classification, domain, application, pii, pii-fields |
| ARBAC-01 | 11-03-PLAN | Operator can provision per-topic RBAC bindings (DeveloperWrite/DeveloperRead) via MDS | SATISFIED | `topic_bindings.yml`: POST DeveloperWrite for producers, DeveloperRead for consumers |
| ARBAC-02 | 11-03-PLAN | MDS bearer token with automatic refresh for playbook runs exceeding token TTL | SATISFIED | `authenticate.yml`: expires_in from response; `main.yml`: conditional re-auth when epoch >= _mds_token_expires_at |
| ARBAC-03 | 11-03-PLAN | Consumer group bindings (DeveloperRead on prefixed group pattern) created alongside topic bindings | SATISFIED | `group_bindings.yml`: PREFIXED patternType; no asterisk; principal name prefix via regex_replace |
| ARBAC-04 | 11-03-PLAN | Schema Registry subject bindings created alongside topic bindings | SATISFIED | `sr_bindings.yml`: both -value and -key subjects; DeveloperWrite for producers, DeveloperRead for consumers; schema-registry-cluster scope |
| ARBAC-05 | 11-03-PLAN | LIST/DIFF/ADD/REMOVE reconciliation pattern to remove stale bindings | SATISFIED | `reconcile.yml`: POST resources to list current per principal/role; build desired tuples; DELETE stale (topic/group/subject filter) |

All 17 requirement IDs from phase plans are accounted for. REQUIREMENTS.md coverage table shows all 17 as Phase 11 / Complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
None found. The lint violations in cp_topic converge.yml (missing changed_when on shell tasks) were fixed by the orchestrator in commit 768bcff.

No anti-patterns found in production role task files for any of the three roles. No TODO/FIXME/placeholder content. No hardcoded empty returns. No stub implementations.

### Human Verification Required

#### 1. Molecule Test Execution (all three roles)

**Test:** Run `molecule test --scenario-name default` in each of `ansible/roles/cp_topic/`, `ansible/roles/cp_schema/`, `ansible/roles/cp_rbac/`

**Expected:** All three scenarios complete with zero test failures; idempotency step reports zero changed tasks on second converge run

**Why human:** Molecule execution requires a working Ansible environment with molecule, ansible-core 2.15+, and Python HTTP server capability. Cannot run programmatically without that environment.

#### 2. Check-mode dry run against a live or mock CP endpoint

**Test:** Run one of the three roles in `--check` mode against a CP endpoint (or full mock)

**Expected:** Playbook reports planned changes (WOULD CREATE / WOULD UPDATE / NO CHANGE) without making any API mutations; CAB approval workflow confirmed functional

**Why human:** Requires a running CP cluster or a mock server that handles the full Admin REST v3 / SR / MDS API surface.

#### 3. End-to-end topic lifecycle (create -> update -> delete)

**Test:** Run cp_topic role to create a topic, then run again with changed retention to converge, then run with state: absent + confirm_deletion: true

**Expected:** First run creates topic (changed); second run updates retention only (changed); third run deletes (changed); fourth run on absent topic is a no-op (unchanged)

**Why human:** Requires a live CP cluster with Admin REST v3 enabled.

### Gaps Summary

No gaps remain. The original lint gap (cp_topic converge.yml missing changed_when on 2 shell tasks) was fixed by the orchestrator in commit 768bcff. All 17 functional requirements are satisfied. All 186 unit tests pass. All 3 roles pass ansible-lint at shared profile with zero violations.

---

_Verified: 2026-04-09T02:15:00Z_
_Verifier: Claude (gsd-verifier)_
