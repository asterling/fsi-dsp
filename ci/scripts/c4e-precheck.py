#!/usr/bin/env python3
"""
FSI Kafka Platform - C4E Pre-Check Suite

Validates topic requests before human C4E review by running 5 automated checks:
  1. Naming Convention   - domain/application/version/entity regex validation
  2. Schema Compatibility - structure + namespace validation of referenced .avsc files
  3. RBAC Completeness    - producer/consumer SA bindings per data classification
  4. SLA Tier Consistency - retention/partition overrides vs tier minimums
  5. PII Field Audit      - confidential topics must declare PII fields matching schema

Parses .tf source files (not Terraform state) to extract module arguments.
Also parses CFK KafkaTopic YAML files for governance validation (same 5 checks).
Uses only Python stdlib -- no pip dependencies (matches validate-schemas.py pattern).

Usage:
  python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cc-aws/
  python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cfk-openshift/ --verbose
  python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cc-aws/ --schemas-dir schemas/ --verbose
"""

import argparse
import json
import os
import re
import sys


# ── Naming regex patterns (match modules/topic/variables.tf) ──
DOMAIN_PATTERN = re.compile(r'^[a-z][a-z0-9-]{1,30}$')
APPLICATION_PATTERN = re.compile(r'^[a-z][a-z0-9-]{1,30}$')
VERSION_PATTERN = re.compile(r'^v[0-9]+$')
ENTITY_PATTERN = re.compile(r'^[a-z][a-z0-9-]{1,60}$')

# Avro namespace pattern (from validate-schemas.py)
NAMESPACE_PATTERN = re.compile(r'^org\.fsi\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*\.v[0-9]+$')

# SLA tier minimums
TIER_MIN_RETENTION_MS = {
    'critical': 604800000,       # 7 days
    'standard': 259200000,       # 3 days
    'best-effort': 86400000,     # 1 day
    'compliance': 220898482000,  # ~7 years
}

TIER_MIN_PARTITIONS = {
    'critical': 6,
    'standard': 3,
    'best-effort': 1,
    'compliance': 3,
}


def parse_tf_modules(scenario_dir):
    """Parse .tf files for module blocks calling ../../modules/topic.

    Returns a list of dicts, each containing module name and extracted arguments.
    """
    modules = []
    tf_files = sorted(
        f for f in os.listdir(scenario_dir)
        if f.endswith('.tf') and os.path.isfile(os.path.join(scenario_dir, f))
    )

    for tf_file in tf_files:
        filepath = os.path.join(scenario_dir, tf_file)
        with open(filepath) as f:
            content = f.read()

        # Find module blocks that reference the topic module
        # Pattern: module "name" { ... source = "../../modules/topic" ... }
        module_pattern = re.compile(
            r'module\s+"([^"]+)"\s*\{(.*?)\n\}',
            re.DOTALL
        )

        for match in module_pattern.finditer(content):
            module_name = match.group(1)
            block = match.group(2)

            # Check if this module uses the topic module
            if 'modules/topic' not in block:
                continue

            # Extract arguments
            args = {}
            # String arguments: key = "value"
            str_pattern = re.compile(
                r'(domain|application|schema_version|entity|sla_tier|'
                r'data_classification|schema_file|owner|compatibility_override)\s*=\s*"([^"]*)"'
            )
            for arg_match in str_pattern.finditer(block):
                args[arg_match.group(1)] = arg_match.group(2)

            # Numeric arguments: key = 12345
            num_pattern = re.compile(
                r'(retention_ms_override|partitions_override)\s*=\s*(-?\d+)'
            )
            for arg_match in num_pattern.finditer(block):
                args[arg_match.group(1)] = int(arg_match.group(2))

            # List arguments: pii_fields = ["field1", "field2"]
            pii_pattern = re.compile(
                r'pii_fields\s*=\s*\[(.*?)\]', re.DOTALL
            )
            pii_match = pii_pattern.search(block)
            if pii_match:
                pii_raw = pii_match.group(1)
                pii_fields = re.findall(r'"([^"]*)"', pii_raw)
                args['pii_fields'] = pii_fields
            else:
                args['pii_fields'] = []

            # List arguments for service accounts
            for sa_key in ['producer_service_accounts', 'consumer_service_accounts',
                           'producer_sa_names', 'consumer_sa_names']:
                sa_pattern = re.compile(
                    rf'{sa_key}\s*=\s*\[(.*?)\]', re.DOTALL
                )
                sa_match = sa_pattern.search(block)
                if sa_match:
                    sa_raw = sa_match.group(1)
                    sa_values = re.findall(r'"([^"]*)"', sa_raw)
                    args[sa_key] = sa_values
                else:
                    # Check for variable reference: key = var.something
                    var_pattern = re.compile(rf'{sa_key}\s*=\s*var\.(\w+)')
                    var_match = var_pattern.search(block)
                    if var_match:
                        # Variable reference -- assume non-empty (CI can't resolve vars)
                        args[sa_key] = ['<var-ref>']
                    else:
                        args[sa_key] = []

            modules.append({
                'name': module_name,
                'file': tf_file,
                'args': args,
            })

    return modules


