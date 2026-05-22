---
phase: quick-260522-kjt
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ansible/roles/flink_operators/defaults/main.yml
  - ansible/roles/flink_operators/meta/main.yml
  - ansible/roles/flink_operators/tasks/main.yml
  - ansible/roles/flink_operators/tasks/deploy.yml
  - ansible/roles/flink_operators/tasks/check.yml
  - ansible/playbooks/flink_operators.yml
  - accelerators/confluent-on-linuxone/layers/05-flink/kustomization.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/flink-environment.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/cmfrestclass.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/secrets.template/cmf-mtls-credentials.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/secrets.template/flink-kafka-client-credentials.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/rolebindings/flink-developer.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/rolebindings/flink-job-runtime.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/tls/certificate-crs.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/applications/txn-volume-tumbling-window.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/applications/account-transaction-enrichment.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/topics/kafkatopic-flink-output.yaml
  - accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/Dockerfile
  - accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/README.md
  - accelerators/confluent-on-linuxone/layers/05-flink/validate-flink.sh
  - accelerators/confluent-on-linuxone/layers/05-flink/README.md
  - accelerators/confluent-on-linuxone/overlays/dev/kustomization.yaml
  - accelerators/confluent-on-linuxone/overlays/prod/kustomization.yaml
  - accelerators/confluent-on-linuxone/RUNBOOK.md
  - accelerators/confluent-on-linuxone/README.md
  - accelerators/confluent-on-linuxone/DESIGN.md
  - accelerators/confluent-on-linuxone/KNOWN-GAPS.md
  - .github/workflows/accelerator-linuxone.yml
autonomous: true
requirements: [QUICK-260522-kjt]

must_haves:
  truths:
    - "A developer can install FKO + CMF before kustomize build via a single readiness-gated Ansible role/playbook"
    - "layers/05-flink is a kind:Component that adds Flink CRs and patches nothing"
    - "kustomize build of both dev and prod overlays succeeds with 05-flink included"
    - "Layer 05 carries its own mTLS, RBAC, and topic governance — no Flink CRs leak into layers 01-04"
    - "Two example FSI FlinkApplication jobs are defined as CFK FlinkApplication CRs with SQL in ConfigMaps"
    - "Per-overlay patches size FlinkApplications differently (prod: EXACTLY_ONCE/30s/7y; dev: parallelism 1/60s/30d)"
    - "No real secrets committed — all credential files use <PLACEHOLDER>"
    - "Docs (RUNBOOK, README, DESIGN, KNOWN-GAPS) reflect the five-layer reality with G-10..G-13"
  artifacts:
    - path: "ansible/roles/flink_operators/tasks/main.yml"
      provides: "flink_operators role entry point routing check vs deploy"
    - path: "ansible/playbooks/flink_operators.yml"
      provides: "Playbook invoking the flink_operators role"
    - path: "accelerators/confluent-on-linuxone/layers/05-flink/kustomization.yaml"
      provides: "kind:Component for layer 05, resources-only"
      contains: "kind: Component"
    - path: "accelerators/confluent-on-linuxone/layers/05-flink/applications/txn-volume-tumbling-window.yaml"
      provides: "FlinkApplication CR + SQL ConfigMap for tumbling-window aggregation"
      contains: "kind: FlinkApplication"
    - path: "accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/Dockerfile"
      provides: "s390x cp-flink SQL-runner image definition (shipped, not built)"
    - path: "accelerators/confluent-on-linuxone/layers/05-flink/validate-flink.sh"
      provides: "cluster-dependent Flink layer validator"
  key_links:
    - from: "overlays/{dev,prod}/kustomization.yaml"
      to: "layers/05-flink"
      via: "components: list, appended last"
      pattern: "../../layers/05-flink"
    - from: "layers/05-flink/tls/certificate-crs.yaml"
      to: "layers/02-tls confluent-ca-issuer ClusterIssuer"
      via: "issuerRef referencing existing ClusterIssuer"
      pattern: "confluent-ca-issuer"
    - from: "layers/05-flink/applications/*.yaml"
      to: "topics/kafkatopic-flink-output.yaml"
      via: "FlinkApplication SQL sink table -> KafkaTopic CR"
      pattern: "FlinkApplication"
---

<objective>
Add Apache Flink as the fifth capability layer (`layers/05-flink/`) of the
`accelerators/confluent-on-linuxone/` accelerator, so the accelerator covers
governed stream processing — not just Kafka/SR/Connect — on CFK/OpenShift/s390x.

Purpose: Flink is the single CFK-supported s390x workload (CFK 3.2.0+ on s390x
supports only managing Flink Applications). Adding it is the best-grounded
capability the accelerator can offer on LinuxONE. The layer is purely additive
(a Kustomize `kind: Component` that patches nothing), self-contained for its own
mTLS/RBAC/topic governance, and modeled exactly on the existing four-layer
pattern.

Output:
- New shared Ansible role `ansible/roles/flink_operators/` + playbook (FKO + CMF
  Helm install, readiness-gated, check-mode) — RUNBOOK Step 1b.
