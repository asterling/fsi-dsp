"""
Unit tests for the orchestration playbooks (site.yml and deploy-governance.yml).

Tests validate the multi-play structure of site.yml, tag architecture for
selective execution, tag isolation to prevent import_playbook inheritance
leakage, and the governance-only deploy-governance.yml playbook.
"""
import os

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ANSIBLE_DIR = os.path.join(REPO_ROOT, 'ansible')


def _load_yaml(path):
    """Load and parse a YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def _load_yaml_all(path):
    """Load a multi-document YAML file (multiple plays)."""
    with open(path) as f:
        return list(yaml.safe_load_all(f))


def _read_text(path):
    """Read file as raw text."""
    with open(path) as f:
        return f.read()


# ---------------------------------------------------------------------------
# TestSiteYml -- structure and content of site.yml
# ---------------------------------------------------------------------------
class TestSiteYml:
    """Validate site.yml has 4 plays with correct hosts and tags."""

    SITE_PATH = os.path.join(ANSIBLE_DIR, 'site.yml')

    def test_site_yml_exists(self):
        assert os.path.isfile(self.SITE_PATH), "ansible/site.yml must exist"

    def test_site_yml_is_valid_yaml(self):
        data = _load_yaml_all(self.SITE_PATH)
        assert data is not None

    def test_site_yml_has_four_plays(self):
        data = _load_yaml_all(self.SITE_PATH)
        # Filter out None documents
        plays = [d for d in data if d is not None]
        # site.yml may use import_playbook which creates list-of-dicts
        # Flatten: each top-level list item is a play or import directive
        flat = []
        for item in plays:
            if isinstance(item, list):
                flat.extend(item)
            else:
                flat.append(item)
        assert len(flat) == 4, (
            f"Expected 4 plays in site.yml, found {len(flat)}"
        )

    def test_play1_imports_cluster_deploy(self):
        text = _read_text(self.SITE_PATH)
        assert 'import_playbook' in text, (
            "Play 1 must use import_playbook for cluster deploy"
        )

    def test_play1_has_cluster_tag(self):
        text = _read_text(self.SITE_PATH)
        assert 'cluster' in text, "Play 1 must have 'cluster' tag"

    def test_play2_targets_kafka_broker(self):
        text = _read_text(self.SITE_PATH)
        assert 'kafka_broker[0]' in text or 'kafka_broker' in text, (
            "Play 2 must target kafka_broker[0] for governance"
        )

    def test_play2_includes_governance_roles(self):
        text = _read_text(self.SITE_PATH)
        assert 'cp_topic' in text, "Play 2 must include cp_topic role"
        assert 'cp_schema' in text, "Play 2 must include cp_schema role"
        assert 'cp_rbac' in text, "Play 2 must include cp_rbac role"

    def test_play2_has_governance_tag(self):
        text = _read_text(self.SITE_PATH)
        assert 'governance' in text, "Play 2 must have 'governance' tag"

    def test_play3_targets_kafka_connect(self):
        text = _read_text(self.SITE_PATH)
        assert 'kafka_connect[0]' in text or 'kafka_connect' in text, (
            "Play 3 must target kafka_connect[0] for connectors"
        )

    def test_play3_includes_cp_connect(self):
        text = _read_text(self.SITE_PATH)
        assert 'cp_connect' in text, "Play 3 must include cp_connect role"

    def test_play3_has_connectors_tag(self):
        text = _read_text(self.SITE_PATH)
        assert 'connectors' in text, "Play 3 must have 'connectors' tag"

    def test_play4_targets_all_hosts(self):
        text = _read_text(self.SITE_PATH)
        # Play 4 should target 'all' hosts for observability
        assert 'all' in text, "Play 4 must target 'all' for observability"

    def test_play4_includes_cp_observability(self):
        text = _read_text(self.SITE_PATH)
        assert 'cp_observability' in text, (
            "Play 4 must include cp_observability role"
        )

    def test_play4_has_observability_tag(self):
        text = _read_text(self.SITE_PATH)
        assert 'observability' in text, "Play 4 must have 'observability' tag"

    def test_play3_waits_for_connect_port(self):
        text = _read_text(self.SITE_PATH)
        assert 'wait_for' in text or 'ansible.builtin.wait_for' in text, (
            "Play 3 must wait for Connect REST API port before deploying"
        )

    def test_all_module_refs_use_fqcn(self):
        """All module references in site.yml must use FQCN."""
        text = _read_text(self.SITE_PATH)
        bare_modules = [
            'include_role:', 'include_tasks:', 'wait_for:',
            'debug:', 'import_playbook:'
        ]
        for line in text.split('\n'):
            stripped = line.lstrip()
            if stripped.startswith('#') or not stripped:
                continue
            if stripped.startswith('- name:') or stripped.startswith('name:'):
                continue
            for bare in bare_modules:
                if stripped.startswith(bare):
                    assert False, (
                        f"Bare module '{bare}' in site.yml: '{stripped}'. "
                        f"Use ansible.builtin.{bare[:-1]} instead."
                    )

    def test_all_task_names_start_uppercase(self):
        """All task names must start with uppercase per ansible-lint."""
        data = _load_yaml_all(self.SITE_PATH)
        plays = [d for d in data if d is not None]
        flat = []
        for item in plays:
            if isinstance(item, list):
                flat.extend(item)
            else:
                flat.append(item)
        for play in flat:
            if not isinstance(play, dict):
                continue
            # Check play name
            if 'name' in play:
                name = play['name']
                assert name[0].isupper(), (
                    f"Play name must start with uppercase: '{name}'"
                )
            # Check tasks, pre_tasks, post_tasks
            for section in ['tasks', 'pre_tasks', 'post_tasks']:
                for task in play.get(section, []) or []:
                    if isinstance(task, dict) and 'name' in task:
                        name = task['name']
                        assert name[0].isupper(), (
                            f"Task name must start with uppercase: '{name}'"
                        )


# ---------------------------------------------------------------------------
# TestTagArchitecture -- tag hierarchy and structure
# ---------------------------------------------------------------------------
class TestTagArchitecture:
    """Validate tag architecture: each play has unique top-level tags."""

    SITE_PATH = os.path.join(ANSIBLE_DIR, 'site.yml')

    def _get_plays(self):
        data = _load_yaml_all(self.SITE_PATH)
        plays = [d for d in data if d is not None]
        flat = []
        for item in plays:
            if isinstance(item, list):
                flat.extend(item)
            else:
                flat.append(item)
        return flat

    def test_each_play_has_tags(self):
        """Every play must have a tags field."""
        plays = self._get_plays()
        for play in plays:
            if not isinstance(play, dict):
                continue
            assert 'tags' in play, (
                f"Play '{play.get('name', 'unknown')}' must have tags"
            )

    def test_governance_tasks_have_specific_tags(self):
        """Governance play tasks should have role-specific tags."""
        text = _read_text(self.SITE_PATH)
        assert 'topics' in text, "Governance play should tag topics"
        assert 'schemas' in text, "Governance play should tag schemas"
        assert 'rbac' in text, "Governance play should tag rbac"

    def test_cluster_tag_only_on_play1(self):
        """The 'cluster' tag must only appear on play 1 (import_playbook)."""
        plays = self._get_plays()
        cluster_plays = []
        for i, play in enumerate(plays):
            if not isinstance(play, dict):
                continue
            tags = play.get('tags', [])
            if isinstance(tags, str):
                tags = [tags]
            if 'cluster' in tags:
                cluster_plays.append(i)
        assert len(cluster_plays) == 1, (
            f"'cluster' tag should appear on exactly 1 play, "
            f"found on plays: {cluster_plays}"
        )
        assert cluster_plays[0] == 0, (
            "'cluster' tag must be on the first play"
        )


# ---------------------------------------------------------------------------
# TestTagIsolation -- disjoint tag sets between plays
# ---------------------------------------------------------------------------
class TestTagIsolation:
    """Verify top-level play tags are disjoint to prevent tag inheritance."""

    SITE_PATH = os.path.join(ANSIBLE_DIR, 'site.yml')

    def _get_play_tag_sets(self):
        """Return list of tag sets, one per play."""
        data = _load_yaml_all(self.SITE_PATH)
        plays = [d for d in data if d is not None]
        flat = []
        for item in plays:
            if isinstance(item, list):
                flat.extend(item)
            else:
                flat.append(item)
        tag_sets = []
        for play in flat:
            if not isinstance(play, dict):
                continue
            tags = play.get('tags', [])
            if isinstance(tags, str):
                tags = [tags]
            tag_sets.append(set(tags))
        return tag_sets

    def test_play_tags_are_disjoint(self):
        """Each play's top-level tags must not overlap with other plays."""
        tag_sets = self._get_play_tag_sets()
        for i in range(len(tag_sets)):
            for j in range(i + 1, len(tag_sets)):
                overlap = tag_sets[i] & tag_sets[j]
                assert not overlap, (
                    f"Plays {i + 1} and {j + 1} share tags: {overlap}. "
                    f"This causes import_playbook tag inheritance leakage."
                )

    def test_connectors_tag_exclusive_to_play3(self):
        """The 'connectors' tag must only be on play 3."""
        tag_sets = self._get_play_tag_sets()
        assert len(tag_sets) >= 3, "Need at least 3 plays"
        for i, tags in enumerate(tag_sets):
            if i == 2:  # Play 3 (0-indexed)
                assert 'connectors' in tags, (
                    "Play 3 must have 'connectors' tag"
                )
            else:
                assert 'connectors' not in tags, (
                    f"Play {i + 1} must NOT have 'connectors' tag "
                    f"(prevents tag inheritance leakage)"
                )

    def test_observability_tag_exclusive_to_play4(self):
        """The 'observability' tag must only be on play 4."""
        tag_sets = self._get_play_tag_sets()
        assert len(tag_sets) >= 4, "Need at least 4 plays"
        for i, tags in enumerate(tag_sets):
            if i == 3:  # Play 4 (0-indexed)
                assert 'observability' in tags, (
                    "Play 4 must have 'observability' tag"
                )
            else:
                assert 'observability' not in tags, (
                    f"Play {i + 1} must NOT have 'observability' tag"
                )


