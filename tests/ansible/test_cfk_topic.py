"""
Unit tests for the cfk_topic Ansible role.

Tests cover role structure, default variables, meta information, governance
wiring (fsi_validate_topic_name, fsi_sla_lookup), CRD generation patterns
(string-typed configs, namespace, kafkaClusterRef), governance parity with
cp_topic role, molecule scenario, FQCN enforcement, and task name casing.
"""
import os

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROLE_DIR = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cfk_topic')
TASKS_DIR = os.path.join(ROLE_DIR, 'tasks')
MOLECULE_DIR = os.path.join(ROLE_DIR, 'molecule', 'default')
CP_TOPIC_TASKS = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cp_topic', 'tasks')


def _load_yaml(path):
    """Load and parse a YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def _read_text(path):
    """Read file as raw text."""
    with open(path) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestRoleStructure -- role files exist
# ---------------------------------------------------------------------------
class TestRoleStructure:
    """Verify all required cfk_topic role files exist."""

    def test_defaults_exist(self):
        assert os.path.isfile(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))

    def test_meta_exist(self):
        assert os.path.isfile(os.path.join(ROLE_DIR, 'meta', 'main.yml'))

    def test_tasks_main_exist(self):
        assert os.path.isfile(os.path.join(TASKS_DIR, 'main.yml'))

    def test_tasks_validate_exist(self):
        assert os.path.isfile(os.path.join(TASKS_DIR, 'validate.yml'))

    def test_tasks_generate_exist(self):
        assert os.path.isfile(os.path.join(TASKS_DIR, 'generate.yml'))

    def test_tasks_check_exist(self):
        assert os.path.isfile(os.path.join(TASKS_DIR, 'check.yml'))

    def test_molecule_yml_exist(self):
        assert os.path.isfile(os.path.join(MOLECULE_DIR, 'molecule.yml'))

    def test_molecule_converge_exist(self):
        assert os.path.isfile(os.path.join(MOLECULE_DIR, 'converge.yml'))

    def test_molecule_verify_exist(self):
        assert os.path.isfile(os.path.join(MOLECULE_DIR, 'verify.yml'))


# ---------------------------------------------------------------------------
# TestDefaults -- default variable values
# ---------------------------------------------------------------------------
class TestDefaults:
    """Verify cfk_topic default variables and their values."""

    def test_namespace_default(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cfk_topic_namespace'] == 'confluent'

    def test_kafka_cluster_name_default(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cfk_kafka_cluster_name'] == 'kafka'

    def test_replication_factor_default(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cfk_replication_factor'] == 3

    def test_topics_dir_defined(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cfk_topics_dir' in data
        assert data['cfk_topics_dir'] == ''

    def test_topics_list_defined(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert 'cfk_topics' in data
        assert data['cfk_topics'] == []

    def test_api_version_default(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cfk_topic_api_version'] == 'platform.confluent.io/v1beta1'


# ---------------------------------------------------------------------------
# TestMetaInfo -- Galaxy metadata
# ---------------------------------------------------------------------------
class TestMetaInfo:
    """Verify cfk_topic Galaxy metadata."""

    def test_role_name(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['galaxy_info']['role_name'] == 'cfk_topic'

    def test_min_ansible_version(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['galaxy_info']['min_ansible_version'] == '2.15'

    def test_no_dependencies(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['dependencies'] == []


# ---------------------------------------------------------------------------
# TestGovernanceWiring -- governance filter and constant usage
# ---------------------------------------------------------------------------
class TestGovernanceWiring:
    """Verify governance filters are wired in validate.yml."""

    def test_uses_fsi_validate_topic_name(self):
        text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'fsi_validate_topic_name' in text

    def test_uses_fsi_sla_lookup(self):
        text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'fsi_sla_lookup' in text

    def test_extracts_sla_tier_label(self):
        text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'fsi.sla-tier' in text

    def test_default_sla_tier_is_standard(self):
        text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert "default('standard')" in text


# ---------------------------------------------------------------------------
# TestCRDGeneration -- KafkaTopic CRD generation patterns
# ---------------------------------------------------------------------------
class TestCRDGeneration:
    """Verify KafkaTopic CRD generation patterns in generate.yml."""

    def test_uses_k8s_module(self):
        text = _read_text(os.path.join(TASKS_DIR, 'generate.yml'))
        assert 'kubernetes.core.k8s:' in text

    def test_generates_kafka_topic_kind(self):
        text = _read_text(os.path.join(TASKS_DIR, 'generate.yml'))
        assert 'kind: KafkaTopic' in text

    def test_includes_kafka_cluster_ref(self):
        text = _read_text(os.path.join(TASKS_DIR, 'generate.yml'))
        assert 'kafkaClusterRef' in text

    def test_injects_namespace(self):
        text = _read_text(os.path.join(TASKS_DIR, 'generate.yml'))
        assert 'cfk_topic_namespace' in text

    def test_string_typed_configs(self):
        """CFK requires string-typed config values -- verify | string filter usage."""
        text = _read_text(os.path.join(TASKS_DIR, 'generate.yml'))
        string_filter_count = text.count('| string')
        # retention.ms, min.insync.replicas, cleanup.policy must all be string-typed
        assert string_filter_count >= 2, (
            f"Expected at least 2 '| string' filters, found {string_filter_count}"
        )

    def test_uses_cfk_api_version(self):
        text = _read_text(os.path.join(TASKS_DIR, 'generate.yml'))
        assert 'cfk_topic_api_version' in text

    def test_no_hardcoded_partition_counts(self):
        """Config values must come from variables, not hardcoded numbers."""
        text = _read_text(os.path.join(TASKS_DIR, 'generate.yml'))
        # partitionCount should reference a variable, not a literal number
        assert 'partitionCount: 12' not in text
        assert 'partitionCount: 6' not in text
        assert 'partitionCount: 3' not in text

    def test_no_hardcoded_retention(self):
        """Retention must come from SLA tier lookup, not hardcoded."""
        text = _read_text(os.path.join(TASKS_DIR, 'generate.yml'))
        assert '604800000' not in text
        assert '259200000' not in text


# ---------------------------------------------------------------------------
# TestGovernanceParity -- cp_topic vs cfk_topic governance equivalence
# ---------------------------------------------------------------------------
class TestGovernanceParity:
    """Verify cfk_topic and cp_topic use identical governance filters."""

    def test_both_use_fsi_validate_topic_name(self):
        cp_text = _read_text(os.path.join(CP_TOPIC_TASKS, 'validate.yml'))
        cfk_text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'fsi_validate_topic_name' in cp_text
        assert 'fsi_validate_topic_name' in cfk_text

    def test_both_use_fsi_sla_lookup(self):
        cp_text = _read_text(os.path.join(CP_TOPIC_TASKS, 'validate.yml'))
        cfk_text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'fsi_sla_lookup' in cp_text
        assert 'fsi_sla_lookup' in cfk_text

    def test_both_extract_sla_tier_label(self):
        cp_text = _read_text(os.path.join(CP_TOPIC_TASKS, 'validate.yml'))
        cfk_text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'fsi.sla-tier' in cp_text
        assert 'fsi.sla-tier' in cfk_text

    def test_both_reference_sla_tiers_for_min_isr(self):
        cp_text = _read_text(os.path.join(CP_TOPIC_TASKS, 'validate.yml'))
        cfk_text = _read_text(os.path.join(TASKS_DIR, 'validate.yml'))
        assert 'sla_tiers[_topic_sla_tier].min_insync_replicas' in cp_text
        assert 'sla_tiers[_topic_sla_tier].min_insync_replicas' in cfk_text

    def test_both_load_governance_vars(self):
        cp_main = _read_text(os.path.join(CP_TOPIC_TASKS, 'main.yml'))
        cfk_main = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'sla_tiers.yml' in cp_main
        assert 'sla_tiers.yml' in cfk_main
        assert 'naming_rules.yml' in cp_main
        assert 'naming_rules.yml' in cfk_main


# ---------------------------------------------------------------------------
# TestGovernanceVarsLoaded -- main.yml loads governance vars
# ---------------------------------------------------------------------------
class TestGovernanceVarsLoaded:
    """Verify main.yml loads shared governance constants."""

    def test_loads_sla_tiers(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'sla_tiers.yml' in text

    def test_loads_naming_rules(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'naming_rules.yml' in text


# ---------------------------------------------------------------------------
# TestCheckModeTasks -- check mode implementation
# ---------------------------------------------------------------------------
class TestCheckModeTasks:
    """Verify check mode tasks query without mutation."""

    def test_check_uses_k8s_info(self):
        text = _read_text(os.path.join(TASKS_DIR, 'check.yml'))
        assert 'kubernetes.core.k8s_info:' in text

    def test_check_uses_changed_when(self):
        text = _read_text(os.path.join(TASKS_DIR, 'check.yml'))
        assert 'changed_when' in text

    def test_main_routes_to_check_mode(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'ansible_check_mode' in text


# ---------------------------------------------------------------------------
# TestFQCNCompliance -- fully qualified collection name enforcement
# ---------------------------------------------------------------------------
class TestFQCNCompliance:
    """Verify all task files use FQCN for every module reference."""

    BARE_MODULES = [
        'uri:', 'set_fact:', 'debug:', 'assert:', 'fail:',
        'include_tasks:', 'find:', 'slurp:', 'include_vars:',
        'include_role:', 'shell:', 'wait_for:'
    ]

    def test_all_tasks_use_fqcn(self):
        task_files = ['main.yml', 'validate.yml', 'generate.yml',
                      'check.yml', 'process_one.yml']
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
                            f"Bare module '{bare}' found in {fname} line {i + 1}: "
                            f"'{stripped}'. Use ansible.builtin.{bare[:-1]} instead."
                        )


# ---------------------------------------------------------------------------
# TestTaskNameCasing -- task names start with uppercase
# ---------------------------------------------------------------------------
class TestTaskNameCasing:
    """Verify all task names start with an uppercase letter."""

    def test_task_names_uppercase(self):
        task_files = ['main.yml', 'validate.yml', 'generate.yml',
                      'check.yml', 'process_one.yml']
        for fname in task_files:
            path = os.path.join(TASKS_DIR, fname)
            if not os.path.isfile(path):
                continue
            data = _load_yaml(path)
            if not isinstance(data, list):
                continue
            for task in data:
                if isinstance(task, dict) and 'name' in task:
                    name = task['name']
                    # Task names may contain Jinja -- check the first
                    # non-whitespace, non-quote character
                    first_char = name.lstrip().lstrip('"').lstrip("'")[0]
                    assert first_char.isupper() or first_char == '{', (
                        f"Task name in {fname} does not start with uppercase: '{name}'"
                    )


# ---------------------------------------------------------------------------
# TestMolecule -- molecule scenario configuration
# ---------------------------------------------------------------------------
class TestMolecule:
    """Verify molecule scenario configuration."""

    def test_uses_delegated_driver(self):
        data = _load_yaml(os.path.join(MOLECULE_DIR, 'molecule.yml'))
        assert data['driver']['name'] == 'delegated'

    def test_converge_includes_role(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'converge.yml'))
        assert 'cfk_topic' in text

    def test_verify_exists(self):
        assert os.path.isfile(os.path.join(MOLECULE_DIR, 'verify.yml'))
