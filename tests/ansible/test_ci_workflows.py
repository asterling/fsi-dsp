"""
CI workflow structure tests for .github/workflows/ansible-ci.yml.

Validates that the Ansible CI workflow has correct trigger paths, lint jobs,
molecule test matrix covering all 5 governance roles, and governance parity
validation as a separate job.
"""
import os

import pytest
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORKFLOW_PATH = os.path.join(REPO_ROOT, '.github', 'workflows', 'ansible-ci.yml')

GOVERNANCE_ROLES = ['cp_topic', 'cp_schema', 'cp_rbac', 'cp_connect', 'cp_observability']


def load_workflow():
    """Load and parse the ansible-ci.yml workflow."""
    with open(WORKFLOW_PATH) as f:
        return yaml.safe_load(f)


class TestAnsibleLintWorkflow:
    """Validate lint job structure in ansible-ci.yml."""

    def test_workflow_exists(self):
        assert os.path.isfile(WORKFLOW_PATH), \
            f"Workflow file does not exist: {WORKFLOW_PATH}"

    def test_workflow_valid_yaml(self):
        with open(WORKFLOW_PATH) as f:
            data = yaml.safe_load(f)
        assert isinstance(data, dict), "Workflow must parse as a YAML mapping"

    def test_trigger_paths(self):
        wf = load_workflow()
        paths = wf['on']['pull_request']['paths']
        assert 'ansible/**' in paths, "Missing 'ansible/**' in trigger paths"
        assert 'tests/ansible/**' in paths, "Missing 'tests/ansible/**' in trigger paths"

    def test_lint_job_exists(self):
        wf = load_workflow()
        assert 'lint' in wf['jobs'], "Missing 'lint' job in workflow"

    def test_lint_runs_yamllint(self):
        wf = load_workflow()
        lint_steps = wf['jobs']['lint']['steps']
        step_runs = [s.get('run', '') for s in lint_steps if 'run' in s]
        yamllint_found = any('yamllint' in run for run in step_runs)
        assert yamllint_found, "lint job must run yamllint"

    def test_lint_runs_ansible_lint(self):
        wf = load_workflow()
        lint_steps = wf['jobs']['lint']['steps']
        step_runs = [s.get('run', '') for s in lint_steps if 'run' in s]
        ansible_lint_found = any(
            'ansible-lint' in run and '.ansible-lint' in run
            for run in step_runs
        )
        assert ansible_lint_found, \
            "lint job must run ansible-lint with config reference to .ansible-lint"

    def test_lint_installs_deps(self):
        wf = load_workflow()
        lint_steps = wf['jobs']['lint']['steps']
        step_runs = [s.get('run', '') for s in lint_steps if 'run' in s]
        install_run = ' '.join(step_runs)
        assert 'ansible-core' in install_run, "lint job must install ansible-core"
        assert 'ansible-lint' in install_run, "lint job must install ansible-lint"
        assert 'yamllint' in install_run, "lint job must install yamllint"


class TestMoleculeScenarios:
    """Validate molecule test matrix in ansible-ci.yml."""

    def test_molecule_job_exists(self):
        wf = load_workflow()
        assert 'molecule' in wf['jobs'], "Missing 'molecule' job in workflow"

    def test_molecule_matrix(self):
        wf = load_workflow()
        matrix_roles = wf['jobs']['molecule']['strategy']['matrix']['role']
        for role in GOVERNANCE_ROLES:
            assert role in matrix_roles, \
                f"Role '{role}' missing from molecule matrix"

    def test_molecule_installs_collections(self):
        wf = load_workflow()
        mol_steps = wf['jobs']['molecule']['steps']
        step_runs = [s.get('run', '') for s in mol_steps if 'run' in s]
        galaxy_found = any(
            'ansible-galaxy' in run and 'collection install' in run
            for run in step_runs
        )
        assert galaxy_found, "molecule job must run ansible-galaxy collection install"

    def test_molecule_working_directory(self):
        wf = load_workflow()
        mol_steps = wf['jobs']['molecule']['steps']
        mol_test_steps = [
            s for s in mol_steps
            if 'run' in s and 'molecule test' in s.get('run', '')
        ]
        assert len(mol_test_steps) > 0, "molecule job must have a 'molecule test' step"
        wd = mol_test_steps[0].get('working-directory', '')
        # The working directory should reference matrix.role
        assert 'matrix.role' in wd, \
            f"molecule test working-directory must reference matrix.role, got: {wd}"

    def test_all_roles_have_molecule(self):
        for role in GOVERNANCE_ROLES:
            mol_path = os.path.join(
                REPO_ROOT, 'ansible', 'roles', role, 'molecule', 'default', 'molecule.yml'
            )
            assert os.path.isfile(mol_path), \
                f"Role '{role}' missing molecule/default/molecule.yml at {mol_path}"


class TestParityValidation:
    """Validate governance parity job in ansible-ci.yml."""

    def test_parity_job_exists(self):
        wf = load_workflow()
        assert 'parity' in wf['jobs'], "Missing 'parity' job in workflow"

    def test_parity_runs_pytest(self):
        wf = load_workflow()
        parity_steps = wf['jobs']['parity']['steps']
        step_runs = [s.get('run', '') for s in parity_steps if 'run' in s]
        pytest_found = any(
            'pytest' in run and 'test_governance_parity' in run
            for run in step_runs
        )
        assert pytest_found, \
            "parity job must run pytest with test_governance_parity.py"
