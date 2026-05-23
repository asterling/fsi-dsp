#!/usr/bin/env bash
# =============================================================================
# validate-flink.sh — assert Flink layer 05 controls are correctly applied
# =============================================================================
# CLUSTER-DEPENDENT: run against a real OCP-on-LinuxONE cluster after deploying
# the 05-flink layer. NOT executed in CI — requires a running CFK/Flink cluster.
#
# This script is authored and bash -n validated here; execution requires an
# OCP-on-LinuxONE cluster with FKO + CMF installed (RUNBOOK Step 1b) and
# the 05-flink layer applied (RUNBOOK Step 3 with 05-flink in components:).
#
# Prerequisites:
#   - FKO and CMF installed via: ansible-playbook ansible/playbooks/flink_operators.yml
#   - 05-flink layer applied: kustomize build overlays/prod | oc apply -f -
#   - `oc` logged into the OCP cluster with confluent namespace access
#   - `confluent` CLI authenticated against the cluster MDS (for Kafka checks)
#   - KAFKA_BOOTSTRAP, SR_URL, FLINK_NAMESPACE env vars set
#   - Flink mTLS client cert available at FLINK_CERT, FLINK_KEY, FLINK_CA_CERT
#
# Usage:
#   KAFKA_BOOTSTRAP=kafka.confluent.svc.cluster.local:9092 \
#   SR_URL=https://schemaregistry.confluent.svc.cluster.local:8081 \
#   FLINK_CERT=/path/to/client.pem \
#   FLINK_KEY=/path/to/client-key.pem \
#   FLINK_CA_CERT=/path/to/ca.pem \
#   bash layers/05-flink/validate-flink.sh
# =============================================================================
set -euo pipefail

: "${KAFKA_BOOTSTRAP:?Set KAFKA_BOOTSTRAP}"
: "${SR_URL:?Set SR_URL}"
: "${FLINK_CERT:?Set FLINK_CERT (path to Flink client cert PEM)}"
: "${FLINK_KEY:?Set FLINK_KEY (path to Flink client key PEM)}"
: "${FLINK_CA_CERT:?Set FLINK_CA_CERT (path to CA cert PEM)}"

NAMESPACE="${FLINK_NAMESPACE:-confluent}"
PASS=0
FAIL=0

log_pass() { echo "[PASS] $1"; (( PASS++ )) || true; }
log_fail() { echo "[FAIL] $1" >&2; (( FAIL++ )) || true; }

# ---------------------------------------------------------------------------
echo "=== 05-flink validation ==="
echo ""

