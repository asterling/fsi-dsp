# Project Research Summary

**Project:** FSI Kafka Platform — Ansible-Native Automation (v2.0 Milestone)
**Domain:** Ansible-based governance automation for Confluent Platform on RHEL and CFK on OpenShift
**Researched:** 2026-04-07
**Confidence:** HIGH (stack and architecture verified against official Confluent docs; features validated against codebase; pitfalls confirmed across multiple sources)

## Executive Summary

The v2.0 milestone adds Ansible-native governance automation as a peer automation surface alongside the existing Terraform-based Confluent Cloud workflows. This is not a replacement of existing content — it is an additive layer that brings the same governed topic provisioning (SLA-tier defaults, Avro schema registration, MDS RBAC bindings, DR orchestration) to Confluent Platform on RHEL and CFK on OpenShift deployments that currently lack automation parity with the Terraform CC module. The recommended approach follows the pattern established by the existing codebase: a single source of governance truth (SLA-tier maps, naming regex, compatibility modes) that both Terraform and Ansible consume, eliminating drift between deployment models.

The core technical recommendation is clear: use `ansible.builtin.uri` against Confluent's three stable REST APIs (Admin REST v3 for topics on port 8090, Schema Registry REST on port 8081, MDS REST for RBAC on port 8090) rather than custom Ansible modules or Confluent CLI. The cp-ansible collection (version 7.7.8, targeting CP 7.7.x) handles Day 1 cluster deployment; custom governance roles in `ansible/roles/` handle Day 2 operations. This boundary is explicit and must not be crossed. The architecture calls for standalone roles (not a Galaxy collection), multi-environment inventories, and shared governance constants in `ansible/vars/sla_tiers.yml` that CI validates against the Terraform module's `locals` blocks.

The highest-risk area is governance drift between the Terraform module and new Ansible roles — a silent failure that violates the platform's core constraint of deployment parity. The second-highest risk cluster involves operational correctness of the REST API implementations: idempotency (GET-before-POST for topics), two-pass schema validation (check compatibility before registering), and MDS token expiration handling during long playbook runs. All three must be designed correctly from Phase 1; retrofitting them is costly and risks leaving clusters in partially-provisioned states. The RHEL 8 vs RHEL 9 bifurcation and the Ansible Vault vs HashiCorp Vault naming collision are additional FSI-specific pitfalls that require early architectural decisions.

## Key Findings

### Recommended Stack

The Ansible runtime is the `ansible` package 11.x (which bundles ansible-core 2.18 and all required collections) targeting RHEL 9. For RHEL 8 legacy environments, fall back to `ansible` 9.x (ansible-core 2.16). The cp-ansible collection version is `confluent.platform:==7.7.8` — a deliberate conservative step from the codebase's current CP 7.6 baseline. Jumping to cp-ansible 8.x (which requires KRaft migration and removes ZooKeeper) is explicitly out of scope for v2.0 and should be a separate milestone.

**Core technologies:**
- `ansible` 11.x (ansible-core 2.18): Automation engine — bundles community.general, ansible.posix; Confluent docs explicitly warn against bare ansible-core
- `confluent.platform` 7.7.8: cp-ansible collection for CP 7.7 cluster deployment — 1:1 version match with target CP version is mandatory; pin in `requirements.yml`
- `ansible.builtin.uri`: REST API client for all governance operations — preferred over custom modules and Confluent CLI for idempotency and transparency
- `community.general` 10.x: `consul_kv` for DR failover state, `json_query` for MDS/SR response parsing, `java_keystore` for mTLS
- `kubernetes.core` 6.3.0: Helm and k8s modules for CFK on OpenShift deployment — requires Helm v3 (v4 not yet supported)
- `ansible-lint` 26.3.0 and `molecule` 26.3.0: CI/CD toolchain — ansible-lint `shared` profile (not `production`); molecule with `delegated` driver for governance roles, Podman `ubi-init` driver for systemd-requiring roles
- Python 3.11: Control node runtime — sweet spot for ansible-core 2.18 compatibility on RHEL 9

