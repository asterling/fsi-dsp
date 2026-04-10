"""
Unit tests for the DR drill playbook and compliance report template.

Tests cover playbook structure (multi-play, kafka_broker targeting), play
sequencing (pre-drill snapshot, failover, failback, report generation),
backend selection (cp_dr_mrc default, cp_dr_mm2 supported), timestamp
tracking across plays, compliance report template content (heading, drill ID,
verdict, step table, regulatory attestation, validation details), FQCN
enforcement, and task name conventions.
"""
import os
import re

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLAYBOOKS_DIR = os.path.join(REPO_ROOT, 'ansible', 'playbooks')
TEMPLATES_DIR = os.path.join(REPO_ROOT, 'ansible', 'templates')
DRILL_PLAYBOOK = os.path.join(PLAYBOOKS_DIR, 'dr-drill.yml')
REPORT_TEMPLATE = os.path.join(TEMPLATES_DIR, 'dr-drill-report.md.j2')


def _load_yaml(path):
    """Load and parse a YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def _read_text(path):
    """Read file as raw text."""
    with open(path) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestDrillPlaybookStructure -- dr-drill.yml exists and has correct shape
# ---------------------------------------------------------------------------
class TestDrillPlaybookStructure:
    """Verify dr-drill.yml playbook existence, validity, and multi-play structure."""

    def test_drill_playbook_exists(self):
        assert os.path.isfile(DRILL_PLAYBOOK), "ansible/playbooks/dr-drill.yml must exist"

    def test_drill_playbook_valid_yaml(self):
        data = _load_yaml(DRILL_PLAYBOOK)
        assert isinstance(data, list), "dr-drill.yml must be a list of plays"

    def test_drill_playbook_has_at_least_4_plays(self):
        data = _load_yaml(DRILL_PLAYBOOK)
        assert len(data) >= 4, (
            f"dr-drill.yml must have at least 4 plays, found {len(data)}"
        )

    def test_all_plays_target_kafka_broker(self):
        data = _load_yaml(DRILL_PLAYBOOK)
        for i, play in enumerate(data):
            hosts = play.get('hosts', '')
            assert 'kafka_broker' in hosts, (
                f"Play {i + 1} must target kafka_broker for variable "
                f"persistence, found hosts: '{hosts}'"
            )

    def test_first_play_gathers_facts(self):
        data = _load_yaml(DRILL_PLAYBOOK)
        first_play = data[0]
        assert first_play.get('gather_facts') is True, (
            "First play must have gather_facts: true"
        )


# ---------------------------------------------------------------------------
# TestDrillPlaybookPlays -- play content and sequencing
# ---------------------------------------------------------------------------
class TestDrillPlaybookPlays:
    """Verify play sequencing: pre-drill, failover, failback, report."""

    def test_pre_drill_sets_start_timestamp(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert '_drill_start' in text, (
            "First play must set _drill_start timestamp"
        )

    def test_pre_drill_sets_drill_steps(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert '_drill_steps' in text, (
            "First play must initialize _drill_steps list"
        )

    def test_pre_drill_sets_drill_id(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert '_drill_id' in text, (
            "First play must set _drill_id"
        )

    def test_failover_play_includes_role(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert 'include_role' in text, (
            "dr-drill.yml must include a role via include_role"
        )
        assert 'dr_drill_backend' in text, (
            "include_role must reference dr_drill_backend variable"
        )

    def test_failover_captures_results(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert '_failover_results' in text, (
            "Drill playbook must capture _failover_results from role output"
        )

    def test_failback_play_includes_role(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert 'failback' in text, (
            "dr-drill.yml must have a failback operation"
        )

    def test_failback_captures_results(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert '_failback_results' in text, (
            "Drill playbook must capture _failback_results from role output"
        )

    def test_report_play_uses_template(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert 'dr-drill-report.md.j2' in text, (
            "A play must render dr-drill-report.md.j2 template"
        )

    def test_report_output_includes_date(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert 'ansible_date_time' in text, (
            "Report output path must include ansible_date_time"
        )


# ---------------------------------------------------------------------------
# TestDrillBackend -- configurable DR backend selection
# ---------------------------------------------------------------------------
class TestDrillBackend:
    """Verify dr_drill_backend variable with default cp_dr_mrc."""

    def test_default_backend_is_cp_dr_mrc(self):
        text = _read_text(DRILL_PLAYBOOK)
        has_single = "default('cp_dr_mrc')" in text
        has_double = 'default("cp_dr_mrc")' in text
        assert has_single or has_double, (
            "dr-drill.yml must default dr_drill_backend to cp_dr_mrc"
        )

    def test_backend_variable_name(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert 'dr_drill_backend' in text, (
            "dr-drill.yml must reference dr_drill_backend variable"
        )


# ---------------------------------------------------------------------------
# TestDrillTimestamps -- step timestamps built across plays
# ---------------------------------------------------------------------------
class TestDrillTimestamps:
    """Verify drill steps track timestamps and build list across plays."""

    def test_step_timestamps_recorded(self):
        text = _read_text(DRILL_PLAYBOOK)
        assert '_drill_steps' in text, (
            "dr-drill.yml must build _drill_steps list across plays"
        )
        # Verify list concatenation pattern (append to list)
        has_concat = '+' in text or '_drill_steps |' in text or 'union' in text
        assert has_concat, (
            "dr-drill.yml must append to _drill_steps via list concatenation"
        )


# ---------------------------------------------------------------------------
# TestReportTemplate -- dr-drill-report.md.j2 content verification
# ---------------------------------------------------------------------------
class TestReportTemplate:
    """Verify compliance report Jinja2 template content."""

    def test_report_template_exists(self):
        assert os.path.isfile(REPORT_TEMPLATE), (
            "ansible/templates/dr-drill-report.md.j2 must exist"
        )

    def test_report_has_heading(self):
        text = _read_text(REPORT_TEMPLATE)
        assert 'DR Drill Compliance Report' in text

    def test_report_has_drill_id(self):
        text = _read_text(REPORT_TEMPLATE)
        assert '_drill_id' in text

    def test_report_has_verdict(self):
        text = _read_text(REPORT_TEMPLATE)
        assert 'PASS' in text
        assert 'FAIL' in text

    def test_report_has_steps_table(self):
        text = _read_text(REPORT_TEMPLATE)
        assert 'Step' in text
        assert 'Result' in text
        assert 'Duration' in text

    def test_report_has_attestation(self):
        text = _read_text(REPORT_TEMPLATE)
        assert 'Regulatory Attestation' in text

    def test_report_has_regulatory_reference(self):
        text = _read_text(REPORT_TEMPLATE)
        has_occ = 'OCC' in text
        has_fdic = 'FDIC' in text
        assert has_occ or has_fdic, (
            "Report template must reference OCC or FDIC"
        )

    def test_report_has_failover_details(self):
        text = _read_text(REPORT_TEMPLATE)
        has_post = 'Post-Failover' in text
        has_failover = 'Failover' in text
        assert has_post or has_failover, (
            "Report template must have failover validation details"
        )

    def test_report_has_failback_details(self):
        text = _read_text(REPORT_TEMPLATE)
        has_post = 'Post-Failback' in text
        has_failback = 'Failback' in text
        assert has_post or has_failback, (
            "Report template must have failback validation details"
        )

    def test_report_iterates_steps(self):
        text = _read_text(REPORT_TEMPLATE)
        has_for = 'for step in' in text
        has_steps = '_drill_steps' in text
        assert has_for or has_steps, (
            "Report template must iterate over _drill_steps"
        )

    def test_report_has_timestamp(self):
        text = _read_text(REPORT_TEMPLATE)
        assert 'ansible_date_time' in text, (
            "Report template must include ansible_date_time"
        )


# ---------------------------------------------------------------------------
# TestFQCN -- FQCN enforcement in dr-drill.yml
# ---------------------------------------------------------------------------
class TestFQCN:
    """Verify all tasks in dr-drill.yml use FQCN for module references."""

    BARE_MODULES = [
        'command:', 'uri:', 'set_fact:', 'debug:', 'assert:', 'fail:',
        'include_tasks:', 'include_role:', 'shell:', 'wait_for:',
        'include_vars:', 'pause:', 'template:'
    ]

    def test_all_tasks_use_fqcn(self):
        text = _read_text(DRILL_PLAYBOOK)
        lines = text.split('\n')
        for i, line in enumerate(lines):
            stripped = line.lstrip()
            if stripped.startswith('#') or not stripped:
                continue
            if stripped.startswith('- name:') or stripped.startswith('name:'):
                continue
            for bare in self.BARE_MODULES:
                if stripped.startswith(bare):
                    assert False, (
                        f"Bare module '{bare}' found in dr-drill.yml "
                        f"line {i + 1}: '{stripped}'. "
                        f"Use ansible.builtin.{bare[:-1]} instead."
                    )


# ---------------------------------------------------------------------------
# TestTaskNames -- task name conventions in dr-drill.yml
# ---------------------------------------------------------------------------
class TestTaskNames:
    """Verify all task names in dr-drill.yml start with uppercase."""

    def test_all_task_names_uppercase(self):
        data = _load_yaml(DRILL_PLAYBOOK)
        for play in data:
            tasks = play.get('tasks', [])
            for task in tasks:
                if isinstance(task, dict) and 'name' in task:
                    name = task['name']
                    if name.startswith('{{'):
                        continue
                    assert name[0].isupper(), (
                        f"Task name must start with uppercase: '{name}'"
                    )
