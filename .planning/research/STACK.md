# Stack Research: Ansible-Native Automation for Confluent Platform

**Domain:** Ansible-based governance roles, deployment pipelines, and DR automation for Confluent Platform on RHEL and CFK on OpenShift
**Researched:** 2026-04-07
**Confidence:** HIGH (versions verified against official Confluent docs, Ansible docs, PyPI, and GitHub releases)

---

## Scope

This document covers ONLY the stack additions needed for the v2.0 Ansible automation milestone. It does not re-document the existing Terraform, Java, Python, or .NET stack from the v1.0 research. Cross-references to the existing stack are noted where integration points exist.

---

## Recommended Stack

### Core Ansible Runtime

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| ansible-core | 2.18.x | Automation engine | Latest ansible-core supported by cp-ansible 8.2.0. Supports RHEL 9 (primary target) and all required modules (uri, template, assert, command). Use 2.16 only if RHEL 8 hosts are required. | HIGH |
| Ansible (package) | 11.x | Collection bundle including ansible-core 2.18 | Confluent explicitly recommends the `ansible` package over bare `ansible-core` because cp-ansible depends on modules from community.general and other collections that are not bundled with ansible-core alone. Ansible 11.x bundles ansible-core 2.18. | HIGH |
| Python | >= 3.11 | Control node runtime | Python 3.11 is the sweet spot: fully supported by ansible-core 2.18 and cp-ansible 8.2.0, available on RHEL 9 natively. Python 3.12 also works but 3.11 avoids deprecation noise from older pip packages. | HIGH |

**RHEL 8 fallback:** If RHEL 8 targets are required, pin to Ansible 9.x (ansible-core 2.16) and Python 3.10. RHEL 8 does not support Ansible 10+ or ansible-core 2.17+. This is a Confluent-documented constraint.

### Confluent Platform and cp-ansible

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| confluent.platform (cp-ansible) | 7.7.8 | CP cluster deployment roles | **Use 7.7.8, not 8.2.0.** The codebase is on CP 7.6.0. cp-ansible 7.7.8 is the conservative next step: same Kafka 3.7 protocol family, ZooKeeper still supported (migration to KRaft can happen later), Ansible 9.x support for RHEL 8 compatibility, OAuth 2.0 support added. Jumping to cp-ansible 8.x means Kafka 4.x which removes ZooKeeper and requires KRaft migration -- a separate project. | HIGH |
| Confluent Platform | 7.7.x | Target platform version | CP 7.7 is based on Apache Kafka 3.7, maintains ZooKeeper compatibility, adds OAuth 2.0/OIDC, and is the last major release before the 7.8-7.9-8.0 KRaft migration path. Stable for FSI compliance windows. | HIGH |
| confluent.platform (cp-ansible) | 8.2.0 | Future upgrade target (NOT for initial v2.0) | CP 8.2 is based on Kafka 4.2, ZooKeeper removed, Java 21 recommended. Use this as the upgrade target AFTER v2.0 ships and KRaft migration is planned as a separate effort. Supports Ansible 9-11, RHEL 8-10, FIPS 140-3. | MEDIUM |

**Version mapping (verified):**

| cp-ansible | Confluent Platform | Apache Kafka | ZooKeeper | Ansible Support |
|------------|-------------------|--------------|-----------|-----------------|
| 7.6.10 | 7.6.x | 3.6.x | Yes | 4.x - 7.x |
| 7.7.8 | 7.7.x | 3.7.x | Yes (KRaft optional) | 7.x - 9.x |
| 7.8.7 | 7.8.x | 3.8.x | Yes (KRaft recommended) | 8.x - 10.x |
| 7.9.6 | 7.9.x | 3.9.x | Yes (last release) | 9.x - 10.x |
| 8.0.4 | 8.0.x | 4.0.x | No (KRaft only) | 9.x - 11.x |
| 8.2.0 | 8.2.x | 4.2.x | No (KRaft only) | 9.x - 11.x |

### Ansible Collection Dependencies