**Critical version constraints:**
- cp-ansible collection version MUST match CP version (7.7.8 collection = CP 7.7.x cluster)
- RHEL 8 is limited to Ansible 9.x (ansible-core 2.16); RHEL 9 supports Ansible 11.x
- kubernetes.core 6.3.0 does NOT support Helm v4; CFK uses Helm v3 charts

### Expected Features

**Must have (table stakes) — governance parity with Terraform module:**
- Topic lifecycle role: create/update/delete via Admin REST v3, SLA-tier-derived defaults, naming validation, idempotent GET-before-POST pattern, CPTopic YAML consumption, check mode support
- Schema registration role: Avro .avsc registration via SR REST, compatibility pre-check before registration (two-pass), SLA-tier-derived compatibility mode, PII metadata tagging
- RBAC provisioning role: MDS token acquisition with refresh, per-topic DeveloperWrite/DeveloperRead bindings, consumer group bindings, SR subject bindings, LIST/DIFF/ADD/REMOVE reconciliation (not add-only)
- End-to-end orchestration playbook (`site.yml`): topics to schemas to RBAC to connectors to observability pipeline with tags for selective execution
- CI/CD for Ansible: ansible-lint and yamllint in GitHub Actions on every PR; molecule tests per role

**Should have (differentiators that justify custom roles over community tools):**
- SLA-tier abstraction: single `sla_tier` input derives all config (partitions, retention, compatibility, alert thresholds) — not available in cp-ansible-admin or community tools
- Unified CPTopic YAML across Terraform and Ansible: define once, deploy to CC (Terraform) or CP/CFK (Ansible)
- Compliance-tier with year-based retention: `retention_years: 7` auto-calculated — first-class FSI regulatory concept
- DR automation playbooks (MM2): parallel task execution, structured audit reports, check mode — superior to existing `fsi-dr.sh` shell script
- Observability deployment role: inventory-driven Prometheus scrape configs, SLA-tier-aware alert thresholds per topic
- Connector deployment role: idempotent Connect REST API management, health validation, DR pause/resume

**Defer to later phase:**
- MRC failover playbook: highest-complexity DR pattern; ship MM2 first
- DR drill orchestration playbook: depends on proven failover/failback
- Per-provider observability beyond Grafana/Prometheus (Dynatrace, Datadog, Splunk)
- CFK governance via Ansible: different pattern (kubernetes.core.k8s CRDs vs REST API calls); separate from CP roles
- cp-ansible 8.x and KRaft migration: separate milestone after v2.0 ships

### Architecture Approach

The `ansible/` directory is a **peer automation surface** alongside `modules/` (Terraform CC) and `scenarios/` (cp-ansible deployment). It is strictly additive — no existing files are modified. Governance constants are extracted to `ansible/vars/sla_tiers.yml` and `ansible/vars/naming_rules.yml`, mirroring the Terraform `locals` blocks. A CI job validates parity between these YAML files and the Terraform module, preventing drift. The data flow is: CPTopic YAML definitions (existing) and Avro .avsc schemas (existing) flow into custom governance roles, which call the three Confluent REST APIs. The full pipeline playbook (`site.yml`) chains cp-ansible cluster deployment (existing) with the new governance roles.

**Major components:**
1. `ansible/roles/cp_topic` — topic lifecycle via Admin REST v3; GET-check-POST-verify idempotency pattern
2. `ansible/roles/cp_schema` — schema registration via SR REST; two-pass validate-then-register; reuses `ci/scripts/validate-schemas.py` via `ansible.builtin.command`
3. `ansible/roles/cp_rbac` — RBAC bindings via MDS REST; token caching per-playbook with refresh; LIST/DIFF/ADD/REMOVE reconciliation
4. `ansible/roles/cp_dr_mm2` and `cp_dr_mrc` — DR orchestration replacing `scripts/fsi-dr.sh`; parallel task execution, structured reporting
5. `ansible/roles/cp_observability` and `cp_connect` — supporting roles consuming existing `observability/` templates
6. `ansible/vars/sla_tiers.yml` and `filter_plugins/fsi_governance.py` — shared governance constants and Jinja2 filters; single source of truth validated against Terraform
7. `ansible/inventories/{dev,staging,prod,dr}/` — multi-environment inventory separation; governance inventory kept separate from cp-ansible deployment inventory

