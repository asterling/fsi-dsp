# Domain Pitfalls

**Domain:** Ansible-based governance automation for Confluent Platform in FSI environments (v2.0 milestone)
**Researched:** 2026-04-07
**Confidence:** MEDIUM-HIGH (web-verified against official Confluent docs, cp-ansible GitHub, and Ansible project documentation)

---

## Critical Pitfalls

Mistakes that cause rewrites, governance violations, or production outages in FSI environments.

---

### Pitfall 1: Governance Drift Between Terraform and Ansible Implementations

**What goes wrong:** The existing Terraform topic module (`modules/topic/main.tf`) encodes governance rules -- SLA-tier-to-partition mapping, SLA-tier-to-compatibility mapping, topic naming regex, PII enforcement preconditions, retention calculations. When Ansible roles replicate this logic, the two implementations inevitably diverge. A change to the partition map in Terraform (e.g., bumping `critical` from 12 to 16 partitions) does not propagate to Ansible. After six months, Confluent Cloud topics created via Terraform have different governance properties than CP topics created via Ansible, violating the platform's core constraint: "deployment parity."

**Why it happens:** Terraform locals (`local.compatibility_map`, `local.partition_map`, `local.retention_map`) and Ansible defaults (`defaults/main.yml`) are separate codebases with separate review processes. There is no shared governance artifact that both tools consume. The existing topic YAML files (`scenarios/cp-rhel/topics/*.yml`) use a `CPTopic` CRD-like format with hardcoded values, not computed from SLA tier like the Terraform module does.

**Consequences:**
- Audit reveals a "critical" topic on CP-RHEL has 6 partitions (Ansible default) while the same SLA tier on CC has 12 (Terraform computed)
- Schema compatibility mode is BACKWARD on CP but FULL_TRANSITIVE on CC for the same SLA tier, because someone forgot to update the Ansible defaults
- FSI compliance review flags inconsistent retention policies across deployment models
- Teams lose trust in the "golden path" when governance differs by deployment model

**Prevention:**
- Create a single source of truth for governance rules: a shared YAML file (e.g., `governance/sla-tiers.yml`) consumed by both Terraform (via `yamldecode(file(...))`) and Ansible (via `include_vars`)
- Implement a CI validation step that compares Terraform locals and Ansible defaults, failing if they diverge
- The Ansible topic role must compute configurations from SLA tier, not accept hardcoded partition counts and retention values
- Add a governance parity test: create a topic via Terraform (in local Docker SR/broker) and via Ansible, then compare all topic configs and schema settings
- Review the existing `CPTopic` YAML format in `scenarios/cp-rhel/topics/` -- it hardcodes `partitionCount: 12` and `retention.ms: 604800000` instead of deriving from `fsi.sla-tier: critical`. The Ansible role must compute these from the SLA tier label.

**Detection:** Periodic compliance scan comparing topic configurations across deployment models; CI test that creates topics via both tools and diffs configurations

**Phase mapping:** Phase 1 (Ansible governance roles) -- this is the foundational design decision. Get it wrong here and every subsequent phase inherits the drift.

---

### Pitfall 2: cp-ansible Collection Version and Confluent Platform Version Must Match Exactly

**What goes wrong:** Teams install the latest `confluent.platform` collection from Ansible Galaxy but deploy against an older CP version (e.g., collection 8.2.0 against CP 7.6.0 brokers). The collection templates generate configuration properties that don't exist in the older CP version, causing broker startup failures. Conversely, using an old collection version against a newer CP misses critical security patches and new configuration options.

**Why it happens:** The cp-ansible collection follows Confluent Platform versioning (collection 7.7.x deploys CP 7.7.x, collection 8.2.x deploys CP 8.2.x). But `ansible-galaxy collection install confluent.platform` without version pinning installs the latest. The current codebase pins `confluent_package_version: "7.6.0"` in `all.yml` but does not pin the collection version. The Ansible 9.x / RHEL 8 constraint compounds this: RHEL 8 only supports Ansible 9.x (ansible-core 2.16), and Ansible 9.x reached EOL in May 2025. Confluent continues supporting it solely for RHEL 8 compatibility, but newer collection features may not be tested against ansible-core 2.16.

**Consequences:**
- Broker fails to start with `ConfigException: Unknown configuration` for a property added in CP 8.0 but not present in CP 7.6
- Playbook fails with deprecated Ansible module calls because the collection version expects a newer ansible-core
- Subtle behavior differences: a collection upgrade changes the default JMX exporter port or TLS configuration template without the team realizing
- RHEL 8 hosts stuck on Ansible 9.x cannot use collection features that require ansible-core 2.17+

**Prevention:**
- Pin collection version in `requirements.yml` to match `confluent_package_version`:
  ```yaml
  collections:
    - name: confluent.platform
      version: "==7.6.0"
  ```
- Add a preflight assertion in the playbook that validates collection version matches CP version
- Document the RHEL 8 + Ansible 9.x constraint explicitly in the scenario README. For new deployments, prefer RHEL 9 which supports Ansible 9.x through 11.x
- Test collection upgrades in CI against the target CP version before deploying to any environment
- When upgrading CP (e.g., 7.6 to 7.7), upgrade the collection version in the same PR

**Detection:** Broker startup failures with unknown config properties; Ansible deprecation warnings during playbook runs; `ansible-galaxy collection list` shows version mismatch with `confluent_package_version`

**Phase mapping:** Phase 1 (Ansible governance roles) -- pin versions in the first commit. RHEL version decision in Phase 1 affects the entire collection lifecycle.

---

### Pitfall 3: MDS REST API Authentication Token Expiration During Long Playbook Runs

**What goes wrong:** The Ansible RBAC role authenticates to MDS once at the beginning of a playbook run (via `POST /security/1.0/authenticate`), obtains a bearer token, and uses it for all subsequent role binding operations. The MDS token has a default expiration of 900 seconds (15 minutes). A playbook that provisions RBAC for dozens of topics across multiple service accounts takes longer than 15 minutes. Midway through, the token expires and all subsequent `uri` module calls fail with 401 Unauthorized. The playbook reports partial success: some role bindings were created, others were not, leaving the cluster in an inconsistent RBAC state.