| Collection | Version | Purpose | Why Needed | Confidence |
|------------|---------|---------|------------|------------|
| ansible.builtin | (bundled with ansible-core) | Core modules: uri, template, assert, command, file, copy, service, systemd, set_fact, debug, fail, stat, lineinfile | Every role uses builtin modules. The `uri` module is the workhorse for all REST API calls to MDS, Schema Registry, and Kafka Admin REST. No external HTTP library needed. | HIGH |
| community.general | >= 10.x (bundled with Ansible 11.x) | json_query filter, ini_file, java_keystore, ldap_entry, consul_kv modules | `json_query` is essential for parsing MDS and SR API responses. `consul_kv` enables DR failover state management. `java_keystore` handles TLS keystore operations for mTLS. Bundled with the Ansible package so no separate install needed. | HIGH |
| kubernetes.core | 6.3.0 | helm, k8s, k8s_info modules | Required for CFK on OpenShift deployment. `kubernetes.core.helm` deploys CFK operator chart. `kubernetes.core.k8s` manages KafkaTopic, SchemaRegistrySubject, and other CFK CRDs. `kubernetes.core.k8s_info` validates resource state. | HIGH |
| ansible.posix | >= 1.6.0 (bundled with Ansible 11.x) | firewalld, sysctl, selinux modules | RHEL firewall and SELinux configuration for CP nodes. Required for production RHEL deployments where firewalld and SELinux are enforced. | MEDIUM |

**Do NOT add:** `ansible.netcommon`, `amazon.aws`, `azure.azcollection`, `google.cloud` -- the governance roles are platform-agnostic. Cloud-specific provisioning stays in Terraform.

### REST API Endpoints (for Custom Governance Roles)

The custom governance roles (topic lifecycle, schema registration, RBAC) call Confluent REST APIs via `ansible.builtin.uri`. These are NOT cp-ansible roles -- they are new roles we build.

#### Kafka Admin REST API v3 (Topic Lifecycle)

| Endpoint | Method | Purpose | Notes |
|----------|--------|---------|-------|
| `/kafka/v3/clusters/{cluster_id}/topics` | POST | Create topic | Request body: `topic_name`, `partitions_count`, `replication_factor`, `configs`. Available on Confluent Server (port 8090) or REST Proxy. |
| `/kafka/v3/clusters/{cluster_id}/topics` | GET | List topics | Returns topic names with partition/replica metadata. |
| `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}` | GET | Get topic details | Includes partition count, replication factor, and configs. |
| `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs` | GET | Get topic configs | Full config dump including dynamic overrides. |
| `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs:alter` | POST | Update topic configs | Batch update topic configurations. |
| `/kafka/v3/clusters/{cluster_id}/topics/{topic_name}` | DELETE | Delete topic | Destructive. Governance role should require explicit confirmation variable. |

**Base URL:** `https://<broker>:8090/kafka` (Confluent Server embedded REST) or `https://<rest-proxy>:8082` (standalone REST Proxy, omit `/kafka` prefix).

#### Schema Registry REST API (Schema Registration)

| Endpoint | Method | Purpose | Notes |
|----------|--------|---------|-------|
| `/subjects` | GET | List all subjects | Returns array of subject name strings. |
| `/subjects/{subject}/versions` | POST | Register schema | Body: `{"schema": "<escaped-json>", "schemaType": "AVRO"}`. Returns `{"id": <global-id>}`. |
| `/subjects/{subject}/versions/{version}` | GET | Get schema by version | Version is integer or "latest". |
| `/compatibility/subjects/{subject}/versions/{version}` | POST | Check compatibility | Body contains schema to test. Returns `{"is_compatible": true/false}`. |
| `/config/{subject}` | PUT | Set subject compatibility | Body: `{"compatibility": "FULL_TRANSITIVE"}`. |
| `/config/{subject}` | GET | Get subject compatibility | Returns current compatibility level. |

**Base URL:** `https://<schema-registry>:8081`
**Content-Type:** `application/vnd.schemaregistry.v1+json`
**Auth:** Basic auth (LDAP user) or mTLS client cert when RBAC is enabled.

#### MDS REST API (RBAC Management)

