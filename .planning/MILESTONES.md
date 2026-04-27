# Milestones

## v3.0 LinuxONE / s390x Integration (Shipped: 2026-04-27)

**Phases completed:** 5 phases (16-20), 11 plans

**Key accomplishments:**

- 5 standalone Linux_One/ansible-mtls roles absorbed into single cp_mtls composite role with generalized branding, FQCN compliance, and molecule tests
- community.crypto >= 2.15.0 added to Ansible collection dependencies for cryptographic operations
- LinuxONE scenario directories: cp-rhel-linuxone (full mTLS + inventory + playbooks) and cfk-openshift-linuxone (s390x node affinity, multi-arch images)
- IBM Semeru 17 as default JDK for s390x with PKCS12 keystores and FIPS-aware MAC algorithm flags
- s390x-conditional FIPS validation: IBM JDK providers (IBMJCEPlusFIPS), PKCS12 (not BCFKS), CPACF detection, NTP skew check
- ADR-009: LinuxONE deployment guidance documenting software keys default, on-target assembly, PKCS12-only, Semeru 17
- Four documentation deliverables from .docx conversion: mTLS guide, troubleshooting guide (Usual Suspects + per-component TLS debug), FIPS guide, CEX/PKCS#11 guide
- Optional CEX/PKCS#11 HSM support via cp_mtls_keystore_backend toggle with CCA/EP11 mode detection
- cp_mtls added to molecule CI matrix and ansible-ci.yml path triggers extended for new scenarios
- Linux_One directory deprecated with forwarding README; top-level README updated with LinuxONE as 7th and 8th deployment models

---

## v2.0 Ansible Based Automation (Shipped: 2026-04-10)

**Phases completed:** 15 phases, 42 plans, 77 tasks

**Key accomplishments:**

