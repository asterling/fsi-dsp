"""
FSI Governance Jinja2 filters for Ansible.

Provides filters for topic name assembly, SLA-tier property lookups,
and topic name validation. These filters centralise governance logic
so every Ansible role uses consistent naming and SLA-tier rules that
mirror the Terraform module in modules/topic/.

Filters:
    fsi_topic_name       - Assemble a topic name from a dict of components
    fsi_sla_lookup       - Look up an SLA-tier property (partitions, etc.)
    fsi_validate_topic_name - Validate a topic name string against governance rules
"""

import re

from ansible.errors import AnsibleFilterError
from ansible.module_utils.common.text.converters import to_native

# ---------------------------------------------------------------------------
# Compiled regex constants -- MUST match modules/topic/variables.tf exactly
# ---------------------------------------------------------------------------
DOMAIN_RE = re.compile(r'^[a-z][a-z0-9-]{1,30}$')
APP_RE = re.compile(r'^[a-z][a-z0-9-]{1,30}$')
VERSION_RE = re.compile(r'^v[0-9]+$')
ENTITY_RE = re.compile(r'^[a-z][a-z0-9-]{1,60}$')

# Map component names to their compiled regex patterns
_COMPONENT_REGEX = {
    'domain': DOMAIN_RE,
    'application': APP_RE,
    'version': VERSION_RE,
    'entity': ENTITY_RE,
}

# ---------------------------------------------------------------------------
# SLA tier constants -- MUST match modules/topic/main.tf locals exactly
# ---------------------------------------------------------------------------
SLA_TIERS = {
    'critical': {
        'compatibility': 'FULL_TRANSITIVE',
        'partitions': 12,
        'retention_ms': 604800000,
    },
    'standard': {
        'compatibility': 'BACKWARD_TRANSITIVE',
        'partitions': 6,
        'retention_ms': 259200000,
    },
    'best-effort': {
        'compatibility': 'BACKWARD',
        'partitions': 3,
        'retention_ms': 86400000,
    },
    'compliance': {
        'compatibility': 'FULL_TRANSITIVE',
        'partitions': 12,
        'retention_ms': -1,
    },
}

# Required keys for topic name assembly
_REQUIRED_KEYS = ('domain', 'application', 'version', 'entity')


# ---------------------------------------------------------------------------
# Filter functions
# ---------------------------------------------------------------------------
def fsi_topic_name(topic_def):
    """Assemble a governed topic name from a dict of components.

    Args:
        topic_def: dict with keys domain, application, version, entity.

    Returns:
        str: assembled topic name in {domain}.{application}.{version}.{entity} format.

    Raises:
        AnsibleFilterError: on missing keys, empty values, or regex mismatches.
    """
    try:
        if not isinstance(topic_def, dict):
            raise AnsibleFilterError(
                "fsi_topic_name expects a dict, got %s" % type(topic_def).__name__
            )

        # Check for missing or empty required keys
        missing = [k for k in _REQUIRED_KEYS if not topic_def.get(k)]
        if missing:
            raise AnsibleFilterError(
                "fsi_topic_name: missing required keys: %s" % ', '.join(missing)
            )

        # Validate each component against its governance regex
        for key in _REQUIRED_KEYS:
            value = topic_def[key]
            pattern = _COMPONENT_REGEX[key]
            if not pattern.match(value):
                raise AnsibleFilterError(
                    "fsi_topic_name: '%s' value '%s' does not match pattern %s"
                    % (key, value, pattern.pattern)
                )

        return "%s.%s.%s.%s" % (
            topic_def['domain'],
            topic_def['application'],
            topic_def['version'],
            topic_def['entity'],
        )
    except AnsibleFilterError:
        raise
    except Exception as e:
        raise AnsibleFilterError("fsi_topic_name: %s" % to_native(e))


def fsi_sla_lookup(tier, prop):
    """Look up a property value for a given SLA tier.

    Args:
        tier: SLA tier name (critical, standard, best-effort, compliance).
        prop: Property name (compatibility, partitions, retention_ms).

    Returns:
        The property value (str or int).

    Raises:
        AnsibleFilterError: on unknown tier or unknown property.
    """
    try:
        if tier not in SLA_TIERS:
            raise AnsibleFilterError(
                "fsi_sla_lookup: unknown tier '%s'. Valid tiers: %s"
                % (tier, ', '.join(sorted(SLA_TIERS.keys())))
            )

        tier_data = SLA_TIERS[tier]
        if prop not in tier_data:
            raise AnsibleFilterError(
                "fsi_sla_lookup: unknown property '%s' for tier '%s'. "
                "Valid properties: %s"
                % (prop, tier, ', '.join(sorted(tier_data.keys())))
            )

        return tier_data[prop]
    except AnsibleFilterError:
        raise
    except Exception as e:
        raise AnsibleFilterError("fsi_sla_lookup: %s" % to_native(e))


def fsi_validate_topic_name(name):
    """Validate a topic name string against governance naming rules.

    Args:
        name: topic name string to validate.

    Returns:
        True if valid.

    Raises:
        AnsibleFilterError: if the name does not conform to governance rules.
    """
    try:
        parts = name.split('.')
        if len(parts) != 4:
            raise AnsibleFilterError(
                "fsi_validate_topic_name: expected 4 dot-separated parts, "
                "got %d in '%s'" % (len(parts), name)
            )

        labels = ['domain', 'application', 'version', 'entity']
        errors = []
        for label, value in zip(labels, parts):
            pattern = _COMPONENT_REGEX[label]
            if not pattern.match(value):
                errors.append(
                    "%s '%s' is invalid (expected pattern: %s)"
                    % (label, value, pattern.pattern)
                )

        if errors:
            raise AnsibleFilterError(
                "fsi_validate_topic_name: %s" % '; '.join(errors)
            )

        return True
    except AnsibleFilterError:
        raise
    except Exception as e:
        raise AnsibleFilterError("fsi_validate_topic_name: %s" % to_native(e))


# ---------------------------------------------------------------------------
# Ansible FilterModule registration
# ---------------------------------------------------------------------------
class FilterModule:
    """FSI governance filters for Ansible playbooks and roles."""

    def filters(self):
        return {
            'fsi_topic_name': fsi_topic_name,
            'fsi_sla_lookup': fsi_sla_lookup,
            'fsi_validate_topic_name': fsi_validate_topic_name,
        }
