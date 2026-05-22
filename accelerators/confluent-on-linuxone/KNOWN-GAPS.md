# Known Gaps — s390x / LinuxONE Accelerator

This document registers every known gap, constraint, or limitation in the
`accelerators/confluent-on-linuxone/` tree. Each entry includes the gap, its
operational impact, the approved workaround, and current status.

---

## Gap Register

| # | Gap | Impact | Workaround | Status |
|---|-----|--------|------------|--------|
| G-01 | Fetch-by-SHA requires network access at activation | `flox activate` (and CI) requires outbound HTTPS to github.com | Pre-fetch in a network-accessible environment and artifact-cache `base/upstream/`; or configure OCP cluster egress to allow github.com access | Open |
| G-02 | FIPS only effective on FIPS-at-install OCP cluster | `spec.tls.fips.enabled: true` is a no-op on a non-FIPS OCP installation | OCP must be installed with `fips: true` in `install-config.yaml`; post-install FIPS is not supported by Red Hat | Open |
| G-03 | No native Dynatrace Kafka Connector | Dynatrace does not publish a first-party Kafka Connect connector | HTTP Sink connector (confluentinc/kafka-connect-http) POSTing to Dynatrace generic log ingest API v2; see `layers/04-audit/connect-cr.yaml` | Workaround in place |
| G-04 | Control Center next-gen s390x image availability unverified | C3 next-gen UI may not have a published s390x multi-arch image | Use Control Center classic (included in CP 8.2.0 s390x images) until next-gen image is verified; check `docker manifest inspect confluentinc/confluent-control-center:8.2.0` | Needs verification |
| G-05 | SR bootstrap Job base image must be s390x | `job-sr-bootstrap.yaml` image must run on s390x workers; standard `alpine` or `debian` images may lack s390x variants | Use `registry.access.redhat.com/ubi9/ubi-minimal:latest` — UBI9 has s390x multi-arch manifests; verify with `docker manifest inspect` before deploying | Workaround in place |
| G-06 | x86 node-agent sidecars (Splunk/DT) have QEMU overhead | Running x86 Splunk/Dynatrace forwarder agents as sidecars on s390x nodes uses QEMU binary translation — significant CPU penalty | Route audit events via Kafka Connect (Connect-based SIEM shipping) instead of node-agent sidecars; `layers/04-audit/connect-cr.yaml` implements this pattern | Mitigated by design |
| G-07 | Flox manifest.lock stub must be regenerated | `manifest.lock` in `.flox/env/` is a stub — actual Nix store paths are platform-specific | On a machine with Flox installed, run `flox activate` in `accelerators/confluent-on-linuxone/` to generate a real lock file; commit the result | Open |
| G-08 | Custom s390x Connect image required | `layers/04-audit/connect-cr.yaml` references a custom Connect image with Splunk Sink + HTTP Sink JARs pre-installed for s390x | Build with `docker buildx build --platform linux/s390x`; base image must be CP 8.2.0 Connect s390x image; JAR versions must match connector compatibility matrix | Open |
| G-09 | Cluster Linking schema sync (CP 8.2+) needs verification | Schema Registry Cluster Linking for automatic schema migration between clusters may have s390x-specific behavior | Test schema sync feature in a staging environment; fall back to manual SR migration tool if needed; see `MIGRATION.md` Section 2.4 | Needs verification |

---

## Gap Detail

### G-01: Fetch-by-SHA network access requirement

**Context:** Locked decision D-01 — upstream code is never committed. `base/fetch-upstream.sh`
clones `mmondics/Confluent-LinuxONE-Mirror` at a pinned SHA at activation time.

**Impact:** CI runners and developer machines must have outbound HTTPS access to
`github.com`. Air-gapped environments are not directly supported.

**Workaround options:**
1. **CI caching**: cache `base/upstream/` as a CI artifact keyed on `UPSTREAM_SHA`
   (most CI systems support artifact caches with SHA-based keys).
2. **Internal mirror**: mirror the upstream repo to an internal GitHub Enterprise or
   Gitea instance; update `UPSTREAM_REPO` in `fetch-upstream.sh` to point there.
3. **OCP egress policy**: ensure OCP cluster egress NetworkPolicy allows outbound HTTPS
   to github.com for CI runner pods.

---

### G-02: FIPS requires OCP installed in FIPS mode

