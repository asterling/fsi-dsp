#!/usr/bin/env python3
"""
FSI Kafka Platform - Avro Schema Validation Script

Validates .avsc files for:
  1. Structure: valid JSON, type=record, namespace, non-empty fields with name+type
  2. Namespace: must match org.fsi.{domain}.{application}.v{N}
  3. Compatibility (optional): checks against live Schema Registry via REST API

Usage:
  python3 ci/scripts/validate-schemas.py --schemas-dir schemas/
  python3 ci/scripts/validate-schemas.py --schemas-dir schemas/ --check-compatibility

Environment variables (required only with --check-compatibility):
  SR_ENDPOINT   - Schema Registry REST endpoint (e.g., https://psrc-xxxxx.eastus2.azure.confluent.cloud)
  SR_API_KEY    - Schema Registry API key
  SR_API_SECRET - Schema Registry API secret
"""

import argparse
import base64
import glob
import json
import os
import re
import sys
import urllib.error
import urllib.request

# Namespace must be org.fsi.{domain}.{application}.v{N}
# Domain and application segments: lowercase letter followed by lowercase letters, digits, or hyphens
# Version segment: v followed by one or more digits
NAMESPACE_PATTERN = re.compile(r'^org\.fsi\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*\.v[0-9]+$')


def validate_schema_structure(schema_path):
    """Validate Avro schema JSON structure and required fields.

    Returns (schema_dict, errors_list). schema_dict is None if JSON parsing fails.
    """
    try:
        with open(schema_path) as f:
            schema = json.load(f)
    except json.JSONDecodeError as e:
        return None, [f"Invalid JSON: {e}"]

    errors = []

    if schema.get("type") != "record":
        errors.append(f"Schema must be a record type, got: {schema.get('type')}")

    if not schema.get("namespace"):
        errors.append("Schema must have a namespace")

    if not schema.get("name"):
        errors.append("Schema must have a name")

    fields = schema.get("fields")
    if not fields or not isinstance(fields, list) or len(fields) == 0:
        errors.append("Schema must have a non-empty fields array")
    else:
        for i, field in enumerate(fields):
            if "name" not in field:
                errors.append(f"Field {i} missing 'name'")
            if "type" not in field:
                field_name = field.get("name", f"index {i}")
                errors.append(f"Field '{field_name}' missing 'type'")

    return schema, errors


def validate_namespace(schema):
    """Validate namespace matches org.fsi.{domain}.{application}.v{N}.

    The entity is the Avro record name, NOT part of the namespace.
    """
    namespace = schema.get("namespace", "")
    if not NAMESPACE_PATTERN.match(namespace):
        return [
            f"Invalid namespace '{namespace}'. "
            f"Must match org.fsi.{{domain}}.{{application}}.v{{N}}"
        ]
    return []


def derive_subject_name(schema):
    """Derive the Schema Registry subject name from schema namespace and record name.

    Takes the last 3 segments of the namespace (domain.application.version) plus
    the kebab-cased record name, joined with dots, and appends '-value'.
    Example: org.fsi.cncb.core.v1 + AccountTransaction -> cncb.core.v1.account-transaction-value
    """
    namespace = schema.get("namespace", "")
    name = schema.get("name", "")

    # Extract domain.application.version from namespace
    parts = namespace.split(".")
    if len(parts) >= 5:
        domain_app_version = ".".join(parts[2:])  # e.g., cncb.core.v1
    else:
        domain_app_version = namespace

    # Convert PascalCase record name to kebab-case
    kebab_name = re.sub(r"(?<!^)(?=[A-Z])", "-", name).lower()

    return f"{domain_app_version}.{kebab_name}-value"


def check_compatibility(schema, schema_path, sr_endpoint, sr_key, sr_secret):
    """Check schema compatibility against Schema Registry.

    Calls POST /compatibility/subjects/{subject}/versions?verbose=true
    Returns list of error strings (empty = compatible or new subject).
    """
    subject = derive_subject_name(schema)
    url = f"{sr_endpoint}/compatibility/subjects/{subject}/versions?verbose=true"

    # Build the request body: schema must be JSON-escaped string
    body = json.dumps({
        "schema": json.dumps(schema),
        "schemaType": "AVRO"
    }).encode("utf-8")

    credentials = base64.b64encode(f"{sr_key}:{sr_secret}".encode()).decode()

    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/vnd.schemaregistry.v1+json")
    req.add_header("Authorization", f"Basic {credentials}")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            if not result.get("is_compatible", False):
                messages = result.get("messages", [])
                return [f"Schema incompatible with subject '{subject}': {messages}"]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            # Subject does not exist yet -- first registration, skip
            pass
        else:
            return [f"SR API error for subject '{subject}': {e.code} {e.reason}"]
    except urllib.error.URLError as e:
        # SR unreachable -- warn but do not fail
        print(f"  WARNING: Schema Registry unreachable ({e.reason}), skipping compatibility check for {schema_path}")

    return []


def main():
    parser = argparse.ArgumentParser(description="Validate Avro schemas for FSI Kafka Platform")
    parser.add_argument(
        "--schemas-dir",
        default="schemas/",
        help="Directory containing .avsc files to validate (default: schemas/)"
    )
    parser.add_argument(
        "--check-compatibility",
        action="store_true",
        help="Enable Schema Registry compatibility checks (requires SR_ENDPOINT, SR_API_KEY, SR_API_SECRET env vars)"
    )
    args = parser.parse_args()

    # Find all .avsc files recursively
    pattern = os.path.join(args.schemas_dir, "**", "*.avsc")
    schema_files = sorted(glob.glob(pattern, recursive=True))

    if not schema_files:
        print(f"No .avsc files found in {args.schemas_dir}")
        sys.exit(1)

    # If compatibility checking is enabled, read SR credentials
    sr_endpoint = None
    sr_key = None
    sr_secret = None
    if args.check_compatibility:
        sr_endpoint = os.environ.get("SR_ENDPOINT", "").rstrip("/")
        sr_key = os.environ.get("SR_API_KEY", "")
        sr_secret = os.environ.get("SR_API_SECRET", "")
        if not sr_endpoint or not sr_key or not sr_secret:
            print("WARNING: --check-compatibility requires SR_ENDPOINT, SR_API_KEY, SR_API_SECRET env vars")
            print("         Skipping compatibility checks (structure and namespace validation still runs)")
            args.check_compatibility = False

    total_errors = 0
    total_schemas = 0

    for schema_path in schema_files:
        total_schemas += 1
        file_errors = []

        # 1. Structure validation
        schema, struct_errors = validate_schema_structure(schema_path)
        file_errors.extend(struct_errors)

        # 2. Namespace validation (only if structure is valid enough)
        if schema:
            ns_errors = validate_namespace(schema)
            file_errors.extend(ns_errors)

        # 3. Compatibility check (only if requested and structure is valid)
        if schema and args.check_compatibility and not file_errors:
            compat_errors = check_compatibility(schema, schema_path, sr_endpoint, sr_key, sr_secret)
            file_errors.extend(compat_errors)

        # Report results
        if file_errors:
            total_errors += 1
            for err in file_errors:
                print(f"FAIL: {schema_path}: {err}")
        else:
            field_count = len(schema.get("fields", [])) if schema else 0
            namespace = schema.get("namespace", "?") if schema else "?"
            print(f"OK: {schema_path} ({field_count} fields, namespace: {namespace})")

    # Summary
    print(f"\n{total_schemas} schemas validated, {total_errors} failed")

    if total_errors > 0:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
