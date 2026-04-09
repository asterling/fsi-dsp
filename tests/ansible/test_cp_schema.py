"""
Unit tests for the cp_schema Ansible role.

Tests cover role structure, molecule scenario configuration, governance wiring
(SLA tiers, filter plugins), two-pass compatibility-then-register flow,
structural validation, schema registration, PII metadata properties, check
mode routing, error collection, FQCN enforcement, and SR mock fixtures.
"""
import json
import os
import re

import pytest
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROLE_DIR = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cp_schema')


def load_yaml_file(relpath):
    """Load a YAML file relative to the repo root."""
    with open(os.path.join(REPO_ROOT, relpath)) as f:
        return yaml.safe_load(f)


def load_role_yaml(relpath):
    """Load a YAML file relative to the role directory."""
    with open(os.path.join(ROLE_DIR, relpath)) as f:
        return yaml.safe_load(f)


def load_role_text(relpath):
    """Load raw text from a file relative to the role directory."""
    with open(os.path.join(ROLE_DIR, relpath)) as f:
        return f.read()


def load_text(relpath):
    """Load raw text from a file relative to the repo root."""
    with open(os.path.join(REPO_ROOT, relpath)) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestCpSchemaRoleStructure
# ---------------------------------------------------------------------------
class TestCpSchemaRoleStructure:
    """Verify cp_schema role file structure and default variables."""

    def test_defaults_exist(self):
        path = os.path.join(ROLE_DIR, 'defaults', 'main.yml')
        assert os.path.isfile(path)
        data = load_role_yaml('defaults/main.yml')
        assert data is not None

    def test_meta_exist(self):
        data = load_role_yaml('meta/main.yml')
        assert data['galaxy_info']['role_name'] == 'cp_schema'

    def test_task_files_exist(self):
        for task_file in ['main.yml', 'validate.yml', 'compatibility.yml',
                          'register.yml', 'check.yml']:
            path = os.path.join(ROLE_DIR, 'tasks', task_file)
            assert os.path.isfile(path), f"Missing task file: {task_file}"

    def test_molecule_files_exist(self):
        for mol_file in ['molecule/default/molecule.yml',
                         'molecule/default/converge.yml',
                         'molecule/default/verify.yml']:
            path = os.path.join(ROLE_DIR, mol_file)
            assert os.path.isfile(path), f"Missing molecule file: {mol_file}"

    def test_defaults_variables(self):
        data = load_role_yaml('defaults/main.yml')
        expected_keys = [
            'cp_sr_url',
            'cp_schema_metadata_enabled',
            'cp_schema_validate_structural',
            'cp_schema_validate_script',
            'cp_schema_results',
        ]
        for key in expected_keys:
            assert key in data, f"Missing default variable: {key}"

    def test_defaults_credential_vars_empty(self):
        data = load_role_yaml('defaults/main.yml')
        assert data['cp_sr_user'] == ''
        assert data['cp_sr_password'] == ''
        assert data['cp_sr_token'] == ''


# ---------------------------------------------------------------------------
# TestCpSchemaMolecule
# ---------------------------------------------------------------------------
class TestCpSchemaMolecule:
    """Verify molecule scenario configuration."""

    def test_molecule_uses_delegated_driver(self):
        data = load_role_yaml('molecule/default/molecule.yml')
        assert data['driver']['name'] == 'delegated'

    def test_molecule_no_managed_hosts(self):
        data = load_role_yaml('molecule/default/molecule.yml')
        # Delegated driver means no Docker/Podman provisioner
        assert data['driver']['name'] == 'delegated'
        # No 'managed' key or explicit Docker references
        assert 'docker' not in str(data).lower()

    def test_converge_uses_local_connection(self):
        """ansible_connection: local is set in molecule.yml inventory."""
        text = load_role_text('molecule/default/molecule.yml')
        assert 'ansible_connection: local' in text

    def test_converge_sets_mock_sr_url(self):
        text = load_role_text('molecule/default/converge.yml')
        assert 'cp_sr_url' in text

    def test_verify_asserts_idempotency(self):
        text = load_role_text('molecule/default/verify.yml')
        assert 'changed' in text

    def test_verify_includes_cp_schema_role(self):
        text = load_role_text('molecule/default/verify.yml')
        assert 'cp_schema' in text