**Why it happens:** MDS token lifetime defaults to 15 minutes (`confluent.oidc.session.token.expiry.ms: 900000`). The Ansible `uri` module has no built-in token refresh mechanism. Unlike Terraform (which manages authentication per-resource via the provider), Ansible tasks execute sequentially and rely on a token obtained by an earlier task. Nobody thinks about token lifetime during initial development because test playbooks run in under a minute.

**Consequences:**
- RBAC provisioning completes for topics A-F but fails for G-Z with 401 errors
- The partially-provisioned state is dangerous: some producers have write access, others do not, but the playbook reports "failed" without indicating which bindings succeeded
- Re-running the playbook after fixing the token doesn't know which bindings already exist (idempotency challenge -- see Pitfall 5)
- In FSI environments, partial RBAC means some service accounts can access topics they shouldn't, or cannot access topics they need

**Prevention:**
- Implement a token refresh handler: before each batch of MDS API calls, check token age. If > 80% of expiry window, re-authenticate
- Structure the RBAC role to authenticate per-topic-batch rather than once at playbook start
- Increase MDS token lifetime for automation accounts (but not so high it becomes a security risk): set `auth.token.max.lifetime.ms` to 3600000 (1 hour) for the service account used by Ansible
- Add a `failed_when` check on every MDS `uri` call that detects 401 and triggers re-authentication via a rescue block
- Use `retries` and `delay` with a token-refresh pre-task in the retry loop:
  ```yaml
  - name: Create role binding
    ansible.builtin.uri:
      url: "{{ mds_url }}/security/1.0/principals/User:{{ item.principal }}/roles/{{ item.role }}/bindings"
      headers:
        Authorization: "Bearer {{ mds_token }}"
      status_code: [200, 204]
    register: result
    retries: 2
    delay: 5
    until: result.status != 401
  ```

**Detection:** Playbook fails partway through RBAC tasks with 401 status; `result.json` shows "Authentication required" mid-playbook; RBAC audit reveals missing bindings for topics later in alphabetical order

**Phase mapping:** Phase 1 (RBAC role) -- must be designed into the role from the start, not bolted on after the first timeout incident

---

### Pitfall 4: Schema Registry REST API Compatibility Check Happens at Registration, Not at Validation Time

**What goes wrong:** Teams build an Ansible role that validates Avro schema JSON syntax (parsing, required fields) and then registers the schema via `POST /subjects/{subject}/versions`. They assume that if validation passes, registration will succeed. But Schema Registry performs compatibility checking at registration time against the previously registered version. A schema that is syntactically valid but not backward-compatible with the existing version is rejected with a 409 Conflict. The Ansible playbook fails mid-run after some schemas registered but before others, leaving the schema state inconsistent.

**Why it happens:** The Schema Registry REST API separates two operations: (1) `POST /compatibility/subjects/{subject}/versions/latest` (compatibility check, non-mutating) and (2) `POST /subjects/{subject}/versions` (registration, mutating). Most Ansible implementations skip step 1 and go straight to step 2. When step 2 fails for one schema in a batch, earlier schemas in the same playbook run have already been registered -- you cannot easily roll back a schema registration (requires soft delete + hard delete, which has its own pitfalls).

**Consequences:**
- Schema A registered successfully, Schema B failed compatibility, Schema C was never attempted. The cluster now has Schema A at a new version but Schema B is still at the old version -- a governance inconsistency
- The error message from SR's `POST /subjects/{subject}/versions` says "Schema being registered is incompatible" but does not say WHY. Teams must add `?verbose=true` to the compatibility check endpoint to see the specific incompatibility
- Schema Registry deleting a soft-deleted subject also removes its compatibility settings -- if someone tries to clean up by deleting and re-registering, the compatibility mode is lost
- Schema IDs are permanent: even after soft+hard deleting a schema version, the canonical MD5 hash persists. Re-registering the same schema gets the same ID, but re-registering a different schema gets a new ID. This is confusing when debugging registration failures.

**Prevention:**
- The Ansible schema role must always call the compatibility check endpoint FIRST:
  ```yaml
  - name: Check schema compatibility
    ansible.builtin.uri:
      url: "{{ sr_url }}/compatibility/subjects/{{ subject }}/versions/latest?verbose=true"
      method: POST
      body_format: json
      body:
        schema: "{{ schema_content }}"
        schemaType: "AVRO"
      status_code: [200]
    register: compat_result

  - name: Fail early if incompatible
    ansible.builtin.fail:
      msg: "Schema {{ subject }} is incompatible: {{ compat_result.json.messages }}"
    when: not compat_result.json.is_compatible
  ```
- Run ALL compatibility checks before ANY registrations (two-pass approach: validate all, then register all)
- Never use schema deletion as a rollback mechanism in production -- it removes compatibility settings and schema IDs are permanent
- Log the full compatibility check response (with `verbose=true`) for debugging

**Detection:** Playbook fails with 409 on schema registration; `verbose=true` compatibility check shows the specific incompatibility; schema registry has partially-updated subjects

**Phase mapping:** Phase 1 (schema registration role) -- two-pass validate-then-register pattern must be the default

---

### Pitfall 5: Ansible Topic Management via REST API Is Not Natively Idempotent

**What goes wrong:** Ansible's `uri` module makes HTTP requests. Creating a Kafka topic via the Admin REST API (`POST /kafka/v3/clusters/{cluster_id}/topics`) returns 201 on success and 400 if the topic already exists. The Ansible task fails on re-run because the topic already exists. Teams work around this with `failed_when: result.status not in [201, 400]` but then lose the ability to detect actual errors (malformed request also returns 400). Updating topic configs is a separate API (`PUT /kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs:alter`) that does not create the topic. There is no single "ensure topic exists with these configs" idempotent endpoint.