| Endpoint | Method | Purpose | Notes |
|----------|--------|---------|-------|
| `/security/1.0/roles` | GET | List available roles | Returns role definitions with resource types and allowed operations. |
| `/security/1.0/roleNames` | GET | List role names only | Lightweight alternative to /roles. |
| `/security/1.0/principals/{principal}/roles/{roleName}` | POST | Create cluster-scoped role binding | Body: cluster scope JSON. Returns 204 No Content. |
| `/security/1.0/principals/{principal}/roles/{roleName}/bindings` | POST | Create resource-scoped role binding | Body includes resourcePatterns array with resourceType (Topic, Subject, Group, etc.), name, patternType (LITERAL, PREFIXED). |
| `/security/1.0/principals/{principal}/roles/{roleName}/resources` | POST | List role binding resources | Returns resource grants for the principal/role combination. |
| `/security/1.0/principals/{principal}/roles/{roleName}` | DELETE | Delete role binding | Body: same cluster scope as create. Returns 204. |
| `/security/1.0/lookup/principals/{principal}/roleNames` | POST | Lookup effective roles | Returns all roles for a principal at a given scope. |

**Base URL:** `https://<mds-host>:8090` (MDS runs co-located on Kafka brokers)
**Auth:** Bearer token obtained from `/security/1.0/authenticate` (LDAP credentials -> JWT token)

**Predefined roles for governance automation:**
- `DeveloperRead` -- consumer access to topics and consumer groups
- `DeveloperWrite` -- producer access to topics
- `DeveloperManage` -- topic create/delete/alter (for C4E service accounts)
- `ResourceOwner` -- full control over specific resources
- `SecurityAdmin` -- manage role bindings (for the automation service account itself)

### CI/CD and Testing

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| ansible-lint | 26.3.0 | Static analysis of roles and playbooks | De facto standard for Ansible quality. Version 26.x supports ansible-core 2.18, includes profile-based severity (use `shared` profile for roles meant to be reusable). Catches FQCN violations, deprecated modules, unsafe practices, YAML formatting. | HIGH |
| molecule | 26.3.0 | Role testing framework | De facto standard for Ansible role testing. Provides converge-verify-destroy lifecycle. Use `delegated` driver for governance roles (they call REST APIs, not manage containers). Use `podman` driver for deployment roles that need a systemd-capable container. | HIGH |
| molecule-plugins | 25.8.12 | Driver plugins for molecule (docker, podman, delegated) | Provides the podman and docker drivers. Install with `pip install "molecule-plugins[podman]"`. Podman is preferred over Docker for FSI environments where rootless containers are required. | HIGH |
| yamllint | >= 1.35 | YAML syntax validation | ansible-lint delegates to yamllint for YAML formatting. Pin a version to avoid CI flakiness from upstream changes. | HIGH |
| GitHub Actions | N/A (managed) | CI/CD pipeline | Extend existing workflows with Ansible-specific jobs. Reuse existing `ubuntu-latest` runners. Install ansible + molecule via pip in the workflow. | HIGH |
| Confluent CLI | >= 4.x | Operational commands in DR playbooks | Used by DR roles for `confluent kafka mirror promote`, `confluent kafka mirror status`, `confluent kafka topic list`. Already in the codebase for shell-based DR. Ansible roles invoke via `ansible.builtin.command` with registered output parsing. | MEDIUM |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| ansible-navigator | Interactive role development and testing | Optional but helpful for local development. Provides container-based execution that mirrors CI. |
| ansible-vault | Secret management for role variables | Already used in cp-rhel scenario. Encrypt MDS passwords, LDAP creds, TLS keys. Use `vault_password_file` in CI. |
| jq | JSON parsing in shell-based verification scripts | Used in molecule verify steps that call REST APIs and check responses. |
| pre-commit | Git hook framework | Add ansible-lint and yamllint as pre-commit hooks. Catches issues before CI. |

---

## Installation

### Control Node Setup

```bash
# Create virtual environment (recommended)
python3.11 -m venv .venv
source .venv/bin/activate

# Core runtime
pip install ansible==11.6.0  # Bundles ansible-core 2.18 + community collections

# Confluent collection (specific version for CP 7.7)
ansible-galaxy collection install confluent.platform:==7.7.8

# Kubernetes collection (for CFK on OpenShift)
ansible-galaxy collection install kubernetes.core:==6.3.0

# Testing and linting
pip install ansible-lint==26.3.0
pip install molecule==26.3.0
pip install "molecule-plugins[podman]==25.8.12"
pip install yamllint>=1.35

# Optional: pre-commit hooks
pip install pre-commit
```