**Key architectural decisions:**
- Standalone roles (not a Galaxy collection): tightly coupled to repository governance constants
- `ansible.builtin.uri` over custom modules: stable Confluent REST APIs cover all operations; cp-ansible-admin community project validates this pattern
- Shared YAML governance constants: only approach that satisfies the deployment parity constraint
- Separate inventory directories for deployment vs governance operations

### Critical Pitfalls

1. **Governance drift between Terraform and Ansible** — Extract constants to `ansible/vars/sla_tiers.yml` consumed by both tools; add CI job that cross-validates against `modules/topic/main.tf` locals; never hardcode partition counts in CPTopic YAML
2. **cp-ansible collection version not pinned to CP version** — Pin `confluent.platform:==7.7.8` in `requirements.yml` from the first commit; collection version must equal CP version or broker deployment fails with unknown config properties
3. **MDS bearer token expires mid-playbook (15-min default TTL)** — Implement per-batch authentication with refresh handler; increase `auth.token.max.lifetime.ms` to 3600000 for automation service accounts; add 401 detection with rescue block
4. **Schema Registry compatibility check at registration time, not before** — Always POST to `/compatibility/subjects/{subject}/versions/latest?verbose=true` first; run all compatibility checks before any registrations (two-pass: validate all, then register all)
5. **Ansible `uri` POST always reports `changed`, breaking idempotency tests** — Use `changed_when: result.status == 201` on create tasks; GET-before-POST pattern; `molecule idempotence` test will fail if not handled from the start
6. **Ansible Vault vs HashiCorp Vault naming collision causes credential exposure** — Establish naming convention immediately: `ansible-vault` vs `hcv`; `no_log: true` on every auth task; `gitleaks` in CI from day one

## Implications for Roadmap

Based on combined research, the dependency structure is clear: governance constants must exist before roles, roles before orchestration, orchestration before DR, all before CFK. The suggested phases directly follow the architecture's "Suggested Build Order" with pitfall mitigations baked in.

### Phase 1: Ansible Foundation and Governance Scaffolding

**Rationale:** Everything depends on getting governance constants, tool versions, and security patterns right from the start. Pitfalls 1, 2, 6, 13, 14, and 15 are all "fix at setup time or never" — they cannot be retrofit. This phase has no user-visible deliverable but is the highest-leverage phase.
**Delivers:** `ansible/` directory structure, `requirements.yml` with pinned versions, `ansible.cfg` (including `hash_behaviour = merge`), `ansible/vars/sla_tiers.yml` and `naming_rules.yml` mirroring Terraform locals, `filter_plugins/fsi_governance.py`, multi-environment inventory skeletons, `.ansible-lint` config, CI job validating Terraform/Ansible governance parity, `gitleaks` scanning in CI, naming convention docs for Ansible Vault vs HashiCorp Vault
**Addresses:** Foundation for all features from FEATURES.md; establishes SLA-tier abstraction before any role is written
**Avoids:** Governance drift (Pitfall 1), collection version mismatch (Pitfall 2), credential exposure (Pitfall 6), hash_behaviour deprecation (Pitfall 14), API endpoint confusion (Pitfall 15)

### Phase 2: Core Governance Roles (Topic, Schema, RBAC)