**Why it happens:** The Kafka Admin REST API follows standard REST semantics: POST creates (not idempotent), PUT updates (idempotent), GET reads. There is no Ansible module for Confluent Platform topic management (unlike the Confluent Terraform provider which handles create-or-update internally). The `ansible.builtin.uri` module is a generic HTTP client with no understanding of Kafka semantics.

**Consequences:**
- Playbook reports "changed" on every run even when nothing actually changed (breaking idempotency CI tests)
- Error masking: `failed_when: result.status not in [201, 400]` swallows real 400 errors (invalid config, malformed JSON)
- Config drift: topic was created with 6 partitions but the playbook now declares 12. The POST fails (topic exists), the config update is never attempted, and nobody notices the drift
- Partition count cannot be decreased after creation -- attempting to update to fewer partitions silently fails or errors
- `min.insync.replicas` changes require careful ordering (lower first, then change replication, then raise) which simple uri calls don't handle

**Prevention:**
- Build a three-step idempotent pattern in the topic role:
  1. **GET** the topic: `GET /kafka/v3/clusters/{cluster_id}/topics/{topic_name}` -- if 404, create; if 200, compare configs
  2. **CREATE** if absent: `POST /kafka/v3/clusters/{cluster_id}/topics` -- only when step 1 returned 404
  3. **UPDATE** if configs differ: `PUT /kafka/v3/clusters/{cluster_id}/topics/{topic_name}/configs:alter` -- only when step 1 returned 200 and configs don't match
- Use `changed_when` carefully: `changed_when: result.status == 201` for creation, `changed_when: config_changed` for updates
- Document explicitly that partition count can only increase, never decrease. The role should fail with a clear message if a decrease is attempted.
- Consider using the Confluent CLI (`confluent kafka topic create --if-not-exists`) as a fallback, which handles idempotency natively, but note the CLI must be installed on the target host or delegated
- Alternatively, write a custom Ansible module in Python that wraps the `confluent_kafka.admin.AdminClient` for proper idempotent topic management

**Detection:** Ansible reports "changed" tasks on every run; `molecule idempotence` test fails; topic configurations don't match what the role declares; partition count warnings in broker logs

**Phase mapping:** Phase 1 (topic lifecycle role) -- the idempotent pattern must be established before any topic is created via Ansible

---

### Pitfall 6: Ansible Vault vs HashiCorp Vault Naming Confusion Causes Security Incidents

**What goes wrong:** The codebase already uses both: Ansible Vault for encrypting inventory secrets (`vault_mds_password`, `vault_kafka_broker_password` in `all.yml`) and HashiCorp Vault for dynamic secrets in production (referenced in Connect configs, ADR decisions). A developer writes documentation saying "store the MDS password in Vault" without specifying which Vault. Another developer stores the MDS superuser password in HashiCorp Vault but doesn't encrypt the playbook's Vault lookup token with Ansible Vault. Now the HashiCorp Vault token is in plaintext in the inventory file, committed to Git.

**Why it happens:** The term "Vault" is overloaded. Ansible Vault is a file/string encryption tool (`ansible-vault encrypt_string`). HashiCorp Vault is a secrets management server accessed via `community.hashi_vault` lookup plugin. The existing `all.yml` uses `{{ vault_mds_password }}` syntax which is Ansible Vault (the variable is decrypted from an encrypted vars file). But the production architecture uses HashiCorp Vault for credential rotation. When Ansible roles need to fetch dynamic credentials from HashiCorp Vault at runtime, the lookup plugin configuration (Vault address, token, mount path) itself needs to be secured -- typically via Ansible Vault encryption.

**Consequences:**
- HashiCorp Vault tokens committed in plaintext to Git (the developer thought "it's in Vault" meant it was safe)
- Ansible Vault password shared via Slack because the team doesn't have a password management process for it
- MDS superuser credentials stored in Ansible Vault at rest but logged in plaintext in Ansible output (no `no_log: true`)
- FSI security audit flags credential management as non-compliant

**Prevention:**
- Establish and document a clear naming convention in the project:
  - `ansible-vault` (hyphenated, lowercase) = Ansible's built-in encryption tool
  - `HashiCorp Vault` or `hcv` (abbreviated) = the secrets management server
  - Variable prefix: `ansible_vault_*` for Ansible Vault configs, `hcv_*` for HashiCorp Vault configs
- For production: use `community.hashi_vault.vault_read` lookup to fetch secrets at runtime:
  ```yaml
  mds_super_user_password: "{{ lookup('community.hashi_vault.vault_read', 'secret/data/confluent/mds').data.data.password }}"
  ```
- Encrypt the HashiCorp Vault authentication (AppRole `role_id` and `secret_id`) using Ansible Vault
- Add `no_log: true` to every task that handles passwords, tokens, or API keys
- Add a CI check that scans for plaintext secrets in inventory files (use `detect-secrets` or `gitleaks`)
- Never store the Ansible Vault password in the repository -- use `--vault-password-file` pointing to a CI secret or a HashiCorp Vault lookup

**Detection:** `gitleaks` or `detect-secrets` finds tokens in inventory; Ansible output logs contain passwords; security audit reveals unencrypted credential files in Git history

**Phase mapping:** Phase 1 (security foundation) -- naming convention and secret management pattern must be established before any role uses credentials

---

## Moderate Pitfalls

Mistakes that cause significant rework, delayed delivery, or degraded operations.

---

### Pitfall 7: MDS RBAC Role Bindings Lack a "Desired State" API -- Incremental Only

**What goes wrong:** The MDS REST API provides endpoints to ADD role bindings (`POST /security/1.0/principals/User:{principal}/roles/{role}/bindings`) and DELETE role bindings (`DELETE /security/1.0/principals/User:{principal}/roles/{role}/bindings`). There is no "set these exact bindings and remove everything else" (desired-state) endpoint. When a team removes a consumer from the topic YAML definition, the Ansible role adds new bindings but never removes old ones. Over time, service accounts accumulate stale RBAC bindings -- a compliance violation in FSI environments where least-privilege is mandatory.