### requirements.yml (for ansible-galaxy)

```yaml
---
collections:
  - name: confluent.platform
    version: ">=7.7.0,<7.8.0"
  - name: kubernetes.core
    version: ">=6.0.0,<7.0.0"
  - name: community.general
    version: ">=10.0.0"
  - name: ansible.posix
    version: ">=1.6.0"
```

### pip requirements (requirements-ansible.txt)

```
ansible>=11.0.0,<12.0.0
ansible-lint>=26.0.0,<27.0.0
molecule>=26.0.0,<27.0.0
molecule-plugins[podman]>=25.0.0
yamllint>=1.35.0
jmespath>=1.0.1
```

### ansible-lint configuration (.ansible-lint)

```yaml
---
profile: shared  # Roles are reusable content; shared profile enforces Galaxy metadata, FQCN, docs

# Exclude cp-ansible's own roles (we lint only our custom roles)
exclude_paths:
  - .cache/
  - .venv/
  - scenarios/cp-rhel/  # Existing v1.0 content, lint separately

# Rules that conflict with cp-ansible patterns
skip_list:
  - role-name[path]  # cp-ansible role names don't follow galaxy convention

# Warn but don't fail on these (review and fix iteratively)
warn_list:
  - no-changed-when  # uri module calls often lack changed_when
  - command-instead-of-module  # Confluent CLI calls via command are intentional

# YAML formatting
yaml:
  max-line-length: 160  # Match cp-ansible's own line length
```

### molecule configuration (molecule/default/molecule.yml template for governance roles)