- Compliance SLA tier (FULL_TRANSITIVE/12 partitions/infinite retention) added to topic module with cluster config externalized to auto.tfvars variables
- Python schema validation script with namespace/compatibility checks, override detection in CI, and 5-step breaking change runbook
- Three ADRs documenting OAuth auth strategy, topic naming convention with regex validation, and DR tier classification with RPO/RTO targets per SLA tier and deployment model
- Three self-contained CC scenario directories (Azure/AWS/GCP) with cloud-native backends, identical governance via shared topic module, and quickstart READMEs
- Reusable CI workflow with per-scenario callers and curl-based post-apply validation checking topics, schemas, RBAC, and DR mirrors via Confluent Cloud REST APIs
- Create-or-reference SA provisioning with effective ID abstraction for unified RBAC bindings across both SA lifecycle modes
- Per-scenario OAuth identity providers (Azure AD, AWS IAM, GCP Cloud Identity) with Vault credential rotation runbook and CSFLE setup guide covering all KMS providers
- CSFLE encryption enforcement for confidential topics with KEK/ruleset, configurable compliance retention (7+ years), and audit log alert rule templates
- CI apply job writes structured compliance audit trail with metadata and validation results; PR template gains compliance checkboxes; regulatory examiner guide maps PR-to-verify chain to FSI control categories
- Unified fsi-dr.sh CLI with pluggable backend dispatch, SLA-tier lag assessment per ADR-008, atomic state file tracking, and 54-test unit suite
- 6-step cmd_failover with dry-run preview, per-step rollback instructions, mirror lag warning, and 33-test dry-run validation suite
- 8-step cmd_failback with two destructive-operation gates, mirror sync wait, and 462-line DR runbook with decision trees and per-step rollback guidance
- Cross-provider metrics mapping with all 6 providers, plus 5 Grafana dashboard JSONs, SLA-tier alert rules, CC Metrics API datasource, JMX exporter stub, and import README
- Dashboard templates for 3 enterprise observability providers with 5-panel structure, SLA-tier alerting parity across all providers, CC Metrics API export configs, and JMX stubs for CFK/CP
- New Relic NerdGraph 5-page dashboard and Instana custom dashboard with 20 NRQL/threshold alert conditions each, CC Metrics API configs, JMX stubs, and .env.example expanded to cover all 6 observability providers
- Reusable Terraform module for CC Flink compute pool and SQL statement provisioning, wired into all 3 CC scenarios with opt-in flag and SR auto-discovery documented
- Four CC Flink SQL templates (tumbling window, stream-table join, filter-and-route, DLQ) with FSI domain examples and usage README
- YAML issue form with deployment model/SLA/Flink dropdowns plus Python C4E pre-check automating 5 validation categories (naming, schema, RBAC, SLA tier, PII) in CI before human review
- Python producer/consumer mirroring Java patterns with Avro/Prometheus/DLQ, plus DLQ handlers retrofitted into all 3 languages (Java, .NET, Python) with identical 3-retry exponential backoff and error categorization
- Shell-based error-path integration tests covering 4 failure scenarios (serialization, RBAC, schema incompat, broker failure) plus Docker Compose extended with Flink 1.20 SQL client behind --profile flink
- CFK-on-OpenShift scenario with 16 Helm/CRD files, governance-parity KafkaTopic CRDs, and CI validation extended for YAML topics
- MirrorMaker 2 backend for fsi-dr.sh with 5 backend functions, 22-test unit suite, and DR runbook extended with MM2 failover/failback procedures and CL vs MM2 comparison table
- Flink Kubernetes Operator 1.14.0 with 3 FlinkDeployment examples porting CC Flink SQL templates to CFK via explicit CREATE TABLE with avro-confluent format, custom Docker image with connector JARs, and JMX metrics export for observability
- CP-RHEL Ansible scaffold with cp-ansible inventory, MDS RBAC group vars, deploy playbook, and 3 CPTopic governance definitions matching CFK label parity
- Private Cloud Terraform scenario with kafka_rest_endpoint provider and CPTopic YAML parser extending C4E precheck to validate all 3 deployment model types
- MRC (Multi-Region Cluster) backend added to fsi-dr.sh with kafka-leader-election.sh for RPO=0 DR, 27 unit tests, and DR runbook MRC procedures
- Standalone Flink 1.20 Ansible role with systemd services, avro-confluent SR connector, FIPS 140-2 validation playbook for CP-RHEL and CFK-OpenShift, and .env.example Section 16 for CP/Private Cloud variables
- Ansible directory scaffolded with cp-ansible 7.7.8 pinned, 4-environment inventory skeletons (dev/staging/prod/dr), and ansible-lint passing with shared+FQCN profile
- SLA tier and naming governance constants mirroring Terraform, plus fsi_governance Jinja2 filter plugin with 3 filters (topic name assembly, SLA lookup, name validation) and 48-test parity suite
- Ansible role for CP topic lifecycle management via Admin REST v3 with SLA-tier governance, idempotent CRUD, check mode, and 40 unit tests
- Ansible role for Avro schema registration on CP Schema Registry with two-pass compatibility safety, SLA-tier-derived compatibility modes via fsi_sla_lookup, and PII metadata properties matching Terraform
- MDS RBAC binding lifecycle role with topic/group/SR bindings, dynamic token refresh, LIST/DIFF/DELETE reconciliation, and 54 unit tests
- 4-play orchestration pipeline (site.yml) with tag-isolated selective execution and cp_connect role for idempotent connector lifecycle via PUT REST API
- Ansible role deploying JMX exporter configs per CP component, auto-generating Prometheus file_sd_configs from inventory, importing Grafana dashboards via file provisioning or API, and deploying SLA-tier-aware alert rules from alerts.yaml
- RED phase
- Ansible role for MM2 DR failover with 6-step sequence, audit-ready check mode, Consul KV flip, connector polling, and SLA-tier-aware state validation
- MM2 DR failback with 7-step reversed replication sequence, GET-before-DELETE config capture, swapped source/target aliases, and operator-facing failback playbook
- CFK operator Ansible role with Helm deployment, platform CR readiness gates (k8s_info+until), check-mode audit, and deploy-cfk.yml orchestration playbook
- cfk_topic Ansible role generating KafkaTopic CRDs from CPTopic YAML with governance parity via fsi_sla_lookup/fsi_validate_topic_name and string-typed CFK configs
- cp_dr_mrc Ansible role with UNCLEAN/PREFERRED leader election, Consul flip, check-mode audit, and operator playbooks
- DR drill playbook orchestrating full failover-validate-failback-validate cycle with compliance report generation for OCC/FDIC quarterly testing

---
