"""
Governance parity tests between Ansible YAML files and Terraform HCL source.

Validates that ansible/vars/sla_tiers.yml and ansible/vars/naming_rules.yml
contain values identical to modules/topic/main.tf and modules/topic/variables.tf.
CI-enforced drift prevention.
"""
import os
import re

import pytest
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load_yaml(relpath):
    """Load a YAML file relative to the repo root."""
    with open(os.path.join(REPO_ROOT, relpath)) as f:
        return yaml.safe_load(f)


def load_text(relpath):
    """Load a text file relative to the repo root."""
    with open(os.path.join(REPO_ROOT, relpath)) as f:
        return f.read()


def extract_tf_map(text, map_name):
    """Extract a Terraform map block: name = { key = value ... }
    Returns dict of key -> value (string)."""
    pattern = rf'{map_name}\s*=\s*\{{([\s\S]*?)\}}'
    match = re.search(pattern, text)
    if not match:
        return {}
    block = match.group(1)
    result = {}
    for line in block.strip().split('\n'):
        line = re.sub(r'#.*$', '', line).strip()
        m = re.match(r'([\w-]+)\s*=\s*(.+)', line)
        if m:
            key = m.group(1).strip()
            val = m.group(2).strip().strip('"')
            result[key] = val
    return result


def extract_tf_validation_regex(text, var_name):
    """Extract regex pattern from Terraform variable validation block."""
    var_pattern = rf'variable\s+"{var_name}"\s*\{{([\s\S]*?)\n\}}'
    var_match = re.search(var_pattern, text)
    if not var_match:
        return None
    block = var_match.group(1)
    regex_match = re.search(r'regex\("([^"]+)"', block)
    return regex_match.group(1) if regex_match else None


class TestGovernanceParity:
    """Verify Ansible governance constants mirror Terraform HCL exactly."""

    @pytest.fixture(autouse=True)
    def setup(self):
        self.sla_tiers = load_yaml('ansible/vars/sla_tiers.yml')
        self.naming_rules = load_yaml('ansible/vars/naming_rules.yml')
        self.main_tf = load_text('modules/topic/main.tf')
        self.variables_tf = load_text('modules/topic/variables.tf')

    # --- SLA tier compatibility ---
    def test_sla_tier_compatibility_matches_terraform(self):
        tf_map = extract_tf_map(self.main_tf, 'compatibility_map')
        for tier in ['critical', 'standard', 'best-effort', 'compliance']:
            assert self.sla_tiers['sla_tiers'][tier]['compatibility'] == tf_map[tier], \
                f"Compatibility mismatch for tier '{tier}'"

    # --- SLA tier partitions ---
    def test_sla_tier_partitions_matches_terraform(self):
        tf_map = extract_tf_map(self.main_tf, 'partition_map')
        for tier in ['critical', 'standard', 'best-effort', 'compliance']:
            assert self.sla_tiers['sla_tiers'][tier]['partitions'] == int(tf_map[tier]), \
                f"Partition mismatch for tier '{tier}'"

    # --- SLA tier retention ---
    def test_sla_tier_retention_matches_terraform(self):
        tf_map = extract_tf_map(self.main_tf, 'retention_map')
        for tier in ['critical', 'standard', 'best-effort']:
            assert self.sla_tiers['sla_tiers'][tier]['retention_ms'] == int(tf_map[tier]), \
                f"Retention mismatch for tier '{tier}'"
        # Compliance tier: TF uses local.compliance_retention_ms which defaults to -1
        assert self.sla_tiers['sla_tiers']['compliance']['retention_ms'] == -1, \
            "Compliance tier retention should default to -1"

    # --- Individual tier value checks ---
    def test_sla_tier_critical(self):
        tier = self.sla_tiers['sla_tiers']['critical']
        assert tier['compatibility'] == 'FULL_TRANSITIVE'
        assert tier['partitions'] == 12
        assert tier['retention_ms'] == 604800000
        assert tier['min_insync_replicas'] == 2

    def test_sla_tier_standard(self):
        tier = self.sla_tiers['sla_tiers']['standard']
        assert tier['compatibility'] == 'BACKWARD_TRANSITIVE'
        assert tier['partitions'] == 6
        assert tier['retention_ms'] == 259200000
        assert tier['min_insync_replicas'] == 2

    def test_sla_tier_best_effort(self):
        tier = self.sla_tiers['sla_tiers']['best-effort']
        assert tier['compatibility'] == 'BACKWARD'
        assert tier['partitions'] == 3
        assert tier['retention_ms'] == 86400000
        assert tier['min_insync_replicas'] == 1

    def test_sla_tier_compliance(self):
        tier = self.sla_tiers['sla_tiers']['compliance']
        assert tier['compatibility'] == 'FULL_TRANSITIVE'
        assert tier['partitions'] == 12
        assert tier['retention_ms'] == -1
        assert tier['min_insync_replicas'] == 2

    # --- Naming regex parity ---
    def test_naming_domain_regex_matches_terraform(self):
        tf_regex = extract_tf_validation_regex(self.variables_tf, 'domain')
        assert self.naming_rules['naming_rules']['domain']['pattern'] == tf_regex, \
            f"Domain regex mismatch: YAML={self.naming_rules['naming_rules']['domain']['pattern']} TF={tf_regex}"

    def test_naming_application_regex_matches_terraform(self):
        tf_regex = extract_tf_validation_regex(self.variables_tf, 'application')
        assert self.naming_rules['naming_rules']['application']['pattern'] == tf_regex

    def test_naming_version_regex_matches_terraform(self):
        tf_regex = extract_tf_validation_regex(self.variables_tf, 'schema_version')
        assert self.naming_rules['naming_rules']['version']['pattern'] == tf_regex

    def test_naming_entity_regex_matches_terraform(self):
        tf_regex = extract_tf_validation_regex(self.variables_tf, 'entity')
        assert self.naming_rules['naming_rules']['entity']['pattern'] == tf_regex

    # --- Completeness checks ---
    def test_sla_tier_names_complete(self):
        expected = {'critical', 'standard', 'best-effort', 'compliance'}
        assert set(self.sla_tiers['sla_tiers'].keys()) == expected

    def test_sla_tier_default_is_standard(self):
        assert self.sla_tiers['sla_tier_default'] == 'standard'
