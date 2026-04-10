"""
Unit tests for the cfk_operator Ansible role.

Tests cover role structure, default variables, meta information, task files
for deploy (Helm install), apply_crs (readiness gates), check mode
(k8s_info audit), molecule scenario configuration, FQCN enforcement, and
task name casing.
"""
import os
import re

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROLE_DIR = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cfk_operator')
TASKS_DIR = os.path.join(ROLE_DIR, 'tasks')
MOLECULE_DIR = os.path.join(ROLE_DIR, 'molecule', 'default')


def _load_yaml(path):
    """Load and parse a YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def _read_text(path):
    """Read file as raw text."""
    with open(path) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestRoleStructure -- cfk_operator role files exist
# ---------------------------------------------------------------------------
class TestRoleStructure:
    """Verify cfk_operator role directory structure has all required files."""

    REQUIRED_FILES = [
        'defaults/main.yml',
        'meta/main.yml',
        'tasks/main.yml',
        'tasks/deploy.yml',
        'tasks/apply_crs.yml',
        'tasks/check.yml',
        'molecule/default/molecule.yml',
        'molecule/default/converge.yml',
        'molecule/default/verify.yml',
    ]

    def test_all_required_files_exist(self):
        for rel in self.REQUIRED_FILES:
            path = os.path.join(ROLE_DIR, rel)
            assert os.path.isfile(path), f"Missing required file: {rel}"


# ---------------------------------------------------------------------------
# TestDefaults -- cfk_operator default variables
# ---------------------------------------------------------------------------
class TestDefaults:
    """Verify cfk_operator defaults contain correct values."""

    DATA = None

    @classmethod
    def _data(cls):
        if cls.DATA is None:
            cls.DATA = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        return cls.DATA

    def test_helm_repo_url(self):
        assert self._data()['cfk_helm_repo_url'] == 'https://packages.confluent.io/helm'

    def test_helm_chart_ref(self):
        assert self._data()['cfk_helm_chart_ref'] == 'confluentinc/confluent-for-kubernetes'

    def test_namespace(self):
        assert self._data()['cfk_namespace'] == 'confluent'

    def test_readiness_retries_min(self):
        val = self._data()['cfk_readiness_retries']
        assert isinstance(val, int), "cfk_readiness_retries must be int"
        assert val >= 10, "cfk_readiness_retries must be >= 10"

    def test_readiness_delay_min(self):
        val = self._data()['cfk_readiness_delay']
        assert isinstance(val, int), "cfk_readiness_delay must be int"
        assert val >= 10, "cfk_readiness_delay must be >= 10"

    def test_expected_status_phase(self):
        assert self._data()['cfk_expected_status_phase'] == 'RUNNING'


# ---------------------------------------------------------------------------
# TestMetaInfo -- cfk_operator galaxy metadata
# ---------------------------------------------------------------------------
class TestMetaInfo:
    """Verify cfk_operator meta/main.yml galaxy info."""

    DATA = None

    @classmethod
    def _data(cls):
        if cls.DATA is None:
            cls.DATA = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        return cls.DATA

    def test_role_name(self):
        assert self._data()['galaxy_info']['role_name'] == 'cfk_operator'

    def test_min_ansible_version(self):
        assert self._data()['galaxy_info']['min_ansible_version'] == '2.15'

    def test_no_dependencies(self):
        assert self._data()['dependencies'] == [], (
            "cfk_operator must have no role dependencies"
        )


# ---------------------------------------------------------------------------
# TestDeployTasks -- deploy.yml Helm-based operator install
# ---------------------------------------------------------------------------
class TestDeployTasks:
    """Verify deploy.yml uses kubernetes.core.helm for CFK operator."""

    TEXT = None

    @classmethod
    def _text(cls):
        if cls.TEXT is None:
            cls.TEXT = _read_text(os.path.join(TASKS_DIR, 'deploy.yml'))
        return cls.TEXT

    def test_uses_helm_repository(self):
        assert 'kubernetes.core.helm_repository:' in self._text(), (
            "deploy.yml must use kubernetes.core.helm_repository"
        )

    def test_uses_helm(self):
        assert 'kubernetes.core.helm:' in self._text(), (
            "deploy.yml must use kubernetes.core.helm"
        )

    def test_references_chart_ref(self):
        assert 'cfk_helm_chart_ref' in self._text(), (
            "deploy.yml must reference cfk_helm_chart_ref variable"
        )

    def test_create_namespace(self):
        assert 'create_namespace: true' in self._text(), (
            "deploy.yml must set create_namespace: true"
        )

    def test_wait_enabled(self):
        assert 'wait: true' in self._text(), (
            "deploy.yml must set wait: true for operator readiness"
        )


# ---------------------------------------------------------------------------
# TestApplyCRsTasks -- apply_crs.yml CR application with readiness gates
# ---------------------------------------------------------------------------
class TestApplyCRsTasks:
    """Verify apply_crs.yml applies CRs and polls for readiness."""

    TEXT = None

    @classmethod
    def _text(cls):
        if cls.TEXT is None:
            cls.TEXT = _read_text(os.path.join(TASKS_DIR, 'apply_crs.yml'))
        return cls.TEXT

    def test_uses_k8s_module(self):
        assert 'kubernetes.core.k8s:' in self._text(), (
            "apply_crs.yml must use kubernetes.core.k8s for CR application"
        )

    def test_uses_k8s_info(self):
        assert 'kubernetes.core.k8s_info:' in self._text(), (
            "apply_crs.yml must use kubernetes.core.k8s_info for readiness polling"
        )

    def test_cfk_api_version(self):
        assert 'platform.confluent.io/v1beta1' in self._text(), (
            "apply_crs.yml must reference CFK API version"
        )

    def test_until_loop(self):
        assert 'until:' in self._text(), (
            "apply_crs.yml must use until: for readiness retry loop"
        )

    def test_retries(self):
        assert 'retries:' in self._text(), (
            "apply_crs.yml must configure retries for readiness polling"
        )

    def test_delay(self):
        assert 'delay:' in self._text(), (
            "apply_crs.yml must configure delay between readiness polls"
        )

    def test_kafka_kind(self):
        assert 'kind: Kafka' in self._text(), (
            "apply_crs.yml must handle Kafka CR kind"
        )

    def test_schema_registry_kind(self):
        assert 'kind: SchemaRegistry' in self._text(), (
            "apply_crs.yml must handle SchemaRegistry CR kind"
        )

    def test_connect_kind(self):
        assert 'kind: Connect' in self._text(), (
            "apply_crs.yml must handle Connect CR kind"
        )


# ---------------------------------------------------------------------------
# TestCheckModeTasks -- check.yml read-only audit
# ---------------------------------------------------------------------------
class TestCheckModeTasks:
    """Verify check.yml queries state without mutations."""

    TEXT = None

    @classmethod
    def _text(cls):
        if cls.TEXT is None:
            cls.TEXT = _read_text(os.path.join(TASKS_DIR, 'check.yml'))
        return cls.TEXT

    def test_uses_helm_info(self):
        assert 'kubernetes.core.helm_info:' in self._text(), (
            "check.yml must use kubernetes.core.helm_info for Helm status query"
        )

    def test_uses_k8s_info(self):
        assert 'kubernetes.core.k8s_info:' in self._text(), (
            "check.yml must use kubernetes.core.k8s_info for CR status query"
        )

    def test_no_helm_install(self):
        assert 'kubernetes.core.helm:' not in self._text(), (
            "check.yml must NOT use kubernetes.core.helm (no mutations)"
        )

    def test_no_k8s_apply(self):
        assert 'kubernetes.core.k8s:' not in self._text(), (
            "check.yml must NOT use kubernetes.core.k8s (no mutations)"
        )

    def test_changed_when_false(self):
        assert 'changed_when: false' in self._text(), (
            "check.yml must use changed_when: false on all queries"
        )


# ---------------------------------------------------------------------------
# TestFQCNCompliance -- FQCN enforcement across all task files
# ---------------------------------------------------------------------------
class TestFQCNCompliance:
    """Verify all task files use FQCN for every module reference."""

    BARE_MODULES = [
        'set_fact:', 'debug:', 'assert:', 'fail:',
        'include_tasks:', 'include_role:', 'include_vars:',
        'shell:', 'command:', 'wait_for:',
    ]

    def test_all_tasks_use_fqcn(self):
        task_files = ['main.yml', 'deploy.yml', 'apply_crs.yml', 'check.yml']
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
                            f"Use FQCN (e.g., ansible.builtin.{bare[:-1]}) instead."
                        )


# ---------------------------------------------------------------------------
# TestTaskNameCasing -- task name casing per ansible-lint name[casing]
# ---------------------------------------------------------------------------
class TestTaskNameCasing:
    """Verify all task names start with uppercase per ansible-lint."""

    def test_all_task_names_uppercase(self):
        task_files = ['main.yml', 'deploy.yml', 'apply_crs.yml', 'check.yml']
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


# ---------------------------------------------------------------------------
# TestMolecule -- molecule scenario configuration
# ---------------------------------------------------------------------------
class TestMolecule:
    """Verify molecule scenario for cfk_operator role."""

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

    def test_converge_includes_cfk_operator(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'converge.yml'))
        assert 'cfk_operator' in text, (
            "converge.yml must include cfk_operator role"
        )

    def test_verify_checks_defaults(self):
        text = _read_text(os.path.join(MOLECULE_DIR, 'verify.yml'))
        assert 'cfk_helm_chart_ref' in text or 'cfk_namespace' in text, (
            "verify.yml must validate role defaults"
        )
