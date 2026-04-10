# Phase 10: Ansible Foundation and Governance Scaffolding - Research

**Researched:** 2026-04-07
**Domain:** Ansible automation scaffolding, cp-ansible collection, filter plugins, ansible-lint, governance parity
**Confidence:** HIGH

## Summary

Phase 10 creates the `ansible/` directory at the repo root as the foundation for all subsequent Ansible-based automation (Phases 11-15). The core deliverables are: a `requirements.yml` pinning cp-ansible 7.7.x and supporting collections, an `ansible.cfg` with filter plugin paths, shared governance constants that exactly mirror the Terraform module locals in `modules/topic/main.tf`, a custom `fsi_governance` filter plugin for topic name assembly and SLA-tier lookups, multi-environment inventory skeletons, and an ansible-lint configuration using the `shared` profile.

The cp-ansible collection (`confluent.platform`) version 7.7.8 is the latest 7.7.x release, with no declared external collection dependencies in its `galaxy.yml`. However, the project will need `community.general` and `ansible.posix` for future phases (uri module enhancements, file operations). The governance constants are fully defined in the existing Terraform module (`modules/topic/main.tf` lines 35-82) and must be mirrored exactly -- this is a data extraction exercise, not a design decision.

**Primary recommendation:** Scaffold `ansible/` with pinned dependencies, extract governance constants verbatim from Terraform, build the `fsi_governance` filter plugin as a pure-function Python module with comprehensive error handling, and configure ansible-lint with the `shared` profile targeting the `ansible/` directory.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
All implementation choices are at Claude's discretion -- pure infrastructure phase with no user-facing behavior decisions. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions.

Key constraints from success criteria:
- `requirements.yml` must pin cp-ansible 7.7.x and all required collections
- `sla_tiers.yml` must produce identical values to Terraform module locals
- `fsi_governance` filter plugin must match Terraform `{domain}.{application}.{version}.{entity}` regex
- `ansible-lint` must pass with zero violations
- Inventory skeletons for dev, staging, prod, dr environments

### Claude's Discretion
All implementation choices -- pure infrastructure phase.

### Deferred Ideas (OUT OF SCOPE)
None -- infrastructure phase, discuss skipped.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AFOUND-01 | `ansible/` directory contains `requirements.yml` with pinned cp-ansible 7.7.x collection, `ansible.cfg`, and multi-environment inventory skeletons (dev/staging/prod/dr) | Standard Stack section provides exact collection versions to pin; Architecture Patterns section provides directory structure and inventory skeleton patterns based on existing cp-rhel scenario |
| AFOUND-02 | Shared governance constants in `ansible/vars/sla_tiers.yml` mirror Terraform module SLA-tier mappings (partitions, retention, compatibility per tier) and CI validates parity | Code Examples section provides exact values extracted from `modules/topic/main.tf` locals; Common Pitfalls covers drift prevention |
| AFOUND-03 | Topic naming validation regex in `ansible/vars/naming_rules.yml` matches Terraform `variables.tf` regex and CI validates parity | Code Examples section provides exact regex patterns from `modules/topic/variables.tf`; filter plugin section shows how to use them |
| AFOUND-04 | Filter plugin (`filter_plugins/fsi_governance.py`) provides Jinja2 filters for SLA-tier lookups and topic name assembly usable by all roles | Architecture Patterns section details FilterModule class structure, error handling with AnsibleFilterError, and pure-function design |
| AFOUND-05 | `.ansible-lint` config with `shared` profile enforces FQCN, Galaxy metadata, and documentation standards on all roles | Standard Stack section documents ansible-lint configuration; note that `shared` profile does NOT include FQCN rule (that is `production` profile), so either use `production` or add FQCN to `enable_list` |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Deployment parity**: Core governance (topic naming, schema compat, RBAC) must work identically across all deployment models -- Ansible vars MUST mirror Terraform module locals exactly
- **No custom Python modules**: `ansible.builtin.uri` covers all REST API needs (STATE.md decision); but filter plugins are explicitly allowed (they are Jinja2 filters, not action modules)
- **Standalone roles**: Not Galaxy collection packaging -- roles are tightly coupled to repo governance data (Out of Scope in REQUIREMENTS.md)
- **CP 7.7.x target**: cp-ansible 8.x/KRaft migration is explicitly out of scope
- **Backward compatibility**: Existing Confluent Cloud Terraform modules must continue to work -- extend, don't break
- **Commit messages**: conventional commit format (`feat:`, `fix:`, `docs:`, etc.)
- **Shell scripts**: `set -euo pipefail` for strict error handling
- **Python 3**: Standard for CI/CD validation scripts

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| confluent.platform | 7.7.8 | cp-ansible collection for Confluent Platform deployment | Latest 7.7.x release; pinned to match CP 7.7.x target per project constraints |
| ansible-core | >=2.14, <2.17 | Automation engine | cp-ansible 7.7.x supports ansible-core 2.14-2.16 (Ansible packages 7.x-9.x) |
| ansible-lint | >=24.0.0 | Linting and style enforcement | Supports `shared` profile; Python >=3.10 required |
| yamllint | >=1.30.0 | YAML syntax validation | Used by ansible-lint internally; also for standalone CI checks |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| community.general | >=8.0.0 | General-purpose modules (ini_file, json_query, etc.) | Future phases (12-15) will need these; pin now for consistency |
| ansible.posix | >=1.5.0 | POSIX modules (sysctl, selinux, synchronize) | Future phases for RHEL system configuration |
| ansible.utils | >=2.10.0 | Network/data manipulation utilities (ipaddr filter, validate) | Future phases for inventory validation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom Python Ansible modules | ansible.builtin.uri | Project decision: uri for REST APIs; filter plugins only for Jinja2 data transforms |
| Galaxy collection packaging | Standalone roles in repo | Project decision: roles coupled to repo governance data, no external distribution needed |
| cp-ansible 8.x | cp-ansible 7.7.x | 8.x introduces KRaft; 7.7.x is the stable ZooKeeper-based target per project scope |