**Rationale:** These three roles are the v2.0 milestone deliverable. They must be built in dependency order — topics first, then schemas (reference topic subjects), then RBAC (binds principals to topics and subjects). The idempotency and authentication pitfalls (3, 4, 5, 7, 11, 12) must be addressed in role design, not bolted on after.
**Delivers:** `cp_topic` role with GET-check-POST-verify idempotency, `cp_schema` role with two-pass validate-then-register, `cp_rbac` role with MDS token caching and LIST/DIFF/ADD/REMOVE reconciliation, per-role molecule tests, individual role READMEs
**Uses:** `ansible.builtin.uri` against Admin REST v3 (topic), SR REST (schema), MDS REST (RBAC); governance constants from Phase 1; existing CPTopic YAML definitions from `scenarios/cp-rhel/topics/`; existing `ci/scripts/validate-schemas.py` reused via `ansible.builtin.command`
**Implements:** cp_topic, cp_schema, cp_rbac architecture components
**Avoids:** MDS token expiration (Pitfall 3), SR compatibility-at-registration (Pitfall 4), REST API non-idempotency (Pitfall 5), stale RBAC bindings (Pitfall 7), `uri` always-changed (Pitfall 12), SR auth variations (Pitfall 11)

### Phase 3: Orchestration Pipeline and CI/CD

**Rationale:** Individual roles are only valuable when composed. The end-to-end pipeline (`site.yml`, `deploy-governance.yml`) delivers the "single automation run" promise. CI/CD ensures quality does not degrade from the first PR. RHEL 8/9 test matrix and Molecule systemd strategy must be decided here (Pitfalls 8, 9) — not retrofitted.
**Delivers:** `ansible/playbooks/deploy-governance.yml` (topics + schemas + RBAC chain), `ansible/playbooks/site.yml` (full pipeline importing cp-ansible deployment), `cp_connect` role (connector deployment via Connect REST), `cp_observability` role (JMX exporter + Prometheus scrape config + Grafana dashboard import), GitHub Actions `ansible-lint.yml` and `ansible-molecule.yml` workflows, Ansible tags for selective execution
**Addresses:** End-to-end orchestration playbook, connector deployment, observability deployment from FEATURES.md
**Avoids:** Monolithic playbook anti-pattern; RHEL 8/9 test matrix must be established here (Pitfall 8); Molecule systemd container strategy (Pitfall 9)

### Phase 4: DR Automation Playbooks (MM2)

**Rationale:** DR automation replaces the existing `fsi-dr.sh` shell script with Ansible's superior error handling, parallel execution, and check mode. MM2 is the primary DR pattern for the existing codebase. Build and validate MM2 before MRC (more complex). Can be developed in parallel with Phase 3 if resources allow, since it depends only on Phase 2 completion.
**Delivers:** `cp_dr_mm2` role with failover/failback tasks, `ansible/playbooks/dr-failover.yml` and `dr-failback.yml`, dry-run mode generating CAB-ready output, structured YAML/JSON audit report, parallel connector pause/resume, DR state validation pre/post-flight tasks
**Uses:** `ansible.builtin.command` (Confluent CLI for mirror promote/status), `ansible.builtin.uri` (Connect REST for connector pause/resume), `community.general.consul_kv` (Consul endpoint flip); existing `fsi-dr.sh` logic as reference
**Implements:** cp_dr_mm2 architecture component; replaces `scripts/fsi-dr.sh` for CP deployments

### Phase 5: CFK on OpenShift Governance

**Rationale:** CFK uses Kubernetes CRDs (KafkaTopic, SchemaRegistrySubject) via `kubernetes.core.k8s` rather than REST API calls — a fundamentally different pattern from CP roles. Deferred to its own phase because it requires the `kubernetes.core` collection, OpenShift SCC pre-configuration, and separate Molecule test scenarios. Governance constants from Phase 1 still apply; the execution mechanism differs.
**Delivers:** CFK-specific playbooks using `kubernetes.core.helm` for CFK operator deployment, `kubernetes.core.k8s` for CRD application, `kubernetes.core.k8s_info` readiness gates, separation of deployment playbook from governance playbook with explicit health gates
**Uses:** `kubernetes.core` 6.3.0 (Helm v3 only), governance constants from Phase 1, same CPTopic YAML format consumed differently
**Avoids:** Helm timeout and readiness pitfall (Pitfall 10) — explicit `wait_timeout: "15m0s"` and CRD readiness checks before governance tasks; combining deployment and governance in one playbook