**Why it happens:** Terraform handles this naturally: removing a `confluent_role_binding` resource from code causes `terraform plan` to show the deletion. The MDS REST API is imperative (add/remove individual bindings), not declarative (here is the full desired state). Ansible's `uri` module calls are also imperative. Without explicit state tracking, the role has no way to know what bindings currently exist vs. what should exist.

**Consequences:**
- Former team members' service accounts retain access to sensitive topics for months after access should have been revoked
- RBAC audit shows hundreds of stale bindings that nobody can explain
- A security incident investigation is complicated by excessive permissions that mask the actual access pattern
- Manual cleanup is error-prone: removing the wrong binding breaks a production consumer

**Prevention:**
- Implement a reconciliation pattern in the RBAC role:
  1. **LIST** current bindings: `POST /security/1.0/lookup/principals/User:{principal}/roleNames` and per-role `POST /security/1.0/lookup/role/{role}/resource/{resourceType}/name/{name}`
  2. **DIFF** against desired state (from topic YAML definitions)
  3. **ADD** missing bindings
  4. **REMOVE** extra bindings (with a safety flag: `rbac_remove_stale: true` must be explicitly set)
- Log all binding additions and removals for audit trail
- Implement a "dry-run" mode that reports what would be added/removed without executing
- Add a periodic RBAC audit playbook that lists all bindings and compares against the declared topology

**Detection:** `POST /security/1.0/lookup/principals/User:{principal}/roleNames` returns roles not declared in any topic YAML; RBAC audit report shows growing binding count over time

**Phase mapping:** Phase 1 (RBAC role) -- the reconciliation pattern is a design decision. Starting with "add only" and bolting on removal later is how stale bindings accumulate.

---

### Pitfall 8: RHEL 8 vs RHEL 9 Creates a Bifurcated Testing Matrix

**What goes wrong:** RHEL 8 limits Ansible to version 9.x (ansible-core 2.16) while RHEL 9 supports Ansible 9.x through 11.x. The team writes Ansible roles that work on RHEL 9 with Ansible 11 but fails on RHEL 8 because ansible-core 2.16 doesn't support a module parameter introduced in 2.17. Additionally, RHEL 9 is required for FIPS 140-3 compliance (RHEL 8 only supports FIPS 140-2 compatibility mode). Avro and libserdes RPM packages are not available for RHEL 9, replaced by libschemaregistry which requires CMake integration.

**Why it happens:** RHEL 8 reached maintenance support in May 2024 but many FSI shops still run it due to change management cadence. Confluent explicitly supports RHEL 8 with Ansible 9.x and will continue to, but Ansible 9.x is EOL. This creates a "supported but deprecated" limbo where the combination works but receives no new Ansible fixes.

**Consequences:**
- Roles tested only on RHEL 9 fail on RHEL 8 customer environments
- FIPS 140-3 features (`fips_enabled: true` + `fips_mode: fips-140-3`) require RHEL 9 but the playbook doesn't validate this
- Python version differences (RHEL 8 ships Python 3.6 by default, though 3.11+ is available via AppStream) cause collection dependency failures
- Molecule tests that pass in RHEL 9 containers fail in RHEL 8 containers due to different default packages

**Prevention:**
- Support RHEL 8 and RHEL 9 explicitly with separate Molecule scenarios and CI matrix:
  ```yaml
  # molecule/rhel8/molecule.yml
  platforms:
    - name: rhel8-instance
      image: registry.access.redhat.com/ubi8/ubi-init:latest
  # molecule/rhel9/molecule.yml
  platforms:
    - name: rhel9-instance
      image: registry.access.redhat.com/ubi9/ubi-init:latest
  ```
- Add preflight assertions for FIPS mode:
  ```yaml
  - name: Validate RHEL 9 for FIPS 140-3
    ansible.builtin.assert:
      that: ansible_distribution_major_version | int >= 9
      fail_msg: "FIPS 140-3 requires RHEL 9. RHEL 8 supports FIPS 140-2 only."
    when: fips_mode == "fips-140-3"
  ```
- Pin Ansible version per RHEL version in CI: RHEL 8 tests use Ansible 9.x, RHEL 9 tests use Ansible 11.x
- Document clearly: "New deployments should target RHEL 9. RHEL 8 is supported for existing installations only."
- Ensure Python 3.11+ is installed on RHEL 8 hosts (via `python3.11` AppStream package) before running the collection

**Detection:** Molecule CI matrix shows RHEL 8 failures while RHEL 9 passes; FIPS validation playbook fails on RHEL 8 with cryptographic errors; Python version mismatch errors in collection imports

**Phase mapping:** Phase 2 (CI/CD for Ansible) -- the CI matrix decision must be made early to avoid "works on my machine" issues

---

### Pitfall 9: Molecule Cannot Test cp-ansible Roles in Containers Without Systemd

**What goes wrong:** cp-ansible roles deploy Confluent Platform components as systemd services. Molecule's default Docker/Podman driver runs containers without a proper init system. When the cp-ansible `kafka_broker` role attempts `systemctl start confluent-kafka`, it fails because systemd is not PID 1 in the container. Teams either skip integration testing entirely or write Molecule tests that only test their custom governance roles (topic, schema, RBAC) but never test the full deployment pipeline.

**Why it happens:** Docker containers are designed to run a single process, not a full init system. systemd requires `--privileged` mode, cgroup mounts, and `/sbin/init` as the entrypoint. Standard UBI images don't enable this by default. Podman has better systemd support than Docker, but still requires specific configuration (`container_manage_cgroup: true` on RHEL 8 with SELinux).

**Consequences:**
- Molecule tests cover custom roles but not the cp-ansible integration -- the most failure-prone part
- A configuration change in the governance role breaks cp-ansible's broker deployment, but this is only discovered in staging, not CI
- Teams resort to testing on full VMs (Vagrant, cloud instances), which is slow and expensive
- CI pipeline has a false sense of security: "all Molecule tests pass" but the actual deployment has never been tested end-to-end in CI