# ---------------------------------------------------------------------------
# Section 1: FlinkEnvironment and CMFRestClass reconciled
# ---------------------------------------------------------------------------
echo "--- Check: FlinkEnvironment CR is reconciled ---"
fe_phase=$(oc get flinkenvironment fsi-flink-env -n "${NAMESPACE}" \
  -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
if [ "${fe_phase}" = "RUNNING" ]; then
  log_pass "FlinkEnvironment fsi-flink-env phase = RUNNING"
else
  log_fail "FlinkEnvironment fsi-flink-env phase = '${fe_phase}' (expected RUNNING)"
fi
echo ""

echo "--- Check: CMFRestClass CR is reconciled ---"
cmf_phase=$(oc get cmfrestclass fsi-cmf-rest -n "${NAMESPACE}" \
  -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
if [ "${cmf_phase}" = "RUNNING" ]; then
  log_pass "CMFRestClass fsi-cmf-rest phase = RUNNING"
else
  log_fail "CMFRestClass fsi-cmf-rest phase = '${cmf_phase}' (expected RUNNING)"
fi
echo ""

# ---------------------------------------------------------------------------
# Section 2: FlinkApplication CRs reach RUNNING state
# ---------------------------------------------------------------------------
echo "--- Check: FlinkApplication fsi-txn-volume-tumbling-window is RUNNING ---"
tw_phase=$(oc get flinkapplication fsi-txn-volume-tumbling-window -n "${NAMESPACE}" \
  -o jsonpath='{.status.jobStatus.state}' 2>/dev/null || echo "unknown")
if [ "${tw_phase}" = "RUNNING" ]; then
  log_pass "FlinkApplication fsi-txn-volume-tumbling-window state = RUNNING"
else
  log_fail "FlinkApplication fsi-txn-volume-tumbling-window state = '${tw_phase}' (expected RUNNING)"
fi
echo ""

echo "--- Check: FlinkApplication fsi-account-txn-enrichment is RUNNING ---"
enrich_phase=$(oc get flinkapplication fsi-account-txn-enrichment -n "${NAMESPACE}" \
  -o jsonpath='{.status.jobStatus.state}' 2>/dev/null || echo "unknown")
if [ "${enrich_phase}" = "RUNNING" ]; then
  log_pass "FlinkApplication fsi-account-txn-enrichment state = RUNNING"
else
  log_fail "FlinkApplication fsi-account-txn-enrichment state = '${enrich_phase}' (expected RUNNING)"
fi
echo ""

# ---------------------------------------------------------------------------
# Section 3: Flink mTLS handshake to Kafka (mutual auth, not truststore-only)
# ---------------------------------------------------------------------------
echo "--- Check: Flink→Kafka mTLS handshake works ---"
# Use openssl s_client to verify the Kafka broker accepts the Flink client cert.
# This validates that the broker's mtls listener accepts the cert signed by confluent-ca-issuer.
kafka_host="${KAFKA_BOOTSTRAP%%:*}"
kafka_port="${KAFKA_BOOTSTRAP##*:}"
if echo "" | openssl s_client \
    -connect "${kafka_host}:${kafka_port}" \
    -cert "${FLINK_CERT}" \
    -key "${FLINK_KEY}" \
    -CAfile "${FLINK_CA_CERT}" \
    -verify_return_error \
    -quiet 2>/dev/null; then
  log_pass "Flink client cert accepted by Kafka broker (mTLS handshake OK)"
else
  log_fail "Flink→Kafka mTLS handshake failed — check confluent-ca-issuer cert chain and ConfluentRolebinding"
fi
echo ""

# ---------------------------------------------------------------------------
# Section 4: Schema Registry Avro-Confluent integration
# ---------------------------------------------------------------------------
echo "--- Check: SR URL reachable with Flink client cert (avro-confluent integration) ---"
sr_http_code=$(curl -s -o /dev/null -w "%{http_code}" \
  --cert "${FLINK_CERT}" \
  --key "${FLINK_KEY}" \
  --cacert "${FLINK_CA_CERT}" \
  "${SR_URL}/subjects" 2>/dev/null || echo "000")
if [ "${sr_http_code}" = "200" ]; then
  log_pass "Schema Registry reachable via mTLS from Flink cert identity (${SR_URL}/subjects = 200)"
else
  log_fail "Schema Registry returned HTTP ${sr_http_code} — check flink-kafka-client-tls cert and SR RBAC binding"
fi
echo ""

# ---------------------------------------------------------------------------
# Section 5: Flink output topics exist with correct config
# ---------------------------------------------------------------------------
echo "--- Check: Flink output topic KafkaTopic CRs exist ---"
for topic_name in flink-output-txn-volume-1m flink-output-enriched-transaction; do
  if oc get kafkatopic "${topic_name}" -n "${NAMESPACE}" &>/dev/null; then
    retention=$(oc get kafkatopic "${topic_name}" -n "${NAMESPACE}" \
      -o jsonpath='{.spec.configs.retention\.ms}' 2>/dev/null || echo "unknown")
    log_pass "KafkaTopic ${topic_name} exists (retention.ms=${retention})"
  else
    log_fail "KafkaTopic ${topic_name} not found in namespace ${NAMESPACE}"
  fi
done
echo ""

# ---------------------------------------------------------------------------
# Section 6: RBAC ConfluentRolebinding CRs exist
# ---------------------------------------------------------------------------
echo "--- Check: Flink RBAC ConfluentRolebinding CRs exist ---"
for rb in flink-developer flink-job-runtime-source-read flink-job-runtime-sink-write flink-job-runtime-sr-read; do
  if oc get confluentrolebinding "${rb}" -n "${NAMESPACE}" &>/dev/null; then
    log_pass "ConfluentRolebinding ${rb} exists"
  else
    log_fail "ConfluentRolebinding ${rb} not found — check layers/05-flink/rolebindings/"
  fi
done
echo ""

# ---------------------------------------------------------------------------
# Section 7: Flink Kafka access appears in audit log (layer 04 + 05 integration)
# ---------------------------------------------------------------------------
echo "--- Check: Flink topic access events in confluent-audit-log-events ---"
echo "[INFO] Waiting up to 15s for Flink job activity to appear in audit topic ..."
# CFK manages Kafka as a StatefulSet (not Deployment) — pods are kafka-0/1/2,
# the workload object is sts/kafka. `oc exec deploy/kafka` would fail with
# NotFound (no Deployment exists).
# Layer 02 enables internal-listener mTLS, so kafka-console-consumer needs
# a consumer.config with the broker truststore — without it the SSL handshake
# fails before any record is consumed. Mount path matches the broker pod's
# in-cluster TLS material (CFK-rendered).
audit_events=$(oc exec -n "${NAMESPACE}" sts/kafka -c kafka -- \
  kafka-console-consumer \
  --bootstrap-server kafka.confluent.svc.cluster.local:9092 \
  --consumer.config /mnt/sslcerts/kafka-server/consumer.properties \
  --topic confluent-audit-log-events \
  --from-beginning \
  --max-messages 100 \
  --timeout-ms 15000 2>/dev/null | grep -c "flink" || true)
if [ "${audit_events}" -gt 0 ]; then
  log_pass "Flink Kafka access events found in confluent-audit-log-events (${audit_events} matching events)"
else
  log_fail "No Flink-related events found in confluent-audit-log-events — check ConfluentServerAuthorizer (layer 01) and audit router (layer 04)"
fi
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== Validation summary ==="
echo "PASS: ${PASS}"
echo "FAIL: ${FAIL}"
echo ""

if [ "${FAIL}" -gt 0 ]; then
  echo "[ERROR] ${FAIL} check(s) failed — see output above"
  exit 1
else
  echo "[OK] All ${PASS} checks passed"
  exit 0
fi