```yaml
---
driver:
  name: delegated  # Governance roles call REST APIs, not manage hosts
  options:
    managed: false

platforms:
  - name: cp-governance-test
    groups:
      - cp_governance

provisioner:
  name: ansible
  inventory:
    host_vars:
      cp-governance-test:
        kafka_rest_url: "${KAFKA_REST_URL:-https://localhost:8090}"
        schema_registry_url: "${SR_URL:-https://localhost:8081}"
        mds_url: "${MDS_URL:-https://localhost:8090}"
        mds_user: "mds"
        mds_password: "${MDS_PASSWORD:-mds-secret}"

verifier:
  name: ansible  # Use Ansible playbooks for verification, not testinfra

scenario:
  test_sequence:
    - dependency
    - lint
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - cleanup
    - destroy
```

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| cp-ansible 7.7.8 | cp-ansible 8.2.0 | CP 8.x requires KRaft (ZooKeeper removed). Existing codebase is on CP 7.6 with ZooKeeper. Jumping two major versions (7.6 -> 8.2) in the same milestone as adding Ansible governance is too much change at once. Upgrade to 8.x should be a separate milestone after v2.0 ships. |
| Ansible 11.x (ansible-core 2.18) | Ansible 9.x (ansible-core 2.16) | Ansible 9.x is only needed for RHEL 8 compatibility. RHEL 9 is the recommended target for new CP deployments. If RHEL 8 is required, fall back to Ansible 9.x. |
| ansible.builtin.uri for REST APIs | Custom Ansible module (Python) | uri module is sufficient for all MDS, SR, and Admin REST endpoints. Writing custom Python modules adds maintenance burden and requires understanding the Ansible module SDK. Only consider custom modules if uri becomes unwieldy (>15 lines of response parsing per call). |
| ansible.builtin.uri for REST APIs | Confluent CLI via command module | CLI is less idempotent -- harder to check state before acting. URI calls with GET-then-POST pattern are naturally idempotent. CLI is better for DR operations (mirror promote, mirror status) where the CLI provides cleaner output. Use both: URI for governance CRUD, CLI for DR orchestration. |
| molecule with delegated driver | molecule with docker/podman driver | Governance roles (topic, schema, RBAC) manage remote services via REST APIs, not local hosts. There is nothing to run in a container. Delegated driver lets molecule run the role against a mock or real CP cluster. Use podman driver only for roles that manage systemd services (e.g., JMX exporter config). |
| ansible-lint shared profile | ansible-lint production profile | Production profile is for Ansible Automation Platform (AAP) certified content. Our roles are not going through AAP certification. Shared profile is the right level: enforces FQCN, Galaxy metadata, documentation requirements without AAP-specific constraints. |
| yamllint (via ansible-lint) | standalone yamllint only | ansible-lint bundles yamllint integration. Running yamllint separately adds CI complexity with no benefit. Configure yamllint rules inside .ansible-lint. |
| Ansible Vault for secrets | HashiCorp Vault lookup plugin | Vault lookup plugin (`hashi_vault`) adds complexity and requires Vault infrastructure in the test environment. Ansible Vault is simpler and already in use in the cp-rhel scenario. For production, teams can swap to `hashi_vault` lookup -- our roles should accept credentials as variables regardless of source. |
| kubernetes.core for CFK | Raw kubectl via command module | kubernetes.core.k8s provides declarative state management with built-in wait/retry logic. Command module with kubectl is imperative and fragile. kubernetes.core also supports kubeconfig auth, service account tokens, and OpenShift OAuth. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| cp-ansible 8.x (for initial v2.0) | Requires KRaft migration from ZooKeeper. Mixing Ansible governance work with a metadata migration is high-risk. CP 8.0 also removes Java 8/11 support and requires Java 17/21. | cp-ansible 7.7.8 for v2.0; plan 8.x upgrade as separate milestone. |
| ansible-core (bare, without ansible package) | Missing community.general, ansible.posix, and other collections that cp-ansible depends on. Confluent docs explicitly warn against this. | `ansible` package (11.x) which bundles all required collections. |
| Terraform for topic/schema/RBAC on CP | The existing Terraform topic module targets Confluent Cloud via the Confluent TF provider. There is no Terraform provider for on-prem MDS RBAC or Confluent Server Admin REST. Attempting to use Terraform for CP governance creates a tool mismatch. | Ansible roles calling MDS/SR/Admin REST APIs via ansible.builtin.uri. |
| confluent-kafka Python library (for Ansible modules) | Would require writing custom Ansible modules wrapping the Python Kafka client. Adds a runtime dependency (librdkafka) to the control node. Admin operations don't need a full Kafka client -- REST APIs are sufficient. | ansible.builtin.uri module calling REST API endpoints. |
| Custom Ansible modules (Python) for MDS/SR | High maintenance cost, requires testing the module SDK, versioning, and documentation separately from the roles. The REST APIs are simple CRUD -- uri handles them cleanly. | ansible.builtin.uri with registered variables and assert for validation. |
| testinfra/inspec for molecule verification | These are host-level testing tools (check packages installed, services running, file permissions). Governance roles don't modify hosts -- they manage remote API state. | Ansible verifier (verify.yml playbook that calls REST APIs to confirm state). |
| ansible.netcommon collection | Not needed. No network device management in this project. | N/A |
| AWX/Tower for execution | Adds infrastructure overhead. GitHub Actions is already the CI/CD platform. AWX is useful for FSI teams that adopt the roles but not needed for the roles themselves. | GitHub Actions workflows for CI/CD. Document AWX compatibility in README. |

---

## Stack Patterns by Variant

### Governance Roles (topic, schema, RBAC)

```
ansible.builtin.uri -> REST API (MDS/SR/Admin REST)
                    -> Validate with assert
                    -> Idempotency via GET-before-POST pattern
Test with: molecule (delegated driver) against live or mocked CP
Lint with: ansible-lint (shared profile)
```

**Pattern:** Each role follows GET-check-POST-verify:
1. GET current state (topic exists? schema registered? binding present?)
2. Compare desired state from variables
3. POST/PUT only if change needed (idempotent)
4. Verify with follow-up GET
5. Register results for reporting

### Deployment Pipeline Playbooks

```
confluent.platform roles -> CP cluster deployment
Custom governance roles  -> Topic/schema/RBAC configuration
Custom observability role -> JMX exporter + Prometheus config
```

**Pattern:** Pipeline playbook imports cp-ansible roles for infrastructure, then applies custom governance roles for day-2 configuration. Two separate plays, not one monolithic playbook.

### DR Automation Playbooks