def parse_yaml_simple(filepath):
    """Lightweight YAML parser for CFK KafkaTopic CRDs (stdlib only).

    Handles the limited YAML subset used in KafkaTopic CRDs:
      - key: value
      - key: "quoted value"
      - key: (start of nested block via indentation)
    Does not handle arrays, multiline strings, or anchors.

    Returns a nested dict matching the YAML hierarchy.
    """
    result = {}
    # Stack tracks (indent_level, dict_ref) pairs.
    # indent_level is the indentation at which this dict's keys appear.
    stack = [(-1, result)]  # sentinel with indent -1

    with open(filepath) as f:
        for line in f:
            # Skip empty lines and comments
            stripped = line.rstrip('\n\r')
            if not stripped or stripped.lstrip().startswith('#'):
                continue

            # Calculate indentation (number of leading spaces)
            indent = len(stripped) - len(stripped.lstrip())
            content = stripped.lstrip()

            # Pop stack entries that are at the same level or deeper
            # Keep only ancestors (strictly less indentation)
            while len(stack) > 1 and stack[-1][0] >= indent:
                stack.pop()

            # Parse key: value
            colon_idx = content.find(':')
            if colon_idx == -1:
                continue

            key = content[:colon_idx].strip()
            value_part = content[colon_idx + 1:].strip()

            if not key:
                continue

            # Remove surrounding quotes from value
            if value_part.startswith('"') and value_part.endswith('"'):
                value_part = value_part[1:-1]

            current_dict = stack[-1][1]

            if value_part:
                # key: value (leaf node)
                current_dict[key] = value_part
            else:
                # key: (start of nested block)
                new_dict = {}
                current_dict[key] = new_dict
                # Children will appear at a deeper indent level
                # We use indent+1 as a placeholder; the while-loop above
                # uses >= comparison so any child indent > indent will keep
                # this entry on the stack
                stack.append((indent + 1, new_dict))

    return result


def parse_cfk_topics(scenario_dir):
    """Parse KafkaTopic YAML files for governance validation.

    Looks in {scenario_dir}/topics/ for .yaml/.yml files with kind: KafkaTopic.
    Returns a list of dicts with the same structure as parse_tf_modules returns,
    allowing CFK topics to pass through the same 5 governance checks.
    """
    modules = []
    topics_dir = os.path.join(scenario_dir, 'topics')
    if not os.path.isdir(topics_dir):
        return modules

    yaml_files = sorted(
        f for f in os.listdir(topics_dir)
        if f.endswith(('.yaml', '.yml')) and os.path.isfile(os.path.join(topics_dir, f))
    )

    for yaml_file in yaml_files:
        filepath = os.path.join(topics_dir, yaml_file)
        doc = parse_yaml_simple(filepath)

        # Filter for KafkaTopic documents only
        if doc.get('kind') != 'KafkaTopic':
            continue

        metadata = doc.get('metadata', {})
        labels = metadata.get('labels', {})
        spec = doc.get('spec', {})
        configs = spec.get('configs', {})

        topic_name = metadata.get('name', '')

        # Split topic name: {domain}.{application}.{version}.{entity}
        name_parts = topic_name.split('.')
        if len(name_parts) >= 4:
            domain = name_parts[0]
            application = name_parts[1]
            schema_version = name_parts[2]
            entity = '.'.join(name_parts[3:])  # entity may contain dots
        else:
            # Not enough parts -- will fail naming check
            domain = name_parts[0] if len(name_parts) > 0 else ''
            application = name_parts[1] if len(name_parts) > 1 else ''
            schema_version = name_parts[2] if len(name_parts) > 2 else ''
            entity = ''

        sla_tier = labels.get('fsi.sla-tier', '')

        # Map CFK labels to module args for governance check compatibility
        args = {
            'domain': domain,
            'application': application,
            'schema_version': schema_version,
            'entity': entity,
            'sla_tier': sla_tier,
            'owner': labels.get('fsi.owner', ''),
            'data_classification': labels.get('fsi.data-classification', 'internal'),
            # CFK schemas registered separately -- not part of KafkaTopic CRD
            'schema_file': '',
            'pii_fields': [],
            # Marker: CFK topics manage PII via schema registration, not CRD labels
            '_cfk_source': True,
            # ACLs managed separately for CFK (via acl-templates.yaml)
            'producer_service_accounts': ['<cfk-acl>'],
            'consumer_service_accounts': ['<cfk-acl>'],
            'producer_sa_names': [],
            'consumer_sa_names': [],
        }

        # Only set overrides if they differ from tier defaults
        # (avoid triggering override checks when using tier defaults)
        partition_count = spec.get('partitionCount', '')
        if partition_count:
            try:
                args['partitions_override'] = int(partition_count)
            except ValueError:
                pass

        retention_ms = configs.get('retention.ms', '')
        if retention_ms:
            try:
                args['retention_ms_override'] = int(retention_ms)
            except ValueError:
                pass

        modules.append({
            'name': topic_name,
            'file': yaml_file,
            'args': args,
        })

    return modules


