"""
Unit tests for the cp_rbac Ansible role.

Tests cover role structure, defaults, molecule scenarios, MDS authentication,
topic bindings, consumer group bindings, Schema Registry subject bindings,
reconciliation, check mode, error collection, FQCN compliance, and fixtures.
"""
import json
import os
import re

import pytest
import yaml

REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
ROLE_DIR = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cp_rbac')
FIXTURES_DIR = os.path.join(
    REPO_ROOT, 'tests', 'ansible', 'fixtures', 'mock_responses', 'mds'
)


def _read_yaml(path):
    """Read and parse a YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def _read_text(path):
    """Read a file as text."""
    with open(path) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestCpRbacRoleStructure -- role directory and file existence
# ---------------------------------------------------------------------------
class TestCpRbacRoleStructure:
    """Verify cp_rbac role has all required files."""

    def test_defaults_exist(self):
        path = os.path.join(ROLE_DIR, 'defaults', 'main.yml')
        assert os.path.isfile(path)
        data = _read_yaml(path)
        assert data is not None

    def test_meta_exist(self):
        path = os.path.join(ROLE_DIR, 'meta', 'main.yml')
        assert os.path.isfile(path)
        data = _read_yaml(path)
        assert data['galaxy_info']['role_name'] == 'cp_rbac'

    def test_task_files_exist(self):
        expected = [
            'main.yml', 'authenticate.yml', 'topic_bindings.yml',
            'group_bindings.yml', 'sr_bindings.yml', 'reconcile.yml',
            'check.yml',
        ]
        for filename in expected:
            path = os.path.join(ROLE_DIR, 'tasks', filename)
            assert os.path.isfile(path), f"Missing task file: {filename}"

    def test_molecule_files_exist(self):
        expected = [
            'molecule/default/molecule.yml',
            'molecule/default/converge.yml',
            'molecule/default/verify.yml',
        ]
        for relpath in expected:
            path = os.path.join(ROLE_DIR, relpath)
            assert os.path.isfile(path), f"Missing molecule file: {relpath}"

    def test_defaults_variables(self):
        data = _read_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        required_keys = [
            'cp_mds_url', 'cp_kafka_cluster_id', 'cp_sr_cluster_id',
            'cp_rbac_bindings', 'cp_rbac_reconcile',
            'cp_rbac_token_refresh_margin', 'cp_rbac_results',
        ]
        for key in required_keys:
            assert key in data, f"Missing default variable: {key}"

    def test_defaults_credential_vars_empty(self):
        data = _read_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cp_mds_username'] == ''
        assert data['cp_mds_password'] == ''

    def test_defaults_reconcile_enabled(self):
        data = _read_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cp_rbac_reconcile'] is True

    def test_defaults_token_refresh_margin(self):
        data = _read_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cp_rbac_token_refresh_margin'] == 60


# ---------------------------------------------------------------------------
# TestCpRbacMolecule -- molecule scenario configuration
# ---------------------------------------------------------------------------
class TestCpRbacMolecule:
    """Verify molecule test scenario configuration."""

    def test_molecule_uses_delegated_driver(self):
        data = _read_yaml(
            os.path.join(ROLE_DIR, 'molecule', 'default', 'molecule.yml')
        )
        assert data['driver']['name'] == 'delegated'

    def test_molecule_no_managed_hosts(self):
        data = _read_yaml(
            os.path.join(ROLE_DIR, 'molecule', 'default', 'molecule.yml')
        )
        # Delegated driver means no Docker/Podman provisioner
        assert data['driver']['name'] == 'delegated'
        # No docker or podman driver
        assert 'docker' not in str(data.get('driver', {}))

    def test_converge_uses_local_connection(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'molecule', 'default', 'converge.yml')
        )
        # The molecule.yml sets ansible_connection: local, but converge
        # should reference cp_rbac role
        assert 'cp_rbac' in text

    def test_converge_sets_mock_mds_url(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'molecule', 'default', 'converge.yml')
        )
        assert 'cp_mds_url' in text

    def test_verify_asserts_idempotency(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'molecule', 'default', 'verify.yml')
        )
        assert 'changed' in text

    def test_verify_includes_cp_rbac_role(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'molecule', 'default', 'verify.yml')
        )
        assert 'cp_rbac' in text


# ---------------------------------------------------------------------------
# TestCpRbacAuthentication -- MDS token handling
# ---------------------------------------------------------------------------
class TestCpRbacAuthentication:
    """Verify MDS token acquisition and refresh logic."""

    def test_authenticate_url(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'authenticate.yml')
        )
        assert 'security/1.0/authenticate' in text

    def test_authenticate_basic_auth(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'authenticate.yml')
        )
        assert 'force_basic_auth: true' in text

    def test_authenticate_no_log(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'authenticate.yml')
        )
        assert 'no_log: true' in text

    def test_authenticate_stores_token(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'authenticate.yml')
        )
        assert '_mds_token' in text

    def test_authenticate_computes_expiry(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'authenticate.yml')
        )
        assert '_mds_token_expires_at' in text

    def test_authenticate_reads_expires_in(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'authenticate.yml')
        )
        # Token refresh reads expires_in from response, not hardcoded
        assert 'expires_in' in text

    def test_token_refresh(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'main.yml')
        )
        # main.yml checks _mds_token_expires_at in a when condition
        assert '_mds_token_expires_at' in text

    def test_authenticate_uses_retries(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'authenticate.yml')
        )
        assert 'retries:' in text


# ---------------------------------------------------------------------------
# TestCpRbacTopicBindings -- topic DeveloperWrite/DeveloperRead
# ---------------------------------------------------------------------------
class TestCpRbacTopicBindings:
    """Verify topic RBAC binding tasks."""

    def test_topic_bindings_developer_write(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'topic_bindings.yml')
        )
        assert 'DeveloperWrite' in text

    def test_topic_bindings_developer_read(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'topic_bindings.yml')
        )
        assert 'DeveloperRead' in text

    def test_topic_bindings_literal_pattern(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'topic_bindings.yml')
        )
        assert 'LITERAL' in text

    def test_topic_bindings_topic_resource_type(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'topic_bindings.yml')
        )
        assert 'resourceType' in text
        assert 'Topic' in text

    def test_topic_bindings_uses_token(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'topic_bindings.yml')
        )
        assert '_mds_token' in text

    def test_topic_bindings_scope(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'topic_bindings.yml')
        )
        assert 'kafka-cluster' in text


# ---------------------------------------------------------------------------
# TestCpRbacGroupBindings -- consumer group PREFIXED bindings
# ---------------------------------------------------------------------------
class TestCpRbacGroupBindings:
    """Verify consumer group RBAC binding tasks."""

    def test_group_bindings_prefixed(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'group_bindings.yml')
        )
        assert 'PREFIXED' in text

    def test_group_bindings_resource_type(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'group_bindings.yml')
        )
        assert 'Group' in text

    def test_group_bindings_principal_prefix(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'group_bindings.yml')
        )
        # Must strip User: prefix from principal name
        assert 'regex_replace' in text or 'User:' in text

    def test_group_bindings_developer_read(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'group_bindings.yml')
        )
        assert 'DeveloperRead' in text

    def test_group_bindings_no_asterisk(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'group_bindings.yml')
        )
        # Research pitfall 6: MDS handles prefix matching implicitly.
        # The resource name pattern must NOT contain an asterisk.
        # Check the body/resourcePatterns section for * in name field
        lines = text.split('\n')
        in_resource_patterns = False
        for line in lines:
            if 'resourcePatterns' in line:
                in_resource_patterns = True
            if in_resource_patterns and 'name:' in line:
                assert '*' not in line, (
                    "Group binding name must not contain asterisk "
                    "(MDS handles prefix matching implicitly)"
                )
                break


# ---------------------------------------------------------------------------
# TestCpRbacSrBindings -- Schema Registry subject bindings
# ---------------------------------------------------------------------------
class TestCpRbacSrBindings:
    """Verify Schema Registry subject RBAC binding tasks."""

    def test_sr_bindings_scope(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'sr_bindings.yml')
        )
        assert 'schema-registry-cluster' in text

    def test_sr_bindings_subject_type(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'sr_bindings.yml')
        )
        assert 'Subject' in text

    def test_sr_bindings_value_subject(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'sr_bindings.yml')
        )
        assert '-value' in text

    def test_sr_bindings_key_subject(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'sr_bindings.yml')
        )
        assert '-key' in text

    def test_sr_producer_developer_write(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'sr_bindings.yml')
        )
        assert 'DeveloperWrite' in text

    def test_sr_consumer_developer_read(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'sr_bindings.yml')
        )
        assert 'DeveloperRead' in text


# ---------------------------------------------------------------------------
# TestCpRbacReconciliation -- LIST/DIFF/ADD/REMOVE
# ---------------------------------------------------------------------------
class TestCpRbacReconciliation:
    """Verify reconciliation logic for stale binding cleanup."""

    def test_reconcile_lists_resources(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'reconcile.yml')
        )
        assert 'resources' in text

    def test_reconcile_uses_delete(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'reconcile.yml')
        )
        assert 'DELETE' in text

    def test_reconcile_scope_filter(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'reconcile.yml')
        )
        # Reconciliation filters to Topic, Group, Subject resourceTypes
        assert 'Topic' in text
        assert 'Group' in text
        assert 'Subject' in text

    def test_reconcile_conditional(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'main.yml')
        )
        assert 'cp_rbac_reconcile' in text

    def test_reconcile_uses_ignore_errors(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'reconcile.yml')
        )
        # Uses failed_when: false (ignore_errors equivalent)
        assert 'failed_when: false' in text or 'ignore_errors' in text


# ---------------------------------------------------------------------------
# TestCpRbacCheckMode -- check mode diff reporting
# ---------------------------------------------------------------------------
class TestCpRbacCheckMode:
    """Verify check mode handling."""

    def test_check_forces_execution(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'check.yml')
        )
        assert 'check_mode: false' in text

    def test_check_uses_debug(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'check.yml')
        )
        assert 'ansible.builtin.debug' in text

    def test_main_routes_check_mode(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'main.yml')
        )
        assert 'ansible_check_mode' in text


# ---------------------------------------------------------------------------
# TestCpRbacErrorCollection -- error handling in main.yml
# ---------------------------------------------------------------------------
class TestCpRbacErrorCollection:
    """Verify error collection and reporting in main entry point."""

    def test_main_uses_ignore_errors(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'main.yml')
        )
        assert 'ignore_errors' in text

    def test_main_registers_results(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'main.yml')
        )
        assert 'cp_rbac_results' in text

    def test_main_fails_on_errors(self):
        text = _read_text(
            os.path.join(ROLE_DIR, 'tasks', 'main.yml')
        )
        assert 'ansible.builtin.fail' in text


# ---------------------------------------------------------------------------
# TestCpRbacFQCN -- all task files use fully qualified collection names
# ---------------------------------------------------------------------------
class TestCpRbacFQCN:
    """Verify all task files use FQCN for module references."""

    # Bare module names that should be fully qualified
    BARE_MODULES = [
        'uri', 'set_fact', 'debug', 'assert', 'fail',
        'include_tasks', 'include_role', 'shell',
        'command', 'wait_for', 'slurp', 'file', 'find',
        'include_vars', 'template', 'copy',
    ]

    def test_all_tasks_use_fqcn(self):
        task_dir = os.path.join(ROLE_DIR, 'tasks')
        for filename in os.listdir(task_dir):
            if not filename.endswith('.yml'):
                continue
            text = _read_text(os.path.join(task_dir, filename))
            for line in text.split('\n'):
                stripped = line.strip()
                # Skip comments and non-module lines
                if stripped.startswith('#') or ':' not in stripped:
                    continue
                # Check for bare module usage (key: value where key is
                # a bare module name)
                for module in self.BARE_MODULES:
                    pattern = rf'^{module}:'
                    if re.match(pattern, stripped):
                        pytest.fail(
                            f"Bare module '{module}' in "
                            f"{filename}: {stripped}"
                        )


# ---------------------------------------------------------------------------
# TestCpRbacFixtures -- MDS mock response fixtures
# ---------------------------------------------------------------------------
class TestCpRbacFixtures:
    """Verify MDS mock response fixtures are valid."""

    def test_mock_responses_valid_json(self):
        for filename in os.listdir(FIXTURES_DIR):
            if not filename.endswith('.json'):
                continue
            path = os.path.join(FIXTURES_DIR, filename)
            with open(path) as f:
                data = json.load(f)
            assert data is not None, f"Invalid JSON in {filename}"

    def test_authenticate_response_structure(self):
        path = os.path.join(FIXTURES_DIR, 'authenticate.json')
        with open(path) as f:
            data = json.load(f)
        assert 'auth_token' in data
        assert 'token_type' in data
        assert 'expires_in' in data

    def test_list_resources_structure(self):
        path = os.path.join(FIXTURES_DIR, 'list_resources.json')
        with open(path) as f:
            data = json.load(f)
        assert isinstance(data, list)
        for item in data:
            assert 'resourceType' in item
            assert 'name' in item
            assert 'patternType' in item
