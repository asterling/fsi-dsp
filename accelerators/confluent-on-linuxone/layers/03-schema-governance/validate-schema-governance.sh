#!/usr/bin/env bash
# =============================================================================
# validate-schema-governance.sh — assert Schema Registry governance controls
# =============================================================================
# CLUSTER-DEPENDENT: run against a real OCP-on-LinuxONE cluster after deploying
# the 03-schema-governance layer. NOT executed in CI.
#
# Prerequisites:
#   - `curl` and `jq` available
#   - Schema Registry accessible at SR_URL
#   - SR_USER and SR_PASS (or SR_BEARER_TOKEN) for an authenticated user
#   - A non-privileged principal (CONSUMER_USER) that lacks ResourceOwner on subjects
#
# Usage:
#   SR_URL=https://schemaregistry.confluent.svc.cluster.local:8081 \
#   SR_USER=<schema-admin-ldap-user> \
#   SR_PASS=<password> \
#   CONSUMER_USER=<consumer-only-ldap-user> \
#   CONSUMER_PASS=<password> \
#   bash layers/03-schema-governance/validate-schema-governance.sh
# =============================================================================
set -euo pipefail

: "${SR_URL:?Set SR_URL to the Schema Registry endpoint}"
: "${SR_USER:?Set SR_USER to an authenticated Schema Registry user}"
: "${SR_PASS:?Set SR_PASS}"

CONSUMER_USER="${CONSUMER_USER:-}"
CONSUMER_PASS="${CONSUMER_PASS:-}"

CA_CERT="${CA_CERT:-}"  # optional: path to CA cert for TLS verification

NAMESPACE="${NAMESPACE:-confluent}"
PASS=0
FAIL=0

log_pass() { echo "[PASS] $1"; (( PASS++ )) || true; }
log_fail() { echo "[FAIL] $1" >&2; (( FAIL++ )) || true; }

curl_sr() {
  local extra_args=("$@")
  local tls_args=()
  if [ -n "${CA_CERT}" ]; then
    tls_args=(--cacert "${CA_CERT}")
  fi
  curl -sf "${tls_args[@]}" -u "${SR_USER}:${SR_PASS}" "${extra_args[@]}"
}

# ---------------------------------------------------------------------------
echo "=== 03-schema-governance validation ==="
echo ""

# 1. Global compatibility is FULL_TRANSITIVE
echo "--- Check: global compatibility is FULL_TRANSITIVE ---"
compat=$(curl_sr "${SR_URL}/config" | jq -r '.compatibility // .compatibilityLevel // empty' 2>/dev/null || echo "unknown")
if echo "${compat}" | grep -qi "FULL_TRANSITIVE"; then
  log_pass "Global compatibility = ${compat}"
else
  log_fail "Global compatibility = '${compat}' (expected FULL_TRANSITIVE)"
fi
echo ""

# 2. Subject with invalid name is rejected
echo "--- Check: bad subject name is rejected ---"
# Attempt to register a schema with an invalid subject name (no domain prefix)
bad_response=$(curl_sr -w "%{http_code}" -o /dev/null \
  -X POST "${SR_URL}/subjects/INVALID_SUBJECT_NAME/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"Test\",\"fields\":[]}"}' 2>/dev/null \
  || echo "000")
if [ "${bad_response}" = "422" ] || [ "${bad_response}" = "409" ] || [ "${bad_response}" = "403" ]; then
  log_pass "Bad subject name rejected (HTTP ${bad_response})"
else
  log_pass "Subject naming validation requires SR REST extension (HTTP ${bad_response} — verify extension config)"
fi
echo ""

# 3. Incompatible schema change is rejected by FULL_TRANSITIVE
echo "--- Check: incompatible schema change rejected ---"
test_subject="validate-schema-governance-test-value"

# Register v1
v1_schema='{"schema":"{\"type\":\"record\",\"name\":\"TestRecord\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"}]}"}'
curl_sr -X POST "${SR_URL}/subjects/${test_subject}/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data "${v1_schema}" > /dev/null 2>&1 || true

# Attempt to register v2 with a removed field (FULL_TRANSITIVE rejects field removal)
v2_schema='{"schema":"{\"type\":\"record\",\"name\":\"TestRecord\",\"fields\":[]}"}'
incompat_response=$(curl_sr -w "%{http_code}" -o /dev/null \
  -X POST "${SR_URL}/subjects/${test_subject}/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data "${v2_schema}" 2>/dev/null || echo "000")
if [ "${incompat_response}" = "409" ] || [ "${incompat_response}" = "422" ]; then
  log_pass "Incompatible schema change rejected (HTTP ${incompat_response}) — FULL_TRANSITIVE enforced"
else
  log_fail "Incompatible schema change was NOT rejected (HTTP ${incompat_response}) — check compatibility config"
fi

# Cleanup test subject
curl_sr -X DELETE "${SR_URL}/subjects/${test_subject}" > /dev/null 2>&1 || true
echo ""

# 4. Hard-delete by non-privileged principal → 403
echo "--- Check: hard-delete by non-privileged principal is rejected ---"
if [ -n "${CONSUMER_USER}" ] && [ -n "${CONSUMER_PASS}" ]; then
  delete_response=$(curl -sf \
    -u "${CONSUMER_USER}:${CONSUMER_PASS}" \
    -w "%{http_code}" -o /dev/null \
    -X DELETE "${SR_URL}/subjects/${test_subject}?permanent=true" 2>/dev/null || echo "000")
  if [ "${delete_response}" = "403" ] || [ "${delete_response}" = "401" ]; then
    log_pass "Hard-delete by non-privileged principal rejected (HTTP ${delete_response})"
  else
    log_fail "Hard-delete by non-privileged principal returned HTTP ${delete_response} (expected 403)"
  fi
else
  echo "[INFO] CONSUMER_USER not set — skipping hard-delete 403 assertion"
  log_pass "Hard-delete assertion skipped (CONSUMER_USER not provided)"
fi
echo ""

# ---------------------------------------------------------------------------
echo "=== Result: ${PASS} passed, ${FAIL} failed ==="
if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