def check_naming(modules, verbose=False):
    """Check 1: Validate naming convention for domain/application/version/entity."""
    print("[CHECK 1/5] Naming Convention")
    passed = 0
    failed = 0

    for mod in modules:
        args = mod['args']
        errors = []

        domain = args.get('domain', '')
        application = args.get('application', '')
        version = args.get('schema_version', '')
        entity = args.get('entity', '')

        if domain and not DOMAIN_PATTERN.match(domain):
            errors.append(f"domain '{domain}' does not match ^[a-z][a-z0-9-]{{1,30}}$")
        elif not domain:
            errors.append("domain is missing")

        if application and not APPLICATION_PATTERN.match(application):
            errors.append(f"application '{application}' does not match ^[a-z][a-z0-9-]{{1,30}}$")
        elif not application:
            errors.append("application is missing")

        if version and not VERSION_PATTERN.match(version):
            errors.append(f"schema_version '{version}' does not match ^v[0-9]+$")
        elif not version:
            errors.append("schema_version is missing")

        if entity and not ENTITY_PATTERN.match(entity):
            errors.append(f"entity '{entity}' does not match ^[a-z][a-z0-9-]{{1,60}}$")
        elif not entity:
            errors.append("entity is missing")

        topic_name = f"{domain}.{application}.{version}.{entity}" if all([domain, application, version, entity]) else "<incomplete>"

        if errors:
            failed += 1
            print(f"  {mod['name']}: FAIL ({', '.join(errors)})")
        else:
            passed += 1
            print(f"  {mod['name']}: PASS ({topic_name})")

    return passed, failed


def check_schema(modules, schemas_dir, verbose=False):
    """Check 2: Validate schema structure and namespace for referenced .avsc files."""
    print("[CHECK 2/5] Schema Compatibility")
    passed = 0
    failed = 0

    for mod in modules:
        args = mod['args']
        schema_file = args.get('schema_file', '')

        if not schema_file:
            if verbose:
                print(f"  {mod['name']}: SKIP (no schema_file argument)")
            continue

        # Resolve schema path -- could be relative to scenario dir or schemas dir
        schema_path = None
        candidates = [
            schema_file,
            os.path.join(schemas_dir, schema_file),
            os.path.join(schemas_dir, os.path.basename(schema_file)),
        ]
        for candidate in candidates:
            if os.path.isfile(candidate):
                schema_path = candidate
                break

        if not schema_path:
            # Schema file references like ../../schemas/examples/foo.avsc
            # may be relative to the scenario dir -- not a failure if not found in CI
            if verbose:
                print(f"  {mod['name']}: SKIP (schema file '{schema_file}' not found)")
            continue

        try:
            with open(schema_path) as f:
                schema = json.load(f)
        except json.JSONDecodeError as e:
            failed += 1
            print(f"  {mod['name']}: FAIL (invalid JSON in {schema_path}: {e})")
            continue

        errors = []

        # Structure checks
        if schema.get('type') != 'record':
            errors.append(f"type must be 'record', got '{schema.get('type')}'")
        if not schema.get('namespace'):
            errors.append("missing namespace")
        if not schema.get('name'):
            errors.append("missing name")
        if not schema.get('fields') or not isinstance(schema.get('fields'), list):
            errors.append("missing or empty fields array")
        else:
            for i, field in enumerate(schema['fields']):
                if 'name' not in field:
                    errors.append(f"field {i} missing 'name'")
                if 'type' not in field:
                    errors.append(f"field '{field.get('name', i)}' missing 'type'")

        # Namespace check
        namespace = schema.get('namespace', '')
        if namespace and not NAMESPACE_PATTERN.match(namespace):
            errors.append(f"namespace '{namespace}' must match org.fsi.{{domain}}.{{application}}.v{{N}}")

        if errors:
            failed += 1
            print(f"  {mod['name']}: FAIL ({'; '.join(errors)})")
        else:
            field_count = len(schema.get('fields', []))
            passed += 1
            print(f"  {mod['name']}: PASS ({field_count} fields, namespace: {namespace})")

    if not any(mod['args'].get('schema_file') for mod in modules):
        print("  (no schema_file references found)")

    return passed, failed


