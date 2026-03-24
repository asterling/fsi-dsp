# Compliance Guide

This guide maps the FSI Kafka Platform CI/CD workflow to regulatory control categories. It is the starting point for audit trail navigation. Regulatory examiners can trace any deployed resource from pull request through review, merge, apply, and validation -- with clickable links to GitHub artifacts.

## Audience

- **Regulatory examiners** verifying change management and access controls
- **Internal audit teams** preparing for examinations
- **Platform engineers** understanding compliance controls built into the pipeline

## Audit Trail Flow

The following diagram shows the end-to-end change management process and the control it maps to at each step:

```
PR Created -> CI Validation -> Human Review -> Merge to Main -> Terraform Apply -> Post-Apply Validation
     |              |                |               |                 |                    |
Change request  Automated checks  Segregation    Approval gate   Infrastructure       Verification
                                  of duties                      deployment
```

Each step produces evidence in GitHub that an examiner can review:
- **PR Created**: The pull request page shows the change request, description, and checklist completion.
- **CI Validation**: The GitHub Actions "Lint & Validate" job shows automated checks (format, schema validation, compatibility, override detection).
- **Human Review**: The PR review tab shows at least one approving review from a non-author (segregation of duties).
- **Merge to Main**: The merge event confirms required reviewers and CI checks passed.
- **Terraform Apply**: The GitHub Actions "Terraform Apply" job shows infrastructure deployment.
- **Post-Apply Validation**: The job summary "Compliance Audit Trail" shows validation results for every deployed resource.

## Control Mapping

