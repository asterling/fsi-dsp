"""
Unit tests for the cp_dr_mrc Ansible role.

Tests cover role structure, default variables, meta information, task files
for MRC failover (UNCLEAN leader election), failback (PREFERRED leader election),
check mode (GET-only audit output), state validation with observer ISR checks,
Consul KV flip, election JSON template, molecule scenario, FQCN enforcement,
task name casing, playbook entry points, and CI matrix inclusion.
"""
import os
import re

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROLE_DIR = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cp_dr_mrc')
TASKS_DIR = os.path.join(ROLE_DIR, 'tasks')
MOLECULE_DIR = os.path.join(ROLE_DIR, 'molecule', 'default')
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
# TestRoleStructure -- cp_dr_mrc role files exist
# ---------------------------------------------------------------------------
class TestRoleStructure:
    """Verify cp_dr_mrc role directory structure and file existence."""

    def test_defaults_exist(self):
        path = os.path.join(ROLE_DIR, 'defaults', 'main.yml')
        assert os.path.isfile(path), "defaults/main.yml must exist"
        data = _load_yaml(path)
        assert data is not None

    def test_meta_exist(self):
        path = os.path.join(ROLE_DIR, 'meta', 'main.yml')
        assert os.path.isfile(path), "meta/main.yml must exist"

    def test_task_files_exist(self):
        expected = [
            'main.yml', 'check.yml', 'failover.yml', 'failback.yml',
            'validate_state.yml', 'consul_flip.yml'
        ]
        for fname in expected:
            path = os.path.join(TASKS_DIR, fname)
            assert os.path.isfile(path), f"Missing task file: {fname}"

    def test_template_exists(self):
        path = os.path.join(ROLE_DIR, 'templates', 'unclean_election.json.j2')
        assert os.path.isfile(path), "templates/unclean_election.json.j2 must exist"

    def test_molecule_files_exist(self):
        for fname in ['molecule.yml', 'converge.yml', 'verify.yml']:
            path = os.path.join(MOLECULE_DIR, fname)
            assert os.path.isfile(path), f"Missing molecule file: {fname}"


# ---------------------------------------------------------------------------
# TestDefaults -- cp_dr_mrc defaults/main.yml variable verification
# ---------------------------------------------------------------------------
class TestDefaults:
    """Verify cp_dr_mrc defaults contain all required variables."""

    def _defaults(self):
        return _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))

    def test_operation_default(self):
        data = self._defaults()
        assert data['cp_dr_mrc_operation'] == 'failover'

    def test_bootstrap_default(self):
        data = self._defaults()
        assert data['cp_dr_mrc_bootstrap'] == 'localhost:9092'

    def test_command_config_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_command_config' in data
        assert data['cp_dr_mrc_command_config'] == ''

    def test_east_rack_default(self):
        data = self._defaults()
        assert data['cp_dr_mrc_east_rack'] == 'us-east'

    def test_west_rack_default(self):
        data = self._defaults()
        assert data['cp_dr_mrc_west_rack'] == 'us-west'

    def test_observer_rack_default(self):
        data = self._defaults()
        assert data['cp_dr_mrc_observer_rack'] == 'us-central'

    def test_target_region_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_target_region' in data
        assert data['cp_dr_mrc_target_region'] == 'west'

    def test_consul_url_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_consul_url' in data

    def test_consul_kv_key_default(self):
        data = self._defaults()
        assert data['cp_dr_mrc_consul_kv_key'] == 'fsi/kafka/active-region'

    def test_admin_rest_url_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_admin_rest_url' in data

    def test_cluster_id_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_cluster_id' in data

    def test_admin_rest_token_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_admin_rest_token' in data

    def test_validate_observers_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_validate_observers' in data
        assert data['cp_dr_mrc_validate_observers'] is True

    def test_validate_writability_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_validate_writability' in data
        assert data['cp_dr_mrc_validate_writability'] is True

    def test_election_json_dir_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_election_json_dir' in data
        assert data['cp_dr_mrc_election_json_dir'] == '/tmp'

    def test_election_wait_seconds_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_election_wait_seconds' in data
        assert data['cp_dr_mrc_election_wait_seconds'] == 5

    def test_results_default(self):
        data = self._defaults()
        assert 'cp_dr_mrc_results' in data
        results = data['cp_dr_mrc_results']
        assert 'operation' in results
        assert 'election_type' in results
        assert 'election_triggered' in results
        assert 'consul_flipped' in results
        assert 'validation_passed' in results
        assert 'audit_log' in results

    def test_results_election_triggered_false(self):
        data = self._defaults()
        assert data['cp_dr_mrc_results']['election_triggered'] is False

    def test_results_consul_flipped_false(self):
        data = self._defaults()
        assert data['cp_dr_mrc_results']['consul_flipped'] is False

    def test_results_validation_passed_false(self):
        data = self._defaults()
        assert data['cp_dr_mrc_results']['validation_passed'] is False