**Installation:**
```bash
# From ansible/ directory:
ansible-galaxy collection install -r requirements.yml --force
pip install ansible-lint yamllint
```

**Version verification:** cp-ansible 7.7.8 confirmed as latest 7.7.x release via GitHub releases page (2026-03-26). confluent.platform collection has `dependencies: {}` in galaxy.yml -- no transitive collection dependencies. ansible-lint 26.3.0 is latest on PyPI (2026-03-05).

## Architecture Patterns

### Recommended Project Structure
```
ansible/
├── ansible.cfg                    # Project-scoped Ansible config
├── requirements.yml               # Pinned collection dependencies
├── .ansible-lint                  # Lint configuration (shared profile)
├── filter_plugins/                # Custom Jinja2 filter plugins
│   └── fsi_governance.py          # SLA-tier lookups, topic name assembly
├── vars/                          # Shared governance constants
│   ├── sla_tiers.yml              # SLA tier -> partition/retention/compat mappings
│   └── naming_rules.yml           # Topic naming regex patterns
├── inventories/                   # Multi-environment inventory skeletons
│   ├── dev/
│   │   ├── hosts.yml              # Dev environment hosts
│   │   └── group_vars/
│   │       └── all.yml            # Dev-specific variables
│   ├── staging/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       └── all.yml
│   ├── prod/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       ├── all.yml
│   │       ├── kafka_broker.yml
│   │       ├── schema_registry.yml
│   │       └── kafka_connect.yml
│   └── dr/
│       ├── hosts.yml
│       └── group_vars/
│           └── all.yml
├── playbooks/                     # Placeholder for future phases
│   └── .gitkeep
└── roles/                         # Placeholder for future phases
    └── .gitkeep
```

### Pattern 1: Governance Constants as YAML Data Files
**What:** Extract SLA-tier mappings and naming regex from Terraform into standalone YAML files that Ansible roles consume via `vars_files` or `include_vars`.
**When to use:** Any role that needs to derive topic configuration from SLA tier or validate topic names.
**Example:**
```yaml
# ansible/vars/sla_tiers.yml
# Source of truth: modules/topic/main.tf lines 44-82
# WARNING: These values MUST stay in sync with Terraform.
# CI validates parity -- see ci/scripts/validate-governance-parity.py

sla_tiers:
  critical:
    compatibility: FULL_TRANSITIVE
    partitions: 12
    retention_ms: 604800000      # 7 days
    min_insync_replicas: 2
  standard:
    compatibility: BACKWARD_TRANSITIVE
    partitions: 6
    retention_ms: 259200000      # 3 days
    min_insync_replicas: 2
  best-effort:
    compatibility: BACKWARD
    partitions: 3
    retention_ms: 86400000       # 1 day
    min_insync_replicas: 1
  compliance:
    compatibility: FULL_TRANSITIVE
    partitions: 12
    retention_ms: -1             # Configurable via retention_years
    min_insync_replicas: 2

# Default tier when none specified
sla_tier_default: standard

# Valid SLA tier names (for validation)
sla_tier_names:
  - critical
  - standard
  - best-effort
  - compliance
```