### Phase 6: MRC Failover and DR Drill

**Rationale:** MRC (Multi-Region Clusters) observer promotion is the highest-complexity DR pattern — deferred until MM2 is validated. The DR drill playbook (full failover + validate + failback cycle) depends on both failover and failback playbooks being proven in Phase 4.
**Delivers:** `cp_dr_mrc` role, `ansible/playbooks/dr-drill.yml` orchestrating full cycle, timestamped compliance evidence report, quarterly drill scheduling documentation
**Deferred because:** MRC topology requires specific cluster configuration that may not be universally deployed; DR drill orchestration builds on proven individual playbooks from Phase 4

### Phase Ordering Rationale

- Phase 1 before everything: governance constants, security patterns, and version pinning cannot be retrofit — establishing them first prevents the highest-severity pitfalls from entering the codebase at all
- Phase 2 before Phase 3: individual roles must exist and be tested before orchestration playbooks can meaningfully compose them
- Phase 3 includes CI/CD: quality gates must exist before any role reaches production use; Molecule test strategy must be decided when the first role is written
- Phase 4 (DR) is a parallel track to Phase 3 at the discretion of the team; both depend on Phase 2 completion
- Phase 5 deferred: CFK's Kubernetes-native pattern is architecturally distinct from CP REST API patterns; separating it prevents scope creep in the core governance work
- Phase 6 last: highest complexity, lowest urgency, depends on Phase 4 being proven

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (RBAC role):** MDS LIST/DIFF/ADD/REMOVE reconciliation pattern has no official reference implementation; exact request body schemas for binding enumeration need validation against a running CP 7.7 instance. The community cp-ansible-admin project provides a starting point but is MEDIUM confidence.
- **Phase 4 (DR automation):** MM2 failover sequence via Ansible has not been validated end-to-end against the existing `fsi-dr.sh` logic. Parallel connector pause behavior under load, and exact `mirror promote` CLI output format for Ansible `register` parsing, need verification.
- **Phase 5 (CFK):** OpenShift SCC pre-configuration requirements for CFK 3.2.x on OCP 4.14-4.21 need validation. The existing `scenarios/cfk-openshift/` content should be reviewed for current SCC binding approach before Phase 5 planning.

Phases with standard patterns (skip additional research):
- **Phase 1 (Foundation):** All decisions are well-documented in official Ansible and Confluent docs. Version pinning, `ansible.cfg`, inventory structure, ansible-lint config — standard patterns with HIGH confidence sources.
- **Phase 3 (Orchestration and CI):** GitHub Actions workflows for ansible-lint and molecule are standard. Grafana dashboard import via `community.grafana.grafana_dashboard` is well-documented. No research needed.
- **Phase 6 (MRC and Drill):** MRC observer promotion uses documented Confluent CLI commands. Once Phase 4 is validated, Phase 6 is straightforward composition.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All versions verified against official Confluent docs, PyPI, and cp-ansible GitHub releases. Version matrix (cp-ansible vs CP vs Ansible vs RHEL) confirmed from multiple official sources. |
| Features | MEDIUM | Table stakes derived from existing Terraform module (HIGH confidence codebase reference) and cp-ansible-admin community validation (MEDIUM). Differentiators are inferred from product requirements; no direct community validation of full-stack atomic provisioning via Ansible exists. |
| Architecture | HIGH | Standalone roles vs collection decision is well-documented Ansible guidance. `uri` module pattern validated by cp-ansible-admin. Shared governance YAML is logically required by parity constraint. Data flow confirmed from existing codebase analysis. |
| Pitfalls | HIGH | All critical pitfalls verified against official docs: MDS token TTL from MDS configuration docs, SR compatibility-at-registration from SR API reference, cp-ansible hash_behaviour from Confluent troubleshooting guide, RHEL 8/9 matrix from Confluent requirements docs. |