# ---------------------------------------------------------------------------
# TestMetaInfo -- meta/main.yml galaxy info
# ---------------------------------------------------------------------------
class TestMetaInfo:
    """Verify cp_dr_mrc meta information."""

    def test_role_name(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['galaxy_info']['role_name'] == 'cp_dr_mrc'

    def test_author(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['galaxy_info']['author'] == 'fsi-c4e'

    def test_no_dependencies(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['dependencies'] == []


# ---------------------------------------------------------------------------
# TestMainEntry -- main.yml entry point routing
# ---------------------------------------------------------------------------
class TestMainEntry:
    """Verify main.yml routes to check/failover/failback with pre/post validation."""

    MAIN_PATH = os.path.join(TASKS_DIR, 'main.yml')

    def test_main_loads_sla_tiers(self):
        text = _read_text(self.MAIN_PATH)
        assert 'sla_tiers.yml' in text, (
            "main.yml must load sla_tiers.yml via include_vars"
        )

    def test_main_routes_to_check_mode(self):
        text = _read_text(self.MAIN_PATH)
        assert 'ansible_check_mode' in text, (
            "main.yml must route to check.yml when ansible_check_mode"
        )
        assert 'check.yml' in text

    def test_main_routes_to_failover(self):
        text = _read_text(self.MAIN_PATH)
        assert 'failover.yml' in text
        assert 'cp_dr_mrc_operation' in text

    def test_main_routes_to_failback(self):
        text = _read_text(self.MAIN_PATH)
        assert 'failback.yml' in text

    def test_main_runs_pre_post_validation(self):
        text = _read_text(self.MAIN_PATH)
        count = text.count('validate_state.yml')
        assert count >= 2, (
            f"main.yml must include validate_state.yml at least twice "
            f"(pre and post), found {count}"
        )

    def test_main_sets_results(self):
        text = _read_text(self.MAIN_PATH)
        assert 'cp_dr_mrc_results' in text

    def test_main_has_fail_guard(self):
        text = _read_text(self.MAIN_PATH)
        assert 'ansible.builtin.fail' in text, (
            "main.yml must have fail guard when validation_passed is false"
        )

    def test_main_initializes_counters(self):
        text = _read_text(self.MAIN_PATH)
        assert '_dr_election_triggered' in text
        assert '_dr_election_type' in text
        assert '_dr_consul_flipped' in text
        assert '_dr_validation_passed' in text
        assert '_dr_audit_log' in text


# ---------------------------------------------------------------------------
# TestFailover -- failover.yml UNCLEAN leader election sequence
# ---------------------------------------------------------------------------
class TestFailover:
    """Verify failover.yml implements UNCLEAN leader election."""

    FAILOVER_PATH = os.path.join(TASKS_DIR, 'failover.yml')

    def test_failover_has_at_least_4_tasks(self):
        data = _load_yaml(self.FAILOVER_PATH)
        assert len(data) >= 4, (
            f"failover.yml must have at least 4 tasks, found {len(data)}"
        )

    def test_failover_lists_topics(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'kafka-topics.sh' in text, (
            "failover.yml must list topics via kafka-topics.sh"
        )

    def test_failover_renders_election_template(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'unclean_election.json.j2' in text, (
            "failover.yml must render unclean_election.json.j2 template"
        )

    def test_failover_triggers_unclean_election(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'kafka-leader-election.sh' in text, (
            "failover.yml must trigger leader election via kafka-leader-election.sh"
        )
        assert 'UNCLEAN' in text, (
            "failover.yml must use UNCLEAN election type"
        )

    def test_failover_includes_consul_flip(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'consul_flip.yml' in text, (
            "failover.yml must include consul_flip.yml"
        )

    def test_failover_guards_cli_with_check_mode(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'not (ansible_check_mode' in text, (
            "failover.yml must guard CLI commands with check_mode condition"
        )

    def test_failover_has_changed_when(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'changed_when' in text, (
            "failover.yml must use changed_when on command tasks"
        )

    def test_failover_has_failed_when(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'failed_when' in text, (
            "failover.yml must use failed_when on command tasks"
        )

    def test_failover_waits_for_election(self):
        text = _read_text(self.FAILOVER_PATH)
        assert 'ansible.builtin.pause' in text or 'election_wait_seconds' in text, (
            "failover.yml must wait for election to propagate"
        )


# ---------------------------------------------------------------------------
# TestFailback -- failback.yml PREFERRED leader election
# ---------------------------------------------------------------------------
class TestFailback:
    """Verify failback.yml implements PREFERRED leader election."""

    FAILBACK_PATH = os.path.join(TASKS_DIR, 'failback.yml')

    def test_failback_triggers_preferred_election(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'kafka-leader-election.sh' in text, (
            "failback.yml must trigger leader election"
        )
        assert 'PREFERRED' in text, (
            "failback.yml must use PREFERRED election type"
        )

    def test_failback_uses_all_topic_partitions(self):
        text = _read_text(self.FAILBACK_PATH)
        assert '--all-topic-partitions' in text, (
            "failback.yml must use --all-topic-partitions flag"
        )

    def test_failback_includes_consul_flip(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'consul_flip.yml' in text, (
            "failback.yml must include consul_flip.yml"
        )

    def test_failback_checks_primary_reachability(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'kafka-broker-api-versions.sh' in text or 'kafka-topics.sh' in text, (
            "failback.yml must check primary DC reachability"
        )

    def test_failback_guards_cli_with_check_mode(self):
        text = _read_text(self.FAILBACK_PATH)
        assert 'not (ansible_check_mode' in text, (
            "failback.yml must guard CLI commands with check_mode condition"
        )

    def test_failback_sets_election_triggered(self):
        text = _read_text(self.FAILBACK_PATH)
        assert '_dr_election_triggered' in text, (
            "failback.yml must set _dr_election_triggered flag"
        )


# ---------------------------------------------------------------------------
# TestConsulFlip -- consul_flip.yml Consul KV operations
# ---------------------------------------------------------------------------
class TestConsulFlip:
    """Verify consul_flip.yml reads, updates, and verifies Consul KV."""

    CONSUL_PATH = os.path.join(TASKS_DIR, 'consul_flip.yml')

    def test_consul_has_at_least_4_tasks(self):
        data = _load_yaml(self.CONSUL_PATH)
        assert len(data) >= 4, (
            f"consul_flip.yml must have at least 4 tasks, found {len(data)}"
        )

    def test_consul_reads_current_region(self):
        text = _read_text(self.CONSUL_PATH)
        assert 'method: GET' in text
        assert '?raw' in text

    def test_consul_updates_target(self):
        text = _read_text(self.CONSUL_PATH)
        assert 'method: PUT' in text

    def test_consul_verifies_after_flip(self):
        text = _read_text(self.CONSUL_PATH)
        get_count = text.count('method: GET')
        assert get_count >= 2, (
            f"consul_flip.yml must verify with GET after PUT, found {get_count} GETs"
        )

    def test_consul_uses_mrc_variables(self):
        text = _read_text(self.CONSUL_PATH)
        assert 'cp_dr_mrc_consul_url' in text
        assert 'cp_dr_mrc_consul_kv_key' in text

    def test_consul_guards_put_with_check_mode(self):
        text = _read_text(self.CONSUL_PATH)
        assert 'ansible_check_mode' in text

    def test_consul_sets_flipped_flag(self):
        text = _read_text(self.CONSUL_PATH)
        assert '_dr_consul_flipped' in text


# ---------------------------------------------------------------------------
# TestValidateState -- validate_state.yml observer/writability checks
# ---------------------------------------------------------------------------
class TestValidateState:
    """Verify validate_state.yml checks topic availability and writability."""

    VALIDATE_PATH = os.path.join(TASKS_DIR, 'validate_state.yml')

    def test_has_validation_phase(self):
        text = _read_text(self.VALIDATE_PATH)
        assert '_validation_phase' in text

    def test_checks_topic_availability(self):
        text = _read_text(self.VALIDATE_PATH)
        assert 'kafka-topics.sh' in text, (
            "validate_state.yml must check topic availability"
        )

    def test_references_sla_tier_mirror_lag(self):
        text = _read_text(self.VALIDATE_PATH)
        assert 'sla_tier_mirror_lag' in text

    def test_has_writability_check(self):
        text = _read_text(self.VALIDATE_PATH)
        assert 'cp_dr_mrc_validate_writability' in text or 'writability' in text.lower(), (
            "validate_state.yml must have writability check on post-validation"
        )

    def test_sets_validation_passed(self):
        text = _read_text(self.VALIDATE_PATH)
        assert '_dr_validation_passed' in text


# ---------------------------------------------------------------------------
# TestCheckMode -- check.yml GET-only audit log
# ---------------------------------------------------------------------------
class TestCheckMode:
    """Verify check.yml produces audit log without CLI execution."""

    CHECK_PATH = os.path.join(TASKS_DIR, 'check.yml')

    def test_check_initializes_audit_log(self):
        text = _read_text(self.CHECK_PATH)
        assert '_dr_audit_log' in text

    def test_check_records_steps(self):
        text = _read_text(self.CHECK_PATH)
        assert 'step' in text
        assert 'action' in text
        assert 'current_state' in text
        assert 'expected_result' in text

    def test_check_has_failover_steps(self):
        """Check mode must have failover audit steps (4 steps)."""
        data = _load_yaml(self.CHECK_PATH)
        failover_steps = [
            task for task in data
            if isinstance(task, dict) and 'name' in task
            and 'failover' in task['name'].lower()
            and 'step' in task['name'].lower()
        ]
        assert len(failover_steps) == 4, (
            f"check.yml must have 4 failover audit steps, found "
            f"{len(failover_steps)}"
        )

    def test_check_has_failback_steps(self):
        """Check mode must have failback audit steps (3 steps)."""
        data = _load_yaml(self.CHECK_PATH)
        failback_steps = [
            task for task in data
            if isinstance(task, dict) and 'name' in task
            and 'failback' in task['name'].lower()
            and 'step' in task['name'].lower()
        ]
        assert len(failback_steps) == 3, (
            f"check.yml must have 3 failback audit steps, found "
            f"{len(failback_steps)}"
        )

    def test_check_displays_audit_log(self):
        text = _read_text(self.CHECK_PATH)
        assert 'ansible.builtin.debug' in text

    def test_check_no_put(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: PUT' not in text

    def test_check_no_post(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: POST' not in text

    def test_check_no_delete(self):
        text = _read_text(self.CHECK_PATH)
        assert 'method: DELETE' not in text

    def test_check_no_command(self):
        """Check mode must not run CLI commands."""
        text = _read_text(self.CHECK_PATH)
        assert 'ansible.builtin.command' not in text, (
            "check.yml must not run CLI commands (GET-only audit mode)"
        )


# ---------------------------------------------------------------------------
# TestElectionTemplate -- unclean_election.json.j2
# ---------------------------------------------------------------------------
class TestElectionTemplate:
    """Verify unclean_election.json.j2 template structure."""

    TEMPLATE_PATH = os.path.join(ROLE_DIR, 'templates', 'unclean_election.json.j2')

    def test_contains_partitions_key(self):
        text = _read_text(self.TEMPLATE_PATH)
        assert 'partitions' in text, (
            "unclean_election.json.j2 must contain 'partitions' key"
        )


# ---------------------------------------------------------------------------
# TestFQCN -- FQCN enforcement across all task files
# ---------------------------------------------------------------------------
class TestFQCN:
    """Verify all task files use FQCN for every module reference."""

    BARE_MODULES = [
        'command:', 'uri:', 'set_fact:', 'debug:', 'assert:', 'fail:',
        'include_tasks:', 'include_role:', 'shell:', 'wait_for:',
        'include_vars:', 'pause:', 'template:'
    ]

    TASK_FILES = [
        'main.yml', 'check.yml', 'failover.yml', 'failback.yml',
        'validate_state.yml', 'consul_flip.yml'
    ]

    def test_all_tasks_use_fqcn(self):
        for fname in self.TASK_FILES:
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
# TestTaskNames -- task name conventions
# ---------------------------------------------------------------------------
class TestTaskNames:
    """Verify all task names follow ansible-lint conventions."""

    TASK_FILES = [
        'main.yml', 'check.yml', 'failover.yml', 'failback.yml',
        'validate_state.yml', 'consul_flip.yml'
    ]

    def test_all_task_names_uppercase(self):
        for fname in self.TASK_FILES:
            path = os.path.join(TASKS_DIR, fname)
            if not os.path.isfile(path):
                continue
            data = _load_yaml(path)
            if not data:
                continue
            for task in data:
                if isinstance(task, dict) and 'name' in task:
                    name = task['name']
                    if name.startswith('{{'):
                        continue
                    assert name[0].isupper(), (
                        f"Task name in {fname} must start with uppercase: "
                        f"'{name}'"
                    )

    def test_no_jinja_before_final_position(self):
        for fname in self.TASK_FILES:
            path = os.path.join(TASKS_DIR, fname)
            if not os.path.isfile(path):
                continue
            data = _load_yaml(path)
            if not data:
                continue
            for task in data:
                if isinstance(task, dict) and 'name' in task:
                    name = task['name']
                    jinja_positions = [
                        m.start() for m in re.finditer(r'\{\{', name)
                    ]
                    if len(jinja_positions) <= 1:
                        continue
                    assert not name.startswith('{{'), (
                        f"Task name in {fname} starts with Jinja: '{name}'"
                    )


# ---------------------------------------------------------------------------
# TestMolecule -- molecule scenario for cp_dr_mrc
# ---------------------------------------------------------------------------
class TestMolecule:
    """Verify molecule scenario for cp_dr_mrc role."""

    def test_molecule_uses_delegated_driver(self):
        data = _load_yaml(os.path.join(MOLECULE_DIR, 'molecule.yml'))
        assert data['driver']['name'] == 'delegated'

    def test_converge_includes_cp_dr_mrc(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'converge.yml'))
        assert 'cp_dr_mrc' in text

    def test_converge_uses_check_mode(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'converge.yml'))
        assert 'check_mode' in text, (
            "converge.yml must use check_mode (no CLI binaries in CI)"
        )

    def test_verify_checks_results(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'verify.yml'))
        assert 'cp_dr_mrc_results' in text


# ---------------------------------------------------------------------------
# TestPlaybooks -- operator-facing playbooks
# ---------------------------------------------------------------------------
class TestPlaybooks:
    """Verify operator-facing MRC failover/failback playbooks."""

    def test_failover_playbook_exists(self):
        path = os.path.join(PLAYBOOKS_DIR, 'dr-failover-mrc.yml')
        assert os.path.isfile(path), "dr-failover-mrc.yml must exist"

    def test_failover_playbook_targets_kafka_broker(self):
        text = _read_text(os.path.join(PLAYBOOKS_DIR, 'dr-failover-mrc.yml'))
        assert 'kafka_broker[0]' in text

    def test_failover_playbook_includes_cp_dr_mrc(self):
        text = _read_text(os.path.join(PLAYBOOKS_DIR, 'dr-failover-mrc.yml'))
        assert 'cp_dr_mrc' in text
        assert 'include_role' in text

    def test_failover_playbook_sets_operation(self):
        text = _read_text(os.path.join(PLAYBOOKS_DIR, 'dr-failover-mrc.yml'))
        assert 'cp_dr_mrc_operation: failover' in text

    def test_failback_playbook_exists(self):
        path = os.path.join(PLAYBOOKS_DIR, 'dr-failback-mrc.yml')
        assert os.path.isfile(path), "dr-failback-mrc.yml must exist"

    def test_failback_playbook_targets_kafka_broker(self):
        text = _read_text(os.path.join(PLAYBOOKS_DIR, 'dr-failback-mrc.yml'))
        assert 'kafka_broker[0]' in text

    def test_failback_playbook_sets_operation(self):
        text = _read_text(os.path.join(PLAYBOOKS_DIR, 'dr-failback-mrc.yml'))
        assert 'cp_dr_mrc_operation: failback' in text

    def test_failback_playbook_no_gather_facts(self):
        data = _load_yaml(os.path.join(PLAYBOOKS_DIR, 'dr-failback-mrc.yml'))
        play = data[0]
        assert play.get('gather_facts') is False


# ---------------------------------------------------------------------------
# TestCI -- ansible-ci.yml molecule matrix includes cp_dr_mrc
# ---------------------------------------------------------------------------
class TestCI:
    """Verify CI workflow includes cp_dr_mrc in molecule matrix."""

    CI_PATH = os.path.join(REPO_ROOT, '.github', 'workflows', 'ansible-ci.yml')

    def test_ci_matrix_includes_cp_dr_mrc(self):
        data = _load_yaml(self.CI_PATH)
        jobs = data.get('jobs', data.get(True, {}).get('jobs', {}))
        # Handle PyYAML parsing 'on' as True
        if not jobs:
            for key in data:
                if isinstance(data[key], dict) and 'jobs' in data[key]:
                    jobs = data[key]['jobs']
                    break
        if not jobs:
            jobs = data.get('jobs', {})
        molecule = jobs.get('molecule', {})
        strategy = molecule.get('strategy', {})
        matrix = strategy.get('matrix', {})
        roles = matrix.get('role', [])
        assert 'cp_dr_mrc' in roles, (
            f"ansible-ci.yml molecule matrix must include cp_dr_mrc, "
            f"found: {roles}"
        )