### Pattern 2: Filter Plugin as Pure Function Module
**What:** A Python module containing a `FilterModule` class that exposes Jinja2 filters for governance operations. All filters are pure functions (input -> output, no side effects).
**When to use:** Any Jinja2 template or `when:` condition that needs to look up SLA-tier defaults or assemble/validate topic names.
**Example:**
```python
# ansible/filter_plugins/fsi_governance.py
"""FSI Governance Jinja2 filters for Ansible.

Provides:
  - fsi_topic_name: Assemble topic name from components
  - fsi_sla_lookup: Look up SLA-tier property (partitions, retention_ms, compatibility)
  - fsi_validate_topic_name: Validate topic name against naming regex
"""
import re

from ansible.errors import AnsibleFilterError


# Regex patterns matching modules/topic/variables.tf
DOMAIN_PATTERN = re.compile(r'^[a-z][a-z0-9-]{1,30}$')
APPLICATION_PATTERN = re.compile(r'^[a-z][a-z0-9-]{1,30}$')
VERSION_PATTERN = re.compile(r'^v[0-9]+$')
ENTITY_PATTERN = re.compile(r'^[a-z][a-z0-9-]{1,60}$')

# SLA tier defaults matching modules/topic/main.tf locals
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


def fsi_topic_name(topic_def):
    """Assemble topic name: {domain}.{application}.{version}.{entity}"""
    # ... implementation
    pass


def fsi_sla_lookup(tier, property_name):
    """Look up SLA tier property value."""
    # ... implementation
    pass


def fsi_validate_topic_name(name):
    """Validate a topic name string against governance regex."""
    # ... implementation
    pass


class FilterModule:
    """FSI Governance filters for Ansible."""
    def filters(self):
        return {
            'fsi_topic_name': fsi_topic_name,
            'fsi_sla_lookup': fsi_sla_lookup,
            'fsi_validate_topic_name': fsi_validate_topic_name,
        }
```

### Pattern 3: Multi-Environment Inventory with Shared Group Structure
**What:** Each environment gets its own inventory directory with hosts.yml and group_vars/, sharing the same host group names (kafka_broker, schema_registry, kafka_connect, flink_jobmanager, flink_taskmanager) that match the existing cp-rhel inventory pattern.
**When to use:** All playbook executions use `-i ansible/inventories/{env}/`.
**Source:** Existing pattern in `scenarios/cp-rhel/inventory/hosts.yml.example`.

### Pattern 4: ansible.cfg with Project-Scoped Paths
**What:** The `ansible.cfg` at `ansible/` root configures filter_plugins, vars, and inventory paths relative to the ansible directory, plus collection paths.
**When to use:** Always -- this is the project configuration anchor.
**Example:**
```ini
# ansible/ansible.cfg
[defaults]
# Collection install location
collections_path = ./collections:~/.ansible/collections

# Custom filter plugins
filter_plugins = ./filter_plugins

# Default inventory (overridden with -i)
inventory = ./inventories/dev

# Reduce noise
deprecation_warnings = False
retry_files_enabled = False

# SSH settings for RHEL targets
host_key_checking = False
timeout = 30

[inventory]
# Enable YAML inventory plugin
enable_plugins = yaml, ini

[privilege_escalation]
become = true
become_method = sudo
```

### Anti-Patterns to Avoid
- **Hardcoding governance values in roles:** Always reference `vars/sla_tiers.yml` via `include_vars` or the `fsi_governance` filter. Never duplicate partition counts or retention values in role defaults.
- **Using short module names:** The `shared` profile implicitly encourages FQCN, but the requirement calls it out explicitly. Use `ansible.builtin.uri` not `uri`, `ansible.builtin.assert` not `assert`.
- **Mixing Python module logic and filter logic:** Filter plugins are Jinja2 filters (pure data transformation). Do not add HTTP calls, file I/O, or side effects to filter plugins. That's what action modules or `ansible.builtin.uri` is for.
- **Storing secrets in inventory group_vars:** Inventory skeletons should reference Ansible Vault variables (`{{ vault_* }}`), not contain actual credentials.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Governance constant management | Custom sync scripts between TF and Ansible | Single-source YAML file + CI parity check script | Parity validation is a CI concern, not a runtime concern |
| Topic name regex validation | Ad-hoc regex in each role | `fsi_governance` filter plugin with compiled regex | Central maintenance, tested once, used everywhere |
| SLA tier property lookups | Nested `when:` conditionals per tier | `fsi_governance` filter plugin `fsi_sla_lookup` | Eliminates error-prone conditional chains in every role |
| Inventory per environment | Dynamic inventory scripts | Static YAML inventory skeletons with group_vars | CP-RHEL targets are known hosts, not cloud-dynamic; static is simpler and auditable |
| Collection dependency resolution | Manual pip/galaxy install commands | `requirements.yml` with `ansible-galaxy collection install -r` | Standard Ansible pattern; reproducible across environments |