**Prevention:**
- Use Molecule with Podman and `ubi-init` images that include systemd:
  ```yaml
  platforms:
    - name: kafka-broker
      image: registry.access.redhat.com/ubi9/ubi-init:latest
      command: /sbin/init
      privileged: true
      volumes:
        - /sys/fs/cgroup:/sys/fs/cgroup:rw
  ```
- Separate test strategies by role type:
  - **Custom governance roles** (topic, schema, RBAC): Test via Molecule against a pre-deployed CP cluster (Docker Compose with CP images, similar to existing `reference/local-dev/docker-compose.yml`)
  - **cp-ansible integration**: Test via Molecule with `ubi-init` + systemd or via scheduled CI runs against ephemeral VMs (weekly, not per-PR)
- For the governance roles specifically, mock the REST API endpoints in Molecule verify steps rather than requiring a running broker
- Document the Molecule driver requirements clearly: "Podman recommended, Docker requires `--privileged`"
- Add a CI "integration" job that runs the full deployment on a provisioned RHEL VM (nightly or on `main` merge, not on every PR)

**Detection:** Molecule converge step fails with `Failed to connect to bus: No such file or directory` (systemd socket missing); CI passes but staging deployment fails; `systemctl` commands return "System has not been booted with systemd"

**Phase mapping:** Phase 2 (CI/CD) -- test strategy must be designed before writing Molecule scenarios for governance roles

---

### Pitfall 10: CFK Deployment via kubernetes.core.helm Requires Careful Timeout and Wait Configuration

**What goes wrong:** Deploying CFK operator and Confluent components via `kubernetes.core.helm` module in Ansible appears to succeed (Helm release created) but the underlying pods are not yet ready. The next Ansible task -- creating topics or registering schemas -- fails because Schema Registry or Kafka brokers are still starting up. The `kubernetes.core.helm` module's `wait` parameter does not wait for all pods to become ready by default, only for Helm hooks to complete.

**Why it happens:** CFK deployment is a multi-phase process: (1) Helm installs the CFK operator, (2) operator creates CRDs, (3) applying Confluent CRDs triggers the operator to create StatefulSets, (4) StatefulSets create pods, (5) pods reach Ready state. Step 1 completes quickly but steps 2-5 take 5-15 minutes depending on cluster resources. The Ansible `kubernetes.core.helm` module returns success after step 1 unless `wait: true` and an adequate `wait_timeout` are set. Even with `wait: true`, the default timeout may be too short for FSI environments with strict PodSecurityPolicies and image pull policies (private registries, image scanning).

**Consequences:**
- Governance playbook tasks (topic creation, schema registration, RBAC) fail because CP components are not ready
- Re-running the playbook creates duplicate Helm releases or conflicts with the partially-deployed operator
- OpenShift-specific SCC validation adds startup latency that exceeds the default timeout
- Teams add `pause` tasks with fixed delays (e.g., `ansible.builtin.pause: minutes: 10`) which is brittle and wasteful

**Prevention:**
- Set explicit `wait: true` and generous `wait_timeout` on the Helm task:
  ```yaml
  - name: Deploy CFK operator
    kubernetes.core.helm:
      name: confluent-operator
      chart_ref: confluentinc/confluent-for-kubernetes
      release_namespace: confluent
      wait: true
      wait_timeout: "15m0s"
  ```
- After Helm deployment, add explicit readiness checks using `kubernetes.core.k8s_info`:
  ```yaml
  - name: Wait for Kafka cluster ready
    kubernetes.core.k8s_info:
      api_version: platform.confluent.io/v1beta1
      kind: Kafka
      namespace: confluent
    register: kafka_status
    until: kafka_status.resources[0].status.phase == "RUNNING"
    retries: 30
    delay: 30
  ```
- Separate the deployment playbook from the governance playbook. Run deployment first, verify readiness, then run governance. Do not chain them in a single playbook without explicit health gates.
- For OpenShift: pre-create the SCC and bind it to service accounts BEFORE the Helm install (existing Pitfall 2 from v1.0 research still applies)

**Detection:** Ansible tasks after Helm deploy fail with connection refused or 503 errors; `kubectl get pods -n confluent` shows pods in `ContainerCreating` or `Init` state when governance tasks run

**Phase mapping:** Phase 3 (CFK deployment via Ansible) -- deployment and governance must be separate playbooks with health gates between them

---

### Pitfall 11: Schema Registry REST API Authentication Differs Between CC, CP, and CFK

**What goes wrong:** The Ansible schema registration role works against the local Docker Compose Schema Registry (no auth) but fails against CP (basic auth with MDS) and CFK (mTLS with certificates). The `uri` module call needs different `headers`, `client_cert`, `client_key`, and `url_username`/`url_password` parameters depending on the deployment model. A single role that works across all three requires careful parameterization that most implementations get wrong on the first attempt.

**Why it happens:** Schema Registry authentication varies:
- **Confluent Cloud:** API key + secret as HTTP basic auth
- **CP on RHEL (MDS RBAC):** Bearer token from MDS authentication, or basic auth if RBAC is disabled
- **CFK on OpenShift:** mTLS client certificates, or bearer token via MDS
- **Local Docker Compose:** No authentication
The `uri` module doesn't abstract this -- each auth method needs different parameters.

**Consequences:**
- Role works in development (no auth Docker Compose) but fails in staging (CP with MDS basic auth)
- mTLS certificates for CFK require `client_cert` and `client_key` parameters that are ignored in the CP basic auth path -- conditional logic gets messy
- Token-based auth (MDS) and API-key auth (CC) have different header formats (`Authorization: Bearer <token>` vs `Authorization: Basic <base64>`)
- TLS verification (`validate_certs`) must be `true` in production but `false` in development with self-signed certs -- a forgotten toggle causes CI to pass but prod to fail