**Context:** `spec.tls.fips.enabled: true` on CFK CRs instructs the CP Java process
to load IBM Semeru's `IBMJCEPlusFIPS` providers (or OpenJDK FIPS equivalent).

**Impact:** On a non-FIPS OCP cluster, this field is accepted by the CRD (no admission
rejection) but has no effect — the JVM does not load FIPS providers.

**Detection:** `oc get node -o json | jq '.items[0].status.nodeInfo.operatingSystem'`
and verify `fips_enabled=1` in `/proc/sys/crypto/fips_enabled` on a worker node.

**Consequence:** Deployments that skip FIPS-at-install and rely on `spec.tls.fips.enabled`
will silently fail FSI compliance. Verify OCP FIPS mode before applying layer 02.

---

### G-03: No native Dynatrace Kafka Connector

**Context:** Dynatrace does not publish a Confluent-certified Kafka Connect connector.
Monitoring `confluent-audit-log-events` via Dynatrace requires a bridge.

**Workaround:** `kafka-connect-http` (confluentinc) posts JSON batches to Dynatrace's
generic log ingest API v2 (`/api/v2/logs/ingest`). The payload is JSON-formatted audit
events; Dynatrace DPL rules extract structured attributes.

**Limitation:** HTTP Sink is not a purpose-built observability connector — there is no
built-in schema translation. Dynatrace log processing pipelines must be configured to
parse Confluent's audit event schema (documented in `observability/dynatrace/`).

---

### G-04: Control Center next-gen s390x image availability

**Context:** Confluent Control Center v2 ("next-gen") introduced a React-based UI.
Multi-arch s390x images for the next-gen UI may not be in the CP 8.2.0 release.

**Verification command:**
```bash
docker manifest inspect confluentinc/confluent-control-center:8.2.0 \
  | jq '.manifests[].platform | select(.architecture == "s390x")'
```

**Fallback:** Classic Control Center (the existing C3 image) is included in the
`confluentinc/confluent-control-center` multi-arch manifest and is s390x-supported.

---

### G-05: SR Bootstrap Job — s390x base image

**Context:** `layers/03-schema-governance/job-sr-bootstrap.yaml` runs a curl-based
REST initialization Job. The Job must run on s390x workers (node affinity set).

**Verification:**
```bash
docker manifest inspect registry.access.redhat.com/ubi9/ubi-minimal:latest \
  | jq '.manifests[].platform | select(.architecture == "s390x")'
```

UBI9 minimal has s390x in its multi-arch manifest. If the UBI9 image is unavailable
(air-gapped), build a custom `FROM scratch` + static curl binary for s390x.

---

### G-06: SIEM delivery via Connect, not node-agent sidecars

**Context:** Splunk and Dynatrace typically ship data from Kubernetes via host-level
agents (DaemonSets). On s390x nodes, x86 agent binaries require QEMU emulation
(qemu-user-static), which introduces 2-5x CPU overhead.

**Design mitigation:** This accelerator routes audit events via Kafka Connect Sink
connectors — arch-neutral Java running in s390x-native JVM with CPACF acceleration.
Do not add x86 agent sidecars to the CP pods.

---

### G-07: Flox manifest.lock stub

**Context:** Flox lock files contain Nix store paths which are platform-specific and
generated by the Flox daemon. The stub `manifest.lock` in `.flox/env/` is a placeholder.

**Regeneration:**
```bash
cd accelerators/confluent-on-linuxone
flox activate
# Flox resolves packages and writes the real manifest.lock
git add .flox/env/manifest.lock
git commit -m "chore(accelerator): regenerate Flox manifest.lock"
```

---

### G-08: Custom s390x Connect image

**Context:** `layers/04-audit/connect-cr.yaml` references a custom Connect image
(`<PLACEHOLDER_S390X_CONNECT_IMAGE>`) with Splunk Sink and HTTP Sink JARs pre-installed.

**Build process:**
```bash
docker buildx build \
  --platform linux/s390x \
  --build-arg BASE=confluentinc/confluent-kafka-connect:8.2.0 \
  -f connect.Dockerfile \
  -t <YOUR_REGISTRY>/fsi-connect-s390x:8.2.0 \
  --push .
```

The `connect.Dockerfile` should download connector JARs (arch-neutral Java) from
Confluent Hub and install them into the CFK Connect image base.