**Key insight:** The governance constants are a data extraction exercise from Terraform, not a design decision. The Terraform module (`modules/topic/main.tf`) is the source of truth. The Ansible YAML file is a mirror. CI validates parity. This is a deliberate duplication with automated parity checking -- the alternative (Terraform generating Ansible vars at apply-time) creates a runtime dependency between IaC tools that should remain independent.

## Common Pitfalls

### Pitfall 1: Governance Value Drift Between Terraform and Ansible
**What goes wrong:** SLA-tier values in `ansible/vars/sla_tiers.yml` diverge from `modules/topic/main.tf` locals after a Terraform-side update.
**Why it happens:** Two sources of truth for the same data. A developer updates Terraform but forgets the Ansible mirror.
**How to avoid:** CI parity validation script (Python) that parses both files and asserts equality. Run on every PR touching either `modules/topic/` or `ansible/vars/`. This is required by AFOUND-02 and AFOUND-03.
**Warning signs:** Topic created via Ansible has different partition count or retention than the same tier in Terraform.

### Pitfall 2: ansible-lint `shared` Profile Does Not Include FQCN Rule
**What goes wrong:** Requirement AFOUND-05 says "enforces FQCN" but the `shared` profile does NOT include the `fqcn` rule -- that's only in the `production` profile.
**Why it happens:** Misunderstanding profile hierarchy. The `shared` profile sits below `production`.
**How to avoid:** Either (a) use `profile: production` which includes FQCN, or (b) use `profile: shared` with `enable_list: [fqcn]` to add FQCN enforcement. Option (b) is preferred because `production` also includes `meta-no-dependencies` which may conflict with collections that have dependencies.
**Warning signs:** ansible-lint passes but playbooks use short module names like `command` instead of `ansible.builtin.command`.

### Pitfall 3: Filter Plugin Import Path Issues
**What goes wrong:** `fsi_governance.py` placed in wrong directory or `ansible.cfg` `filter_plugins` path doesn't resolve correctly.
**Why it happens:** Ansible searches for filter plugins relative to the playbook location, the role, or the configured `filter_plugins` path. If `ansible.cfg` is not in the expected location, the path resolution fails silently.
**How to avoid:** Place `ansible.cfg` at `ansible/` root. Set `filter_plugins = ./filter_plugins` (relative to ansible.cfg location). Always run ansible-playbook from the `ansible/` directory or use `ANSIBLE_CONFIG=ansible/ansible.cfg`.
**Warning signs:** `filter 'fsi_topic_name' is undefined` error at playbook runtime.

### Pitfall 4: cp-ansible 7.7.x Ansible Version Warning
**What goes wrong:** When using ansible-core 2.15+, cp-ansible 7.7.x emits `[WARNING]: Collection confluent.platform does not support Ansible version 2.15`.
**Why it happens:** The `meta/runtime.yml` in cp-ansible 7.7.x declares a supported Ansible version range that was updated in later releases.
**How to avoid:** This warning is cosmetic and can be safely ignored (confirmed by Confluent docs). Do not downgrade ansible-core to suppress it. Document this in the ansible.cfg comments.
**Warning signs:** CI logs show warnings but all operations succeed.

### Pitfall 5: Inventory Skeleton Secrets in Git
**What goes wrong:** Developer fills in actual passwords or API keys in inventory group_vars and commits them.
**Why it happens:** Skeleton files look like they need real values to "work."
**How to avoid:** All sensitive values in skeleton files MUST use `{{ vault_* }}` Ansible Vault references. Add a comment block at the top of each group_vars file explaining the Vault workflow. Add `*.vault.yml` to `.gitignore` if needed.
**Warning signs:** `grep -r 'password:' ansible/inventories/` returns non-vault-reference values.

### Pitfall 6: Compliance Tier Retention Value Handling
**What goes wrong:** The compliance tier retention_ms in Terraform is computed dynamically from `retention_years` variable (default -1 = infinite). Representing this in static YAML requires special handling.
**Why it happens:** Terraform locals can compute; YAML vars files are static. The compliance tier's `retention_ms` depends on a per-topic input variable, not a fixed constant.
**How to avoid:** Set compliance tier `retention_ms: -1` in sla_tiers.yml as the default (infinite retention). The actual per-topic retention calculation (`years * 31557600000 ms/year`) should be handled in the topic role (Phase 11), not in the governance constants file. Document this clearly.
**Warning signs:** Compliance topics all get -1 retention instead of the intended years-based value.

