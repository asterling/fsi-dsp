"""
Unit tests for the cp_observability Ansible role.

Tests validate role structure, default variables, JMX exporter task wiring,
Prometheus scrape target generation, Grafana dashboard import, alert rule
deployment, molecule configuration, requirements.yml updates, and FQCN
enforcement.
"""
import os

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROLE_DIR = os.path.join(REPO_ROOT, 'ansible', 'roles', 'cp_observability')
TASKS_DIR = os.path.join(ROLE_DIR, 'tasks')
TEMPLATES_DIR = os.path.join(ROLE_DIR, 'templates')
MOLECULE_DIR = os.path.join(ROLE_DIR, 'molecule', 'default')
OBS_GRAFANA_DIR = os.path.join(REPO_ROOT, 'observability', 'grafana')


def _load_yaml(path):
    """Load and parse a YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def _read_text(path):
    """Read file as raw text."""
    with open(path) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestRoleStructure -- role files and default variables
# ---------------------------------------------------------------------------
class TestRoleStructure:
    """Verify cp_observability role directory structure and defaults."""

    def test_defaults_exist(self):
        path = os.path.join(ROLE_DIR, 'defaults', 'main.yml')
        assert os.path.isfile(path)
        data = _load_yaml(path)
        assert data is not None

    def test_meta_exist(self):
        path = os.path.join(ROLE_DIR, 'meta', 'main.yml')
        assert os.path.isfile(path)
        data = _load_yaml(path)
        assert data['galaxy_info']['role_name'] == 'cp_observability'

    def test_meta_no_dependencies(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'meta', 'main.yml'))
        assert data['dependencies'] == []

    def test_defaults_jmx_ports(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cp_obs_broker_jmx_port'] == 8080
        assert data['cp_obs_sr_jmx_port'] == 8078
        assert data['cp_obs_connect_jmx_port'] == 8077
        assert data['cp_obs_zk_jmx_port'] == 8079

    def test_defaults_directories(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cp_obs_jmx_exporter_config_dir'] == '/opt/prometheus/jmx-exporter'
        assert data['cp_obs_prometheus_targets_dir'] == '/etc/prometheus/file_sd'

    def test_defaults_grafana(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cp_obs_grafana_url'] == 'http://localhost:3000'
        assert data['cp_obs_grafana_method'] == 'file_provisioning'
        assert data['cp_obs_grafana_provisioning_dir'] == '/etc/grafana/provisioning/dashboards'
        assert data['cp_obs_grafana_alert_provisioning_dir'] == '/etc/grafana/provisioning/alerting'

    def test_defaults_cluster_info(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cp_obs_cluster_name'] == 'fsi-kafka'
        assert data['cp_obs_environment'] == 'prod'

    def test_defaults_deploy_flags(self):
        data = _load_yaml(os.path.join(ROLE_DIR, 'defaults', 'main.yml'))
        assert data['cp_obs_deploy_jmx'] is True
        assert data['cp_obs_deploy_prometheus'] is True
        assert data['cp_obs_deploy_grafana'] is True
        assert data['cp_obs_deploy_alerts'] is True

    def test_task_files_exist(self):
        expected = ['main.yml', 'jmx_exporter.yml', 'prometheus.yml',
                    'grafana.yml', 'check.yml']
        for fname in expected:
            path = os.path.join(TASKS_DIR, fname)
            assert os.path.isfile(path), f"Missing task file: {fname}"


# ---------------------------------------------------------------------------
# TestJmxExporter -- JMX exporter task wiring
# ---------------------------------------------------------------------------
class TestJmxExporter:
    """Verify jmx_exporter.yml uses templates for each CP component."""

    def test_uses_ansible_builtin_template(self):
        text = _read_text(os.path.join(TASKS_DIR, 'jmx_exporter.yml'))
        assert 'ansible.builtin.template' in text

    def test_references_broker_template(self):
        text = _read_text(os.path.join(TASKS_DIR, 'jmx_exporter.yml'))
        assert 'jmx_exporter_broker.yml.j2' in text

    def test_references_connect_template(self):
        text = _read_text(os.path.join(TASKS_DIR, 'jmx_exporter.yml'))
        assert 'jmx_exporter_connect.yml.j2' in text

    def test_references_sr_template(self):
        text = _read_text(os.path.join(TASKS_DIR, 'jmx_exporter.yml'))
        assert 'jmx_exporter_schema_registry.yml.j2' in text

    def test_targets_config_dir(self):
        text = _read_text(os.path.join(TASKS_DIR, 'jmx_exporter.yml'))
        assert 'cp_obs_jmx_exporter_config_dir' in text

    def test_template_files_exist(self):
        expected = ['jmx_exporter_broker.yml.j2',
                    'jmx_exporter_connect.yml.j2',
                    'jmx_exporter_schema_registry.yml.j2']
        for fname in expected:
            path = os.path.join(TEMPLATES_DIR, fname)
            assert os.path.isfile(path), f"Missing template: {fname}"

    def test_broker_template_port(self):
        text = _read_text(os.path.join(TEMPLATES_DIR, 'jmx_exporter_broker.yml.j2'))
        assert 'cp_obs_broker_jmx_port' in text

    def test_connect_template_port(self):
        text = _read_text(os.path.join(TEMPLATES_DIR, 'jmx_exporter_connect.yml.j2'))
        assert 'cp_obs_connect_jmx_port' in text

    def test_sr_template_port(self):
        text = _read_text(os.path.join(TEMPLATES_DIR, 'jmx_exporter_schema_registry.yml.j2'))
        assert 'cp_obs_sr_jmx_port' in text


# ---------------------------------------------------------------------------
# TestPrometheusScrapeGen -- Prometheus scrape target generation
# ---------------------------------------------------------------------------
class TestPrometheusScrapeGen:
    """Verify prometheus.yml uses templates for file_sd_configs generation."""

    def test_uses_ansible_builtin_template(self):
        text = _read_text(os.path.join(TASKS_DIR, 'prometheus.yml'))
        assert 'ansible.builtin.template' in text

    def test_references_prometheus_template(self):
        text = _read_text(os.path.join(TASKS_DIR, 'prometheus.yml'))
        assert 'prometheus_targets.json.j2' in text

    def test_template_exists(self):
        path = os.path.join(TEMPLATES_DIR, 'prometheus_targets.json.j2')
        assert os.path.isfile(path)

    def test_template_references_kafka_broker(self):
        text = _read_text(os.path.join(TEMPLATES_DIR, 'prometheus_targets.json.j2'))
        assert 'kafka_broker' in text

    def test_template_references_schema_registry(self):
        text = _read_text(os.path.join(TEMPLATES_DIR, 'prometheus_targets.json.j2'))
        assert 'schema_registry' in text

    def test_template_references_kafka_connect(self):
        text = _read_text(os.path.join(TEMPLATES_DIR, 'prometheus_targets.json.j2'))
        assert 'kafka_connect' in text

    def test_template_references_port_variables(self):
        text = _read_text(os.path.join(TEMPLATES_DIR, 'prometheus_targets.json.j2'))
        assert 'cp_obs_broker_jmx_port' in text
        assert 'cp_obs_sr_jmx_port' in text
        assert 'cp_obs_connect_jmx_port' in text

    def test_template_contains_file_sd_structure(self):
        """Template should generate valid file_sd_configs JSON structure."""
        text = _read_text(os.path.join(TEMPLATES_DIR, 'prometheus_targets.json.j2'))
        assert 'targets' in text
        assert 'labels' in text


# ---------------------------------------------------------------------------
# TestGrafanaDashboards -- Grafana dashboard import tasks
# ---------------------------------------------------------------------------
class TestGrafanaDashboards:
    """Verify grafana.yml has tasks for dashboard import with dual-method support."""

    def test_references_dashboards(self):
        text = _read_text(os.path.join(TASKS_DIR, 'grafana.yml'))
        assert 'dashboard' in text.lower()

    def test_supports_file_provisioning(self):
        text = _read_text(os.path.join(TASKS_DIR, 'grafana.yml'))
        assert 'file_provisioning' in text

    def test_supports_api_method(self):
        text = _read_text(os.path.join(TASKS_DIR, 'grafana.yml'))
        assert 'api' in text

    def test_cp_obs_grafana_method_conditional(self):
        text = _read_text(os.path.join(TASKS_DIR, 'grafana.yml'))
        assert 'cp_obs_grafana_method' in text

    def test_references_dashboard_json_files(self):
        text = _read_text(os.path.join(TASKS_DIR, 'grafana.yml'))
        assert 'dashboard' in text and 'json' in text


# ---------------------------------------------------------------------------
# TestAlertRules -- alert rule deployment
# ---------------------------------------------------------------------------
class TestAlertRules:
    """Verify grafana.yml includes alert rule deployment from alerts.yaml."""

    def test_alert_task_exists(self):
        text = _read_text(os.path.join(TASKS_DIR, 'grafana.yml'))
        assert 'alert' in text.lower()

    def test_references_alerts_yaml(self):
        text = _read_text(os.path.join(TASKS_DIR, 'grafana.yml'))
        assert 'alerts' in text

    def test_alert_provisioning_dir(self):
        text = _read_text(os.path.join(TASKS_DIR, 'grafana.yml'))
        assert 'cp_obs_grafana_alert_provisioning_dir' in text


# ---------------------------------------------------------------------------
# TestMainDispatch -- main.yml dispatch logic
# ---------------------------------------------------------------------------
class TestMainDispatch:
    """Verify main.yml dispatches to sub-task files based on deploy flags."""

    def test_dispatches_to_jmx(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'jmx_exporter.yml' in text

    def test_dispatches_to_prometheus(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'prometheus.yml' in text

    def test_dispatches_to_grafana(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'grafana.yml' in text

    def test_uses_deploy_jmx_flag(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'cp_obs_deploy_jmx' in text

    def test_uses_deploy_prometheus_flag(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'cp_obs_deploy_prometheus' in text

    def test_uses_deploy_grafana_flag(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'cp_obs_deploy_grafana' in text or 'cp_obs_deploy_alerts' in text

    def test_sets_results_fact(self):
        text = _read_text(os.path.join(TASKS_DIR, 'main.yml'))
        assert 'cp_observability_results' in text


# ---------------------------------------------------------------------------
# TestObservabilityMolecule -- molecule scenario files
# ---------------------------------------------------------------------------
class TestObservabilityMolecule:
    """Verify molecule/default/ has all required files."""

    def test_molecule_yml_exists(self):
        assert os.path.isfile(os.path.join(MOLECULE_DIR, 'molecule.yml'))

    def test_converge_yml_exists(self):
        assert os.path.isfile(os.path.join(MOLECULE_DIR, 'converge.yml'))

    def test_verify_yml_exists(self):
        assert os.path.isfile(os.path.join(MOLECULE_DIR, 'verify.yml'))

    def test_molecule_uses_delegated_driver(self):
        data = _load_yaml(os.path.join(MOLECULE_DIR, 'molecule.yml'))
        assert data['driver']['name'] == 'delegated'


# ---------------------------------------------------------------------------
# TestRequirementsYml -- community.grafana collection in requirements
# ---------------------------------------------------------------------------
class TestRequirementsYml:
    """Verify ansible/requirements.yml includes community.grafana collection."""

    def test_community_grafana_present(self):
        data = _load_yaml(os.path.join(REPO_ROOT, 'ansible', 'requirements.yml'))
        collection_names = [c['name'] for c in data['collections']]
        assert 'community.grafana' in collection_names


# ---------------------------------------------------------------------------
# TestFQCN -- fully qualified collection name enforcement
# ---------------------------------------------------------------------------
class TestFQCN:
    """Verify all task files use FQCN for every module reference."""

    # Bare module names that should never appear as top-level task action keys.
    # Excludes 'file:' and 'stat:' because they also appear as parameter keys
    # (e.g., ansible.builtin.include_tasks file: X).
    BARE_MODULES = [
        'uri:', 'set_fact:', 'debug:', 'assert:', 'fail:',
        'include_tasks:', 'find:', 'slurp:', 'include_vars:',
        'include_role:', 'shell:', 'wait_for:', 'template:',
        'copy:'
    ]

    def test_all_tasks_use_fqcn(self):
        """Check that no bare module names appear as task-level action keys."""
        task_files = ['main.yml', 'jmx_exporter.yml', 'prometheus.yml',
                      'grafana.yml', 'check.yml']
        for fname in task_files:
            path = os.path.join(TASKS_DIR, fname)
            if not os.path.isfile(path):
                continue
            data = _load_yaml(path)
            if not isinstance(data, list):
                continue
            for task in data:
                if not isinstance(task, dict):
                    continue
                for bare in self.BARE_MODULES:
                    key = bare.rstrip(':')
                    if key in task:
                        assert False, (
                            f"Bare module '{key}' found as task action in {fname}. "
                            f"Use ansible.builtin.{key} instead."
                        )


# ---------------------------------------------------------------------------
# TestTaskNaming -- task names start with uppercase
# ---------------------------------------------------------------------------
class TestTaskNaming:
    """Verify all task names start with uppercase per ansible-lint name[casing]."""

    def test_task_names_uppercase(self):
        task_files = ['main.yml', 'jmx_exporter.yml', 'prometheus.yml',
                      'grafana.yml', 'check.yml']
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
                    if isinstance(name, str) and name:
                        assert name[0].isupper(), (
                            f"Task name in {fname} must start with uppercase: '{name}'"
                        )
