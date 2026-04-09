"""
Unit tests for the cp_topic Ansible role.

Tests validate role structure, molecule configuration, governance filter wiring,
API endpoint usage, check mode implementation, deletion guards, error collection,
FQCN enforcement, and test fixture integrity.
"""
import json
import os

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROLE_DIR = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cp_topic')
TASKS_DIR = os.path.join(ROLE_DIR, 'tasks')
MOLECULE_DIR = os.path.join(ROLE_DIR, 'molecule', 'default')
FIXTURES_DIR = os.path.join(REPO_ROOT, 'tests', 'ansible', 'fixtures')


def _load_yaml(path):
    """Load and parse a YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def _read_text(path):
    """Read file as raw text."""
    with open(path) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestCpTopicRoleStructure -- role files and default variables
# ---------------------------------------------------------------------------
class TestCpTopicRoleStructure:
    """Verify cp_topic role directory structure and defaults."""

    def test_defaults_exist(self):
        path = os.path.join(ROLE_DIR, 'defaults', 'main.yml')
        assert os.path.isfile(path)
        data = _load_yaml(path)
        assert data is not None

    def test_meta_exist(self):
        path = os.path.join(ROLE_DIR, 'meta', 'main.yml')
        assert os.path.isfile(path)
        data = _load_yaml(path)
        assert data['galaxy_info']['role_name'] == 'cp_topic'

    def test_task_files_exist(self):
        expected = ['main.yml', 'validate.yml', 'create.yml', 'update.yml',
                    'delete.yml', 'check.yml']
        for fname in expected:
            path = os.path.join(TASKS_DIR, fname)
            assert os.path.isfile(path), f"Missing task file: {fname}"

    def test_molecule_files_exist(self):
        expected = ['molecule.yml', 'converge.yml', 'verify.yml']
        for fname in expected:
            path = os.path.join(MOLECULE_DIR, fname)
            assert os.path.isfile(path), f"Missing molecule file: {fname}"

    def test_defaults_variables(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        for key in ['cp_admin_rest_url', 'cp_cluster_id', 'cp_topics_dir',
                     'cp_topics', 'cp_replication_factor', 'cp_topic_results']:
            assert key in data, f"Missing default variable: {key}"

    def test_defaults_credential_vars_empty(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        for key in ['cp_admin_rest_token', 'cp_admin_rest_user',
                     'cp_admin_rest_password']:
            assert data[key] == '', f"Credential var {key} should default to empty string"


# ---------------------------------------------------------------------------
# TestCpTopicMolecule -- molecule scenario configuration
# ---------------------------------------------------------------------------
class TestCpTopicMolecule:
    """Verify molecule scenario files."""

    def test_molecule_uses_delegated_driver(self):
        data = _load_yaml(os.path.join(MOLECULE_DIR, 'molecule.yml'))
        assert data['driver']['name'] == 'delegated'

    def test_molecule_no_managed_hosts(self):
        data = _load_yaml(os.path.join(MOLECULE_DIR, 'molecule.yml'))
        # Delegated driver means no Docker/Podman provisioner
        assert data['driver']['name'] == 'delegated'
        assert 'docker' not in str(data).lower()

    def test_converge_uses_local_connection(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'converge.yml'))
        # The molecule.yml defines ansible_connection: local for the host
        mol_text = _read_text(os.path.join(MOLECULE_DIR, 'molecule.yml'))
        assert 'ansible_connection: local' in mol_text or 'ansible_connection: local' in text

    def test_converge_sets_mock_api_url(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'converge.yml'))
        assert 'cp_admin_rest_url' in text

    def test_verify_asserts_idempotency(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'verify.yml'))
        assert 'changed' in text

    def test_verify_includes_cp_topic_role(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'verify.yml'))
        assert 'cp_topic' in text


# ---------------------------------------------------------------------------
# TestCpTopicGovernanceWiring -- governance filter and constant usage
# ---------------------------------------------------------------------------
class TestCpTopicGovernanceWiring:
    """Verify governance filters and constants are wired in task files."""

    def test_main_loads_sla_tiers(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'sla_tiers.yml' in text

    def test_main_loads_naming_rules(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'naming_rules.yml' in text

    def test_validate_uses_fsi_validate_topic_name(self):
        text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'fsi_validate_topic_name' in text

    def test_validate_uses_fsi_sla_lookup(self):
        text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'fsi_sla_lookup' in text

    def test_sla_tier_derivation(self):
        sla_path = os.path.join(REPO_ROOT, 'ansible', 'vars', 'sla_tiers.yml')
        data = _load_yaml(sla_path)
        tiers = data['sla_tiers']
        # Critical
        assert tiers['critical']['partitions'] == 12
        assert tiers['critical']['retention_ms'] == 604800000
        assert tiers['critical']['min_insync_replicas'] == 2
        # Standard
        assert tiers['standard']['partitions'] == 6
        assert tiers['standard']['retention_ms'] == 259200000
        assert tiers['standard']['min_insync_replicas'] == 2
        # Best-effort
        assert tiers['best-effort']['partitions'] == 3
        assert tiers['best-effort']['retention_ms'] == 86400000
        assert tiers['best-effort']['min_insync_replicas'] == 1
        # Compliance
        assert tiers['compliance']['partitions'] == 12
        assert tiers['compliance']['retention_ms'] == -1
        assert tiers['compliance']['min_insync_replicas'] == 2


# ---------------------------------------------------------------------------
# TestCpTopicApiWiring -- REST API endpoint and method usage
# ---------------------------------------------------------------------------
class TestCpTopicApiWiring:
    """Verify Admin REST v3 API patterns in create and update task files."""

    def test_create_uses_admin_rest_v3_url(self):
        text = _read_text(os.path.join(TASKS_DIR, 'create.yml'))
        assert 'kafka/v3/clusters' in text

    def test_create_uses_post_method(self):
        text = _read_text(os.path.join(TASKS_DIR, 'create.yml'))
        assert 'method: POST' in text

    def test_create_stringifies_config_values(self):
        text = _read_text(os.path.join(TASKS_DIR, 'create.yml'))
        assert '| string' in text

    def test_create_handles_404_and_200(self):
        text = _read_text(os.path.join(TASKS_DIR, 'create.yml'))
        assert '200' in text
        assert '404' in text

    def test_create_uses_retries(self):
        text = _read_text(os.path.join(TASKS_DIR, 'create.yml'))
        assert 'retries:' in text

    def test_update_uses_configs_alter(self):
        text = _read_text(os.path.join(TASKS_DIR, 'update.yml'))
        assert 'configs:alter' in text

    def test_update_uses_set_operation(self):
        text = _read_text(os.path.join(TASKS_DIR, 'update.yml'))
        assert 'SET' in text


# ---------------------------------------------------------------------------
# TestCpTopicCheckMode -- check-mode implementation
# ---------------------------------------------------------------------------
class TestCpTopicCheckMode:
    """Verify check-mode task file implementation."""

    def test_check_yml_forces_execution(self):
        text = _read_text(os.path.join(TASKS_DIR, 'check.yml'))
        assert 'check_mode: false' in text

    def test_check_yml_uses_debug(self):
        text = _read_text(os.path.join(TASKS_DIR, 'check.yml'))
        assert 'ansible.builtin.debug' in text

    def test_check_yml_uses_changed_when(self):
        text = _read_text(os.path.join(TASKS_DIR, 'check.yml'))
        assert 'changed_when' in text

    def test_main_routes_to_check_mode(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'ansible_check_mode' in text


# ---------------------------------------------------------------------------
# TestCpTopicDeletion -- deletion guard implementation
# ---------------------------------------------------------------------------
class TestCpTopicDeletion:
    """Verify deletion safety gates in delete.yml."""

    def test_delete_requires_confirm(self):
        text = _read_text(os.path.join(TASKS_DIR, 'delete.yml'))
        assert 'confirm_deletion' in text

    def test_delete_blocks_critical_tier(self):
        text = _read_text(os.path.join(TASKS_DIR, 'delete.yml'))
        assert 'critical' in text

    def test_delete_blocks_compliance_tier(self):
        text = _read_text(os.path.join(TASKS_DIR, 'delete.yml'))
        assert 'compliance' in text

    def test_delete_force_override(self):
        text = _read_text(os.path.join(TASKS_DIR, 'delete.yml'))
        assert 'force_delete_override' in text

    def test_delete_idempotent_404(self):
        text = _read_text(os.path.join(TASKS_DIR, 'delete.yml'))
        assert '404' in text


# ---------------------------------------------------------------------------
# TestCpTopicErrorCollection -- error collection and summary pattern
# ---------------------------------------------------------------------------
class TestCpTopicErrorCollection:
    """Verify error collection pattern in main.yml."""

    def test_main_uses_ignore_errors(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'ignore_errors: true' in text

    def test_main_registers_results(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'cp_topic_results' in text

    def test_main_fails_on_errors(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'ansible.builtin.fail' in text
        assert 'failed' in text


# ---------------------------------------------------------------------------
# TestCpTopicFQCN -- fully qualified collection name enforcement
# ---------------------------------------------------------------------------
class TestCpTopicFQCN:
    """Verify all task files use FQCN for every module reference."""

    # Bare module names that should never appear as top-level task keys
    BARE_MODULES = [
        'uri:', 'set_fact:', 'debug:', 'assert:', 'fail:',
        'include_tasks:', 'find:', 'slurp:', 'include_vars:',
        'include_role:', 'shell:', 'wait_for:'
    ]

    def test_all_tasks_use_fqcn(self):
        task_files = ['main.yml', 'validate.yml', 'create.yml', 'update.yml',
                      'delete.yml', 'check.yml', 'process_one.yml']
        for fname in task_files:
            path = os.path.join(TASKS_DIR, fname)
            if not os.path.isfile(path):
                continue
            text = _read_text(path)
            for bare in self.BARE_MODULES:
                # Check for bare module name at the start of a line (after spaces)
                # A bare module reference would be like "  uri:" without "ansible.builtin." prefix
                lines = text.split('\n')
                for i, line in enumerate(lines):
                    stripped = line.lstrip()
                    # Skip comments and empty lines
                    if stripped.startswith('#') or not stripped:
                        continue
                    # Skip lines that are values (contain the bare name in a value context)
                    if stripped.startswith('- name:') or stripped.startswith('name:'):
                        continue
                    # Check if bare module is used as a task action key
                    if stripped.startswith(bare):
                        # But not if it's prefixed with "ansible.builtin."
                        assert False, (
                            f"Bare module '{bare}' found in {fname} line {i + 1}: "
                            f"'{stripped}'. Use ansible.builtin.{bare[:-1]} instead."
                        )


# ---------------------------------------------------------------------------
# TestCpTopicFixtures -- test fixture integrity
# ---------------------------------------------------------------------------
class TestCpTopicFixtures:
    """Verify test fixture files are valid."""

    def test_mock_responses_valid_json(self):
        mock_dir = os.path.join(FIXTURES_DIR, 'mock_responses', 'admin_rest_v3')
        for fname in os.listdir(mock_dir):
            if fname.endswith('.json'):
                path = os.path.join(mock_dir, fname)
                with open(path) as f:
                    data = json.load(f)
                assert data is not None, f"Failed to parse JSON: {fname}"

    def test_cptopic_samples_valid_yaml(self):
        samples_dir = os.path.join(FIXTURES_DIR, 'cptopic_samples')
        for fname in os.listdir(samples_dir):
            if fname.endswith('.yml'):
                path = os.path.join(samples_dir, fname)
                data = _load_yaml(path)
                assert data['kind'] == 'CPTopic', f"{fname} missing kind: CPTopic"
                assert 'name' in data['metadata'], f"{fname} missing metadata.name"

    def test_cptopic_yaml_parsing(self):
        path = os.path.join(FIXTURES_DIR, 'cptopic_samples',
                            'corebanking-account-txn.yml')
        data = _load_yaml(path)
        assert data['metadata']['labels']['fsi.sla-tier'] == 'critical'
        assert data['metadata']['name'] == 'corebanking.transactions.v1.account-transaction'