## Code Examples

Verified patterns from project codebase and official sources:

### Governance Constants Extraction (from Terraform)
```yaml
# ansible/vars/sla_tiers.yml
# Mirrors: modules/topic/main.tf lines 44-82
# Parity validated by CI -- do NOT edit without updating Terraform
---
sla_tiers:
  critical:
    compatibility: FULL_TRANSITIVE
    partitions: 12
    retention_ms: 604800000
    min_insync_replicas: 2
  standard:
    compatibility: BACKWARD_TRANSITIVE
    partitions: 6
    retention_ms: 259200000
    min_insync_replicas: 2
  best-effort:
    compatibility: BACKWARD
    partitions: 3
    retention_ms: 86400000
    min_insync_replicas: 1
  compliance:
    compatibility: FULL_TRANSITIVE
    partitions: 12
    retention_ms: -1
    min_insync_replicas: 2

sla_tier_default: standard
sla_tier_names:
  - critical
  - standard
  - best-effort
  - compliance
```

### Naming Rules Extraction (from Terraform variables.tf)
```yaml
# ansible/vars/naming_rules.yml
# Mirrors: modules/topic/variables.tf lines 8-46
# Parity validated by CI -- do NOT edit without updating Terraform
---
naming_rules:
  domain:
    pattern: "^[a-z][a-z0-9-]{1,30}$"
    description: "Lowercase alphanumeric with hyphens, 2-31 chars, starting with a letter"
  application:
    pattern: "^[a-z][a-z0-9-]{1,30}$"
    description: "Lowercase alphanumeric with hyphens, 2-31 chars"
  version:
    pattern: "^v[0-9]+$"
    description: "Version identifier: v1, v2, etc."
  entity:
    pattern: "^[a-z][a-z0-9-]{1,60}$"
    description: "Lowercase alphanumeric with hyphens, 2-61 chars"

# Assembled topic name format
topic_name_format: "{domain}.{application}.{version}.{entity}"
topic_name_separator: "."
```

### requirements.yml with Pinned Versions
```yaml
# ansible/requirements.yml
---
collections:
  # Confluent Platform Ansible collection -- CP 7.7.x deployment roles
  - name: confluent.platform
    version: "7.7.8"

  # General-purpose modules (json_query, ini_file, etc.)
  - name: community.general
    version: ">=8.0.0"

  # POSIX modules (sysctl, selinux, synchronize)
  - name: ansible.posix
    version: ">=1.5.0"

  # Data manipulation utilities (ipaddr filter, validate)
  - name: ansible.utils
    version: ">=2.10.0"
```

### ansible-lint Configuration
```yaml
# ansible/.ansible-lint
---
profile: shared

# FQCN enforcement (not included in shared profile, required by AFOUND-05)
enable_list:
  - fqcn

# Paths to lint
exclude_paths:
  - collections/
  - .cache/

# Mock unavailable roles during lint (cp-ansible roles not installed locally)
mock_roles:
  - confluent.platform.kafka_broker
  - confluent.platform.schema_registry
  - confluent.platform.kafka_connect
  - confluent.platform.zookeeper
  - confluent.platform.kafka_rest
  - confluent.platform.ksql
  - confluent.platform.control_center

# Variable naming: allow both snake_case and Confluent's custom property names
var_naming_pattern: "^[a-z_][a-z0-9_]*$"

# Offline mode (don't try to install requirements during lint)
offline: true
```