The table below maps each workflow step to a generic FSI control category. See [Framework Mapping](#framework-mapping) to translate these to your specific regulatory framework.

| Control Category | Workflow Step | Evidence Location | What to Look For |
|-----------------|--------------|-------------------|------------------|
| Change Management | PR created with template | GitHub PR page | Completed checklist, description, linked issue |
| Automated Validation | CI lint + validate + plan | GitHub Actions "Lint & Validate" job | terraform fmt, validate, schema validation all green |
| Schema Governance | Schema compatibility check | GitHub Actions "Lint & Validate" job | SR compatibility check result (continue-on-error noted) |
| Override Documentation | Compatibility override check | GitHub Actions "Lint & Validate" job | Override detection script output |
| Access Control Review | PR template compliance checkboxes | GitHub PR page | RBAC verified checkbox checked, data classification reviewed |
| Segregation of Duties | Human reviewer approval | GitHub PR review tab | At least one approving review from non-author |
| Approval Gate | Branch protection merge | GitHub PR merge event | Required reviewers met, CI checks passed |
| Deployment Automation | Terraform apply | GitHub Actions "Terraform Apply" job | Apply step succeeded, resources created |
| Post-Deploy Verification | Post-apply validation | GitHub Actions job summary "Compliance Audit Trail" | All validation checks PASS |
| Audit Logging | Job summary and annotations | GitHub Actions workflow run page | Timestamp, actor, commit SHA, run ID, validation results |

## How to Navigate an Audit

Follow these steps to trace any infrastructure change from request to deployed resource:

1. **Start at the GitHub repository's Pull Requests tab** (filter by "Merged" to see completed changes).
2. **Find the PR for the change in question** -- search by topic name, date, or author.
3. **Review the PR description and checklist completion** -- the compliance review section documents data classification, RBAC verification, and schema compatibility.
4. **Check the "Files changed" tab** for what Terraform, schema, or configuration files were modified.
5. **Check the "Conversation" tab** for reviewer approval -- at least one approving review from a non-author satisfies segregation of duties.
6. **Click the CI check link** to view the workflow run in GitHub Actions.
7. **In the workflow run, open the "Lint & Validate" job** to review format checks, schema validation, compatibility checks, and override detection.
8. **Open the "Terraform Apply" job** to review the infrastructure deployment.
9. **Review the "Compliance Audit Trail" job summary** (at the bottom of the job page) -- this shows scenario, timestamp, actor, commit SHA, run ID, and validation results.
10. **Verify all validation checks show PASS** -- the summary includes the full output of the post-apply validation script showing topic existence, schema registration, RBAC verification, and DR mirror status.

### Evidence Checklist for Examiners

Use this checklist to confirm all controls are present for a given change:

- [ ] PR created with completed checklist (change management)
- [ ] CI checks passed (automated validation)
- [ ] At least one non-author reviewer approved (segregation of duties)
- [ ] Branch protection rules enforced (approval gate)
- [ ] Terraform apply succeeded (deployment automation)
- [ ] Post-apply validation PASSED (post-deploy verification)
- [ ] Job summary contains timestamp, actor, commit SHA (audit logging)

## Framework Mapping

This guide uses generic FSI control categories. Map to your regulatory framework:

- **OCC/FFIEC (United States)**: Map "Change Management" to IT Handbook - Development & Acquisition. Map "Access Control Review" to IT Handbook - Information Security. Map "Audit Logging" to IT Handbook - Audit.
- **PRA (United Kingdom)**: Map to SS1/21 Operational Resilience. Map "Change Management" to outsourcing and third-party risk management expectations.
- **MAS (Singapore)**: Map to TRM Guidelines. Map "Change Management" to TRM Section 6 (IT Project Management) and Section 7 (System Development).
- **APRA (Australia)**: Map to CPS 234 Information Security. Map "Access Control Review" to CPS 234 Paragraph 27 (access controls).
- **OSFI (Canada)**: Map to Guideline B-13 Technology and Cyber Risk Management. Map "Change Management" to change management domain.

Each institution should maintain a mapping document that cross-references these generic categories to their specific regulatory framework requirements and internal control IDs.

## Glossary

| Term | Definition |
|------|-----------|
| **PR (Pull Request)** | A request to merge code changes into the main branch. In this platform, every infrastructure change goes through a PR. |
| **CI/CD** | Continuous Integration / Continuous Deployment. Automated pipelines that validate and deploy changes. |
| **Terraform** | Infrastructure as Code tool that declaratively manages Confluent Cloud resources (topics, schemas, RBAC). |
| **RBAC** | Role-Based Access Control. Controls which service accounts can produce to or consume from Kafka topics. |
| **CSFLE** | Client-Side Field-Level Encryption. Encrypts individual fields in Kafka messages at the producer, decrypted only by authorized consumers. |
| **SLA Tier** | Service Level Agreement classification (critical, standard, best-effort, compliance) that determines topic configuration defaults. |
| **Data Classification** | Categorization of data sensitivity: confidential (PII, financial data), internal (business data), or public. |
| **Schema Registry (SR)** | Service that stores and validates Avro schemas, enforcing compatibility rules to prevent breaking changes. |
| **Avro** | Data serialization format used for Kafka message schemas. Supports schema evolution with compatibility modes. |
| **Compatibility Mode** | Schema Registry setting that controls what schema changes are allowed (FULL_TRANSITIVE, BACKWARD_TRANSITIVE, BACKWARD). |
| **DR (Disaster Recovery)** | Infrastructure and processes for recovering from regional outages. Uses Cluster Linking to replicate topics. |
| **Cluster Linking** | Confluent Cloud feature that replicates topics between clusters in different regions for disaster recovery. |
| **PII** | Personally Identifiable Information. Data that can identify an individual (name, email, SSN, account number). |
| **Service Account (SA)** | Identity used by applications to authenticate to Kafka and Schema Registry. Each SA has specific RBAC bindings. |
| **Job Summary** | GitHub Actions feature that displays structured output at the bottom of a workflow run page. Used for the Compliance Audit Trail. |
| **Annotation** | GitHub Actions feature that surfaces notices and warnings at the workflow run level. Used for audit trail visibility. |

---

*This document is maintained alongside the CI/CD pipeline. When workflow steps change, update the control mapping table accordingly.*