# ---------------------------------------------------------------------------
# TestDeployGovernance -- deploy-governance.yml structure
# ---------------------------------------------------------------------------
class TestDeployGovernance:
    """Validate deploy-governance.yml for Day-2 governance-only ops."""

    GOV_PATH = os.path.join(ANSIBLE_DIR, 'playbooks', 'deploy-governance.yml')

    def test_deploy_governance_exists(self):
        assert os.path.isfile(self.GOV_PATH), (
            "ansible/playbooks/deploy-governance.yml must exist"
        )

    def test_deploy_governance_is_valid_yaml(self):
        data = _load_yaml_all(self.GOV_PATH)
        assert data is not None

    def test_includes_governance_roles(self):
        text = _read_text(self.GOV_PATH)
        assert 'cp_topic' in text, "Must include cp_topic role"
        assert 'cp_schema' in text, "Must include cp_schema role"
        assert 'cp_rbac' in text, "Must include cp_rbac role"

    def test_includes_connect_role(self):
        text = _read_text(self.GOV_PATH)
        assert 'cp_connect' in text, (
            "deploy-governance.yml must include cp_connect role"
        )

    def test_no_cluster_deploy(self):
        text = _read_text(self.GOV_PATH)
        assert 'import_playbook' not in text or 'deploy-cp' not in text, (
            "deploy-governance.yml must NOT import cluster deployment"
        )

    def test_governance_play_targets_broker(self):
        text = _read_text(self.GOV_PATH)
        assert 'kafka_broker' in text, (
            "Governance play must target kafka_broker"
        )

    def test_connectors_play_targets_connect(self):
        text = _read_text(self.GOV_PATH)
        assert 'kafka_connect' in text, (
            "Connectors play must target kafka_connect"
        )

    def test_all_task_names_start_uppercase(self):
        """All task names must start with uppercase per ansible-lint."""
        data = _load_yaml_all(self.GOV_PATH)
        plays = [d for d in data if d is not None]
        flat = []
        for item in plays:
            if isinstance(item, list):
                flat.extend(item)
            else:
                flat.append(item)
        for play in flat:
            if not isinstance(play, dict):
                continue
            if 'name' in play:
                name = play['name']
                assert name[0].isupper(), (
                    f"Play name must start with uppercase: '{name}'"
                )
            for section in ['tasks', 'pre_tasks', 'post_tasks']:
                for task in play.get(section, []) or []:
                    if isinstance(task, dict) and 'name' in task:
                        name = task['name']
                        assert name[0].isupper(), (
                            f"Task name must start with uppercase: '{name}'"
                        )