```
ansible.builtin.command -> Confluent CLI (mirror promote, mirror status)
ansible.builtin.uri     -> MDS API (verify RBAC state post-failover)
community.general.consul_kv -> Consul endpoint flip
```

**Pattern:** DR playbooks use Confluent CLI for mirror operations (CLI provides better error messages and progress output than raw Admin REST for long-running operations). Use `--dry-run` pattern via `--check` mode with `ansible.builtin.debug` showing planned actions.

### CFK on OpenShift

```
kubernetes.core.helm    -> Deploy CFK operator chart
kubernetes.core.k8s     -> Apply KafkaTopic, SchemaRegistrySubject CRDs
kubernetes.core.k8s_info -> Validate resource status
```

**Pattern:** CFK CRDs handle topic/schema/RBAC at the Kubernetes level. The same governance logic (naming validation, SLA-tier defaults) runs in Ansible before creating the CRD, but the CRD is the execution mechanism -- not REST API calls.

---

## Version Compatibility Matrix

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| cp-ansible 7.7.8 | Ansible 7.x-9.x, Python 3.9+ | Use Ansible 9.x for RHEL 8; Ansible 11.x for RHEL 9 |
| cp-ansible 7.7.8 | CP 7.7.x (Kafka 3.7.x) | 1:1 version mapping. Collection version = CP version. |
| ansible-lint 26.3.0 | ansible-core 2.17-2.21 | Supports all ansible-core versions we might use. |
| molecule 26.3.0 | ansible-core 2.17-2.21, Python 3.10+ | Same compatibility range as ansible-lint. |
| kubernetes.core 6.3.0 | ansible-core 2.17-2.20, Helm v3.x | Helm v4 NOT supported yet. CFK uses Helm v3 charts. |
| community.general 10.x | ansible-core 2.17-2.21 | Bundled with Ansible 11.x package. |
| Confluent CLI 4.x | CP 7.6+ and CC | CLI version is independent of CP version but 4.x supports all current CP features. |

### Critical: cp-ansible / Ansible / RHEL Compatibility

| Target OS | Ansible Package | ansible-core | cp-ansible | Python |
|-----------|-----------------|--------------|------------|--------|
| RHEL 9 (recommended) | 11.x | 2.18 | 7.7.8 | 3.11 |
| RHEL 8 (legacy) | 9.x | 2.16 | 7.7.8 | 3.10 |
| RHEL 10 (future) | 11.x | 2.18 | 8.2.0 (requires CP 8.2) | 3.12 |

---

## Integration Points with Existing Codebase

| Existing Component | Integration Point | How |
|--------------------|--------------------|-----|
| `scenarios/cp-rhel/` (v1.0) | Ansible governance roles called after cp-ansible deployment | Pipeline playbook imports existing deploy-cp.yml, then runs governance roles. Existing inventory/group_vars reused. |
| `schemas/examples/*.avsc` | Schema registration role reads .avsc files | Role variable `schema_file` points to .avsc file. Role reads content, validates JSON, POSTs to SR REST API. Same schema files used by Terraform CI and Ansible. |
| `topics/*.yml` (CPTopic YAML) | Topic lifecycle role reads CPTopic definitions | Role parses CPTopic YAML (already exists in cp-rhel scenario), extracts spec and labels, creates topic via Admin REST, applies metadata. |
| `scripts/fsi-dr.sh` | DR playbooks replace shell scripts | Ansible DR playbooks provide the same operations (failover, failback, validate, drill) with structured error handling, dry-run mode, and reporting. Shell scripts remain as legacy/fallback. |
| `ci/scripts/validate-schemas.py` | Schema validation runs in molecule verify step | Molecule verify playbook calls the existing Python validation script, then verifies schemas are registered in SR. |
| `observability/` templates | Observability role deploys JMX exporter configs | Role templates JMX exporter YAML from existing observability directory patterns. No duplication -- role references shared config. |
| `.github/workflows/` | New Ansible CI workflows added alongside existing TF workflows | Separate workflow files: `ansible-lint.yml`, `ansible-molecule.yml`. Do not modify existing `terraform-plan.yml` or `terraform-apply.yml`. |

---

## Upgrade Path