**Overall confidence:** HIGH

### Gaps to Address

- **MDS binding enumeration API:** The exact MDS REST endpoints and request bodies for enumerating all current bindings for a principal across all resource types need validation against a running CP 7.7+ instance. PITFALLS.md documents the conceptual pattern; exact implementation details are MEDIUM confidence.
- **Admin REST v3 config:alter request body:** The exact JSON structure for the batch config update endpoint (`POST /kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs:alter`) is documented but noted in ARCHITECTURE.md as needing "validation against running CP instance." Confirm in Phase 2 before finalizing the topic role.
- **RHEL 8 customer prevalence:** Research recommends targeting RHEL 9 for new deployments, with RHEL 8 as a fallback. The actual split of FSI customers on RHEL 8 vs RHEL 9 is unknown. If more than 50% of target customers are on RHEL 8, the Ansible 9.x constraint becomes the primary target. Clarify with stakeholders before Phase 2.
- **CFK SCC requirements for CP 7.7:** The existing `scenarios/cfk-openshift/` SCC configuration was written for an earlier CFK version. Validate against CFK 3.2.x release notes before Phase 5 planning.

## Sources

### Primary (HIGH confidence)
- [Confluent Ansible Requirements](https://docs.confluent.io/ansible/current/ansible-requirements.html) — cp-ansible version matrix, RHEL compatibility, Python requirements
- [Confluent Ansible Release Notes](https://docs.confluent.io/ansible/current/ansible-release-notes.html) — cp-ansible 7.7.8 and 8.2.0 feature details
- [Confluent Platform Versions](https://docs.confluent.io/platform/current/installation/versions-interoperability.html) — CP-to-Kafka version mapping, RHEL/Java support matrix
- [MDS REST API Reference](https://docs.confluent.io/platform/current/security/authorization/rbac/mds-api.html) — RBAC endpoints, authentication, token configuration
- [Schema Registry API Reference](https://docs.confluent.io/platform/current/schema-registry/develop/api.html) — Registration, compatibility check, verbose mode
- [Kafka REST API v3](https://docs.confluent.io/platform/current/kafka-rest/api.html) — Admin REST topic CRUD and config management
- [Confluent Ansible Troubleshooting](https://docs.confluent.io/ansible/current/ansible-troubleshooting.html) — hash_behaviour requirement, known issues
- [Schema Registry Deletion Guidelines](https://docs.confluent.io/platform/current/schema-registry/schema-deletion-guidelines.html) — Soft/hard delete behavior, schema ID permanence
- [kubernetes.core.helm Module](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/helm_module.html) — wait_timeout, Helm v3 support
- [ansible.builtin.uri Module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/uri_module.html) — HTTP client behavior, changed_when, no_log
- Existing codebase: `modules/topic/main.tf`, `modules/topic/variables.tf`, `scenarios/cp-rhel/`, `scripts/fsi-dr.sh`, `observability/` — primary implementation reference

### Secondary (MEDIUM confidence)
- [cp-ansible-admin community project](https://github.com/thecrazymonkey/cp-ansible-admin) — Validates uri-based pattern for topic/schema/RBAC Day 2 operations; does not have SLA-tier abstraction
- [Ansible Multi-Environment Inventory Patterns](https://www.digitalocean.com/community/tutorials/how-to-manage-multistage-environments-with-ansible) — Multi-environment inventory structure
- [Molecule with Podman for systemd testing](https://www.ansible.com/blog/developing-and-testing-ansible-roles-with-molecule-and-podman-part-1/) — Podman ubi-init image approach, SELinux cgroup requirements
- [ansible-lint Profiles documentation](https://docs.ansible.com/projects/lint/profiles/) — Profile hierarchy: shared vs production vs min

---
*Research completed: 2026-04-07*
*Ready for roadmap: yes*