# ---------------------------------------------------------------------------
# TestConnectorsExample -- connectors-example.yml structure
# ---------------------------------------------------------------------------
class TestConnectorsExample:
    """Validate connectors-example.yml variable file."""

    VARS_PATH = os.path.join(ANSIBLE_DIR, 'vars', 'connectors-example.yml')

    def test_connectors_example_exists(self):
        assert os.path.isfile(self.VARS_PATH), (
            "ansible/vars/connectors-example.yml must exist"
        )

    def test_connectors_example_valid_yaml(self):
        data = _load_yaml(self.VARS_PATH)
        assert data is not None

    def test_has_cp_connectors_list(self):
        data = _load_yaml(self.VARS_PATH)
        assert 'cp_connectors' in data, "Must define cp_connectors"
        assert isinstance(data['cp_connectors'], list), (
            "cp_connectors must be a list"
        )

    def test_has_at_least_two_connectors(self):
        data = _load_yaml(self.VARS_PATH)
        assert len(data['cp_connectors']) >= 2, (
            "cp_connectors must have at least 2 example connectors"
        )

    def test_has_jdbc_source(self):
        data = _load_yaml(self.VARS_PATH)
        names = [c['name'] for c in data['cp_connectors']]
        source_found = any('source' in n for n in names)
        assert source_found, "Must have a JDBC source connector example"

    def test_has_jdbc_sink(self):
        data = _load_yaml(self.VARS_PATH)
        names = [c['name'] for c in data['cp_connectors']]
        sink_found = any('sink' in n for n in names)
        assert sink_found, "Must have a JDBC sink connector example"

    def test_connectors_have_name_and_config(self):
        data = _load_yaml(self.VARS_PATH)
        for conn in data['cp_connectors']:
            assert 'name' in conn, f"Connector missing 'name'"
            assert 'config' in conn, (
                f"Connector '{conn['name']}' missing 'config'"
            )

    def test_source_has_connector_class(self):
        data = _load_yaml(self.VARS_PATH)
        for conn in data['cp_connectors']:
            assert 'connector.class' in conn['config'], (
                f"Connector '{conn['name']}' missing connector.class"
            )