**Prevention:**
- Design the schema role with an `sr_auth_type` variable:
  ```yaml
  sr_auth_type: "none"  # none | basic | bearer | mtls
  sr_url: "https://schema-registry:8081"
  sr_username: ""        # for basic auth
  sr_password: ""        # for basic auth
  sr_token: ""           # for bearer (MDS)
  sr_client_cert: ""     # for mTLS
  sr_client_key: ""      # for mTLS
  sr_validate_certs: true
  ```
- Use a shared task file for SR API calls that branches on `sr_auth_type`:
  ```yaml
  - name: Register schema
    ansible.builtin.uri:
      url: "{{ sr_url }}/subjects/{{ subject }}/versions"
      method: POST
      headers: "{{ sr_headers }}"
      client_cert: "{{ sr_client_cert | default(omit) }}"
      client_key: "{{ sr_client_key | default(omit) }}"
      validate_certs: "{{ sr_validate_certs }}"
      body_format: json
      body:
        schema: "{{ schema_content }}"
        schemaType: "AVRO"
  ```
- Test each auth mode in Molecule: one scenario per auth type
- The `sr_headers` variable should be computed based on `sr_auth_type`, not hardcoded

**Detection:** Role works locally but fails with 401/403 in CP or CFK environments; mTLS handshake failures logged in SR; `validate_certs: false` accidentally deployed to production

**Phase mapping:** Phase 1 (schema role) -- the auth abstraction must be built into the role interface from day one

---

## Minor Pitfalls

Mistakes that cause delays or friction but are recoverable.

---

### Pitfall 12: Ansible `uri` Module POST Requests Always Report "changed" Even When Nothing Changed

**What goes wrong:** Every `uri` module call with `method: POST` reports `changed: true` in Ansible output, regardless of whether the API call actually modified anything. This breaks idempotency reporting: `ansible-playbook --check` cannot predict whether a change will happen, and `molecule idempotence` tests always fail because POST tasks always report changed.

**Why it happens:** The `uri` module is a generic HTTP client. It does not understand REST API semantics. POST always reports changed because Ansible assumes any non-GET request is a mutation. There is no built-in mechanism to compare the current state with the desired state.

**Prevention:**
- Use `changed_when` on every `uri` task:
  ```yaml
  - name: Create topic
    ansible.builtin.uri:
      url: "{{ admin_url }}/kafka/v3/clusters/{{ cluster_id }}/topics"
      method: POST
      body: "{{ topic_config }}"
      status_code: [201, 400]  # 400 = already exists
    register: result
    changed_when: result.status == 201
  ```
- For update operations, compare current config with desired before making the call
- Add `check_mode: false` to API calls that are read-only (GET requests used for state comparison)
- Document this limitation in the role's README so consumers understand why `molecule idempotence` requires careful `changed_when` tuning

**Detection:** `molecule idempotence` tests fail on all REST API tasks; Ansible reports 100% changed tasks on re-runs; `--diff` output shows no actual differences

**Phase mapping:** Phase 1 (all roles using `uri`) -- establish the `changed_when` convention in the first role and apply it consistently

---

### Pitfall 13: Missing `no_log: true` on URI Tasks Exposes Credentials in Ansible Output

**What goes wrong:** Ansible's `uri` module logs the full request and response by default, including `Authorization` headers (Bearer tokens, Basic auth credentials) and response bodies (which may contain API keys or tokens). In CI/CD systems with persistent logs (GitHub Actions, Jenkins), these credentials are visible to anyone with log access.

**Why it happens:** Ansible's default behavior is to log task details for debugging. The `uri` module is especially problematic because it logs both request headers and response bodies. While Ansible has `no_log: true` to suppress output, it must be explicitly set on every task that handles sensitive data. Developers writing initial roles focus on functionality, not security -- `no_log` is added later (if at all).

**Prevention:**
- Add `no_log: true` to every `uri` task that includes authentication headers:
  ```yaml
  - name: Authenticate to MDS
    ansible.builtin.uri:
      url: "{{ mds_url }}/security/1.0/authenticate"
      method: POST
      url_username: "{{ mds_user }}"
      url_password: "{{ mds_password }}"
    register: mds_auth
    no_log: true
  ```
- Create an `ansible-lint` custom rule that flags `uri` tasks without `no_log: true` when `Authorization` is in the headers or `url_password` is set
- For debugging: use `ANSIBLE_LOG_PATH` to a local file (not CI output) and set `no_log: false` only for the specific task being debugged
- Review all existing `uri` tasks in the CP-RHEL playbooks for credential exposure

**Detection:** `grep -r "Authorization" /var/log/ansible/` finds tokens in logs; GitHub Actions log viewer shows base64-encoded credentials; security scan flags credential exposure in CI logs

**Phase mapping:** Phase 1 (all roles) -- add `no_log` to every role from the start. Retrofitting is painful and credentials may already be in log history.

---

### Pitfall 14: Ansible `hash_behaviour=merge` Required by cp-ansible But Deprecated

**What goes wrong:** cp-ansible requires `ANSIBLE_HASH_BEHAVIOUR=merge` to properly merge group_vars dictionaries (e.g., `kafka_broker.yml` overriding values from `all.yml`). Without this setting, Ansible uses `replace` behavior, which means group_vars in `kafka_broker.yml` completely overwrite variables from `all.yml` instead of merging. But `hash_behaviour=merge` was deprecated in ansible-core 2.15+ and may be removed in future versions. Teams upgrading Ansible get deprecation warnings that become errors.

**Why it happens:** cp-ansible's inventory structure relies on hierarchical variable merging: common settings in `all.yml`, component-specific overrides in `kafka_broker.yml`, `schema_registry.yml`, etc. Ansible's default `replace` behavior would require duplicating all common variables in every component group_vars file. Confluent's documentation and troubleshooting guide explicitly recommend setting `ANSIBLE_HASH_BEHAVIOUR=merge`.