### Filter Plugin Complete Structure
```python
# ansible/filter_plugins/fsi_governance.py
"""FSI Governance Jinja2 filters for Ansible.

Provides filters for topic name assembly, SLA-tier property lookups,
and topic name validation. All filters are pure functions with no
side effects.

Source of truth: modules/topic/main.tf (SLA tiers), modules/topic/variables.tf (naming regex)
"""

import re

from ansible.errors import AnsibleFilterError
from ansible.module_utils.common.text.converters import to_native


# Naming regex -- mirrors modules/topic/variables.tf lines 8-46
DOMAIN_RE = re.compile(r'^[a-z][a-z0-9-]{1,30}$')
APP_RE = re.compile(r'^[a-z][a-z0-9-]{1,30}$')
VERSION_RE = re.compile(r'^v[0-9]+$')
ENTITY_RE = re.compile(r'^[a-z][a-z0-9-]{1,60}$')

# SLA tier defaults -- mirrors modules/topic/main.tf lines 44-82
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


def fsi_topic_name(topic_def):
    """Assemble topic name from dict with domain, application, version, entity keys.

    Usage in Jinja2:
      {{ topic | fsi_topic_name }}
    Where topic = {domain: 'cncb', application: 'core', version: 'v1', entity: 'account-txn'}
    Returns: 'cncb.core.v1.account-txn'
    """
    try:
        required = ['domain', 'application', 'version', 'entity']
        missing = [k for k in required if k not in topic_def or not topic_def[k]]
        if missing:
            raise AnsibleFilterError(
                "fsi_topic_name: missing required keys: %s" % ', '.join(missing)
            )

        domain = str(topic_def['domain'])
        app = str(topic_def['application'])
        version = str(topic_def['version'])
        entity = str(topic_def['entity'])

        # Validate each component
        if not DOMAIN_RE.match(domain):
            raise AnsibleFilterError(
                "fsi_topic_name: domain '%s' does not match %s" % (domain, DOMAIN_RE.pattern)
            )
        if not APP_RE.match(app):
            raise AnsibleFilterError(
                "fsi_topic_name: application '%s' does not match %s" % (app, APP_RE.pattern)
            )
        if not VERSION_RE.match(version):
            raise AnsibleFilterError(
                "fsi_topic_name: version '%s' does not match %s" % (version, VERSION_RE.pattern)
            )
        if not ENTITY_RE.match(entity):
            raise AnsibleFilterError(
                "fsi_topic_name: entity '%s' does not match %s" % (entity, ENTITY_RE.pattern)
            )

        return "%s.%s.%s.%s" % (domain, app, version, entity)

    except AnsibleFilterError:
        raise
    except Exception as e:
        raise AnsibleFilterError("fsi_topic_name: %s" % to_native(e))


def fsi_sla_lookup(tier, prop):
    """Look up an SLA tier property.

    Usage in Jinja2:
      {{ 'critical' | fsi_sla_lookup('partitions') }}
    Returns: 12
    """
    try:
        if tier not in SLA_TIERS:
            raise AnsibleFilterError(
                "fsi_sla_lookup: unknown tier '%s', valid: %s"
                % (tier, ', '.join(sorted(SLA_TIERS.keys())))
            )
        tier_props = SLA_TIERS[tier]
        if prop not in tier_props:
            raise AnsibleFilterError(
                "fsi_sla_lookup: unknown property '%s' for tier '%s', valid: %s"
                % (prop, tier, ', '.join(sorted(tier_props.keys())))
            )
        return tier_props[prop]
    except AnsibleFilterError:
        raise
    except Exception as e:
        raise AnsibleFilterError("fsi_sla_lookup: %s" % to_native(e))


def fsi_validate_topic_name(name):
    """Validate a fully-assembled topic name string.

    Usage in Jinja2:
      {{ topic_name | fsi_validate_topic_name }}
    Returns: True if valid, raises AnsibleFilterError if invalid.
    """
    try:
        parts = str(name).split('.')
        if len(parts) != 4:
            raise AnsibleFilterError(
                "fsi_validate_topic_name: expected 4 dot-separated parts, got %d in '%s'"
                % (len(parts), name)
            )
        domain, app, version, entity = parts
        errors = []
        if not DOMAIN_RE.match(domain):
            errors.append("domain '%s' invalid" % domain)
        if not APP_RE.match(app):
            errors.append("application '%s' invalid" % app)
        if not VERSION_RE.match(version):
            errors.append("version '%s' invalid" % version)
        if not ENTITY_RE.match(entity):
            errors.append("entity '%s' invalid" % entity)
        if errors:
            raise AnsibleFilterError(
                "fsi_validate_topic_name: '%s' failed: %s" % (name, '; '.join(errors))
            )
        return True
    except AnsibleFilterError:
        raise
    except Exception as e:
        raise AnsibleFilterError("fsi_validate_topic_name: %s" % to_native(e))


class FilterModule:
    """FSI Governance filters."""

    def filters(self):
        return {
            'fsi_topic_name': fsi_topic_name,
            'fsi_sla_lookup': fsi_sla_lookup,
            'fsi_validate_topic_name': fsi_validate_topic_name,
        }
```