- New `layers/05-flink/` Component tree: Flink CRs, hardening (mTLS/RBAC),
  example FSI jobs, output topics, SQL-runner image definition, validator, README.
- Overlay wiring in `overlays/{dev,prod}` with per-overlay FlinkApplication sizing.
- Updated docs: RUNBOOK, README, DESIGN, KNOWN-GAPS (G-10..G-13), CI workflow.

This plan implements the user-approved spec at
`/Users/jhogan/.claude/plans/look-into-planning-to-refactored-goose.md` exactly.
Its 8-step Implementation Sequence maps 1:1 to the 8 tasks below — one atomic
commit per step.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md

# THE APPROVED PLAN — authoritative spec. Implement exactly this.
@/Users/jhogan/.claude/plans/look-into-planning-to-refactored-goose.md

# Accelerator design (the layer/Component pattern being extended)
@accelerators/confluent-on-linuxone/DESIGN.md

# Patterns to mirror
@ansible/roles/cfk_operator/tasks/main.yml
@ansible/roles/cfk_operator/tasks/deploy.yml
@ansible/roles/cfk_operator/tasks/check.yml
@ansible/roles/cfk_operator/defaults/main.yml
@ansible/roles/cfk_operator/meta/main.yml
@accelerators/confluent-on-linuxone/layers/04-audit/kustomization.yaml
@accelerators/confluent-on-linuxone/layers/04-audit/kafkatopic-audit.yaml
@accelerators/confluent-on-linuxone/layers/01-rbac/rolebindings/producer-only.yaml
@accelerators/confluent-on-linuxone/overlays/prod/kustomization.yaml
@accelerators/confluent-on-linuxone/overlays/dev/kustomization.yaml
@.github/workflows/accelerator-linuxone.yml

# Reuse sources — re-shape, do NOT copy/edit in place
@reference/flink-sql/tumbling-window-aggregation.sql
@reference/flink-sql/stream-table-join-enrichment.sql
@scenarios/cfk-openshift/flink/examples/tumbling-window.yaml
@scenarios/cfk-openshift/flink/flink-docker/Dockerfile

<constraints>
ALL tasks must respect:
- s390x compatibility: every image/chart/tool must run on s390x. `cp-flink`,
  `cp-cmf`, `cp-flink-kubernetes-operator` are multi-arch with s390x. Apply the
  `kubernetes.io/arch: s390x` nodeSelector/affinity block where CR pods are scheduled.
- CFK CRDs are `platform.confluent.io/v1beta1`: `FlinkApplication`,
  `FlinkEnvironment`, `CMFRestClass`, `ConfluentRolebinding`, `KafkaTopic`.
- Version matrix: CP 8.2.0 / CFK 3.2.x / CMF 2.3.x / FKO 1.14.x / Apache Flink 1.20.x.
- NO secrets committed — every credential value is a literal `<PLACEHOLDER>`.
- Idempotent / declarative — Ansible tasks idempotent; CRs declarative.
- The SQL-runner image is SHIPPED as a `Dockerfile` + documented `docker buildx`
  step, NOT built in this work — mirrors the existing G-08 Connect-image gap.
- Cluster-dependent validators (`validate-flink.sh`) are authored + `bash -n`
  checked here, but EXECUTED by a developer against a real OCP-on-LinuxONE cluster.
- 05-flink Component has `resources:` only — NO `patches:` (Flink is a Kafka
  client; there is no existing CR field to merge-patch).
- Self-contained hardening — NO Flink patches into layers 01-04.
- Reuse re-shaped: `reference/flink-sql/` SQL and `scenarios/cfk-openshift/flink/`
  image pattern become CFK `FlinkApplication` CRs — NOT upstream `FlinkDeployment`.