# ---------------------------------------------------------------------------
# TestCpSchemaGovernanceWiring
# ---------------------------------------------------------------------------
class TestCpSchemaGovernanceWiring:
    """Verify governance constants and filter plugin integration."""

    def test_main_loads_sla_tiers(self):
        text = load_role_text('tasks/main.yml')
        assert 'sla_tiers.yml' in text

    def test_compatibility_uses_fsi_sla_lookup(self):
        text = load_role_text('tasks/compatibility.yml')
        assert 'fsi_sla_lookup' in text

    def test_compatibility_mode(self):
        """Verify SLA tier -> compatibility mode mapping from sla_tiers.yml."""
        sla = load_yaml_file('ansible/vars/sla_tiers.yml')
        expected = {
            'critical': 'FULL_TRANSITIVE',
            'standard': 'BACKWARD_TRANSITIVE',
            'best-effort': 'BACKWARD',
            'compliance': 'FULL_TRANSITIVE',
        }
        for tier, mode in expected.items():
            actual = sla['sla_tiers'][tier]['compatibility']
            assert actual == mode, \
                f"SLA tier '{tier}' expected {mode}, got {actual}"


# ---------------------------------------------------------------------------
# TestCpSchemaTwoPassFlow
# ---------------------------------------------------------------------------
class TestCpSchemaTwoPassFlow:
    """Verify two-pass safety: compatibility for all, then register all."""

    def test_main_includes_compatibility(self):
        text = load_role_text('tasks/main.yml')
        assert 'compatibility.yml' in text

    def test_main_includes_register(self):
        text = load_role_text('tasks/main.yml')
        assert 'register.yml' in text

    def test_compatibility_before_register(self):
        """Compatibility include must appear before register include in main.yml."""
        text = load_role_text('tasks/main.yml')
        lines = text.split('\n')
        compat_line = None
        register_line = None
        for i, line in enumerate(lines):
            if 'compatibility.yml' in line and compat_line is None:
                compat_line = i
            if 'register.yml' in line and register_line is None:
                register_line = i
        assert compat_line is not None, "compatibility.yml not found in main.yml"
        assert register_line is not None, "register.yml not found in main.yml"
        assert compat_line < register_line, \
            f"compatibility.yml (line {compat_line}) must appear before " \
            f"register.yml (line {register_line})"

    def test_compatibility_check(self):
        text = load_role_text('tasks/compatibility.yml')
        assert 'compatibility/subjects' in text

    def test_compatibility_checks_is_compatible(self):
        text = load_role_text('tasks/compatibility.yml')
        assert 'is_compatible' in text


# ---------------------------------------------------------------------------
# TestCpSchemaValidation
# ---------------------------------------------------------------------------
class TestCpSchemaValidation:
    """Verify structural validation wiring."""

    def test_validate_uses_command_module(self):
        text = load_role_text('tasks/validate.yml')
        assert 'ansible.builtin.command' in text

    def test_validate_references_script(self):
        text = load_role_text('tasks/validate.yml')
        assert 'validate-schemas.py' in text

    def test_schema_validation_script_exists(self):
        path = os.path.join(REPO_ROOT, 'ci', 'scripts', 'validate-schemas.py')
        assert os.path.isfile(path), "validate-schemas.py not found on disk"


# ---------------------------------------------------------------------------
# TestCpSchemaRegistration
# ---------------------------------------------------------------------------
class TestCpSchemaRegistration:
    """Verify schema registration task configuration."""

    def test_register_posts_to_subjects(self):
        text = load_role_text('tasks/register.yml')
        assert '/subjects/' in text

    def test_register_includes_schema_type(self):
        text = load_role_text('tasks/register.yml')
        assert 'schemaType' in text

    def test_register_includes_avro(self):
        text = load_role_text('tasks/register.yml')
        assert 'AVRO' in text

    def test_register_stringifies_schema(self):
        text = load_role_text('tasks/register.yml')
        assert 'to_json' in text

    def test_register_uses_retries(self):
        text = load_role_text('tasks/register.yml')
        assert 'retries:' in text


# ---------------------------------------------------------------------------
# TestCpSchemaMetadata
# ---------------------------------------------------------------------------
class TestCpSchemaMetadata:
    """Verify PII metadata properties match Terraform pattern."""

    def test_register_includes_metadata_block(self):
        text = load_role_text('tasks/register.yml')
        assert 'metadata' in text

    def test_register_metadata_has_owner(self):
        text = load_role_text('tasks/register.yml')
        assert 'owner' in text

    def test_register_metadata_has_sla_tier(self):
        text = load_role_text('tasks/register.yml')
        assert 'sla-tier' in text

    def test_register_metadata_has_pii(self):
        text = load_role_text('tasks/register.yml')
        assert 'pii' in text

    def test_register_metadata_has_pii_fields(self):
        text = load_role_text('tasks/register.yml')
        assert 'pii-fields' in text or 'pii_fields' in text

    def test_register_metadata_conditional(self):
        text = load_role_text('tasks/register.yml')
        assert 'cp_schema_metadata_enabled' in text

    def test_metadata_properties_match_terraform(self):
        """All 7 Terraform schema_metadata properties must appear in register.yml."""
        tf_text = load_text('modules/topic/main.tf')
        # Extract schema_metadata keys from Terraform
        metadata_match = re.search(
            r'schema_metadata\s*=\s*\{([\s\S]*?)\}', tf_text
        )
        assert metadata_match, "schema_metadata not found in main.tf"
        metadata_block = metadata_match.group(1)
        # Extract property names (quoted keys)
        tf_properties = re.findall(r'"([^"]+)"\s*=', metadata_block)
        assert len(tf_properties) == 7, \
            f"Expected 7 metadata properties, found {len(tf_properties)}: {tf_properties}"

        register_text = load_role_text('tasks/register.yml')
        for prop in tf_properties:
            assert prop in register_text, \
                f"Terraform metadata property '{prop}' not found in register.yml"