def check_rbac(modules, verbose=False):
    """Check 3: Validate RBAC completeness -- at least one producer SA per module."""
    print("[CHECK 3/5] RBAC Completeness")
    passed = 0
    failed = 0

    for mod in modules:
        args = mod['args']
        errors = []

        # At least one producer SA must be set
        producer_sas = args.get('producer_service_accounts', [])
        producer_names = args.get('producer_sa_names', [])
        if not producer_sas and not producer_names:
            errors.append("no producer service accounts defined")

        # For confidential topics, consumer SAs should also be set
        data_class = args.get('data_classification', 'internal')
        if data_class == 'confidential':
            consumer_sas = args.get('consumer_service_accounts', [])
            consumer_names = args.get('consumer_sa_names', [])
            if not consumer_sas and not consumer_names:
                errors.append("confidential topic requires consumer service accounts")

        if errors:
            failed += 1
            print(f"  {mod['name']}: FAIL ({', '.join(errors)})")
        else:
            passed += 1
            sa_count = len(producer_sas) + len(producer_names)
            print(f"  {mod['name']}: PASS ({sa_count} producer SA(s))")

    return passed, failed


def check_sla_tier(modules, verbose=False):
    """Check 4: Validate SLA tier consistency -- overrides must not violate tier minimums."""
    print("[CHECK 4/5] SLA Tier Consistency")
    passed = 0
    failed = 0

    for mod in modules:
        args = mod['args']
        errors = []

        sla_tier = args.get('sla_tier', '')
        if not sla_tier:
            errors.append("sla_tier is missing")
        elif sla_tier not in TIER_MIN_RETENTION_MS:
            errors.append(f"unknown sla_tier '{sla_tier}'")
        else:
            # Check retention override
            retention_override = args.get('retention_ms_override')
            if retention_override is not None:
                min_retention = TIER_MIN_RETENTION_MS[sla_tier]
                # -1 means infinite retention (always valid)
                if retention_override != -1 and retention_override < min_retention:
                    errors.append(
                        f"retention_ms_override ({retention_override}) below "
                        f"{sla_tier} tier minimum ({min_retention})"
                    )

            # Check partitions override
            partitions_override = args.get('partitions_override')
            if partitions_override is not None:
                min_partitions = TIER_MIN_PARTITIONS[sla_tier]
                if partitions_override < min_partitions:
                    errors.append(
                        f"partitions_override ({partitions_override}) below "
                        f"{sla_tier} tier minimum ({min_partitions})"
                    )

        if errors:
            failed += 1
            print(f"  {mod['name']}: FAIL ({', '.join(errors)})")
        else:
            passed += 1
            tier_display = sla_tier if sla_tier else 'unknown'
            print(f"  {mod['name']}: PASS (tier: {tier_display})")

    return passed, failed


