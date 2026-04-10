"""
Unit tests for the cp_dr_mm2 Ansible role.

Tests cover role structure, default variables, meta information, task files
for failover (6-step sequence), failback, check mode (GET-only audit output),
state validation with SLA-tier mirror lag thresholds, Consul KV flip,
connector pause/resume with polling, molecule scenario, FQCN enforcement,
task name casing, playbook entry point, and mock fixture integrity.
"""
import json
import os
import re

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROLE_DIR = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cp_dr_mm2')
TASKS_DIR = os.path.join(ROLE_DIR, 'tasks')
MOLECULE_DIR = os.path.join(ROLE_DIR, 'molecule', 'default')
FIXTURES_DIR = os.path.join(
    REPO_ROOT, 'tests', 'ansible', 'fixtures', 'mock_responses', 'connect'
)
CONSUL_FIXTURES_DIR = os.path.join(
    REPO_ROOT, 'tests', 'ansible', 'fixtures', 'mock_responses', 'consul'
)
PLAYBOOKS_DIR = os.path.join(REPO_ROOT, 'ansible', 'playbooks')
VARS_DIR = os.path.join(REPO_ROOT, 'ansible', 'vars')


def _load_yaml(path):
    """Load and parse a YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def _read_text(path):
    """Read file as raw text."""
    with open(path) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestRoleStructure -- cp_dr_mm2 role files and default variables
# ---------------------------------------------------------------------------
class TestRoleStructure:
    """Verify cp_dr_mm2 role directory structure and defaults."""

    def test_defaults_exist(self):
        path = os.path.join(ROLE_DIR, 'defaults', 'main.yml')
        assert os.path.isfile(path), "defaults/main.yml must exist"
        data = _load_yaml(path)
        assert data is not None

    def test_meta_exist(self):
        path = os.path.join(ROLE_DIR, 'meta', 'main.yml')
        assert os.path.isfile(path), "meta/main.yml must exist"

    def test_meta_role_name(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['galaxy_info']['role_name'] == 'cp_dr_mm2'

    def test_meta_author(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['galaxy_info']['author'] == 'fsi-c4e'

    def test_meta_no_dependencies(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['dependencies'] == [], (
            "cp_dr_mm2 must have no role dependencies"
        )

    def test_task_files_exist(self):
        expected = [
            'main.yml', 'check.yml', 'failover.yml', 'failback.yml',
            'validate_state.yml',
            'consul_flip.yml', 'connector_pause.yml', 'connector_resume.yml'
        ]
        for fname in expected:
            path = os.path.join(TASKS_DIR, fname)
            assert os.path.isfile(path), f"Missing task file: {fname}"

    def test_defaults_cp_dr_mm2_operation(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_operation' in data
        assert data['cp_dr_mm2_operation'] == 'failover'

    def test_defaults_cp_dr_mm2_connect_url(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_connect_url' in data
        assert data['cp_dr_mm2_connect_url'] == 'http://localhost:8083'

    def test_defaults_cp_dr_mm2_consul_url(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_consul_url' in data
        assert data['cp_dr_mm2_consul_url'] == 'http://localhost:8500'

    def test_defaults_cp_dr_mm2_consul_kv_key(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_consul_kv_key' in data
        assert data['cp_dr_mm2_consul_kv_key'] == 'fsi/kafka/active-region'

    def test_defaults_cp_dr_mm2_source_connector(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_source_connector' in data
        assert data['cp_dr_mm2_source_connector'] == 'mm2-source-east-west'

    def test_defaults_cp_dr_mm2_checkpoint_connector(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_checkpoint_connector' in data
        assert data['cp_dr_mm2_checkpoint_connector'] == 'mm2-checkpoint-east-west'

    def test_defaults_cp_dr_mm2_heartbeat_connector(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_heartbeat_connector' in data
        assert data['cp_dr_mm2_heartbeat_connector'] == 'mm2-heartbeat-east-west'

    def test_defaults_cp_dr_mm2_results(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_results' in data
        results = data['cp_dr_mm2_results']
        assert 'operation' in results
        assert 'connectors_paused' in results
        assert 'connectors_resumed' in results
        assert 'consul_flipped' in results
        assert 'validation_passed' in results
        assert 'audit_log' in results

    def test_defaults_pause_retries(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_pause_retries' in data
        assert data['cp_dr_mm2_pause_retries'] == 15

    def test_defaults_pause_delay(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_pause_delay' in data
        assert data['cp_dr_mm2_pause_delay'] == 2

    def test_defaults_resume_retries(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_resume_retries' in data
        assert data['cp_dr_mm2_resume_retries'] == 15

    def test_defaults_resume_delay(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_resume_delay' in data
        assert data['cp_dr_mm2_resume_delay'] == 2

    def test_defaults_validate_health(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_validate_health' in data
        assert data['cp_dr_mm2_validate_health'] is True

    def test_defaults_validate_writability(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_validate_writability' in data
        assert data['cp_dr_mm2_validate_writability'] is True

    def test_defaults_app_connect_url(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_app_connect_url' in data

    def test_defaults_target_region(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cp_dr_mm2_target_region' in data

    def test_molecule_yml_exists(self):
        path = os.path.join(MOLECULE_DIR, 'molecule.yml')
        assert os.path.isfile(path), "molecule/default/molecule.yml must exist"

    def test_molecule_uses_delegated_driver(self):
        data = _load_yaml(os.path.join(MOLECULE_DIR, 'molecule.yml'))
        assert data['driver']['name'] == 'delegated'


# ---------------------------------------------------------------------------
# TestFQCNCompliance -- FQCN enforcement across all task files
# ---------------------------------------------------------------------------
class TestFQCNCompliance:
    """Verify all task files use FQCN for every module reference."""

    BARE_MODULES = [
        'uri:', 'set_fact:', 'debug:', 'assert:', 'fail:',
        'include_tasks:', 'include_role:', 'shell:', 'wait_for:',
        'include_vars:'
    ]

    def test_all_tasks_use_fqcn(self):
        task_files = [
            'main.yml', 'check.yml', 'failover.yml', 'failback.yml',
            'validate_state.yml',
            'consul_flip.yml', 'connector_pause.yml', 'connector_resume.yml'
        ]
        for fname in task_files:
            path = os.path.join(TASKS_DIR, fname)
            if not os.path.isfile(path):
                continue
            text = _read_text(path)
            for bare in self.BARE_MODULES:
                lines = text.split('\n')
                for i, line in enumerate(lines):
                    stripped = line.lstrip()
                    if stripped.startswith('#') or not stripped:
                        continue
                    if stripped.startswith('- name:') or stripped.startswith('name:'):
                        continue
                    if stripped.startswith(bare):
                        assert False, (
                            f"Bare module '{bare}' found in {fname} "
                            f"line {i + 1}: '{stripped}'. "
                            f"Use ansible.builtin.{bare[:-1]} instead."
                        )


# ---------------------------------------------------------------------------
# TestTaskNameCasing -- task name casing
# ---------------------------------------------------------------------------
class TestTaskNameCasing:
    """Verify all task names start with uppercase per ansible-lint."""

    def test_all_task_names_uppercase(self):
        task_files = [
            'main.yml', 'check.yml', 'failover.yml', 'failback.yml',
            'validate_state.yml',
            'consul_flip.yml', 'connector_pause.yml', 'connector_resume.yml'
        ]
        for fname in task_files:
            path = os.path.join(TASKS_DIR, fname)
            if not os.path.isfile(path):
                continue
            data = _load_yaml(path)
            if not data:
                continue
            for task in data:
                if isinstance(task, dict) and 'name' in task:
                    name = task['name']
                    # Skip Jinja-only names
                    if name.startswith('{{'):
                        continue
                    assert name[0].isupper(), (
                        f"Task name in {fname} must start with uppercase: "
                        f"'{name}'"
                    )

    def test_no_jinja_before_final_position(self):
        """Task names must not have Jinja templates before the end."""
        task_files = [
            'main.yml', 'check.yml', 'failover.yml', 'failback.yml',
            'validate_state.yml',
            'consul_flip.yml', 'connector_pause.yml', 'connector_resume.yml'
        ]
        for fname in task_files:
            path = os.path.join(TASKS_DIR, fname)
            if not os.path.isfile(path):
                continue
            data = _load_yaml(path)
            if not data:
                continue
            for task in data:
                if isinstance(task, dict) and 'name' in task:
                    name = task['name']
                    # Find all Jinja expressions
                    jinja_positions = [
                        m.start() for m in re.finditer(r'\{\{', name)
                    ]
                    if len(jinja_positions) <= 1:
                        continue
                    # Multiple Jinja blocks: each must be at the end
                    # (this is a simplified check -- just verify first
                    # char is not Jinja)
                    assert not name.startswith('{{'), (
                        f"Task name in {fname} starts with Jinja: '{name}'"
                    )


# ---------------------------------------------------------------------------
# TestCheckMode -- check.yml GET-only without mutations
# ---------------------------------------------------------------------------
class TestCheckMode:
    """Verify check.yml uses GET-only operations (no PUT/POST/DELETE)."""

    CHECK_PATH = os.path.join(TASKS_DIR, 'check.yml')

    def test_check_no_put(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: PUT' not in text, (
            "check.yml must NOT use PUT (read-only check mode)"
        )

    def test_check_no_post(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: POST' not in text, (
            "check.yml must NOT use POST (read-only check mode)"
        )

    def test_check_no_delete(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: DELETE' not in text, (
            "check.yml must NOT use DELETE (read-only check mode)"
        )

    def test_check_uses_check_mode_false(self):
        text = _read_text(self.CHECK_PATH)
        assert 'check_mode: false' in text, (
            "check.yml must use check_mode: false on uri tasks"
        )

    def test_check_uses_changed_when_false(self):
        text = _read_text(self.CHECK_PATH)
        assert 'changed_when: false' in text, (
            "check.yml must use changed_when: false on all tasks"
        )

    def test_check_initializes_audit_log(self):
        text = _read_text(self.CHECK_PATH)
        assert '_dr_audit_log' in text, (
            "check.yml must initialize _dr_audit_log list"
        )

    def test_check_appends_audit_steps(self):
        text = _read_text(self.CHECK_PATH)
        assert 'step' in text, "check.yml must record step numbers"
        assert 'action' in text, "check.yml must record action descriptions"
        assert 'current_state' in text, "check.yml must record current_state"
        assert 'expected_result' in text, "check.yml must record expected_result"

    def test_check_uses_get_method(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: GET' in text, "check.yml must use GET method"


# ---------------------------------------------------------------------------
# TestFailoverTasks -- failover.yml 6-step sequence
# ---------------------------------------------------------------------------
class TestFailoverTasks:
    """Verify failover.yml implements the 6-step failover sequence."""

    FAILOVER_PATH = os.path.join(TASKS_DIR, 'failover.yml')
    MAIN_PATH = os.path.join(TASKS_DIR, 'main.yml')

    def test_failover_includes_connector_pause(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'connector_pause' in text, (
            "failover.yml must include connector_pause.yml"
        )

    def test_failover_pauses_app_connectors(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'cp_dr_mm2_app_connect_url' in text or 'app_connect' in text, (
            "failover.yml must pause application connectors"
        )

    def test_failover_pauses_mm2_connectors(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'cp_dr_mm2_source_connector' in text, (
            "failover.yml must pause MM2 source connector"
        )

    def test_failover_includes_consul_flip(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'consul_flip' in text, (
            "failover.yml must include consul_flip.yml"
        )

    def test_failover_includes_connector_resume(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'connector_resume' in text, (
            "failover.yml must include connector_resume.yml"
        )

    def test_main_routes_to_check_mode(self):
        text = _read_text(self.MAIN_PATH)
        assert 'ansible_check_mode' in text, (
            "main.yml must route to check.yml when ansible_check_mode"
        )
        assert 'check.yml' in text, (
            "main.yml must include check.yml"
        )

    def test_main_routes_to_failover(self):
        text = _read_text(self.MAIN_PATH)
        assert 'failover.yml' in text, (
            "main.yml must include failover.yml"
        )
        assert "cp_dr_mm2_operation" in text, (
            "main.yml must check cp_dr_mm2_operation"
        )

    def test_main_includes_pre_validation(self):
        text = _read_text(self.MAIN_PATH)
        assert 'validate_state.yml' in text, (
            "main.yml must include validate_state.yml"
        )

    def test_main_includes_post_validation(self):
        text = _read_text(self.MAIN_PATH)
        # Must have two include_tasks for validate_state.yml (pre + post)
        count = text.count('validate_state.yml')
        assert count >= 2, (
            f"main.yml must include validate_state.yml at least twice "
            f"(pre and post), found {count}"
        )

    def test_main_sets_results(self):
        text = _read_text(self.MAIN_PATH)
        assert 'cp_dr_mm2_results' in text, (
            "main.yml must set cp_dr_mm2_results output variable"
        )

    def test_main_loads_sla_tiers(self):
        text = _read_text(self.MAIN_PATH)
        assert 'sla_tiers.yml' in text, (
            "main.yml must load sla_tiers.yml via include_vars"
        )


# ---------------------------------------------------------------------------
# TestConnectorPause -- connector_pause.yml polling with retries
# ---------------------------------------------------------------------------
class TestConnectorPause:
    """Verify connector_pause.yml uses PUT with polling loop."""

    PAUSE_PATH = os.path.join(TASKS_DIR, 'connector_pause.yml')

    def test_pause_uses_put(self):
        text = _read_text(self.PAUSE_PATH)
        assert 'method: PUT' in text, (
            "connector_pause.yml must use PUT method"
        )

    def test_pause_accepts_200_202(self):
        text = _read_text(self.PAUSE_PATH)
        assert '200' in text, "connector_pause.yml must accept 200"
        assert '202' in text, "connector_pause.yml must accept 202"

    def test_pause_has_retries(self):
        text = _read_text(self.PAUSE_PATH)
        assert 'retries:' in text, (
            "connector_pause.yml must have retries for polling"
        )

    def test_pause_has_delay(self):
        text = _read_text(self.PAUSE_PATH)
        assert 'delay:' in text, (
            "connector_pause.yml must have delay between retries"
        )

    def test_pause_has_until(self):
        text = _read_text(self.PAUSE_PATH)
        assert 'until:' in text, (
            "connector_pause.yml must have until condition"
        )

    def test_pause_checks_paused_state(self):
        text = _read_text(self.PAUSE_PATH)
        assert 'PAUSED' in text, (
            "connector_pause.yml must check for PAUSED state"
        )

    def test_pause_uses_failed_when_false(self):
        text = _read_text(self.PAUSE_PATH)
        assert 'failed_when: false' in text, (
            "connector_pause.yml must use failed_when: false"
        )


# ---------------------------------------------------------------------------
# TestConnectorResume -- connector_resume.yml polling with retries
# ---------------------------------------------------------------------------
class TestConnectorResume:
    """Verify connector_resume.yml uses PUT with polling loop."""

    RESUME_PATH = os.path.join(TASKS_DIR, 'connector_resume.yml')

    def test_resume_uses_put(self):
        text = _read_text(self.RESUME_PATH)
        assert 'method: PUT' in text, (
            "connector_resume.yml must use PUT method"
        )

    def test_resume_accepts_200_202(self):
        text = _read_text(self.RESUME_PATH)
        assert '200' in text, "connector_resume.yml must accept 200"
        assert '202' in text, "connector_resume.yml must accept 202"

    def test_resume_has_retries(self):
        text = _read_text(self.RESUME_PATH)
        assert 'retries:' in text, (
            "connector_resume.yml must have retries for polling"
        )

    def test_resume_has_delay(self):
        text = _read_text(self.RESUME_PATH)
        assert 'delay:' in text, (
            "connector_resume.yml must have delay between retries"
        )

    def test_resume_has_until(self):
        text = _read_text(self.RESUME_PATH)
        assert 'until:' in text, (
            "connector_resume.yml must have until condition"
        )

    def test_resume_checks_running_state(self):
        text = _read_text(self.RESUME_PATH)
        assert 'RUNNING' in text, (
            "connector_resume.yml must check for RUNNING state"
        )


# ---------------------------------------------------------------------------
# TestConsulFlip -- consul_flip.yml Consul KV operations
# ---------------------------------------------------------------------------
class TestConsulFlip:
    """Verify consul_flip.yml reads, updates, and verifies Consul KV."""

    CONSUL_PATH = os.path.join(TASKS_DIR, 'consul_flip.yml')

    def test_consul_reads_current_region(self):
        text = _read_text(self.CONSUL_PATH)
        assert 'method: GET' in text, (
            "consul_flip.yml must GET current region"
        )
        assert '?raw' in text or 'raw' in text, (
            "consul_flip.yml must use ?raw query for plain text response"
        )

    def test_consul_uses_kv_endpoint(self):
        text = _read_text(self.CONSUL_PATH)
        assert 'v1/kv' in text, (
            "consul_flip.yml must use /v1/kv/ endpoint"
        )

    def test_consul_updates_region_with_put(self):
        text = _read_text(self.CONSUL_PATH)
        assert 'method: PUT' in text, (
            "consul_flip.yml must use PUT to update region"
        )

    def test_consul_verifies_after_flip(self):
        text = _read_text(self.CONSUL_PATH)
        # Must have at least 2 GET calls (read + verify)
        get_count = text.count('method: GET')
        assert get_count >= 2, (
            f"consul_flip.yml must verify with GET after PUT, "
            f"found {get_count} GETs"
        )

    def test_consul_guards_mutations(self):
        text = _read_text(self.CONSUL_PATH)
        assert 'ansible_check_mode' in text, (
            "consul_flip.yml must guard mutations with check_mode condition"
        )


# ---------------------------------------------------------------------------
# TestValidation -- validate_state.yml connector health + writability
# ---------------------------------------------------------------------------
class TestValidation:
    """Verify validate_state.yml checks connector health and writability."""

    VALIDATE_PATH = os.path.join(TASKS_DIR, 'validate_state.yml')

    def test_validation_checks_connector_health(self):
        text = _read_text(self.VALIDATE_PATH)
        assert '/status' in text or 'status' in text, (
            "validate_state.yml must check connector status"
        )

    def test_validation_has_phase_variable(self):
        text = _read_text(self.VALIDATE_PATH)
        assert '_validation_phase' in text, (
            "validate_state.yml must have _validation_phase variable"
        )

    def test_validation_references_sla_tier_mirror_lag(self):
        text = _read_text(self.VALIDATE_PATH)
        assert 'sla_tier_mirror_lag' in text, (
            "validate_state.yml must reference sla_tier_mirror_lag thresholds"
        )

    def test_validation_uses_get_for_health(self):
        text = _read_text(self.VALIDATE_PATH)
        assert 'method: GET' in text, (
            "validate_state.yml must use GET for health checks"
        )


# ---------------------------------------------------------------------------
# TestSLATierMirrorLag -- sla_tiers.yml mirror lag thresholds
# ---------------------------------------------------------------------------
class TestSLATierMirrorLag:
    """Verify sla_tiers.yml contains mirror lag thresholds."""

    SLA_PATH = os.path.join(VARS_DIR, 'sla_tiers.yml')

    def test_sla_tier_mirror_lag_exists(self):
        data = _load_yaml(self.SLA_PATH)
        assert 'sla_tier_mirror_lag' in data, (
            "sla_tiers.yml must contain sla_tier_mirror_lag top-level key"
        )

    def test_sla_tier_mirror_lag_has_critical(self):
        data = _load_yaml(self.SLA_PATH)
        lag = data['sla_tier_mirror_lag']
        assert 'critical' in lag

    def test_sla_tier_mirror_lag_has_standard(self):
        data = _load_yaml(self.SLA_PATH)
        lag = data['sla_tier_mirror_lag']
        assert 'standard' in lag

    def test_sla_tier_mirror_lag_has_best_effort(self):
        data = _load_yaml(self.SLA_PATH)
        lag = data['sla_tier_mirror_lag']
        assert 'best-effort' in lag

    def test_sla_tier_mirror_lag_has_compliance(self):
        data = _load_yaml(self.SLA_PATH)
        lag = data['sla_tier_mirror_lag']
        assert 'compliance' in lag

    def test_critical_warn_seconds(self):
        data = _load_yaml(self.SLA_PATH)
        assert data['sla_tier_mirror_lag']['critical']['warn_seconds'] == 30

    def test_critical_alert_seconds(self):
        data = _load_yaml(self.SLA_PATH)
        assert data['sla_tier_mirror_lag']['critical']['alert_seconds'] == 60

    def test_compliance_warn_seconds(self):
        data = _load_yaml(self.SLA_PATH)
        assert data['sla_tier_mirror_lag']['compliance']['warn_seconds'] == 10

    def test_compliance_alert_seconds(self):
        data = _load_yaml(self.SLA_PATH)
        assert data['sla_tier_mirror_lag']['compliance']['alert_seconds'] == 30

    def test_each_tier_has_warn_and_alert(self):
        data = _load_yaml(self.SLA_PATH)
        lag = data['sla_tier_mirror_lag']
        for tier_name in ['critical', 'standard', 'best-effort', 'compliance']:
            tier = lag[tier_name]
            assert 'warn_seconds' in tier, (
                f"{tier_name} must have warn_seconds"
            )
            assert 'alert_seconds' in tier, (
                f"{tier_name} must have alert_seconds"
            )
            assert isinstance(tier['warn_seconds'], int), (
                f"{tier_name}.warn_seconds must be int"
            )
            assert isinstance(tier['alert_seconds'], int), (
                f"{tier_name}.alert_seconds must be int"
            )

    def test_original_sla_tiers_intact(self):
        """The original sla_tiers key must not be modified."""
        data = _load_yaml(self.SLA_PATH)
        assert 'sla_tiers' in data, (
            "sla_tiers.yml must still contain original sla_tiers key"
        )
        assert 'critical' in data['sla_tiers']
        assert 'standard' in data['sla_tiers']
        assert data['sla_tiers']['critical']['compatibility'] == 'FULL_TRANSITIVE'


# ---------------------------------------------------------------------------
# TestMockFixtures -- mock fixture integrity
# ---------------------------------------------------------------------------
class TestMockFixtures:
    """Verify MM2 and Consul mock fixtures are valid."""

    def test_mm2_status_running_valid(self):
        path = os.path.join(FIXTURES_DIR, 'mm2_connector_status_running.json')
        assert os.path.isfile(path), "mm2_connector_status_running.json must exist"
        with open(path) as f:
            data = json.load(f)
        assert 'name' in data
        assert data['connector']['state'] == 'RUNNING'
        assert len(data['tasks']) > 0
        assert data['type'] == 'source'

    def test_mm2_status_paused_valid(self):
        path = os.path.join(FIXTURES_DIR, 'mm2_connector_status_paused.json')
        assert os.path.isfile(path), "mm2_connector_status_paused.json must exist"
        with open(path) as f:
            data = json.load(f)
        assert data['connector']['state'] == 'PAUSED'

    def test_mm2_config_valid(self):
        path = os.path.join(FIXTURES_DIR, 'mm2_connector_config.json')
        assert os.path.isfile(path), "mm2_connector_config.json must exist"
        with open(path) as f:
            data = json.load(f)
        assert 'MirrorSourceConnector' in data['connector.class']

    def test_consul_kv_active_region(self):
        path = os.path.join(CONSUL_FIXTURES_DIR, 'kv_active_region.txt')
        assert os.path.isfile(path), "consul/kv_active_region.txt must exist"
        with open(path) as f:
            content = f.read().strip()
        assert content == 'east'


# ---------------------------------------------------------------------------
# TestPlaybook -- dr-failover-mm2.yml top-level playbook
# ---------------------------------------------------------------------------
class TestPlaybook:
    """Verify the operator-facing failover playbook."""

    PLAYBOOK_PATH = os.path.join(PLAYBOOKS_DIR, 'dr-failover-mm2.yml')

    def test_playbook_exists(self):
        assert os.path.isfile(self.PLAYBOOK_PATH), (
            "dr-failover-mm2.yml must exist"
        )

    def test_playbook_targets_kafka_connect(self):
        text = _read_text(self.PLAYBOOK_PATH)
        assert 'kafka_connect' in text, (
            "dr-failover-mm2.yml must target kafka_connect hosts"
        )

    def test_playbook_sets_failover_operation(self):
        text = _read_text(self.PLAYBOOK_PATH)
        assert 'cp_dr_mm2_operation: failover' in text, (
            "dr-failover-mm2.yml must set cp_dr_mm2_operation: failover"
        )

    def test_playbook_includes_cp_dr_mm2_role(self):
        text = _read_text(self.PLAYBOOK_PATH)
        assert 'cp_dr_mm2' in text, (
            "dr-failover-mm2.yml must include cp_dr_mm2 role"
        )
        assert 'include_role' in text, (
            "dr-failover-mm2.yml must use include_role"
        )


# ---------------------------------------------------------------------------
# TestMolecule -- molecule scenario for cp_dr_mm2
# ---------------------------------------------------------------------------
class TestMolecule:
    """Verify molecule scenario for cp_dr_mm2 role."""

    def test_molecule_yml_exists(self):
        path = os.path.join(MOLECULE_DIR, 'molecule.yml')
        assert os.path.isfile(path), "molecule/default/molecule.yml must exist"

    def test_converge_yml_exists(self):
        path = os.path.join(MOLECULE_DIR, 'converge.yml')
        assert os.path.isfile(path), "molecule/default/converge.yml must exist"

    def test_verify_yml_exists(self):
        path = os.path.join(MOLECULE_DIR, 'verify.yml')
        assert os.path.isfile(path), "molecule/default/verify.yml must exist"

    def test_molecule_uses_delegated_driver(self):
        data = _load_yaml(os.path.join(MOLECULE_DIR, 'molecule.yml'))
        assert data['driver']['name'] == 'delegated'

    def test_converge_includes_cp_dr_mm2(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'converge.yml'))
        assert 'cp_dr_mm2' in text, (
            "converge.yml must include cp_dr_mm2 role"
        )

    def test_verify_checks_results(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'verify.yml'))
        assert 'cp_dr_mm2_results' in text, (
            "verify.yml must check cp_dr_mm2_results"
        )


# ---------------------------------------------------------------------------
# TestFailbackTasks -- failback.yml 7-step sequence
# ---------------------------------------------------------------------------
class TestFailbackTasks:
    """Verify failback.yml implements the 7-step failback sequence."""

    FAILBACK_PATH = os.path.join(TASKS_DIR, 'failback.yml')

    def test_failback_file_exists(self):
        assert os.path.isfile(self.FAILBACK_PATH), (
            "failback.yml must exist"
        )

    def test_failback_fetches_config_with_get(self):
        """Pitfall 4: GET config BEFORE deleting connectors."""
        text = _read_text(self.FAILBACK_PATH)
        assert 'method: GET' in text, (
            "failback.yml must fetch original connector config via GET"
        )
        # GET must appear before DELETE
        get_pos = text.index('method: GET')
        delete_pos = text.index('method: DELETE')
        assert get_pos < delete_pos, (
            "failback.yml must GET config BEFORE DELETE (pitfall 4)"
        )

    def test_failback_deletes_connectors(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'method: DELETE' in text, (
            "failback.yml must DELETE existing MM2 connectors"
        )

    def test_failback_creates_reversed_connectors(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'method: POST' in text, (
            "failback.yml must POST reversed MM2 connectors"
        )

    def test_failback_has_retries_for_running(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'retries' in text, (
            "failback.yml must have retries for polling reversed connectors"
        )

    def test_failback_has_delay_for_polling(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'delay' in text, (
            "failback.yml must have delay for polling loop"
        )

    def test_failback_has_until_for_polling(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'until' in text, (
            "failback.yml must have until condition for RUNNING poll"
        )

    def test_failback_includes_consul_flip(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'consul_flip' in text, (
            "failback.yml must include consul_flip.yml for region cutback"
        )

    def test_failback_includes_connector_resume(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'connector_resume' in text, (
            "failback.yml must include connector_resume.yml for app connectors"
        )

    def test_failback_increments_connectors_deleted(self):
        text = _read_text(self.FAILBACK_PATH)
        assert '_dr_connectors_deleted' in text, (
            "failback.yml must increment _dr_connectors_deleted counter"
        )

    def test_failback_increments_connectors_created(self):
        text = _read_text(self.FAILBACK_PATH)
        assert '_dr_connectors_created' in text, (
            "failback.yml must increment _dr_connectors_created counter"
        )


# ---------------------------------------------------------------------------
# TestFailbackCheckMode -- failback audit steps in check.yml
# ---------------------------------------------------------------------------
class TestFailbackCheckMode:
    """Verify check.yml has failback-specific audit steps."""

    CHECK_PATH = os.path.join(TASKS_DIR, 'check.yml')

    def test_check_has_failback_condition(self):
        text = _read_text(self.CHECK_PATH)
        assert 'failback' in text, (
            "check.yml must contain failback audit steps"
        )

    def test_check_failback_has_7_steps(self):
        """Failback audit must have 7 planned steps."""
        data = _load_yaml(self.CHECK_PATH)
        failback_steps = [
            task for task in data
            if isinstance(task, dict) and 'name' in task
            and 'failback' in task['name'].lower()
            and 'step' in task['name'].lower()
        ]
        assert len(failback_steps) == 7, (
            f"check.yml must have 7 failback audit steps, found "
            f"{len(failback_steps)}: {[s['name'] for s in failback_steps]}"
        )

    def test_check_failback_steps_have_operation_guard(self):
        """Each failback audit step must be guarded by operation == failback."""
        data = _load_yaml(self.CHECK_PATH)
        for task in data:
            if not isinstance(task, dict) or 'name' not in task:
                continue
            name = task['name']
            if 'failback' in name.lower() and 'step' in name.lower():
                when = task.get('when', '')
                when_str = str(when) if not isinstance(when, list) else ' '.join(str(w) for w in when)
                assert 'failback' in when_str, (
                    f"Failback audit step '{name}' must be guarded by "
                    f"cp_dr_mm2_operation == 'failback'"
                )

    def test_check_still_no_put(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: PUT' not in text, (
            "check.yml must NOT use PUT even after failback extension"
        )

    def test_check_still_no_post(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: POST' not in text, (
            "check.yml must NOT use POST even after failback extension"
        )

    def test_check_still_no_delete(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: DELETE' not in text, (
            "check.yml must NOT use DELETE even after failback extension"
        )


# ---------------------------------------------------------------------------
# TestFailbackPlaybook -- dr-failback-mm2.yml top-level playbook
# ---------------------------------------------------------------------------
class TestFailbackPlaybook:
    """Verify the operator-facing failback playbook."""

    PLAYBOOK_PATH = os.path.join(PLAYBOOKS_DIR, 'dr-failback-mm2.yml')

    def test_failback_playbook_exists(self):
        assert os.path.isfile(self.PLAYBOOK_PATH), (
            "dr-failback-mm2.yml must exist"
        )

    def test_failback_playbook_targets_kafka_connect(self):
        text = _read_text(self.PLAYBOOK_PATH)
        assert 'kafka_connect[0]' in text, (
            "dr-failback-mm2.yml must target kafka_connect[0] hosts"
        )

    def test_failback_playbook_sets_failback_operation(self):
        text = _read_text(self.PLAYBOOK_PATH)
        assert 'cp_dr_mm2_operation: failback' in text, (
            "dr-failback-mm2.yml must set cp_dr_mm2_operation: failback"
        )

    def test_failback_playbook_includes_cp_dr_mm2_role(self):
        text = _read_text(self.PLAYBOOK_PATH)
        assert 'cp_dr_mm2' in text, (
            "dr-failback-mm2.yml must include cp_dr_mm2 role"
        )
        assert 'include_role' in text, (
            "dr-failback-mm2.yml must use include_role"
        )

    def test_failback_playbook_no_gather_facts(self):
        data = _load_yaml(self.PLAYBOOK_PATH)
        play = data[0]
        assert play.get('gather_facts') is False, (
            "dr-failback-mm2.yml must set gather_facts: false"
        )


# ---------------------------------------------------------------------------
# TestMainRoutingFailback -- main.yml routes to failback.yml
# ---------------------------------------------------------------------------
class TestMainRoutingFailback:
    """Verify main.yml includes failback.yml with correct condition."""

    MAIN_PATH = os.path.join(TASKS_DIR, 'main.yml')

    def test_main_routes_to_failback(self):
        text = _read_text(self.MAIN_PATH)
        assert 'failback.yml' in text, (
            "main.yml must include failback.yml"
        )

    def test_main_failback_has_operation_condition(self):
        data = _load_yaml(self.MAIN_PATH)
        failback_task = None
        for task in data:
            if isinstance(task, dict) and 'name' in task:
                if 'failback' in task['name'].lower():
                    include = task.get('ansible.builtin.include_tasks', {})
                    if isinstance(include, dict):
                        if include.get('file', '') == 'failback.yml':
                            failback_task = task
                            break
                    elif isinstance(include, str) and include == 'failback.yml':
                        failback_task = task
                        break
        assert failback_task is not None, (
            "main.yml must have a task that includes failback.yml"
        )
        when = failback_task.get('when', [])
        when_str = str(when) if not isinstance(when, list) else ' '.join(str(w) for w in when)
        assert 'failback' in when_str, (
            "main.yml failback routing must check cp_dr_mm2_operation == 'failback'"
        )


# ---------------------------------------------------------------------------
# TestReversedConnectorConfig -- failback.yml reversed alias swap
# ---------------------------------------------------------------------------
class TestReversedConnectorConfig:
    """Verify failback.yml constructs reversed connectors with swapped aliases."""

    FAILBACK_PATH = os.path.join(TASKS_DIR, 'failback.yml')

    def test_failback_references_source_alias(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'cp_dr_mm2_source_alias' in text, (
            "failback.yml must reference cp_dr_mm2_source_alias for swap"
        )

    def test_failback_references_target_alias(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'cp_dr_mm2_target_alias' in text, (
            "failback.yml must reference cp_dr_mm2_target_alias for swap"
        )

    def test_failback_swaps_aliases(self):
        """The failback must swap source/target aliases in connector config."""
        text = _read_text(self.FAILBACK_PATH)
        # Must reference both source and target bootstrap servers for swapping
        assert 'source.cluster.bootstrap.servers' in text or 'bootstrap.servers' in text, (
            "failback.yml must reference bootstrap.servers for the swap"
        )

    def test_failback_constructs_reversed_names(self):
        """Connector names must be reversed (east-west -> west-east)."""
        text = _read_text(self.FAILBACK_PATH)
        # The replace pattern for reversing connector direction
        assert 'replace' in text or 'reversed' in text.lower(), (
            "failback.yml must construct reversed connector names "
            "(e.g., mm2-source-west-east from mm2-source-east-west)"
        )

    def test_failback_references_mm2_connector_config_fields(self):
        """Must reference original config fields for reversal."""
        text = _read_text(self.FAILBACK_PATH)
        assert 'source.cluster.alias' in text, (
            "failback.yml must reference source.cluster.alias config field"
        )
        assert 'target.cluster.alias' in text, (
            "failback.yml must reference target.cluster.alias config field"
        )


# ---------------------------------------------------------------------------
# TestFailbackFQCNCompliance -- FQCN enforcement on failback.yml
# ---------------------------------------------------------------------------
class TestFailbackFQCNCompliance:
    """Verify failback.yml uses FQCN for every module reference."""

    FAILBACK_PATH = os.path.join(TASKS_DIR, 'failback.yml')

    BARE_MODULES = [
        'uri:', 'set_fact:', 'debug:', 'assert:', 'fail:',
        'include_tasks:', 'include_role:', 'shell:', 'wait_for:',
        'include_vars:'
    ]

    def test_failback_uses_fqcn(self):
        if not os.path.isfile(self.FAILBACK_PATH):
            assert False, "failback.yml must exist"
        text = _read_text(self.FAILBACK_PATH)
        for bare in self.BARE_MODULES:
            lines = text.split('\n')
            for i, line in enumerate(lines):
                stripped = line.lstrip()
                if stripped.startswith('#') or not stripped:
                    continue
                if stripped.startswith('- name:') or stripped.startswith('name:'):
                    continue
                if stripped.startswith(bare):
                    assert False, (
                        f"Bare module '{bare}' found in failback.yml "
                        f"line {i + 1}: '{stripped}'. "
                        f"Use ansible.builtin.{bare[:-1]} instead."
                    )


# ---------------------------------------------------------------------------
# TestFailbackTaskNameCasing -- task name casing for failback.yml
# ---------------------------------------------------------------------------
class TestFailbackTaskNameCasing:
    """Verify failback.yml task names follow ansible-lint conventions."""

    FAILBACK_PATH = os.path.join(TASKS_DIR, 'failback.yml')

    def test_failback_task_names_uppercase(self):
        if not os.path.isfile(self.FAILBACK_PATH):
            assert False, "failback.yml must exist"
        data = _load_yaml(self.FAILBACK_PATH)
        if not data:
            assert False, "failback.yml must contain tasks"
        for task in data:
            if isinstance(task, dict) and 'name' in task:
                name = task['name']
                if name.startswith('{{'):
                    continue
                assert name[0].isupper(), (
                    f"Task name in failback.yml must start with uppercase: "
                    f"'{name}'"
                )


# ---------------------------------------------------------------------------
# TestDefaultsCounters -- defaults include connector deleted/created counters
# ---------------------------------------------------------------------------
class TestDefaultsCounters:
    """Verify defaults/main.yml includes connectors_deleted and connectors_created in results."""

    def test_results_has_connectors_deleted(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        results = data.get('cp_dr_mm2_results', {})
        assert 'connectors_deleted' in results, (
            "cp_dr_mm2_results must include connectors_deleted key"
        )

    def test_results_has_connectors_created(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        results = data.get('cp_dr_mm2_results', {})
        assert 'connectors_created' in results, (
            "cp_dr_mm2_results must include connectors_created key"
        )