# ---------------------------------------------------------------------------
# TestCpSchemaCheckMode
# ---------------------------------------------------------------------------
class TestCpSchemaCheckMode:
    """Verify check-mode routing and execution."""

    def test_check_forces_execution(self):
        text = load_role_text('tasks/check.yml')
        assert 'check_mode: false' in text

    def test_check_uses_debug(self):
        text = load_role_text('tasks/check.yml')
        assert 'ansible.builtin.debug' in text

    def test_main_routes_check_mode(self):
        text = load_role_text('tasks/main.yml')
        assert 'ansible_check_mode' in text


# ---------------------------------------------------------------------------
# TestCpSchemaErrorCollection
# ---------------------------------------------------------------------------
class TestCpSchemaErrorCollection:
    """Verify error collection and result aggregation."""

    def test_main_uses_error_suppression(self):
        """main.yml uses failed_when: false for error suppression
        (ansible-lint compliant replacement for ignore_errors)."""
        text = load_role_text('tasks/main.yml')
        assert 'failed_when' in text

    def test_main_registers_results(self):
        text = load_role_text('tasks/main.yml')
        assert 'cp_schema_results' in text


# ---------------------------------------------------------------------------
# TestCpSchemaFQCN
# ---------------------------------------------------------------------------
class TestCpSchemaFQCN:
    """Verify all task files use Fully Qualified Collection Names."""

    # Bare module names that should be fully qualified
    BARE_MODULES = [
        'set_fact:', 'include_vars:', 'include_tasks:', 'debug:',
        'fail:', 'uri:', 'command:', 'find:', 'slurp:', 'assert:',
        'shell:', 'wait_for:', 'include_role:',
    ]

    def test_all_tasks_use_fqcn(self):
        """Scan all 5 task files for bare module names (not FQCN)."""
        task_files = ['main.yml', 'validate.yml', 'compatibility.yml',
                      'register.yml', 'check.yml']
        violations = []
        for task_file in task_files:
            text = load_role_text(f'tasks/{task_file}')
            for line_num, line in enumerate(text.split('\n'), 1):
                stripped = line.strip()
                # Skip comments and empty lines
                if stripped.startswith('#') or not stripped:
                    continue
                for bare in self.BARE_MODULES:
                    # Match bare module at start of a YAML key (after possible -)
                    if re.match(rf'^\s*-?\s*{re.escape(bare)}', stripped):
                        # Only flag if it's NOT prefixed by a collection namespace
                        if not re.search(r'\w+\.\w+\.' + re.escape(bare), stripped):
                            violations.append(
                                f"{task_file}:{line_num}: bare module '{bare}' -- {stripped}"
                            )
        assert not violations, \
            f"FQCN violations found:\n" + "\n".join(violations)


# ---------------------------------------------------------------------------
# TestCpSchemaFixtures
# ---------------------------------------------------------------------------
class TestCpSchemaFixtures:
    """Verify SR mock response fixture files."""

    FIXTURE_DIR = os.path.join(
        REPO_ROOT, 'tests', 'ansible', 'fixtures',
        'mock_responses', 'schema_registry'
    )

    def test_mock_responses_valid_json(self):
        """All JSON files in schema_registry fixture dir are valid JSON."""
        json_files = [f for f in os.listdir(self.FIXTURE_DIR) if f.endswith('.json')]
        assert len(json_files) > 0, "No JSON fixture files found"
        for filename in json_files:
            path = os.path.join(self.FIXTURE_DIR, filename)
            with open(path) as f:
                data = json.load(f)
            assert data is not None, f"Empty JSON in {filename}"

    def test_compatible_response_structure(self):
        path = os.path.join(self.FIXTURE_DIR, 'schema_compatible.json')
        with open(path) as f:
            data = json.load(f)
        assert data['is_compatible'] is True

    def test_incompatible_response_structure(self):
        path = os.path.join(self.FIXTURE_DIR, 'schema_incompatible.json')
        with open(path) as f:
            data = json.load(f)
        assert data['is_compatible'] is False
