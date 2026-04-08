"""
Unit tests for the fsi_governance Ansible filter plugin.

Tests cover topic name assembly, SLA tier lookups, topic name validation,
FilterModule export correctness, and parity between plugin constants and YAML.
"""
import os
import sys
import types

import pytest
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Mock ansible modules if not installed (filter plugin imports from ansible.errors)
try:
    from ansible.errors import AnsibleFilterError
except ImportError:
    ansible_mod = types.ModuleType('ansible')
    errors_mod = types.ModuleType('ansible.errors')

    class AnsibleFilterError(Exception):
        pass

    errors_mod.AnsibleFilterError = AnsibleFilterError
    ansible_mod.errors = errors_mod
    sys.modules['ansible'] = ansible_mod
    sys.modules['ansible.errors'] = errors_mod

    # Mock ansible.module_utils.common.text.converters.to_native
    mu_mod = types.ModuleType('ansible.module_utils')
    common_mod = types.ModuleType('ansible.module_utils.common')
    text_mod = types.ModuleType('ansible.module_utils.common.text')
    conv_mod = types.ModuleType('ansible.module_utils.common.text.converters')
    conv_mod.to_native = str
    text_mod.converters = conv_mod
    common_mod.text = text_mod
    mu_mod.common = common_mod
    sys.modules['ansible.module_utils'] = mu_mod
    sys.modules['ansible.module_utils.common'] = common_mod
    sys.modules['ansible.module_utils.common.text'] = text_mod
    sys.modules['ansible.module_utils.common.text.converters'] = conv_mod

# Now add filter_plugins to path and import
sys.path.insert(0, os.path.join(REPO_ROOT, 'ansible', 'filter_plugins'))
from fsi_governance import (  # noqa: E402
    fsi_topic_name, fsi_sla_lookup, fsi_validate_topic_name,
    FilterModule, SLA_TIERS
)


# ---------------------------------------------------------------------------
# TestFsiTopicName -- topic name assembly from dict
# ---------------------------------------------------------------------------
class TestFsiTopicName:
    """Test fsi_topic_name filter function."""

    def test_valid_assembly(self):
        result = fsi_topic_name({
            'domain': 'cncb',
            'application': 'core',
            'version': 'v1',
            'entity': 'account-txn',
        })
        assert result == 'cncb.core.v1.account-txn'

    def test_cptopic_labels(self):
        result = fsi_topic_name({
            'domain': 'corebanking',
            'application': 'transactions',
            'version': 'v1',
            'entity': 'account-transaction',
        })
        assert result == 'corebanking.transactions.v1.account-transaction'

    def test_missing_keys(self):
        with pytest.raises(Exception, match='missing required keys'):
            fsi_topic_name({'domain': 'cncb'})

    def test_empty_value(self):
        with pytest.raises(Exception, match='missing required keys'):
            fsi_topic_name({
                'domain': 'cncb',
                'application': '',
                'version': 'v1',
                'entity': 'txn',
            })

    def test_bad_domain_uppercase(self):
        with pytest.raises(Exception, match='does not match'):
            fsi_topic_name({
                'domain': 'UPPER',
                'application': 'core',
                'version': 'v1',
                'entity': 'txn',
            })

    def test_bad_version_no_prefix(self):
        with pytest.raises(Exception, match='does not match'):
            fsi_topic_name({
                'domain': 'cncb',
                'application': 'core',
                'version': '1',
                'entity': 'txn',
            })

    def test_bad_entity_too_long(self):
        long_entity = 'a' + '-' + 'b' * 61  # exceeds {1,60} after first char
        with pytest.raises(Exception, match='does not match'):
            fsi_topic_name({
                'domain': 'cncb',
                'application': 'core',
                'version': 'v1',
                'entity': long_entity,
            })