- Namespace `confluent` (the overlay's single global namespace).
</constraints>
</context>

<tasks>

<task type="auto">
  <name>Task 1: flink_operators Ansible role + playbook (FKO + CMF Helm install)</name>
  <files>
    ansible/roles/flink_operators/defaults/main.yml
    ansible/roles/flink_operators/meta/main.yml
    ansible/roles/flink_operators/tasks/main.yml
    ansible/roles/flink_operators/tasks/deploy.yml
    ansible/roles/flink_operators/tasks/check.yml
    ansible/playbooks/flink_operators.yml
  </files>
  <action>
    Implements approved-plan Implementation Sequence step 1 + Decision 1 (new
    shared `ansible/roles/flink_operators`, modeled on `ansible/roles/cfk_operator`).

    Create `ansible/roles/flink_operators/` as a sibling of `cfk_operator`,
    mirroring its structure exactly:
    - `defaults/main.yml`: Helm settings for BOTH operators (FKO + CMF are two
      separate Helm charts). Vars: `flink_helm_repo_name: confluentinc`,
      `flink_helm_repo_url: https://packages.confluent.io/helm`,
      `fko_helm_chart_ref: confluentinc/flink-kubernetes-operator`,
      `fko_helm_chart_version` (FKO 1.14.x line),
      `cmf_helm_chart_ref: confluentinc/confluent-manager-for-apache-flink`,
      `cmf_helm_chart_version` (CMF 2.3.x line),
      `flink_namespace: confluent`, `flink_helm_wait_timeout: "600s"`,
      readiness polling vars (`flink_readiness_retries: 30`,
      `flink_readiness_delay: 20`). Comment each var with WHY per project style.
      Add a comment noting chart versions/names should be confirmed against
      `packages.confluent.io/helm` at deploy time (CP 8.2.0 pairing).
    - `meta/main.yml`: galaxy_info clone of cfk_operator's, `role_name:
      flink_operators`, description "Deploy FKO + CMF Flink operators on OpenShift
      via Helm", `dependencies: []`, EL 8/9 platforms, tags kafka/confluent/flink/
      openshift/kubernetes.
    - `tasks/main.yml`: same routing pattern as cfk_operator/tasks/main.yml —
      include `check.yml` when `ansible_check_mode | bool`, else include
      `deploy.yml`. (No apply_crs.yml — Flink CRs are applied via Kustomize, not
      this role.)
    - `tasks/deploy.yml`: `kubernetes.core.helm_repository` to add the confluentinc
      repo, then TWO `kubernetes.core.helm` installs — FKO first, then CMF — each
      with `wait: true`, `wait_timeout`, `create_namespace: true`,
      `release_namespace: "{{ flink_namespace }}"`. Register results, debug-report
      each. FKO before CMF (CMF depends on the FKO CRDs being present).
    - `tasks/check.yml`: GET-only audit — `kubernetes.core.helm_info` for both
      releases + `kubernetes.core.k8s_info` for `FlinkApplication`,
      `FlinkEnvironment`, `CMFRestClass` (api_version `platform.confluent.io/v1beta1`),
      all with `check_mode: false` + `changed_when: false`, debug-reporting counts/
      phases — exact pattern from cfk_operator/tasks/check.yml.
    - `ansible/playbooks/flink_operators.yml`: minimal playbook (match the style of
      existing `ansible/playbooks/deploy-cfk.yml`) — hosts target, `roles:
      [flink_operators]`.
  </action>
  <verify>
    <automated>cd /Users/jhogan/fsi-kafka-platform && ansible-lint ansible/roles/flink_operators ansible/playbooks/flink_operators.yml && python3 -c "import yaml,glob; [yaml.safe_load(open(f)) for f in glob.glob('ansible/roles/flink_operators/**/*.yml',recursive=True)+['ansible/playbooks/flink_operators.yml']]; print('YAML OK')"</automated>
  </verify>
  <done>
    `ansible/roles/flink_operators/` exists with defaults/meta/tasks{main,deploy,
    check}; playbook exists; `ansible-lint` is clean; all YAML parses; deploy.yml
    installs FKO then CMF readiness-gated; check.yml is GET-only.
  </done>
  <commit>feat(accelerator): add flink_operators Ansible role for FKO + CMF Helm install</commit>
</task>

<task type="auto">
  <name>Task 2: layers/05-flink Component scaffold (Component + FlinkEnvironment + CMFRestClass + secrets)</name>
  <files>
    accelerators/confluent-on-linuxone/layers/05-flink/kustomization.yaml
    accelerators/confluent-on-linuxone/layers/05-flink/flink-environment.yaml
    accelerators/confluent-on-linuxone/layers/05-flink/cmfrestclass.yaml
    accelerators/confluent-on-linuxone/layers/05-flink/secrets.template/cmf-mtls-credentials.yaml
    accelerators/confluent-on-linuxone/layers/05-flink/secrets.template/flink-kafka-client-credentials.yaml
  </files>
  <action>
    Implements approved-plan Implementation Sequence step 2 + Decision 2
    (Kustomize Component, purely additive).

    - `kustomization.yaml`: `apiVersion: kustomize.config.k8s.io/v1alpha1`,
      `kind: Component`. `resources:` ONLY — list every yaml file the layer
      provides (flink-environment.yaml, cmfrestclass.yaml, rolebindings/*.yaml,
      tls/certificate-crs.yaml, applications/*.yaml, topics/*.yaml — include
      Task 3/4 paths now so the Component is complete after this plan).
      NO `patches:` block. Header comment block in the 04-audit style:
      explain this is layer 05, additive, depends on layer 01 MDS + layer 02
      cert ClusterIssuer/broker mTLS listener, hence appended LAST in overlays.
      `secrets.template/` files are NOT in `resources:` (templates, not applied).
    - `flink-environment.yaml`: `FlinkEnvironment` CR (`platform.confluent.io/
      v1beta1`), `namespace: confluent`. Spec configures the Flink cluster context
      CMF manages — Flink defaults, the `kubernetes.io/arch: s390x` node affinity
      block (sourced from `scenarios/cfk-openshift-linuxone/values/kafka.yaml`
      affinity pattern). Comment WHY each block exists.
    - `cmfrestclass.yaml`: `CMFRestClass` CR (`platform.confluent.io/v1beta1`),
      `namespace: confluent`. `spec.cmfRest.endpoint` (CMF service URL),
      `authentication.type: mtls`, `tls.secretRef: cmf-mtls-credentials` — the
      mTLS channel CFK<->CMF. Comment that this is the governed control path.
    - `secrets.template/cmf-mtls-credentials.yaml`: K8s Secret template for the
      CMF mTLS cert/key/CA — every value a literal `<PLACEHOLDER>` (mirror
      `layers/02-tls/secrets.template/component-certs.yaml` style).
    - `secrets.template/flink-kafka-client-credentials.yaml`: K8s Secret template
      for the Flink->Kafka mutual-TLS keystore/truststore — all `<PLACEHOLDER>`.
    Use `confluent` namespace everywhere.
  </action>
  <verify>
    <automated>cd /Users/jhogan/fsi-kafka-platform && python3 -c "import yaml,glob; [list(yaml.safe_load_all(open(f))) for f in glob.glob('accelerators/confluent-on-linuxone/layers/05-flink/**/*.yaml',recursive=True)]; print('YAML OK')" && grep -q 'kind: Component' accelerators/confluent-on-linuxone/layers/05-flink/kustomization.yaml && ! grep -q '^patches:' accelerators/confluent-on-linuxone/layers/05-flink/kustomization.yaml && for f in accelerators/confluent-on-linuxone/layers/05-flink/secrets.template/*.yaml; do grep -q PLACEHOLDER "$f" || { echo "FAIL: $f has no PLACEHOLDER"; exit 1; }; done && echo "secrets OK"</automated>
  </verify>
  <done>
    Component kustomization is `kind: Component` with `resources:` only (no
    `patches:`); FlinkEnvironment + CMFRestClass CRs are valid v1beta1 YAML;
    both secrets.template files contain only `<PLACEHOLDER>` values.
  </done>
  <commit>feat(accelerator): scaffold layers/05-flink Component with Flink CRs and secret templates</commit>
</task>

<task type="auto">
  <name>Task 3: layers/05-flink hardening (RBAC rolebindings + mTLS Certificate CRs)</name>
  <files>
    accelerators/confluent-on-linuxone/layers/05-flink/rolebindings/flink-developer.yaml
    accelerators/confluent-on-linuxone/layers/05-flink/rolebindings/flink-job-runtime.yaml
    accelerators/confluent-on-linuxone/layers/05-flink/tls/certificate-crs.yaml
  </files>
  <action>
    Implements approved-plan Implementation Sequence step 3 + Decision 3
    (self-contained hardening — these CRs live INSIDE layer 05, no patches into
    layers 01-04).

    - `rolebindings/flink-developer.yaml`: `ConfluentRolebinding` CR
      (`platform.confluent.io/v1beta1`). Principal `type: group` bound to an LDAP
      group placeholder `<PLACEHOLDER_FLINK_DEVELOPER_LDAP_GROUP>` — the role that
      submits/manages FlinkApplications. Bind to LDAP groups, NEVER individuals
      (the IdP is the identity boundary — same convention as layers/01-rbac
      rolebindings). Comment the FSI rationale (segregation of duties).
    - `rolebindings/flink-job-runtime.yaml`: `ConfluentRolebinding` CR(s) for the
      least-privilege job runtime principal. Grant exactly: `DeveloperRead` on the
      source topic prefix, `DeveloperWrite` on the sink topic prefix, and
      `DeveloperRead` on the relevant Schema Registry subjects — three resource
      patterns, least privilege (mirror the producer-only.yaml resourcePatterns
      shape). Principal is a service-account placeholder. Comment WHY each grant.
    - `tls/certificate-crs.yaml`: cert-manager `Certificate` CRs — `cmf-tls` and
      `flink-kafka-client-tls`. Each `issuerRef` MUST reference layer 02's
      EXISTING `confluent-ca-issuer` ClusterIssuer by name (kind: ClusterIssuer) —
      reference it, do NOT redefine/duplicate the issuer (it is cluster-scoped).
      `secretName` matches the secrets used by cmfrestclass.yaml (Task 2) and the
      FlinkApplications (Task 4). dnsNames cover the CMF + Flink client identities.
      Comment that this reuses layer 02's CA chain so Flink mTLS shares the same
      trust root as the brokers.
    Add all three files to `layers/05-flink/kustomization.yaml` `resources:` if
    not already listed in Task 2.
  </action>
  <verify>
    <automated>cd /Users/jhogan/fsi-kafka-platform && python3 -c "import yaml,glob; [list(yaml.safe_load_all(open(f))) for f in glob.glob('accelerators/confluent-on-linuxone/layers/05-flink/rolebindings/*.yaml')+glob.glob('accelerators/confluent-on-linuxone/layers/05-flink/tls/*.yaml')]; print('YAML OK')" && grep -q 'confluent-ca-issuer' accelerators/confluent-on-linuxone/layers/05-flink/tls/certificate-crs.yaml && grep -q 'ConfluentRolebinding' accelerators/confluent-on-linuxone/layers/05-flink/rolebindings/flink-developer.yaml</automated>
  </verify>
  <done>
    Two ConfluentRolebinding CRs (flink-developer LDAP-group-bound, flink-job-runtime
    least-privilege) and a Certificate-CR file referencing the existing
    `confluent-ca-issuer` ClusterIssuer all parse as valid v1beta1 YAML; no Flink
    CRs were added to layers 01-04.
  </done>
  <commit>feat(accelerator): add self-contained RBAC and mTLS hardening to layers/05-flink</commit>
</task>

<task type="auto">
  <name>Task 4: layers/05-flink example FlinkApplications + SQL ConfigMaps + output topics</name>
  <files>
    accelerators/confluent-on-linuxone/layers/05-flink/applications/txn-volume-tumbling-window.yaml
    accelerators/confluent-on-linuxone/layers/05-flink/applications/account-transaction-enrichment.yaml
    accelerators/confluent-on-linuxone/layers/05-flink/topics/kafkatopic-flink-output.yaml
  </files>
  <action>
    Implements approved-plan Implementation Sequence step 4 + Decision 4 (reuse,
    re-shaped — express the FSI SQL patterns as CFK `FlinkApplication` CRs, NOT
    upstream `FlinkDeployment`).

    - `applications/txn-volume-tumbling-window.yaml`: TWO documents in one file —
      (a) a `FlinkApplication` CR (`platform.confluent.io/v1beta1`, `namespace:
      confluent`) and (b) a `ConfigMap` holding the SQL. Port
      `reference/flink-sql/tumbling-window-aggregation.sql` (and the CFK CREATE
      TABLE shape from `scenarios/cfk-openshift/flink/examples/tumbling-window.yaml`)
      into the ConfigMap. The FlinkApplication spec: `spec.flinkEnvironment`
      referencing the FlinkEnvironment from Task 2; `spec.image:
      <PLACEHOLDER_CP_FLINK_SQL_RUNNER_IMAGE>`; `spec.job.{jarURI (the
      fsi-sql-runner jar path), state: running, parallelism, upgradeMode:
      savepoint}`; `flinkConfiguration` for checkpointing + an encrypted
      `state.checkpoints.dir` (point at an encrypted StorageClass / SSE location —
      reference G-13). SQL `WITH(...)` clauses use MUTUAL TLS to Kafka (keystore +
      truststore, not truststore-only) and an `https://` `avro-confluent` SR URL
      (layer 02 mTLS'd SR). Mount the SQL ConfigMap into the job. Apply the
      `kubernetes.io/arch: s390x` affinity block.
    - `applications/account-transaction-enrichment.yaml`: same two-document shape
      for the temporal/stream-table join — port
      `reference/flink-sql/stream-table-join-enrichment.sql`.
    - `topics/kafkatopic-flink-output.yaml`: `KafkaTopic` CR(s) for the Flink job
      OUTPUT topics (the windowed + enriched sink topics referenced by the SQL
      sink tables). Model on `layers/04-audit/kafkatopic-audit.yaml`: explicit
      `replicas: 3`, `partitionCount`, `min.insync.replicas: "2"`,
      `cleanup.policy`. Retention via overlay-substitutable var so the per-overlay
      patches (Task 6) can set 7y prod / 30d dev — use a `$(FLINK_OUTPUT_RETENTION_MS)`
      style token consistent with the audit topic's `$(AUDIT_RETENTION_MS)`.
    All values that are registry/secret/credential = `<PLACEHOLDER>`. Ensure these
    three files are in the Component `resources:` list.
  </action>
  <verify>
    <automated>cd /Users/jhogan/fsi-kafka-platform && python3 -c "import yaml,glob; docs=[d for f in glob.glob('accelerators/confluent-on-linuxone/layers/05-flink/applications/*.yaml')+glob.glob('accelerators/confluent-on-linuxone/layers/05-flink/topics/*.yaml') for d in yaml.safe_load_all(open(f))]; kinds={d['kind'] for d in docs if d}; assert 'FlinkApplication' in kinds and 'ConfigMap' in kinds and 'KafkaTopic' in kinds, kinds; assert 'FlinkDeployment' not in kinds; print('kinds OK', kinds)"</automated>
  </verify>
  <done>
    Two FlinkApplication CRs (each with a paired SQL ConfigMap) and the output
    KafkaTopic CR(s) parse as valid v1beta1 YAML; SQL uses mutual TLS to Kafka and
    https SR; retention is overlay-substitutable; no FlinkDeployment kind present.
  </done>
  <commit>feat(accelerator): add FSI example FlinkApplications, SQL ConfigMaps, and output topics</commit>
</task>

<task type="auto">
  <name>Task 5: layers/05-flink SQL-runner image (Dockerfile + README), validate-flink.sh, layer README</name>
  <files>
    accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/Dockerfile
    accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/README.md
    accelerators/confluent-on-linuxone/layers/05-flink/validate-flink.sh
    accelerators/confluent-on-linuxone/layers/05-flink/README.md
  </files>
  <action>
    Implements approved-plan Implementation Sequence step 5 + G-12 (custom s390x
    SQL-runner image shipped as a Dockerfile, NOT built here — mirrors the G-08
    Connect-image gap).

    - `sql-runner/Dockerfile`: re-base `scenarios/cfk-openshift/flink/flink-docker/
      Dockerfile` onto the s390x `cp-flink` 1.20.x image. Layer in the SQL-runner
      jar and the pinned connector JARs — `flink-sql-connector-kafka` +
      `flink-sql-avro-confluent-registry` (versions matched to Flink 1.20.x).
      Comment the JAR version matrix. This file is SHIPPED, not built by this work.
    - `sql-runner/README.md`: the `docker buildx build --platform linux/s390x ...`
      instructions, the JAR version matrix table, registry/push guidance, and an
      explicit note that the image must be built and pushed to a `<PLACEHOLDER>`
      registry by the developer before applying the FlinkApplications (cross-link
      G-12).
    - `validate-flink.sh`: a cluster-dependent validator (model on
      `layers/04-audit/validate-audit.sh` structure — `set -euo pipefail`,
      section-separator comments, snake_case). Checks: FlinkEnvironment + CMFRestClass
      reconciled; both example FlinkApplications reach `RUNNING`; Flink->Kafka mTLS
      handshake works; SR (`avro-confluent`) integration works; test records produce
      windowed/enriched output on the sink topics. Header comment MUST state it is
      run by a developer against a real OCP-on-LinuxONE cluster, NOT in CI.
    - `README.md` (layer 05): FSI rationale — stream-processing governance,
      exactly-once for regulatory reporting, checkpoint-state encryption (G-13).
      Document: the three Flink CRs; self-contained mTLS/RBAC; that layer 04
      audits Flink's Kafka access automatically (Flink authenticates via mTLS +
      ConfluentServerAuthorizer) so NO layer-04 change is needed; Flink
      job-lifecycle auditing via the OCP audit log / GitOps trail; the mandated
      encrypted StorageClass / SSE for `state.checkpoints.dir`; cross-links to
      `observability/grafana/dashboard-flink-jobs.json` and the Prometheus reporter
      on port 9249; the single-namespace `confluent` decision with multi-namespace
      noted as a variant. Match the dense, technical, no-marketing style of the
      other layer READMEs.
  </action>
  <verify>
    <automated>cd /Users/jhogan/fsi-kafka-platform && bash -n accelerators/confluent-on-linuxone/layers/05-flink/validate-flink.sh && test -f accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/Dockerfile && test -f accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/README.md && test -f accelerators/confluent-on-linuxone/layers/05-flink/README.md && echo "files OK"</automated>
  </verify>
  <done>
    Dockerfile + sql-runner README ship the buildx-built s390x image (not built
    here); `validate-flink.sh` passes `bash -n` and is documented as
    cluster-run-only; layer README covers FSI rationale, the audit-by-layer-04
    note, and G-13 state encryption.
  </done>
  <commit>feat(accelerator): add Flink SQL-runner image definition, validator, and layer README</commit>
</task>

<task type="auto">
  <name>Task 6: Wire layer 05 into overlays/{dev,prod} with per-overlay FlinkApplication patches</name>
  <files>
    accelerators/confluent-on-linuxone/overlays/dev/kustomization.yaml
    accelerators/confluent-on-linuxone/overlays/prod/kustomization.yaml
  </files>
  <action>
    Implements approved-plan Implementation Sequence step 6 + the Composition
    section (05-flink appended LAST; per-overlay FlinkApplication sizing patches).

    Both overlays — append `../../layers/05-flink` to the `components:` list as
    the LAST entry (after `04-audit`). Update the header-comment block to mention
    the now-five components and that 05 is last because it depends on layer 02's
    cert ClusterIssuer + broker mTLS listener and layer 01's MDS.

    `overlays/prod/kustomization.yaml` — add `patches:` targeting `kind:
    FlinkApplication` (same JSON6902 mechanism as the existing audit/SR/Kafka-replica
    patches): production sizing — `EXACTLY_ONCE` processing semantics, parallelism
    increased, 30s checkpoint interval — plus a patch targeting the Flink output
    `KafkaTopic` retention set to 7y (`220752000000`), consistent with how the
    audit topic retention is patched at prod kustomization line ~37.

    `overlays/dev/kustomization.yaml` — add `patches:` targeting `kind:
    FlinkApplication`: dev sizing — parallelism 1, 60s checkpoint interval — plus a
    patch targeting the Flink output `KafkaTopic` retention 30d (`2592000000`),
    consistent with the dev audit retention patch at dev kustomization line ~28.

    Do NOT alter the existing 01-04 component entries or existing patches.
  </action>
  <verify>
    <automated>cd /Users/jhogan/fsi-kafka-platform && python3 -c "import yaml; [print(e, yaml.safe_load(open('accelerators/confluent-on-linuxone/overlays/%s/kustomization.yaml'%e))['components'][-1]) for e in ['dev','prod']]" && grep -q '../../layers/05-flink' accelerators/confluent-on-linuxone/overlays/dev/kustomization.yaml && grep -q '../../layers/05-flink' accelerators/confluent-on-linuxone/overlays/prod/kustomization.yaml && grep -q 'FlinkApplication' accelerators/confluent-on-linuxone/overlays/prod/kustomization.yaml && grep -q 'FlinkApplication' accelerators/confluent-on-linuxone/overlays/dev/kustomization.yaml</automated>
  </verify>
  <done>
    Both overlays list `../../layers/05-flink` as the LAST component; prod has
    FlinkApplication patches (EXACTLY_ONCE, higher parallelism, 30s checkpoints,
    7y output retention); dev has FlinkApplication patches (parallelism 1, 60s
    checkpoints, 30d retention); existing 01-04 wiring untouched.
  </done>
  <commit>feat(accelerator): wire layer 05-flink into dev and prod overlays with sizing patches</commit>
</task>

<task type="auto">
  <name>Task 7: Docs — RUNBOOK, README, DESIGN, KNOWN-GAPS (G-10..G-13), CI workflow</name>
  <files>
    accelerators/confluent-on-linuxone/RUNBOOK.md
    accelerators/confluent-on-linuxone/README.md
    accelerators/confluent-on-linuxone/DESIGN.md
    accelerators/confluent-on-linuxone/KNOWN-GAPS.md
    .github/workflows/accelerator-linuxone.yml
  </files>
  <action>
    Implements approved-plan Implementation Sequence step 7 + Decision 5 (G-10
    constraint relaxation) + Decision 7 (DESIGN.md updated in place).

    - `RUNBOOK.md`: insert a new **Step 1b** right after Step 1 (CFK operator
      install) — "Install FKO + CMF" via `ansible-playbook ansible/playbooks/
      flink_operators.yml`, readiness-gated, with the `--check` audit-mode note.
      Insert a new **Step 10** — run `layers/05-flink/validate-flink.sh` against
      the cluster. Add troubleshooting rows for Flink (FlinkApplication stuck
      pending, CMF mTLS handshake failure, missing SQL-runner image). Clearly mark
      these as GoodLabs additions, matching how the existing FSI steps are marked.
    - `README.md`: add a **Layer 05 — Flink** section to the hardening-layers list
      with FSI rationale (stream-processing governance, exactly-once for regulatory
      reporting). Add a provenance-table row (GoodLabs addition; not in Mondics
      upstream). Note the FKO+CMF Helm prerequisite. Update any "four layers"
      phrasing to "five layers".
    - `DESIGN.md`: update IN PLACE to the now-five-layer reality — extend the
      directory-structure block with `layers/05-flink/`, add a `### 5.
      layers/05-flink/ — Flink stream processing` subsection under "Layer detail"
      summarizing the CRs/hardening/composition, and update the composition and
      "four components" phrasing to five. Preserve the committed-design-record
      header.
    - `KNOWN-GAPS.md`: add G-10 (FKO + CMF parallel Helm operators — overlay is no
      longer a self-sufficient `kustomize build` when 05 is on; mitigated by the
      `flink_operators` role + RUNBOOK Step 1b), G-11 (verbatim Confluent
      statement: CFK 3.2.0+ on s390x supported only for managing Flink Applications
      — layers 01-04 are run-at-your-own-risk; informational), G-12 (custom s390x
      SQL-runner image required — workaround `sql-runner/Dockerfile` + buildx),
      G-13 (Flink checkpoint state encryption — encrypted StorageClass / SSE;
      cluster-dependent verification item). Match the existing gap-entry format.
    - `.github/workflows/accelerator-linuxone.yml`: no structural change needed —
      the `kustomize build overlays/{dev,prod}` jobs already build the overlays
      that now include 05-flink, the `bash -n` job already globs all `*.sh` (picks
      up validate-flink.sh), the secrets.template scan already globs all
      `*/secrets.template/*.yaml`, and the kind:Component check already loops all
      `layers/*/`. Update the workflow header comment to mention layer 05 / Flink
      and add `validate-flink.sh` to the "cluster-dependent validators NOT run in
      CI" note. Confirm via the verify command that 05 is exercised.
  </action>
  <verify>
    <automated>cd /Users/jhogan/fsi-kafka-platform && grep -q 'G-10' accelerators/confluent-on-linuxone/KNOWN-GAPS.md && grep -q 'G-13' accelerators/confluent-on-linuxone/KNOWN-GAPS.md && grep -qi 'flink' accelerators/confluent-on-linuxone/RUNBOOK.md && grep -qi 'flink' accelerators/confluent-on-linuxone/README.md && grep -q '05-flink' accelerators/confluent-on-linuxone/DESIGN.md && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/accelerator-linuxone.yml')); print('CI YAML OK')"</automated>
  </verify>
  <done>
    RUNBOOK has Step 1b (FKO+CMF) and Step 10 (validate-flink) + Flink
    troubleshooting rows; README has a Layer 05 section + provenance row; DESIGN
    reflects five layers in place; KNOWN-GAPS has G-10/G-11/G-12/G-13; CI workflow
    header mentions Flink and parses as valid YAML.
  </done>
  <commit>docs(accelerator): document layer 05-flink in RUNBOOK, README, DESIGN, KNOWN-GAPS</commit>
</task>

<task type="auto">
  <name>Task 8: Validate — kustomize build both overlays, ansible-lint, bash -n</name>
  <files>
    (no new files — validation pass; fix any failures in the files above)
  </files>
  <action>
    Implements approved-plan Implementation Sequence step 8 (final validation).

    Run the full validation suite the approved plan's Verification section
    specifies. If anything fails, FIX the offending file from Tasks 1-7 (this task
    may amend earlier files) — do not paper over failures.

    1. `kustomize build` BOTH overlays with 05-flink included. This requires the
       upstream base to be populated first — run `base/fetch-upstream.sh` if
       `base/upstream/` is empty (it is gitignored). If outbound network is
       unavailable in the execution environment, document that `kustomize build`
       was not run here and MUST be run by the developer per RUNBOOK.md — but
       still confirm the 05-flink Component and overlay YAML parse standalone
       (`kustomize build` is also exercised by CI on PR).
    2. `ansible-lint ansible/roles/flink_operators` — clean.
    3. `bash -n` on `validate-flink.sh` and `sql-runner/` shell scripts (and any
       other new `*.sh`).
    4. Confirm every `secrets.template/*.yaml` contains `<PLACEHOLDER>` (no real
       credentials), and the 05-flink kustomization is `kind: Component` with no
       `patches:`.

    Record the validation results in the plan SUMMARY. This task commits only if
    a fix was needed; if everything is already clean, note "validation pass — no
    changes" and skip the commit.
  </action>
  <verify>
    <automated>cd /Users/jhogan/fsi-kafka-platform/accelerators/confluent-on-linuxone && (test -d base/upstream && bash -c 'command -v kustomize >/dev/null && kustomize build overlays/dev >/dev/null && kustomize build overlays/prod >/dev/null && echo "kustomize build OK"' || echo "kustomize build SKIPPED — base/upstream absent or kustomize missing; CI + developer run it") && cd /Users/jhogan/fsi-kafka-platform && ansible-lint ansible/roles/flink_operators && find accelerators/confluent-on-linuxone/layers/05-flink -name '*.sh' -exec bash -n {} \; && echo "validation suite OK"</automated>
  </verify>
  <done>
    `ansible-lint` on `flink_operators` is clean; `bash -n` passes on all layer-05
    shell scripts; `kustomize build` of both overlays succeeds when `base/upstream/`
    is present (or is explicitly deferred to CI/developer with a recorded reason);
    no secrets without `<PLACEHOLDER>`; 05-flink is `kind: Component` with no
    `patches:`.
  </done>
  <commit>chore(accelerator): validate layer 05-flink — kustomize build, ansible-lint, bash -n</commit>
</task>

</tasks>

<verification>
Phase-level checks (the approved plan's Verification section):
- `kustomize build overlays/{dev,prod}` succeeds with `05-flink` included (after
  `base/fetch-upstream.sh`); CI's `accelerator-linuxone.yml` also exercises this
  on PR.
- `bash -n` passes on `validate-flink.sh` and `sql-runner/` scripts; all layer-05
  YAML parses.
- `ansible-lint ansible/roles/flink_operators` is clean; the role's `check.yml`
  path is GET-only (safe for `--check`).
- 05-flink `kustomization.yaml` is `kind: Component` with `resources:` only — no
  `patches:`; no Flink CRs were added to layers 01-04.
- Every `secrets.template/*.yaml` contains only `<PLACEHOLDER>` values.
- Cluster-dependent end-to-end (developer, on OCP-on-LinuxONE): RUNBOOK Step 1b
  installs FKO+CMF → `kustomize build overlays/prod | oc apply -f -` →
  FlinkEnvironment/CMFRestClass reconcile → both FlinkApplications reach RUNNING →
  `validate-flink.sh` confirms job status, Kafka mTLS, SR integration → Flink's
  Kafka access appears in `confluent-audit-log-events`.
</verification>

<success_criteria>
- `ansible/roles/flink_operators/` + `ansible/playbooks/flink_operators.yml` exist,
  install FKO then CMF readiness-gated, support `--check` mode, `ansible-lint` clean.
- `accelerators/confluent-on-linuxone/layers/05-flink/` exists as a complete
  `kind: Component` (resources-only, no patches) with FlinkEnvironment, CMFRestClass,
  rolebindings, TLS Certificate CRs, two example FlinkApplications + SQL ConfigMaps,
  output KafkaTopic CR(s), SQL-runner Dockerfile + README, validate-flink.sh, README.
- Both `overlays/{dev,prod}` list `../../layers/05-flink` LAST in `components:` with
  per-overlay FlinkApplication sizing patches (prod EXACTLY_ONCE/30s/7y; dev
  parallelism 1/60s/30d).
- RUNBOOK (Step 1b + Step 10 + troubleshooting), README (Layer 05 + provenance),
  DESIGN (five-layer, in place), KNOWN-GAPS (G-10..G-13), CI workflow header all updated.
- No secrets committed (all `<PLACEHOLDER>`); SQL-runner image shipped as a
  Dockerfile, not built; all 7 locked decisions honored; 8 atomic commits, one per
  Implementation Sequence step.
</success_criteria>

<output>
After completion, create
`.planning/quick/260522-kjt-add-apache-flink-as-layer-05-of-the-conf/260522-kjt-SUMMARY.md`
recording: files created/modified, the 8 commits, validation results (including
whether `kustomize build` ran here or was deferred to CI/developer), and any
deviations from the approved plan.
</output>
