---
phase: 11-core-governance-roles
created: 2026-04-08
status: active
---

# Phase 11: Validation Strategy

## Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.4.2 + molecule (delegated driver) |
| Config file | `tests/ansible/conftest.py` (existing from Phase 10) |
| Quick run command | `python3 -m pytest tests/ansible/ -x --tb=short` |
| Full suite command | `python3 -m pytest tests/ansible/ -v` |

## Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command |
|--------|----------|-----------|-------------------|
| ATOPIC-01 | Idempotent topic creation via Admin REST v3 | unit + molecule | `python3 -m pytest tests/ansible/test_cp_topic.py -x` |
| ATOPIC-02 | SLA tier derivation for topic config | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_sla_tier_derivation -x` |
| ATOPIC-03 | CPTopic YAML consumption | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_cptopic_yaml_parsing -x` |
| ATOPIC-04 | Topic name validation before API calls | unit | Covered by existing `test_fsi_governance_filter.py` (Phase 10) |
| ATOPIC-05 | Config convergence without recreation | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_config_update -x` |
| ATOPIC-06 | Check mode shows planned changes | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_check_mode -x` |
| ATOPIC-07 | Guarded deletion with tier protection | unit | `python3 -m pytest tests/ansible/test_cp_topic.py::test_deletion_guards -x` |
| ASCHEMA-01 | Schema registration via SR REST API | unit + molecule | `python3 -m pytest tests/ansible/test_cp_schema.py -x` |
| ASCHEMA-02 | Two-pass compatibility pre-check | unit | `python3 -m pytest tests/ansible/test_cp_schema.py::test_compatibility_check -x` |
| ASCHEMA-03 | Subject compatibility from SLA tier | unit | `python3 -m pytest tests/ansible/test_cp_schema.py::test_compatibility_mode -x` |
| ASCHEMA-04 | Reuse validate-schemas.py | unit | `python3 -m pytest tests/ansible/test_cp_schema.py::test_schema_validation -x` |
| ASCHEMA-05 | PII metadata properties on subjects | unit | `python3 -m pytest tests/ansible/test_cp_schema.py::test_metadata_properties -x` |
| ARBAC-01 | Per-topic RBAC bindings via MDS | unit + molecule | `python3 -m pytest tests/ansible/test_cp_rbac.py -x` |
| ARBAC-02 | MDS token refresh | unit | `python3 -m pytest tests/ansible/test_cp_rbac.py::test_token_refresh -x` |
| ARBAC-03 | Consumer group bindings (PREFIXED) | unit | `python3 -m pytest tests/ansible/test_cp_rbac.py::test_group_bindings -x` |
| ARBAC-04 | SR subject bindings | unit | `python3 -m pytest tests/ansible/test_cp_rbac.py::test_sr_bindings -x` |
| ARBAC-05 | Reconciliation (remove stale bindings) | unit | `python3 -m pytest tests/ansible/test_cp_rbac.py::test_reconciliation -x` |

## Sampling Rate
- **Per task commit:** `python3 -m pytest tests/ansible/ -x --tb=short`
- **Per wave merge:** `python3 -m pytest tests/ansible/ -v`
- **Phase gate:** Full suite green before `/gsd:verify-work`

## Wave 0 Gaps
- [ ] `tests/ansible/test_cp_topic.py` -- unit tests for cp_topic role logic
- [ ] `tests/ansible/test_cp_schema.py` -- unit tests for cp_schema role logic
- [ ] `tests/ansible/test_cp_rbac.py` -- unit tests for cp_rbac role logic
- [ ] `tests/ansible/fixtures/mock_responses/` -- mock CP API response JSON files
- [ ] `tests/ansible/fixtures/cptopic_samples/` -- sample CPTopic YAML for testing
- [ ] molecule installation: `pip install molecule` (for running molecule test scenarios)