# ---------------------------------------------------------------------------
# TestFsiSlaLookup -- SLA tier property lookups
# ---------------------------------------------------------------------------
class TestFsiSlaLookup:
    """Test fsi_sla_lookup filter function."""

    def test_critical_partitions(self):
        assert fsi_sla_lookup('critical', 'partitions') == 12

    def test_critical_compatibility(self):
        assert fsi_sla_lookup('critical', 'compatibility') == 'FULL_TRANSITIVE'

    def test_critical_retention(self):
        assert fsi_sla_lookup('critical', 'retention_ms') == 604800000

    def test_standard_partitions(self):
        assert fsi_sla_lookup('standard', 'partitions') == 6

    def test_standard_compatibility(self):
        assert fsi_sla_lookup('standard', 'compatibility') == 'BACKWARD_TRANSITIVE'

    def test_standard_retention(self):
        assert fsi_sla_lookup('standard', 'retention_ms') == 259200000

    def test_best_effort_partitions(self):
        assert fsi_sla_lookup('best-effort', 'partitions') == 3

    def test_best_effort_compatibility(self):
        assert fsi_sla_lookup('best-effort', 'compatibility') == 'BACKWARD'

    def test_best_effort_retention(self):
        assert fsi_sla_lookup('best-effort', 'retention_ms') == 86400000

    def test_compliance_partitions(self):
        assert fsi_sla_lookup('compliance', 'partitions') == 12

    def test_compliance_compatibility(self):
        assert fsi_sla_lookup('compliance', 'compatibility') == 'FULL_TRANSITIVE'

    def test_compliance_retention(self):
        assert fsi_sla_lookup('compliance', 'retention_ms') == -1

    def test_invalid_tier(self):
        with pytest.raises(Exception, match='unknown tier'):
            fsi_sla_lookup('gold', 'partitions')

    def test_invalid_property(self):
        with pytest.raises(Exception, match='unknown property'):
            fsi_sla_lookup('critical', 'nonexistent')


# ---------------------------------------------------------------------------
# TestFsiValidateTopicName -- topic name string validation
# ---------------------------------------------------------------------------
class TestFsiValidateTopicName:
    """Test fsi_validate_topic_name filter function."""

    def test_valid_name(self):
        assert fsi_validate_topic_name('cncb.core.v1.account-txn') is True

    def test_valid_corebanking(self):
        assert fsi_validate_topic_name('corebanking.transactions.v1.account-transaction') is True

    def test_too_few_parts(self):
        with pytest.raises(Exception, match='expected 4'):
            fsi_validate_topic_name('cncb.core')

    def test_too_many_parts(self):
        with pytest.raises(Exception, match='expected 4'):
            fsi_validate_topic_name('a.b.c.d.e')

    def test_bad_domain(self):
        with pytest.raises(Exception, match='invalid'):
            fsi_validate_topic_name('UPPER.core.v1.txn')

    def test_bad_version(self):
        with pytest.raises(Exception, match='invalid'):
            fsi_validate_topic_name('cncb.core.1.txn')


# ---------------------------------------------------------------------------
# TestFilterModule -- Ansible plugin registration
# ---------------------------------------------------------------------------
class TestFilterModule:
    """Test FilterModule class exports."""

    def test_exports_all_filters(self):
        filters = FilterModule().filters()
        assert set(filters.keys()) == {
            'fsi_topic_name', 'fsi_sla_lookup', 'fsi_validate_topic_name'
        }

    def test_filter_callables(self):
        filters = FilterModule().filters()
        for name, func in filters.items():
            assert callable(func), f"Filter '{name}' is not callable"


# ---------------------------------------------------------------------------
# TestSlaTiersParity -- plugin constants match YAML file
# ---------------------------------------------------------------------------
class TestSlaTiersParity:
    """Verify SLA_TIERS dict in plugin matches ansible/vars/sla_tiers.yml."""

    def test_sla_tiers_match_yaml(self):
        yaml_path = os.path.join(REPO_ROOT, 'ansible', 'vars', 'sla_tiers.yml')
        with open(yaml_path) as f:
            yaml_data = yaml.safe_load(f)

        for tier in ['critical', 'standard', 'best-effort', 'compliance']:
            for prop in ['compatibility', 'partitions', 'retention_ms']:
                assert SLA_TIERS[tier][prop] == yaml_data['sla_tiers'][tier][prop], \
                    f"SLA_TIERS['{tier}']['{prop}'] mismatch: " \
                    f"plugin={SLA_TIERS[tier][prop]} yaml={yaml_data['sla_tiers'][tier][prop]}"