### Inventory Skeleton Pattern (from existing cp-rhel)
```yaml
# ansible/inventories/prod/hosts.yml
# Production environment inventory skeleton
# Copy and customize with actual hostnames and IPs.
# Sensitive values use Ansible Vault references: {{ vault_* }}
---
all:
  vars:
    ansible_connection: ssh
    ansible_user: confluent
    ansible_become: true
    confluent_server_enabled: true
    confluent_package_version: "7.7.0"

  children:
    kafka_broker:
      hosts:
        kafka-prod-1:
          ansible_host: <IP_ADDRESS>
          kafka_broker_custom_properties:
            broker.id: 1
            broker.rack: <AVAILABILITY_ZONE>
        kafka-prod-2:
          ansible_host: <IP_ADDRESS>
          kafka_broker_custom_properties:
            broker.id: 2
            broker.rack: <AVAILABILITY_ZONE>
        kafka-prod-3:
          ansible_host: <IP_ADDRESS>
          kafka_broker_custom_properties:
            broker.id: 3
            broker.rack: <AVAILABILITY_ZONE>

    schema_registry:
      hosts:
        sr-prod-1:
          ansible_host: <IP_ADDRESS>
        sr-prod-2:
          ansible_host: <IP_ADDRESS>

    kafka_connect:
      hosts:
        connect-prod-1:
          ansible_host: <IP_ADDRESS>
        connect-prod-2:
          ansible_host: <IP_ADDRESS>

    flink_jobmanager:
      hosts:
        flink-jm-prod-1:
          ansible_host: <IP_ADDRESS>

    flink_taskmanager:
      hosts:
        flink-tm-prod-1:
          ansible_host: <IP_ADDRESS>
        flink-tm-prod-2:
          ansible_host: <IP_ADDRESS>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| cp-ansible as standalone playbooks | cp-ansible as Galaxy collection (`confluent.platform`) | CP 7.0+ | Install via `ansible-galaxy collection install` instead of git clone |
| `ssl_mutual_auth_enabled: true` | `ssl_client_authentication` variable | cp-ansible 7.8.0+ | 7.7.x still uses old variable; no migration needed for this phase |
| ansible-lint numeric version (e.g., 6.x) | ansible-lint CalVer (24.x, 25.x, 26.x) | 2024+ | Version scheme changed; use `>=24.0.0` for minimum |
| Profiles didn't exist in ansible-lint | Profiles (min/basic/moderate/safety/shared/production) | ansible-lint 6.x+ | Use `profile: shared` for publishing-quality enforcement |
| ZooKeeper-based CP deployment | KRaft (no ZooKeeper) | cp-ansible 8.x | Out of scope for v2.0; 7.7.x is ZooKeeper-based |

**Deprecated/outdated:**
- cp-ansible as git clone workflow: Use Galaxy collection install instead
- ansible-lint < 6.x configuration format: Old `.ansible-lint` format still works but profiles are preferred
- `ssl_mutual_auth_enabled`: Deprecated in 7.8.0+ but still required for 7.7.x

## Open Questions

1. **RHEL 8 vs RHEL 9 target in inventory skeletons**
   - What we know: STATE.md notes "RHEL 8 vs RHEL 9 customer prevalence unknown" as a blocker/concern
   - What's unclear: Whether inventory skeletons should default to RHEL 8 or RHEL 9 specific configurations
   - Recommendation: Keep inventories RHEL-version-agnostic (no RHEL version in skeleton). The deploy-cp.yml playbook already asserts `ansible_distribution_major_version >= 8`. Defer RHEL-specific config to group_vars populated at deployment time.

2. **CI parity validation script location**
   - What we know: AFOUND-02 and AFOUND-03 require CI validates parity between Ansible and Terraform
   - What's unclear: Whether the parity check script belongs in `ci/scripts/` (existing CI pattern) or in `ansible/`
   - Recommendation: Place in `ci/scripts/validate-governance-parity.py` following existing CI script pattern (`validate-schemas.py`, `c4e-precheck.py`). This is a CI concern, not an Ansible concern. However, this script is part of Phase 12 (ACI-03), not Phase 10. Phase 10 should structure the YAML files to be machine-parseable for this future script.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Python 3 | Filter plugin development, ansible-lint | Yes | 3.9.6 | -- |
| ansible-core | Playbook execution (not needed for scaffolding) | No | -- | Not needed for Phase 10 scaffolding; install for validation only |
| ansible-lint | Lint validation (AFOUND-05) | No | -- | `pip install ansible-lint` during validation |
| ansible-galaxy | Collection installation (AFOUND-01) | No | -- | Installed with ansible package |

**Missing dependencies with no fallback:**
- None that block Phase 10. This phase creates files; it does not execute playbooks against remote hosts.

**Missing dependencies with fallback:**
- `ansible-lint`: Not installed but can be installed via pip for local validation. CI will be the authoritative lint runner. Phase 10 implementation can validate lint config by installing in a temp venv if desired, but this is optional -- the success criterion is that the config file is correct, not that it runs on the developer's Mac.
- `ansible-core` / `ansible-galaxy`: Not installed locally. The `requirements.yml` correctness can be validated syntactically (valid YAML, correct collection names/versions) without running `ansible-galaxy collection install`. Actual installation testing deferred to CI.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Python unittest (stdlib) + ansible-lint |
| Config file | None yet -- Wave 0 creates test infrastructure |
| Quick run command | `python3 -m pytest tests/ansible/ -x --tb=short` |
| Full suite command | `python3 -m pytest tests/ansible/ -v` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AFOUND-01 | requirements.yml has pinned cp-ansible 7.7.x | unit | `python3 -m pytest tests/ansible/test_requirements.py -x` | Wave 0 |
| AFOUND-02 | sla_tiers.yml values match Terraform locals | unit | `python3 -m pytest tests/ansible/test_governance_parity.py::test_sla_tiers -x` | Wave 0 |
| AFOUND-03 | naming_rules.yml regex matches Terraform variables.tf | unit | `python3 -m pytest tests/ansible/test_governance_parity.py::test_naming_rules -x` | Wave 0 |
| AFOUND-04 | fsi_governance filter plugin produces correct outputs | unit | `python3 -m pytest tests/ansible/test_fsi_governance_filter.py -x` | Wave 0 |
| AFOUND-05 | ansible-lint passes with zero violations | smoke | `cd ansible && ansible-lint --offline` (requires ansible-lint installed) | manual-only |

### Sampling Rate
- **Per task commit:** `python3 -m pytest tests/ansible/ -x --tb=short`
- **Per wave merge:** `python3 -m pytest tests/ansible/ -v`
- **Phase gate:** All tests green + ansible-lint zero violations

### Wave 0 Gaps
- [ ] `tests/ansible/test_requirements.py` -- validates requirements.yml structure and version pins (AFOUND-01)
- [ ] `tests/ansible/test_governance_parity.py` -- validates sla_tiers.yml and naming_rules.yml match Terraform (AFOUND-02, AFOUND-03)
- [ ] `tests/ansible/test_fsi_governance_filter.py` -- unit tests for filter plugin functions without Ansible runtime (AFOUND-04)
- [ ] `tests/ansible/__init__.py` -- package init
- [ ] pytest framework: already available via `pip install pytest` (Python 3.9.6 present)

## Sources

### Primary (HIGH confidence)
- `modules/topic/main.tf` lines 35-82 -- SLA tier maps (compatibility, partitions, retention) -- read directly from codebase
- `modules/topic/variables.tf` lines 8-46, 61-69 -- Topic naming regex and SLA tier enum -- read directly from codebase
- `scenarios/cp-rhel/inventory/hosts.yml.example` -- Existing inventory structure -- read directly from codebase
- `scenarios/cp-rhel/playbooks/deploy-cp.yml` -- Existing playbook patterns -- read directly from codebase
- `scenarios/cp-rhel/topics/*.yml` -- CPTopic YAML format -- read directly from codebase
- [Confluent cp-ansible GitHub releases](https://github.com/confluentinc/cp-ansible/releases) -- v7.7.8 is latest 7.7.x
- [cp-ansible galaxy.yml (7.7.0-post branch)](https://github.com/confluentinc/cp-ansible/blob/7.7.0-post/galaxy.yml) -- `dependencies: {}` confirmed

### Secondary (MEDIUM confidence)
- [Confluent Ansible requirements docs](https://docs.confluent.io/ansible/current/ansible-requirements.html) -- cp-ansible 7.7.x requires Ansible 7.x-9.x (ansible-core 2.14-2.16)
- [ansible-lint profiles documentation](https://docs.ansible.com/projects/lint/profiles/) -- shared profile rules list, production profile adds FQCN
- [ansible-lint configuration documentation](https://docs.ansible.com/projects/lint/configuring/) -- full config file format
- [Ansible developing plugins documentation](https://docs.ansible.com/projects/ansible/latest/dev_guide/developing_plugins.html) -- FilterModule class pattern, AnsibleFilterError usage
- [ansible-lint PyPI](https://pypi.org/project/ansible-lint/) -- version 26.3.0 latest (2026-03-05)
- [Confluent Ansible download docs](https://docs.confluent.io/ansible/current/ansible-download.html) -- installation methods

### Tertiary (LOW confidence)
- None -- all claims verified with primary or secondary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- versions confirmed via GitHub releases and official docs; cp-ansible 7.7.8 verified, galaxy.yml dependencies confirmed empty
- Architecture: HIGH -- directory structure derived from existing cp-rhel patterns in the repo; filter plugin pattern from official Ansible docs
- Pitfalls: HIGH -- governance drift is a known concern documented in STATE.md; FQCN profile issue verified against official ansible-lint docs

**Research date:** 2026-04-07
**Valid until:** 2026-05-07 (30 days -- stable domain, no fast-moving dependencies)