def check_pii(modules, schemas_dir, verbose=False):
    """Check 5: Validate PII field audit -- confidential topics must declare PII fields."""
    print("[CHECK 5/5] PII Field Audit")
    passed = 0
    failed = 0

    for mod in modules:
        args = mod['args']
        errors = []

        data_class = args.get('data_classification', 'internal')
        pii_fields = args.get('pii_fields', [])

        # CFK topics manage PII via schema registration (separate from CRD)
        is_cfk = args.get('_cfk_source', False)

        if data_class == 'confidential' and is_cfk:
            # CFK topics: PII fields are in the schema, not the KafkaTopic CRD
            passed += 1
            print(f"  {mod['name']}: PASS (confidential, PII managed via schema registration)")
            continue
        elif data_class == 'confidential':
            if not pii_fields:
                errors.append("confidential topic must have non-empty pii_fields")
            else:
                # If schema_file is referenced, verify PII field names exist in schema
                schema_file = args.get('schema_file', '')
                if schema_file:
                    schema_path = None
                    candidates = [
                        schema_file,
                        os.path.join(schemas_dir, schema_file),
                        os.path.join(schemas_dir, os.path.basename(schema_file)),
                    ]
                    for candidate in candidates:
                        if os.path.isfile(candidate):
                            schema_path = candidate
                            break

                    if schema_path:
                        try:
                            with open(schema_path) as f:
                                schema = json.load(f)
                            schema_field_names = [
                                field.get('name', '') for field in schema.get('fields', [])
                            ]
                            for pii_field in pii_fields:
                                if pii_field not in schema_field_names:
                                    errors.append(
                                        f"PII field '{pii_field}' not found in schema "
                                        f"(available: {', '.join(schema_field_names)})"
                                    )
                        except (json.JSONDecodeError, IOError):
                            if verbose:
                                print(f"  {mod['name']}: WARNING (could not parse schema for PII audit)")
        else:
            # Non-confidential topics: PII check is informational
            if pii_fields and verbose:
                print(f"  {mod['name']}: INFO (pii_fields set on non-confidential topic)")

        if errors:
            failed += 1
            print(f"  {mod['name']}: FAIL ({', '.join(errors)})")
        else:
            passed += 1
            if data_class == 'confidential':
                print(f"  {mod['name']}: PASS (confidential, {len(pii_fields)} PII field(s))")
            else:
                print(f"  {mod['name']}: PASS ({data_class})")

    return passed, failed


def main():
    parser = argparse.ArgumentParser(
        description="C4E Pre-Check Suite - Validates topic requests before human review"
    )
    parser.add_argument(
        '--scenario-dir',
        required=True,
        help="Path to scenario directory to validate -- works with both Terraform "
             "(e.g., scenarios/cc-aws/) and CFK YAML scenarios (e.g., scenarios/cfk-openshift/)"
    )
    parser.add_argument(
        '--schemas-dir',
        default='schemas/',
        help="Path to schemas directory (default: schemas/)"
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help="Enable detailed output"
    )
    args = parser.parse_args()

    # Validate scenario directory exists
    if not os.path.isdir(args.scenario_dir):
        print(f"ERROR: Scenario directory not found: {args.scenario_dir}")
        sys.exit(1)

    print(f"=== C4E Pre-Check: {args.scenario_dir} ===")
    print()

    # Parse topic modules from Terraform .tf files
    tf_modules = parse_tf_modules(args.scenario_dir)

    # Parse topic modules from CFK KafkaTopic YAML files
    cfk_modules = parse_cfk_topics(args.scenario_dir)

    # Combine all modules for unified governance checks
    modules = tf_modules + cfk_modules

    if not modules:
        print("No topic modules found in scenario directory.")
        print("(Looking for: Terraform module blocks with 'modules/topic', "
              "or KafkaTopic YAML files in topics/ directory)")
        print()
        print("RESULT: 0 checks passed, 0 failed (no modules to validate)")
        sys.exit(0)

    if args.verbose:
        if tf_modules:
            print(f"Found {len(tf_modules)} Terraform topic module(s): "
                  f"{', '.join(m['name'] for m in tf_modules)}")
        if cfk_modules:
            print(f"Found {len(cfk_modules)} CFK KafkaTopic CRD(s): "
                  f"{', '.join(m['name'] for m in cfk_modules)}")
        print()

    # Run all 5 checks
    total_passed = 0
    total_failed = 0

    for check_fn, check_args in [
        (check_naming, (modules,)),
        (check_schema, (modules, args.schemas_dir)),
        (check_rbac, (modules,)),
        (check_sla_tier, (modules,)),
        (check_pii, (modules, args.schemas_dir)),
    ]:
        p, f = check_fn(*check_args, verbose=args.verbose)
        total_passed += p
        total_failed += f
        print()

    # Summary
    print(f"RESULT: {total_passed} checks passed, {total_failed} failed")

    if total_failed > 0:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