### Immediate (v2.0 scope)

| Component | Current | Target | Breaking Changes | Priority |
|-----------|---------|--------|------------------|----------|
| cp-ansible | 7.6.x (implicit, cp-rhel scenario) | 7.7.8 | None within 7.x. Minor config changes documented in cp-ansible 7.7 release notes (OAuth vars added, JMX exporter 0.20.0). | Phase 1 |
| Ansible package | Not formalized | 11.x (new) | N/A -- new addition to project | Phase 1 |
| ansible-lint | Not present | 26.3.0 (new) | N/A -- new addition | Phase 1 |
| molecule | Not present | 26.3.0 (new) | N/A -- new addition | Phase 1 |
| kubernetes.core | Not formalized | 6.3.0 (new) | N/A -- new addition | CFK phase |

### Future (post-v2.0)

| Component | Current | Target | Breaking Changes | Priority |
|-----------|---------|--------|------------------|----------|
| cp-ansible | 7.7.8 | 8.2.0 | KRaft migration required (ZooKeeper removed in CP 8.0). Java 21 recommended. FIPS 140-3 replaces 140-2. RHEL 10 support added. | Separate milestone |
| Ansible package | 11.x | 13.x | Follow ansible-core lifecycle. Check cp-ansible compatibility before upgrading. | As needed |

---

## Sources

- [Confluent Ansible Requirements](https://docs.confluent.io/ansible/current/ansible-requirements.html) -- Compatibility matrix: cp-ansible 8.2.0 supports Ansible 9-11, Python 3.10+ (HIGH confidence)
- [Confluent Ansible Release Notes](https://docs.confluent.io/ansible/current/ansible-release-notes.html) -- cp-ansible 8.2.0 features: RHEL 10, FIPS 140-3, AWS SSM (HIGH confidence)
- [cp-ansible 7.7 Release Notes](https://docs.confluent.io/ansible/7.7/ansible-release-notes.html) -- cp-ansible 7.7.8 details, OAuth 2.0 support (HIGH confidence)
- [cp-ansible GitHub Releases](https://github.com/confluentinc/cp-ansible/releases) -- Full version history confirming 7.7.8 and 8.2.0 as latest in each stream (HIGH confidence)
- [Confluent Platform Versions](https://docs.confluent.io/platform/current/installation/versions-interoperability.html) -- CP-to-Kafka version mapping, RHEL/Java support matrix (HIGH confidence)
- [MDS REST API Reference](https://docs.confluent.io/platform/current/security/authorization/rbac/mds-api.html) -- RBAC endpoints for role binding CRUD (HIGH confidence)
- [Schema Registry REST API](https://docs.confluent.io/platform/current/schema-registry/develop/api.html) -- Schema registration, compatibility check endpoints (HIGH confidence)
- [Kafka REST Proxy API](https://docs.confluent.io/platform/current/kafka-rest/api.html) -- Admin REST v3 topic management endpoints (HIGH confidence)
- [ansible-core on PyPI](https://pypi.org/project/ansible-core/) -- ansible-core 2.20.4 latest, 2.18 in active support (HIGH confidence)
- [ansible-lint on PyPI](https://pypi.org/project/ansible-lint/) -- Version 26.3.0, March 2026 (HIGH confidence)
- [molecule on PyPI](https://pypi.org/project/molecule/) -- Version 26.3.0, March 2026 (HIGH confidence)
- [molecule-plugins on PyPI](https://pypi.org/project/molecule-plugins/) -- Version 25.8.12, supports docker/podman/delegated drivers (HIGH confidence)
- [kubernetes.core Collection](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/index.html) -- Version 6.3.0, helm module for CFK deployment (HIGH confidence)
- [ansible-lint Profiles](https://docs.ansible.com/projects/lint/profiles/) -- Profile hierarchy: min > basic > moderate > safety > shared > production (HIGH confidence)
- [Confluent CLI RBAC Commands](https://docs.confluent.io/confluent-cli/current/command-reference/iam/rbac/role-binding/index.html) -- confluent iam rbac role-binding create/list/delete (HIGH confidence)

---

*Stack research for: Ansible-native governance automation for Confluent Platform*
*Researched: 2026-04-07*
