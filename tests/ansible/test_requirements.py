"""
Tests for ansible/requirements.yml collection dependencies.

Validates that required Ansible collections are present and pinned correctly.
"""
import os

import pytest
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load_yaml(relpath):
    """Load a YAML file relative to the repo root."""
    with open(os.path.join(REPO_ROOT, relpath)) as f:
        return yaml.safe_load(f)


class TestRequirements:
    """Verify ansible/requirements.yml is valid and contains required collections."""

    @pytest.fixture(autouse=True)
    def setup(self):
        self.reqs = load_yaml('ansible/requirements.yml')

    def _find_collection(self, name):
        """Find a collection entry by name."""
        for entry in self.reqs.get('collections', []):
            if entry.get('name') == name:
                return entry
        return None

    def test_requirements_yaml_valid(self):
        assert 'collections' in self.reqs
        assert isinstance(self.reqs['collections'], list)
        assert len(self.reqs['collections']) > 0

    def test_cp_ansible_pinned(self):
        entry = self._find_collection('confluent.platform')
        assert entry is not None, "confluent.platform not found in requirements.yml"
        assert entry['version'] == '7.7.8', \
            f"Expected confluent.platform version 7.7.8, got {entry['version']}"

    def test_community_general_present(self):
        entry = self._find_collection('community.general')
        assert entry is not None, "community.general not found in requirements.yml"

    def test_ansible_posix_present(self):
        entry = self._find_collection('ansible.posix')
        assert entry is not None, "ansible.posix not found in requirements.yml"

    def test_ansible_utils_present(self):
        entry = self._find_collection('ansible.utils')
        assert entry is not None, "ansible.utils not found in requirements.yml"
