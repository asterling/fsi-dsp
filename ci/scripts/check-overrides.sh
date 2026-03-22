#!/bin/bash
# =============================================================================
# FSI Kafka Platform - Compatibility Override Detection
# Checks for compatibility_override usage in scenario/environment .tf files.
# Requires PR body to contain ADR or JIRA reference if override is used.
# =============================================================================
set -euo pipefail

PR_BODY="${PR_BODY:-}"

# Get changed .tf files in environments/ and scenarios/ ONLY
# Exclude modules/ to avoid false positives on the variable definition itself (Pitfall 6)
CHANGED_FILES=$(git diff origin/main --name-only -- 'environments/**/*.tf' 'scenarios/**/*.tf' 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "No compatibility_override detected -- no scenario/environment .tf files changed."
  exit 0
fi

# Look for non-null compatibility_override assignments
# Matches: compatibility_override = "FULL_TRANSITIVE" (actual usage)
# Does NOT match: compatibility_override = null, or variable declarations with default = null
OVERRIDE_FILES=""
for file in $CHANGED_FILES; do
  if [ -f "$file" ] && grep -qE 'compatibility_override\s*=\s*"[^"]*"' "$file" 2>/dev/null; then
    OVERRIDE_FILES="$OVERRIDE_FILES $file"
  fi
done

if [ -n "$OVERRIDE_FILES" ]; then
  echo "compatibility_override detected in:$OVERRIDE_FILES"

  if echo "$PR_BODY" | grep -qE '(ADR-[0-9]+|[A-Z]{2,10}-[0-9]+)'; then
    echo "OK: ADR/JIRA reference found in PR description."
    exit 0
  else
    echo "ERROR: compatibility_override requires an ADR or JIRA reference in the PR description."
    echo "Add a reference like 'ADR-006' or 'PROJ-1234' to the PR body explaining the exception."
    exit 1
  fi
else
  echo "No compatibility_override detected in changed files."
  exit 0
fi