**Consequences:**
- Without merge behavior: broker deploys with missing TLS settings because `kafka_broker.yml` replaced `all.yml` instead of merging
- With merge behavior: deprecation warnings fill CI logs, and future Ansible versions may break the entire deployment
- Inconsistent behavior if `ANSIBLE_HASH_BEHAVIOUR` is set on the control node but not in `ansible.cfg`

**Prevention:**
- Set `hash_behaviour = merge` in the project's `ansible.cfg` (not just as an environment variable):
  ```ini
  [defaults]
  hash_behaviour = merge
  ```
- Document this requirement prominently in the README
- Monitor ansible-core release notes for the eventual removal of `hash_behaviour=merge`
- Plan a migration strategy: when cp-ansible drops the merge requirement (or when Ansible removes the option), refactor inventory to use `combine` filter or explicit variable nesting
- Pin ansible-core version to avoid unexpected breakage from the deprecation becoming an error

**Detection:** Broker starts with default (non-TLS) configuration despite TLS being set in `all.yml`; Ansible output shows `[DEPRECATION WARNING]: hash_behaviour`; component-specific vars silently override common vars

**Phase mapping:** Phase 1 (Ansible setup) -- configure `ansible.cfg` in the first commit. The merge behavior affects every cp-ansible role.

---

### Pitfall 15: Confluent Admin REST API vs Confluent REST Proxy vs MDS API Confusion

**What goes wrong:** Confluent Platform exposes multiple REST APIs on different ports with overlapping functionality. The Admin REST API (embedded in brokers, port 8090 by default) handles topic CRUD. The REST Proxy (separate component, port 8082) handles produce/consume but cannot create topics. The MDS API (embedded in brokers, port 8090) handles RBAC. Teams mix up endpoints, send topic creation requests to the REST Proxy (fails), or send RBAC requests to the Admin REST API without the MDS path prefix (fails).

**Why it happens:** The Admin REST API and MDS API share the same port (8090) but have different path prefixes. The REST Proxy is a separate component entirely. The Confluent documentation uses different terminology in different places. The Ansible roles need clear endpoint configuration for each API type.

**Consequences:**
- Topic creation task sends POST to REST Proxy endpoint (port 8082) and gets 404 or 405
- RBAC task sends POST to `/kafka/v3/...` (Admin API path) instead of `/security/1.0/...` (MDS path)
- Role variables mix `kafka_rest_url`, `admin_rest_url`, `mds_url`, and `sr_url` -- developers use the wrong one

**Prevention:**
- Define clear, well-documented variables for each API:
  ```yaml
  # Admin REST API (topic management) -- embedded in broker
  cp_admin_rest_url: "https://{{ broker_host }}:8090"
  # MDS API (RBAC) -- embedded in broker, same port, different path
  cp_mds_url: "https://{{ broker_host }}:8090"
  # Schema Registry API -- separate component
  cp_sr_url: "https://{{ sr_host }}:8081"
  # REST Proxy (produce/consume only) -- separate component, NOT for admin ops
  cp_rest_proxy_url: "https://{{ rest_proxy_host }}:8082"
  ```
- Add comments in the role's `defaults/main.yml` explaining which API each URL targets
- Validate endpoints in a preflight task: call a known health endpoint for each API and assert the expected response
- The REST Proxy should never appear in governance roles -- it's for produce/consume only

**Detection:** 404 or 405 responses from `uri` tasks; topic creation fails but SR registration succeeds (different endpoints); RBAC tasks get "not found" because they're hitting the Admin API path instead of MDS path

**Phase mapping:** Phase 1 (role defaults) -- correct endpoint naming and validation must be in the initial role skeleton

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation | Severity |
|-------------|---------------|------------|----------|
| Ansible governance roles (topic lifecycle) | Governance drift from Terraform (Pitfall 1) | Shared governance YAML consumed by both Terraform and Ansible | Critical |
| Ansible governance roles (topic lifecycle) | REST API non-idempotency (Pitfall 5) | Three-step GET/CREATE/UPDATE pattern with `changed_when` | Critical |
| Ansible governance roles (schema registration) | SR compatibility check at registration only (Pitfall 4) | Two-pass validate-then-register pattern | Critical |
| Ansible governance roles (RBAC via MDS) | MDS token expiration (Pitfall 3) | Token refresh handler, per-batch authentication | Critical |
| Ansible governance roles (RBAC via MDS) | No desired-state RBAC API (Pitfall 7) | LIST/DIFF/ADD/REMOVE reconciliation pattern | Moderate |
| Ansible governance roles (all) | `uri` module always reports changed (Pitfall 12) | `changed_when` on every POST/PUT task | Minor |
| Ansible governance roles (all) | Credential exposure in logs (Pitfall 13) | `no_log: true` on all auth tasks | Minor |
| Ansible governance roles (all) | SR auth varies by deployment (Pitfall 11) | `sr_auth_type` variable with conditional headers | Moderate |
| Ansible governance roles (all) | API endpoint confusion (Pitfall 15) | Clear variable naming, preflight validation | Minor |
| cp-ansible integration | Collection/CP version mismatch (Pitfall 2) | Pin collection version in `requirements.yml` to match CP version | Critical |
| cp-ansible integration | `hash_behaviour=merge` deprecated (Pitfall 14) | Set in `ansible.cfg`, pin ansible-core version | Minor |
| Security and secrets | Ansible Vault vs HashiCorp Vault confusion (Pitfall 6) | Naming convention, `no_log`, `gitleaks` scanning | Critical |
| CI/CD for Ansible | RHEL 8 vs RHEL 9 matrix (Pitfall 8) | Dual Molecule scenarios, per-version CI matrix | Moderate |
| CI/CD for Ansible | Molecule + systemd containers (Pitfall 9) | Podman + `ubi-init` images, separated test strategies | Moderate |
| CFK deployment via Ansible | Helm timeout and readiness (Pitfall 10) | Explicit `wait_timeout`, CRD readiness checks, separate playbooks | Moderate |

---

## Integration Pitfalls (Terraform + Ansible Coexistence)

These pitfalls are specific to running Terraform and Ansible side-by-side in the same platform.

| Integration Risk | Description | Mitigation |
|-----------------|-------------|------------|
| **Topic name format divergence** | Terraform assembles topic names from variables (`${var.domain}.${var.application}.${var.schema_version}.${var.entity}`). Ansible roles must use the identical formula. | Share the naming regex in a governance YAML file. Both tools validate against it. |
| **SLA tier logic duplication** | Terraform has `local.compatibility_map`, `local.partition_map`, `local.retention_map`. Ansible must have identical maps. | Single `sla-tiers.yml` file consumed by both. CI test that cross-validates. |
| **RBAC model mismatch** | Terraform uses Confluent Cloud RBAC (CRN-based). Ansible uses MDS RBAC (resource pattern-based). Same logical intent, different API shapes. | Document the mapping: CC `DeveloperWrite` on CRN = CP `DeveloperWrite` on MDS resource pattern. Test both produce identical effective permissions. |
| **Schema subject naming** | Terraform uses TopicNameStrategy (`{topic}-value`). Ansible must use the same strategy, not RecordNameStrategy or TopicRecordNameStrategy. | Hardcode TopicNameStrategy in the Ansible schema role. Validate in CI. |
| **Drift detection** | Terraform has `terraform plan` for drift detection. Ansible has no equivalent -- playbooks don't report "your cluster has drifted." | Build an Ansible audit playbook that reads current topic/schema/RBAC state and diffs against declared state. Run weekly. |
| **Shared schema library** | Both tools need the same `.avsc` files from `schemas/`. Terraform uses `file()`. Ansible uses `lookup('file', ...)`. | Schemas stay in `schemas/` directory. Both tools reference the same files. CI validates schemas exist. |

---

## Sources

- [Confluent Ansible Requirements and Compatibility Matrix](https://docs.confluent.io/ansible/current/ansible-requirements.html) -- RHEL 8/9 constraints, Ansible version matrix, Python requirements (HIGH confidence)
- [Confluent Ansible Troubleshooting](https://docs.confluent.io/ansible/current/ansible-troubleshooting.html) -- Known issues, hash behaviour, collection dependency errors (HIGH confidence)
- [Confluent Ansible Release Notes](https://docs.confluent.io/ansible/current/ansible-release-notes.html) -- Collection 8.2.0 features, RHEL 10 support, FIPS 140-3 (HIGH confidence)
- [Confluent MDS REST API Reference](https://docs.confluent.io/platform/current/security/authorization/rbac/mds-api.html) -- Endpoint paths, authentication, role binding operations (HIGH confidence)
- [Configure RBAC using REST API](https://docs.confluent.io/platform/current/security/authorization/rbac/rbac-config-using-rest-api.html) -- MDS authentication, component roles, binding patterns (HIGH confidence)
- [MDS Token Configuration](https://docs.confluent.io/platform/current/kafka/configure-mds/mds-configuration.html) -- Token expiry defaults, session timeout settings (HIGH confidence)
- [Schema Registry API Reference](https://docs.confluent.io/platform/current/schema-registry/develop/api.html) -- REST endpoints, compatibility check, verbose mode (HIGH confidence)
- [Schema Deletion Guidelines](https://docs.confluent.io/platform/current/schema-registry/schema-deletion-guidelines.html) -- Soft/hard delete behavior, schema ID persistence, compatibility setting removal (HIGH confidence)
- [Schema Evolution and Compatibility](https://docs.confluent.io/platform/current/schema-registry/fundamentals/schema-evolution.html) -- Compatibility modes, backward/forward/full (HIGH confidence)
- [cp-ansible GitHub Repository](https://github.com/confluentinc/cp-ansible) -- Collection source, open issues (MEDIUM confidence)
- [community.hashi_vault Collection](https://github.com/ansible-collections/community.hashi_vault) -- Naming rationale, Ansible Vault vs HashiCorp Vault distinction (HIGH confidence)
- [HashiCorp Vault Issue #3726](https://github.com/hashicorp/vault/issues/3726) -- Community discussion on naming confusion (MEDIUM confidence)
- [Molecule Documentation](https://docs.ansible.com/projects/molecule/philosophy/) -- Testing philosophy, scenarios, Podman driver (HIGH confidence)
- [Molecule + Systemd Testing](https://medium.com/@TomaszKlosinski/testing-ansible-role-of-a-systemd-based-service-using-molecule-and-docker-4b3608a10ef0) -- Container systemd limitations, privileged mode requirements (MEDIUM confidence)
- [Developing Ansible Roles with Molecule and Podman](https://www.ansible.com/blog/developing-and-testing-ansible-roles-with-molecule-and-podman-part-1/) -- Podman advantages, rootless testing, SELinux cgroup boolean (MEDIUM confidence)
- [kubernetes.core.helm Module](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/helm_module.html) -- wait_timeout, Helm v3 support (HIGH confidence)
- [CFK Release Notes](https://docs.confluent.io/operator/current/release-notes.html) -- CFK 3.2.x supports OCP 4.14-4.21 (HIGH confidence)
- [ansible.builtin.uri Module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/uri_module.html) -- HTTP client behavior, changed_when, no_log (HIGH confidence)
- Codebase analysis: `modules/topic/main.tf`, `modules/topic/variables.tf`, `scenarios/cp-rhel/` (all files), `inventory/group_vars/all.yml` (HIGH confidence)
- `.planning/PROJECT.md` -- v2.0 milestone requirements and constraints (HIGH confidence)

**Confidence note:** Pitfalls 1, 5, 7, and the Integration Pitfalls section are derived from direct analysis of the codebase's existing Terraform governance logic compared against what the Ansible roles will need to replicate. MDS API behavior (Pitfalls 3, 7) is verified against official Confluent documentation. Schema Registry REST API behavior (Pitfall 4) is verified against official API reference. Molecule/systemd container limitations (Pitfall 9) are well-documented across multiple community sources. RHEL 8/9 differences (Pitfall 8) are verified against Confluent's requirements documentation.
